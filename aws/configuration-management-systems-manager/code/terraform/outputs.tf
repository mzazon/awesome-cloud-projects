# Outputs for AWS Systems Manager State Manager configuration management infrastructure
# This file defines all output values that will be displayed after Terraform applies

output "state_manager_role_arn" {
  description = "ARN of the IAM role used by State Manager"
  value       = aws_iam_role.state_manager_role.arn
}

output "state_manager_role_name" {
  description = "Name of the IAM role used by State Manager"
  value       = aws_iam_role.state_manager_role.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for configuration drift notifications"
  value       = aws_sns_topic.config_drift_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for configuration drift notifications"
  value       = aws_sns_topic.config_drift_alerts.name
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for State Manager"
  value       = aws_cloudwatch_log_group.state_manager_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for State Manager"
  value       = aws_cloudwatch_log_group.state_manager_logs.arn
}

output "security_configuration_document_name" {
  description = "Name of the custom security configuration SSM document"
  value       = aws_ssm_document.security_configuration.name
}

output "security_configuration_document_arn" {
  description = "ARN of the custom security configuration SSM document"
  value       = aws_ssm_document.security_configuration.arn
}

output "remediation_automation_document_name" {
  description = "Name of the remediation automation SSM document"
  value       = aws_ssm_document.remediation_automation.name
}

output "remediation_automation_document_arn" {
  description = "ARN of the remediation automation SSM document"
  value       = aws_ssm_document.remediation_automation.arn
}

output "compliance_report_document_name" {
  description = "Name of the compliance report SSM document"
  value       = aws_ssm_document.compliance_report.name
}

output "compliance_report_document_arn" {
  description = "ARN of the compliance report SSM document"
  value       = aws_ssm_document.compliance_report.arn
}

output "agent_update_association_id" {
  description = "ID of the SSM Agent update association"
  value       = aws_ssm_association.agent_update.association_id
}

output "security_config_association_id" {
  description = "ID of the security configuration association"
  value       = aws_ssm_association.security_configuration.association_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for State Manager output"
  value       = aws_s3_bucket.state_manager_output.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for State Manager output"
  value       = aws_s3_bucket.state_manager_output.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.state_manager_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.state_manager_dashboard.dashboard_name}"
}

output "association_failure_alarm_name" {
  description = "Name of the CloudWatch alarm for association failures"
  value       = aws_cloudwatch_metric_alarm.association_failures.alarm_name
}

output "compliance_violation_alarm_name" {
  description = "Name of the CloudWatch alarm for compliance violations"
  value       = aws_cloudwatch_metric_alarm.compliance_violations.alarm_name
}

output "test_instance_ids" {
  description = "IDs of the test EC2 instances (if created)"
  value       = var.create_test_instances ? aws_instance.test_instances[*].id : []
}

output "test_instance_private_ips" {
  description = "Private IP addresses of the test EC2 instances (if created)"
  value       = var.create_test_instances ? aws_instance.test_instances[*].private_ip : []
}

output "configuration_summary" {
  description = "Summary of the State Manager configuration"
  value = {
    environment                = var.environment
    target_tag                = "${var.target_tag_key}=${var.target_tag_value}"
    association_schedule       = var.association_schedule
    agent_update_schedule      = var.agent_update_schedule
    compliance_severity        = var.compliance_severity
    notification_email         = var.notification_email
    security_configurations = {
      enable_firewall      = var.enable_firewall
      disable_root_login   = var.disable_root_login
    }
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    1. Confirm SNS subscription in your email (${var.notification_email})
    2. Tag your EC2 instances with ${var.target_tag_key}=${var.target_tag_value}
    3. Check CloudWatch dashboard: ${aws_cloudwatch_dashboard.state_manager_dashboard.dashboard_name}
    4. Monitor association execution in Systems Manager console
    5. Review compliance reports in the CloudWatch logs
  EOT
}