# User and Group Information
output "test_user_name" {
  description = "Name of the created test user"
  value       = aws_iam_user.test_user.name
}

output "test_user_arn" {
  description = "ARN of the created test user"
  value       = aws_iam_user.test_user.arn
}

output "admin_group_name" {
  description = "Name of the MFA administrators group"
  value       = aws_iam_group.mfa_admins.name
}

output "admin_group_arn" {
  description = "ARN of the MFA administrators group"
  value       = aws_iam_group.mfa_admins.arn
}

# Temporary Password (marked as sensitive)
output "temporary_password" {
  description = "Temporary password for the test user (change on first login)"
  value       = var.temporary_password
  sensitive   = true
}

# MFA Policy Information
output "mfa_policy_name" {
  description = "Name of the MFA enforcement policy"
  value       = aws_iam_policy.mfa_enforcement.name
}

output "mfa_policy_arn" {
  description = "ARN of the MFA enforcement policy"
  value       = aws_iam_policy.mfa_enforcement.arn
}

# MFA Device Information
output "virtual_mfa_device_arn" {
  description = "ARN of the virtual MFA device"
  value       = aws_iam_virtual_mfa_device.test_user_mfa.arn
}

output "virtual_mfa_device_serial_number" {
  description = "Serial number of the virtual MFA device"
  value       = aws_iam_virtual_mfa_device.test_user_mfa.arn
}

output "mfa_qr_code_file" {
  description = "Path to the generated MFA QR code image file"
  value       = "mfa-qr-code.png"
}

# AWS Console Login Information
output "aws_console_login_url" {
  description = "AWS Console login URL for the test user"
  value       = "https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console"
}

output "aws_account_id" {
  description = "AWS Account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are created"
  value       = data.aws_region.current.name
}

# CloudTrail Information (conditional outputs)
output "cloudtrail_name" {
  description = "Name of the CloudTrail trail for MFA audit logging"
  value       = var.enable_cloudtrail ? aws_cloudtrail.mfa_audit_trail[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.mfa_audit_trail[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket name for CloudTrail logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

output "cloudtrail_log_group" {
  description = "CloudWatch log group for CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail_logs[0].name : null
}

# CloudWatch Dashboard Information
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for MFA monitoring"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.mfa_security_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.mfa_security_dashboard[0].dashboard_name}" : null
}

# CloudWatch Alarms Information
output "non_mfa_alarm_name" {
  description = "Name of the CloudWatch alarm for non-MFA logins"
  value       = var.enable_cloudtrail && var.enable_mfa_alarms ? aws_cloudwatch_metric_alarm.non_mfa_console_logins[0].alarm_name : null
}

output "non_mfa_alarm_arn" {
  description = "ARN of the CloudWatch alarm for non-MFA logins"
  value       = var.enable_cloudtrail && var.enable_mfa_alarms ? aws_cloudwatch_metric_alarm.non_mfa_console_logins[0].arn : null
}

# SNS Information (conditional outputs)
output "sns_topic_arn" {
  description = "ARN of the SNS topic for MFA alerts"
  value       = var.enable_sns_notifications && var.notification_email != "" ? aws_sns_topic.mfa_alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for MFA alerts"
  value       = var.enable_sns_notifications && var.notification_email != "" ? aws_sns_topic.mfa_alerts[0].name : null
}

# Setup Instructions
output "setup_instructions" {
  description = "Instructions for setting up MFA"
  value = <<-EOT
    
    MFA Setup Instructions:
    ======================
    
    1. Console Login:
       - URL: https://${data.aws_caller_identity.current.account_id}.signin.aws.amazon.com/console
       - Username: ${aws_iam_user.test_user.name}
       - Password: [Use the temporary_password output - marked as sensitive]
    
    2. MFA Device Setup:
       - Open your authenticator app (Google Authenticator, Authy, etc.)
       - Scan the QR code from: mfa-qr-code.png
       - Enter two consecutive MFA codes when prompted
    
    3. Emergency Access:
       - Save backup codes in a secure location
       - Document emergency procedures for MFA device loss
       - Consider hardware MFA for critical accounts
    
    4. Monitoring:
       - CloudWatch Dashboard: ${var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.dashboard_name}" : "Not enabled"}
       - CloudTrail Logs: ${var.enable_cloudtrail ? aws_cloudwatch_log_group.cloudtrail_logs[0].name : "Not enabled"}
    
    5. Validation:
       - Test login without MFA (should be restricted)
       - Test login with MFA (should have full access)
       - Verify CloudWatch metrics and alarms
    
    Important Notes:
    ================
    - MFA device must be activated before enforcement takes effect
    - Always test MFA policies with non-administrative users first
    - Ensure emergency access procedures are documented
    - Monitor non-MFA login attempts for security incidents
  EOT
}

# Resource Summary
output "resources_created" {
  description = "Summary of resources created"
  value = {
    iam_user           = aws_iam_user.test_user.name
    iam_group          = aws_iam_group.mfa_admins.name
    iam_policy         = aws_iam_policy.mfa_enforcement.name
    virtual_mfa_device = aws_iam_virtual_mfa_device.test_user_mfa.arn
    cloudtrail_enabled = var.enable_cloudtrail
    dashboard_enabled  = var.enable_cloudwatch_dashboard
    alarms_enabled     = var.enable_mfa_alarms
    sns_enabled        = var.enable_sns_notifications && var.notification_email != ""
  }
}