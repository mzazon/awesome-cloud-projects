# ==============================================================================
# NETWORKING OUTPUTS
# ==============================================================================

output "vpc_id" {
  description = "ID of the VPC created for VMware Cloud connectivity"
  value       = aws_vpc.vmware_migration.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.vmware_migration.cidr_block
}

output "subnet_id" {
  description = "ID of the subnet created for VMware Cloud connectivity"
  value       = aws_subnet.vmware_migration.id
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = aws_subnet.vmware_migration.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.vmware_migration.id
}

output "route_table_id" {
  description = "ID of the route table"
  value       = aws_route_table.vmware_migration.id
}

# ==============================================================================
# SECURITY GROUP OUTPUTS
# ==============================================================================

output "hcx_security_group_id" {
  description = "ID of the HCX security group"
  value       = aws_security_group.hcx.id
}

output "mgn_security_group_id" {
  description = "ID of the MGN replication security group"
  value       = var.enable_mgn ? aws_security_group.mgn_replication[0].id : null
}

# ==============================================================================
# DIRECT CONNECT OUTPUTS
# ==============================================================================

output "direct_connect_gateway_id" {
  description = "ID of the Direct Connect Gateway"
  value       = var.enable_direct_connect ? aws_dx_gateway.vmware_migration[0].id : null
}

output "direct_connect_virtual_interface_id" {
  description = "ID of the Direct Connect Virtual Interface"
  value       = var.enable_direct_connect && var.direct_connect_connection_id != "" ? aws_dx_private_virtual_interface.vmware_migration[0].id : null
}

# ==============================================================================
# IAM OUTPUTS
# ==============================================================================

output "vmware_cloud_service_role_arn" {
  description = "ARN of the VMware Cloud on AWS service role"
  value       = aws_iam_role.vmware_cloud_service_role.arn
}

output "vmware_cloud_service_role_name" {
  description = "Name of the VMware Cloud on AWS service role"
  value       = aws_iam_role.vmware_cloud_service_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ==============================================================================
# MIGRATION SERVICE OUTPUTS
# ==============================================================================

output "mgn_replication_configuration_template_id" {
  description = "ID of the MGN replication configuration template"
  value       = var.enable_mgn ? aws_mgn_replication_configuration_template.main[0].id : null
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "backup_bucket_name" {
  description = "Name of the S3 bucket for VMware backups"
  value       = aws_s3_bucket.vmware_backup.bucket
}

output "backup_bucket_arn" {
  description = "ARN of the S3 bucket for VMware backups"
  value       = aws_s3_bucket.vmware_backup.arn
}

output "backup_bucket_domain_name" {
  description = "Domain name of the S3 bucket for VMware backups"
  value       = aws_s3_bucket.vmware_backup.bucket_domain_name
}

output "backup_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket for VMware backups"
  value       = aws_s3_bucket.vmware_backup.bucket_regional_domain_name
}

# ==============================================================================
# DATABASE OUTPUTS
# ==============================================================================

output "migration_tracking_table_name" {
  description = "Name of the DynamoDB table for migration tracking"
  value       = aws_dynamodb_table.migration_tracking.name
}

output "migration_tracking_table_arn" {
  description = "ARN of the DynamoDB table for migration tracking"
  value       = aws_dynamodb_table.migration_tracking.arn
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for VMware operations"
  value       = aws_cloudwatch_log_group.vmware_migration.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for VMware operations"
  value       = aws_cloudwatch_log_group.vmware_migration.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.vmware_migration.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.vmware_migration.dashboard_name}"
}

# ==============================================================================
# NOTIFICATION OUTPUTS
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for VMware migration alerts"
  value       = aws_sns_topic.vmware_migration_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for VMware migration alerts"
  value       = aws_sns_topic.vmware_migration_alerts.name
}

# ==============================================================================
# LAMBDA OUTPUTS
# ==============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for migration orchestration"
  value       = aws_lambda_function.migration_orchestrator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for migration orchestration"
  value       = aws_lambda_function.migration_orchestrator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for migration orchestration"
  value       = aws_lambda_function.migration_orchestrator.invoke_arn
}

# ==============================================================================
# COST MONITORING OUTPUTS
# ==============================================================================

output "budget_name" {
  description = "Name of the AWS Budget for VMware Cloud on AWS"
  value       = var.enable_cost_budget ? aws_budgets_budget.vmware_cloud_budget[0].name : null
}

output "cost_anomaly_detector_arn" {
  description = "ARN of the Cost Anomaly Detector"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_detector.vmware_cost[0].arn : null
}

# ==============================================================================
# CLOUDTRAIL OUTPUTS
# ==============================================================================

output "cloudtrail_name" {
  description = "Name of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.vmware_migration[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.vmware_migration[0].arn : null
}

output "cloudtrail_bucket_name" {
  description = "Name of the S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

# ==============================================================================
# VPC FLOW LOGS OUTPUTS
# ==============================================================================

output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = var.enable_vpc_flow_logs ? aws_flow_log.vmware_vpc[0].id : null
}

output "vpc_flow_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Flow Logs"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}

# ==============================================================================
# CONFIGURATION OUTPUTS
# ==============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# ==============================================================================
# MIGRATION WAVE OUTPUTS
# ==============================================================================

output "migration_waves" {
  description = "Configuration of migration waves"
  value = {
    for wave in var.migration_waves : "wave-${wave.wave}" => {
      wave_number    = wave.wave
      description    = wave.description
      priority       = wave.priority
      vm_count       = length(wave.vms)
      migration_type = wave.migration_type
    }
  }
}

output "migration_wave_count" {
  description = "Total number of migration waves configured"
  value       = length(var.migration_waves)
}

# ==============================================================================
# NEXT STEPS OUTPUTS
# ==============================================================================

output "next_steps" {
  description = "Next steps for completing the VMware Cloud on AWS setup"
  value = {
    vmware_cloud_console = {
      description = "Complete SDDC deployment via VMware Cloud Console"
      url         = "https://vmc.vmware.com"
      steps = [
        "Login to VMware Cloud Console",
        "Create SDDC with the following parameters:",
        "- Name: ${var.sddc_name}",
        "- Region: ${var.aws_region}",
        "- Host Type: ${var.vmware_host_type}",
        "- Number of Hosts: ${var.vmware_host_count}",
        "- Management Subnet: ${var.management_subnet_cidr}",
        "- Connected VPC: ${aws_vpc.vmware_migration.id}",
        "- Connected Subnet: ${aws_subnet.vmware_migration.id}"
      ]
    }
    hcx_configuration = {
      description = "Configure HCX for workload migration"
      steps = [
        "Deploy HCX Manager in on-premises environment",
        "Configure HCX Cloud Manager in VMware Cloud on AWS",
        "Establish network connectivity between HCX components",
        "Configure service mesh for workload migration",
        "Test connectivity and perform pilot migrations"
      ]
    }
    monitoring_access = {
      description = "Access monitoring dashboards"
      cloudwatch_dashboard = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.vmware_migration.dashboard_name}"
    }
  }
}

# ==============================================================================
# IMPORTANT NOTES OUTPUT
# ==============================================================================

output "important_notes" {
  description = "Important notes and considerations"
  value = {
    cost_warning = "VMware Cloud on AWS incurs significant monthly costs. Monitor usage and scale appropriately."
    security_note = "Review security group rules and adjust CIDR blocks based on your network requirements."
    backup_location = "VMware backups are stored in S3 bucket: ${aws_s3_bucket.vmware_backup.bucket}"
    notifications = "Email notifications will be sent to: ${var.admin_email}"
    direct_connect = var.enable_direct_connect ? "Direct Connect Gateway created: ${aws_dx_gateway.vmware_migration[0].id}" : "Direct Connect is disabled. Enable via variables if needed."
    mgn_status = var.enable_mgn ? "AWS Application Migration Service is enabled for non-VMware workloads" : "AWS Application Migration Service is disabled"
  }
}