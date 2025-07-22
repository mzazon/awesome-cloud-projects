# ===================================
# OUTPUTS - Dynamic Configuration with Parameter Store
# ===================================
#
# This file defines outputs for the dynamic configuration management solution.
# Outputs are organized by resource type and provide essential information
# for verification, integration, and troubleshooting.

# ===================================
# LAMBDA FUNCTION OUTPUTS
# ===================================

output "lambda_function_arn" {
  description = "ARN of the Lambda function for configuration management"
  value       = aws_lambda_function.config_manager.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.config_manager.function_name
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function (used by other AWS services)"
  value       = aws_lambda_function.config_manager.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function with version"
  value       = aws_lambda_function.config_manager.qualified_arn
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.config_manager.version
}

output "lambda_function_last_modified" {
  description = "Date the Lambda function was last modified"
  value       = aws_lambda_function.config_manager.last_modified
}

output "lambda_function_source_code_size" {
  description = "Size of the Lambda function deployment package in bytes"
  value       = aws_lambda_function.config_manager.source_code_size
}

# ===================================
# IAM ROLE OUTPUTS
# ===================================

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = aws_iam_role.lambda_role.unique_id
}

output "parameter_store_policy_arn" {
  description = "ARN of the custom IAM policy for Parameter Store access"
  value       = aws_iam_policy.parameter_store_policy.arn
}

output "parameter_store_policy_id" {
  description = "ID of the custom IAM policy for Parameter Store access"
  value       = aws_iam_policy.parameter_store_policy.id
}

# ===================================
# PARAMETER STORE OUTPUTS
# ===================================

output "parameter_names" {
  description = "List of all Parameter Store parameter names created"
  value = [
    aws_ssm_parameter.database_host.name,
    aws_ssm_parameter.database_port.name,
    aws_ssm_parameter.database_password.name,
    aws_ssm_parameter.api_timeout.name,
    aws_ssm_parameter.feature_new_ui.name
  ]
}

output "parameter_arns" {
  description = "List of all Parameter Store parameter ARNs created"
  value = [
    aws_ssm_parameter.database_host.arn,
    aws_ssm_parameter.database_port.arn,
    aws_ssm_parameter.database_password.arn,
    aws_ssm_parameter.api_timeout.arn,
    aws_ssm_parameter.feature_new_ui.arn
  ]
}

output "parameter_prefix" {
  description = "Parameter Store prefix used for configuration parameters"
  value       = var.parameter_prefix
}

output "parameter_details" {
  description = "Detailed information about all parameters created"
  value = {
    database = {
      host_name = aws_ssm_parameter.database_host.name
      host_arn  = aws_ssm_parameter.database_host.arn
      host_type = aws_ssm_parameter.database_host.type
      port_name = aws_ssm_parameter.database_port.name
      port_arn  = aws_ssm_parameter.database_port.arn
      port_type = aws_ssm_parameter.database_port.type
      password_name = aws_ssm_parameter.database_password.name
      password_arn  = aws_ssm_parameter.database_password.arn
      password_type = aws_ssm_parameter.database_password.type
    }
    api = {
      timeout_name = aws_ssm_parameter.api_timeout.name
      timeout_arn  = aws_ssm_parameter.api_timeout.arn
      timeout_type = aws_ssm_parameter.api_timeout.type
    }
    features = {
      new_ui_name = aws_ssm_parameter.feature_new_ui.name
      new_ui_arn  = aws_ssm_parameter.feature_new_ui.arn
      new_ui_type = aws_ssm_parameter.feature_new_ui.type
    }
  }
}

# ===================================
# EVENTBRIDGE OUTPUTS
# ===================================

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for parameter change events"
  value       = aws_cloudwatch_event_rule.parameter_change_rule.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for parameter change events"
  value       = aws_cloudwatch_event_rule.parameter_change_rule.name
}

output "eventbridge_rule_id" {
  description = "ID of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.parameter_change_rule.id
}

output "eventbridge_rule_description" {
  description = "Description of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.parameter_change_rule.description
}

output "eventbridge_target_id" {
  description = "ID of the EventBridge target"
  value       = aws_cloudwatch_event_target.lambda_target.target_id
}

# ===================================
# CLOUDWATCH MONITORING OUTPUTS
# ===================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.config_manager.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "Direct URL to the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.config_manager.dashboard_name}"
}

output "cloudwatch_alarm_names" {
  description = "Names of all CloudWatch alarms created"
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_duration.alarm_name,
    aws_cloudwatch_metric_alarm.config_failures.alarm_name
  ]
}

output "cloudwatch_alarm_arns" {
  description = "ARNs of all CloudWatch alarms created"
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.arn,
    aws_cloudwatch_metric_alarm.lambda_duration.arn,
    aws_cloudwatch_metric_alarm.config_failures.arn
  ]
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = "/aws/lambda/${aws_lambda_function.config_manager.function_name}"
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.config_manager.function_name}:*"
}

# ===================================
# EXTENSION AND LAYER OUTPUTS
# ===================================

output "parameters_extension_arn" {
  description = "ARN of the AWS Parameters and Secrets Extension layer"
  value       = local.extension_layer_arn
}

output "parameters_extension_region" {
  description = "AWS region for the Parameters and Secrets Extension"
  value       = data.aws_region.current.name
}

# ===================================
# MONITORING AND METRICS OUTPUTS
# ===================================

output "custom_metrics_namespace" {
  description = "CloudWatch namespace for custom metrics"
  value       = "ConfigManager"
}

output "custom_metrics_list" {
  description = "List of custom metrics that will be published by the Lambda function"
  value = [
    "SuccessfulParameterRetrievals",
    "FailedParameterRetrievals",
    "ConfigurationErrors",
    "ConfigurationProcessingTime",
    "ConfigurationRetrievals",
    "ConfigurationValidationErrors",
    "LambdaHandlerErrors"
  ]
}

# ===================================
# RESOURCE IDENTIFIERS
# ===================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ===================================
# INTEGRATION OUTPUTS
# ===================================

output "test_command" {
  description = "AWS CLI command to test the Lambda function"
  value       = "aws lambda invoke --function-name ${aws_lambda_function.config_manager.function_name} --payload '{}' response.json && cat response.json"
}

output "parameter_update_example" {
  description = "Example AWS CLI command to update a parameter and trigger the system"
  value       = "aws ssm put-parameter --name '${var.parameter_prefix}/api/timeout' --value '45' --type 'String' --overwrite"
}

output "logs_command" {
  description = "AWS CLI command to view Lambda function logs"
  value       = "aws logs filter-log-events --log-group-name '/aws/lambda/${aws_lambda_function.config_manager.function_name}' --start-time $(date -d '10 minutes ago' +%s)000"
}

output "metrics_command" {
  description = "AWS CLI command to view custom metrics"
  value       = "aws cloudwatch get-metric-statistics --namespace 'ConfigManager' --metric-name 'SuccessfulParameterRetrievals' --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum"
}

# ===================================
# SUMMARY OUTPUT
# ===================================

output "deployment_summary" {
  description = "Summary of deployed resources and key information"
  value = {
    lambda_function = {
      name         = aws_lambda_function.config_manager.function_name
      arn          = aws_lambda_function.config_manager.arn
      runtime      = aws_lambda_function.config_manager.runtime
      memory_size  = aws_lambda_function.config_manager.memory_size
      timeout      = aws_lambda_function.config_manager.timeout
    }
    parameters = {
      prefix = var.parameter_prefix
      count  = 5
      names  = [
        aws_ssm_parameter.database_host.name,
        aws_ssm_parameter.database_port.name,
        aws_ssm_parameter.database_password.name,
        aws_ssm_parameter.api_timeout.name,
        aws_ssm_parameter.feature_new_ui.name
      ]
    }
    monitoring = {
      dashboard = aws_cloudwatch_dashboard.config_manager.dashboard_name
      alarms    = [
        aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
        aws_cloudwatch_metric_alarm.lambda_duration.alarm_name,
        aws_cloudwatch_metric_alarm.config_failures.alarm_name
      ]
      log_group = "/aws/lambda/${aws_lambda_function.config_manager.function_name}"
    }
    eventbridge = {
      rule = aws_cloudwatch_event_rule.parameter_change_rule.name
      arn  = aws_cloudwatch_event_rule.parameter_change_rule.arn
    }
    region     = data.aws_region.current.name
    account_id = data.aws_caller_identity.current.account_id
  }
}