# ============================================================================
# S3 Outputs
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data and quality reports"
  value       = aws_s3_bucket.data_quality_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data and quality reports"
  value       = aws_s3_bucket.data_quality_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_quality_bucket.bucket_domain_name
}

output "sample_data_key" {
  description = "S3 key for the sample data file"
  value       = var.sample_data_enabled ? aws_s3_object.sample_data[0].key : "No sample data created"
}

# ============================================================================
# DataBrew Outputs
# ============================================================================

output "databrew_dataset_name" {
  description = "Name of the DataBrew dataset"
  value       = aws_databrew_dataset.customer_data.name
}

output "databrew_dataset_arn" {
  description = "ARN of the DataBrew dataset"
  value       = aws_databrew_dataset.customer_data.arn
}

output "databrew_ruleset_name" {
  description = "Name of the DataBrew ruleset"
  value       = aws_databrew_ruleset.customer_quality_rules.name
}

output "databrew_ruleset_arn" {
  description = "ARN of the DataBrew ruleset"
  value       = aws_databrew_ruleset.customer_quality_rules.arn
}

output "databrew_profile_job_name" {
  description = "Name of the DataBrew profile job"
  value       = aws_databrew_profile_job.quality_assessment.name
}

output "databrew_profile_job_arn" {
  description = "ARN of the DataBrew profile job"
  value       = aws_databrew_profile_job.quality_assessment.arn
}

# ============================================================================
# Lambda Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for processing data quality events"
  value       = aws_lambda_function.data_quality_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for processing data quality events"
  value       = aws_lambda_function.data_quality_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.data_quality_processor.invoke_arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}

# ============================================================================
# EventBridge Outputs
# ============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for DataBrew validation events"
  value       = aws_cloudwatch_event_rule.databrew_validation_rule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for DataBrew validation events"
  value       = aws_cloudwatch_event_rule.databrew_validation_rule.arn
}

# ============================================================================
# IAM Outputs
# ============================================================================

output "databrew_service_role_arn" {
  description = "ARN of the DataBrew service role"
  value       = aws_iam_role.databrew_service_role.arn
}

output "databrew_service_role_name" {
  description = "Name of the DataBrew service role"
  value       = aws_iam_role.databrew_service_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# ============================================================================
# SNS Outputs
# ============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if created)"
  value       = var.notification_email != "" ? aws_sns_topic.data_quality_notifications[0].arn : "No SNS topic created"
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications (if created)"
  value       = var.notification_email != "" ? aws_sns_topic.data_quality_notifications[0].name : "No SNS topic created"
}

# ============================================================================
# Configuration Outputs
# ============================================================================

output "data_quality_rules_summary" {
  description = "Summary of data quality rules configured"
  value = {
    email_validation_threshold    = var.email_validation_threshold
    age_validation_threshold     = var.age_validation_threshold
    purchase_amount_threshold    = var.purchase_amount_threshold
    age_min_value               = var.age_min_value
    age_max_value               = var.age_max_value
  }
}

output "databrew_job_configuration" {
  description = "DataBrew job configuration summary"
  value = {
    max_capacity = var.databrew_job_max_capacity
    timeout      = var.databrew_job_timeout
  }
}

# ============================================================================
# Validation and Testing Outputs
# ============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.data_quality_bucket.id}/"
    check_dataset   = "aws databrew describe-dataset --name ${aws_databrew_dataset.customer_data.name}"
    check_ruleset   = "aws databrew describe-ruleset --name ${aws_databrew_ruleset.customer_quality_rules.name}"
    check_job       = "aws databrew describe-profile-job --name ${aws_databrew_profile_job.quality_assessment.name}"
    start_job       = "aws databrew start-job-run --name ${aws_databrew_profile_job.quality_assessment.name}"
  }
}

output "monitoring_commands" {
  description = "Commands for monitoring the pipeline"
  value = {
    lambda_logs    = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/DataQualityProcessor'"
    eventbridge_rule = "aws events describe-rule --name ${aws_cloudwatch_event_rule.databrew_validation_rule.name}"
    s3_reports     = "aws s3 ls s3://${aws_s3_bucket.data_quality_bucket.id}/quality-reports/ --recursive"
  }
}

# ============================================================================
# Resource Summary
# ============================================================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    s3_bucket           = aws_s3_bucket.data_quality_bucket.id
    databrew_dataset    = aws_databrew_dataset.customer_data.name
    databrew_ruleset    = aws_databrew_ruleset.customer_quality_rules.name
    databrew_job        = aws_databrew_profile_job.quality_assessment.name
    lambda_function     = aws_lambda_function.data_quality_processor.function_name
    eventbridge_rule    = aws_cloudwatch_event_rule.databrew_validation_rule.name
    sns_topic          = var.notification_email != "" ? aws_sns_topic.data_quality_notifications[0].name : "None"
    notification_email = var.notification_email != "" ? var.notification_email : "None"
    environment        = var.environment
    region             = var.aws_region
  }
}

# ============================================================================
# Next Steps
# ============================================================================

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Verify S3 bucket was created: aws s3 ls s3://${aws_s3_bucket.data_quality_bucket.id}/",
    "2. Check DataBrew dataset: aws databrew describe-dataset --name ${aws_databrew_dataset.customer_data.name}",
    "3. Start profile job: aws databrew start-job-run --name ${aws_databrew_profile_job.quality_assessment.name}",
    "4. Monitor job progress: aws databrew describe-job-run --name ${aws_databrew_profile_job.quality_assessment.name} --run-id <RUN_ID>",
    "5. Check Lambda logs: aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_log_group.name}",
    "6. Review quality reports: aws s3 ls s3://${aws_s3_bucket.data_quality_bucket.id}/quality-reports/ --recursive",
    var.notification_email != "" ? "7. Confirm SNS subscription via email" : "7. Configure SNS notifications by setting notification_email variable"
  ]
}