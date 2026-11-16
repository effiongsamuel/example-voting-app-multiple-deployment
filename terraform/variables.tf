# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Short project name (10 characters at most), used as a prefix for resource names."
  type        = string
  default     = "voting-app"

  validation {
    condition     = length(var.project_name) <= 10
    error_message = "project_name must be 10 characters or fewer (load balancer target group names are limited to 32)."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "Two availability zones. vote, result and worker run in both; redis and postgres in the first."
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones (the load balancer needs two)."
  }
}

variable "single_nat_gateway" {
  description = "true: one NAT gateway for the whole VPC (cheaper). false: one per AZ (as in the diagram)."
  type        = bool
  default     = true
}

variable "app_allowed_cidrs" {
  description = "CIDRs allowed to open the vote and result pages through the load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_allowed_cidrs" {
  description = "Optional: CIDRs allowed to SSH straight to the PUBLIC servers (vote, result). Private servers are only reachable through the Instance Connect Endpoint. Leave empty to use only the endpoint."
  type        = list(string)
  default     = []
}

variable "result_listener_port" {
  description = "Load balancer port for the result page (the vote page is on 80)."
  type        = number
  default     = 8081

  validation {
    condition     = var.result_listener_port != 80 && var.result_listener_port >= 1 && var.result_listener_port <= 65535
    error_message = "result_listener_port must be 1-65535 and different from 80."
  }
}

# ---------------------------------------------------------------------------
# How the app is deployed
# ---------------------------------------------------------------------------
variable "deploy_method" {
  description = "compose = one Docker Compose container per server, k3s = a k3s cluster over the same servers (manifests from the Helm chart in helm/voting-app/), both = both side by side."
  type        = string
  default     = "both"

  validation {
    condition     = contains(["compose", "k3s", "both"], var.deploy_method)
    error_message = "deploy_method must be compose, k3s or both."
  }
}

variable "k3s_vote_nodeport" {
  description = "k3s: NodePort of the vote service. Passed to the chart as vote.service.nodePort. Also the load balancer port."
  type        = number
  default     = 31000
}

variable "k3s_result_nodeport" {
  description = "k3s: NodePort of the result service. Passed to the chart as result.service.nodePort. Also the load balancer port."
  type        = number
  default     = 31001
}

# ---------------------------------------------------------------------------
# Application images, built by .github/workflows/ci-cd.yml and published to GHCR
# ---------------------------------------------------------------------------
variable "github_owner" {
  description = "GitHub user or organisation whose GHCR packages hold the images (ghcr.io/<github_owner>/example-voting-app-5tier-*)."
  type        = string

  validation {
    condition     = var.github_owner != "" && var.github_owner != "CHANGE_ME"
    error_message = "Set github_owner in terraform.tfvars to your GitHub user or organisation name."
  }
}

variable "image_tag" {
  description = "Image tag for the first deployment (CI later deploys the commit SHA)."
  type        = string
  default     = "latest"
}

variable "vote_image" {
  description = "Docker Compose: full vote image reference. Empty = ghcr.io/<github_owner>/example-voting-app-5tier-vote:<image_tag>."
  type        = string
  default     = ""
}

variable "result_image" {
  description = "Docker Compose: full result image reference. Empty = the GHCR image built by CI."
  type        = string
  default     = ""
}

variable "worker_image" {
  description = "Docker Compose: full worker image reference. Empty = the GHCR image built by CI."
  type        = string
  default     = ""
}

variable "grafana_nodeport" {
  description = "k3s: NodePort of Grafana (monitoring in the Helm chart). Also the load balancer port."
  type        = number
  default     = 31002
}

variable "run_ansible" {
  description = "Run the Ansible playbook automatically once the servers exist."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------
variable "ami_name_filter" {
  description = "Name filter for the Canonical Ubuntu AMI (24.04 LTS)."
  type        = string
  default     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
}

variable "instance_type" {
  description = "Instance type for all eight servers (2 vCPU / 2 GB RAM or more)."
  type        = string
  default     = "t3.small"
}

variable "instance_type_overrides" {
  description = "Bigger or smaller size for single servers, e.g. { \"worker-a\" = \"m7i-flex.large\" }. worker-a runs the k3s control plane, which needs about 4 GB. On a free-tier account only free-tier eligible types are allowed."
  type        = map(string)
  default     = {}
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB) per server."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# SSH key
# ---------------------------------------------------------------------------
variable "key_name" {
  description = "EC2 key pair name (without .pem): an existing one, or the name to create when create_key_pair = true."
  type        = string
  default     = "devop-aws-ssh"
}

variable "create_key_pair" {
  description = "false: key_name already exists in AWS. true: create it from ssh_public_key_path."
  type        = bool
  default     = false
}

variable "ssh_public_key_path" {
  description = "Public key to upload when create_key_pair = true."
  type        = string
  default     = "~/.ssh/devop-aws-ssh.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the .pem on the machine running terraform/ansible (chmod 400)."
  type        = string
  default     = "~/.ssh/devop-aws-ssh.pem"
}

variable "ssh_user" {
  description = "Login user of the Ubuntu AMI."
  type        = string
  default     = "ubuntu"
}
