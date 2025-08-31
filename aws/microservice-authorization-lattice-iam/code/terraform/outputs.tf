# Outputs for Microservice Authorization with VPC Lattice and IAM
# These outputs provide key information for verification and integration

#####################################################################
# VPC Lattice Infrastructure Outputs
#####################################################################

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.microservices_network.id
}

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.microservices_network.arn
}

output "service_network_name" {
  description = "Name of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.microservices_network.name
}

output "order_service_id" {
  description = "ID of the VPC Lattice order service"
  value       = aws_vpclattice_service.order_service.id
}

output "order_service_arn" {
  description = "ARN of the VPC Lattice order service"
  value       = aws_vpclattice_service.order_service.arn
}

output "order_service_name" {
  description = "Name of the VPC Lattice order service"
  value       = aws_vpclattice_service.order_service.name
}

output "target_group_id" {
  description = "ID of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.order_targets.id
}

output "target_group_arn" {
  description = "ARN of the VPC Lattice target group"
  value       = aws_vpclattice_target_group.order_targets.arn
}

#####################################################################
# Lambda Function Outputs
#####################################################################

output "product_service_function_name" {
  description = "Name of the product service Lambda function"
  value       = aws_lambda_function.product_service.function_name
}

output "product_service_function_arn" {
  description = "ARN of the product service Lambda function"
  value       = aws_lambda_function.product_service.arn
}

output "order_service_function_name" {
  description = "Name of the order service Lambda function"
  value       = aws_lambda_function.order_service.function_name
}

output "order_service_function_arn" {
  description = "ARN of the order service Lambda function"
  value       = aws_lambda_function.order_service.arn
}

#####################################################################
# IAM Role Outputs
#####################################################################

output "product_service_role_name" {
  description = "Name of the product service IAM role"
  value       = aws_iam_role.product_service_role.name
}

output "product_service_role_arn" {
  description = "ARN of the product service IAM role"
  value       = aws_iam_role.product_service_role.arn
}

output "order_service_role_name" {
  description = "Name of the order service IAM role"
  value       = aws_iam_role.order_service_role.name
}

output "order_service_role_arn" {
  description = "ARN of the order service IAM role"
  value       = aws_iam_role.order_service_role.arn
}

#####################################################################
# CloudWatch Monitoring Outputs
#####################################################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Lattice access logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.vpc_lattice_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC Lattice access logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.vpc_lattice_logs[0].arn : null
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for authorization failures"
  value       = aws_cloudwatch_metric_alarm.auth_failures.alarm_name
}

output "cloudwatch_alarm_arn" {
  description = "ARN of the CloudWatch alarm for authorization failures"
  value       = aws_cloudwatch_metric_alarm.auth_failures.arn
}

#####################################################################
# Security and Configuration Outputs
#####################################################################

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "auth_policy_methods" {
  description = "HTTP methods allowed by the authorization policy"
  value       = var.auth_policy_methods
}

output "auth_policy_paths" {
  description = "Paths allowed by the authorization policy"
  value       = var.auth_policy_paths
}

#####################################################################
# Verification Commands for CLI Testing
#####################################################################

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_service_network = "aws vpc-lattice get-service-network --service-network-identifier ${aws_vpclattice_service_network.microservices_network.id}"
    check_service         = "aws vpc-lattice get-service --service-identifier ${aws_vpclattice_service.order_service.id}"
    check_auth_policy     = "aws vpc-lattice get-auth-policy --resource-identifier ${aws_vpclattice_service.order_service.id}"
    test_product_service  = "aws lambda invoke --function-name ${aws_lambda_function.product_service.function_name} --payload '{\"test\": \"authorized_request\"}' response.json && cat response.json"
    test_order_service    = "aws lambda invoke --function-name ${aws_lambda_function.order_service.function_name} --payload '{}' response.json && cat response.json"
    check_logs           = var.enable_cloudwatch_logs ? "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.vpc_lattice_logs[0].name} --order-by LastEventTime --descending" : "CloudWatch logging not enabled"
  }
}

#####################################################################
# Service URLs and Endpoints
#####################################################################

output "service_discovery_info" {
  description = "Information for service discovery and integration"
  value = {
    service_network_dns = "${aws_vpclattice_service_network.microservices_network.id}.vpc-lattice-svcs.${var.aws_region}.on.aws"
    order_service_dns  = "${aws_vpclattice_service.order_service.id}.${aws_vpclattice_service_network.microservices_network.id}.vpc-lattice-svcs.${var.aws_region}.on.aws"
    listener_port      = aws_vpclattice_listener.order_listener.port
    listener_protocol  = aws_vpclattice_listener.order_listener.protocol
  }
}

#####################################################################
# Cost Estimation Information
#####################################################################

output "cost_estimation" {
  description = "Estimated monthly costs for deployed resources"
  value = {
    vpc_lattice_service_network = "Free tier: First 1M requests/month, then $0.025 per million requests"
    vpc_lattice_data_processing = "First 1GB/month free, then $0.125 per GB"
    lambda_invocations         = "Free tier: 1M requests/month, then $0.20 per million requests"
    lambda_compute_time        = "Free tier: 400K GB-seconds/month, then $0.0000166667 per GB-second"
    cloudwatch_logs           = var.enable_cloudwatch_logs ? "First 5GB/month free, then $0.50 per GB ingested" : "Not enabled"
    cloudwatch_alarms         = "First 10 alarms free, then $0.10 per alarm per month"
  }
}

#####################################################################
# Integration Examples
#####################################################################

output "integration_examples" {
  description = "Example configurations for integrating with this infrastructure"
  value = {
    curl_test_command = "curl -H 'Authorization: AWS4-HMAC-SHA256 ...' https://${aws_vpclattice_service.order_service.id}.${aws_vpclattice_service_network.microservices_network.id}.vpc-lattice-svcs.${var.aws_region}.on.aws/orders"
    sdk_endpoint      = "https://${aws_vpclattice_service.order_service.id}.${aws_vpclattice_service_network.microservices_network.id}.vpc-lattice-svcs.${var.aws_region}.on.aws"
    iam_role_example  = "Use ${aws_iam_role.product_service_role.arn} for client services"
  }
}