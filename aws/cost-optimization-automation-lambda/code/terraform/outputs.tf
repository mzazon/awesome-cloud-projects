# Primary resource outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for cost optimization reports"
  value       = aws_s3_bucket.cost_optimization_reports.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for cost optimization reports"
  value       = aws_s3_bucket.cost_optimization_reports.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for tracking cost optimization actions"
  value       = aws_dynamodb_table.cost_optimization_tracking.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for tracking cost optimization actions"
  value       = aws_dynamodb_table.cost_optimization_tracking.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for cost optimization alerts"
  value       = aws_sns_topic.cost_optimization_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost optimization alerts"
  value       = aws_sns_topic.cost_optimization_alerts.arn
}

# Lambda function outputs
output "cost_analysis_function_name" {
  description = "Name of the cost analysis Lambda function"
  value       = aws_lambda_function.cost_optimization_analysis.function_name
}

output "cost_analysis_function_arn" {
  description = "ARN of the cost analysis Lambda function"
  value       = aws_lambda_function.cost_optimization_analysis.arn
}

output "remediation_function_name" {
  description = "Name of the remediation Lambda function"
  value       = aws_lambda_function.cost_optimization_remediation.function_name
}

output "remediation_function_arn" {
  description = "ARN of the remediation Lambda function"
  value       = aws_lambda_function.cost_optimization_remediation.arn
}

# IAM role outputs
output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "scheduler_execution_role_name" {
  description = "Name of the EventBridge Scheduler execution IAM role"
  value       = aws_iam_role.scheduler_execution_role.name
}

output "scheduler_execution_role_arn" {
  description = "ARN of the EventBridge Scheduler execution IAM role"
  value       = aws_iam_role.scheduler_execution_role.arn
}

# EventBridge Scheduler outputs
output "schedule_group_name" {
  description = "Name of the EventBridge schedule group"
  value       = aws_scheduler_schedule_group.cost_optimization.name
}

output "schedule_group_arn" {
  description = "ARN of the EventBridge schedule group"
  value       = aws_scheduler_schedule_group.cost_optimization.arn
}

output "daily_analysis_schedule_name" {
  description = "Name of the daily analysis schedule"
  value       = aws_scheduler_schedule.daily_analysis.name
}

output "daily_analysis_schedule_arn" {
  description = "ARN of the daily analysis schedule"
  value       = aws_scheduler_schedule.daily_analysis.arn
}

output "weekly_analysis_schedule_name" {
  description = "Name of the weekly comprehensive analysis schedule"
  value       = aws_scheduler_schedule.weekly_analysis.name
}

output "weekly_analysis_schedule_arn" {
  description = "ARN of the weekly comprehensive analysis schedule"
  value       = aws_scheduler_schedule.weekly_analysis.arn
}

# CloudWatch outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.cost_optimization.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization.dashboard_name}"
}

output "cost_analysis_log_group_name" {
  description = "Name of the cost analysis Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.cost_analysis_logs.name
}

output "cost_analysis_log_group_arn" {
  description = "ARN of the cost analysis Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.cost_analysis_logs.arn
}

output "remediation_log_group_name" {
  description = "Name of the remediation Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.remediation_logs.name
}

output "remediation_log_group_arn" {
  description = "ARN of the remediation Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.remediation_logs.arn
}

# Configuration outputs
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Deployment information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    project_name         = var.project_name
    environment          = var.environment
    aws_region          = data.aws_region.current.name
    aws_account_id      = data.aws_caller_identity.current.account_id
    resources_deployed  = {
      s3_bucket          = aws_s3_bucket.cost_optimization_reports.bucket
      dynamodb_table     = aws_dynamodb_table.cost_optimization_tracking.name
      sns_topic          = aws_sns_topic.cost_optimization_alerts.name
      lambda_functions   = [
        aws_lambda_function.cost_optimization_analysis.function_name,
        aws_lambda_function.cost_optimization_remediation.function_name
      ]
      schedules          = [
        aws_scheduler_schedule.daily_analysis.name,
        aws_scheduler_schedule.weekly_analysis.name
      ]
      cloudwatch_dashboard = aws_cloudwatch_dashboard.cost_optimization.dashboard_name
    }
    configuration = {
      auto_remediation_enabled = var.enable_auto_remediation
      analysis_schedule        = var.analysis_schedule_expression
      comprehensive_schedule   = var.comprehensive_analysis_schedule_expression
      notification_email       = var.notification_email != "" ? var.notification_email : "Not configured"
      cost_alert_threshold     = var.cost_alert_threshold
    }
  }
}

# Next steps information
output "next_steps" {
  description = "Next steps after deployment"
  value = {
    1 = "Confirm email subscription to SNS topic: ${aws_sns_topic.cost_optimization_alerts.arn}"
    2 = "Test the system by invoking the analysis function: aws lambda invoke --function-name ${aws_lambda_function.cost_optimization_analysis.function_name} --payload '{}' response.json"
    3 = "Monitor the CloudWatch dashboard: ${aws_cloudwatch_dashboard.cost_optimization.dashboard_name}"
    4 = "Review DynamoDB table for cost optimization opportunities: ${aws_dynamodb_table.cost_optimization_tracking.name}"
    5 = "Check S3 bucket for generated reports: ${aws_s3_bucket.cost_optimization_reports.bucket}"
    6 = "Adjust auto-remediation settings if needed by updating the enable_auto_remediation variable"
  }
}

# Cost estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the deployed resources (USD)"
  value = {
    lambda_functions = "~$10-30 (based on execution frequency)"
    dynamodb        = "~$5-15 (based on read/write capacity)"
    s3_storage      = "~$1-5 (based on report storage)"
    sns_notifications = "~$0.50-2 (based on notification volume)"
    cloudwatch_logs = "~$2-8 (based on log retention)"
    eventbridge     = "~$0.50-2 (based on schedule frequency)"
    total_estimate  = "~$19-62 per month"
    note           = "Costs may vary based on actual usage patterns and AWS pricing changes"
  }
}

# Security recommendations
output "security_recommendations" {
  description = "Security recommendations for the deployed system"
  value = {
    1 = "Review and restrict IAM policies to minimum required permissions"
    2 = "Enable AWS CloudTrail for audit logging of all API calls"
    3 = "Configure AWS Config rules for compliance monitoring"
    4 = "Set up AWS GuardDuty for threat detection"
    5 = "Regularly review and rotate IAM credentials"
    6 = "Monitor CloudWatch logs for unusual activity patterns"
    7 = "Consider encrypting SNS messages if sensitive data is included"
    8 = "Implement least privilege access for users managing the system"
  }
}