# =============================================================================
# Outputs for Amazon Personalize Recommendation System
# =============================================================================

# General Infrastructure Outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = local.region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = local.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# =============================================================================
# S3 Storage Outputs
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing training data and batch output"
  value       = aws_s3_bucket.personalize_data.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing training data and batch output"
  value       = aws_s3_bucket.personalize_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.personalize_data.bucket_domain_name
}

output "s3_training_data_prefix" {
  description = "S3 prefix for training data files"
  value       = "s3://${aws_s3_bucket.personalize_data.id}/training-data/"
}

output "s3_batch_output_prefix" {
  description = "S3 prefix for batch inference output"
  value       = "s3://${aws_s3_bucket.personalize_data.id}/batch-output/"
}

output "s3_metadata_prefix" {
  description = "S3 prefix for metadata files"
  value       = "s3://${aws_s3_bucket.personalize_data.id}/metadata/"
}

# =============================================================================
# IAM Role Outputs
# =============================================================================

output "personalize_service_role_arn" {
  description = "ARN of the IAM role for Amazon Personalize service"
  value       = aws_iam_role.personalize_service_role.arn
}

output "personalize_service_role_name" {
  description = "Name of the IAM role for Amazon Personalize service"
  value       = aws_iam_role.personalize_service_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_execution_role.name
}

# =============================================================================
# Amazon Personalize Dataset Outputs
# =============================================================================

output "dataset_group_arn" {
  description = "ARN of the Personalize dataset group"
  value       = aws_personalize_dataset_group.main.arn
}

output "dataset_group_name" {
  description = "Name of the Personalize dataset group"
  value       = aws_personalize_dataset_group.main.name
}

output "interactions_dataset_arn" {
  description = "ARN of the interactions dataset"
  value       = aws_personalize_dataset.interactions.arn
}

output "items_dataset_arn" {
  description = "ARN of the items dataset"
  value       = aws_personalize_dataset.items.arn
}

output "users_dataset_arn" {
  description = "ARN of the users dataset"
  value       = aws_personalize_dataset.users.arn
}

# =============================================================================
# Schema Outputs
# =============================================================================

output "interactions_schema_arn" {
  description = "ARN of the interactions schema"
  value       = aws_personalize_schema.interactions.arn
}

output "items_schema_arn" {
  description = "ARN of the items schema"
  value       = aws_personalize_schema.items.arn
}

output "users_schema_arn" {
  description = "ARN of the users schema"
  value       = aws_personalize_schema.users.arn
}

# =============================================================================
# Solution (ML Model) Outputs
# =============================================================================

output "solution_arns" {
  description = "ARNs of all Personalize solutions"
  value = {
    user_personalization = aws_personalize_solution.user_personalization.arn
    similar_items        = aws_personalize_solution.similar_items.arn
    trending_now         = aws_personalize_solution.trending_now.arn
    popularity           = aws_personalize_solution.popularity.arn
  }
}

output "user_personalization_solution_arn" {
  description = "ARN of the User-Personalization solution"
  value       = aws_personalize_solution.user_personalization.arn
}

output "similar_items_solution_arn" {
  description = "ARN of the Similar-Items solution"
  value       = aws_personalize_solution.similar_items.arn
}

output "trending_now_solution_arn" {
  description = "ARN of the Trending-Now solution"
  value       = aws_personalize_solution.trending_now.arn
}

output "popularity_solution_arn" {
  description = "ARN of the Popularity-Count solution"
  value       = aws_personalize_solution.popularity.arn
}

# =============================================================================
# Filter Outputs
# =============================================================================

output "filter_arns" {
  description = "ARNs of all Personalize filters"
  value = {
    exclude_purchased = aws_personalize_filter.exclude_purchased.arn
    category_filter   = aws_personalize_filter.category_filter.arn
    price_filter      = aws_personalize_filter.price_filter.arn
  }
}

output "exclude_purchased_filter_arn" {
  description = "ARN of the exclude purchased items filter"
  value       = aws_personalize_filter.exclude_purchased.arn
}

output "category_filter_arn" {
  description = "ARN of the category filter"
  value       = aws_personalize_filter.category_filter.arn
}

output "price_filter_arn" {
  description = "ARN of the price range filter"
  value       = aws_personalize_filter.price_filter.arn
}

# =============================================================================
# Lambda Function Outputs
# =============================================================================

output "recommendation_service_function_name" {
  description = "Name of the recommendation service Lambda function"
  value       = aws_lambda_function.recommendation_service.function_name
}

output "recommendation_service_function_arn" {
  description = "ARN of the recommendation service Lambda function"
  value       = aws_lambda_function.recommendation_service.arn
}

output "recommendation_service_invoke_arn" {
  description = "Invoke ARN of the recommendation service Lambda function"
  value       = aws_lambda_function.recommendation_service.invoke_arn
}

output "data_generator_function_name" {
  description = "Name of the data generator Lambda function"
  value       = var.generate_sample_data ? aws_lambda_function.data_generator[0].function_name : null
}

output "data_generator_function_arn" {
  description = "ARN of the data generator Lambda function"
  value       = var.generate_sample_data ? aws_lambda_function.data_generator[0].arn : null
}

output "retraining_automation_function_name" {
  description = "Name of the retraining automation Lambda function"
  value       = var.enable_auto_retraining ? aws_lambda_function.retraining_automation[0].function_name : null
}

output "retraining_automation_function_arn" {
  description = "ARN of the retraining automation Lambda function"
  value       = var.enable_auto_retraining ? aws_lambda_function.retraining_automation[0].arn : null
}

# =============================================================================
# EventBridge Outputs
# =============================================================================

output "retraining_schedule_rule_name" {
  description = "Name of the EventBridge rule for automated retraining"
  value       = var.enable_auto_retraining ? aws_cloudwatch_event_rule.retraining_schedule[0].name : null
}

output "retraining_schedule_rule_arn" {
  description = "ARN of the EventBridge rule for automated retraining"
  value       = var.enable_auto_retraining ? aws_cloudwatch_event_rule.retraining_schedule[0].arn : null
}

output "retraining_schedule_expression" {
  description = "Schedule expression for automated retraining"
  value       = var.retraining_schedule
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name}"
}

output "recommendation_service_log_group" {
  description = "CloudWatch log group for recommendation service"
  value       = aws_cloudwatch_log_group.recommendation_service_logs.name
}

output "high_error_rate_alarm_name" {
  description = "Name of the high error rate alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.alarm_name
}

# =============================================================================
# API Gateway Outputs (Optional)
# =============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.recommendation_api[0].id : null
}

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = var.enable_api_gateway ? "https://${aws_api_gateway_rest_api.recommendation_api[0].id}.execute-api.${local.region}.amazonaws.com/${var.api_gateway_stage_name}" : null
}

output "api_gateway_stage_name" {
  description = "Stage name of the API Gateway deployment"
  value       = var.enable_api_gateway ? var.api_gateway_stage_name : null
}

# =============================================================================
# Security Outputs
# =============================================================================

output "kms_key_id" {
  description = "ID of the KMS key for S3 encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.s3_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key for S3 encryption"
  value       = var.enable_kms_encryption ? aws_kms_key.s3_key[0].arn : null
}

output "kms_alias_name" {
  description = "Alias name of the KMS key"
  value       = var.enable_kms_encryption ? aws_kms_alias.s3_key_alias[0].name : null
}

# =============================================================================
# Configuration Outputs for CLI Commands
# =============================================================================

output "cli_environment_variables" {
  description = "Environment variables for CLI commands"
  value = {
    AWS_REGION                        = local.region
    AWS_ACCOUNT_ID                   = local.account_id
    BUCKET_NAME                      = aws_s3_bucket.personalize_data.id
    DATASET_GROUP_ARN               = aws_personalize_dataset_group.main.arn
    PERSONALIZE_ROLE_ARN            = aws_iam_role.personalize_service_role.arn
    INTERACTIONS_DATASET_ARN        = aws_personalize_dataset.interactions.arn
    ITEMS_DATASET_ARN               = aws_personalize_dataset.items.arn
    USERS_DATASET_ARN               = aws_personalize_dataset.users.arn
    EXCLUDE_PURCHASED_FILTER_ARN    = aws_personalize_filter.exclude_purchased.arn
    CATEGORY_FILTER_ARN             = aws_personalize_filter.category_filter.arn
    PRICE_FILTER_ARN                = aws_personalize_filter.price_filter.arn
    LAMBDA_FUNCTION_NAME            = aws_lambda_function.recommendation_service.function_name
  }
}

output "next_steps" {
  description = "Next steps to complete the setup"
  value = {
    step_1 = "Import training data using dataset import jobs"
    step_2 = "Create solution versions (train models) - this takes 60-90 minutes"
    step_3 = "Create campaigns for real-time inference"
    step_4 = "Test recommendations using the Lambda function"
    step_5 = "Monitor performance using CloudWatch dashboard"
  }
}

# =============================================================================
# Sample Commands Outputs
# =============================================================================

output "sample_commands" {
  description = "Sample commands for interacting with the system"
  value = {
    test_lambda = "aws lambda invoke --function-name ${aws_lambda_function.recommendation_service.function_name} --payload '{\"pathParameters\":{\"userId\":\"user_0001\",\"type\":\"personalized\"},\"queryStringParameters\":{\"numResults\":\"10\"}}' response.json"
    
    view_logs = "aws logs tail /aws/lambda/${aws_lambda_function.recommendation_service.function_name} --follow"
    
    check_s3_contents = "aws s3 ls s3://${aws_s3_bucket.personalize_data.id}/ --recursive"
    
    view_dashboard = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${aws_cloudwatch_dashboard.personalize_dashboard.dashboard_name}"
    
    generate_sample_data = var.generate_sample_data ? "aws lambda invoke --function-name ${aws_lambda_function.data_generator[0].function_name} --payload '{\"action\":\"generate_all_datasets\"}' response.json" : "Sample data generation is disabled"
  }
}

# =============================================================================
# Cost Estimation
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (USD)"
  value = {
    s3_storage = "~$10-30 (depends on data volume)"
    lambda_compute = "~$5-20 (depends on request volume)"
    personalize_training = "~$50-150 (monthly retraining)"
    personalize_campaigns = "~$100-300 (depends on TPS allocation)"
    cloudwatch_logs = "~$5-15 (depends on log volume)"
    api_gateway = var.enable_api_gateway ? "~$3-10 (per million requests)" : "Not enabled"
    total_estimated = "~$200-500 per month for moderate usage"
    note = "Costs vary significantly based on data volume, request frequency, and TPS allocation"
  }
}