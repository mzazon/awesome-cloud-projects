# Network infrastructure outputs
output "vpc_id" {
  description = "ID of the target VPC"
  value       = aws_vpc.target_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the target VPC"
  value       = aws_vpc.target_vpc.cidr_block
}

output "subnet_ids" {
  description = "IDs of the created subnets"
  value       = aws_subnet.target_subnets[*].id
}

output "vpc_endpoint_id" {
  description = "ID of the API Gateway VPC endpoint"
  value       = aws_vpc_endpoint.api_gateway_endpoint.id
}

output "vpc_endpoint_dns_entries" {
  description = "DNS entries for the VPC endpoint"
  value       = aws_vpc_endpoint.api_gateway_endpoint.dns_entry
}

# API Gateway outputs
output "api_gateway_id" {
  description = "ID of the private API Gateway"
  value       = aws_api_gateway_rest_api.private_api.id
}

output "api_gateway_arn" {
  description = "ARN of the private API Gateway"
  value       = aws_api_gateway_rest_api.private_api.arn
}

output "api_gateway_endpoint" {
  description = "Private API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.private_api.id}-${aws_vpc_endpoint.api_gateway_endpoint.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_orders_endpoint" {
  description = "Full URL for the orders endpoint"
  value       = "https://${aws_api_gateway_rest_api.private_api.id}-${aws_vpc_endpoint.api_gateway_endpoint.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/orders"
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway deployment stage"
  value       = aws_api_gateway_deployment.api_deployment.stage_name
}

# VPC Lattice outputs
output "vpc_lattice_service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.private_api_network.id
}

output "vpc_lattice_service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.private_api_network.arn
}

output "resource_gateway_id" {
  description = "ID of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.api_gateway_resource_gateway.id
}

output "resource_gateway_arn" {
  description = "ARN of the VPC Lattice resource gateway"
  value       = aws_vpclattice_resource_gateway.api_gateway_resource_gateway.arn
}

output "resource_configuration_id" {
  description = "ID of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.private_api_config.id
}

output "resource_configuration_arn" {
  description = "ARN of the VPC Lattice resource configuration"
  value       = aws_vpclattice_resource_configuration.private_api_config.arn
}

output "resource_association_id" {
  description = "ID of the service network resource association"
  value       = aws_vpclattice_service_network_resource_association.private_api_association.id
}

# IAM outputs
output "iam_role_arn" {
  description = "ARN of the EventBridge and Step Functions IAM role"
  value       = aws_iam_role.eventbridge_stepfunctions_role.arn
}

output "iam_role_name" {
  description = "Name of the EventBridge and Step Functions IAM role"
  value       = aws_iam_role.eventbridge_stepfunctions_role.name
}

# EventBridge outputs
output "eventbridge_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.private_api_bus.name
}

output "eventbridge_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.private_api_bus.arn
}

output "eventbridge_connection_arn" {
  description = "ARN of the EventBridge connection"
  value       = aws_cloudwatch_event_connection.private_api_connection.arn
}

output "eventbridge_connection_name" {
  description = "Name of the EventBridge connection"
  value       = aws_cloudwatch_event_connection.private_api_connection.name
}

output "api_destination_arn" {
  description = "ARN of the EventBridge API destination"
  value       = aws_cloudwatch_event_api_destination.private_api_destination.arn
}

output "api_destination_name" {
  description = "Name of the EventBridge API destination"
  value       = aws_cloudwatch_event_api_destination.private_api_destination.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.trigger_workflow.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.trigger_workflow.name
}

# Step Functions outputs
output "step_function_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.private_api_workflow.arn
}

output "step_function_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.private_api_workflow.name
}

# Test and validation outputs
output "test_event_command" {
  description = "AWS CLI command to send test event"
  value = "aws events put-events --entries '[{\"Source\": \"demo.application\", \"DetailType\": \"Order Received\", \"Detail\": \"{\\\"orderId\\\": \\\"test-123\\\", \\\"customerId\\\": \\\"cust-456\\\"}\", \"EventBusName\": \"${aws_cloudwatch_event_bus.private_api_bus.name}\"}]'"
}

output "step_function_console_url" {
  description = "AWS Console URL for Step Functions state machine"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.private_api_workflow.arn}"
}

output "api_gateway_console_url" {
  description = "AWS Console URL for API Gateway"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.private_api.id}/resources/"
}

output "vpc_lattice_console_url" {
  description = "AWS Console URL for VPC Lattice service network"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/vpc/home?region=${data.aws_region.current.name}#ServiceNetworks:serviceNetworkId=${aws_vpclattice_service_network.private_api_network.id}"
}

# Resource identifiers for cleanup
output "resource_identifiers" {
  description = "Key resource identifiers for reference and cleanup"
  value = {
    vpc_id                        = aws_vpc.target_vpc.id
    api_gateway_id               = aws_api_gateway_rest_api.private_api.id
    service_network_id           = aws_vpclattice_service_network.private_api_network.id
    resource_gateway_id          = aws_vpclattice_resource_gateway.api_gateway_resource_gateway.id
    resource_configuration_arn   = aws_vpclattice_resource_configuration.private_api_config.arn
    step_function_arn           = aws_sfn_state_machine.private_api_workflow.arn
    eventbridge_bus_name        = aws_cloudwatch_event_bus.private_api_bus.name
    iam_role_name               = aws_iam_role.eventbridge_stepfunctions_role.name
  }
}