# Output values for the network troubleshooting solution

# VPC Information
output "vpc_id" {
  description = "ID of the VPC created for testing"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnet Information
output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

# VPC Lattice Information
output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.arn
}

output "service_network_dns_name" {
  description = "DNS name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.main.dns_entry[0].domain_name
}

# Test Instance Information
output "test_instance_id" {
  description = "ID of the test EC2 instance"
  value       = aws_instance.test_instance.id
}

output "test_instance_public_ip" {
  description = "Public IP address of the test instance"
  value       = aws_instance.test_instance.public_ip
}

output "test_instance_private_ip" {
  description = "Private IP address of the test instance"
  value       = aws_instance.test_instance.private_ip
}

# Security Group Information
output "test_security_group_id" {
  description = "ID of the security group for test instances"
  value       = aws_security_group.test_instances.id
}

# IAM Role Information
output "ssm_automation_role_arn" {
  description = "ARN of the Systems Manager automation role"
  value       = aws_iam_role.ssm_automation.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}

# Systems Manager Information
output "automation_document_name" {
  description = "Name of the Systems Manager automation document"
  value       = aws_ssm_document.network_analysis.name
}

output "automation_document_arn" {
  description = "ARN of the Systems Manager automation document"
  value       = aws_ssm_document.network_analysis.arn
}

# SNS and Notification Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for network alerts"
  value       = aws_sns_topic.network_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for network alerts"
  value       = aws_sns_topic.network_alerts.name
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the Lambda function for network troubleshooting"
  value       = aws_lambda_function.network_troubleshooting.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for network troubleshooting"
  value       = aws_lambda_function.network_troubleshooting.arn
}

# CloudWatch Information
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.network_monitoring.dashboard_name}"
}

output "vpc_lattice_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Lattice"
  value       = aws_cloudwatch_log_group.vpc_lattice.name
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda"
  value       = aws_cloudwatch_log_group.lambda.name
}

# CloudWatch Alarm Information
output "high_error_rate_alarm_name" {
  description = "Name of the high error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.alarm_name
}

output "high_latency_alarm_name" {
  description = "Name of the high latency CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_latency.alarm_name
}

# Resource Naming Information
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

output "name_prefix" {
  description = "Prefix used for resource naming"
  value       = local.name_prefix
}

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

# Manual Test Commands
output "manual_test_commands" {
  description = "Commands to manually test the network troubleshooting automation"
  value = {
    execute_automation = "aws ssm start-automation-execution --document-name ${aws_ssm_document.network_analysis.name} --parameters 'SourceId=${aws_instance.test_instance.id},DestinationId=${aws_instance.test_instance.id},AutomationAssumeRole=${aws_iam_role.ssm_automation.arn}'"
    invoke_lambda = "aws lambda invoke --function-name ${aws_lambda_function.network_troubleshooting.function_name} --payload '{\"Records\":[{\"EventSource\":\"aws:sns\",\"Sns\":{\"Message\":\"{\\\"AlarmName\\\":\\\"${aws_cloudwatch_metric_alarm.high_error_rate.alarm_name}\\\",\\\"NewStateValue\\\":\\\"ALARM\\\"}\"}}]}' response.json"
    check_vpc_lattice = "aws vpc-lattice get-service-network --service-network-identifier ${aws_vpclattice_service_network.main.id}"
  }
}

# Network Insights Analysis Commands
output "network_insights_commands" {
  description = "Commands for manual network insights analysis"
  value = {
    list_paths = "aws ec2 describe-network-insights-paths --filters 'Name=tag:Name,Values=AutomatedTroubleshooting'"
    list_analyses = "aws ec2 describe-network-insights-analyses"
    create_path = "aws ec2 create-network-insights-path --source ${aws_instance.test_instance.id} --destination ${aws_instance.test_instance.id} --protocol tcp --destination-port 80"
  }
}