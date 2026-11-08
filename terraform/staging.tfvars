# Staging values. Use with:  terraform plan -var-file=staging.tfvars
# Give staging its OWN state key (for example voting-app/staging.tfstate),
# otherwise it would overwrite the dev stack in the shared state.
key_name             = "devop-aws-ssh"
ssh_private_key_path = "~/.ssh/devop-aws-ssh.pem"
create_key_pair      = false
ssh_user             = "ubuntu"
ssh_allowed_cidrs    = []

aws_region   = "eu-north-1"
project_name = "voting-app"
environment  = "staging"

vpc_cidr             = "10.1.0.0/16"
availability_zones   = ["eu-north-1a", "eu-north-1b"]
single_nat_gateway   = true
app_allowed_cidrs    = ["0.0.0.0/0"]
result_listener_port = 8081

# How the app is deployed: "compose", "k3s" or "both"
#   compose = one Docker container per server
#   k3s     = one k3s cluster over the same servers (k8s-specifications/, pods pinned by tier)
#   both    = the two side by side (two separate copies of the app, each with its own votes)
deploy_method       = "k3s"
k3s_vote_nodeport   = 31000
k3s_result_nodeport = 31001

run_ansible = true

ami_name_filter  = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
instance_type    = "t3.small"
root_volume_size = 20

# worker-a also runs the k3s control plane, so give it more memory (m7i-flex.large: 8 GB, free-tier eligible; t3.medium is not)
instance_type_overrides = { "worker-a" = "m7i-flex.large" }
