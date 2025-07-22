# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for DataBrew results"
  value       = aws_s3_bucket.databrew_results.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for DataBrew results"
  value       = aws_s3_bucket.databrew_results.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.databrew_results.bucket_domain_name
}

# IAM Role Information
output "databrew_service_role_arn" {
  description = "ARN of the DataBrew service role"
  value       = aws_iam_role.databrew_service_role.arn
}

output "databrew_service_role_name" {
  description = "Name of the DataBrew service role"
  value       = aws_iam_role.databrew_service_role.name
}

# DataBrew Dataset Information
output "databrew_dataset_name" {
  description = "Name of the DataBrew dataset"
  value       = aws_databrew_dataset.customer_dataset.name
}

output "databrew_dataset_arn" {
  description = "ARN of the DataBrew dataset"
  value       = aws_databrew_dataset.customer_dataset.arn
}

# DataBrew Ruleset Information
output "databrew_ruleset_name" {
  description = "Name of the DataBrew data quality ruleset"
  value       = aws_databrew_ruleset.data_quality_ruleset.name
}

output "databrew_ruleset_arn" {
  description = "ARN of the DataBrew data quality ruleset"
  value       = aws_databrew_ruleset.data_quality_ruleset.arn
}

# DataBrew Profile Job Information
output "databrew_profile_job_name" {
  description = "Name of the DataBrew profile job"
  value       = aws_databrew_job.profile_job.name
}

output "databrew_profile_job_arn" {
  description = "ARN of the DataBrew profile job"
  value       = aws_databrew_job.profile_job.arn
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for data quality alerts"
  value       = aws_sns_topic.data_quality_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for data quality alerts"
  value       = aws_sns_topic.data_quality_alerts.arn
}

# EventBridge Rule Information
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for DataBrew validation events"
  value       = var.eventbridge_rule_config.enabled ? aws_cloudwatch_event_rule.databrew_validation_rule[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for DataBrew validation events"
  value       = var.eventbridge_rule_config.enabled ? aws_cloudwatch_event_rule.databrew_validation_rule[0].arn : null
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for event processing"
  value       = aws_lambda_function.databrew_event_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for event processing"
  value       = aws_lambda_function.databrew_event_processor.arn
}

# CloudWatch Log Group Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DataBrew job logs"
  value       = aws_cloudwatch_log_group.databrew_job_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for DataBrew job logs"
  value       = aws_cloudwatch_log_group.databrew_job_logs.arn
}

# Data Quality Rules Summary
output "data_quality_rules_summary" {
  description = "Summary of configured data quality rules"
  value = {
    total_rules = length(var.data_quality_rules)
    rules = [
      for rule in var.data_quality_rules : {
        name        = rule.name
        description = rule.description
        threshold   = rule.threshold
        disabled    = rule.disabled
      }
    ]
  }
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "random_suffix" {
  description = "Random suffix used for resource names"
  value       = random_string.suffix.result
}

# Resource URLs and Access Information
output "aws_console_urls" {
  description = "AWS Console URLs for easy access to resources"
  value = {
    s3_bucket = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.databrew_results.bucket}"
    databrew_dataset = "https://console.aws.amazon.com/databrew/home?region=${var.aws_region}#datasets/${aws_databrew_dataset.customer_dataset.name}"
    databrew_job = "https://console.aws.amazon.com/databrew/home?region=${var.aws_region}#jobs/${aws_databrew_job.profile_job.name}"
    databrew_ruleset = "https://console.aws.amazon.com/databrew/home?region=${var.aws_region}#rulesets/${aws_databrew_ruleset.data_quality_ruleset.name}"
    sns_topic = "https://console.aws.amazon.com/sns/v3/home?region=${var.aws_region}#/topic/${aws_sns_topic.data_quality_alerts.arn}"
    cloudwatch_logs = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.databrew_job_logs.name, "/", "%2F")}"
    eventbridge_rule = var.eventbridge_rule_config.enabled ? "https://console.aws.amazon.com/events/home?region=${var.aws_region}#/rules/${aws_cloudwatch_event_rule.databrew_validation_rule[0].name}" : null
    lambda_function = "https://console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.databrew_event_processor.function_name}"
  }
}

# CLI Commands for Running the Profile Job
output "cli_commands" {
  description = "AWS CLI commands for common operations"
  value = {
    start_profile_job = "aws databrew start-job-run --name ${aws_databrew_job.profile_job.name} --region ${var.aws_region}"
    list_job_runs = "aws databrew list-job-runs --name ${aws_databrew_job.profile_job.name} --region ${var.aws_region}"
    describe_dataset = "aws databrew describe-dataset --name ${aws_databrew_dataset.customer_dataset.name} --region ${var.aws_region}"
    describe_ruleset = "aws databrew describe-ruleset --name ${aws_databrew_ruleset.data_quality_ruleset.name} --region ${var.aws_region}"
    list_s3_results = "aws s3 ls s3://${aws_s3_bucket.databrew_results.bucket}/profile-results/ --recursive"
    download_results = "aws s3 cp s3://${aws_s3_bucket.databrew_results.bucket}/profile-results/ ./results/ --recursive"
  }
}

# Next Steps Instructions
output "next_steps" {
  description = "Next steps to complete the data quality monitoring setup"
  value = [
    "1. Confirm your email subscription to the SNS topic: ${aws_sns_topic.data_quality_alerts.arn}",
    "2. Upload your actual data files to: s3://${aws_s3_bucket.databrew_results.bucket}/raw-data/",
    "3. Start the profile job using: aws databrew start-job-run --name ${aws_databrew_job.profile_job.name}",
    "4. Monitor job progress in the AWS Console or using CLI commands",
    "5. Review profile results in S3 bucket: s3://${aws_s3_bucket.databrew_results.bucket}/profile-results/",
    "6. Check CloudWatch logs for job execution details: ${aws_cloudwatch_log_group.databrew_job_logs.name}",
    "7. Customize data quality rules as needed for your specific use case"
  ]
}