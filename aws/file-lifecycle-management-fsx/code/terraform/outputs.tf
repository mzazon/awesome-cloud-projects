# outputs.tf
# Output values for FSx Intelligent Tiering with Lambda lifecycle management

# FSx File System Outputs
output "fsx_file_system_id" {
  description = "ID of the FSx OpenZFS file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.id
}

output "fsx_file_system_arn" {
  description = "ARN of the FSx OpenZFS file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.arn
}

output "fsx_dns_name" {
  description = "DNS name of the FSx file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.dns_name
}

output "fsx_network_interface_ids" {
  description = "Network interface IDs of the FSx file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.network_interface_ids
}

output "fsx_owner_id" {
  description = "AWS account identifier that created the file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.owner_id
}

output "fsx_storage_capacity" {
  description = "Storage capacity of the FSx file system in GiB"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.storage_capacity
}

output "fsx_throughput_capacity" {
  description = "Throughput capacity of the FSx file system in MBps"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.throughput_capacity
}

output "fsx_storage_type" {
  description = "Storage type of the FSx file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.storage_type
}

output "fsx_deployment_type" {
  description = "Deployment type of the FSx file system"
  value       = aws_fsx_openzfs_file_system.intelligent_tiering.deployment_type
}

# NFS Mount Information
output "nfs_mount_command" {
  description = "Command to mount the FSx file system via NFS"
  value = "sudo mount -t nfs -o nfsvers=4.1 ${aws_fsx_openzfs_file_system.intelligent_tiering.dns_name}:/ /mnt/fsx"
}

output "nfs_mount_target" {
  description = "NFS mount target for the FSx file system"
  value = "${aws_fsx_openzfs_file_system.intelligent_tiering.dns_name}:/"
}

# Lambda Function Outputs
output "lifecycle_policy_function_arn" {
  description = "ARN of the lifecycle policy Lambda function"
  value       = aws_lambda_function.lifecycle_policy.arn
}

output "lifecycle_policy_function_name" {
  description = "Name of the lifecycle policy Lambda function"
  value       = aws_lambda_function.lifecycle_policy.function_name
}

output "cost_reporting_function_arn" {
  description = "ARN of the cost reporting Lambda function"
  value       = aws_lambda_function.cost_reporting.arn
}

output "cost_reporting_function_name" {
  description = "Name of the cost reporting Lambda function"
  value       = aws_lambda_function.cost_reporting.function_name
}

output "alert_handler_function_arn" {
  description = "ARN of the alert handler Lambda function"
  value       = aws_lambda_function.alert_handler.arn
}

output "alert_handler_function_name" {
  description = "Name of the alert handler Lambda function"
  value       = aws_lambda_function.alert_handler.function_name
}

# S3 Bucket Outputs
output "s3_reports_bucket_name" {
  description = "Name of the S3 bucket for FSx reports"
  value       = aws_s3_bucket.fsx_reports.bucket
}

output "s3_reports_bucket_arn" {
  description = "ARN of the S3 bucket for FSx reports"
  value       = aws_s3_bucket.fsx_reports.arn
}

output "s3_reports_bucket_domain_name" {
  description = "Domain name of the S3 bucket for FSx reports"
  value       = aws_s3_bucket.fsx_reports.bucket_domain_name
}

# SNS Topic Outputs
output "sns_alerts_topic_arn" {
  description = "ARN of the SNS topic for FSx alerts"
  value       = aws_sns_topic.fsx_alerts.arn
}

output "sns_alerts_topic_name" {
  description = "Name of the SNS topic for FSx alerts"
  value       = aws_sns_topic.fsx_alerts.name
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.fsx_lifecycle_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.fsx_lifecycle_dashboard.dashboard_name}"
}

# EventBridge Rules Outputs
output "lifecycle_policy_schedule_rule_name" {
  description = "Name of the EventBridge rule for lifecycle policy checks"
  value       = aws_cloudwatch_event_rule.lifecycle_policy_schedule.name
}

output "cost_reporting_schedule_rule_name" {
  description = "Name of the EventBridge rule for cost reporting"
  value       = aws_cloudwatch_event_rule.cost_reporting_schedule.name
}

# Security Group Outputs
output "fsx_security_group_id" {
  description = "ID of the security group for FSx"
  value       = aws_security_group.fsx.id
}

output "lambda_security_group_id" {
  description = "ID of the security group for Lambda functions"
  value       = aws_security_group.lambda.id
}

# KMS Key Outputs (when encryption is enabled)
output "fsx_kms_key_id" {
  description = "ID of the KMS key for FSx encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.fsx[0].id : null
}

output "fsx_kms_key_arn" {
  description = "ARN of the KMS key for FSx encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.fsx[0].arn : null
}

output "s3_kms_key_id" {
  description = "ID of the KMS key for S3 encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.s3[0].id : null
}

output "logs_kms_key_id" {
  description = "ID of the KMS key for CloudWatch Logs encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.logs[0].id : null
}

output "sns_kms_key_id" {
  description = "ID of the KMS key for SNS encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.sns[0].id : null
}

# CloudWatch Alarm Outputs
output "storage_utilization_alarm_name" {
  description = "Name of the storage utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.fsx_storage_utilization.alarm_name
}

output "cache_hit_ratio_alarm_name" {
  description = "Name of the cache hit ratio CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.fsx_cache_hit_ratio.alarm_name
}

output "lambda_error_rate_alarm_name" {
  description = "Name of the Lambda error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_error_rate.alarm_name
}

# IAM Role Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# Networking Information
output "vpc_id" {
  description = "ID of the VPC where resources are deployed"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet where FSx is deployed"
  value       = local.subnet_id
}

# Cost Information
output "estimated_monthly_cost_breakdown" {
  description = "Estimated monthly cost breakdown for the solution"
  value = {
    fsx_storage = {
      description = "FSx storage and throughput costs"
      storage_gb = var.fsx_storage_capacity
      throughput_mbps = var.fsx_throughput_capacity
      estimated_monthly_usd = "Varies by region and usage patterns"
    }
    lambda = {
      description = "Lambda function execution costs"
      estimated_monthly_usd = "Minimal - based on execution frequency and duration"
    }
    cloudwatch = {
      description = "CloudWatch logs, metrics, and alarms"
      estimated_monthly_usd = "5-15 USD depending on log retention"
    }
    s3 = {
      description = "S3 storage for reports"
      estimated_monthly_usd = "1-5 USD depending on report volume"
    }
    data_transfer = {
      description = "Data transfer and API calls"
      estimated_monthly_usd = "Minimal - based on usage patterns"
    }
  }
}

# Management Information
output "deployment_information" {
  description = "Key information about the deployed infrastructure"
  value = {
    project_name = var.project_name
    environment = var.environment
    aws_region = data.aws_region.current.name
    deployment_timestamp = timestamp()
    resource_prefix = local.resource_prefix
    intelligent_tiering_enabled = var.enable_intelligent_tiering
    kms_encryption_enabled = var.enable_kms_encryption
  }
}

# Operations Information
output "operational_commands" {
  description = "Useful operational commands for managing the solution"
  value = {
    test_lambda_lifecycle_policy = "aws lambda invoke --function-name ${aws_lambda_function.lifecycle_policy.function_name} --payload '{}' response.json"
    test_lambda_cost_reporting = "aws lambda invoke --function-name ${aws_lambda_function.cost_reporting.function_name} --payload '{}' response.json"
    view_fsx_metrics = "aws logs tail /aws/fsx/openzfs --follow"
    list_s3_reports = "aws s3 ls s3://${aws_s3_bucket.fsx_reports.bucket}/cost-reports/ --recursive"
    check_alarm_states = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.fsx_storage_utilization.alarm_name} ${aws_cloudwatch_metric_alarm.fsx_cache_hit_ratio.alarm_name}"
  }
}

# Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and managing the solution"
  value = {
    cloudwatch_dashboard = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.fsx_lifecycle_dashboard.dashboard_name}"
    fsx_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/fsx/home?region=${data.aws_region.current.name}#file-systems/${aws_fsx_openzfs_file_system.intelligent_tiering.id}"
    lambda_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions"
    s3_reports_console = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.fsx_reports.bucket}?region=${data.aws_region.current.name}"
  }
}