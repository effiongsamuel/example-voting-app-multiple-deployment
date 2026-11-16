# ---------------------------------------------------------------------------
# Five-tier deployment of the example voting app, one server per job:
#
#   internet -> ALB -> vote   (public subnet)  -> redis    (private subnet)
#                   -> result (public subnet)  -> postgres (private subnet)
#                      worker (private subnet) -> redis, postgres
#
# vote, result and worker run in BOTH availability zones (they keep no data).
# redis and postgres run ONCE, in the first AZ: the app has no replication, so
# a second copy would be a second, separate set of votes.
#
# The app is deployed with Docker Compose (one container per server), with k3s
# (one Kubernetes cluster over the same servers, pods pinned to their tier), or
# both side by side: see var.deploy_method.
#
# Nobody needs a bastion host: every server, public or private, is reached with
# SSH through an EC2 Instance Connect Endpoint (see outputs.tf: ssh_commands).
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  ssh_key_name = var.create_key_pair ? aws_key_pair.ssh[0].key_name : var.key_name

  # The two availability zones used: "a" and "b".
  azs       = { a = var.availability_zones[0], b = var.availability_zones[1] }
  az_number = { a = 0, b = 1 }

  # One subnet per tier per AZ, as in the diagram.
  tiers = {
    vote     = { public = true, index = 1 }
    result   = { public = true, index = 2 }
    worker   = { public = false, index = 3 }
    redis    = { public = false, index = 4 }
    postgres = { public = false, index = 5 }
  }

  # Keys look like "vote-a", "redis-b". CIDRs: AZ a = 10.0.11-15.0, AZ b = 10.0.21-25.0.
  subnets = merge([
    for tier, t in local.tiers : {
      for az, az_name in local.azs : "${tier}-${az}" => {
        tier    = tier
        az      = az
        az_name = az_name
        public  = t.public
        cidr    = cidrsubnet(var.vpc_cidr, 8, (local.az_number[az] + 1) * 10 + t.index)
      }
    }
  ]...)

  # Servers: vote, result and worker in both AZs; redis and postgres only in AZ a.
  servers = merge(
    { for k, s in local.subnets : k => s if contains(["vote", "result", "worker"], s.tier) },
    { for k, s in local.subnets : k => s if contains(["redis", "postgres"], s.tier) && s.az == "a" },
  )

  # One NAT gateway (AZ a) or one per AZ.
  nat_azs = { for az, az_name in local.azs : az => az_name if !var.single_nat_gateway || az == "a" }

  tier_sg = {
    vote     = aws_security_group.vote.id
    result   = aws_security_group.result.id
    worker   = aws_security_group.worker.id
    redis    = aws_security_group.redis.id
    postgres = aws_security_group.postgres.id
  }

  use_compose = contains(["compose", "both"], var.deploy_method)
  use_k3s     = contains(["k3s", "both"], var.deploy_method)

  # The k3s control plane runs on this server; every other server joins it as an agent.
  k3s_server_key = "worker-a"

  # Load balancer routes. Docker Compose is served on :80 and :<result_listener_port>,
  # k3s (NodePorts) on :<k3s_vote_nodeport> and :<k3s_result_nodeport>.
  lb_routes_all = {
    "vote"       = { method = "compose", tier = "vote", listener = 80, target = 80, sticky = false }
    "result"     = { method = "compose", tier = "result", listener = var.result_listener_port, target = 80, sticky = true }
    "k3s-vote"   = { method = "k3s", tier = "vote", listener = var.k3s_vote_nodeport, target = var.k3s_vote_nodeport, sticky = false }
    "k3s-result" = { method = "k3s", tier = "result", listener = var.k3s_result_nodeport, target = var.k3s_result_nodeport, sticky = true }
  }
  lb_routes = { for k, r in local.lb_routes_all : k => r if r.method == "compose" ? local.use_compose : local.use_k3s }

  # Every vote/result server is a target of the routes of its tier.
  lb_attachments = merge([
    for rk, r in local.lb_routes : {
      for sk, s in local.servers : "${rk}/${sk}" => { route = rk, server = sk, target = r.target }
      if s.tier == r.tier
    }
  ]...)
}

# ---------------------------------------------------------------------------
# Network: VPC, 10 subnets, internet gateway, NAT gateway(s), route tables
# ---------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_subnet" "tier" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az_name
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = each.value.public

  tags = {
    Name = "${local.name_prefix}-${each.key}-subnet"
    Tier = each.value.tier
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = { for k, s in local.subnets : k => s if s.public }

  subnet_id      = aws_subnet.tier[each.key].id
  route_table_id = aws_route_table.public.id
}

# NAT gateways live in the public "vote" subnet of their AZ.
resource "aws_eip" "nat" {
  for_each = local.nat_azs

  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "${local.name_prefix}-nat-eip-${each.key}" }
}

resource "aws_nat_gateway" "nat" {
  for_each = local.nat_azs

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.tier["vote-${each.key}"].id
  depends_on    = [aws_internet_gateway.igw]

  tags = { Name = "${local.name_prefix}-nat-${each.key}" }
}

resource "aws_route_table" "private" {
  for_each = local.azs

  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-private-rt-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each = local.azs

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[var.single_nat_gateway ? "a" : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = { for k, s in local.subnets : k => s if !s.public }

  subnet_id      = aws_subnet.tier[each.key].id
  route_table_id = aws_route_table.private[each.value.az].id
}

# ---------------------------------------------------------------------------
# Security groups (one per tier, chained exactly like the traffic flow)
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Load balancer: vote and result pages from the internet"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = local.lb_routes
    content {
      description = "Listener: ${ingress.key}"
      protocol    = "tcp"
      from_port   = ingress.value.listener
      to_port     = ingress.value.listener
      cidr_blocks = var.app_allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# Attached to the Instance Connect Endpoint: it may only open SSH inside the VPC.
resource "aws_security_group" "eice" {
  name        = "${local.name_prefix}-eice-sg"
  description = "EC2 Instance Connect Endpoint: SSH to the servers"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "SSH to the servers"
    protocol    = "tcp"
    from_port   = 22
    to_port     = 22
    cidr_blocks = [var.vpc_cidr]
  }

  tags = { Name = "${local.name_prefix}-eice-sg" }
}

resource "aws_security_group" "vote" {
  name        = "${local.name_prefix}-vote-sg"
  description = "Vote servers: HTTP from the load balancer"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = toset([for r in local.lb_routes : tostring(r.target) if r.tier == "vote"])
    content {
      description     = "Web traffic from the load balancer"
      protocol        = "tcp"
      from_port       = tonumber(ingress.value)
      to_port         = tonumber(ingress.value)
      security_groups = [aws_security_group.alb.id]
    }
  }

  ingress {
    description     = "SSH through the Instance Connect Endpoint"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.eice.id]
  }

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "SSH straight from allowed CIDRs (public servers only)"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      cidr_blocks = var.ssh_allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-vote-sg" }
}

resource "aws_security_group" "result" {
  name        = "${local.name_prefix}-result-sg"
  description = "Result servers: HTTP from the load balancer"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = toset([for r in local.lb_routes : tostring(r.target) if r.tier == "result"])
    content {
      description     = "Web traffic from the load balancer"
      protocol        = "tcp"
      from_port       = tonumber(ingress.value)
      to_port         = tonumber(ingress.value)
      security_groups = [aws_security_group.alb.id]
    }
  }

  ingress {
    description     = "SSH through the Instance Connect Endpoint"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.eice.id]
  }

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "SSH straight from allowed CIDRs (public servers only)"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      cidr_blocks = var.ssh_allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-result-sg" }
}

# The worker accepts no connections at all except SSH.
resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-worker-sg"
  description = "Worker servers: SSH only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH through the Instance Connect Endpoint"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.eice.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-worker-sg" }
}

resource "aws_security_group" "redis" {
  name        = "${local.name_prefix}-redis-sg"
  description = "Redis: 6379 from vote and worker"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Redis from vote and worker"
    protocol        = "tcp"
    from_port       = 6379
    to_port         = 6379
    security_groups = [aws_security_group.vote.id, aws_security_group.worker.id]
  }

  ingress {
    description     = "SSH through the Instance Connect Endpoint"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.eice.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-redis-sg" }
}

resource "aws_security_group" "postgres" {
  name        = "${local.name_prefix}-postgres-sg"
  description = "Postgres: 5432 from worker and result"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from worker and result"
    protocol        = "tcp"
    from_port       = 5432
    to_port         = 5432
    security_groups = [aws_security_group.worker.id, aws_security_group.result.id]
  }

  ingress {
    description     = "SSH through the Instance Connect Endpoint"
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    security_groups = [aws_security_group.eice.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-postgres-sg" }
}

# k3s: lets the API (6443), flannel VXLAN (8472/udp), kubelet (10250) and pod
# traffic flow between the servers. Attached to every server when k3s is used.
resource "aws_security_group" "k8s_nodes" {
  count       = local.use_k3s ? 1 : 0
  name        = "${local.name_prefix}-k8s-nodes-sg"
  description = "k3s node-to-node traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "All traffic between k3s nodes"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-k8s-nodes-sg" }
}

# ---------------------------------------------------------------------------
# EC2 Instance Connect Endpoint: SSH into ANY server, including the private
# ones, with no bastion host and no public IP. Free of charge.
# ---------------------------------------------------------------------------
resource "aws_ec2_instance_connect_endpoint" "ssh" {
  subnet_id          = aws_subnet.tier["worker-a"].id
  security_group_ids = [aws_security_group.eice.id]
  preserve_client_ip = false # servers see the endpoint's address, which the security groups allow

  tags = { Name = "${local.name_prefix}-eice" }
}

# ---------------------------------------------------------------------------
# SSH key pair (existing in AWS by default, or uploaded when create_key_pair)
# ---------------------------------------------------------------------------
resource "aws_key_pair" "ssh" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = var.key_name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# ---------------------------------------------------------------------------
# AMI + the eight servers
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "server" {
  for_each = local.servers

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = lookup(var.instance_type_overrides, each.key, var.instance_type)
  subnet_id                   = aws_subnet.tier[each.key].id
  vpc_security_group_ids      = concat([local.tier_sg[each.value.tier]], aws_security_group.k8s_nodes[*].id)
  key_name                    = local.ssh_key_name
  associate_public_ip_address = each.value.public

  # redis and postgres get a fixed address, so the other tiers can point at it.
  private_ip = contains(["redis", "postgres"], each.value.tier) ? cidrhost(each.value.cidr, 10) : null

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }

  # Servers need their route to the internet (IGW or NAT) before first boot.
  depends_on = [
    aws_route_table_association.public,
    aws_route_table_association.private,
    aws_route.private_nat,
  ]

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Tier = each.value.tier
  }
}

# ---------------------------------------------------------------------------
# Application load balancer. One listener and target group per route (lb_routes):
#   Docker Compose: :80 -> vote servers, :<result_listener_port> -> result servers
#   k3s (NodePort): :<k3s_vote_nodeport> -> vote servers, :<k3s_result_nodeport> -> result servers
# ---------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.tier["vote-a"].id, aws_subnet.tier["vote-b"].id]

  depends_on = [aws_internet_gateway.igw]

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "route" {
  for_each = local.lb_routes

  name     = "${local.name_prefix}-${each.key}-tg"
  port     = each.value.target
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # The live results page uses socket.io, which needs the same server every time.
  dynamic "stickiness" {
    for_each = each.value.sticky ? [1] : []
    content {
      type            = "lb_cookie"
      enabled         = true
      cookie_duration = 3600
    }
  }

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name_prefix}-${each.key}-tg" }
}

resource "aws_lb_listener" "route" {
  for_each = local.lb_routes

  load_balancer_arn = aws_lb.app.arn
  port              = each.value.listener
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.route[each.key].arn
  }
}

resource "aws_lb_target_group_attachment" "route" {
  for_each = local.lb_attachments

  target_group_arn = aws_lb_target_group.route[each.value.route].arn
  target_id        = aws_instance.server[each.value.server].id
  port             = each.value.target
}
