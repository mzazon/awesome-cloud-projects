# Output Values for EC2 Instance Connect Infrastructure
# This file defines the outputs that will be displayed after deployment
# and can be used by other Terraform configurations or automation scripts

# Basic Infrastructure Information
output "aws_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "vpc_id" {
  description = "VPC ID used for the deployment"
  value       = data.aws_vpc.selected.id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name used for resource tagging"
  value       = var.environment
}

output "resource_name_prefix" {
  description = "Name prefix used for all resources"
  value       = local.name_prefix
}

# Security Group Information
output "security_group_id" {
  description = "ID of the security group allowing SSH access"
  value       = aws_security_group.ec2_connect.id
}

output "security_group_name" {
  description = "Name of the security group allowing SSH access"
  value       = aws_security_group.ec2_connect.name
}

# Public Instance Information
output "public_instance_id" {
  description = "Instance ID of the public EC2 instance"
  value       = aws_instance.public.id
}

output "public_instance_public_ip" {
  description = "Public IP address of the public EC2 instance"
  value       = aws_instance.public.public_ip
}

output "public_instance_private_ip" {
  description = "Private IP address of the public EC2 instance"
  value       = aws_instance.public.private_ip
}

output "public_instance_subnet_id" {
  description = "Subnet ID where the public instance is deployed"
  value       = aws_instance.public.subnet_id
}

output "public_instance_ami_id" {
  description = "AMI ID used for the public instance"
  value       = aws_instance.public.ami
}

# Private Instance Information (conditional outputs)
output "private_instance_id" {
  description = "Instance ID of the private EC2 instance (if created)"
  value       = var.create_private_instance ? aws_instance.private[0].id : null
}

output "private_instance_private_ip" {
  description = "Private IP address of the private EC2 instance (if created)"
  value       = var.create_private_instance ? aws_instance.private[0].private_ip : null
}

output "private_subnet_id" {
  description = "ID of the private subnet (if created)"
  value       = var.create_private_instance ? aws_subnet.private[0].id : null
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet (if created)"
  value       = var.create_private_instance ? aws_subnet.private[0].cidr_block : null
}

# Instance Connect Endpoint Information
output "instance_connect_endpoint_id" {
  description = "ID of the EC2 Instance Connect Endpoint (if created)"
  value       = var.create_private_instance ? aws_ec2_instance_connect_endpoint.private[0].id : null
}

output "instance_connect_endpoint_dns_name" {
  description = "DNS name of the EC2 Instance Connect Endpoint (if created)"
  value       = var.create_private_instance ? aws_ec2_instance_connect_endpoint.private[0].dns_name : null
}

output "instance_connect_endpoint_network_interface_ids" {
  description = "Network interface IDs of the Instance Connect Endpoint (if created)"
  value       = var.create_private_instance ? aws_ec2_instance_connect_endpoint.private[0].network_interface_ids : null
}

# IAM Policy Information
output "iam_policy_arn" {
  description = "ARN of the basic EC2 Instance Connect IAM policy"
  value       = aws_iam_policy.ec2_instance_connect.arn
}

output "iam_policy_name" {
  description = "Name of the basic EC2 Instance Connect IAM policy"
  value       = aws_iam_policy.ec2_instance_connect.name
}

output "iam_restrictive_policy_arn" {
  description = "ARN of the restrictive EC2 Instance Connect IAM policy (if created)"
  value       = var.create_restrictive_policy ? aws_iam_policy.ec2_instance_connect_restrictive[0].arn : null
}

output "iam_restrictive_policy_name" {
  description = "Name of the restrictive EC2 Instance Connect IAM policy (if created)"
  value       = var.create_restrictive_policy ? aws_iam_policy.ec2_instance_connect_restrictive[0].name : null
}

# IAM User Information (conditional outputs)
output "iam_user_name" {
  description = "Name of the IAM user with Instance Connect permissions (if created)"
  value       = var.iam_user_name != "" ? aws_iam_user.ec2_connect_user[0].name : null
}

output "iam_user_arn" {
  description = "ARN of the IAM user with Instance Connect permissions (if created)"
  value       = var.iam_user_name != "" ? aws_iam_user.ec2_connect_user[0].arn : null
}

output "iam_access_key_id" {
  description = "Access key ID for the IAM user (if created)"
  value       = var.iam_user_name != "" ? aws_iam_access_key.ec2_connect_user[0].id : null
  sensitive   = false
}

output "iam_secret_access_key" {
  description = "Secret access key for the IAM user (if created)"
  value       = var.iam_user_name != "" ? aws_iam_access_key.ec2_connect_user[0].secret : null
  sensitive   = true
}

# CloudTrail Information (conditional outputs)
output "cloudtrail_name" {
  description = "Name of the CloudTrail (if created)"
  value       = var.create_cloudtrail ? aws_cloudtrail.ec2_connect_audit[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail (if created)"
  value       = var.create_cloudtrail ? aws_cloudtrail.ec2_connect_audit[0].arn : null
}

output "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs (if created)"
  value       = var.create_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
}

output "cloudtrail_s3_bucket_arn" {
  description = "S3 bucket ARN for CloudTrail logs (if created)"
  value       = var.create_cloudtrail ? aws_s3_bucket.cloudtrail[0].arn : null
}

# Connection Information and Commands
output "public_instance_ssh_command" {
  description = "SSH command to connect to the public instance using EC2 Instance Connect"
  value = "aws ec2-instance-connect ssh --instance-id ${aws_instance.public.id} --os-user ec2-user"
}

output "private_instance_ssh_command" {
  description = "SSH command to connect to the private instance using Instance Connect Endpoint (if created)"
  value = var.create_private_instance ? "aws ec2-instance-connect ssh --instance-id ${aws_instance.private[0].id} --os-user ec2-user --connection-type eice" : null
}

output "manual_ssh_public_key_command" {
  description = "Command to manually send SSH public key to the public instance"
  value = "aws ec2-instance-connect send-ssh-public-key --instance-id ${aws_instance.public.id} --instance-os-user ec2-user --ssh-public-key file://path/to/your/public-key.pub"
}

# Verification Commands
output "verification_commands" {
  description = "Commands to verify the Instance Connect setup"
  value = {
    check_instance_status        = "aws ec2 describe-instances --instance-ids ${aws_instance.public.id} --query 'Reservations[0].Instances[0].State.Name'"
    test_instance_connect       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.public.id} --os-user ec2-user --command 'echo Instance Connect working'"
    check_service_status        = "aws ec2-instance-connect ssh --instance-id ${aws_instance.public.id} --os-user ec2-user --command 'sudo systemctl status ec2-instance-connect'"
    view_cloudtrail_events      = var.create_cloudtrail ? "aws logs filter-log-events --log-group-name /aws/cloudtrail/${aws_cloudtrail.ec2_connect_audit[0].name} --filter-pattern '{ $.eventName = \"SendSSHPublicKey\" }'" : null
  }
}

# Additional Configuration Information
output "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  value       = var.allowed_ssh_cidrs
}

output "instance_type" {
  description = "EC2 instance type used for instances"
  value       = var.instance_type
}

output "ami_name" {
  description = "Name of the AMI used for instances"
  value       = data.aws_ami.amazon_linux.name
}

output "ami_description" {
  description = "Description of the AMI used for instances"
  value       = data.aws_ami.amazon_linux.description
}

# Tags Applied to Resources
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Summary Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    public_instances                = 1
    private_instances              = var.create_private_instance ? 1 : 0
    instance_connect_endpoints     = var.create_private_instance ? 1 : 0
    iam_policies                   = var.create_restrictive_policy ? 2 : 1
    iam_users                      = var.iam_user_name != "" ? 1 : 0
    cloudtrail_enabled            = var.create_cloudtrail
    private_subnet_created        = var.create_private_instance
    total_estimated_monthly_cost  = "< $20 USD (for t3.micro instances)"
  }
}