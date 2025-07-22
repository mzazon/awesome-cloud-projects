# Output Values for AWS AppConfig Feature Flags Infrastructure
# These outputs provide essential information for validation, integration, and monitoring

# AppConfig Application Information
output "appconfig_application_id" {
  description = "The ID of the AppConfig application"
  value       = aws_appconfig_application.feature_flags.id
}

output "appconfig_application_name" {
  description = "The name of the AppConfig application"
  value       = aws_appconfig_application.feature_flags.name
}

output "appconfig_application_arn" {
  description = "The ARN of the AppConfig application"
  value       = aws_appconfig_application.feature_flags.arn
}

# AppConfig Environment Information
output "appconfig_environment_id" {
  description = "The ID of the AppConfig environment"
  value       = aws_appconfig_environment.production.environment_id
}

output "appconfig_environment_name" {
  description = "The name of the AppConfig environment"
  value       = aws_appconfig_environment.production.name
}

output "appconfig_environment_arn" {
  description = "The ARN of the AppConfig environment"
  value       = aws_appconfig_environment.production.arn
}

# Configuration Profile Information
output "configuration_profile_id" {
  description = "The ID of the feature flags configuration profile"
  value       = aws_appconfig_configuration_profile.feature_flags.configuration_profile_id
}

output "configuration_profile_name" {
  description = "The name of the feature flags configuration profile"
  value       = aws_appconfig_configuration_profile.feature_flags.name
}

output "configuration_profile_arn" {
  description = "The ARN of the feature flags configuration profile"
  value       = aws_appconfig_configuration_profile.feature_flags.arn
}

# Configuration Version Information
output "initial_configuration_version" {
  description = "The version number of the initial feature flag configuration"
  value       = aws_appconfig_hosted_configuration_version.feature_flags.version_number
}

# Deployment Strategy Information
output "deployment_strategy_id" {
  description = "The ID of the gradual rollout deployment strategy"
  value       = aws_appconfig_deployment_strategy.gradual_rollout.id
}

output "deployment_strategy_name" {
  description = "The name of the gradual rollout deployment strategy"
  value       = aws_appconfig_deployment_strategy.gradual_rollout.name
}

output "deployment_strategy_arn" {
  description = "The ARN of the gradual rollout deployment strategy"
  value       = aws_appconfig_deployment_strategy.gradual_rollout.arn
}

# Lambda Function Information
output "lambda_function_name" {
  description = "The name of the Lambda function for feature flag demonstration"
  value       = aws_lambda_function.feature_flag_demo.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.feature_flag_demo.arn
}

output "lambda_function_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.feature_flag_demo.invoke_arn
}

output "lambda_function_role_arn" {
  description = "The ARN of the Lambda function's execution role"
  value       = aws_iam_role.lambda_execution.arn
}

# CloudWatch Monitoring Information
output "cloudwatch_alarm_name" {
  description = "The name of the CloudWatch alarm for Lambda error monitoring"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "cloudwatch_alarm_arn" {
  description = "The ARN of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

# IAM Resources Information
output "lambda_execution_role_name" {
  description = "The name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "lambda_execution_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

output "appconfig_access_policy_arn" {
  description = "The ARN of the AppConfig access policy"
  value       = aws_iam_policy.appconfig_access.arn
}

output "service_linked_role_arn" {
  description = "The ARN of the AppConfig service-linked role"
  value       = aws_iam_service_linked_role.appconfig.arn
}

# Deployment Information (if auto-deployment is enabled)
output "initial_deployment_number" {
  description = "The deployment number of the initial feature flag deployment (if auto-deployment is enabled)"
  value       = var.enable_auto_deployment ? aws_appconfig_deployment.initial_deployment[0].deployment_number : null
}

output "initial_deployment_state" {
  description = "The state of the initial deployment (if auto-deployment is enabled)"
  value       = var.enable_auto_deployment ? aws_appconfig_deployment.initial_deployment[0].state : null
}

# Configuration Details for Integration
output "appconfig_endpoint_url" {
  description = "The AppConfig endpoint URL for Lambda extension integration"
  value       = "http://localhost:2772/applications/${aws_appconfig_application.feature_flags.id}/environments/${aws_appconfig_environment.production.environment_id}/configurations/${aws_appconfig_configuration_profile.feature_flags.configuration_profile_id}"
}

output "feature_flag_configuration" {
  description = "The current feature flag configuration structure"
  value = {
    new_checkout_flow = {
      enabled             = var.initial_feature_flags.new_checkout_flow.enabled
      rollout_percentage  = var.initial_feature_flags.new_checkout_flow.rollout_percentage
      target_audience     = var.initial_feature_flags.new_checkout_flow.target_audience
    }
    enhanced_search = {
      enabled          = var.initial_feature_flags.enhanced_search.enabled
      search_algorithm = var.initial_feature_flags.enhanced_search.search_algorithm
      cache_ttl        = var.initial_feature_flags.enhanced_search.cache_ttl
    }
    premium_features = {
      enabled      = var.initial_feature_flags.premium_features.enabled
      feature_list = var.initial_feature_flags.premium_features.feature_list
    }
  }
}

# Testing and Validation Commands
output "lambda_test_command" {
  description = "AWS CLI command to test the Lambda function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.feature_flag_demo.function_name} --payload '{}' response.json && cat response.json"
}

output "appconfig_deployment_status_command" {
  description = "AWS CLI command to check deployment status"
  value = var.enable_auto_deployment ? "aws appconfig get-deployment --application-id ${aws_appconfig_application.feature_flags.id} --environment-id ${aws_appconfig_environment.production.environment_id} --deployment-number ${aws_appconfig_deployment.initial_deployment[0].deployment_number}" : "echo 'Auto-deployment not enabled'"
}

output "cloudwatch_metrics_command" {
  description = "AWS CLI command to view Lambda function metrics"
  value       = "aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations --dimensions Name=FunctionName,Value=${aws_lambda_function.feature_flag_demo.function_name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum"
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    appconfig_application    = aws_appconfig_application.feature_flags.name
    appconfig_environment    = aws_appconfig_environment.production.name
    configuration_profile    = aws_appconfig_configuration_profile.feature_flags.name
    deployment_strategy      = aws_appconfig_deployment_strategy.gradual_rollout.name
    lambda_function         = aws_lambda_function.feature_flag_demo.function_name
    cloudwatch_alarm        = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
    iam_role               = aws_iam_role.lambda_execution.name
    iam_policy             = aws_iam_policy.appconfig_access.name
    configuration_version   = aws_appconfig_hosted_configuration_version.feature_flags.version_number
    auto_deployment_enabled = var.enable_auto_deployment
  }
}

# Console URLs for easy access
output "aws_console_urls" {
  description = "AWS Console URLs for easy access to resources"
  value = {
    appconfig_application = "https://${data.aws_region.current.name}.console.aws.amazon.com/systems-manager/appconfig/applications/${aws_appconfig_application.feature_flags.id}"
    lambda_function      = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.feature_flag_demo.function_name}"
    cloudwatch_alarm     = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:alarm/${aws_cloudwatch_metric_alarm.lambda_errors.alarm_name}"
    cloudwatch_logs      = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/$252Faws$252Flambda$252F${aws_lambda_function.feature_flag_demo.function_name}"
  }
}