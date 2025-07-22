# Outputs for Reserved Instance Management Automation
# This file defines all output values for the Terraform configuration

# =====================================================
# Core Infrastructure Outputs
# =====================================================

output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = local.account_id
}

# =====================================================
# S3 Bucket Outputs
# =====================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for RI reports"
  value       = aws_s3_bucket.ri_reports.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for RI reports"
  value       = aws_s3_bucket.ri_reports.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.ri_reports.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.ri_reports.bucket_regional_domain_name
}

# =====================================================
# DynamoDB Table Outputs
# =====================================================

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for RI tracking"
  value       = aws_dynamodb_table.ri_tracking.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for RI tracking"
  value       = aws_dynamodb_table.ri_tracking.arn
}

# =====================================================
# SNS Topic Outputs
# =====================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for RI alerts"
  value       = aws_sns_topic.ri_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for RI alerts"
  value       = aws_sns_topic.ri_alerts.arn
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.ri_alerts.display_name
}

# =====================================================
# IAM Role Outputs
# =====================================================

output "lambda_execution_role_name" {
  description = "Name of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

# =====================================================
# Lambda Function Outputs
# =====================================================

output "lambda_functions" {
  description = "Information about all Lambda functions"
  value = {
    utilization = {
      function_name = aws_lambda_function.ri_utilization.function_name
      arn          = aws_lambda_function.ri_utilization.arn
      invoke_arn   = aws_lambda_function.ri_utilization.invoke_arn
      version      = aws_lambda_function.ri_utilization.version
    }
    recommendations = {
      function_name = aws_lambda_function.ri_recommendations.function_name
      arn          = aws_lambda_function.ri_recommendations.arn
      invoke_arn   = aws_lambda_function.ri_recommendations.invoke_arn
      version      = aws_lambda_function.ri_recommendations.version
    }
    monitoring = {
      function_name = aws_lambda_function.ri_monitoring.function_name
      arn          = aws_lambda_function.ri_monitoring.arn
      invoke_arn   = aws_lambda_function.ri_monitoring.invoke_arn
      version      = aws_lambda_function.ri_monitoring.version
    }
  }
}

output "ri_utilization_function_name" {
  description = "Name of the RI utilization analysis Lambda function"
  value       = aws_lambda_function.ri_utilization.function_name
}

output "ri_recommendations_function_name" {
  description = "Name of the RI recommendations Lambda function"
  value       = aws_lambda_function.ri_recommendations.function_name
}

output "ri_monitoring_function_name" {
  description = "Name of the RI monitoring Lambda function"
  value       = aws_lambda_function.ri_monitoring.function_name
}

# =====================================================
# EventBridge Rules Outputs
# =====================================================

output "eventbridge_rules" {
  description = "Information about EventBridge rules"
  value = {
    daily_utilization = {
      name = aws_cloudwatch_event_rule.daily_utilization.name
      arn  = aws_cloudwatch_event_rule.daily_utilization.arn
      schedule = var.daily_analysis_schedule
    }
    weekly_recommendations = {
      name = aws_cloudwatch_event_rule.weekly_recommendations.name
      arn  = aws_cloudwatch_event_rule.weekly_recommendations.arn
      schedule = var.weekly_recommendations_schedule
    }
    weekly_monitoring = {
      name = aws_cloudwatch_event_rule.weekly_monitoring.name
      arn  = aws_cloudwatch_event_rule.weekly_monitoring.arn
      schedule = var.weekly_monitoring_schedule
    }
  }
}

# =====================================================
# CloudWatch Log Groups Outputs
# =====================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    utilization     = aws_cloudwatch_log_group.ri_utilization_logs.name
    recommendations = aws_cloudwatch_log_group.ri_recommendations_logs.name
    monitoring      = aws_cloudwatch_log_group.ri_monitoring_logs.name
  }
}

# =====================================================
# Configuration Outputs
# =====================================================

output "configuration" {
  description = "Key configuration values for the RI management system"
  value = {
    utilization_threshold       = var.utilization_threshold
    expiration_warning_days     = var.expiration_warning_days
    critical_expiration_days    = var.critical_expiration_days
    lambda_timeout             = var.lambda_timeout
    lambda_memory_size         = var.lambda_memory_size
    cloudwatch_log_retention   = var.cloudwatch_log_retention_days
    s3_lifecycle_days          = var.s3_bucket_lifecycle_days
    enable_cost_explorer_api   = var.enable_cost_explorer_api
    enable_xray_tracing       = var.enable_xray_tracing
    dynamodb_pitr_enabled     = var.dynamodb_point_in_time_recovery
    s3_versioning_enabled     = var.s3_bucket_versioning
  }
}

# =====================================================
# Deployment Information Outputs
# =====================================================

output "deployment_info" {
  description = "Information about the deployment"
  value = {
    random_suffix = local.random_suffix
    deployed_at   = timestamp()
    terraform_workspace = terraform.workspace
  }
}

# =====================================================
# Usage Instructions Outputs
# =====================================================

output "usage_instructions" {
  description = "Instructions for using the RI management system"
  value = {
    view_reports = "aws s3 ls s3://${aws_s3_bucket.ri_reports.bucket}/ --recursive"
    test_utilization_function = "aws lambda invoke --function-name ${aws_lambda_function.ri_utilization.function_name} --payload '{}' response.json"
    test_recommendations_function = "aws lambda invoke --function-name ${aws_lambda_function.ri_recommendations.function_name} --payload '{}' response.json"
    test_monitoring_function = "aws lambda invoke --function-name ${aws_lambda_function.ri_monitoring.function_name} --payload '{}' response.json"
    view_dynamodb_data = "aws dynamodb scan --table-name ${aws_dynamodb_table.ri_tracking.name} --max-items 10"
    subscribe_to_alerts = var.notification_email == "" ? "aws sns subscribe --topic-arn ${aws_sns_topic.ri_alerts.arn} --protocol email --notification-endpoint YOUR_EMAIL" : "Email subscription already configured"
  }
}

# =====================================================
# Monitoring Outputs
# =====================================================

output "monitoring_dashboards" {
  description = "CloudWatch dashboard URLs for monitoring"
  value = {
    lambda_functions = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:"
    cost_explorer = "https://console.aws.amazon.com/cost-management/home#/cost-explorer"
    reserved_instances = "https://${var.aws_region}.console.aws.amazon.com/ec2/home?region=${var.aws_region}#ReservedInstances:"
  }
}

# =====================================================
# Cost Information Outputs
# =====================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the RI management system"
  value = {
    lambda_executions = "~$2-5 (based on execution frequency)"
    dynamodb = "~$1-3 (pay-per-request pricing)"
    s3_storage = "~$1-5 (depending on report volume)"
    sns_notifications = "~$0.50-2 (based on alert frequency)"
    cloudwatch_logs = "~$0.50-2 (based on log volume)"
    cost_explorer_api = "~$10-50 (first 1000 requests free, then $0.01/request)"
    total_estimated = "~$15-67 per month"
    note = "Costs depend on usage patterns and data volume"
  }
}

# =====================================================
# Security Information Outputs
# =====================================================

output "security_features" {
  description = "Security features implemented in the solution"
  value = {
    s3_encryption = "AES256 server-side encryption enabled"
    s3_public_access = "All public access blocked"
    dynamodb_encryption = "Server-side encryption enabled"
    sns_encryption = "KMS encryption with AWS managed key"
    iam_least_privilege = "IAM roles follow least privilege principle"
    vpc_endpoints = "Consider adding VPC endpoints for enhanced security"
    lambda_environment_variables = "Sensitive variables should use AWS Systems Manager Parameter Store"
  }
}

# =====================================================
# Next Steps Outputs
# =====================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm SNS email subscription if email was provided",
    "2. Test Lambda functions using the provided CLI commands",
    "3. Review initial RI reports in S3 bucket after first execution",
    "4. Customize utilization thresholds based on your requirements",
    "5. Consider adding Slack webhook URL for additional notifications",
    "6. Set up CloudWatch dashboards for enhanced monitoring",
    "7. Review and adjust EventBridge schedules as needed",
    "8. Implement VPC endpoints for enhanced security (optional)",
    "9. Configure AWS Systems Manager Parameter Store for sensitive variables",
    "10. Set up cross-account access if managing multiple AWS accounts"
  ]
}