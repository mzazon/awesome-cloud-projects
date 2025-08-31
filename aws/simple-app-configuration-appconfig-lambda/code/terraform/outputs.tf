# =============================================================================
# Simple Application Configuration with AppConfig and Lambda - Outputs
# 
# This file defines all output values that will be displayed after
# successful Terraform deployment and can be referenced by other configurations.
# =============================================================================

# =============================================================================
# AppConfig Outputs
# =============================================================================

output "appconfig_application_id" {
  description = "ID of the AppConfig application"
  value       = aws_appconfig_application.main.id
}

output "appconfig_application_arn" {
  description = "ARN of the AppConfig application"
  value       = aws_appconfig_application.main.arn
}

output "appconfig_application_name" {
  description = "Name of the AppConfig application"
  value       = aws_appconfig_application.main.name
}

output "appconfig_environment_id" {
  description = "ID of the AppConfig environment"
  value       = aws_appconfig_environment.dev.environment_id
}

output "appconfig_environment_arn" {
  description = "ARN of the AppConfig environment"
  value       = aws_appconfig_environment.dev.arn
}

output "appconfig_configuration_profile_id" {
  description = "ID of the AppConfig configuration profile"
  value       = aws_appconfig_configuration_profile.app_settings.configuration_profile_id
}

output "appconfig_configuration_profile_arn" {
  description = "ARN of the AppConfig configuration profile"
  value       = aws_appconfig_configuration_profile.app_settings.arn
}

output "appconfig_hosted_configuration_version" {
  description = "Version number of the hosted configuration"
  value       = aws_appconfig_hosted_configuration_version.initial.version_number
}

output "appconfig_deployment_strategy_id" {
  description = "ID of the AppConfig deployment strategy"
  value       = aws_appconfig_deployment_strategy.immediate.id
}

output "appconfig_deployment_id" {
  description = "ID of the AppConfig deployment"
  value       = aws_appconfig_deployment.initial.deployment_id
}

# =============================================================================
# Lambda Function Outputs
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.config_demo.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.config_demo.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for API Gateway integration"
  value       = aws_lambda_function.config_demo.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.config_demo.qualified_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.config_demo.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.config_demo.last_modified
}

output "lambda_function_source_code_size" {
  description = "Size in bytes of the function .zip file"
  value       = aws_lambda_function.config_demo.source_code_size
}

output "lambda_function_url" {
  description = "HTTP URL endpoint for the Lambda function (if enabled)"
  value       = var.create_function_url ? aws_lambda_function_url.config_demo_url[0].function_url : null
}

# =============================================================================
# IAM Role and Policy Outputs
# =============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "appconfig_access_policy_arn" {
  description = "ARN of the AppConfig access policy"
  value       = aws_iam_policy.appconfig_access.arn
}

output "appconfig_access_policy_name" {
  description = "Name of the AppConfig access policy"
  value       = aws_iam_policy.appconfig_access.name
}

# =============================================================================
# CloudWatch Outputs
# =============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm (if enabled)"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.config_errors[0].alarm_name : null
}

# =============================================================================
# Configuration Data Outputs
# =============================================================================

output "configuration_data" {
  description = "The initial configuration data as JSON"
  value       = local.default_config
  sensitive   = false
}

output "configuration_endpoint" {
  description = "AppConfig extension endpoint URL for Lambda"
  value       = "http://localhost:2772/applications/${aws_appconfig_application.main.id}/environments/${aws_appconfig_environment.dev.environment_id}/configurations/${aws_appconfig_configuration_profile.app_settings.configuration_profile_id}"
}

# =============================================================================
# Deployment Information Outputs
# =============================================================================

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    application_name      = aws_appconfig_application.main.name
    environment_name     = var.environment_name
    configuration_profile = aws_appconfig_configuration_profile.app_settings.name
    deployment_strategy  = aws_appconfig_deployment_strategy.immediate.name
    lambda_function     = aws_lambda_function.config_demo.function_name
    region             = data.aws_region.current.name
    account_id         = data.aws_caller_identity.current.account_id
  }
}

# =============================================================================
# Testing and Validation Outputs
# =============================================================================

output "test_commands" {
  description = "Commands to test the deployment"
  value = {
    invoke_lambda = "aws lambda invoke --function-name ${aws_lambda_function.config_demo.function_name} --payload '{}' response.json && cat response.json"
    view_logs     = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '5 minutes ago' +%s)000"
    get_config    = "aws appconfig get-configuration --application ${aws_appconfig_application.main.id} --environment ${aws_appconfig_environment.dev.environment_id} --configuration ${aws_appconfig_configuration_profile.app_settings.configuration_profile_id} --client-id terraform-test"
  }
}

output "aws_cli_examples" {
  description = "AWS CLI commands for managing the configuration"
  value = {
    create_new_version = "aws appconfig create-hosted-configuration-version --application-id ${aws_appconfig_application.main.id} --configuration-profile-id ${aws_appconfig_configuration_profile.app_settings.configuration_profile_id} --content-type application/json --content '{\"database\":{\"max_connections\":200}}'"
    start_deployment   = "aws appconfig start-deployment --application-id ${aws_appconfig_application.main.id} --environment-id ${aws_appconfig_environment.dev.environment_id} --deployment-strategy-id ${aws_appconfig_deployment_strategy.immediate.id} --configuration-profile-id ${aws_appconfig_configuration_profile.app_settings.configuration_profile_id} --configuration-version NEW_VERSION_NUMBER"
    list_deployments   = "aws appconfig list-deployments --application-id ${aws_appconfig_application.main.id} --environment-id ${aws_appconfig_environment.dev.environment_id}"
  }
}

# =============================================================================
# Resource Summary Output
# =============================================================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    appconfig_resources = {
      application           = aws_appconfig_application.main.name
      environment          = aws_appconfig_environment.dev.name
      configuration_profile = aws_appconfig_configuration_profile.app_settings.name
      deployment_strategy  = aws_appconfig_deployment_strategy.immediate.name
      hosted_config_version = aws_appconfig_hosted_configuration_version.initial.version_number
      deployment_id        = aws_appconfig_deployment.initial.deployment_id
    }
    lambda_resources = {
      function_name = aws_lambda_function.config_demo.function_name
      runtime      = aws_lambda_function.config_demo.runtime
      memory_size  = aws_lambda_function.config_demo.memory_size
      timeout      = aws_lambda_function.config_demo.timeout
    }
    iam_resources = {
      execution_role    = aws_iam_role.lambda_execution.name
      appconfig_policy = aws_iam_policy.appconfig_access.name
    }
    monitoring_resources = {
      log_group    = aws_cloudwatch_log_group.lambda_logs.name
      log_retention = aws_cloudwatch_log_group.lambda_logs.retention_in_days
      alarm_enabled = var.enable_cloudwatch_alarms
    }
  }
}