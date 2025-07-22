# outputs.tf - Output values for AWS Glue Workflows infrastructure
# This file defines the output values that will be displayed after successful deployment

# S3 Bucket Outputs
output "raw_data_bucket_name" {
  description = "Name of the S3 bucket for raw data storage"
  value       = aws_s3_bucket.raw_data.id
}

output "raw_data_bucket_arn" {
  description = "ARN of the S3 bucket for raw data storage"
  value       = aws_s3_bucket.raw_data.arn
}

output "processed_data_bucket_name" {
  description = "Name of the S3 bucket for processed data storage"
  value       = aws_s3_bucket.processed_data.id
}

output "processed_data_bucket_arn" {
  description = "ARN of the S3 bucket for processed data storage"
  value       = aws_s3_bucket.processed_data.arn
}

# IAM Role Outputs
output "glue_role_name" {
  description = "Name of the IAM role for Glue workflow operations"
  value       = aws_iam_role.glue_role.name
}

output "glue_role_arn" {
  description = "ARN of the IAM role for Glue workflow operations"
  value       = aws_iam_role.glue_role.arn
}

# Glue Database Outputs
output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.workflow_database.name
}

output "glue_database_arn" {
  description = "ARN of the Glue catalog database"
  value       = aws_glue_catalog_database.workflow_database.arn
}

# Glue Crawler Outputs
output "source_crawler_name" {
  description = "Name of the source data crawler"
  value       = aws_glue_crawler.source_crawler.name
}

output "source_crawler_arn" {
  description = "ARN of the source data crawler"
  value       = aws_glue_crawler.source_crawler.arn
}

output "target_crawler_name" {
  description = "Name of the target data crawler"
  value       = aws_glue_crawler.target_crawler.name
}

output "target_crawler_arn" {
  description = "ARN of the target data crawler"
  value       = aws_glue_crawler.target_crawler.arn
}

# Glue Job Outputs
output "etl_job_name" {
  description = "Name of the ETL data processing job"
  value       = aws_glue_job.data_processing.name
}

output "etl_job_arn" {
  description = "ARN of the ETL data processing job"
  value       = aws_glue_job.data_processing.arn
}

# Glue Workflow Outputs
output "workflow_name" {
  description = "Name of the Glue workflow"
  value       = aws_glue_workflow.data_pipeline.name
}

output "workflow_arn" {
  description = "ARN of the Glue workflow"
  value       = aws_glue_workflow.data_pipeline.arn
}

# Glue Trigger Outputs
output "schedule_trigger_name" {
  description = "Name of the schedule trigger"
  value       = aws_glue_trigger.schedule_trigger.name
}

output "schedule_trigger_arn" {
  description = "ARN of the schedule trigger"
  value       = aws_glue_trigger.schedule_trigger.arn
}

output "crawler_success_trigger_name" {
  description = "Name of the crawler success trigger"
  value       = aws_glue_trigger.crawler_success_trigger.name
}

output "crawler_success_trigger_arn" {
  description = "ARN of the crawler success trigger"
  value       = aws_glue_trigger.crawler_success_trigger.arn
}

output "job_success_trigger_name" {
  description = "Name of the job success trigger"
  value       = aws_glue_trigger.job_success_trigger.name
}

output "job_success_trigger_arn" {
  description = "ARN of the job success trigger"
  value       = aws_glue_trigger.job_success_trigger.arn
}

# CloudWatch Outputs (conditional)
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Glue jobs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.glue_jobs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Glue jobs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.glue_jobs[0].arn : null
}

# SNS Outputs (conditional)
output "notification_topic_name" {
  description = "Name of the SNS topic for workflow notifications"
  value       = var.enable_workflow_notifications ? aws_sns_topic.workflow_notifications[0].name : null
}

output "notification_topic_arn" {
  description = "ARN of the SNS topic for workflow notifications"
  value       = var.enable_workflow_notifications ? aws_sns_topic.workflow_notifications[0].arn : null
}

# Deployment Information
output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

# Workflow Management Commands
output "workflow_start_command" {
  description = "AWS CLI command to start the workflow manually"
  value       = "aws glue start-workflow-run --name ${aws_glue_workflow.data_pipeline.name}"
}

output "workflow_status_command" {
  description = "AWS CLI command to check workflow status"
  value       = "aws glue get-workflow-runs --name ${aws_glue_workflow.data_pipeline.name}"
}

output "workflow_stop_command" {
  description = "AWS CLI command to stop a running workflow"
  value       = "aws glue stop-workflow-run --name ${aws_glue_workflow.data_pipeline.name} --run-id <RUN_ID>"
}

# Data Access Information
output "sample_data_location" {
  description = "S3 location of the sample data file"
  value       = "s3://${aws_s3_bucket.raw_data.id}/input/sample-data.csv"
}

output "etl_script_location" {
  description = "S3 location of the ETL script"
  value       = "s3://${aws_s3_bucket.processed_data.id}/scripts/etl-script.py"
}

output "processed_data_location" {
  description = "S3 location where processed data will be stored"
  value       = "s3://${aws_s3_bucket.processed_data.id}/output/"
}

# Monitoring and Troubleshooting
output "glue_console_workflow_url" {
  description = "AWS Console URL for the Glue workflow"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/glue/home?region=${data.aws_region.current.name}#/v2/etl-configuration/workflows/${aws_glue_workflow.data_pipeline.name}"
}

output "cloudwatch_logs_url" {
  description = "AWS Console URL for CloudWatch logs"
  value       = var.enable_cloudwatch_logs ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.glue_jobs[0].name, "/", "$252F")}" : null
}

output "s3_console_raw_data_url" {
  description = "AWS Console URL for raw data S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.raw_data.id}?region=${data.aws_region.current.name}"
}

output "s3_console_processed_data_url" {
  description = "AWS Console URL for processed data S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.processed_data.id}?region=${data.aws_region.current.name}"
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration parameters"
  value = {
    environment           = var.environment
    project_name         = var.project_name
    workflow_schedule    = var.workflow_schedule
    glue_version         = var.glue_version
    max_concurrent_runs  = var.max_concurrent_runs
    job_timeout_minutes  = var.glue_job_timeout
    cloudwatch_logs      = var.enable_cloudwatch_logs
    notifications        = var.enable_workflow_notifications
    bucket_versioning    = var.s3_bucket_versioning
    bucket_encryption    = var.s3_bucket_encryption
  }
}