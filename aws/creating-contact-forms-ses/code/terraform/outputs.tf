# Output values for the contact form backend infrastructure

# ========================================
# API Gateway Information
# ========================================

output "api_gateway_url" {
  description = "The complete URL for the contact form API endpoint"
  value       = "https://${aws_api_gateway_rest_api.contact_form_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.contact_form_api_stage.stage_name}/contact"
}

output "api_gateway_id" {
  description = "The ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.contact_form_api.id
}

output "api_gateway_stage_name" {
  description = "The name of the API Gateway deployment stage"
  value       = aws_api_gateway_stage.contact_form_api_stage.stage_name
}

output "api_gateway_execution_arn" {
  description = "The execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.contact_form_api.execution_arn
}

# ========================================
# Lambda Function Information
# ========================================

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.contact_form_processor.function_name
}

output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.contact_form_processor.arn
}

output "lambda_invoke_arn" {
  description = "The invoke ARN of the Lambda function"
  value       = aws_lambda_function.contact_form_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "The ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

# ========================================
# SES Information
# ========================================

output "ses_email_identity" {
  description = "The email identity configured for SES"
  value       = aws_ses_email_identity.sender.email
}

output "ses_configuration_set" {
  description = "The SES configuration set name"
  value       = aws_ses_configuration_set.contact_form.name
}

output "ses_verification_status" {
  description = "Instructions for email verification"
  value       = "Check your email (${var.sender_email}) for a verification link from AWS SES"
}

# ========================================
# CloudWatch Logs Information
# ========================================

output "lambda_log_group_name" {
  description = "The name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "The ARN of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "api_gateway_log_group_name" {
  description = "The name of the CloudWatch log group for API Gateway (if enabled)"
  value       = var.enable_api_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

# ========================================
# Security Information
# ========================================

output "iam_role_name" {
  description = "The name of the IAM role used by Lambda"
  value       = aws_iam_role.lambda_execution.name
}

output "iam_policy_arn" {
  description = "The ARN of the custom SES policy"
  value       = aws_iam_policy.ses_send_email.arn
}

# ========================================
# Configuration Information
# ========================================

output "cors_configuration" {
  description = "CORS configuration for the API"
  value = {
    allowed_origins = var.cors_allow_origins
    allowed_methods = ["POST", "OPTIONS"]
    allowed_headers = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
  }
}

output "throttling_configuration" {
  description = "API Gateway throttling configuration"
  value = {
    rate_limit  = var.rate_limit
    burst_limit = var.burst_limit
  }
}

# ========================================
# Deployment Information
# ========================================

output "deployment_region" {
  description = "The AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "The AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ========================================
# Usage Instructions
# ========================================

output "curl_test_command" {
  description = "Example curl command to test the contact form API"
  value = <<-EOF
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"name": "Test User", "email": "test@example.com", "subject": "Test Message", "message": "This is a test message from the contact form."}' \
  https://${aws_api_gateway_rest_api.contact_form_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.contact_form_api_stage.stage_name}/contact
EOF
}

output "javascript_fetch_example" {
  description = "Example JavaScript fetch code for frontend integration"
  value = <<-EOF
fetch('https://${aws_api_gateway_rest_api.contact_form_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.contact_form_api_stage.stage_name}/contact', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
  },
  body: JSON.stringify({
    name: 'John Doe',
    email: 'john@example.com',
    subject: 'Website Inquiry',
    message: 'Hello, I would like to know more about your services.'
  })
})
.then(response => response.json())
.then(data => console.log('Success:', data))
.catch(error => console.error('Error:', error));
EOF
}

# ========================================
# Cost Optimization Information
# ========================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for typical usage (very low volume)"
  value = {
    lambda_requests     = "1M requests/month: $0.00 (Free Tier)"
    lambda_duration     = "Basic usage: < $0.01"
    api_gateway         = "1M requests/month: $1.00"
    ses_emails         = "62K emails/month: $0.00 (Free Tier)"
    cloudwatch_logs    = "Basic logging: < $0.01"
    total_estimated    = "~$1.01/month for 1M requests"
  }
}

# ========================================
# Next Steps
# ========================================

output "next_steps" {
  description = "Instructions for completing the setup"
  value = <<-EOF
1. Verify your email address in AWS SES:
   - Check your email (${var.sender_email}) for a verification link
   - Click the link to verify your email address
   
2. Test the API endpoint:
   - Use the provided curl command or JavaScript example
   - Verify that emails are being sent to ${var.sender_email}
   
3. Integrate with your website:
   - Use the API Gateway URL in your contact form
   - Implement proper error handling in your frontend
   - Consider adding client-side validation
   
4. Monitor the deployment:
   - Check CloudWatch logs: ${aws_cloudwatch_log_group.lambda_logs.name}
   - Monitor API Gateway metrics in CloudWatch
   - Set up alarms for error rates if needed

5. Production considerations:
   - Move out of SES sandbox for production use
   - Implement additional security measures (API keys, WAF)
   - Consider implementing rate limiting per IP
   - Add monitoring and alerting
EOF
}