# Outputs for API Gateway Module

output "deployment_id" {
  description = "ID of the API Gateway deployment"
  value       = aws_api_gateway_deployment.main.id
}

output "stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.main.stage_name
}

output "stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = aws_api_gateway_stage.main.arn
}

output "invoke_url" {
  description = "Invoke URL for the API Gateway stage"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "health_resource_id" {
  description = "Resource ID for the health endpoint"
  value       = aws_api_gateway_resource.health.id
}

output "users_resource_id" {
  description = "Resource ID for the users endpoint"
  value       = aws_api_gateway_resource.users.id
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for API Gateway (if enabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.api_gateway[0].arn : null
}