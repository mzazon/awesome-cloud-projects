# Outputs for Interactive Data Analytics with Bedrock AgentCore Code Interpreter

# ============================================================================
# INFRASTRUCTURE IDENTIFIERS
# ============================================================================

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "unique_suffix" {
  description = "Unique suffix used for resource names"
  value       = random_id.suffix.hex
}

# ============================================================================
# S3 STORAGE RESOURCES
# ============================================================================

output "s3_bucket_raw_data" {
  description = "Name of the S3 bucket for raw data input"
  value       = aws_s3_bucket.raw_data.bucket
}

output "s3_bucket_raw_data_arn" {
  description = "ARN of the S3 bucket for raw data input"
  value       = aws_s3_bucket.raw_data.arn
}

output "s3_bucket_results" {
  description = "Name of the S3 bucket for analysis results"
  value       = aws_s3_bucket.results.bucket
}

output "s3_bucket_results_arn" {
  description = "ARN of the S3 bucket for analysis results"
  value       = aws_s3_bucket.results.arn
}

output "s3_raw_data_upload_url" {
  description = "S3 console URL for uploading raw data"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.raw_data.bucket}?region=${data.aws_region.current.name}&tab=objects"
}

output "s3_results_view_url" {
  description = "S3 console URL for viewing analysis results"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.results.bucket}?region=${data.aws_region.current.name}&tab=objects"
}

# ============================================================================
# COMPUTE AND AI RESOURCES
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda orchestration function"
  value       = aws_lambda_function.orchestrator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda orchestration function"
  value       = aws_lambda_function.orchestrator.arn
}

output "lambda_function_url" {
  description = "AWS console URL for the Lambda function"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.orchestrator.function_name}"
}

output "code_interpreter_id" {
  description = "ID of the Bedrock AgentCore Code Interpreter"
  value       = local.code_interpreter_id
}

output "code_interpreter_name" {
  description = "Name of the Bedrock AgentCore Code Interpreter"
  value       = local.code_interpreter
}

output "code_interpreter_arn" {
  description = "ARN of the Bedrock AgentCore Code Interpreter (Note: Created via CLI)"
  value       = "arn:aws:bedrock-agentcore:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:code-interpreter/${local.code_interpreter_id}"
}

output "bedrock_console_url" {
  description = "AWS console URL for Bedrock AgentCore"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/bedrock/home?region=${data.aws_region.current.name}#/agentcore"
}

# ============================================================================
# IAM AND SECURITY
# ============================================================================

output "execution_role_name" {
  description = "Name of the IAM execution role"
  value       = aws_iam_role.execution_role.name
}

output "execution_role_arn" {
  description = "ARN of the IAM execution role"
  value       = aws_iam_role.execution_role.arn
}

output "analytics_policy_arn" {
  description = "ARN of the custom analytics IAM policy"
  value       = aws_iam_policy.analytics_policy.arn
}

# ============================================================================
# MESSAGING AND QUEUING
# ============================================================================

output "dead_letter_queue_name" {
  description = "Name of the SQS dead letter queue"
  value       = aws_sqs_queue.dlq.name
}

output "dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.dlq.url
}

output "dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}

# ============================================================================
# MONITORING AND LOGGING
# ============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.analytics.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.analytics.dashboard_name}"
}

output "lambda_log_group_name" {
  description = "Name of the Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "code_interpreter_log_group_name" {
  description = "Name of the Code Interpreter CloudWatch log group"
  value       = aws_cloudwatch_log_group.code_interpreter_logs.name
}

output "cloudwatch_logs_url" {
  description = "URL to view CloudWatch logs"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names"
  value = [
    aws_cloudwatch_metric_alarm.execution_errors.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_duration.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
  ]
}

# ============================================================================
# API GATEWAY (CONDITIONAL)
# ============================================================================

output "api_gateway_enabled" {
  description = "Whether API Gateway is enabled"
  value       = var.enable_api_gateway
}

output "api_gateway_id" {
  description = "ID of the API Gateway (if enabled)"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.analytics[0].id : null
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint (if enabled)"
  value       = var.enable_api_gateway ? "${aws_api_gateway_rest_api.analytics[0].execution_arn}/prod/analytics" : null
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway (if enabled)"
  value       = var.enable_api_gateway ? "https://${aws_api_gateway_rest_api.analytics[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/analytics" : null
}

output "api_gateway_console_url" {
  description = "AWS console URL for API Gateway (if enabled)"
  value       = var.enable_api_gateway ? "https://${data.aws_region.current.name}.console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.analytics[0].id}" : null
}

# ============================================================================
# TESTING AND VALIDATION
# ============================================================================

output "test_lambda_command" {
  description = "AWS CLI command to test the Lambda function"
  value = "aws lambda invoke --function-name ${aws_lambda_function.orchestrator.function_name} --payload '{\"query\": \"Analyze the sales data and provide insights\"}' --cli-binary-format raw-in-base64-out response.json && cat response.json"
}

output "sample_api_request" {
  description = "Sample curl command to test the API (if enabled)"
  value = var.enable_api_gateway ? "curl -X POST https://${aws_api_gateway_rest_api.analytics[0].id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/analytics -H 'Content-Type: application/json' -d '{\"query\": \"Calculate total sales by region\"}'" : "API Gateway not enabled"
}

output "upload_sample_data_command" {
  description = "AWS CLI command to upload sample data"
  value = "aws s3 cp sample_data.csv s3://${aws_s3_bucket.raw_data.bucket}/datasets/"
}

# ============================================================================
# COST INFORMATION
# ============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (USD)"
  value = {
    lambda_executions = "~$5-15 (depends on usage)"
    bedrock_inference = "$10-30 (depends on model usage)"
    s3_storage        = "$1-5 (depends on data size)"
    cloudwatch_logs   = "$1-3 (depends on log volume)"
    api_gateway       = var.enable_api_gateway ? "$3-10 (depends on requests)" : "Not applicable"
    total_estimated   = "$20-65 per month for moderate usage"
  }
}

# ============================================================================
# CONFIGURATION SUMMARY
# ============================================================================

output "configuration_summary" {
  description = "Summary of key configuration parameters"
  value = {
    lambda_timeout              = "${var.lambda_timeout} seconds"
    lambda_memory               = "${var.lambda_memory_size} MB"
    lambda_reserved_concurrency = var.lambda_reserved_concurrency
    s3_lifecycle_transition     = "${var.s3_lifecycle_transition_days} days to IA"
    s3_glacier_transition       = "${var.s3_glacier_transition_days} days to Glacier"
    s3_results_expiration       = "${var.s3_results_expiration_days} days"
    log_retention               = "${var.cloudwatch_log_retention_days} days"
    api_gateway_enabled         = var.enable_api_gateway
    xray_tracing_enabled        = var.enable_xray_tracing
    detailed_monitoring_enabled = var.enable_detailed_monitoring
  }
}

# ============================================================================
# USEFUL LINKS AND COMMANDS
# ============================================================================

output "useful_links" {
  description = "Useful AWS console links and commands"
  value = {
    bedrock_console     = "https://${data.aws_region.current.name}.console.aws.amazon.com/bedrock/home?region=${data.aws_region.current.name}"
    lambda_console      = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}"
    s3_console          = "https://s3.console.aws.amazon.com/s3/buckets?region=${data.aws_region.current.name}"
    cloudwatch_console  = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}"
    iam_console         = "https://console.aws.amazon.com/iam/home"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload sample data to S3 bucket: ${aws_s3_bucket.raw_data.bucket}",
    "2. Test Lambda function using the test command provided",
    "3. Monitor execution through CloudWatch dashboard: ${aws_cloudwatch_dashboard.analytics.dashboard_name}",
    "4. Review CloudWatch logs for detailed execution information",
    var.enable_api_gateway ? "5. Test API Gateway endpoint using the sample curl command" : "5. Consider enabling API Gateway for external access",
    "6. Customize analytics queries based on your specific data requirements",
    "7. Set up additional CloudWatch alarms for production monitoring"
  ]
}