# Outputs for Automated Data Analysis with Bedrock AgentCore Runtime
# These outputs provide important information about the deployed infrastructure

output "data_bucket_name" {
  description = "Name of the S3 bucket for uploading datasets"
  value       = aws_s3_bucket.data_bucket.bucket
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket for uploading datasets"
  value       = aws_s3_bucket.data_bucket.arn
}

output "results_bucket_name" {
  description = "Name of the S3 bucket containing analysis results"
  value       = aws_s3_bucket.results_bucket.bucket
}

output "results_bucket_arn" {
  description = "ARN of the S3 bucket containing analysis results"
  value       = aws_s3_bucket.results_bucket.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function that orchestrates data analysis"
  value       = aws_lambda_function.data_analysis_orchestrator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function that orchestrates data analysis"
  value       = aws_lambda_function.data_analysis_orchestrator.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for API Gateway integration"
  value       = aws_lambda_function.data_analysis_orchestrator.invoke_arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard (if enabled)"
  value = var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.data_analysis_dashboard[0].dashboard_name}" : "Dashboard not enabled"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications (if email provided)"
  value       = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : "No notification email configured"
}

# Upload instructions for users
output "upload_instructions" {
  description = "Instructions for uploading datasets to trigger analysis"
  value = <<-EOT
To upload datasets for analysis:

1. Upload files to the data bucket with the datasets/ prefix:
   aws s3 cp your-dataset.csv s3://${aws_s3_bucket.data_bucket.bucket}/datasets/

2. Supported file types:
   - CSV files (.csv)
   - JSON files (.json)
   - Excel files (.xlsx, .xls)
   - Other file types (basic analysis)

3. View analysis results:
   aws s3 ls s3://${aws_s3_bucket.results_bucket.bucket}/analysis-results/

4. Monitor Lambda function logs:
   aws logs tail /aws/lambda/${aws_lambda_function.data_analysis_orchestrator.function_name} --follow

5. Access CloudWatch dashboard:
   ${var.enable_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.data_analysis_dashboard[0].dashboard_name}" : "Dashboard not enabled"}
EOT
}

# Cost optimization information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the deployed infrastructure"
  value = <<-EOT
Cost Optimization Tips:

1. Lambda Function:
   - Current timeout: ${var.lambda_timeout} seconds
   - Current memory: ${var.lambda_memory_size} MB
   - Cost scales with execution time and memory usage

2. S3 Storage:
   - Use S3 Intelligent Tiering for automatic cost optimization
   - Consider lifecycle policies for old analysis results
   - Enable S3 Analytics for usage insights

3. CloudWatch Logs:
   - Current retention: ${var.cloudwatch_log_retention_days} days
   - Reduce retention period if shorter history is acceptable

4. Monitoring:
   - CloudWatch Dashboard: Minimal cost impact
   - Consider disabling dashboard in non-production environments

5. SNS Notifications:
   - ${var.notification_email != "" ? "Email notifications enabled - minimal cost" : "No email notifications - no SNS costs"}

Estimated monthly cost for typical usage (100 analyses/month):
- Lambda: $1-5 (depending on execution time)
- S3: $1-10 (depending on data volume)
- CloudWatch: $1-3 (logs and dashboard)
- Total: ~$3-18/month
EOT
}

# Security information
output "security_configuration" {
  description = "Security features implemented in this deployment"
  value = <<-EOT
Security Configuration:

1. S3 Buckets:
   - Public access blocked: ✅
   - Encryption enabled: ${var.enable_encryption ? "✅" : "❌"}
   - Versioning enabled: ${var.enable_versioning ? "✅" : "❌"}

2. IAM Role:
   - Least privilege principle applied: ✅
   - Bedrock AgentCore permissions: ✅
   - S3 bucket-specific permissions: ✅

3. Lambda Function:
   - Execution role with minimal permissions: ✅
   - Environment variables for configuration: ✅
   - CloudWatch logging enabled: ✅

4. Network Security:
   - Lambda runs in AWS managed VPC: ✅
   - No internet access required: ✅

5. Data Processing:
   - Bedrock AgentCore sandboxed execution: ✅
   - No data persistence in AgentCore: ✅

Recommendations:
- Regularly review IAM permissions
- Monitor CloudWatch logs for security events
- Consider VPC deployment for additional isolation
- Enable AWS CloudTrail for API auditing
EOT
}