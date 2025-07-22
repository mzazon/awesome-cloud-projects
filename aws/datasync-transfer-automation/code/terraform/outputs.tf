# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "source_bucket_name" {
  description = "Name of the source S3 bucket"
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_arn" {
  description = "ARN of the source S3 bucket"
  value       = aws_s3_bucket.source.arn
}

output "destination_bucket_name" {
  description = "Name of the destination S3 bucket"
  value       = aws_s3_bucket.destination.bucket
}

output "destination_bucket_arn" {
  description = "ARN of the destination S3 bucket"
  value       = aws_s3_bucket.destination.arn
}

# ============================================================================
# DataSync Outputs
# ============================================================================

output "datasync_task_arn" {
  description = "ARN of the DataSync task"
  value       = aws_datasync_task.s3_to_s3.arn
}

output "datasync_task_name" {
  description = "Name of the DataSync task"
  value       = aws_datasync_task.s3_to_s3.name
}

output "datasync_source_location_arn" {
  description = "ARN of the DataSync source location"
  value       = aws_datasync_location_s3.source.arn
}

output "datasync_destination_location_arn" {
  description = "ARN of the DataSync destination location"
  value       = aws_datasync_location_s3.destination.arn
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "datasync_service_role_arn" {
  description = "ARN of the DataSync service role"
  value       = aws_iam_role.datasync_service_role.arn
}

output "datasync_service_role_name" {
  description = "Name of the DataSync service role"
  value       = aws_iam_role.datasync_service_role.name
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge role for DataSync execution"
  value       = var.enable_scheduled_execution ? aws_iam_role.eventbridge_datasync_role[0].arn : null
}

# ============================================================================
# CloudWatch Outputs
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DataSync"
  value       = aws_cloudwatch_log_group.datasync.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for DataSync"
  value       = aws_cloudwatch_log_group.datasync.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.datasync_monitoring[0].dashboard_name}" : null
}

# ============================================================================
# EventBridge Outputs
# ============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled execution"
  value       = var.enable_scheduled_execution ? aws_cloudwatch_event_rule.datasync_schedule[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled execution"
  value       = var.enable_scheduled_execution ? aws_cloudwatch_event_rule.datasync_schedule[0].arn : null
}

output "schedule_expression" {
  description = "Schedule expression for automated DataSync execution"
  value       = var.enable_scheduled_execution ? var.schedule_expression : null
}

# ============================================================================
# Task Configuration Outputs
# ============================================================================

output "task_verification_mode" {
  description = "Verification mode configured for the DataSync task"
  value       = var.datasync_verify_mode
}

output "task_transfer_mode" {
  description = "Transfer mode configured for the DataSync task"
  value       = var.datasync_transfer_mode
}

output "task_log_level" {
  description = "Log level configured for the DataSync task"
  value       = var.datasync_log_level
}

output "bandwidth_throttle" {
  description = "Bandwidth throttle setting (bytes per second, -1 for unlimited)"
  value       = var.datasync_bandwidth_throttle
}

# ============================================================================
# Sample Data Outputs
# ============================================================================

output "sample_data_created" {
  description = "Whether sample data was created in the source bucket"
  value       = var.create_sample_data
}

output "source_bucket_sample_objects" {
  description = "List of sample objects created in the source bucket"
  value = var.create_sample_data ? [
    aws_s3_object.sample_file_root[0].key,
    aws_s3_object.sample_file_folder1[0].key,
    aws_s3_object.sample_file_folder2[0].key
  ] : []
}

# ============================================================================
# Quick Start Commands
# ============================================================================

output "start_task_execution_command" {
  description = "AWS CLI command to start DataSync task execution"
  value       = "aws datasync start-task-execution --task-arn ${aws_datasync_task.s3_to_s3.arn} --region ${data.aws_region.current.name}"
}

output "monitor_task_command" {
  description = "AWS CLI command to describe DataSync task"
  value       = "aws datasync describe-task --task-arn ${aws_datasync_task.s3_to_s3.arn} --region ${data.aws_region.current.name}"
}

output "view_logs_command" {
  description = "AWS CLI command to view DataSync logs"
  value       = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.datasync.name} --region ${data.aws_region.current.name}"
}

output "list_source_objects_command" {
  description = "AWS CLI command to list objects in source bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.source.bucket}/ --recursive --region ${data.aws_region.current.name}"
}

output "list_destination_objects_command" {
  description = "AWS CLI command to list objects in destination bucket"
  value       = "aws s3 ls s3://${aws_s3_bucket.destination.bucket}/ --recursive --region ${data.aws_region.current.name}"
}

# ============================================================================
# Resource Summary
# ============================================================================

output "infrastructure_summary" {
  description = "Summary of created infrastructure resources"
  value = {
    s3_buckets = {
      source      = aws_s3_bucket.source.bucket
      destination = aws_s3_bucket.destination.bucket
    }
    datasync = {
      task_arn        = aws_datasync_task.s3_to_s3.arn
      source_location = aws_datasync_location_s3.source.arn
      dest_location   = aws_datasync_location_s3.destination.arn
    }
    monitoring = {
      log_group = aws_cloudwatch_log_group.datasync.name
      dashboard = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.datasync_monitoring[0].dashboard_name : "Not created"
    }
    automation = {
      scheduled_execution = var.enable_scheduled_execution
      schedule_expression = var.enable_scheduled_execution ? var.schedule_expression : "Not configured"
    }
    features = {
      task_reporting      = var.enable_task_reporting
      sample_data_created = var.create_sample_data
      bucket_encryption   = var.enable_bucket_encryption
      bucket_versioning   = var.enable_bucket_versioning
    }
  }
}