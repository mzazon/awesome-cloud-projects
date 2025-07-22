# Output values for the custom CloudFormation resources infrastructure

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.random_suffix
}

# S3 Bucket Outputs
output "demo_bucket_name" {
  description = "Name of the S3 bucket used for custom resource data"
  value       = aws_s3_bucket.demo_bucket.id
}

output "demo_bucket_arn" {
  description = "ARN of the S3 bucket used for custom resource data"
  value       = aws_s3_bucket.demo_bucket.arn
}

output "demo_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.demo_bucket.bucket_domain_name
}

output "standard_bucket_name" {
  description = "Name of the standard S3 bucket for comparison"
  value       = aws_s3_bucket.standard_bucket.id
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the basic custom resource Lambda function"
  value       = aws_lambda_function.custom_resource_handler.function_name
}

output "lambda_function_arn" {
  description = "ARN of the basic custom resource Lambda function"
  value       = aws_lambda_function.custom_resource_handler.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the basic custom resource Lambda function"
  value       = aws_lambda_function.custom_resource_handler.invoke_arn
}

output "advanced_lambda_function_name" {
  description = "Name of the advanced custom resource Lambda function"
  value       = var.enable_advanced_error_handling ? aws_lambda_function.advanced_custom_resource_handler[0].function_name : null
}

output "advanced_lambda_function_arn" {
  description = "ARN of the advanced custom resource Lambda function"
  value       = var.enable_advanced_error_handling ? aws_lambda_function.advanced_custom_resource_handler[0].arn : null
}

# IAM Role Outputs
output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_s3_policy_arn" {
  description = "ARN of the custom S3 access policy for Lambda"
  value       = aws_iam_policy.lambda_s3_policy.arn
}

# CloudWatch Logs Outputs
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for basic Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for basic Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "advanced_lambda_log_group_name" {
  description = "Name of the CloudWatch log group for advanced Lambda function"
  value       = var.enable_advanced_error_handling ? aws_cloudwatch_log_group.advanced_lambda_logs[0].name : null
}

# CloudFormation Stack Outputs
output "cloudformation_stack_name" {
  description = "Name of the CloudFormation stack with custom resources"
  value       = aws_cloudformation_stack.custom_resource_demo.name
}

output "cloudformation_stack_id" {
  description = "ID of the CloudFormation stack with custom resources"
  value       = aws_cloudformation_stack.custom_resource_demo.id
}

output "cloudformation_stack_outputs" {
  description = "Outputs from the CloudFormation stack"
  value       = aws_cloudformation_stack.custom_resource_demo.outputs
}

output "production_stack_name" {
  description = "Name of the production CloudFormation stack"
  value       = var.enable_production_template ? aws_cloudformation_stack.production_custom_resource[0].name : null
}

output "production_stack_outputs" {
  description = "Outputs from the production CloudFormation stack"
  value       = var.enable_production_template ? aws_cloudformation_stack.production_custom_resource[0].outputs : null
}

# Custom Resource Data Outputs
output "data_file_name" {
  description = "Name of the data file created by custom resource"
  value       = var.data_file_name
}

output "custom_data_content" {
  description = "JSON content configured for the custom resource"
  value       = var.custom_data_content
}

output "data_url" {
  description = "URL of the data file created by custom resource"
  value       = "https://${aws_s3_bucket.demo_bucket.bucket_domain_name}/${var.data_file_name}"
}

# Environment and Configuration Outputs
output "environment" {
  description = "Environment name used for resource deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "lambda_runtime" {
  description = "Python runtime version used for Lambda functions"
  value       = var.lambda_runtime
}

output "lambda_timeout" {
  description = "Timeout configured for Lambda functions"
  value       = var.lambda_timeout
}

output "lambda_memory_size" {
  description = "Memory allocation for Lambda functions"
  value       = var.lambda_memory_size
}

# Security and Access Outputs
output "s3_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.s3_versioning_enabled
}

output "log_retention_days" {
  description = "CloudWatch logs retention period in days"
  value       = var.log_retention_days
}

# Feature Flags Outputs
output "advanced_error_handling_enabled" {
  description = "Whether advanced error handling Lambda function is deployed"
  value       = var.enable_advanced_error_handling
}

output "production_template_enabled" {
  description = "Whether production CloudFormation template is deployed"
  value       = var.enable_production_template
}

# Validation and Testing Outputs
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = [
    "aws s3 ls s3://${aws_s3_bucket.demo_bucket.id}/",
    "aws cloudformation describe-stacks --stack-name ${aws_cloudformation_stack.custom_resource_demo.name}",
    "aws lambda get-function --function-name ${aws_lambda_function.custom_resource_handler.function_name}",
    "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${local.name_prefix}"
  ]
}

output "monitoring_urls" {
  description = "URLs for monitoring the deployed resources"
  value = {
    cloudformation_console = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudformation/home?region=${data.aws_region.current.name}#/stacks/stackinfo?stackId=${aws_cloudformation_stack.custom_resource_demo.id}"
    lambda_console         = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.custom_resource_handler.function_name}"
    s3_console            = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.demo_bucket.id}"
    cloudwatch_logs       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
  }
}