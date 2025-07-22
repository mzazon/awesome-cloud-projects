# outputs.tf - Output values for multi-region EventBridge replication

# Resource Identifiers
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.random_suffix
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# EventBridge Resources
output "event_bus_name" {
  description = "Name of the EventBridge event bus"
  value       = local.event_bus_name
}

output "event_bus_arns" {
  description = "ARNs of EventBridge event buses in all regions"
  value = {
    primary   = aws_cloudwatch_event_bus.primary.arn
    secondary = aws_cloudwatch_event_bus.secondary.arn
    tertiary  = aws_cloudwatch_event_bus.tertiary.arn
  }
}

output "event_rule_arns" {
  description = "ARNs of EventBridge rules in all regions"
  value = {
    primary_cross_region = aws_cloudwatch_event_rule.cross_region_replication.arn
    secondary_local      = aws_cloudwatch_event_rule.secondary_local_processing.arn
    tertiary_local       = aws_cloudwatch_event_rule.tertiary_local_processing.arn
  }
}

# Lambda Function Information
output "lambda_function_arns" {
  description = "ARNs of Lambda functions in all regions"
  value = {
    primary   = aws_lambda_function.primary.arn
    secondary = aws_lambda_function.secondary.arn
    tertiary  = aws_lambda_function.tertiary.arn
  }
}

output "lambda_function_names" {
  description = "Names of Lambda functions in all regions"
  value = {
    primary   = aws_lambda_function.primary.function_name
    secondary = aws_lambda_function.secondary.function_name
    tertiary  = aws_lambda_function.tertiary.function_name
  }
}

# IAM Role Information
output "eventbridge_cross_region_role_arn" {
  description = "ARN of the EventBridge cross-region IAM role"
  value       = aws_iam_role.eventbridge_cross_region.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution.arn
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

# Route 53 Health Check
output "health_check_id" {
  description = "ID of the Route 53 health check"
  value       = aws_route53_health_check.eventbridge_health.id
}

output "health_check_fqdn" {
  description = "FQDN being monitored by the health check"
  value       = aws_route53_health_check.eventbridge_health.fqdn
}

# CloudWatch Monitoring
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.eventbridge_monitoring.dashboard_name}"
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarm names and ARNs"
  value = {
    eventbridge_failed_invocations = {
      name = aws_cloudwatch_metric_alarm.eventbridge_failed_invocations.alarm_name
      arn  = aws_cloudwatch_metric_alarm.eventbridge_failed_invocations.arn
    }
    lambda_errors = {
      name = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
      arn  = aws_cloudwatch_metric_alarm.lambda_errors.arn
    }
  }
}

# Region Configuration
output "region_configuration" {
  description = "Configuration of all regions"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    tertiary  = var.tertiary_region
  }
}

# Testing Information
output "test_event_command" {
  description = "AWS CLI command to send a test event"
  value = <<-EOT
    aws events put-events \
      --entries '[{
        "Source": "finance.transactions",
        "DetailType": "Transaction Created",
        "Detail": "{\"transactionId\":\"test-tx-001\",\"amount\":\"${var.financial_amount_threshold + 100}\",\"currency\":\"USD\",\"priority\":\"high\"}",
        "EventBusName": "${local.event_bus_name}"
      }]' \
      --region ${var.primary_region}
  EOT
}

# Log Group Information
output "lambda_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    primary   = "/aws/lambda/${aws_lambda_function.primary.function_name}"
    secondary = "/aws/lambda/${aws_lambda_function.secondary.function_name}"
    tertiary  = "/aws/lambda/${aws_lambda_function.tertiary.function_name}"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_event_buses = "aws events list-event-buses --region ${var.primary_region}"
    check_rules       = "aws events list-rules --event-bus-name ${local.event_bus_name} --region ${var.primary_region}"
    check_targets     = "aws events list-targets-by-rule --rule cross-region-replication-rule --event-bus-name ${local.event_bus_name} --region ${var.primary_region}"
    check_lambda_logs = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${local.lambda_function_name}' --region ${var.primary_region}"
    check_health      = "aws route53 get-health-check --health-check-id ${aws_route53_health_check.eventbridge_health.id}"
  }
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    event_buses_created     = 3
    lambda_functions_created = 3
    regions_configured      = [var.primary_region, var.secondary_region, var.tertiary_region]
    cross_region_replication = true
    monitoring_enabled      = var.enable_enhanced_monitoring
    encryption_enabled      = var.enable_encryption
    notification_email      = var.notification_email != "" ? var.notification_email : "Not configured"
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Cost estimation information"
  value = {
    lambda_free_tier_requests = "1,000,000 requests/month"
    lambda_free_tier_duration = "400,000 GB-seconds/month"
    eventbridge_free_tier     = "First 14 million events/month"
    cloudwatch_free_tier_alarms = "10 alarms/month"
    estimated_monthly_cost    = "$10-50 depending on event volume"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    iam_roles_created         = 2
    kms_encryption_enabled    = var.enable_encryption
    least_privilege_access    = true
    cross_region_access_controlled = true
    event_bus_permissions     = "Account-level access only"
  }
}

# Troubleshooting Information
output "troubleshooting_info" {
  description = "Troubleshooting information"
  value = {
    common_issues = {
      "EventBridge rule not triggering" = "Check event pattern matching and IAM permissions"
      "Lambda function not receiving events" = "Verify Lambda permissions and EventBridge targets"
      "Cross-region replication not working" = "Check IAM roles and event bus permissions"
      "Health check failing" = "Verify Route 53 health check configuration and endpoint availability"
    }
    log_locations = {
      eventbridge = "CloudWatch Logs -> /aws/events/*"
      lambda      = "CloudWatch Logs -> /aws/lambda/${local.lambda_function_name}"
      health_check = "CloudWatch Metrics -> AWS/Route53"
    }
  }
}