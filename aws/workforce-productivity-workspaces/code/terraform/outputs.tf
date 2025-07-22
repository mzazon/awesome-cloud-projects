# =============================================================================
# Outputs for AWS WorkSpaces Infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# VPC and Networking Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC created for WorkSpaces"
  value       = aws_vpc.workspaces_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.workspaces_vpc.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets where WorkSpaces are deployed"
  value       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

output "private_subnet_1_id" {
  description = "ID of the first private subnet"
  value       = aws_subnet.private_subnet_1.id
}

output "private_subnet_2_id" {
  description = "ID of the second private subnet"
  value       = aws_subnet.private_subnet_2.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.workspaces_igw.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.workspaces_nat.id
}

output "nat_gateway_eip" {
  description = "Elastic IP address of the NAT Gateway"
  value       = aws_eip.nat_eip.public_ip
}

# -----------------------------------------------------------------------------
# Directory Service Outputs
# -----------------------------------------------------------------------------

output "directory_id" {
  description = "ID of the Simple AD directory"
  value       = aws_directory_service_directory.workspaces_directory.id
}

output "directory_name" {
  description = "Name of the Simple AD directory"
  value       = aws_directory_service_directory.workspaces_directory.name
}

output "directory_dns_ip_addresses" {
  description = "DNS IP addresses of the Simple AD directory"
  value       = aws_directory_service_directory.workspaces_directory.dns_ip_addresses
  sensitive   = true
}

output "directory_security_group_id" {
  description = "Security Group ID of the Simple AD directory"
  value       = aws_directory_service_directory.workspaces_directory.security_group_id
}

# -----------------------------------------------------------------------------
# WorkSpaces Directory Outputs
# -----------------------------------------------------------------------------

output "workspaces_directory_id" {
  description = "ID of the WorkSpaces directory registration"
  value       = aws_workspaces_directory.workspaces_directory.directory_id
}

output "workspaces_directory_state" {
  description = "State of the WorkSpaces directory"
  value       = aws_workspaces_directory.workspaces_directory.state
}

output "workspaces_directory_workspace_security_group_id" {
  description = "Security Group ID for WorkSpaces instances"
  value       = aws_workspaces_directory.workspaces_directory.workspace_security_group_id
}

output "workspaces_directory_iam_role_id" {
  description = "IAM role ID for the WorkSpaces directory"
  value       = aws_workspaces_directory.workspaces_directory.iam_role_id
}

output "workspaces_directory_registration_code" {
  description = "Registration code for the WorkSpaces directory"
  value       = aws_workspaces_directory.workspaces_directory.registration_code
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------------------------------

output "workspaces_security_group_id" {
  description = "ID of the custom security group for WorkSpaces"
  value       = aws_security_group.workspaces_sg.id
}

output "workspaces_security_group_arn" {
  description = "ARN of the custom security group for WorkSpaces"
  value       = aws_security_group.workspaces_sg.arn
}

# -----------------------------------------------------------------------------
# IP Access Control Group Outputs
# -----------------------------------------------------------------------------

output "workspaces_ip_group_id" {
  description = "ID of the WorkSpaces IP access control group"
  value       = aws_workspaces_ip_group.workspaces_ip_group.id
}

output "workspaces_ip_group_name" {
  description = "Name of the WorkSpaces IP access control group"
  value       = aws_workspaces_ip_group.workspaces_ip_group.name
}

# -----------------------------------------------------------------------------
# WorkSpace Bundle Information
# -----------------------------------------------------------------------------

output "workspace_bundle_id" {
  description = "ID of the WorkSpace bundle being used"
  value       = data.aws_workspaces_bundle.standard_windows.id
}

output "workspace_bundle_name" {
  description = "Name of the WorkSpace bundle being used"
  value       = data.aws_workspaces_bundle.standard_windows.name
}

output "workspace_bundle_description" {
  description = "Description of the WorkSpace bundle being used"
  value       = data.aws_workspaces_bundle.standard_windows.description
}

output "workspace_bundle_compute_type" {
  description = "Compute type details of the WorkSpace bundle"
  value       = data.aws_workspaces_bundle.standard_windows.compute_type
}

output "workspace_bundle_storage" {
  description = "Storage details of the WorkSpace bundle"
  value       = data.aws_workspaces_bundle.standard_windows.root_storage
}

# -----------------------------------------------------------------------------
# Sample WorkSpace Outputs (if created)
# -----------------------------------------------------------------------------

output "sample_workspace_id" {
  description = "ID of the sample WorkSpace (if created)"
  value       = var.create_sample_workspace ? aws_workspaces_workspace.sample_workspace[0].id : null
}

output "sample_workspace_ip_address" {
  description = "IP address of the sample WorkSpace (if created)"
  value       = var.create_sample_workspace ? aws_workspaces_workspace.sample_workspace[0].ip_address : null
}

output "sample_workspace_state" {
  description = "State of the sample WorkSpace (if created)"
  value       = var.create_sample_workspace ? aws_workspaces_workspace.sample_workspace[0].state : null
}

output "sample_workspace_computer_name" {
  description = "Computer name of the sample WorkSpace (if created)"
  value       = var.create_sample_workspace ? aws_workspaces_workspace.sample_workspace[0].computer_name : null
}

output "sample_workspace_username" {
  description = "Username of the sample WorkSpace (if created)"
  value       = var.create_sample_workspace ? aws_workspaces_workspace.sample_workspace[0].user_name : null
}

# -----------------------------------------------------------------------------
# CloudWatch Monitoring Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for WorkSpaces"
  value       = aws_cloudwatch_log_group.workspaces_log_group.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for WorkSpaces"
  value       = aws_cloudwatch_log_group.workspaces_log_group.arn
}

output "cloudwatch_connection_failures_alarm_arn" {
  description = "ARN of the CloudWatch alarm for connection failures (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.workspaces_connection_failures[0].arn : null
}

output "cloudwatch_session_disconnections_alarm_arn" {
  description = "ARN of the CloudWatch alarm for session disconnections (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.workspaces_session_disconnections[0].arn : null
}

# -----------------------------------------------------------------------------
# SNS Topic Outputs (if created)
# -----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the SNS topic for WorkSpaces alerts (if created)"
  value       = var.enable_cloudwatch_alarms && length(var.cloudwatch_alarm_actions) == 0 ? aws_sns_topic.workspaces_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for WorkSpaces alerts (if created)"
  value       = var.enable_cloudwatch_alarms && length(var.cloudwatch_alarm_actions) == 0 ? aws_sns_topic.workspaces_alerts[0].name : null
}

# -----------------------------------------------------------------------------
# Connection Information
# -----------------------------------------------------------------------------

output "workspaces_client_download_urls" {
  description = "Download URLs for WorkSpaces client applications"
  value = {
    windows = "https://clients.amazonworkspaces.com/windows/"
    macos   = "https://clients.amazonworkspaces.com/macos/"
    linux   = "https://clients.amazonworkspaces.com/linux/"
    ios     = "https://apps.apple.com/us/app/amazon-workspaces/id625081876"
    android = "https://play.google.com/store/apps/details?id=com.amazon.workspaces"
  }
}

output "workspaces_web_access_url" {
  description = "URL for web-based WorkSpaces access"
  value       = "https://clients.amazonworkspaces.com/webclient"
}

# -----------------------------------------------------------------------------
# Cost Estimation Information
# -----------------------------------------------------------------------------

output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs"
  value = {
    note                     = "Actual costs depend on usage patterns, bundle type, and running mode"
    workspaces_pricing_url   = "https://aws.amazon.com/workspaces/pricing/"
    simple_ad_cost          = "Free when used with WorkSpaces"
    nat_gateway_cost        = "~$45/month for NAT Gateway + data processing charges"
    sample_workspace_cost   = var.create_sample_workspace ? "~$25-50/month depending on bundle and usage" : "No sample WorkSpace created"
  }
}

# -----------------------------------------------------------------------------
# AWS Region and Account Information
# -----------------------------------------------------------------------------

output "aws_region" {
  description = "AWS region where resources are created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Next Steps Information
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Next steps for setting up WorkSpaces"
  value = {
    "1_create_users"     = "Create users in the Simple AD directory or import from existing directory"
    "2_create_workspaces" = "Create additional WorkSpaces for users using the AWS CLI or Console"
    "3_configure_ip_groups" = "Update IP access control groups with specific IP ranges for security"
    "4_setup_monitoring" = "Configure additional CloudWatch metrics and dashboards for monitoring"
    "5_test_access"     = "Test WorkSpace access using the client applications"
    "6_backup_strategy"  = "Implement backup strategy for user data and WorkSpace images"
  }
}