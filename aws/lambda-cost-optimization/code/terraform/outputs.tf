# Output values for AWS Lambda Cost Optimization with Compute Optimizer infrastructure
# These outputs provide important information about the deployed resources for validation and integration

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Compute Optimizer Information
output "compute_optimizer_enrollment_status" {
  description = "AWS Compute Optimizer enrollment status"
  value       = var.enable_compute_optimizer ? var.compute_optimizer_enrollment_status : "Not Enabled"
}

# IAM Role Information
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "compute_optimizer_role_arn" {
  description = "ARN of the Compute Optimizer service role"
  value       = aws_iam_role.compute_optimizer_role.arn
  sensitive   = false
}

# Lambda Functions Information
output "sample_lambda_functions" {
  description = "Information about the created sample Lambda functions"
  value = var.create_sample_functions ? {
    for i, func in aws_lambda_function.sample_functions : 
    "function_${i + 1}" => {
      function_name = func.function_name
      function_arn  = func.arn
      memory_size   = func.memory_size
      timeout       = func.timeout
      runtime       = func.runtime
      invoke_arn    = func.invoke_arn
    }
  } : {}
}

output "test_lambda_function" {
  description = "Information about the test Lambda function for optimization validation"
  value = var.create_sample_functions ? {
    function_name = aws_lambda_function.test_optimization_function[0].function_name
    function_arn  = aws_lambda_function.test_optimization_function[0].arn
    memory_size   = aws_lambda_function.test_optimization_function[0].memory_size
    timeout       = aws_lambda_function.test_optimization_function[0].timeout
    runtime       = aws_lambda_function.test_optimization_function[0].runtime
    invoke_arn    = aws_lambda_function.test_optimization_function[0].invoke_arn
  } : null
}

# CloudWatch Monitoring Information
output "cloudwatch_log_groups" {
  description = "CloudWatch log groups created for Lambda functions"
  value = var.create_sample_functions ? {
    for i, lg in aws_cloudwatch_log_group.lambda_log_groups :
    "log_group_${i + 1}" => {
      name              = lg.name
      arn               = lg.arn
      retention_in_days = lg.retention_in_days
    }
  } : {}
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms created for monitoring Lambda performance"
  value = var.enable_cloudwatch_alarms ? {
    error_rate_alarm = {
      name        = aws_cloudwatch_metric_alarm.lambda_error_rate[0].alarm_name
      arn         = aws_cloudwatch_metric_alarm.lambda_error_rate[0].arn
      description = aws_cloudwatch_metric_alarm.lambda_error_rate[0].alarm_description
    }
    duration_alarm = {
      name        = aws_cloudwatch_metric_alarm.lambda_duration_increase[0].alarm_name
      arn         = aws_cloudwatch_metric_alarm.lambda_duration_increase[0].arn
      description = aws_cloudwatch_metric_alarm.lambda_duration_increase[0].alarm_description
    }
  } : {}
}

# SNS Topic Information
output "sns_topic" {
  description = "SNS topic for notifications"
  value = var.create_sns_topic ? {
    name        = aws_sns_topic.lambda_alerts[0].name
    arn         = aws_sns_topic.lambda_alerts[0].arn
    display_name = aws_sns_topic.lambda_alerts[0].display_name
  } : null
}

output "sns_subscription" {
  description = "SNS subscription for email notifications"
  value = var.create_sns_topic && var.notification_email != "" ? {
    endpoint = aws_sns_topic_subscription.email_notification[0].endpoint
    protocol = aws_sns_topic_subscription.email_notification[0].protocol
    arn      = aws_sns_topic_subscription.email_notification[0].arn
  } : null
}

# Cost Analysis Information
output "cost_analysis_function" {
  description = "Cost analysis Lambda function information"
  value = var.enable_cost_analysis ? {
    function_name = aws_lambda_function.cost_analysis_function[0].function_name
    function_arn  = aws_lambda_function.cost_analysis_function[0].arn
    schedule_expression = aws_cloudwatch_event_rule.cost_analysis_schedule[0].schedule_expression
  } : null
}

# KMS Key Information (if created)
output "kms_key" {
  description = "KMS key information for encryption"
  value = var.create_kms_key ? {
    key_id  = aws_kms_key.lambda_key[0].key_id
    arn     = aws_kms_key.lambda_key[0].arn
    alias   = aws_kms_alias.lambda_key_alias[0].name
  } : null
}

# Validation Commands
output "validation_commands" {
  description = "CLI commands to validate the deployment"
  value = {
    check_compute_optimizer_status = "aws compute-optimizer get-enrollment-status"
    list_lambda_functions         = "aws lambda list-functions --query 'Functions[?contains(FunctionName, `${var.project_name}`)].{Name:FunctionName,Memory:MemorySize,Runtime:Runtime}' --output table"
    get_recommendations          = "aws compute-optimizer get-lambda-function-recommendations --output table"
    check_cloudwatch_alarms      = "aws cloudwatch describe-alarms --alarm-name-prefix '${var.project_name}' --output table"
    view_cost_analysis          = var.enable_cost_analysis ? "aws logs filter-log-events --log-group-name '/aws/lambda/${aws_lambda_function.cost_analysis_function[0].function_name}' --start-time $(date -d '1 day ago' +%s)000 --query 'events[].message' --output text" : "Cost analysis not enabled"
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    step_1 = "Wait 14+ days for sufficient Lambda function metrics to accumulate"
    step_2 = "Run: aws compute-optimizer get-lambda-function-recommendations"
    step_3 = "Review recommendations and apply optimizations using the provided scripts"
    step_4 = "Monitor function performance using CloudWatch dashboards and alarms"
    step_5 = var.notification_email != "" ? "Check email for alarm notifications and confirm SNS subscription" : "Configure email notifications by updating the notification_email variable"
  }
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = {
    lambda_functions = "~$${format("%.2f", var.sample_function_count * 0.20)} (assuming minimal usage)"
    cloudwatch_logs  = "~$${format("%.2f", var.sample_function_count * 0.50)} (first 5GB free)"
    cloudwatch_alarms = var.enable_cloudwatch_alarms ? "~$0.20 (2 alarms)" : "$0.00"
    sns_topic        = var.create_sns_topic ? "~$0.50 (first 1M requests free)" : "$0.00"
    kms_key          = var.create_kms_key ? "~$1.00 (if used)" : "$0.00"
    compute_optimizer = "$0.00 (no additional charges)"
    total_estimated  = "~$${format("%.2f", var.sample_function_count * 0.70 + (var.enable_cloudwatch_alarms ? 0.20 : 0) + (var.create_sns_topic ? 0.50 : 0) + (var.create_kms_key ? 1.00 : 0))}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all deployed resources"
  value = {
    iam_roles_created           = 2
    lambda_functions_created    = var.create_sample_functions ? var.sample_function_count + 1 + (var.enable_cost_analysis ? 1 : 0) : 0
    cloudwatch_log_groups      = var.create_sample_functions ? var.sample_function_count + 1 + (var.enable_cost_analysis ? 1 : 0) : 0
    cloudwatch_alarms          = var.enable_cloudwatch_alarms ? 2 : 0
    sns_topics                 = var.create_sns_topic ? 1 : 0
    eventbridge_rules          = var.enable_cost_analysis ? 1 : 0
    kms_keys                   = var.create_kms_key ? 1 : 0
    compute_optimizer_enrolled = var.enable_compute_optimizer
  }
}

# Access Information for Applications
output "integration_endpoints" {
  description = "Endpoints and ARNs for application integration"
  value = {
    lambda_function_arns = var.create_sample_functions ? [
      for func in aws_lambda_function.sample_functions : func.arn
    ] : []
    sns_topic_arn = var.create_sns_topic ? aws_sns_topic.lambda_alerts[0].arn : null
    log_group_names = var.create_sample_functions ? [
      for lg in aws_cloudwatch_log_group.lambda_log_groups : lg.name
    ] : []
  }
}