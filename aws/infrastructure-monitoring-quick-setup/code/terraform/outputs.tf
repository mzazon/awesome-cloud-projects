# Output Values for Infrastructure Monitoring Quick Setup
# These outputs provide important resource identifiers and configuration details

# ============================================================================
# GENERAL OUTPUTS
# ============================================================================

output "aws_region" {
  description = "AWS region where resources were created"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "ssm_service_role_arn" {
  description = "ARN of the Systems Manager service role"
  value       = aws_iam_role.ssm_service_role.arn
}

output "ssm_service_role_name" {
  description = "Name of the Systems Manager service role"
  value       = aws_iam_role.ssm_service_role.name
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "cloudwatch_agent_config_parameter" {
  description = "SSM Parameter Store name containing CloudWatch Agent configuration"
  value       = aws_ssm_parameter.cloudwatch_agent_config.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch monitoring dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure_monitoring.dashboard_name}"
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch monitoring dashboard"
  value       = aws_cloudwatch_dashboard.infrastructure_monitoring.dashboard_name
}

output "infrastructure_log_group_name" {
  description = "CloudWatch log group name for infrastructure logs"
  value       = aws_cloudwatch_log_group.infrastructure_logs.name
}

output "infrastructure_log_group_arn" {
  description = "ARN of the infrastructure CloudWatch log group"
  value       = aws_cloudwatch_log_group.infrastructure_logs.arn
}

output "application_log_group_name" {
  description = "CloudWatch log group name for application logs"
  value       = aws_cloudwatch_log_group.application_logs.name
}

output "application_log_group_arn" {
  description = "ARN of the application CloudWatch log group"
  value       = aws_cloudwatch_log_group.application_logs.arn
}

# ============================================================================
# CLOUDWATCH ALARMS OUTPUTS
# ============================================================================

output "cpu_alarm_name" {
  description = "Name of the high CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name
}

output "cpu_alarm_arn" {
  description = "ARN of the high CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu_utilization.arn
}

output "disk_alarm_name" {
  description = "Name of the high disk usage alarm (if enabled)"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.high_disk_usage[0].alarm_name : null
}

output "disk_alarm_arn" {
  description = "ARN of the high disk usage alarm (if enabled)"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.high_disk_usage[0].arn : null
}

output "memory_alarm_name" {
  description = "Name of the high memory usage alarm (if enabled)"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.high_memory_usage[0].alarm_name : null
}

output "memory_alarm_arn" {
  description = "ARN of the high memory usage alarm (if enabled)"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.high_memory_usage[0].arn : null
}

# ============================================================================
# SYSTEMS MANAGER OUTPUTS
# ============================================================================

output "inventory_association_id" {
  description = "ID of the inventory collection association (if enabled)"
  value       = var.enable_compliance_monitoring ? aws_ssm_association.inventory_collection[0].association_id : null
}

output "inventory_association_name" {
  description = "Name of the inventory collection association (if enabled)"
  value       = var.enable_compliance_monitoring ? aws_ssm_association.inventory_collection[0].association_name : null
}

output "patch_scanning_association_id" {
  description = "ID of the patch scanning association (if enabled)"
  value       = var.enable_compliance_monitoring ? aws_ssm_association.patch_scanning[0].association_id : null
}

output "patch_scanning_association_name" {
  description = "Name of the patch scanning association (if enabled)"
  value       = var.enable_compliance_monitoring ? aws_ssm_association.patch_scanning[0].association_name : null
}

output "cloudwatch_agent_association_id" {
  description = "ID of the CloudWatch Agent installation association (if enabled)"
  value       = var.enable_detailed_monitoring ? aws_ssm_association.cloudwatch_agent_install[0].association_id : null
}

output "cloudwatch_agent_association_name" {
  description = "Name of the CloudWatch Agent installation association (if enabled)"
  value       = var.enable_detailed_monitoring ? aws_ssm_association.cloudwatch_agent_install[0].association_name : null
}

output "patch_baseline_id" {
  description = "ID of the patch baseline (if enabled)"
  value       = var.enable_compliance_monitoring ? aws_ssm_patch_baseline.amazon_linux[0].id : null
}

output "patch_baseline_name" {
  description = "Name of the patch baseline (if enabled)"
  value       = var.enable_compliance_monitoring ? aws_ssm_patch_baseline.amazon_linux[0].name : null
}

# ============================================================================
# CONFIGURATION OUTPUTS
# ============================================================================

output "alarm_thresholds" {
  description = "Configured alarm thresholds"
  value = {
    cpu_threshold  = var.cpu_alarm_threshold
    disk_threshold = var.disk_alarm_threshold
    memory_threshold = 90
  }
}

output "log_retention_settings" {
  description = "Configured log retention settings"
  value = {
    infrastructure_logs = var.log_retention_days
    application_logs   = var.application_log_retention_days
  }
}

output "monitoring_configuration" {
  description = "Current monitoring configuration settings"
  value = {
    detailed_monitoring    = var.enable_detailed_monitoring
    compliance_monitoring  = var.enable_compliance_monitoring
    metrics_interval      = var.metrics_collection_interval
    cloudwatch_namespace  = var.cloudwatch_namespace
  }
}

output "schedule_expressions" {
  description = "Configured schedule expressions for automated tasks"
  value = {
    patch_scanning      = var.patch_scan_schedule
    inventory_collection = var.inventory_collection_schedule
  }
}

# ============================================================================
# VALIDATION COMMANDS
# ============================================================================

output "validation_commands" {
  description = "Commands to validate the monitoring setup"
  value = {
    check_managed_instances = "aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId,ComputerName,ResourceType,IPAddress]' --output table"
    check_cloudwatch_metrics = "aws cloudwatch list-metrics --namespace AWS/EC2 --metric-name CPUUtilization --query 'Metrics[0:3].[MetricName,Namespace]' --output table"
    check_alarm_status = "aws cloudwatch describe-alarms --alarm-names '${aws_cloudwatch_metric_alarm.high_cpu_utilization.alarm_name}' --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' --output table"
    check_compliance_summary = "aws ssm list-compliance-summary-by-compliance-type --query 'ComplianceSummaryItems[*].[ComplianceType,OverallSeverity,CompliantCount]' --output table"
    view_dashboard = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.infrastructure_monitoring.dashboard_name}"
  }
}

# ============================================================================
# CLEANUP COMMANDS
# ============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources (for manual cleanup reference)"
  value = {
    terraform_destroy = "terraform destroy -auto-approve"
    manual_cleanup_note = "Use 'terraform destroy' to remove all resources created by this configuration"
  }
}