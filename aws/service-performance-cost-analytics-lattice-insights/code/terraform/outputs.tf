# VPC Lattice Service Network Outputs
output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.analytics_network.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.analytics_network.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.analytics_network.name
}

# Sample Service Outputs (conditional)
output "sample_service_id" {
  description = "ID of the sample VPC Lattice service (if created)"
  value       = var.create_sample_service ? aws_vpclattice_service.sample_service[0].id : null
}

output "sample_service_arn" {
  description = "ARN of the sample VPC Lattice service (if created)"
  value       = var.create_sample_service ? aws_vpclattice_service.sample_service[0].arn : null
}

# Lambda Function Outputs
output "performance_analyzer_function_name" {
  description = "Name of the performance analyzer Lambda function"
  value       = aws_lambda_function.performance_analyzer.function_name
}

output "performance_analyzer_function_arn" {
  description = "ARN of the performance analyzer Lambda function"
  value       = aws_lambda_function.performance_analyzer.arn
}

output "cost_correlator_function_name" {
  description = "Name of the cost correlator Lambda function"
  value       = aws_lambda_function.cost_correlator.function_name
}

output "cost_correlator_function_arn" {
  description = "ARN of the cost correlator Lambda function"
  value       = aws_lambda_function.cost_correlator.arn
}

output "report_generator_function_name" {
  description = "Name of the report generator Lambda function"
  value       = aws_lambda_function.report_generator.function_name
}

output "report_generator_function_arn" {
  description = "ARN of the report generator Lambda function"
  value       = aws_lambda_function.report_generator.arn
}

# CloudWatch Outputs
output "log_group_name" {
  description = "Name of the CloudWatch log group for VPC Lattice logs"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC Lattice logs"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.arn
}

output "dashboard_url" {
  description = "URL to the CloudWatch dashboard (if created)"
  value = var.enable_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.performance_analytics[0].dashboard_name}" : null
}

# EventBridge Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduling analytics"
  value       = aws_cloudwatch_event_rule.analytics_scheduler.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduling analytics"
  value       = aws_cloudwatch_event_rule.analytics_scheduler.arn
}

# IAM Outputs
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# Cost Anomaly Detection Outputs (conditional)
output "cost_anomaly_detector_arn" {
  description = "ARN of the cost anomaly detector (if created)"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_detector.vpc_lattice_costs[0].arn : null
}

output "cost_anomaly_subscription_arn" {
  description = "ARN of the cost anomaly subscription (if created)"
  value       = var.enable_cost_anomaly_detection ? aws_ce_anomaly_subscription.cost_alerts[0].arn : null
}

# General Outputs
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

# Manual Test Commands
output "test_commands" {
  description = "Commands to test the deployed analytics system"
  value = {
    test_performance_analyzer = "aws lambda invoke --function-name ${aws_lambda_function.performance_analyzer.function_name} --payload '{\"log_group\":\"${aws_cloudwatch_log_group.vpc_lattice_logs.name}\"}' --cli-binary-format raw-in-base64-out response.json"
    test_cost_correlator     = "aws lambda invoke --function-name ${aws_lambda_function.cost_correlator.function_name} --payload '{\"performance_data\":[{\"targetService\":\"test\",\"avgResponseTime\":\"100\",\"requestCount\":\"1000\"}]}' --cli-binary-format raw-in-base64-out response.json"
    test_report_generator    = "aws lambda invoke --function-name ${aws_lambda_function.report_generator.function_name} --payload '{\"suffix\":\"${local.name_suffix}\",\"log_group\":\"${aws_cloudwatch_log_group.vpc_lattice_logs.name}\"}' --cli-binary-format raw-in-base64-out response.json"
    view_logs               = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.vpc_lattice_logs.name}"
    start_insights_query    = "aws logs start-query --log-group-name ${aws_cloudwatch_log_group.vpc_lattice_logs.name} --start-time $(date -d '1 hour ago' +%s) --end-time $(date +%s) --query-string 'fields @timestamp, @message | filter @message like /requestId/ | limit 10'"
  }
}

# CloudWatch Insights Queries
output "insights_queries" {
  description = "Pre-configured CloudWatch Insights queries for VPC Lattice analysis"
  value = {
    performance_summary = "fields @timestamp, sourceVpc, targetService, responseTime, requestSize, responseSize | filter @message like /requestId/ | stats avg(responseTime) as avgResponseTime, sum(requestSize) as totalRequests, sum(responseSize) as totalBytes, count() as requestCount by targetService | sort avgResponseTime desc"
    error_analysis     = "fields @timestamp, targetService, responseCode | filter @message like /requestId/ and responseCode >= 400 | stats count() as errorCount by targetService, responseCode | sort errorCount desc"
    traffic_patterns   = "fields @timestamp, sourceVpc, targetService | filter @message like /requestId/ | stats count() as requestCount by bin(5m) | sort @timestamp desc"
    high_latency      = "fields @timestamp, targetService, responseTime | filter @message like /requestId/ and responseTime > 1000 | sort responseTime desc | limit 100"
  }
}

# Next Steps Instructions
output "next_steps" {
  description = "Instructions for getting started with the deployed system"
  value = [
    "1. Wait 5-10 minutes for all resources to be fully available",
    "2. Generate some test traffic to your VPC Lattice services to create log data",
    "3. Test the Lambda functions using the test_commands output",
    "4. View the CloudWatch dashboard: ${var.enable_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.enable_dashboard ? aws_cloudwatch_dashboard.performance_analytics[0].dashboard_name : "N/A"}" : "Dashboard not enabled"}",
    "5. Use the CloudWatch Insights queries to analyze VPC Lattice performance data",
    "6. The EventBridge rule will automatically run analytics every ${var.analytics_schedule}",
    var.enable_cost_anomaly_detection ? "7. Cost anomaly alerts will be sent to ${var.notification_email}" : "7. Cost anomaly detection is disabled"
  ]
}