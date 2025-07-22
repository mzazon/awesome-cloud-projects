# S3 Bucket Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for email templates and subscriber lists"
  value       = aws_s3_bucket.email_marketing.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.email_marketing.arn
}

output "s3_bucket_url" {
  description = "URL of the S3 bucket"
  value       = "https://${aws_s3_bucket.email_marketing.bucket}.s3.${data.aws_region.current.name}.amazonaws.com"
}

# SES Configuration
output "ses_domain_identity" {
  description = "SES domain identity"
  value       = aws_ses_domain_identity.domain.domain
}

output "ses_email_identity" {
  description = "SES email identity"
  value       = aws_ses_email_identity.sender.email
}

output "ses_domain_verification_token" {
  description = "Domain verification token for DNS configuration"
  value       = aws_ses_domain_identity.domain.verification_token
  sensitive   = true
}

output "ses_dkim_tokens" {
  description = "DKIM tokens for DNS configuration"
  value       = var.enable_dkim ? aws_ses_domain_dkim.domain[0].dkim_tokens : []
  sensitive   = true
}

output "ses_configuration_set_name" {
  description = "Name of the SES configuration set"
  value       = aws_ses_configuration_set.marketing_campaigns.name
}

output "ses_configuration_set_arn" {
  description = "ARN of the SES configuration set"
  value       = aws_ses_configuration_set.marketing_campaigns.arn
}

# SNS Topic Information
output "sns_topic_name" {
  description = "Name of the SNS topic for email events"
  value       = aws_sns_topic.email_events.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for email events"
  value       = aws_sns_topic.email_events.arn
}

# Email Templates
output "welcome_template_name" {
  description = "Name of the welcome email template"
  value       = aws_ses_template.welcome.name
}

output "promotion_template_name" {
  description = "Name of the promotion email template"
  value       = aws_ses_template.promotion.name
}

# Lambda Function Information
output "bounce_handler_function_name" {
  description = "Name of the bounce handler Lambda function"
  value       = var.enable_bounce_handler ? aws_lambda_function.bounce_handler[0].function_name : null
}

output "bounce_handler_function_arn" {
  description = "ARN of the bounce handler Lambda function"
  value       = var.enable_bounce_handler ? aws_lambda_function.bounce_handler[0].arn : null
}

# CloudWatch Dashboard
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.email_marketing[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.email_marketing[0].dashboard_name}" : null
}

# CloudWatch Alarms
output "bounce_rate_alarm_name" {
  description = "Name of the bounce rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_bounce_rate.alarm_name
}

output "complaint_rate_alarm_name" {
  description = "Name of the complaint rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_complaint_rate.alarm_name
}

# EventBridge Information
output "campaign_automation_rule_name" {
  description = "Name of the EventBridge rule for campaign automation"
  value       = var.enable_campaign_automation ? aws_cloudwatch_event_rule.campaign_automation[0].name : null
}

output "campaign_automation_rule_arn" {
  description = "ARN of the EventBridge rule for campaign automation"
  value       = var.enable_campaign_automation ? aws_cloudwatch_event_rule.campaign_automation[0].arn : null
}

# IAM Roles
output "bounce_handler_role_name" {
  description = "Name of the bounce handler IAM role"
  value       = var.enable_bounce_handler ? aws_iam_role.bounce_handler_role[0].name : null
}

output "bounce_handler_role_arn" {
  description = "ARN of the bounce handler IAM role"
  value       = var.enable_bounce_handler ? aws_iam_role.bounce_handler_role[0].arn : null
}

output "campaign_automation_role_name" {
  description = "Name of the campaign automation IAM role"
  value       = var.enable_campaign_automation ? aws_iam_role.campaign_automation_role[0].name : null
}

output "campaign_automation_role_arn" {
  description = "ARN of the campaign automation IAM role"
  value       = var.enable_campaign_automation ? aws_iam_role.campaign_automation_role[0].arn : null
}

# Regional and Account Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Configuration Instructions
output "dns_configuration_instructions" {
  description = "Instructions for DNS configuration"
  value = <<-EOT
To complete SES domain verification and enable DKIM, add the following DNS records:

1. Domain Verification (TXT record):
   - Name: _amazonses.${var.sender_domain}
   - Value: ${aws_ses_domain_identity.domain.verification_token}

${var.enable_dkim ? <<-DKIM
2. DKIM Records (CNAME records):
${join("\n", [for token in aws_ses_domain_dkim.domain[0].dkim_tokens : "   - Name: ${token}._domainkey.${var.sender_domain}\n   - Value: ${token}.dkim.amazonses.com"])}
DKIM
: ""}

After adding these records, it may take up to 72 hours for verification to complete.
EOT
}

output "sample_email_command" {
  description = "Sample AWS CLI command to send a test email"
  value = <<-EOT
# Test email sending (after domain verification):
aws sesv2 send-email \
  --from-email-address "${var.sender_email}" \
  --destination ToAddresses="${var.notification_email}" \
  --content Simple='{
    Subject={
      Data="Test Email from SES",
      Charset="UTF-8"
    },
    Body={
      Text={
        Data="This is a test email from your SES email marketing setup.",
        Charset="UTF-8"
      }
    }
  }' \
  --configuration-set-name "${local.config_set_name}"
EOT
}

output "sample_bulk_email_command" {
  description = "Sample AWS CLI command to send bulk templated emails"
  value = <<-EOT
# Send bulk templated emails (after domain verification):
aws sesv2 send-bulk-email \
  --from-email-address "${var.sender_email}" \
  --destinations '[
    {
      "Destination": {"ToAddresses": ["recipient1@example.com"]},
      "ReplacementTemplateData": "{\"name\":\"John\",\"discount\":\"20\",\"product_name\":\"Sample Product\",\"product_url\":\"https://example.com\",\"expiry_date\":\"2024-12-31\",\"unsubscribe_url\":\"https://example.com/unsubscribe\"}"
    }
  ]' \
  --template-name "${var.promotion_template.name}" \
  --default-template-data '{"name":"Customer","discount":"10","product_name":"Our Products","product_url":"https://example.com","expiry_date":"2024-12-31","unsubscribe_url":"https://example.com/unsubscribe"}' \
  --configuration-set-name "${local.config_set_name}"
EOT
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    s3_bucket           = aws_s3_bucket.email_marketing.bucket
    ses_domain          = aws_ses_domain_identity.domain.domain
    ses_email           = aws_ses_email_identity.sender.email
    configuration_set   = aws_ses_configuration_set.marketing_campaigns.name
    sns_topic           = aws_sns_topic.email_events.name
    welcome_template    = aws_ses_template.welcome.name
    promotion_template  = aws_ses_template.promotion.name
    bounce_handler      = var.enable_bounce_handler ? aws_lambda_function.bounce_handler[0].function_name : "disabled"
    dashboard          = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.email_marketing[0].dashboard_name : "disabled"
    campaign_automation = var.enable_campaign_automation ? aws_cloudwatch_event_rule.campaign_automation[0].name : "disabled"
  }
}