# General Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the main Lambda function"
  value       = aws_lambda_function.canary_demo_function.function_name
}

output "lambda_function_arn" {
  description = "ARN of the main Lambda function"
  value       = aws_lambda_function.canary_demo_function.arn
}

output "lambda_version_1_arn" {
  description = "ARN of Lambda function version 1 (production)"
  value       = aws_lambda_version.version_1.arn
}

output "lambda_version_2_arn" {
  description = "ARN of Lambda function version 2 (canary)"
  value       = aws_lambda_version.version_2.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# VPC Lattice Outputs
output "vpc_lattice_service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.canary_service_network.id
}

output "vpc_lattice_service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.canary_service_network.arn
}

output "vpc_lattice_service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.canary_service.id
}

output "vpc_lattice_service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.canary_service.arn
}

output "vpc_lattice_service_dns_name" {
  description = "DNS name of the VPC Lattice service"
  value       = aws_vpclattice_service.canary_service.dns_entry[0].domain_name
}

output "vpc_lattice_service_hosted_zone_id" {
  description = "Hosted zone ID of the VPC Lattice service"
  value       = aws_vpclattice_service.canary_service.dns_entry[0].hosted_zone_id
}

output "vpc_lattice_listener_id" {
  description = "ID of the VPC Lattice listener"
  value       = aws_vpclattice_listener.canary_listener.id
}

output "vpc_lattice_listener_arn" {
  description = "ARN of the VPC Lattice listener"
  value       = aws_vpclattice_listener.canary_listener.arn
}

# Target Group Outputs
output "production_target_group_id" {
  description = "ID of the production target group"
  value       = aws_vpclattice_target_group.production_targets.id
}

output "production_target_group_arn" {
  description = "ARN of the production target group"
  value       = aws_vpclattice_target_group.production_targets.arn
}

output "canary_target_group_id" {
  description = "ID of the canary target group"
  value       = aws_vpclattice_target_group.canary_targets.id
}

output "canary_target_group_arn" {
  description = "ARN of the canary target group"
  value       = aws_vpclattice_target_group.canary_targets.arn
}

# Traffic Distribution
output "current_traffic_distribution" {
  description = "Current traffic distribution between production and canary"
  value = {
    production_weight = var.production_weight
    canary_weight     = var.initial_canary_weight
  }
}

# CloudWatch Monitoring Outputs
output "cloudwatch_alarm_errors_name" {
  description = "Name of the CloudWatch alarm for canary errors"
  value       = aws_cloudwatch_metric_alarm.canary_lambda_errors.alarm_name
}

output "cloudwatch_alarm_errors_arn" {
  description = "ARN of the CloudWatch alarm for canary errors"
  value       = aws_cloudwatch_metric_alarm.canary_lambda_errors.arn
}

output "cloudwatch_alarm_duration_name" {
  description = "Name of the CloudWatch alarm for canary duration"
  value       = aws_cloudwatch_metric_alarm.canary_lambda_duration.alarm_name
}

output "cloudwatch_alarm_duration_arn" {
  description = "ARN of the CloudWatch alarm for canary duration"
  value       = aws_cloudwatch_metric_alarm.canary_lambda_duration.arn
}

# SNS and Rollback Outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for rollback notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.rollback_topic[0].arn : null
}

output "rollback_function_name" {
  description = "Name of the automatic rollback Lambda function"
  value       = var.enable_rollback_function ? aws_lambda_function.rollback_function[0].function_name : null
}

output "rollback_function_arn" {
  description = "ARN of the automatic rollback Lambda function"
  value       = var.enable_rollback_function ? aws_lambda_function.rollback_function[0].arn : null
}

# Testing Information
output "service_endpoint" {
  description = "Full HTTPS endpoint for testing the service"
  value       = "https://${aws_vpclattice_service.canary_service.dns_entry[0].domain_name}"
}

output "test_commands" {
  description = "Useful commands for testing the canary deployment"
  value = {
    test_endpoint = "curl -s https://${aws_vpclattice_service.canary_service.dns_entry[0].domain_name}"
    check_service_health = "aws vpc-lattice get-service --service-identifier ${aws_vpclattice_service.canary_service.id}"
    check_target_health = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.production_targets.id}"
    view_lambda_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/Lambda --metric-name Invocations --dimensions Name=FunctionName,Value=${aws_lambda_function.canary_demo_function.function_name} --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Sum"
  }
}

# Resource Management Information
output "cleanup_commands" {
  description = "Commands to clean up resources (for reference)"
  value = {
    destroy_infrastructure = "terraform destroy"
    force_delete_versions = "aws lambda delete-function --function-name ${aws_lambda_function.canary_demo_function.function_name}"
    list_vpc_lattice_resources = "aws vpc-lattice list-services && aws vpc-lattice list-service-networks"
  }
}

# Canary Deployment Management
output "canary_management_commands" {
  description = "Commands for managing canary deployment progression"
  value = {
    shift_to_50_50 = "aws vpc-lattice update-listener --service-identifier ${aws_vpclattice_service.canary_service.id} --listener-identifier ${aws_vpclattice_listener.canary_listener.id} --default-action '{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"${aws_vpclattice_target_group.production_targets.id}\",\"weight\":50},{\"targetGroupIdentifier\":\"${aws_vpclattice_target_group.canary_targets.id}\",\"weight\":50}]}}'"
    shift_to_canary_100 = "aws vpc-lattice update-listener --service-identifier ${aws_vpclattice_service.canary_service.id} --listener-identifier ${aws_vpclattice_listener.canary_listener.id} --default-action '{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"${aws_vpclattice_target_group.canary_targets.id}\",\"weight\":100}]}}'"
    rollback_to_production = "aws vpc-lattice update-listener --service-identifier ${aws_vpclattice_service.canary_service.id} --listener-identifier ${aws_vpclattice_listener.canary_listener.id} --default-action '{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"${aws_vpclattice_target_group.production_targets.id}\",\"weight\":100}]}}'"
  }
}