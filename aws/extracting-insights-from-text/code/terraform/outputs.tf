# outputs.tf - Output values for the Comprehend NLP solution

# ===============================
# S3 Bucket Outputs
# ===============================

output "input_bucket_name" {
  description = "Name of the S3 bucket for input documents"
  value       = aws_s3_bucket.input_bucket.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for input documents"
  value       = aws_s3_bucket.input_bucket.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for output results"
  value       = aws_s3_bucket.output_bucket.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for output results"
  value       = aws_s3_bucket.output_bucket.arn
}

# ===============================
# Lambda Function Outputs
# ===============================

output "lambda_function_name" {
  description = "Name of the Lambda function for real-time processing"
  value       = aws_lambda_function.comprehend_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for real-time processing"
  value       = aws_lambda_function.comprehend_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.comprehend_processor.invoke_arn
}

output "lambda_function_url" {
  description = "URL to invoke the Lambda function via AWS CLI"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.comprehend_processor.function_name} --payload '{\"text\": \"Your text here\"}' response.json"
}

# ===============================
# IAM Role Outputs
# ===============================

output "comprehend_service_role_arn" {
  description = "ARN of the IAM role for Comprehend service"
  value       = aws_iam_role.comprehend_service_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ===============================
# EventBridge Outputs
# ===============================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for S3 events"
  value       = var.enable_eventbridge_processing ? aws_cloudwatch_event_rule.s3_object_created[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for S3 events"
  value       = var.enable_eventbridge_processing ? aws_cloudwatch_event_rule.s3_object_created[0].arn : null
}

# ===============================
# SNS Topic Outputs
# ===============================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = var.notification_email != "" ? aws_sns_topic.comprehend_notifications[0].arn : null
}

# ===============================
# CloudWatch Outputs
# ===============================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_log_group[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.comprehend_dashboard.dashboard_name}"
}

# ===============================
# Testing and Usage Outputs
# ===============================

output "sample_lambda_test_command" {
  description = "Sample AWS CLI command to test the Lambda function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.comprehend_processor.function_name} --payload '{\"text\": \"This is a sample text for sentiment analysis and entity detection.\"}' /tmp/response.json && cat /tmp/response.json"
}

output "sample_s3_upload_command" {
  description = "Sample AWS CLI command to upload a file to trigger processing"
  value       = "echo 'Your sample text content here' > sample.txt && aws s3 cp sample.txt s3://${aws_s3_bucket.input_bucket.bucket}/input/"
}

output "batch_sentiment_job_command" {
  description = "Sample AWS CLI command to start a batch sentiment analysis job"
  value       = "aws comprehend start-sentiment-detection-job --job-name sentiment-job-$(date +%s) --language-code ${var.comprehend_language_code} --input-data-config 'S3Uri=s3://${aws_s3_bucket.input_bucket.bucket}/input/' --output-data-config 'S3Uri=s3://${aws_s3_bucket.output_bucket.bucket}/sentiment/' --data-access-role-arn ${aws_iam_role.comprehend_service_role.arn}"
}

output "batch_entities_job_command" {
  description = "Sample AWS CLI command to start a batch entity detection job"
  value       = "aws comprehend start-entities-detection-job --job-name entities-job-$(date +%s) --language-code ${var.comprehend_language_code} --input-data-config 'S3Uri=s3://${aws_s3_bucket.input_bucket.bucket}/input/' --output-data-config 'S3Uri=s3://${aws_s3_bucket.output_bucket.bucket}/entities/' --data-access-role-arn ${aws_iam_role.comprehend_service_role.arn}"
}

output "batch_topics_job_command" {
  description = "Sample AWS CLI command to start a batch topic modeling job"
  value       = "aws comprehend start-topics-detection-job --job-name topics-job-$(date +%s) --input-data-config 'S3Uri=s3://${aws_s3_bucket.input_bucket.bucket}/input/' --output-data-config 'S3Uri=s3://${aws_s3_bucket.output_bucket.bucket}/topics/' --data-access-role-arn ${aws_iam_role.comprehend_service_role.arn} --number-of-topics ${var.topics_detection_number}"
}

# ===============================
# Resource Information
# ===============================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    s3_buckets = {
      input_bucket  = aws_s3_bucket.input_bucket.bucket
      output_bucket = aws_s3_bucket.output_bucket.bucket
    }
    lambda_function = {
      name = aws_lambda_function.comprehend_processor.function_name
      arn  = aws_lambda_function.comprehend_processor.arn
    }
    iam_roles = {
      comprehend_service_role = aws_iam_role.comprehend_service_role.arn
      lambda_execution_role   = aws_iam_role.lambda_execution_role.arn
    }
    eventbridge_enabled = var.enable_eventbridge_processing
    notifications_enabled = var.notification_email != ""
    custom_entities_enabled = var.enable_custom_entity_training
  }
}

# ===============================
# Cost Estimation Information
# ===============================

output "cost_estimation_info" {
  description = "Information about potential costs for the deployed resources"
  value = {
    s3_storage = "S3 storage costs depend on the amount of data stored and accessed"
    lambda_costs = "Lambda costs are based on number of invocations and execution time"
    comprehend_costs = "Comprehend costs are based on the amount of text processed (characters)"
    estimated_monthly_cost = "For moderate usage (~1000 documents/month): approximately $10-50"
    cost_optimization_tips = [
      "Use S3 Intelligent Tiering for long-term storage",
      "Monitor Lambda execution time and memory usage",
      "Use batch processing for large volumes to reduce costs",
      "Set up CloudWatch alarms for cost monitoring"
    ]
  }
}

# ===============================
# Next Steps and Documentation
# ===============================

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Test the Lambda function with sample text using the sample_lambda_test_command",
    "2. Upload sample files to S3 input bucket to trigger EventBridge processing",
    "3. Start batch processing jobs for large-scale text analysis",
    "4. Monitor processing results in the CloudWatch dashboard",
    "5. Configure custom entity training if needed for domain-specific entities",
    "6. Set up SNS email notifications for job completion alerts"
  ]
}

output "useful_aws_cli_commands" {
  description = "Useful AWS CLI commands for managing the deployed resources"
  value = {
    list_lambda_functions = "aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `${var.project_name}`)].FunctionName'"
    list_s3_objects = "aws s3 ls s3://${aws_s3_bucket.input_bucket.bucket} --recursive"
    check_comprehend_jobs = "aws comprehend list-sentiment-detection-jobs --max-results 10"
    view_lambda_logs = "aws logs tail /aws/lambda/${aws_lambda_function.comprehend_processor.function_name} --follow"
    download_results = "aws s3 cp s3://${aws_s3_bucket.output_bucket.bucket}/ ./results/ --recursive"
  }
}