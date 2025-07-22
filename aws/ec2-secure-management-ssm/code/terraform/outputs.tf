# =========================================================================
# AWS EC2 Instances Securely with Systems Manager - Output Definitions
# =========================================================================
# This file defines all outputs from the Terraform configuration,
# providing useful information for verification, integration, and operations.

# =========================================================================
# EC2 INSTANCE INFORMATION
# =========================================================================

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.secure_server.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.secure_server.arn
}

output "instance_state" {
  description = "Current state of the EC2 instance"
  value       = aws_instance.secure_server.instance_state
}

output "instance_type" {
  description = "Instance type of the EC2 instance"
  value       = aws_instance.secure_server.instance_type
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.secure_server.private_ip
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance (if assigned)"
  value       = aws_instance.secure_server.public_ip
}

output "instance_private_dns" {
  description = "Private DNS name of the EC2 instance"
  value       = aws_instance.secure_server.private_dns
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance (if assigned)"
  value       = aws_instance.secure_server.public_dns
}

output "instance_availability_zone" {
  description = "Availability zone where the instance is running"
  value       = aws_instance.secure_server.availability_zone
}

output "instance_ami_id" {
  description = "AMI ID used for the EC2 instance"
  value       = aws_instance.secure_server.ami
}

# =========================================================================
# SYSTEMS MANAGER CONNECTION INFORMATION
# =========================================================================

output "session_manager_command" {
  description = "AWS CLI command to start a Session Manager session"
  value       = "aws ssm start-session --target ${aws_instance.secure_server.id}"
}

output "session_manager_url" {
  description = "Direct URL to Session Manager in AWS Console"
  value       = "https://${data.aws_partition.current.partition == "aws" ? "" : "${data.aws_partition.current.partition}."}console.aws.amazon.com/systems-manager/session-manager/${aws_instance.secure_server.id}?region=${data.aws_region.current.name}"
}

output "run_command_example" {
  description = "Example AWS CLI command for Systems Manager Run Command"
  value       = "aws ssm send-command --document-name 'AWS-RunShellScript' --targets 'Key=InstanceIds,Values=${aws_instance.secure_server.id}' --parameters 'commands=[\"uname -a\",\"df -h\"]'"
}

output "fleet_manager_url" {
  description = "Direct URL to Fleet Manager for file operations"
  value       = "https://${data.aws_partition.current.partition == "aws" ? "" : "${data.aws_partition.current.partition}."}console.aws.amazon.com/systems-manager/managed-instances/${aws_instance.secure_server.id}/file-system?region=${data.aws_region.current.name}"
}

# =========================================================================
# IAM RESOURCES INFORMATION
# =========================================================================

output "iam_role_name" {
  description = "Name of the IAM role attached to the instance"
  value       = aws_iam_role.ssm_instance_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.ssm_instance_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile attached to the instance"
  value       = aws_iam_instance_profile.ssm_instance_profile.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile attached to the instance"
  value       = aws_iam_instance_profile.ssm_instance_profile.arn
}

# =========================================================================
# SECURITY GROUP INFORMATION
# =========================================================================

output "security_group_id" {
  description = "ID of the security group attached to the instance"
  value       = aws_security_group.ssm_secure.id
}

output "security_group_arn" {
  description = "ARN of the security group attached to the instance"
  value       = aws_security_group.ssm_secure.arn
}

output "security_group_name" {
  description = "Name of the security group attached to the instance"
  value       = aws_security_group.ssm_secure.name
}

# =========================================================================
# NETWORK INFORMATION
# =========================================================================

output "vpc_id" {
  description = "ID of the VPC where the instance is deployed"
  value       = data.aws_vpc.default.id
}

output "subnet_id" {
  description = "ID of the subnet where the instance is deployed"
  value       = aws_instance.secure_server.subnet_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = data.aws_vpc.default.cidr_block
}

# =========================================================================
# LOGGING AND MONITORING INFORMATION
# =========================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for session logs"
  value       = var.enable_session_logging ? aws_cloudwatch_log_group.session_logs[0].name : "Session logging not enabled"
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for session logs"
  value       = var.enable_session_logging ? aws_cloudwatch_log_group.session_logs[0].arn : null
}

output "cloudwatch_logs_url" {
  description = "Direct URL to CloudWatch Logs for session monitoring"
  value       = var.enable_session_logging ? "https://${data.aws_partition.current.partition == "aws" ? "" : "${data.aws_partition.current.partition}."}console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.session_logs[0].name, "/", "$252F")}" : "Session logging not enabled"
}

# =========================================================================
# TESTING AND VERIFICATION INFORMATION
# =========================================================================

output "web_application_url" {
  description = "URL to access the test web application (if public IP is assigned)"
  value       = var.assign_public_ip && aws_instance.secure_server.public_ip != null ? "http://${aws_instance.secure_server.public_ip}" : "No public IP assigned - access through Session Manager"
}

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_ssm_registration = "aws ssm describe-instance-information --filters 'Key=InstanceIds,Values=${aws_instance.secure_server.id}' --query 'InstanceInformationList[0].PingStatus' --output text"
    
    test_run_command = "aws ssm send-command --document-name 'AWS-RunShellScript' --targets 'Key=InstanceIds,Values=${aws_instance.secure_server.id}' --parameters 'commands=[\"echo Hello from Systems Manager\",\"hostname\",\"date\"]'"
    
    check_instance_status = "aws ec2 describe-instances --instance-ids ${aws_instance.secure_server.id} --query 'Reservations[0].Instances[0].State.Name' --output text"
    
    view_session_logs = var.enable_session_logging ? "aws logs describe-log-streams --log-group-name '${aws_cloudwatch_log_group.session_logs[0].name}'" : "Session logging not enabled"
  }
}

# =========================================================================
# SECURITY AND COMPLIANCE INFORMATION
# =========================================================================

output "security_summary" {
  description = "Summary of security configurations implemented"
  value = {
    inbound_ports_open    = "None - Zero inbound access"
    ssh_key_required      = "No - Session Manager provides secure access"
    bastion_host_required = "No - Direct Systems Manager access"
    encryption_in_transit = "Yes - TLS 1.2+ via Systems Manager"
    audit_logging         = var.enable_session_logging ? "Yes - CloudWatch Logs" : "No"
    iam_role_based_access = "Yes - No permanent credentials on instance"
  }
}

output "compliance_features" {
  description = "Compliance and auditing features enabled"
  value = {
    session_logging      = var.enable_session_logging
    cloudwatch_logs     = var.enable_session_logging ? aws_cloudwatch_log_group.session_logs[0].name : "Disabled"
    log_retention_days  = var.enable_session_logging ? var.log_retention_days : "N/A"
    encryption_enabled  = var.cloudwatch_encryption_enabled
    s3_backup          = var.s3_bucket_name != "" ? "Enabled" : "Disabled"
  }
}

# =========================================================================
# COST OPTIMIZATION INFORMATION
# =========================================================================

output "cost_optimization" {
  description = "Cost optimization features and recommendations"
  value = {
    instance_type           = var.instance_type
    spot_instances         = var.enable_spot_instances ? "Enabled" : "Disabled"
    detailed_monitoring    = var.enable_detailed_monitoring ? "Enabled" : "Disabled"
    estimated_monthly_cost = "Approximately $${var.instance_type == "t2.micro" ? "8-10" : "20-50"} USD depending on usage"
    
    recommendations = [
      "Use t3.nano or t3.micro for development environments",
      "Enable Spot instances for non-critical workloads",
      "Set up AWS Budgets to monitor costs",
      "Use Instance Scheduler to stop instances during off-hours"
    ]
  }
}

# =========================================================================
# OPERATIONAL INFORMATION
# =========================================================================

output "operational_commands" {
  description = "Common operational commands for managing the instance"
  value = {
    start_session        = "aws ssm start-session --target ${aws_instance.secure_server.id}"
    stop_instance       = "aws ec2 stop-instances --instance-ids ${aws_instance.secure_server.id}"
    start_instance      = "aws ec2 start-instances --instance-ids ${aws_instance.secure_server.id}"
    reboot_instance     = "aws ec2 reboot-instances --instance-ids ${aws_instance.secure_server.id}"
    get_console_output  = "aws ec2 get-console-output --instance-id ${aws_instance.secure_server.id}"
    
    patch_instance = "aws ssm send-command --document-name 'AWS-RunPatchBaseline' --targets 'Key=InstanceIds,Values=${aws_instance.secure_server.id}'"
    
    install_software = "aws ssm send-command --document-name 'AWS-ConfigureAWSPackage' --targets 'Key=InstanceIds,Values=${aws_instance.secure_server.id}' --parameters 'action=Install,name=AmazonCloudWatchAgent'"
  }
}

# =========================================================================
# DATA SOURCES FOR OUTPUT CONTEXT
# =========================================================================

data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# =========================================================================
# INTEGRATION INFORMATION
# =========================================================================

output "integration_endpoints" {
  description = "Endpoints and ARNs for integration with other AWS services"
  value = {
    instance_id          = aws_instance.secure_server.id
    instance_arn         = aws_instance.secure_server.arn
    iam_role_arn         = aws_iam_role.ssm_instance_role.arn
    security_group_id    = aws_security_group.ssm_secure.id
    log_group_arn       = var.enable_session_logging ? aws_cloudwatch_log_group.session_logs[0].arn : null
    
    # For automation and CI/CD integration
    automation_role_arn = aws_iam_role.ssm_instance_role.arn
    target_specification = {
      Key    = "InstanceIds"
      Values = [aws_instance.secure_server.id]
    }
  }
}

# =========================================================================
# TROUBLESHOOTING INFORMATION
# =========================================================================

output "troubleshooting_guide" {
  description = "Common troubleshooting commands and information"
  value = {
    common_issues = {
      "Instance not showing in SSM" = "Check IAM role has AmazonSSMManagedInstanceCore policy and instance has internet access"
      "Session Manager not working" = "Verify Session Manager plugin is installed: 'session-manager-plugin'"
      "Run Command failing"         = "Check instance is 'Online' in Systems Manager console"
    }
    
    diagnostic_commands = {
      check_ssm_agent_status = "aws ssm send-command --document-name 'AWS-RunShellScript' --targets 'Key=InstanceIds,Values=${aws_instance.secure_server.id}' --parameters 'commands=[\"systemctl status amazon-ssm-agent\"]'"
      
      check_connectivity = "aws ssm describe-instance-information --filters 'Key=InstanceIds,Values=${aws_instance.secure_server.id}'"
      
      view_instance_logs = "aws ec2 get-console-output --instance-id ${aws_instance.secure_server.id} --output text"
    }
    
    useful_links = [
      "Systems Manager Troubleshooting: https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting.html",
      "Session Manager Setup: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started.html",
      "Run Command Documentation: https://docs.aws.amazon.com/systems-manager/latest/userguide/execute-remote-commands.html"
    ]
  }
}