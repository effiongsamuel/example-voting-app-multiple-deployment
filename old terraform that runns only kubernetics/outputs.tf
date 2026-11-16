output "vote_url" {
  description = "Docker Compose: vote page (through the load balancer). null when deploy_method = k3s."
  value       = local.use_compose ? "http://${aws_lb.app.dns_name}" : null
}

output "result_url" {
  description = "Docker Compose: result page (through the load balancer). null when deploy_method = k3s."
  value       = local.use_compose ? "http://${aws_lb.app.dns_name}:${var.result_listener_port}" : null
}

output "k3s_vote_url" {
  description = "k3s: vote page (NodePort through the load balancer). null when deploy_method = compose."
  value       = local.use_k3s ? "http://${aws_lb.app.dns_name}:${var.k3s_vote_nodeport}" : null
}

output "k3s_result_url" {
  description = "k3s: result page (NodePort through the load balancer). null when deploy_method = compose."
  value       = local.use_k3s ? "http://${aws_lb.app.dns_name}:${var.k3s_result_nodeport}" : null
}

output "k3s_kubectl" {
  description = "Run kubectl on the control plane (SSH first, using ssh_commands[\"worker-a\"])."
  value       = local.use_k3s ? "sudo k3s kubectl get nodes,pods -o wide" : null
}

output "servers" {
  description = "Every server with its tier, zone and addresses."
  value = {
    for k, i in aws_instance.server : k => {
      tier        = local.servers[k].tier
      az          = local.servers[k].az_name
      instance_id = i.id
      private_ip  = i.private_ip
      public_ip   = i.public_ip
    }
  }
}

output "ssh_commands" {
  description = "SSH into any server, private ones included, straight from your machine (needs AWS CLI v2 and your AWS credentials). No bastion."
  value = {
    for k, i in aws_instance.server : k => "ssh -i ${var.ssh_private_key_path} -o ProxyCommand='aws ec2-instance-connect open-tunnel --instance-id %h --region ${var.aws_region}' ${var.ssh_user}@${i.id}"
  }
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Subnet IDs, keyed by tier and AZ."
  value       = { for k, s in aws_subnet.tier : k => s.id }
}

output "nat_gateway_public_ips" {
  description = "Public IP(s) of the NAT gateway(s)."
  value       = [for e in aws_eip.nat : e.public_ip]
}

output "security_group_ids" {
  description = "Security group IDs by tier."
  value = {
    alb      = aws_security_group.alb.id
    eice     = aws_security_group.eice.id
    vote     = aws_security_group.vote.id
    result   = aws_security_group.result.id
    worker   = aws_security_group.worker.id
    redis    = aws_security_group.redis.id
    postgres = aws_security_group.postgres.id
  }
}

output "instance_connect_endpoint_id" {
  description = "EC2 Instance Connect Endpoint used for SSH."
  value       = aws_ec2_instance_connect_endpoint.ssh.id
}

output "ami_name" {
  description = "Name of the resolved AMI."
  value       = data.aws_ami.ubuntu.name
}
