# Output values for Zero Trust Network Architecture

#####################################################
# VPC and Networking Outputs
#####################################################

output "consumer_vpc_id" {
  description = "ID of the consumer VPC"
  value       = aws_vpc.consumer.id
}

output "consumer_vpc_cidr" {
  description = "CIDR block of the consumer VPC"
  value       = aws_vpc.consumer.cidr_block
}

output "provider_vpc_id" {
  description = "ID of the provider VPC"
  value       = aws_vpc.provider.id
}

output "provider_vpc_cidr" {
  description = "CIDR block of the provider VPC"
  value       = aws_vpc.provider.cidr_block
}

output "consumer_private_subnet_ids" {
  description = "IDs of the consumer private subnets"
  value       = aws_subnet.consumer_private[*].id
}

output "provider_subnet_id" {
  description = "ID of the provider subnet"
  value       = aws_subnet.provider.id
}

#####################################################
# Security Group Outputs
#####################################################

output "vpc_endpoint_security_group_id" {
  description = "ID of the VPC endpoint security group"
  value       = aws_security_group.vpc_endpoint.id
}

output "application_security_group_id" {
  description = "ID of the application security group"
  value       = aws_security_group.application.id
}

output "provider_service_security_group_id" {
  description = "ID of the provider service security group"
  value       = aws_security_group.provider_service.id
}

#####################################################
# VPC Endpoint Outputs
#####################################################

output "s3_vpc_endpoint_id" {
  description = "ID of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "s3_vpc_endpoint_dns_names" {
  description = "DNS names of the S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.dns_entry[*].dns_name
}

output "lambda_vpc_endpoint_id" {
  description = "ID of the Lambda VPC endpoint"
  value       = aws_vpc_endpoint.lambda.id
}

output "lambda_vpc_endpoint_dns_names" {
  description = "DNS names of the Lambda VPC endpoint"
  value       = aws_vpc_endpoint.lambda.dns_entry[*].dns_name
}

output "logs_vpc_endpoint_id" {
  description = "ID of the CloudWatch Logs VPC endpoint"
  value       = aws_vpc_endpoint.logs.id
}

output "logs_vpc_endpoint_dns_names" {
  description = "DNS names of the CloudWatch Logs VPC endpoint"
  value       = aws_vpc_endpoint.logs.dns_entry[*].dns_name
}

output "custom_service_vpc_endpoint_id" {
  description = "ID of the custom service VPC endpoint"
  value       = aws_vpc_endpoint.custom_service.id
}

output "custom_service_vpc_endpoint_dns_names" {
  description = "DNS names of the custom service VPC endpoint"
  value       = aws_vpc_endpoint.custom_service.dns_entry[*].dns_name
}

#####################################################
# PrivateLink Service Outputs
#####################################################

output "endpoint_service_name" {
  description = "Name of the VPC endpoint service"
  value       = aws_vpc_endpoint_service.custom.service_name
}

output "endpoint_service_id" {
  description = "ID of the VPC endpoint service"
  value       = aws_vpc_endpoint_service.custom.id
}

output "network_load_balancer_arn" {
  description = "ARN of the Network Load Balancer"
  value       = aws_lb.provider_nlb.arn
}

output "network_load_balancer_dns_name" {
  description = "DNS name of the Network Load Balancer"
  value       = aws_lb.provider_nlb.dns_name
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.provider.arn
}

#####################################################
# DNS Outputs
#####################################################

output "private_hosted_zone_id" {
  description = "ID of the private hosted zone"
  value       = aws_route53_zone.private.zone_id
}

output "private_hosted_zone_name" {
  description = "Name of the private hosted zone"
  value       = aws_route53_zone.private.name
}

output "api_dns_record_name" {
  description = "DNS name for the API service"
  value       = aws_route53_record.api.name
}

#####################################################
# Monitoring Outputs
#####################################################

output "flow_logs_log_group_name" {
  description = "Name of the VPC Flow Logs CloudWatch log group"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "consumer_vpc_flow_log_id" {
  description = "ID of the consumer VPC Flow Log"
  value       = var.enable_flow_logs ? aws_flow_log.consumer[0].id : null
}

output "provider_vpc_flow_log_id" {
  description = "ID of the provider VPC Flow Log"
  value       = var.enable_flow_logs ? aws_flow_log.provider[0].id : null
}

#####################################################
# Test Lambda Outputs
#####################################################

output "test_lambda_function_name" {
  description = "Name of the test Lambda function"
  value       = var.create_test_lambda ? aws_lambda_function.test[0].function_name : null
}

output "test_lambda_function_arn" {
  description = "ARN of the test Lambda function"
  value       = var.create_test_lambda ? aws_lambda_function.test[0].arn : null
}

output "test_lambda_log_group_name" {
  description = "CloudWatch log group name for the test Lambda function"
  value       = var.create_test_lambda ? aws_cloudwatch_log_group.lambda_test[0].name : null
}

#####################################################
# Validation and Testing Outputs
#####################################################

output "validation_commands" {
  description = "Commands to validate the zero trust network architecture"
  value = {
    test_lambda_invocation = var.create_test_lambda ? "aws lambda invoke --function-name ${aws_lambda_function.test[0].function_name} --payload '{}' /tmp/response.json && cat /tmp/response.json" : "Test Lambda not created"
    check_vpc_endpoints = "aws ec2 describe-vpc-endpoints --vpc-endpoint-ids ${aws_vpc_endpoint.s3.id} ${aws_vpc_endpoint.lambda.id} ${aws_vpc_endpoint.logs.id} ${aws_vpc_endpoint.custom_service.id}"
    check_endpoint_service = "aws ec2 describe-vpc-endpoint-service-configurations --service-ids ${aws_vpc_endpoint_service.custom.id}"
    check_flow_logs = var.enable_flow_logs ? "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.flow_logs[0].name}" : "Flow logs not enabled"
    test_dns_resolution = "nslookup ${aws_route53_record.api.name}"
  }
}

#####################################################
# Network Architecture Summary
#####################################################

output "architecture_summary" {
  description = "Summary of the zero trust network architecture"
  value = {
    consumer_vpc = {
      id          = aws_vpc.consumer.id
      cidr        = aws_vpc.consumer.cidr_block
      subnets     = length(aws_subnet.consumer_private)
      endpoints   = 4 # S3, Lambda, Logs, Custom
    }
    provider_vpc = {
      id       = aws_vpc.provider.id
      cidr     = aws_vpc.provider.cidr_block
      services = 1 # PrivateLink service
    }
    security_features = {
      vpc_endpoints_enabled    = true
      private_dns_enabled     = var.private_dns_enabled
      flow_logs_enabled       = var.enable_flow_logs
      zero_trust_networking   = true
      internet_access_blocked = true
    }
    privatelink_service = {
      service_name = aws_vpc_endpoint_service.custom.service_name
      nlb_dns_name = aws_lb.provider_nlb.dns_name
      acceptance_required = var.endpoint_service_acceptance_required
    }
  }
}

#####################################################
# Cost Estimation Information
#####################################################

output "cost_estimation" {
  description = "Estimated monthly costs for the zero trust architecture"
  value = {
    vpc_endpoints = {
      count = 4
      estimated_monthly_cost = "$28.80" # 4 endpoints × $7.20/month
      data_processing_cost = "$0.01 per GB processed"
    }
    network_load_balancer = {
      estimated_monthly_cost = "$16.20" # $0.0225/hour × 24 × 30
      data_processing_cost = "$0.006 per GB processed"
    }
    flow_logs = var.enable_flow_logs ? {
      estimated_monthly_cost = "$1-10" # Depends on traffic volume
      storage_cost = "$0.50 per GB ingested"
    } : "Not enabled"
    total_estimated_monthly_cost = "$45-55 (excluding data processing)"
    note = "Actual costs depend on data transfer volumes and usage patterns"
  }
}