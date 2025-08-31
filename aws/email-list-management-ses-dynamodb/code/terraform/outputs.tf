# Outputs for Email List Management System
# These outputs provide important information about the deployed infrastructure
# including function ARNs, table details, and access URLs for integration

#------------------------------------------------------------------------------
# DynamoDB Table Information
#------------------------------------------------------------------------------

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table storing subscriber information"
  value       = aws_dynamodb_table.email_subscribers.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for IAM policy references"
  value       = aws_dynamodb_table.email_subscribers.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream (if enabled)"
  value       = aws_dynamodb_table.email_subscribers.stream_arn
}

#------------------------------------------------------------------------------
# SES Configuration
#------------------------------------------------------------------------------

output "ses_sender_identity" {
  description = "Verified SES email identity used for sending newsletters"
  value       = aws_ses_email_identity.sender.email
}

output "ses_identity_arn" {
  description = "ARN of the SES email identity"
  value       = aws_ses_email_identity.sender.arn
}

#------------------------------------------------------------------------------
# Lambda Function Information
#------------------------------------------------------------------------------

output "lambda_function_arns" {
  description = "ARNs of all Lambda functions in the email list management system"
  value = {
    subscribe   = aws_lambda_function.subscribe_function.arn
    newsletter  = aws_lambda_function.newsletter_function.arn
    list        = aws_lambda_function.list_function.arn
    unsubscribe = aws_lambda_function.unsubscribe_function.arn
  }
}

output "lambda_function_names" {
  description = "Names of all Lambda functions for CLI invocation and API Gateway integration"
  value = {
    subscribe   = aws_lambda_function.subscribe_function.function_name
    newsletter  = aws_lambda_function.newsletter_function.function_name
    list        = aws_lambda_function.list_function.function_name
    unsubscribe = aws_lambda_function.unsubscribe_function.function_name
  }
}

output "lambda_invoke_arns" {
  description = "Invoke ARNs for Lambda functions (used with API Gateway integration)"
  value = {
    subscribe   = aws_lambda_function.subscribe_function.invoke_arn
    newsletter  = aws_lambda_function.newsletter_function.invoke_arn
    list        = aws_lambda_function.list_function.invoke_arn
    unsubscribe = aws_lambda_function.unsubscribe_function.invoke_arn
  }
}

#------------------------------------------------------------------------------
# IAM Role Information
#------------------------------------------------------------------------------

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.name
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups
#------------------------------------------------------------------------------

output "cloudwatch_log_groups" {
  description = "Names of CloudWatch Log Groups for Lambda functions"
  value = {
    subscribe   = aws_cloudwatch_log_group.subscribe_logs.name
    newsletter  = aws_cloudwatch_log_group.newsletter_logs.name
    list        = aws_cloudwatch_log_group.list_logs.name
    unsubscribe = aws_cloudwatch_log_group.unsubscribe_logs.name
  }
}

#------------------------------------------------------------------------------
# Lambda Function URLs (if enabled)
#------------------------------------------------------------------------------

output "lambda_function_urls" {
  description = "HTTPS URLs for direct Lambda function invocation (if enabled)"
  value = var.enable_function_urls ? {
    subscribe   = try(aws_lambda_function_url.subscribe_url[0].function_url, null)
    newsletter  = try(aws_lambda_function_url.newsletter_url[0].function_url, null)
    list        = try(aws_lambda_function_url.list_url[0].function_url, null)
    unsubscribe = try(aws_lambda_function_url.unsubscribe_url[0].function_url, null)
  } : null
}

#------------------------------------------------------------------------------
# Resource Identifiers for Integration
#------------------------------------------------------------------------------

output "resource_suffix" {
  description = "Random suffix used for resource naming to ensure uniqueness"
  value       = random_id.suffix.hex
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

#------------------------------------------------------------------------------
# Testing and Validation Commands
#------------------------------------------------------------------------------

output "test_commands" {
  description = "AWS CLI commands to test the deployed functions"
  value = {
    subscribe_test = "aws lambda invoke --function-name ${aws_lambda_function.subscribe_function.function_name} --payload '{\"email\":\"test@example.com\",\"name\":\"Test User\"}' response.json"
    newsletter_test = "aws lambda invoke --function-name ${aws_lambda_function.newsletter_function.function_name} --payload '{\"subject\":\"Test Newsletter\",\"message\":\"This is a test message\"}' response.json"
    list_test = "aws lambda invoke --function-name ${aws_lambda_function.list_function.function_name} --payload '{}' response.json"
    unsubscribe_test = "aws lambda invoke --function-name ${aws_lambda_function.unsubscribe_function.function_name} --payload '{\"email\":\"test@example.com\"}' response.json"
  }
}

#------------------------------------------------------------------------------
# Integration Information
#------------------------------------------------------------------------------

output "api_gateway_integration_info" {
  description = "Information needed for API Gateway integration"
  value = {
    lambda_functions = {
      subscribe = {
        function_name = aws_lambda_function.subscribe_function.function_name
        invoke_arn   = aws_lambda_function.subscribe_function.invoke_arn
        http_method  = "POST"
        description  = "Subscribe new users to the email list"
      }
      newsletter = {
        function_name = aws_lambda_function.newsletter_function.function_name
        invoke_arn   = aws_lambda_function.newsletter_function.invoke_arn
        http_method  = "POST"
        description  = "Send newsletter to all active subscribers"
      }
      list = {
        function_name = aws_lambda_function.list_function.function_name
        invoke_arn   = aws_lambda_function.list_function.invoke_arn
        http_method  = "GET"
        description  = "List all subscribers (admin function)"
      }
      unsubscribe = {
        function_name = aws_lambda_function.unsubscribe_function.function_name
        invoke_arn   = aws_lambda_function.unsubscribe_function.invoke_arn
        http_method  = "POST"
        description  = "Unsubscribe users from the email list"
      }
    }
  }
}

#------------------------------------------------------------------------------
# Cost and Usage Information
#------------------------------------------------------------------------------

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed infrastructure (USD, assuming minimal usage)"
  value = {
    dynamodb_pay_per_request = "~$0.25 per million read/write requests"
    lambda_requests = "~$0.20 per million requests"
    lambda_compute = "~$16.67 per GB-second"
    ses_sending = "~$0.10 per 1,000 emails"
    cloudwatch_logs = "~$0.50 per GB ingested"
    estimated_monthly_minimum = "$0.10 - $2.00 for low-volume usage"
  }
}

#------------------------------------------------------------------------------
# Security and Compliance Information
#------------------------------------------------------------------------------

output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    dynamodb_encryption = "Server-side encryption with AWS managed keys enabled"
    iam_least_privilege = "Lambda functions have minimal required permissions"
    cloudwatch_logging = "All function executions are logged to CloudWatch"
    point_in_time_recovery = aws_dynamodb_table.email_subscribers.point_in_time_recovery[0].enabled ? "Enabled" : "Disabled"
    ses_verified_identity = "Email sender identity verified through SES"
  }
}

#------------------------------------------------------------------------------
# Operational Information
#------------------------------------------------------------------------------

output "operational_notes" {
  description = "Important operational information and next steps"
  value = {
    ses_verification = "Ensure sender email ${var.sender_email} is verified in SES before sending newsletters"
    ses_sandbox = "New SES accounts start in sandbox mode - request production access for unrestricted sending"
    function_urls = var.enable_function_urls ? "Function URLs are enabled - consider adding authentication for production use" : "Function URLs are disabled - use API Gateway or direct Lambda invocation"
    log_retention = "CloudWatch logs are retained for ${var.log_retention_days} days"
    monitoring = "Set up CloudWatch alarms for error rates, duration, and throttles"
  }
}

#------------------------------------------------------------------------------
# Cleanup Commands
#------------------------------------------------------------------------------

output "cleanup_commands" {
  description = "Commands to clean up resources when no longer needed"
  value = {
    terraform_destroy = "terraform destroy"
    manual_ses_cleanup = "aws ses delete-identity --identity ${var.sender_email}"
    log_cleanup = "CloudWatch logs will be automatically deleted after ${var.log_retention_days} days"
  }
}