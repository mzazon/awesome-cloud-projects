# Output values for VPC Flow Logs monitoring infrastructure

output "vpc_id" {
  description = "ID of the VPC being monitored"
  value       = data.aws_vpc.selected.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC being monitored"
  value       = data.aws_vpc.selected.cidr_block
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing flow logs"
  value       = var.enable_s3_flow_logs ? aws_s3_bucket.flow_logs[0].bucket : null
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing flow logs"
  value       = var.enable_s3_flow_logs ? aws_s3_bucket.flow_logs[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for flow logs"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for flow logs"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].arn : null
}

output "flow_log_cloudwatch_id" {
  description = "ID of the CloudWatch flow log"
  value       = var.enable_cloudwatch_flow_logs ? aws_flow_log.cloudwatch[0].id : null
}

output "flow_log_s3_id" {
  description = "ID of the S3 flow log"
  value       = var.enable_s3_flow_logs ? aws_flow_log.s3[0].id : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function for anomaly detection"
  value       = var.enable_lambda_analysis ? aws_lambda_function.anomaly_detector[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for anomaly detection"
  value       = var.enable_lambda_analysis ? aws_lambda_function.anomaly_detector[0].arn : null
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for flow logs analysis"
  value       = var.enable_athena_analysis && var.enable_s3_flow_logs ? aws_athena_workgroup.flow_logs[0].name : null
}

output "athena_database_name" {
  description = "Name of the Athena database for flow logs"
  value       = var.enable_athena_analysis && var.enable_s3_flow_logs ? aws_athena_database.flow_logs[0].name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.enable_cloudwatch_flow_logs ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.network_monitoring[0].dashboard_name}" : null
}

output "iam_role_flow_logs_arn" {
  description = "ARN of the IAM role for VPC Flow Logs"
  value       = aws_iam_role.flow_logs.arn
}

output "iam_role_lambda_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = var.enable_lambda_analysis ? aws_iam_role.lambda[0].arn : null
}

# CloudWatch Alarms
output "alarm_rejected_connections_name" {
  description = "Name of the CloudWatch alarm for rejected connections"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_metric_alarm.rejected_connections[0].alarm_name : null
}

output "alarm_high_data_transfer_name" {
  description = "Name of the CloudWatch alarm for high data transfer"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_metric_alarm.high_data_transfer[0].alarm_name : null
}

output "alarm_external_connections_name" {
  description = "Name of the CloudWatch alarm for external connections"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_metric_alarm.external_connections[0].alarm_name : null
}

# Metric Filters
output "metric_filter_rejected_connections" {
  description = "Name of the metric filter for rejected connections"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_log_metric_filter.rejected_connections[0].name : null
}

output "metric_filter_high_data_transfer" {
  description = "Name of the metric filter for high data transfer"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_log_metric_filter.high_data_transfer[0].name : null
}

output "metric_filter_external_connections" {
  description = "Name of the metric filter for external connections"
  value       = var.enable_cloudwatch_flow_logs ? aws_cloudwatch_log_metric_filter.external_connections[0].name : null
}

# Sample Athena Queries
output "sample_athena_queries" {
  description = "Sample Athena queries for analyzing flow logs"
  value = var.enable_athena_analysis && var.enable_s3_flow_logs ? {
    top_talkers = "SELECT srcaddr, dstaddr, sum(bytes) as total_bytes FROM ${replace("${local.name_prefix}_flow_logs", "-", "_")}.vpc_flow_logs WHERE year='2024' GROUP BY srcaddr, dstaddr ORDER BY total_bytes DESC LIMIT 10"
    rejected_connections = "SELECT srcaddr, dstaddr, count(*) as reject_count FROM ${replace("${local.name_prefix}_flow_logs", "-", "_")}.vpc_flow_logs WHERE action='REJECT' GROUP BY srcaddr, dstaddr ORDER BY reject_count DESC LIMIT 20"
    external_traffic = "SELECT srcaddr, dstaddr, sum(bytes) as total_bytes FROM ${replace("${local.name_prefix}_flow_logs", "-", "_")}.vpc_flow_logs WHERE srcaddr NOT LIKE '10.%' AND srcaddr NOT LIKE '172.%' AND srcaddr NOT LIKE '192.168.%' GROUP BY srcaddr, dstaddr ORDER BY total_bytes DESC LIMIT 10"
  } : null
}

# Monitoring URLs
output "monitoring_urls" {
  description = "Useful AWS Console URLs for monitoring"
  value = {
    cloudwatch_logs = var.enable_cloudwatch_flow_logs ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.flow_logs[0].name, "/", "$252F")}" : null
    cloudwatch_alarms = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#alarmsV2:?search=${local.name_prefix}"
    s3_bucket = var.enable_s3_flow_logs ? "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.flow_logs[0].bucket}" : null
    athena_workgroup = var.enable_athena_analysis && var.enable_s3_flow_logs ? "https://${var.aws_region}.console.aws.amazon.com/athena/home?region=${var.aws_region}#/workgroups/view/${aws_athena_workgroup.flow_logs[0].name}" : null
    lambda_function = var.enable_lambda_analysis ? "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.anomaly_detector[0].function_name}" : null
  }
}

# Cost estimation information
output "cost_estimation" {
  description = "Estimated monthly costs for the monitoring solution"
  value = {
    note = "Costs vary based on traffic volume and retention periods"
    vpc_flow_logs = "~$0.50 per million flow log records"
    cloudwatch_logs = "~$0.50 per GB ingested + $0.03 per GB stored"
    s3_storage = "~$0.023 per GB (Standard) + data transfer costs"
    lambda = "~$0.20 per million requests + compute costs"
    athena = "~$5.00 per TB of data scanned"
    cloudwatch_metrics = "~$0.30 per metric + $0.10 per alarm"
  }
}

# Next steps and recommendations
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    email_subscription = var.notification_email == "" ? "Configure email notification by setting the notification_email variable" : "Email notifications configured for ${var.notification_email}"
    dashboard_access = "Access the CloudWatch dashboard to monitor network metrics in real-time"
    athena_setup = var.enable_athena_analysis && var.enable_s3_flow_logs ? "Wait 10-15 minutes for flow logs data, then create Athena table and run sample queries" : "Enable Athena analysis for advanced flow logs querying"
    tuning = "Monitor alarm sensitivity and adjust thresholds based on your environment"
    testing = "Test the monitoring system by generating network traffic and verifying alerts"
  }
}