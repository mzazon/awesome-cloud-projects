# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_rest_api.serverless_api.execution_arn}/${aws_api_gateway_stage.api_stage.stage_name}"
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.serverless_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}"
}

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.serverless_api.id
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.api_stage.stage_name
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.users_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.users_function.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.users_function.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function"
  value       = aws_lambda_function.users_function.qualified_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.users_function.version
}

# ============================================================================
# DYNAMODB TABLE OUTPUTS
# ============================================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.users_table.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.users_table.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.users_table.id
}

# ============================================================================
# SQS QUEUE OUTPUTS
# ============================================================================

output "sqs_dead_letter_queue_name" {
  description = "Name of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.name
}

output "sqs_dead_letter_queue_arn" {
  description = "ARN of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.arn
}

output "sqs_dead_letter_queue_url" {
  description = "URL of the SQS dead letter queue"
  value       = aws_sqs_queue.dead_letter_queue.id
}

# ============================================================================
# IAM ROLE OUTPUTS
# ============================================================================

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_log_group.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_gateway_log_group.name
}

output "api_gateway_log_group_arn" {
  description = "ARN of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_gateway_log_group.arn
}

# ============================================================================
# KMS OUTPUTS
# ============================================================================

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = aws_kms_key.log_encryption_key.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.log_encryption_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for encryption"
  value       = aws_kms_alias.log_encryption_key_alias.name
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarms created"
  value = {
    lambda_error_alarm      = aws_cloudwatch_metric_alarm.lambda_error_alarm.alarm_name
    lambda_duration_alarm   = aws_cloudwatch_metric_alarm.lambda_duration_alarm.alarm_name
    api_gateway_4xx_alarm   = aws_cloudwatch_metric_alarm.api_gateway_4xx_alarm.alarm_name
    api_gateway_5xx_alarm   = aws_cloudwatch_metric_alarm.api_gateway_5xx_alarm.alarm_name
  }
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_commands" {
  description = "Commands to test the deployed infrastructure"
  value = {
    get_users = "curl -X GET \"https://${aws_api_gateway_rest_api.serverless_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users\""
    create_user = "curl -X POST \"https://${aws_api_gateway_rest_api.serverless_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users\" -H \"Content-Type: application/json\" -d '{\"id\":\"test-user\",\"name\":\"Test User\",\"email\":\"test@example.com\"}'"
    options_request = "curl -X OPTIONS \"https://${aws_api_gateway_rest_api.serverless_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users\" -H \"Access-Control-Request-Method: GET\" -H \"Access-Control-Request-Headers: Content-Type\""
  }
}

# ============================================================================
# RESOURCE INFORMATION OUTPUTS
# ============================================================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    aws_region              = data.aws_region.current.name
    aws_account_id          = data.aws_caller_identity.current.account_id
    environment             = var.environment
    project_name            = var.project_name
    resource_suffix         = local.resource_suffix
    common_name             = local.common_name
    lambda_runtime          = var.lambda_runtime
    dynamodb_billing_mode   = var.dynamodb_billing_mode
    xray_tracing_enabled    = var.enable_xray_tracing
    detailed_monitoring     = var.enable_detailed_monitoring
  }
}

# ============================================================================
# CODECATALYST INTEGRATION OUTPUTS
# ============================================================================

output "codecatalyst_integration_info" {
  description = "Information for CodeCatalyst integration"
  value = {
    stack_name = "${local.common_name}-stack"
    template_parameters = {
      Stage = var.environment
    }
    cloudformation_capabilities = "CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND"
    stack_outputs_to_reference = [
      "ApiEndpoint",
      "DynamoDBTableName", 
      "LambdaFunctionArn"
    ]
  }
}

# ============================================================================
# APPLICATION COMPOSER OUTPUTS
# ============================================================================

output "application_composer_template_mapping" {
  description = "Mapping of Terraform resources to Application Composer components"
  value = {
    serverless_api = {
      terraform_resource = "aws_api_gateway_rest_api.serverless_api"
      composer_component = "ServerlessAPI"
      type = "AWS::Serverless::Api"
    }
    users_function = {
      terraform_resource = "aws_lambda_function.users_function"
      composer_component = "UsersFunction"
      type = "AWS::Serverless::Function"
    }
    users_table = {
      terraform_resource = "aws_dynamodb_table.users_table"
      composer_component = "UsersTable"
      type = "AWS::Serverless::SimpleTable"
    }
    dead_letter_queue = {
      terraform_resource = "aws_sqs_queue.dead_letter_queue"
      composer_component = "UsersDeadLetterQueue"
      type = "AWS::SQS::Queue"
    }
  }
}

# ============================================================================
# COST OPTIMIZATION OUTPUTS
# ============================================================================

output "cost_optimization_info" {
  description = "Information about cost optimization features"
  value = {
    dynamodb_billing_mode = var.dynamodb_billing_mode
    lambda_architecture = var.lambda_architecture
    lambda_memory_size = var.lambda_memory_size
    lambda_timeout = var.lambda_timeout
    lambda_reserved_concurrency = var.lambda_reserved_concurrency
    log_retention_days = var.cloudwatch_log_retention_days
    cost_tags = {
      Project = var.project_name
      Environment = var.environment
    }
  }
}

# ============================================================================
# SECURITY OUTPUTS
# ============================================================================

output "security_configuration" {
  description = "Security configuration details"
  value = {
    encryption_at_rest = {
      dynamodb_encryption = "AWS managed"
      sqs_encryption = "AWS managed"
      cloudwatch_logs_encryption = "Customer managed KMS"
    }
    iam_roles = {
      lambda_execution_role = aws_iam_role.lambda_execution_role.arn
    }
    cors_configuration = {
      allowed_origins = var.cors_allow_origins
      allowed_methods = var.cors_allow_methods
      allowed_headers = var.cors_allow_headers
    }
    xray_tracing = var.enable_xray_tracing
    point_in_time_recovery = var.dynamodb_point_in_time_recovery
  }
}

# ============================================================================
# DEPLOYMENT VALIDATION OUTPUTS
# ============================================================================

output "deployment_validation" {
  description = "Commands and endpoints for deployment validation"
  value = {
    health_check_endpoint = "https://${aws_api_gateway_rest_api.serverless_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.api_stage.stage_name}/users"
    lambda_function_test = "aws lambda invoke --function-name ${aws_lambda_function.users_function.function_name} --payload '{\"httpMethod\":\"GET\"}' /tmp/lambda-output.json"
    dynamodb_table_check = "aws dynamodb describe-table --table-name ${aws_dynamodb_table.users_table.name}"
    cloudwatch_logs_check = "aws logs describe-log-groups --log-group-name-prefix /aws/lambda/${aws_lambda_function.users_function.function_name}"
    api_gateway_test = "aws apigateway test-invoke-method --rest-api-id ${aws_api_gateway_rest_api.serverless_api.id} --resource-id ${aws_api_gateway_resource.users_resource.id} --http-method GET"
  }
}