# S3 bucket outputs
output "input_bucket_name" {
  description = "Name of the S3 bucket for input data"
  value       = aws_s3_bucket.input_bucket.bucket
}

output "input_bucket_arn" {
  description = "ARN of the S3 bucket for input data"
  value       = aws_s3_bucket.input_bucket.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for output data"
  value       = aws_s3_bucket.output_bucket.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for output data"
  value       = aws_s3_bucket.output_bucket.arn
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for text processing"
  value       = aws_lambda_function.comprehend_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for text processing"
  value       = aws_lambda_function.comprehend_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.comprehend_processor.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.comprehend_processor.version
}

# IAM role outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "comprehend_service_role_arn" {
  description = "ARN of the Comprehend service role for batch jobs"
  value       = aws_iam_role.comprehend_service_role.arn
}

output "comprehend_service_role_name" {
  description = "Name of the Comprehend service role for batch jobs"
  value       = aws_iam_role.comprehend_service_role.name
}

# CloudWatch outputs
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# KMS outputs (conditional)
output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.comprehend_key[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_key.comprehend_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption (if enabled)"
  value       = var.enable_kms_encryption ? aws_kms_alias.comprehend_key_alias[0].name : null
}

# SNS outputs (conditional)
output "notification_topic_arn" {
  description = "ARN of the SNS topic for notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : null
}

output "notification_topic_name" {
  description = "Name of the SNS topic for notifications (if enabled)"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].name : null
}

# CloudWatch alarm outputs (conditional)
output "lambda_error_alarm_name" {
  description = "Name of the Lambda error CloudWatch alarm (if monitoring enabled)"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "lambda_duration_alarm_name" {
  description = "Name of the Lambda duration CloudWatch alarm (if monitoring enabled)"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name : null
}

# Test and usage outputs
output "test_lambda_command" {
  description = "AWS CLI command to test the Lambda function"
  value = <<-EOT
aws lambda invoke \
  --function-name ${aws_lambda_function.comprehend_processor.function_name} \
  --payload '{"text": "I love this product! The quality is amazing and delivery was fast.", "output_bucket": "${aws_s3_bucket.output_bucket.bucket}"}' \
  --cli-binary-format raw-in-base64-out \
  response.json
EOT
}

output "upload_test_file_command" {
  description = "AWS CLI command to upload a test file to trigger processing"
  value = <<-EOT
echo "This is a sample text for sentiment analysis. The service quality was excellent!" > sample.txt
aws s3 cp sample.txt s3://${aws_s3_bucket.input_bucket.bucket}/input/sample.txt
EOT
}

output "view_results_command" {
  description = "AWS CLI command to view processing results"
  value = "aws s3 ls s3://${aws_s3_bucket.output_bucket.bucket}/processed/ --recursive"
}

# Resource summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    input_bucket          = aws_s3_bucket.input_bucket.bucket
    output_bucket         = aws_s3_bucket.output_bucket.bucket
    lambda_function       = aws_lambda_function.comprehend_processor.function_name
    lambda_role           = aws_iam_role.lambda_execution_role.name
    comprehend_role       = aws_iam_role.comprehend_service_role.name
    log_group            = aws_cloudwatch_log_group.lambda_logs.name
    kms_encryption       = var.enable_kms_encryption
    monitoring_enabled   = var.enable_detailed_monitoring
    notification_email   = var.notification_email != "" ? var.notification_email : "not configured"
    custom_classification = var.enable_custom_classification
  }
}

# Cost estimation outputs
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    lambda_requests_1m     = "$0.20 (for 1M requests)"
    lambda_duration_gb_sec = "$0.0000166667 per GB-second"
    s3_storage_standard    = "$0.023 per GB"
    comprehend_requests    = "$0.0001 per request (first 10M requests)"
    cloudwatch_logs        = "$0.50 per GB ingested"
    kms_requests          = "$0.03 per 10,000 requests (if enabled)"
    note                  = "Actual costs depend on usage volume and data retention"
  }
}

# Quick start instructions
output "quick_start_instructions" {
  description = "Quick start instructions for using the NLP pipeline"
  value = <<-EOT

Quick Start Instructions:
========================

1. Test the Lambda function directly:
   ${local.name_prefix}_test_text="I love this amazing product! Great quality and fast delivery."
   aws lambda invoke \
     --function-name ${aws_lambda_function.comprehend_processor.function_name} \
     --payload "{\"text\": \"$${local.name_prefix}_test_text\", \"output_bucket\": \"${aws_s3_bucket.output_bucket.bucket}\"}" \
     --cli-binary-format raw-in-base64-out \
     response.json

2. Upload a file to trigger automatic processing:
   echo "Customer feedback: The service was excellent and staff very helpful!" > feedback.txt
   aws s3 cp feedback.txt s3://${aws_s3_bucket.input_bucket.bucket}/input/

3. View processing results:
   aws s3 ls s3://${aws_s3_bucket.output_bucket.bucket}/processed/ --recursive

4. Download and view a result file:
   RESULT_KEY=$(aws s3 ls s3://${aws_s3_bucket.output_bucket.bucket}/processed/ --recursive | head -1 | awk '{print $4}')
   aws s3 cp s3://${aws_s3_bucket.output_bucket.bucket}/$RESULT_KEY result.json
   cat result.json | jq .

5. For batch processing, prepare data in one-doc-per-line format and upload to input bucket, then use Comprehend batch APIs.

EOT
}