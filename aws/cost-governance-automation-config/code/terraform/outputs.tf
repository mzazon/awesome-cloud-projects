# Outputs for Cost Governance Infrastructure

# S3 Bucket Outputs
output "config_bucket_name" {
  description = "Name of the S3 bucket for AWS Config"
  value       = aws_s3_bucket.config_bucket.bucket
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket for AWS Config"
  value       = aws_s3_bucket.config_bucket.arn
}

output "cost_governance_bucket_name" {
  description = "Name of the S3 bucket for cost governance reports"
  value       = aws_s3_bucket.cost_governance_bucket.bucket
}

output "cost_governance_bucket_arn" {
  description = "ARN of the S3 bucket for cost governance reports"
  value       = aws_s3_bucket.cost_governance_bucket.arn
}

# IAM Role Outputs
output "config_role_arn" {
  description = "ARN of the AWS Config service role"
  value       = aws_iam_role.config_role.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# SNS Topic Outputs
output "cost_governance_alerts_topic_arn" {
  description = "ARN of the cost governance alerts SNS topic"
  value       = aws_sns_topic.cost_governance_alerts.arn
}

output "critical_cost_actions_topic_arn" {
  description = "ARN of the critical cost actions SNS topic"
  value       = aws_sns_topic.critical_cost_actions.arn
}

# SQS Queue Outputs
output "cost_governance_queue_url" {
  description = "URL of the cost governance SQS queue"
  value       = aws_sqs_queue.cost_governance_queue.url
}

output "cost_governance_queue_arn" {
  description = "ARN of the cost governance SQS queue"
  value       = aws_sqs_queue.cost_governance_queue.arn
}

output "cost_governance_dlq_url" {
  description = "URL of the cost governance dead letter queue"
  value       = aws_sqs_queue.cost_governance_dlq.url
}

# Lambda Function Outputs
output "idle_instance_detector_arn" {
  description = "ARN of the idle instance detector Lambda function"
  value       = aws_lambda_function.idle_instance_detector.arn
}

output "idle_instance_detector_name" {
  description = "Name of the idle instance detector Lambda function"
  value       = aws_lambda_function.idle_instance_detector.function_name
}

output "volume_cleanup_arn" {
  description = "ARN of the volume cleanup Lambda function"
  value       = aws_lambda_function.volume_cleanup.arn
}

output "volume_cleanup_name" {
  description = "Name of the volume cleanup Lambda function"
  value       = aws_lambda_function.volume_cleanup.function_name
}

output "cost_reporter_arn" {
  description = "ARN of the cost reporter Lambda function"
  value       = aws_lambda_function.cost_reporter.arn
}

output "cost_reporter_name" {
  description = "Name of the cost reporter Lambda function"
  value       = aws_lambda_function.cost_reporter.function_name
}

# AWS Config Outputs
output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = var.enable_config_recorder ? aws_config_configuration_recorder.cost_governance[0].name : null
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = var.enable_config_recorder ? aws_config_delivery_channel.cost_governance[0].name : null
}

# Config Rules Outputs
output "idle_ec2_instances_rule_name" {
  description = "Name of the idle EC2 instances Config rule"
  value       = var.enable_config_recorder ? aws_config_config_rule.idle_ec2_instances[0].name : null
}

output "unattached_ebs_volumes_rule_name" {
  description = "Name of the unattached EBS volumes Config rule"
  value       = var.enable_config_recorder ? aws_config_config_rule.unattached_ebs_volumes[0].name : null
}

output "unused_load_balancers_rule_name" {
  description = "Name of the unused load balancers Config rule"
  value       = var.enable_config_recorder ? aws_config_config_rule.unused_load_balancers[0].name : null
}

# EventBridge Rules Outputs
output "config_compliance_changes_rule_name" {
  description = "Name of the Config compliance changes EventBridge rule"
  value       = aws_cloudwatch_event_rule.config_compliance_changes.name
}

output "config_compliance_changes_rule_arn" {
  description = "ARN of the Config compliance changes EventBridge rule"
  value       = aws_cloudwatch_event_rule.config_compliance_changes.arn
}

output "weekly_cost_optimization_scan_rule_name" {
  description = "Name of the weekly cost optimization scan EventBridge rule"
  value       = var.enable_scheduled_scans ? aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].name : null
}

output "weekly_cost_optimization_scan_rule_arn" {
  description = "ARN of the weekly cost optimization scan EventBridge rule"
  value       = var.enable_scheduled_scans ? aws_cloudwatch_event_rule.weekly_cost_optimization_scan[0].arn : null
}

# CloudWatch Log Groups Outputs
output "lambda_log_groups" {
  description = "CloudWatch Log Groups for Lambda functions"
  value = {
    idle_detector  = aws_cloudwatch_log_group.idle_detector_logs.name
    volume_cleanup = aws_cloudwatch_log_group.volume_cleanup_logs.name
    cost_reporter  = aws_cloudwatch_log_group.cost_reporter_logs.name
  }
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information and next steps"
  value = {
    region              = local.region
    account_id          = local.account_id
    environment         = var.environment
    project_name        = var.project_name
    config_enabled      = var.enable_config_recorder
    scheduled_scans     = var.enable_scheduled_scans
    notification_email  = var.notification_email
    resource_name_suffix = local.suffix
  }
}

# Resource URLs for Console Access
output "console_urls" {
  description = "AWS Console URLs for accessing deployed resources"
  value = {
    config_dashboard = "https://${local.region}.console.aws.amazon.com/config/home?region=${local.region}#/dashboard"
    lambda_functions = "https://${local.region}.console.aws.amazon.com/lambda/home?region=${local.region}#/functions"
    s3_buckets      = "https://s3.console.aws.amazon.com/s3/home?region=${local.region}"
    eventbridge     = "https://${local.region}.console.aws.amazon.com/events/home?region=${local.region}#/rules"
    sns_topics      = "https://${local.region}.console.aws.amazon.com/sns/v3/home?region=${local.region}#/topics"
    cloudwatch_logs = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:log-groups"
  }
}

# Cost Estimates (Approximate)
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for deployed resources (USD)"
  value = {
    config_service      = "$2.00 per Config rule per region (if enabled)"
    lambda_executions   = "$0.20 per 1M requests + $0.0000166667 per GB-second"
    s3_storage         = "$0.023 per GB (Standard), $0.0125 per GB (Standard-IA)"
    sns_notifications  = "$0.50 per 1M requests"
    cloudwatch_logs    = "$0.50 per GB ingested + $0.03 per GB stored"
    eventbridge        = "$1.00 per million events"
    sqs_requests       = "$0.40 per 1M requests"
    total_estimate     = "$20-50 per month (varies by usage)"
    note              = "Costs depend on number of resources monitored and optimization actions performed"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_config_rules = "aws configservice describe-config-rules --region ${local.region}"
    check_lambda_functions = "aws lambda list-functions --region ${local.region} --query 'Functions[?contains(FunctionName, `${local.name_prefix}`)].FunctionName'"
    test_sns_notification = "aws sns publish --topic-arn ${aws_sns_topic.cost_governance_alerts.arn} --subject 'Test' --message 'Test message' --region ${local.region}"
    check_eventbridge_rules = "aws events list-rules --region ${local.region} --query 'Rules[?contains(Name, `${local.name_prefix}`)].{Name:Name,State:State}'"
    view_s3_buckets = "aws s3 ls | grep ${local.name_prefix}"
  }
}