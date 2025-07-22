# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for training data"
  value       = aws_s3_bucket.training_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for training data"
  value       = aws_s3_bucket.training_data.arn
}

output "s3_bucket_url" {
  description = "URL of the S3 bucket for training data"
  value       = "https://${aws_s3_bucket.training_data.id}.s3.${data.aws_region.current.name}.amazonaws.com"
}

output "training_data_s3_uri" {
  description = "S3 URI for the training data file"
  value       = "s3://${aws_s3_bucket.training_data.id}/training-data/interactions.csv"
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "personalize_role_arn" {
  description = "ARN of the IAM role for Amazon Personalize"
  value       = aws_iam_role.personalize_role.arn
}

output "personalize_role_name" {
  description = "Name of the IAM role for Amazon Personalize"
  value       = aws_iam_role.personalize_role.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_role.name
}

# ============================================================================
# AMAZON PERSONALIZE OUTPUTS
# ============================================================================

output "dataset_group_name" {
  description = "Name of the Amazon Personalize dataset group"
  value       = local.dataset_group_name
}

output "dataset_group_arn" {
  description = "ARN of the Amazon Personalize dataset group (to be created)"
  value       = "arn:aws:personalize:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dataset-group/${local.dataset_group_name}"
}

output "solution_name" {
  description = "Name of the Amazon Personalize solution"
  value       = local.solution_name
}

output "solution_arn" {
  description = "ARN of the Amazon Personalize solution (to be created)"
  value       = "arn:aws:personalize:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:solution/${local.solution_name}"
}

output "campaign_name" {
  description = "Name of the Amazon Personalize campaign"
  value       = local.campaign_name
}

output "campaign_arn" {
  description = "ARN of the Amazon Personalize campaign (to be created)"
  value       = "arn:aws:personalize:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:campaign/${local.campaign_name}"
}

output "personalize_recipe_arn" {
  description = "ARN of the Amazon Personalize recipe being used"
  value       = var.personalize_recipe_arn
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.recommendation_api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.recommendation_api.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.recommendation_api.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.recommendation_api.version
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ============================================================================
# API GATEWAY OUTPUTS
# ============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.recommendation_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.recommendation_api.name
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.recommendation_api.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.recommendation_api.execution_arn
}

output "api_gateway_url" {
  description = "URL of the API Gateway REST API"
  value       = "https://${aws_api_gateway_rest_api.recommendation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.recommendation_api.stage_name
}

output "api_gateway_deployment_id" {
  description = "ID of the API Gateway deployment"
  value       = aws_api_gateway_deployment.recommendation_api.id
}

# ============================================================================
# API ENDPOINTS
# ============================================================================

output "recommendations_endpoint" {
  description = "Full URL for the recommendations API endpoint"
  value       = "https://${aws_api_gateway_rest_api.recommendation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/recommendations/{userId}"
}

output "api_documentation_url" {
  description = "URL for API documentation (if available)"
  value       = "https://${aws_api_gateway_rest_api.recommendation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/swagger"
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_log_groups" {
  description = "List of CloudWatch log groups created"
  value = concat(
    [aws_cloudwatch_log_group.lambda_logs.name],
    var.enable_api_gateway_logs ? [aws_cloudwatch_log_group.api_gateway_logs[0].name] : []
  )
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarms created"
  value = var.enable_cloudwatch_alarms ? [
    "RecommendationAPI-4xxErrors-${local.resource_suffix}",
    "RecommendationAPI-5xxErrors-${local.resource_suffix}",
    "RecommendationAPI-Latency-${local.resource_suffix}",
    "RecommendationLambda-Errors-${local.resource_suffix}",
    "RecommendationLambda-Duration-${local.resource_suffix}"
  ] : []
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts (if created)"
  value       = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? aws_sns_topic.alerts[0].arn : null
}

# ============================================================================
# SECURITY OUTPUTS
# ============================================================================

output "cors_configuration" {
  description = "CORS configuration for the API"
  value = {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = var.cors_allowed_methods
    allowed_headers = var.cors_allowed_headers
  }
}

output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray_tracing
}

# ============================================================================
# COST OPTIMIZATION OUTPUTS
# ============================================================================

output "s3_lifecycle_policy" {
  description = "S3 lifecycle policy configuration"
  value = var.enable_s3_intelligent_tiering ? {
    enabled                    = true
    transition_to_ia_days     = var.s3_lifecycle_transition_days
    transition_to_glacier_days = 90
  } : null
}

output "lambda_configuration" {
  description = "Lambda function configuration"
  value = {
    runtime     = var.lambda_runtime
    memory_size = var.lambda_memory_size
    timeout     = var.lambda_timeout
  }
}

output "api_gateway_throttling" {
  description = "API Gateway throttling configuration"
  value = {
    rate_limit  = var.api_gateway_throttle_rate_limit
    burst_limit = var.api_gateway_throttle_burst_limit
  }
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    environment                = var.environment
    project_name              = var.project_name
    resource_suffix           = local.resource_suffix
    deployment_region         = data.aws_region.current.name
    s3_bucket                 = aws_s3_bucket.training_data.id
    lambda_function           = aws_lambda_function.recommendation_api.function_name
    api_gateway_id            = aws_api_gateway_rest_api.recommendation_api.id
    api_endpoint              = "https://${aws_api_gateway_rest_api.recommendation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
    monitoring_enabled        = var.enable_cloudwatch_alarms
    xray_tracing_enabled     = var.enable_xray_tracing
    estimated_monthly_cost    = "Low ($10-50 for development, $50-200 for production)"
  }
}

# ============================================================================
# NEXT STEPS
# ============================================================================

output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Create Amazon Personalize dataset group: aws personalize create-dataset-group --name ${local.dataset_group_name}",
    "2. Create dataset schema and import training data from S3: ${aws_s3_bucket.training_data.id}/training-data/interactions.csv",
    "3. Create Personalize solution using recipe: ${var.personalize_recipe_arn}",
    "4. Train the model and create solution version (this takes 60-90 minutes)",
    "5. Deploy campaign for real-time inference: aws personalize create-campaign --name ${local.campaign_name}",
    "6. Test the API endpoint: ${output.recommendations_endpoint.value}",
    "7. Monitor performance using CloudWatch dashboards and alarms",
    "8. Set up CI/CD pipeline for automated deployments",
    "9. Configure custom domain name for the API (optional)",
    "10. Implement request/response caching for better performance (optional)"
  ]
}

# ============================================================================
# TESTING COMMANDS
# ============================================================================

output "testing_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    test_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.training_data.id}/training-data/"
    test_lambda    = "aws lambda invoke --function-name ${aws_lambda_function.recommendation_api.function_name} --payload '{\"pathParameters\":{\"userId\":\"user1\"},\"queryStringParameters\":{\"numResults\":\"5\"}}' response.json"
    test_api       = "curl -X GET 'https://${aws_api_gateway_rest_api.recommendation_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/recommendations/user1?numResults=5'"
    view_logs      = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
  }
}

# ============================================================================
# CLEANUP COMMANDS
# ============================================================================

output "cleanup_commands" {
  description = "Commands to clean up resources (use with caution)"
  value = {
    terraform_destroy = "terraform destroy"
    manual_cleanup = [
      "Delete Personalize campaign: aws personalize delete-campaign --campaign-arn ${output.campaign_arn.value}",
      "Delete Personalize solution: aws personalize delete-solution --solution-arn ${output.solution_arn.value}",
      "Delete Personalize dataset group: aws personalize delete-dataset-group --dataset-group-arn ${output.dataset_group_arn.value}",
      "Empty S3 bucket: aws s3 rm s3://${aws_s3_bucket.training_data.id} --recursive"
    ]
  }
}