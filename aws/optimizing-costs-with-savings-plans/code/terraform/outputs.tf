# Output Values for Savings Plans Recommendations Infrastructure
# This file defines the output values that will be displayed after deployment
# and can be used by other Terraform configurations or external systems

output "lambda_function_name" {
  description = "Name of the Lambda function for Savings Plans analysis"
  value       = aws_lambda_function.savings_analyzer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for Savings Plans analysis"
  value       = aws_lambda_function.savings_analyzer.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function for external integrations"
  value       = aws_lambda_function.savings_analyzer.invoke_arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing cost recommendations"
  value       = aws_s3_bucket.cost_recommendations.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing cost recommendations"
  value       = aws_s3_bucket.cost_recommendations.arn
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.cost_recommendations.bucket_regional_domain_name
}

output "iam_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled analysis"
  value       = var.eventbridge_schedule_enabled ? aws_cloudwatch_event_rule.monthly_analysis[0].name : null
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled analysis"
  value       = var.eventbridge_schedule_enabled ? aws_cloudwatch_event_rule.monthly_analysis[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring"
  value       = var.cloudwatch_dashboard_enabled ? aws_cloudwatch_dashboard.savings_plans_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for monitoring"
  value       = var.cloudwatch_dashboard_enabled ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.savings_plans_dashboard[0].dashboard_name}" : null
}

# Configuration outputs for reference
output "configuration" {
  description = "Configuration summary of the deployed infrastructure"
  value = {
    aws_region                   = data.aws_region.current.name
    aws_account_id              = data.aws_caller_identity.current.account_id
    environment                 = var.environment
    project_name                = var.project_name
    lambda_timeout              = var.lambda_timeout
    lambda_memory_size          = var.lambda_memory_size
    s3_bucket_versioning        = var.s3_bucket_versioning
    s3_lifecycle_days           = var.s3_bucket_lifecycle_days
    eventbridge_schedule_enabled = var.eventbridge_schedule_enabled
    eventbridge_schedule         = var.eventbridge_schedule_expression
    cloudwatch_dashboard_enabled = var.cloudwatch_dashboard_enabled
    cloudwatch_log_retention     = var.cloudwatch_log_retention_days
    analysis_parameters          = var.lambda_analysis_parameters
  }
}

# Usage instructions output
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    manual_invoke_command = "aws lambda invoke --function-name ${aws_lambda_function.savings_analyzer.function_name} --payload '{\"lookback_days\": \"${var.lambda_analysis_parameters.lookback_days}\", \"term_years\": \"${var.lambda_analysis_parameters.term_years}\", \"payment_option\": \"${var.lambda_analysis_parameters.payment_option}\", \"bucket_name\": \"${aws_s3_bucket.cost_recommendations.id}\"}' response.json"
    
    view_logs_command = "aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name} --start-time $(date -d '1 hour ago' +%s)000"
    
    list_reports_command = "aws s3 ls s3://${aws_s3_bucket.cost_recommendations.id}/savings-plans-recommendations/ --recursive"
    
    download_latest_report = "aws s3 cp s3://${aws_s3_bucket.cost_recommendations.id}/savings-plans-recommendations/$(aws s3 ls s3://${aws_s3_bucket.cost_recommendations.id}/savings-plans-recommendations/ --recursive | sort | tail -n 1 | awk '{print $4}') latest-report.json"
  }
}

# Cost estimation output
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = {
    lambda_function = "~$0.20 per 1M requests + $0.0000166667 per GB-second"
    s3_bucket       = "~$0.023 per GB stored (Standard tier)"
    cloudwatch_logs = "~$0.50 per GB ingested, $0.03 per GB stored"
    eventbridge     = "~$1.00 per million events"
    cost_explorer_api = "$0.01 per API request"
    total_estimated = "~$5-10 per month for typical usage"
  }
}

# Security considerations output
output "security_considerations" {
  description = "Security features and considerations for the deployed infrastructure"
  value = {
    iam_role_principle = "Least privilege access with specific Cost Explorer and Savings Plans permissions"
    s3_encryption     = "Server-side encryption with AES-256"
    s3_public_access  = "All public access blocked"
    lambda_vpc        = "Not required - uses AWS managed endpoints"
    logging           = "All function executions logged to CloudWatch"
    data_retention    = "S3 lifecycle policies for cost optimization"
  }
}