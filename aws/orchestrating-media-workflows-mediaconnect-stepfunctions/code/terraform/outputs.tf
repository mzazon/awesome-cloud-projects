# MediaConnect Flow outputs
output "mediaconnect_flow_arn" {
  description = "ARN of the MediaConnect flow"
  value       = aws_mediaconnect_flow.live_stream.arn
}

output "mediaconnect_flow_name" {
  description = "Name of the MediaConnect flow"
  value       = aws_mediaconnect_flow.live_stream.name
}

output "mediaconnect_ingest_ip" {
  description = "Ingest IP address for the MediaConnect flow"
  value       = aws_mediaconnect_flow.live_stream.source[0].ingest_ip
  sensitive   = false
}

output "mediaconnect_ingest_port" {
  description = "Ingest port for the MediaConnect flow"
  value       = aws_mediaconnect_flow.live_stream.source[0].ingest_port
}

output "mediaconnect_source_arn" {
  description = "ARN of the MediaConnect source"
  value       = aws_mediaconnect_flow.live_stream.source[0].source_arn
}

# Step Functions outputs
output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.media_workflow.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.media_workflow.name
}

# Lambda function outputs
output "stream_monitor_lambda_arn" {
  description = "ARN of the stream monitor Lambda function"
  value       = aws_lambda_function.stream_monitor.arn
}

output "stream_monitor_lambda_name" {
  description = "Name of the stream monitor Lambda function"
  value       = aws_lambda_function.stream_monitor.function_name
}

output "alert_handler_lambda_arn" {
  description = "ARN of the alert handler Lambda function"
  value       = aws_lambda_function.alert_handler.arn
}

output "alert_handler_lambda_name" {
  description = "Name of the alert handler Lambda function"
  value       = aws_lambda_function.alert_handler.function_name
}

# SNS outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for media alerts"
  value       = aws_sns_topic.media_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for media alerts"
  value       = aws_sns_topic.media_alerts.name
}

# CloudWatch outputs
output "packet_loss_alarm_name" {
  description = "Name of the packet loss CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.packet_loss_alarm.alarm_name
}

output "jitter_alarm_name" {
  description = "Name of the jitter CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.jitter_alarm.alarm_name
}

output "workflow_trigger_alarm_name" {
  description = "Name of the workflow trigger CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.workflow_trigger_alarm.alarm_name
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.media_dashboard.dashboard_name
}

# EventBridge outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.alarm_rule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.alarm_rule.arn
}

# S3 bucket outputs
output "lambda_artifacts_bucket_name" {
  description = "Name of the S3 bucket for Lambda artifacts"
  value       = aws_s3_bucket.lambda_artifacts.bucket
}

output "lambda_artifacts_bucket_arn" {
  description = "ARN of the S3 bucket for Lambda artifacts"
  value       = aws_s3_bucket.lambda_artifacts.arn
}

# IAM role outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.step_functions_role.arn
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge execution role"
  value       = aws_iam_role.eventbridge_role.arn
}

# Console URLs for easy access
output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.media_dashboard.dashboard_name}"
}

output "step_functions_console_url" {
  description = "URL to access the Step Functions state machine in the console"
  value       = "https://console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.media_workflow.arn}"
}

output "mediaconnect_console_url" {
  description = "URL to access the MediaConnect flow in the console"
  value       = "https://console.aws.amazon.com/mediaconnect/home?region=${data.aws_region.current.name}#/flows/${split("/", aws_mediaconnect_flow.live_stream.arn)[1]}"
}

# Configuration summary
output "streaming_configuration" {
  description = "Summary of streaming configuration"
  value = {
    ingest_endpoint = "${aws_mediaconnect_flow.live_stream.source[0].ingest_ip}:${aws_mediaconnect_flow.live_stream.source[0].ingest_port}"
    protocol        = "RTP"
    primary_output  = "${var.primary_output_destination}:${var.primary_output_port}"
    backup_output   = "${var.backup_output_destination}:${var.backup_output_port}"
    whitelist_cidr  = var.source_whitelist_cidr
  }
}

output "monitoring_configuration" {
  description = "Summary of monitoring configuration"
  value = {
    packet_loss_threshold     = "${var.packet_loss_threshold}%"
    jitter_threshold         = "${var.jitter_threshold_ms}ms"
    workflow_trigger_threshold = "${var.workflow_trigger_threshold}%"
    notification_email       = var.notification_email
  }
}

# Resource counts
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    mediaconnect_flows     = 1
    lambda_functions       = 2
    step_functions         = 1
    cloudwatch_alarms      = 3
    sns_topics            = 1
    eventbridge_rules     = 1
    s3_buckets           = 1
    iam_roles            = 3
    cloudwatch_dashboards = 1
  }
}