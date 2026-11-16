# Default / dev values. Loaded automatically by `terraform plan|apply`.
# =============================================================================
#  SSH KEY - EDIT HERE
# =============================================================================
key_name             = "devop-aws-ssh"             # key pair name in AWS (no .pem)
ssh_private_key_path = "~/.ssh/devop-aws-ssh.pem"  # written by the GitHub workflow from the EC2_SSH_PRIVATE_KEY secret
create_key_pair      = false                       # false = key pair already exists in AWS (eu-north-1)
# ssh_public_key_path = "~/.ssh/devop-aws-ssh.pub" # only used when create_key_pair = true
ssh_user             = "ubuntu"
# Optional direct SSH to the PUBLIC servers only. Private servers use the
# Instance Connect Endpoint (see the ssh_commands output), so this can stay empty.
ssh_allowed_cidrs    = []
# =============================================================================

aws_region   = "eu-north-1"
project_name = "voting-app"
environment  = "dev"

# Network
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["eu-north-1a", "eu-north-1b"]
single_nat_gateway   = true          # false = one NAT gateway per AZ (as drawn, but about double the NAT cost)
app_allowed_cidrs    = ["0.0.0.0/0"]
result_listener_port = 8081

# How the app is deployed: "compose", "k3s" or "both"
#   compose = one Docker container per server
#   k3s     = one k3s cluster over the same servers (k8s-specifications/, pods pinned by tier)
#   both    = the two side by side (two separate copies of the app, each with its own votes)
deploy_method       = "both"
k3s_vote_nodeport   = 31000
k3s_result_nodeport = 31001

# Images (swap for your own registry images if you build them)
vote_image   = "dockersamples/examplevotingapp_vote"
result_image = "dockersamples/examplevotingapp_result"
worker_image = "dockersamples/examplevotingapp_worker"

# Automatic deployment
run_ansible = true

# Compute (8 servers)
ami_name_filter  = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
instance_type    = "t3.small"
root_volume_size = 20

# worker-a also runs the k3s control plane, so give it more memory (m7i-flex.large: 8 GB, free-tier eligible; t3.medium is not)
instance_type_overrides = { "worker-a" = "m7i-flex.large" }
