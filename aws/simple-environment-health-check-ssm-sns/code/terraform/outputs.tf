# outputs.tf
# Output values for simple-environment-health-check-ssm-sns

# ========================================
# Resource Identifiers
# ========================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# ========================================
# SNS Topic Information
# ========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for health notifications"
  value       = aws_sns_topic.health_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for health notifications"
  value       = aws_sns_topic.health_alerts.name
}

output "sns_subscription_arn" {
  description = "ARN of the email subscription to the SNS topic"
  value       = aws_sns_topic_subscription.email_notification.arn
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email
  sensitive   = true
}

# ========================================
# Lambda Function Information
# ========================================

output "lambda_function_arn" {
  description = "ARN of the health check Lambda function"
  value       = aws_lambda_function.health_check.arn
}

output "lambda_function_name" {
  description = "Name of the health check Lambda function"
  value       = aws_lambda_function.health_check.function_name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.health_check_lambda_role.arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ========================================
# EventBridge Rules Information
# ========================================

output "health_check_schedule_rule_name" {
  description = "Name of the EventBridge rule for scheduled health checks"
  value       = aws_cloudwatch_event_rule.health_check_schedule.name
}

output "health_check_schedule_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled health checks"
  value       = aws_cloudwatch_event_rule.health_check_schedule.arn
}

output "compliance_alerts_rule_name" {
  description = "Name of the EventBridge rule for compliance alerts"
  value       = aws_cloudwatch_event_rule.compliance_alerts.name
}

output "compliance_alerts_rule_arn" {
  description = "ARN of the EventBridge rule for compliance alerts"
  value       = aws_cloudwatch_event_rule.compliance_alerts.arn
}

output "health_check_schedule" {
  description = "Schedule expression for health checks"
  value       = var.health_check_schedule
}

# ========================================
# CloudWatch Dashboard
# ========================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for health monitoring"
  value       = aws_cloudwatch_dashboard.health_monitoring.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.health_monitoring.dashboard_name}"
}

# ========================================
# Systems Manager Information
# ========================================

output "compliance_type" {
  description = "Custom compliance type used for health monitoring"
  value       = var.compliance_type
}

output "managed_instances_count" {
  description = "Number of managed instances found during deployment"
  value       = length(data.aws_instances.managed_instances.ids)
}

output "managed_instance_ids" {
  description = "List of managed instance IDs found during deployment"
  value       = data.aws_instances.managed_instances.ids
}

# ========================================
# Deployment Information
# ========================================

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment tag applied to resources"
  value       = var.environment
}

# ========================================
# Next Steps Information
# ========================================

output "next_steps" {
  description = "Instructions for completing the setup"
  value = <<-EOT
    Environment Health Check Infrastructure Deployed Successfully!
    
    Next Steps:
    1. Check your email (${var.notification_email}) and confirm the SNS subscription
    2. Ensure your EC2 instances have the SSM Agent installed and running
    3. Tag your instances with 'SSMManaged=true' to include them in monitoring
    4. Monitor the Lambda function logs: ${aws_cloudwatch_log_group.lambda_logs.name}
    5. View the health monitoring dashboard: ${aws_cloudwatch_dashboard.health_monitoring.dashboard_name}
    
    Testing:
    - Manually invoke the Lambda function to test health checks
    - Stop an instance's SSM Agent to test non-compliance notifications
    - Check Systems Manager Compliance for health status updates
    
    Resources Created:
    - SNS Topic: ${aws_sns_topic.health_alerts.name}
    - Lambda Function: ${aws_lambda_function.health_check.function_name}
    - EventBridge Rules: 2 rules for scheduling and compliance monitoring
    - CloudWatch Dashboard: ${aws_cloudwatch_dashboard.health_monitoring.dashboard_name}
  EOT
}

# ========================================
# Cost Information
# ========================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for this solution"
  value = <<-EOT
    Estimated Monthly Cost (US East 1):
    - SNS: $0.50 per million notifications + $0.06 per 100,000 email deliveries
    - Lambda: Free tier covers ~1M requests/month, then $0.20 per 1M requests
    - EventBridge: Free tier covers ~1M events/month, then $1.00 per million events
    - CloudWatch Logs: $0.50 per GB ingested (after free tier)
    - CloudWatch Dashboards: $3.00 per dashboard per month
    
    Total estimated cost: $3.50-5.00 per month for typical usage
    Note: Costs may vary based on usage patterns and AWS region
  EOT
}

# ========================================
# AWS CLI Commands for Manual Operations
# ========================================

output "useful_aws_cli_commands" {
  description = "Useful AWS CLI commands for managing this solution"
  value = <<-EOT
    Useful Commands:
    
    # Check SNS topic subscriptions
    aws sns list-subscriptions-by-topic --topic-arn ${aws_sns_topic.health_alerts.arn}
    
    # Manually invoke Lambda function
    aws lambda invoke --function-name ${aws_lambda_function.health_check.function_name} --payload '{"source":"manual-test"}' response.json
    
    # View Lambda logs
    aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --since 30m --follow
    
    # Check compliance summary
    aws ssm list-compliance-summaries --filters Key=ComplianceType,Values=${var.compliance_type}
    
    # Send test notification
    aws sns publish --topic-arn ${aws_sns_topic.health_alerts.arn} --subject "Test Alert" --message "Test notification"
    
    # View managed instances
    aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId,PingStatus,LastPingDateTime]' --output table
  EOT
}