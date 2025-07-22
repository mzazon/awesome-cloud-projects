# Output values for the data governance pipeline

#---------------------------------------------------------------
# Amazon DataZone Outputs
#---------------------------------------------------------------

output "datazone_domain_id" {
  description = "ID of the Amazon DataZone domain"
  value       = aws_datazone_domain.main.id
}

output "datazone_domain_name" {
  description = "Name of the Amazon DataZone domain"
  value       = aws_datazone_domain.main.name
}

output "datazone_domain_arn" {
  description = "ARN of the Amazon DataZone domain"
  value       = aws_datazone_domain.main.arn
}

output "datazone_domain_portal_url" {
  description = "Portal URL for the Amazon DataZone domain"
  value       = aws_datazone_domain.main.portal_url
}

output "datazone_project_id" {
  description = "ID of the Amazon DataZone project"
  value       = aws_datazone_project.main.id
}

output "datazone_project_name" {
  description = "Name of the Amazon DataZone project"
  value       = aws_datazone_project.main.name
}

#---------------------------------------------------------------
# AWS Config Outputs
#---------------------------------------------------------------

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}

output "config_bucket_name" {
  description = "Name of the S3 bucket used for AWS Config delivery channel"
  value       = aws_s3_bucket.config_bucket.bucket
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket used for AWS Config"
  value       = aws_s3_bucket.config_bucket.arn
}

output "config_rules" {
  description = "List of deployed AWS Config rules for data governance"
  value = {
    for rule_name, rule in aws_config_config_rule.governance_rules : rule_name => {
      name        = rule.name
      description = rule.description
      arn         = rule.arn
    }
  }
}

#---------------------------------------------------------------
# Lambda Function Outputs
#---------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the governance Lambda function"
  value       = aws_lambda_function.governance_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the governance Lambda function"
  value       = aws_lambda_function.governance_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the governance Lambda function"
  value       = aws_lambda_function.governance_processor.invoke_arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

#---------------------------------------------------------------
# EventBridge Outputs
#---------------------------------------------------------------

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for governance events"
  value       = aws_cloudwatch_event_rule.governance_events.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.governance_events.arn
}

#---------------------------------------------------------------
# SNS Outputs
#---------------------------------------------------------------

output "sns_topic_name" {
  description = "Name of the SNS topic for governance alerts"
  value       = aws_sns_topic.governance_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for governance alerts"
  value       = aws_sns_topic.governance_alerts.arn
}

output "sns_email_subscription" {
  description = "Email subscription details for governance alerts"
  value = var.sns_email_endpoint != "" ? {
    endpoint = var.sns_email_endpoint
    protocol = "email"
    status   = "PendingConfirmation"
  } : null
}

#---------------------------------------------------------------
# CloudWatch Alarms Outputs
#---------------------------------------------------------------

output "cloudwatch_alarms" {
  description = "CloudWatch alarms for monitoring the governance pipeline"
  value = {
    lambda_errors = {
      name = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
      arn  = aws_cloudwatch_metric_alarm.lambda_errors.arn
    }
    lambda_duration = {
      name = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
      arn  = aws_cloudwatch_metric_alarm.lambda_duration.arn
    }
    compliance_ratio = {
      name = aws_cloudwatch_metric_alarm.compliance_ratio.alarm_name
      arn  = aws_cloudwatch_metric_alarm.compliance_ratio.arn
    }
  }
}

#---------------------------------------------------------------
# IAM Role Outputs
#---------------------------------------------------------------

output "config_role_arn" {
  description = "ARN of the IAM role used by AWS Config"
  value       = aws_iam_role.config_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "datazone_service_role_arn" {
  description = "ARN of the service-linked role for Amazon DataZone"
  value       = aws_iam_service_linked_role.datazone.arn
}

#---------------------------------------------------------------
# Monitoring and Management Outputs
#---------------------------------------------------------------

output "aws_console_links" {
  description = "AWS Console links for managing the governance pipeline"
  value = {
    datazone_portal    = aws_datazone_domain.main.portal_url
    config_dashboard   = "https://${data.aws_region.current.name}.console.aws.amazon.com/config/home?region=${data.aws_region.current.name}#/dashboard"
    lambda_function    = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.governance_processor.function_name}"
    cloudwatch_logs    = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
    eventbridge_rules  = "https://${data.aws_region.current.name}.console.aws.amazon.com/events/home?region=${data.aws_region.current.name}#/rules"
    sns_topics         = "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home?region=${data.aws_region.current.name}#/topics"
  }
}

#---------------------------------------------------------------
# Summary Information
#---------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of the deployed governance pipeline"
  value = {
    # Core components
    datazone_domain    = aws_datazone_domain.main.name
    datazone_project   = aws_datazone_project.main.name
    config_rules_count = length(var.config_rules)
    lambda_function    = aws_lambda_function.governance_processor.function_name
    
    # Monitoring
    sns_topic          = aws_sns_topic.governance_alerts.name
    alarms_count       = 3
    
    # Configuration
    aws_region         = data.aws_region.current.name
    aws_account_id     = data.aws_caller_identity.current.account_id
    environment        = var.environment
    
    # Status
    deployment_time    = timestamp()
    terraform_version  = "~> 1.0"
  }
}

#---------------------------------------------------------------
# Validation Commands
#---------------------------------------------------------------

output "validation_commands" {
  description = "Commands to validate the deployed governance pipeline"
  value = {
    check_datazone_domain = "aws datazone get-domain --identifier ${aws_datazone_domain.main.id} --query 'status' --output text"
    check_config_recorder = "aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[0].recordingGroup' --output table"
    list_config_rules     = "aws configservice describe-config-rules --query 'ConfigRules[].{Name:ConfigRuleName,State:ConfigRuleState}' --output table"
    check_lambda_function = "aws lambda get-function --function-name ${aws_lambda_function.governance_processor.function_name} --query 'Configuration.State' --output text"
    test_eventbridge_rule = "aws events describe-rule --name ${aws_cloudwatch_event_rule.governance_events.name} --query '{Name:Name,State:State}' --output table"
  }
}

#---------------------------------------------------------------
# Cost Estimation
#---------------------------------------------------------------

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the governance pipeline (approximate)"
  value = {
    aws_config_recorder    = "$2.00 per configuration item recorded"
    aws_config_rules       = "$0.001 per rule evaluation"
    lambda_executions      = "$0.20 per 1M requests + compute time"
    datazone_domain        = "$10-50 based on usage"
    cloudwatch_logs        = "$0.50 per GB ingested"
    sns_notifications      = "$0.50 per 1M notifications"
    s3_storage            = "$0.023 per GB stored"
    total_estimate        = "$50-100 per month for moderate usage"
    note                  = "Costs vary based on data volume, rule evaluations, and usage patterns"
  }
}

#---------------------------------------------------------------
# Next Steps
#---------------------------------------------------------------

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm SNS email subscription if email endpoint was provided",
    "2. Access DataZone portal using the provided URL to explore data governance features",
    "3. Monitor AWS Config compliance dashboard for initial rule evaluations",
    "4. Review CloudWatch logs for Lambda function execution details",
    "5. Test governance automation by creating non-compliant resources",
    "6. Configure additional Config rules based on your specific compliance requirements",
    "7. Set up DataZone data sources and projects for your specific data assets",
    "8. Customize Lambda function logic for organization-specific governance workflows"
  ]
}