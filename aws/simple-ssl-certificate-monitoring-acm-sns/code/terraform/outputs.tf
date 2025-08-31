# ==============================================================================
# Output Values for SSL Certificate Monitoring Infrastructure
# ==============================================================================
# This file defines outputs that provide important information about the 
# created resources for verification, integration, and management purposes.
# ==============================================================================

# ==============================================================================
# SNS Topic Outputs
# ==============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for certificate expiration alerts"
  value       = aws_sns_topic.ssl_cert_alerts.arn
  sensitive   = false
}

output "sns_topic_name" {
  description = "Name of the SNS topic used for certificate expiration alerts"
  value       = aws_sns_topic.ssl_cert_alerts.name
  sensitive   = false
}

output "sns_topic_policy" {
  description = "The policy applied to the SNS topic allowing CloudWatch access"
  value       = aws_sns_topic_policy.ssl_cert_alerts_policy.policy
  sensitive   = false
}

# ==============================================================================
# Email Subscription Outputs
# ==============================================================================

output "email_subscription_arn" {
  description = "ARN of the email subscription to the SNS topic (if created)"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.email_notification[0].arn : null
  sensitive   = false
}

output "email_subscription_status" {
  description = "Status of the email subscription (PendingConfirmation until email is confirmed)"
  value       = var.notification_email != "" ? "Created - Check email for confirmation" : "Not created - no email provided"
  sensitive   = false
}

# ==============================================================================
# CloudWatch Alarm Outputs
# ==============================================================================

output "existing_certificate_alarm_name" {
  description = "Name of the CloudWatch alarm monitoring existing certificate (if created)"
  value       = var.monitor_existing_certificates && var.certificate_domain_name != "" ? aws_cloudwatch_metric_alarm.certificate_expiration[0].alarm_name : null
  sensitive   = false
}

output "existing_certificate_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring existing certificate (if created)"
  value       = var.monitor_existing_certificates && var.certificate_domain_name != "" ? aws_cloudwatch_metric_alarm.certificate_expiration[0].arn : null
  sensitive   = false
}

output "certificate_arn_alarm_names" {
  description = "Names of CloudWatch alarms monitoring certificates specified by ARN"
  value       = aws_cloudwatch_metric_alarm.certificate_expiration_by_arn[*].alarm_name
  sensitive   = false
}

output "certificate_arn_alarm_arns" {
  description = "ARNs of CloudWatch alarms monitoring certificates specified by ARN"
  value       = aws_cloudwatch_metric_alarm.certificate_expiration_by_arn[*].arn
  sensitive   = false
}

output "test_certificate_alarm_name" {
  description = "Name of the CloudWatch alarm monitoring test certificate (if created)"
  value       = var.create_test_certificate ? aws_cloudwatch_metric_alarm.test_certificate_expiration[0].alarm_name : null
  sensitive   = false
}

output "test_certificate_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring test certificate (if created)"
  value       = var.create_test_certificate ? aws_cloudwatch_metric_alarm.test_certificate_expiration[0].arn : null
  sensitive   = false
}

# ==============================================================================
# Certificate Outputs
# ==============================================================================

output "monitored_existing_certificate_arn" {
  description = "ARN of the existing certificate being monitored (if using domain lookup)"
  value       = var.monitor_existing_certificates && var.certificate_domain_name != "" ? data.aws_acm_certificate.existing_certificates[0].arn : null
  sensitive   = false
}

output "monitored_existing_certificate_domain" {
  description = "Domain name of the existing certificate being monitored"
  value       = var.monitor_existing_certificates && var.certificate_domain_name != "" ? data.aws_acm_certificate.existing_certificates[0].domain_name : null
  sensitive   = false
}

output "monitored_certificate_arns" {
  description = "List of certificate ARNs being monitored"
  value       = var.certificate_arns
  sensitive   = false
}

output "test_certificate_arn" {
  description = "ARN of the test certificate created for demonstration (if created)"
  value       = var.create_test_certificate ? aws_acm_certificate.test_certificate[0].arn : null
  sensitive   = false
}

output "test_certificate_domain" {
  description = "Domain name of the test certificate (if created)"
  value       = var.create_test_certificate ? aws_acm_certificate.test_certificate[0].domain_name : null
  sensitive   = false
}

output "test_certificate_validation_options" {
  description = "Validation options for the test certificate (DNS records to create)"
  value       = var.create_test_certificate ? aws_acm_certificate.test_certificate[0].domain_validation_options : null
  sensitive   = false
}

# ==============================================================================
# Dashboard Outputs
# ==============================================================================

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for certificate monitoring (if created)"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.ssl_certificate_monitoring[0].dashboard_name : null
  sensitive   = false
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard in AWS Console (if created)"
  value = var.create_dashboard ? format(
    "https://%s.console.aws.amazon.com/cloudwatch/home?region=%s#dashboards:name=%s",
    data.aws_region.current.name,
    data.aws_region.current.name,
    aws_cloudwatch_dashboard.ssl_certificate_monitoring[0].dashboard_name
  ) : null
  sensitive = false
}

# ==============================================================================
# Configuration Summary Outputs
# ==============================================================================

output "monitoring_configuration" {
  description = "Summary of the certificate monitoring configuration"
  value = {
    environment                    = var.environment
    expiration_threshold_days     = var.expiration_threshold_days
    alarm_evaluation_periods      = var.alarm_evaluation_periods
    alarm_period_seconds          = var.alarm_period
    notification_email_configured = var.notification_email != ""
    monitoring_existing_cert      = var.monitor_existing_certificates
    monitoring_certificate_arns   = length(var.certificate_arns) > 0
    test_certificate_created      = var.create_test_certificate
    dashboard_created             = var.create_dashboard
    total_certificates_monitored  = (var.monitor_existing_certificates && var.certificate_domain_name != "" ? 1 : 0) + length(var.certificate_arns) + (var.create_test_certificate ? 1 : 0)
  }
  sensitive = false
}

# ==============================================================================
# Operational Outputs
# ==============================================================================

output "aws_cli_test_commands" {
  description = "AWS CLI commands to test the monitoring setup"
  value = {
    test_sns_topic = "aws sns publish --topic-arn ${aws_sns_topic.ssl_cert_alerts.arn} --message 'Test SSL Certificate Monitoring Alert' --subject 'Test Alert'"
    list_alarms    = "aws cloudwatch describe-alarms --alarm-name-prefix 'SSL-'"
    check_metrics  = var.monitor_existing_certificates && var.certificate_domain_name != "" ? "aws cloudwatch get-metric-statistics --namespace AWS/CertificateManager --metric-name DaysToExpiry --dimensions Name=CertificateArn,Value=${data.aws_acm_certificate.existing_certificates[0].arn} --start-time $(date -d '1 day ago' -u +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 86400 --statistics Minimum" : "No existing certificate configured for testing"
  }
  sensitive = false
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    var.notification_email != "" ? "1. Check your email (${var.notification_email}) and confirm the SNS subscription" : "1. Configure notification_email variable and re-apply to receive email alerts",
    "2. Wait up to 24 hours for ACM to publish initial DaysToExpiry metrics to CloudWatch",
    "3. Use the AWS CLI test commands in the 'aws_cli_test_commands' output to verify functionality",
    var.create_dashboard ? "4. Access the CloudWatch dashboard using the URL in 'dashboard_url' output" : "4. Set create_dashboard=true and re-apply to create monitoring dashboard",
    "5. Consider setting up additional notification endpoints (SMS, Slack, etc.) by subscribing to the SNS topic",
    "6. Review and adjust the expiration_threshold_days based on your certificate renewal processes"
  ]
  sensitive = false
}

# ==============================================================================
# Resource Identifiers for External Integration
# ==============================================================================

output "resource_tags" {
  description = "Common tags applied to all resources for identification and management"
  value       = var.tags
  sensitive   = false
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
  sensitive   = false
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
  sensitive   = false
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
  sensitive   = false
}