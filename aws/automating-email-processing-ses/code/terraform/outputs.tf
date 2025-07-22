# Output values for AWS serverless email processing system

# ============================================================================
# DOMAIN AND EMAIL CONFIGURATION
# ============================================================================

output "domain_name" {
  description = "The verified domain name for email receiving"
  value       = var.domain_name
}

output "domain_verification_token" {
  description = "Domain verification TXT record value for DNS configuration"
  value       = aws_ses_domain_identity.domain.verification_token
}

output "email_addresses" {
  description = "List of email addresses configured to receive and process emails"
  value       = local.email_addresses
}

output "mx_record_value" {
  description = "MX record value to add to DNS for email receiving"
  value       = "10 inbound-smtp.${local.ses_region}.amazonaws.com"
}

# ============================================================================
# INFRASTRUCTURE RESOURCES
# ============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing incoming emails"
  value       = aws_s3_bucket.email_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing incoming emails"
  value       = aws_s3_bucket.email_storage.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function processing emails"
  value       = aws_lambda_function.email_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function processing emails"
  value       = aws_lambda_function.email_processor.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for email processing notifications"
  value       = aws_sns_topic.email_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for email processing notifications"
  value       = aws_sns_topic.email_notifications.arn
}

# ============================================================================
# SES CONFIGURATION
# ============================================================================

output "ses_rule_set_name" {
  description = "Name of the SES receipt rule set"
  value       = aws_ses_receipt_rule_set.email_processing.rule_set_name
}

output "ses_rule_name" {
  description = "Name of the SES receipt rule for email processing"
  value       = aws_ses_receipt_rule.email_processing.name
}

output "ses_domain_identity_arn" {
  description = "ARN of the SES domain identity"
  value       = aws_ses_domain_identity.domain.arn
}

# ============================================================================
# SECURITY AND ACCESS
# ============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_execution.name
}

# ============================================================================
# MONITORING AND LOGGING
# ============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ============================================================================
# DEPLOYMENT INFORMATION
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# CONFIGURATION AND SETUP INSTRUCTIONS
# ============================================================================

output "setup_instructions" {
  description = "Step-by-step setup instructions for the email processing system"
  value = <<-EOT
    Email Processing System Setup Instructions:
    
    1. DNS Configuration:
       Add the following records to your domain's DNS:
       - TXT record: Name="_amazonses.${var.domain_name}", Value="${aws_ses_domain_identity.domain.verification_token}"
       - MX record: Name="${var.domain_name}", Value="10 inbound-smtp.${local.ses_region}.amazonaws.com"
    
    2. Domain Verification:
       Wait for DNS propagation (up to 24 hours), then verify domain in SES console
    
    3. Email Testing:
       Send test emails to: ${join(", ", local.email_addresses)}
    
    4. Monitoring:
       - Check Lambda logs: CloudWatch Logs Group "${aws_cloudwatch_log_group.lambda_logs.name}"
       - Monitor email storage: S3 Bucket "${aws_s3_bucket.email_storage.bucket}"
       - Notifications: SNS Topic "${aws_sns_topic.email_notifications.name}"
    
    5. Verification Commands:
       aws s3 ls s3://${aws_s3_bucket.email_storage.bucket}/emails/
       aws logs filter-log-events --log-group-name "${aws_cloudwatch_log_group.lambda_logs.name}"
  EOT
}

output "test_email_scenarios" {
  description = "Test scenarios to verify email processing functionality"
  value = <<-EOT
    Test Email Scenarios:
    
    1. Support Email Test:
       Send email to: support@${var.domain_name}
       Subject: "Test Support Request"
       Expected: Auto-reply with ticket ID and SNS notification
    
    2. Invoice Email Test:
       Send email to: invoices@${var.domain_name}
       Subject: "Test Invoice Submission"
       Expected: Invoice confirmation reply with reference number
    
    3. General Email Test:
       Send email to: support@${var.domain_name}
       Subject: "General Inquiry"
       Expected: Generic acknowledgment reply
    
    Verification:
    - Check for automated email replies
    - Verify emails stored in S3: s3://${aws_s3_bucket.email_storage.bucket}/emails/
    - Check Lambda function logs in CloudWatch
    - Confirm SNS notifications received
  EOT
}

# ============================================================================
# TROUBLESHOOTING INFORMATION
# ============================================================================

output "troubleshooting_guide" {
  description = "Common troubleshooting steps and helpful commands"
  value = <<-EOT
    Troubleshooting Guide:
    
    1. Email Not Being Received:
       - Verify MX record: dig MX ${var.domain_name}
       - Check domain verification status in SES console
       - Ensure SES receiving is enabled in correct region: ${local.ses_region}
    
    2. Lambda Function Issues:
       - Check function logs: aws logs tail "${aws_cloudwatch_log_group.lambda_logs.name}" --follow
       - Verify IAM permissions: aws iam get-role --role-name "${aws_iam_role.lambda_execution.name}"
       - Test function manually in Lambda console
    
    3. Auto-replies Not Sending:
       - Verify domain is verified for sending in SES
       - Check SES sending statistics and bounce rates
       - Ensure noreply@${var.domain_name} is verified or domain sending is enabled
    
    4. S3 Storage Issues:
       - Check bucket policy allows SES write access
       - Verify bucket exists and is accessible: aws s3 ls s3://${aws_s3_bucket.email_storage.bucket}/
    
    5. SNS Notifications Not Received:
       - Confirm email subscription: aws sns list-subscriptions-by-topic --topic-arn "${aws_sns_topic.email_notifications.arn}"
       - Check spam folder for subscription confirmation
    
    Useful Commands:
    - List stored emails: aws s3 ls s3://${aws_s3_bucket.email_storage.bucket}/emails/ --recursive
    - View Lambda metrics: aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations --dimensions Name=FunctionName,Value=${aws_lambda_function.email_processor.function_name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum
    - Check SES statistics: aws ses get-send-statistics
  EOT
}