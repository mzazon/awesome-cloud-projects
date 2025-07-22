# outputs.tf - Output values for Enterprise Migration Assessment infrastructure
# This file defines the output values that will be displayed after deployment
# and can be used by other Terraform configurations or scripts

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing discovery data"
  value       = aws_s3_bucket.discovery_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing discovery data"
  value       = aws_s3_bucket.discovery_data.arn
}

output "s3_bucket_region" {
  description = "Region where the S3 bucket is located"
  value       = aws_s3_bucket.discovery_data.region
}

# KMS Key Information
output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.discovery_encryption[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.discovery_encryption[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_alias.discovery_encryption[0].name : null
}

# CloudWatch Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for discovery service"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.discovery_service[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for discovery service"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.discovery_service[0].arn : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard for monitoring discovery progress"
  value = var.enable_cloudwatch_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.discovery_monitoring[0].dashboard_name}" : null
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for migration notifications"
  value       = var.notification_email != "" ? aws_sns_topic.migration_notifications[0].arn : null
}

# EventBridge Rule Information
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for automated discovery export"
  value       = var.enable_eventbridge_automation ? aws_cloudwatch_event_rule.discovery_export[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for automated discovery export"
  value       = var.enable_eventbridge_automation ? aws_cloudwatch_event_rule.discovery_export[0].arn : null
}

# Project Information
output "migration_project_name" {
  description = "Name of the migration project"
  value       = var.migration_project_name
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

# Configuration Files
output "agent_config_s3_key" {
  description = "S3 key for the agent configuration file"
  value       = aws_s3_object.agent_config.key
}

output "migration_waves_config_s3_key" {
  description = "S3 key for the migration waves configuration file"
  value       = aws_s3_object.migration_waves_config.key
}

output "connector_config_s3_key" {
  description = "S3 key for the VMware connector configuration file (if configured)"
  value       = var.vmware_vcenter_config.hostname != "" ? aws_s3_object.connector_config[0].key : null
}

# Discovery Agent Download URLs
output "agent_download_urls" {
  description = "URLs for downloading Discovery Agents"
  value = {
    windows_installer = "https://aws-discovery-agent.s3.amazonaws.com/windows/latest/AWSApplicationDiscoveryAgentInstaller.exe"
    linux_tar_gz     = "https://aws-discovery-agent.s3.amazonaws.com/linux/latest/aws-discovery-agent.tar.gz"
    vmware_ova       = "https://aws-discovery-connector.s3.amazonaws.com/VMware/latest/AWS-Discovery-Connector.ova"
  }
}

# AWS Console URLs
output "console_urls" {
  description = "URLs to access AWS console for various services"
  value = {
    application_discovery_service = "https://${data.aws_region.current.name}.console.aws.amazon.com/discovery/home?region=${data.aws_region.current.name}"
    migration_hub                = "https://${data.aws_region.current.name}.console.aws.amazon.com/migrationhub/home?region=${data.aws_region.current.name}"
    s3_bucket                    = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.discovery_data.id}?region=${data.aws_region.current.name}"
    cloudwatch_logs              = var.enable_cloudwatch_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${urlencode(aws_cloudwatch_log_group.discovery_service[0].name)}" : null
  }
}

# Migration Wave Information
output "migration_waves" {
  description = "Configured migration waves for the project"
  value       = var.migration_waves
}

# Security Information
output "security_configuration" {
  description = "Security configuration status"
  value = {
    encryption_enabled    = var.enable_encryption
    versioning_enabled    = var.enable_versioning
    public_access_blocked = true
    ssl_required         = true
    kms_key_rotation     = var.enable_encryption ? true : false
  }
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = time_static.deployment_time.rfc3339
}

# CLI Commands for Common Operations
output "cli_commands" {
  description = "Useful AWS CLI commands for managing the discovery service"
  value = {
    check_agent_health = "aws discovery describe-agents --query 'agentsInfo[*].[agentId,health,version,lastHealthPingTime]' --output table"
    list_servers      = "aws discovery list-configurations --configuration-type SERVER --query 'configurations[*].[configurationId,serverType,osName,osVersion]' --output table"
    start_export      = "aws discovery start-export-task --export-data-format CSV --s3-bucket ${aws_s3_bucket.discovery_data.id} --s3-prefix exports/"
    check_export      = "aws discovery describe-export-tasks --query 'exportsInfo[*].[exportId,exportStatus,s3Bucket,recordsCount]' --output table"
    list_s3_exports   = "aws s3 ls s3://${aws_s3_bucket.discovery_data.id}/exports/ --recursive"
  }
}

# Cost Optimization Information
output "cost_optimization" {
  description = "Information about cost optimization features"
  value = {
    lifecycle_policy_enabled = true
    standard_ia_transition   = "30 days"
    glacier_transition       = "90 days"
    data_retention_days      = var.data_retention_days
    s3_bucket_class         = "STANDARD"
    versioning_cleanup      = var.enable_versioning ? "30 days for old versions" : "disabled"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value = [
    "1. Download Discovery Agents from the provided URLs",
    "2. Install agents on representative servers (Windows/Linux)",
    "3. Configure VMware Discovery Connector if using VMware vSphere",
    "4. Monitor agent health using the CloudWatch dashboard",
    "5. Allow 2+ weeks for comprehensive data collection",
    "6. Export discovery data regularly using the CLI commands",
    "7. Review collected data in AWS Migration Hub",
    "8. Plan migration waves based on discovered dependencies",
    "9. Use discovery data for right-sizing and cost estimation"
  ]
}

# Troubleshooting Information
output "troubleshooting" {
  description = "Common troubleshooting resources"
  value = {
    agent_logs_location = {
      windows = "C:\\Program Files\\Amazon\\AWSApplicationDiscoveryAgent\\logs"
      linux   = "/var/log/aws-discovery-agent"
    }
    common_ports = {
      outbound_https = "443 (required for agent communication)"
      agent_health   = "Check agent health every 15 minutes"
    }
    support_resources = {
      documentation = "https://docs.aws.amazon.com/application-discovery/latest/userguide/"
      troubleshooting = "https://docs.aws.amazon.com/application-discovery/latest/userguide/troubleshooting.html"
    }
  }
}