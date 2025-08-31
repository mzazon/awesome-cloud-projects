# Outputs for Intelligent Web Scraping Infrastructure
# This file defines all output values that are useful for verification,
# integration, and operational management of the deployed infrastructure

#==============================================================================
# S3 BUCKET OUTPUTS
#==============================================================================

output "s3_input_bucket_name" {
  description = "Name of the S3 bucket for storing scraping configurations and input data"
  value       = aws_s3_bucket.input_bucket.id
  sensitive   = false
}

output "s3_input_bucket_arn" {
  description = "ARN of the S3 bucket for input configurations"
  value       = aws_s3_bucket.input_bucket.arn
  sensitive   = false
}

output "s3_output_bucket_name" {
  description = "Name of the S3 bucket for storing processed results and scraped data"
  value       = aws_s3_bucket.output_bucket.id
  sensitive   = false
}

output "s3_output_bucket_arn" {
  description = "ARN of the S3 bucket for output data"
  value       = aws_s3_bucket.output_bucket.arn
  sensitive   = false
}

output "s3_input_bucket_domain_name" {
  description = "Domain name of the input S3 bucket"
  value       = aws_s3_bucket.input_bucket.bucket_domain_name
  sensitive   = false
}

output "s3_output_bucket_domain_name" {
  description = "Domain name of the output S3 bucket"
  value       = aws_s3_bucket.output_bucket.bucket_domain_name
  sensitive   = false
}

#==============================================================================
# LAMBDA FUNCTION OUTPUTS
#==============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function for scraping orchestration"
  value       = aws_lambda_function.scraper_orchestrator.function_name
  sensitive   = false
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for scraping orchestration"
  value       = aws_lambda_function.scraper_orchestrator.arn
  sensitive   = false
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function (for API Gateway integration)"
  value       = aws_lambda_function.scraper_orchestrator.invoke_arn
  sensitive   = false
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function with version"
  value       = aws_lambda_function.scraper_orchestrator.qualified_arn
  sensitive   = false
}

output "lambda_function_version" {
  description = "Latest published version of the Lambda function"
  value       = aws_lambda_function.scraper_orchestrator.version
  sensitive   = false
}

output "lambda_function_last_modified" {
  description = "Date when the Lambda function was last modified"
  value       = aws_lambda_function.scraper_orchestrator.last_modified
  sensitive   = false
}

output "lambda_function_timeout" {
  description = "Timeout configuration of the Lambda function in seconds"
  value       = aws_lambda_function.scraper_orchestrator.timeout
  sensitive   = false
}

output "lambda_function_memory_size" {
  description = "Memory configuration of the Lambda function in MB"
  value       = aws_lambda_function.scraper_orchestrator.memory_size
  sensitive   = false
}

#==============================================================================
# IAM ROLE AND POLICY OUTPUTS
#==============================================================================

output "lambda_role_name" {
  description = "Name of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.name
  sensitive   = false
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.arn
  sensitive   = false
}

output "lambda_role_unique_id" {
  description = "Unique ID of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_role.unique_id
  sensitive   = false
}

#==============================================================================
# CLOUDWATCH MONITORING OUTPUTS
#==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
  sensitive   = false
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
  sensitive   = false
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard for monitoring scraping activities"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.scraping_dashboard.dashboard_name}"
  sensitive   = false
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for monitoring"
  value       = aws_cloudwatch_dashboard.scraping_dashboard.dashboard_name
  sensitive   = false
}

#==============================================================================
# EVENTBRIDGE SCHEDULING OUTPUTS
#==============================================================================

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled scraping"
  value       = aws_cloudwatch_event_rule.schedule.name
  sensitive   = false
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled scraping"
  value       = aws_cloudwatch_event_rule.schedule.arn
  sensitive   = false
}

output "eventbridge_rule_schedule" {
  description = "Schedule expression for the EventBridge rule"
  value       = aws_cloudwatch_event_rule.schedule.schedule_expression
  sensitive   = false
}

output "eventbridge_rule_state" {
  description = "Current state of the EventBridge rule (ENABLED/DISABLED)"
  value       = aws_cloudwatch_event_rule.schedule.state
  sensitive   = false
}

#==============================================================================
# SQS DEAD LETTER QUEUE OUTPUTS
#==============================================================================

output "sqs_dlq_name" {
  description = "Name of the SQS Dead Letter Queue for failed Lambda executions"
  value       = aws_sqs_queue.dlq.name
  sensitive   = false
}

output "sqs_dlq_arn" {
  description = "ARN of the SQS Dead Letter Queue"
  value       = aws_sqs_queue.dlq.arn
  sensitive   = false
}

output "sqs_dlq_url" {
  description = "URL of the SQS Dead Letter Queue"
  value       = aws_sqs_queue.dlq.url
  sensitive   = false
}

#==============================================================================
# CLOUDWATCH ALARMS OUTPUTS
#==============================================================================

output "lambda_error_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda errors"
  value       = var.enable_alerts ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
  sensitive   = false
}

output "lambda_error_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda errors"
  value       = var.enable_alerts ? aws_cloudwatch_metric_alarm.lambda_errors[0].arn : null
  sensitive   = false
}

output "lambda_duration_alarm_name" {
  description = "Name of the CloudWatch alarm for Lambda duration"
  value       = var.enable_alerts ? aws_cloudwatch_metric_alarm.lambda_duration[0].alarm_name : null
  sensitive   = false
}

output "lambda_duration_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda duration"
  value       = var.enable_alerts ? aws_cloudwatch_metric_alarm.lambda_duration[0].arn : null
  sensitive   = false
}

#==============================================================================
# CONFIGURATION OUTPUTS
#==============================================================================

output "scraper_config_s3_key" {
  description = "S3 key for the scraping configuration file"
  value       = aws_s3_object.scraper_config.key
  sensitive   = false
}

output "data_processing_config_s3_key" {
  description = "S3 key for the data processing configuration file"
  value       = aws_s3_object.data_processing_config.key
  sensitive   = false
}

output "project_name" {
  description = "Generated project name with random suffix for resource identification"
  value       = local.project_name
  sensitive   = false
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
  sensitive   = false
}

#==============================================================================
# TESTING AND VALIDATION OUTPUTS
#==============================================================================

output "lambda_test_command" {
  description = "AWS CLI command to test the Lambda function manually"
  value = <<-EOT
    aws lambda invoke \
      --function-name ${aws_lambda_function.scraper_orchestrator.function_name} \
      --payload '{"bucket_input":"${aws_s3_bucket.input_bucket.id}","bucket_output":"${aws_s3_bucket.output_bucket.id}","test_mode":true}' \
      --region ${var.aws_region} \
      response.json && cat response.json
  EOT
  sensitive = false
}

output "s3_list_results_command" {
  description = "AWS CLI command to list scraped results in the output bucket"
  value = <<-EOT
    aws s3 ls s3://${aws_s3_bucket.output_bucket.id}/ --recursive --human-readable
  EOT
  sensitive = false
}

output "logs_tail_command" {
  description = "AWS CLI command to tail Lambda function logs"
  value = <<-EOT
    aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow --region ${var.aws_region}
  EOT
  sensitive = false
}

#==============================================================================
# COST AND RESOURCE TRACKING OUTPUTS
#==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the intelligent scraping infrastructure"
  value = {
    lambda_execution = "Approximately $5-15/month for 100 executions/day at 900s timeout"
    s3_storage      = "Approximately $1-5/month for 10GB of data with versioning"
    cloudwatch      = "Approximately $2-8/month for logs and custom metrics"
    agentcore       = "AgentCore preview pricing - check AWS console for current rates"
    total_estimate  = "Approximately $8-28/month (excluding AgentCore preview costs)"
  }
  sensitive = false
}

output "resource_tags" {
  description = "Common tags applied to all resources for cost allocation and management"
  value       = local.common_tags
  sensitive   = false
}

#==============================================================================
# INTEGRATION AND EXTENSION OUTPUTS
#==============================================================================

output "api_gateway_integration_config" {
  description = "Configuration values for potential API Gateway integration"
  value = {
    lambda_function_name = aws_lambda_function.scraper_orchestrator.function_name
    lambda_invoke_arn   = aws_lambda_function.scraper_orchestrator.invoke_arn
    lambda_role_arn     = aws_iam_role.lambda_role.arn
  }
  sensitive = false
}

output "vpc_integration_requirements" {
  description = "Requirements for VPC integration if enhanced security is needed"
  value = {
    required_vpc_endpoints = ["s3", "logs", "monitoring"]
    security_group_ports  = ["443 (HTTPS)", "80 (HTTP)"]
    subnet_requirements   = "Private subnets with NAT Gateway for internet access"
  }
  sensitive = false
}

#==============================================================================
# OPERATIONAL OUTPUTS
#==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed intelligent web scraping infrastructure"
  value = {
    infrastructure_type    = "Intelligent Web Scraping with AgentCore"
    primary_services      = ["Bedrock AgentCore", "Lambda", "S3", "CloudWatch", "EventBridge"]
    deployment_timestamp  = timestamp()
    environment          = var.environment
    region               = var.aws_region
    automation_enabled   = var.enable_scheduling
    monitoring_enabled   = var.enable_alerts
  }
  sensitive = false
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Test the Lambda function using the provided test command",
    "Review CloudWatch dashboard for monitoring setup",
    "Configure additional scraping scenarios in the S3 input bucket",
    "Set up SNS notifications for alerts if not already configured",
    "Consider implementing VPC integration for enhanced security",
    "Monitor costs and optimize resource configurations as needed"
  ]
  sensitive = false
}