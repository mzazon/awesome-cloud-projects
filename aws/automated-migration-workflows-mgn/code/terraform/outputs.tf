# VPC and Network Outputs
output "vpc_id" {
  description = "ID of the migration VPC"
  value       = aws_vpc.migration_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the migration VPC"
  value       = aws_vpc.migration_vpc.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private_subnet.id
}

output "security_group_id" {
  description = "ID of the migration security group"
  value       = aws_security_group.migration_sg.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway"
  value       = aws_internet_gateway.migration_igw.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = aws_nat_gateway.migration_nat.id
}

# IAM Role Outputs
output "mgn_service_role_arn" {
  description = "ARN of the MGN service role"
  value       = aws_iam_role.mgn_service_role.arn
}

output "ssm_automation_role_arn" {
  description = "ARN of the SSM automation role"
  value       = aws_iam_role.ssm_automation_role.arn
}

# CloudWatch Outputs
output "migration_log_group_name" {
  description = "Name of the migration CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.migration_logs[0].name : null
}

output "orchestrator_log_group_name" {
  description = "Name of the orchestrator CloudWatch log group"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.orchestrator_logs[0].name : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.migration_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.migration_dashboard.dashboard_name}"
}

# Systems Manager Outputs
output "ssm_document_name" {
  description = "Name of the post-migration automation SSM document"
  value       = aws_ssm_document.post_migration_automation.name
}

output "ssm_document_arn" {
  description = "ARN of the post-migration automation SSM document"
  value       = aws_ssm_document.post_migration_automation.arn
}

# VPC Endpoint Outputs
output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "ec2_vpc_endpoint_id" {
  description = "ID of the EC2 VPC endpoint"
  value       = aws_vpc_endpoint.ec2.id
}

output "ssm_vpc_endpoint_id" {
  description = "ID of the SSM VPC endpoint"
  value       = aws_vpc_endpoint.ssm.id
}

# Migration Hub Outputs
output "migration_hub_home_region" {
  description = "Migration Hub home region"
  value       = aws_migrationhub_config.migration_hub_config.home_region
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

# Resource Suffix
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# Network Configuration for MGN
output "mgn_replication_subnet_id" {
  description = "Subnet ID for MGN replication servers (use private subnet)"
  value       = aws_subnet.private_subnet.id
}

output "mgn_target_subnet_id" {
  description = "Subnet ID for MGN target instances (use private subnet)"
  value       = aws_subnet.private_subnet.id
}

# Security Configuration
output "allowed_source_cidr" {
  description = "CIDR block allowed for source server access"
  value       = var.allowed_source_cidr
}

# Project Information
output "project_name" {
  description = "Name of the migration project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Instructions for Next Steps
output "next_steps" {
  description = "Next steps to complete the migration setup"
  value = [
    "1. Initialize MGN service: aws mgn initialize-service --region ${var.aws_region}",
    "2. Create MGN launch template using the provided subnet and security group",
    "3. Update MGN replication configuration with subnet: ${aws_subnet.private_subnet.id}",
    "4. Create Migration Hub Orchestrator workflow using the template",
    "5. Deploy replication agents on source servers",
    "6. Monitor progress via CloudWatch dashboard: ${aws_cloudwatch_dashboard.migration_dashboard.dashboard_name}"
  ]
}

# Cost Estimation Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    vpc_resources = "~$5-10 (NAT Gateway, EIPs)"
    mgn_replication = "~$50-100 per source server (depends on instance type and data volume)"
    cloudwatch = "~$10-20 (logs, metrics, dashboard)"
    vpc_endpoints = "~$22-30 (3 interface endpoints)"
    total_baseline = "~$87-160 (excluding per-server MGN costs)"
    note = "Actual costs depend on data volume, number of source servers, and migration duration"
  }
}