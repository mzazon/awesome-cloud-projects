# ============================================================================
# Core Infrastructure Outputs
# ============================================================================

output "project_id" {
  description = "Unique project identifier with random suffix"
  value       = local.project_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# Lambda Function Outputs
# ============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function that processes email notifications"
  value       = aws_lambda_function.email_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.email_processor.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch log group name for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# ============================================================================
# SES Configuration Outputs
# ============================================================================

output "ses_sender_email" {
  description = "Verified sender email address"
  value       = var.sender_email
}

output "ses_template_name" {
  description = "Name of the SES email template"
  value       = aws_ses_template.notification_template.name
}

output "ses_verified_identities" {
  description = "List of verified SES email identities"
  value = concat(
    var.verify_email_addresses ? [aws_ses_email_identity.sender[0].email] : [],
    var.verify_email_addresses && var.recipient_email != "" ? [aws_ses_email_identity.recipient[0].email] : []
  )
}

# ============================================================================
# EventBridge Configuration Outputs
# ============================================================================

output "eventbridge_bus_name" {
  description = "Name of the EventBridge bus (custom or default)"
  value       = local.event_bus_name
}

output "eventbridge_bus_arn" {
  description = "ARN of the custom EventBridge bus (if created)"
  value       = var.enable_eventbridge_custom_bus ? aws_cloudwatch_event_bus.custom_bus[0].arn : null
}

output "eventbridge_email_rule_name" {
  description = "Name of the EventBridge rule for email notifications"
  value       = aws_cloudwatch_event_rule.email_notification_rule.name
}

output "eventbridge_email_rule_arn" {
  description = "ARN of the EventBridge rule for email notifications"
  value       = aws_cloudwatch_event_rule.email_notification_rule.arn
}

output "eventbridge_priority_rule_name" {
  description = "Name of the EventBridge rule for priority alerts"
  value       = aws_cloudwatch_event_rule.priority_alert_rule.name
}

output "eventbridge_priority_rule_arn" {
  description = "ARN of the EventBridge rule for priority alerts"
  value       = aws_cloudwatch_event_rule.priority_alert_rule.arn
}

output "eventbridge_scheduled_rule_name" {
  description = "Name of the EventBridge rule for scheduled reports"
  value       = var.enable_scheduled_emails ? aws_cloudwatch_event_rule.daily_report_rule[0].name : null
}

output "eventbridge_scheduled_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled reports"
  value       = var.enable_scheduled_emails ? aws_cloudwatch_event_rule.daily_report_rule[0].arn : null
}

# ============================================================================
# S3 Bucket Outputs
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket used for Lambda deployment packages"
  value       = aws_s3_bucket.lambda_deployment.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket used for Lambda deployment packages"
  value       = aws_s3_bucket.lambda_deployment.arn
}

# ============================================================================
# CloudWatch Monitoring Outputs
# ============================================================================

output "cloudwatch_alarms_enabled" {
  description = "Whether CloudWatch alarms are enabled"
  value       = var.enable_cloudwatch_alarms
}

output "cloudwatch_lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "cloudwatch_ses_bounce_alarm_name" {
  description = "Name of the CloudWatch alarm for SES bounces"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.ses_bounces[0].alarm_name : null
}

output "cloudwatch_custom_error_alarm_name" {
  description = "Name of the CloudWatch alarm for custom error metrics"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.email_processing_errors[0].alarm_name : null
}

# ============================================================================
# Testing and Usage Outputs
# ============================================================================

output "sample_event_email_notification" {
  description = "Sample EventBridge event for testing email notifications"
  value = jsonencode({
    Source      = "custom.application"
    DetailType  = "Email Notification Request"
    Detail = {
      emailConfig = {
        recipient = var.recipient_email != "" ? var.recipient_email : "test@example.com"
        subject   = "Test Notification from Terraform"
      }
      title   = "Terraform Deployment Success"
      message = "Your automated email notification system has been successfully deployed with Terraform."
    }
    EventBusName = local.event_bus_name
  })
}

output "sample_event_priority_alert" {
  description = "Sample EventBridge event for testing priority alerts"
  value = jsonencode({
    Source     = "custom.application"
    DetailType = "Priority Alert"
    Detail = {
      priority = "high"
      emailConfig = {
        recipient = var.recipient_email != "" ? var.recipient_email : "alerts@example.com"
        subject   = "High Priority Alert - System Issue"
      }
      title   = "Critical System Alert"
      message = "This is a high priority alert from your monitoring system. Immediate attention required."
    }
    EventBusName = local.event_bus_name
  })
}

output "aws_cli_test_command" {
  description = "AWS CLI command to test the email notification system"
  value = "aws events put-events --entries '${jsonencode([
    {
      Source      = "custom.application"
      DetailType  = "Email Notification Request"
      Detail = jsonencode({
        emailConfig = {
          recipient = var.recipient_email != "" ? var.recipient_email : "test@example.com"
          subject   = "Test from Terraform Infrastructure"
        }
        title   = "Infrastructure Test"
        message = "This is a test email from your Terraform-deployed email automation system."
      })
      EventBusName = local.event_bus_name
    }
  ])}'"
}

# ============================================================================
# Verification Commands
# ============================================================================

output "verification_commands" {
  description = "Commands to verify the deployment and test functionality"
  value = {
    check_lambda_function = "aws lambda get-function --function-name ${aws_lambda_function.email_processor.function_name}"
    check_ses_statistics  = "aws ses get-send-statistics"
    check_eventbridge_bus = var.enable_eventbridge_custom_bus ? "aws events describe-event-bus --name ${local.event_bus_name}" : "aws events describe-event-bus --name default"
    view_lambda_logs      = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --order-by LastEventTime --descending"
    check_ses_template    = "aws ses get-template --template-name ${aws_ses_template.notification_template.name}"
  }
}