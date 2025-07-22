# Outputs for Video Content Analysis Infrastructure

# S3 Bucket Outputs
output "source_bucket_name" {
  description = "Name of the S3 bucket for source videos"
  value       = aws_s3_bucket.source_bucket.bucket
}

output "source_bucket_arn" {
  description = "ARN of the S3 bucket for source videos"
  value       = aws_s3_bucket.source_bucket.arn
}

output "results_bucket_name" {
  description = "Name of the S3 bucket for analysis results"
  value       = aws_s3_bucket.results_bucket.bucket
}

output "results_bucket_arn" {
  description = "ARN of the S3 bucket for analysis results"
  value       = aws_s3_bucket.results_bucket.arn
}

output "temp_bucket_name" {
  description = "Name of the S3 bucket for temporary files"
  value       = aws_s3_bucket.temp_bucket.bucket
}

output "temp_bucket_arn" {
  description = "ARN of the S3 bucket for temporary files"
  value       = aws_s3_bucket.temp_bucket.arn
}

# DynamoDB Outputs
output "analysis_table_name" {
  description = "Name of the DynamoDB table for analysis results"
  value       = aws_dynamodb_table.analysis_table.name
}

output "analysis_table_arn" {
  description = "ARN of the DynamoDB table for analysis results"
  value       = aws_dynamodb_table.analysis_table.arn
}

# Lambda Function Outputs
output "init_function_name" {
  description = "Name of the initialization Lambda function"
  value       = aws_lambda_function.init_function.function_name
}

output "init_function_arn" {
  description = "ARN of the initialization Lambda function"
  value       = aws_lambda_function.init_function.arn
}

output "moderation_function_name" {
  description = "Name of the content moderation Lambda function"
  value       = aws_lambda_function.moderation_function.function_name
}

output "moderation_function_arn" {
  description = "ARN of the content moderation Lambda function"
  value       = aws_lambda_function.moderation_function.arn
}

output "segment_function_name" {
  description = "Name of the segment detection Lambda function"
  value       = aws_lambda_function.segment_function.function_name
}

output "segment_function_arn" {
  description = "ARN of the segment detection Lambda function"
  value       = aws_lambda_function.segment_function.arn
}

output "aggregation_function_name" {
  description = "Name of the aggregation Lambda function"
  value       = aws_lambda_function.aggregation_function.function_name
}

output "aggregation_function_arn" {
  description = "ARN of the aggregation Lambda function"
  value       = aws_lambda_function.aggregation_function.arn
}

output "trigger_function_name" {
  description = "Name of the trigger Lambda function"
  value       = aws_lambda_function.trigger_function.function_name
}

output "trigger_function_arn" {
  description = "ARN of the trigger Lambda function"
  value       = aws_lambda_function.trigger_function.arn
}

# Step Functions Outputs
output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.video_analysis_workflow.name
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.video_analysis_workflow.arn
}

# SNS and SQS Outputs
output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.analysis_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.analysis_notifications.arn
}

output "sqs_queue_name" {
  description = "Name of the SQS queue for notifications"
  value       = aws_sqs_queue.analysis_queue.name
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for notifications"
  value       = aws_sqs_queue.analysis_queue.url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue for notifications"
  value       = aws_sqs_queue.analysis_queue.arn
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.video_analysis_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.video_analysis_dashboard.dashboard_name}"
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the video analysis system"
  value = <<-EOT
    Video Content Analysis System Deployed Successfully!
    
    To use the system:
    1. Upload video files to: s3://${aws_s3_bucket.source_bucket.bucket}/
    2. Monitor progress in CloudWatch Dashboard: ${aws_cloudwatch_dashboard.video_analysis_dashboard.dashboard_name}
    3. View results in: s3://${aws_s3_bucket.results_bucket.bucket}/analysis-results/
    4. Check job status in DynamoDB table: ${aws_dynamodb_table.analysis_table.name}
    
    Supported video formats: .mp4, .avi, .mov, .mkv, .wmv
    
    Example upload command:
    aws s3 cp your-video.mp4 s3://${aws_s3_bucket.source_bucket.bucket}/
  EOT
}

# Cost Optimization Tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs"
  value = <<-EOT
    Cost Optimization Tips:
    
    1. Use S3 lifecycle policies to transition old results to cheaper storage classes
    2. Set appropriate retention policies for CloudWatch logs
    3. Monitor DynamoDB capacity utilization and consider auto-scaling
    4. Use Reserved Capacity for predictable workloads
    5. Regular cleanup of temporary files in ${aws_s3_bucket.temp_bucket.bucket}
    
    Current Configuration:
    - S3 Lifecycle: Objects transition to IA after ${var.s3_lifecycle_transition_days} days
    - CloudWatch Logs: Retained for ${var.cloudwatch_log_retention_days} days
    - DynamoDB: Provisioned capacity (${var.dynamodb_read_capacity} RCU, ${var.dynamodb_write_capacity} WCU)
  EOT
}