# ======================================================================================
# VPC LATTICE OUTPUTS
# ======================================================================================

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.name
}

output "service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.main.id
}

output "service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.main.arn
}

output "service_name" {
  description = "Name of the VPC Lattice service"
  value       = aws_vpclattice_service.main.name
}

output "service_dns_entry" {
  description = "DNS entry for the VPC Lattice service"
  value       = aws_vpclattice_service.main.dns_entry
}

output "target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.main.id
}

output "target_group_arn" {
  description = "ARN of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.main.arn
}

output "target_group_name" {
  description = "Name of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.main.name
}

output "listener_id" {
  description = "ID of the VPC Lattice listener"
  value       = aws_vpclattice_listener.main.id
}

output "listener_arn" {
  description = "ARN of the VPC Lattice listener"
  value       = aws_vpclattice_listener.main.arn
}

# ======================================================================================
# CLOUDWATCH OUTPUTS
# ======================================================================================

output "cloudwatch_alarm_high_5xx_arn" {
  description = "ARN of the CloudWatch alarm for high 5XX error rate"
  value       = aws_cloudwatch_metric_alarm.high_5xx_rate.arn
}

output "cloudwatch_alarm_timeouts_arn" {
  description = "ARN of the CloudWatch alarm for request timeouts"
  value       = aws_cloudwatch_metric_alarm.request_timeouts.arn
}

output "cloudwatch_alarm_response_time_arn" {
  description = "ARN of the CloudWatch alarm for high response time"
  value       = aws_cloudwatch_metric_alarm.high_response_time.arn
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_dashboard ? aws_cloudwatch_dashboard.health_monitoring[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.health_monitoring[0].dashboard_name}" : null
}

# ======================================================================================
# SNS OUTPUTS
# ======================================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for health alerts"
  value       = aws_sns_topic.health_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for health alerts"
  value       = aws_sns_topic.health_alerts.name
}

# ======================================================================================
# LAMBDA OUTPUTS
# ======================================================================================

output "lambda_function_arn" {
  description = "ARN of the Lambda remediation function"
  value       = aws_lambda_function.health_remediation.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda remediation function"
  value       = aws_lambda_function.health_remediation.function_name
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda remediation function"
  value       = aws_lambda_function.health_remediation.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# ======================================================================================
# VPC OUTPUTS
# ======================================================================================

output "vpc_id" {
  description = "ID of the VPC used for the deployment"
  value       = data.aws_vpc.selected.id
}

output "subnet_ids" {
  description = "List of subnet IDs used for the deployment"
  value       = local.subnet_ids
}

# ======================================================================================
# CONFIGURATION OUTPUTS
# ======================================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

output "environment" {
  description = "Environment name used for the deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for the deployment"
  value       = var.project_name
}

# ======================================================================================
# MONITORING CONFIGURATION OUTPUTS
# ======================================================================================

output "monitoring_configuration" {
  description = "Summary of monitoring configuration"
  value = {
    alarm_thresholds = {
      high_5xx_threshold         = var.high_5xx_threshold
      request_timeout_threshold  = var.request_timeout_threshold
      high_response_time_threshold = var.high_response_time_threshold
    }
    alarm_settings = {
      evaluation_periods = var.alarm_evaluation_periods
      period            = var.alarm_period
    }
    health_check_settings = {
      enabled                       = var.health_check_enabled
      interval_seconds             = var.health_check_interval_seconds
      timeout_seconds              = var.health_check_timeout_seconds
      healthy_threshold_count      = var.healthy_threshold_count
      unhealthy_threshold_count    = var.unhealthy_threshold_count
      path                        = var.health_check_path
      protocol                    = var.health_check_protocol
      port                        = var.health_check_port
    }
  }
}

# ======================================================================================
# DEPLOYMENT INSTRUCTIONS
# ======================================================================================

output "deployment_instructions" {
  description = "Instructions for completing the deployment and testing"
  value = {
    next_steps = [
      "1. Register targets with the target group: aws vpc-lattice register-targets --target-group-identifier ${aws_vpclattice_target_group.main.id}",
      "2. Verify health checks are passing: aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.main.id}",
      "3. Test the service endpoint: ${aws_vpclattice_service.main.dns_entry[0].hosted_zone_id}",
      "4. Monitor CloudWatch metrics: aws cloudwatch list-metrics --namespace AWS/VpcLattice",
      "5. Test alarm notifications by simulating failures",
      "6. ${var.notification_email != "" ? "Check your email (${var.notification_email}) for subscription confirmation" : "Subscribe to SNS topic for notifications: aws sns subscribe --topic-arn ${aws_sns_topic.health_alerts.arn} --protocol email --notification-endpoint your-email@example.com"}"
    ]
    dashboard_url = var.create_dashboard ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.health_monitoring[0].dashboard_name}" : "Dashboard creation disabled"
    testing_commands = [
      "# Test Lambda function manually:",
      "aws lambda invoke --function-name ${aws_lambda_function.health_remediation.function_name} --payload '{\"Records\":[{\"Sns\":{\"Message\":\"{\\\"AlarmName\\\":\\\"Test-5XX-Alarm\\\",\\\"NewStateValue\\\":\\\"ALARM\\\",\\\"StateChangeTime\\\":\\\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\\\"}\"}}]}' response.json",
      "",
      "# Test SNS notifications:",
      "aws sns publish --topic-arn ${aws_sns_topic.health_alerts.arn} --subject 'Health Monitoring Test' --message 'Testing health monitoring notification system'"
    ]
  }
}

# ======================================================================================
# RESOURCE IDENTIFIERS FOR CLEANUP
# ======================================================================================

output "cleanup_identifiers" {
  description = "Resource identifiers for cleanup purposes"
  value = {
    service_network_id = aws_vpclattice_service_network.main.id
    service_id         = aws_vpclattice_service.main.id
    target_group_id    = aws_vpclattice_target_group.main.id
    lambda_function_name = aws_lambda_function.health_remediation.function_name
    sns_topic_arn      = aws_sns_topic.health_alerts.arn
    iam_role_name      = aws_iam_role.lambda_role.name
    iam_policy_arn     = aws_iam_policy.lambda_policy.arn
    random_suffix      = local.name_suffix
  }
}