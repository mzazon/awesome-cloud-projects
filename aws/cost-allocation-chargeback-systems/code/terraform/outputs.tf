# Output values for the cost allocation and chargeback system

output "cost_reports_bucket_name" {
  description = "Name of the S3 bucket storing cost reports"
  value       = aws_s3_bucket.cost_reports.bucket
}

output "cost_reports_bucket_arn" {
  description = "ARN of the S3 bucket storing cost reports"
  value       = aws_s3_bucket.cost_reports.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost allocation alerts"
  value       = aws_sns_topic.cost_allocation_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for cost allocation alerts"
  value       = aws_sns_topic.cost_allocation_alerts.name
}

output "lambda_function_name" {
  description = "Name of the cost processing Lambda function"
  value       = aws_lambda_function.cost_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the cost processing Lambda function"
  value       = aws_lambda_function.cost_processor.arn
}

output "cost_category_arn" {
  description = "ARN of the cost category for standardized allocation"
  value       = aws_ce_cost_category.cost_center.arn
}

output "cost_category_effective_start" {
  description = "Effective start date of the cost category"
  value       = aws_ce_cost_category.cost_center.effective_start
}

output "cur_report_name" {
  description = "Name of the Cost and Usage Report"
  value       = aws_cur_report_definition.cost_allocation_report.report_name
}

output "department_budgets" {
  description = "List of created department budgets"
  value = {
    for k, v in aws_budgets_budget.department_budgets : k => {
      name   = v.name
      amount = v.limit_amount
      unit   = v.limit_unit
    }
  }
}

output "cost_anomaly_detector_arn" {
  description = "ARN of the cost anomaly detector (if enabled)"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_detector.department_anomaly_detector[0].arn : null
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled processing"
  value       = aws_cloudwatch_event_rule.cost_allocation_schedule.name
}

output "eventbridge_schedule" {
  description = "Schedule expression for automated cost processing"
  value       = aws_cloudwatch_event_rule.cost_allocation_schedule.schedule_expression
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_cost_processor.name
}

output "cost_allocation_tags" {
  description = "List of configured cost allocation tags"
  value       = var.cost_allocation_tags
}

output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = local.region
}

output "account_id" {
  description = "AWS account ID where resources were deployed"
  value       = local.account_id
}

# Instructions for post-deployment setup
output "post_deployment_instructions" {
  description = "Instructions for completing the cost allocation setup"
  value = <<-EOT
  
  COST ALLOCATION SYSTEM DEPLOYMENT COMPLETE
  ==========================================
  
  Next Steps:
  
  1. Activate Cost Allocation Tags (Manual Step Required):
     - Go to AWS Billing Console > Cost allocation tags
     - Activate the following tags: ${join(", ", var.cost_allocation_tags)}
     - Tags will become available for reporting in 24 hours
  
  2. Email Subscription Confirmation:
     ${var.notification_email != "" ? "- Check ${var.notification_email} for SNS subscription confirmation" : "- No email configured. Add subscription manually if needed"}
  
  3. Start Tagging Resources:
     - Apply 'Department' tags to all AWS resources
     - Use values: ${join(", ", distinct(flatten([for dept in var.department_budgets : dept.department_values])))}
  
  4. Test the System:
     - Run: aws lambda invoke --function-name ${aws_lambda_function.cost_processor.function_name} /tmp/result.json
     - Check SNS notifications and S3 bucket for reports
  
  5. Cost and Usage Reports:
     - Reports will be delivered to: s3://${aws_s3_bucket.cost_reports.bucket}/cost-reports/
     - Initial report delivery may take 24 hours
  
  6. Budget Monitoring:
     - ${length(aws_budgets_budget.department_budgets)} department budgets created
     - Alerts configured at ${min([for k, v in var.department_budgets : v.threshold_percent])}%-${max([for k, v in var.department_budgets : v.threshold_percent])}% thresholds
  
  7. Cost Explorer Integration:
     - Use Cost Categories in Cost Explorer for standardized reporting
     - Category: ${aws_ce_cost_category.cost_center.name}
  
  Useful Commands:
  - View budget status: aws budgets describe-budgets --account-id ${local.account_id}
  - Test Lambda function: aws lambda invoke --function-name ${aws_lambda_function.cost_processor.function_name} /tmp/test.json
  - List cost reports: aws s3 ls s3://${aws_s3_bucket.cost_reports.bucket}/cost-reports/ --recursive
  
  EOT
}

# Resource summary for quick reference
output "resource_summary" {
  description = "Summary of deployed resources"
  value = {
    s3_bucket          = aws_s3_bucket.cost_reports.bucket
    sns_topic          = aws_sns_topic.cost_allocation_alerts.name
    lambda_function    = aws_lambda_function.cost_processor.function_name
    cost_category      = aws_ce_cost_category.cost_center.name
    cur_report         = aws_cur_report_definition.cost_allocation_report.report_name
    budget_count       = length(aws_budgets_budget.department_budgets)
    anomaly_detection  = var.enable_cost_anomaly_detection
    schedule_frequency = "Monthly (1st day at 9 AM UTC)"
  }
}