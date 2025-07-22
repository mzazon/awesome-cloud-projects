# =============================================================================
# Email Reports Infrastructure - Outputs
# =============================================================================
# Output values that provide important information about the deployed
# infrastructure, including endpoints, ARNs, and monitoring resources.

# -----------------------------------------------------------------------------
# App Runner Service Outputs
# -----------------------------------------------------------------------------

output "app_runner_service_name" {
  description = "Name of the App Runner service hosting the email reports application"
  value       = aws_apprunner_service.email_reports_service.service_name
}

output "app_runner_service_arn" {
  description = "ARN of the App Runner service"
  value       = aws_apprunner_service.email_reports_service.arn
}

output "app_runner_service_url" {
  description = "URL of the App Runner service. Use this to access the application endpoints."
  value       = "https://${aws_apprunner_service.email_reports_service.service_url}"
}

output "app_runner_service_status" {
  description = "Current status of the App Runner service"
  value       = aws_apprunner_service.email_reports_service.status
}

output "app_runner_health_check_url" {
  description = "Health check endpoint URL for the App Runner service"
  value       = "https://${aws_apprunner_service.email_reports_service.service_url}${var.health_check_path}"
}

output "app_runner_report_generation_url" {
  description = "Endpoint URL for manually triggering report generation"
  value       = "https://${aws_apprunner_service.email_reports_service.service_url}/generate-report"
}

# -----------------------------------------------------------------------------
# IAM Resources Outputs
# -----------------------------------------------------------------------------

output "app_runner_role_arn" {
  description = "ARN of the IAM role used by the App Runner service"
  value       = aws_iam_role.app_runner_role.arn
}

output "app_runner_role_name" {
  description = "Name of the IAM role used by the App Runner service"
  value       = aws_iam_role.app_runner_role.name
}

output "scheduler_role_arn" {
  description = "ARN of the IAM role used by EventBridge Scheduler"
  value       = aws_iam_role.scheduler_role.arn
}

output "scheduler_role_name" {
  description = "Name of the IAM role used by EventBridge Scheduler"
  value       = aws_iam_role.scheduler_role.name
}

# -----------------------------------------------------------------------------
# Amazon SES Outputs
# -----------------------------------------------------------------------------

output "ses_email_identity" {
  description = "Email address configured in Amazon SES for sending reports"
  value       = aws_ses_email_identity.sender_identity.email
}

output "ses_identity_arn" {
  description = "ARN of the SES email identity"
  value       = aws_ses_email_identity.sender_identity.arn
}

# -----------------------------------------------------------------------------
# EventBridge Scheduler Outputs
# -----------------------------------------------------------------------------

output "schedule_name" {
  description = "Name of the EventBridge Schedule for automated report generation"
  value       = aws_scheduler_schedule.daily_report_schedule.name
}

output "schedule_arn" {
  description = "ARN of the EventBridge Schedule"
  value       = aws_scheduler_schedule.daily_report_schedule.arn
}

output "schedule_expression" {
  description = "Cron expression used for the EventBridge Schedule"
  value       = aws_scheduler_schedule.daily_report_schedule.schedule_expression
}

output "schedule_timezone" {
  description = "Timezone configured for the EventBridge Schedule"
  value       = aws_scheduler_schedule.daily_report_schedule.schedule_expression_timezone
}

output "schedule_state" {
  description = "Current state of the EventBridge Schedule (ENABLED/DISABLED)"
  value       = aws_scheduler_schedule.daily_report_schedule.state
}

# -----------------------------------------------------------------------------
# CloudWatch Monitoring Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm monitoring report generation failures"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.report_generation_failures[0].alarm_name : null
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.report_generation_failures[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring the email reports system"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.email_reports_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard in the AWS Console"
  value = var.enable_cloudwatch_dashboard ? (
    "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.email_reports_dashboard[0].dashboard_name}"
  ) : null
}

output "cloudwatch_logs_group" {
  description = "CloudWatch Logs group name where App Runner service logs are stored"
  value       = "/aws/apprunner/${aws_apprunner_service.email_reports_service.service_name}"
}

# -----------------------------------------------------------------------------
# System Information Outputs
# -----------------------------------------------------------------------------

output "aws_region" {
  description = "AWS region where the resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where the resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# -----------------------------------------------------------------------------
# Verification and Testing Outputs
# -----------------------------------------------------------------------------

output "manual_test_commands" {
  description = "Commands to manually test the deployed infrastructure"
  value = {
    health_check = "curl -s https://${aws_apprunner_service.email_reports_service.service_url}${var.health_check_path}"
    generate_report = "curl -X POST https://${aws_apprunner_service.email_reports_service.service_url}/generate-report -H 'Content-Type: application/json' -d '{}'"
    check_schedule = "aws scheduler get-schedule --name ${aws_scheduler_schedule.daily_report_schedule.name}"
    view_logs = "aws logs describe-log-streams --log-group-name /aws/apprunner/${aws_apprunner_service.email_reports_service.service_name}"
  }
}

# -----------------------------------------------------------------------------
# Next Steps Output
# -----------------------------------------------------------------------------

output "next_steps" {
  description = "Next steps to complete the setup after Terraform deployment"
  value = {
    step_1 = "Verify your email address (${var.ses_verified_email}) in Amazon SES by checking your inbox and clicking the verification link"
    step_2 = "Push your Flask application code to the GitHub repository (${var.github_repository_url})"
    step_3 = "Wait for App Runner to build and deploy your application (this may take 5-10 minutes)"
    step_4 = "Test the health check endpoint: curl -s ${aws_apprunner_service.email_reports_service.service_url}${var.health_check_path}"
    step_5 = "Test report generation: curl -X POST https://${aws_apprunner_service.email_reports_service.service_url}/generate-report -H 'Content-Type: application/json' -d '{}'"
    step_6 = "Monitor the CloudWatch dashboard: ${var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.email_reports_dashboard[0].dashboard_name}" : "Dashboard not enabled"}"
  }
}

# -----------------------------------------------------------------------------
# Cost Estimation Output
# -----------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the deployed resources"
  value = {
    app_runner_base = "App Runner: ~$5-10/month (0.25 vCPU, 0.5 GB memory, minimal traffic)"
    ses_emails = "SES: $0.10 per 1,000 emails (first 62,000 emails free per month)"
    eventbridge_scheduler = "EventBridge Scheduler: $1.00 per million invocations (first 14 million free)"
    cloudwatch = "CloudWatch: ~$1-3/month (custom metrics, alarms, dashboard)"
    total_estimate = "Total: ~$6-14/month for basic usage"
    note = "Costs may vary based on actual usage, region, and additional features enabled"
  }
}