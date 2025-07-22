# Output values for the Comprehend Custom Entity Recognition and Classification infrastructure
# These outputs provide important information for accessing and managing the deployed resources

output "project_name" {
  description = "The project name used as a prefix for resources"
  value       = var.project_name
}

output "resource_prefix" {
  description = "The generated resource prefix including random suffix"
  value       = local.resource_prefix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing training data and model artifacts"
  value       = aws_s3_bucket.comprehend_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing training data and model artifacts"
  value       = aws_s3_bucket.comprehend_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.comprehend_bucket.bucket_domain_name
}

# IAM Role Information
output "comprehend_role_arn" {
  description = "ARN of the IAM role used by Comprehend, Lambda, and Step Functions"
  value       = aws_iam_role.comprehend_role.arn
}

output "comprehend_role_name" {
  description = "Name of the IAM role used by Comprehend, Lambda, and Step Functions"
  value       = aws_iam_role.comprehend_role.name
}

# Lambda Function Information
output "data_preprocessor_function_name" {
  description = "Name of the data preprocessing Lambda function"
  value       = aws_lambda_function.data_preprocessor.function_name
}

output "data_preprocessor_function_arn" {
  description = "ARN of the data preprocessing Lambda function"
  value       = aws_lambda_function.data_preprocessor.arn
}

output "model_trainer_function_name" {
  description = "Name of the model training Lambda function"
  value       = aws_lambda_function.model_trainer.function_name
}

output "model_trainer_function_arn" {
  description = "ARN of the model training Lambda function"
  value       = aws_lambda_function.model_trainer.arn
}

output "status_checker_function_name" {
  description = "Name of the status checking Lambda function"
  value       = aws_lambda_function.status_checker.function_name
}

output "status_checker_function_arn" {
  description = "ARN of the status checking Lambda function"
  value       = aws_lambda_function.status_checker.arn
}

output "inference_api_function_name" {
  description = "Name of the inference API Lambda function"
  value       = aws_lambda_function.inference_api.function_name
}

output "inference_api_function_arn" {
  description = "ARN of the inference API Lambda function"
  value       = aws_lambda_function.inference_api.arn
}

# Step Functions Information
output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine for training pipeline"
  value       = aws_sfn_state_machine.training_pipeline.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine for training pipeline"
  value       = aws_sfn_state_machine.training_pipeline.name
}

# DynamoDB Information
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for storing inference results"
  value       = aws_dynamodb_table.inference_results.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for storing inference results"
  value       = aws_dynamodb_table.inference_results.arn
}

# API Gateway Information
output "api_gateway_id" {
  description = "ID of the API Gateway for inference endpoints"
  value       = aws_apigatewayv2_api.inference_api.id
}

output "api_gateway_endpoint" {
  description = "HTTP endpoint URL of the API Gateway"
  value       = aws_apigatewayv2_api.inference_api.api_endpoint
}

output "api_gateway_inference_url" {
  description = "Full URL for the inference API endpoint"
  value       = "${aws_apigatewayv2_api.inference_api.api_endpoint}/${var.api_gateway_stage_name}/inference"
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_apigatewayv2_stage.inference_stage.name
}

# CloudWatch Information
output "lambda_log_groups" {
  description = "Names of CloudWatch log groups for Lambda functions"
  value = {
    data_preprocessor = "/aws/lambda/${local.resource_prefix}-data-preprocessor"
    model_trainer     = "/aws/lambda/${local.resource_prefix}-model-trainer"
    status_checker    = "/aws/lambda/${local.resource_prefix}-status-checker"
    inference_api     = "/aws/lambda/${local.resource_prefix}-inference-api"
  }
}

output "step_functions_log_group" {
  description = "Name of CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.step_functions_logs.name
}

output "api_gateway_log_group" {
  description = "Name of CloudWatch log group for API Gateway (if enabled)"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

# Training Data Information
output "training_data_locations" {
  description = "S3 locations of the uploaded training data files"
  value = {
    entity_csv_file     = "s3://${aws_s3_bucket.comprehend_bucket.id}/${aws_s3_object.entity_training_data.key}"
    entity_text_file    = "s3://${aws_s3_bucket.comprehend_bucket.id}/${aws_s3_object.entity_text_file.key}"
    classification_file = "s3://${aws_s3_bucket.comprehend_bucket.id}/${aws_s3_object.classification_training_data.key}"
  }
}

# SNS Information (conditional)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for training notifications (if enabled)"
  value       = var.enable_sns_notifications ? aws_sns_topic.training_notifications[0].arn : null
}

# CloudWatch Dashboard Information (conditional)
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch monitoring dashboard (if enabled)"
  value       = var.enable_monitoring_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.monitoring_dashboard[0].dashboard_name}" : null
}

# Quick Start Commands
output "step_functions_execution_command" {
  description = "AWS CLI command to start the training pipeline"
  value = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.training_pipeline.arn} --name \"training-$(date +%Y%m%d-%H%M%S)\" --region ${data.aws_region.current.name}"
}

output "api_test_command" {
  description = "Example curl command to test the inference API"
  value = "curl -X POST ${aws_apigatewayv2_api.inference_api.api_endpoint}/${var.api_gateway_stage_name}/inference -H \"Content-Type: application/json\" -d '{\"text\": \"Goldman Sachs upgraded Tesla (TSLA) following strong quarterly earnings.\", \"entity_model_arn\": \"ENTITY_MODEL_ARN\", \"classifier_model_arn\": \"CLASSIFIER_MODEL_ARN\"}'"
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Configuration Summary
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    environment                    = var.environment
    aws_region                    = data.aws_region.current.name
    lambda_timeout                = var.lambda_timeout
    lambda_memory_size            = var.lambda_memory_size
    dynamodb_billing_mode         = var.dynamodb_billing_mode
    api_gateway_throttle_rate     = var.api_gateway_throttle_rate_limit
    api_gateway_throttle_burst    = var.api_gateway_throttle_burst_limit
    comprehend_language_code      = var.comprehend_language_code
    s3_versioning_enabled         = var.enable_versioning
    s3_encryption_enabled         = var.enable_encryption
    sns_notifications_enabled     = var.enable_sns_notifications
    monitoring_dashboard_enabled  = var.enable_monitoring_dashboard
    api_gateway_logging_enabled   = var.enable_api_gateway_logging
    cloudwatch_logs_retention     = var.enable_cloudwatch_logs_retention ? var.cloudwatch_logs_retention_days : "No retention"
  }
}

# Cost Estimation Guidance
output "cost_estimation_info" {
  description = "Information for estimating costs of the deployed infrastructure"
  value = {
    message = "Cost depends on usage patterns. Key cost components include:"
    components = [
      "Comprehend custom model training: $3-12 per model training job",
      "Comprehend inference: $0.50-2.00 per 1M characters analyzed",
      "Lambda invocations: First 1M requests/month free, then $0.20 per 1M requests",
      "DynamoDB: Pay-per-request billing, ~$1.25 per million write requests",
      "S3 storage: ~$0.023 per GB per month for Standard storage",
      "API Gateway: $1.00 per million HTTP API requests",
      "CloudWatch Logs: $0.50 per GB ingested"
    ]
    recommendation = "Monitor AWS Cost Explorer and set up billing alerts for cost control"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Upload your own training data to replace the sample data in S3",
    "2. Start the training pipeline using the provided AWS CLI command",
    "3. Monitor training progress in the Step Functions console",
    "4. After training completes (1-4 hours), test the inference API",
    "5. Integrate the API endpoint with your applications",
    "6. Set up CloudWatch alarms for monitoring and alerting",
    "7. Review and adjust API Gateway throttling settings based on usage",
    "8. Consider implementing additional security measures for production use"
  ]
}