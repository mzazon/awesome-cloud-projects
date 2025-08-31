# Outputs for Distributed Service Tracing Infrastructure
# These outputs provide important information about the deployed resources

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC used for the infrastructure"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet used for Lambda functions"
  value       = local.subnet_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.main[0].cidr_block : "N/A (using existing VPC)"
}

# ============================================================================
# VPC LATTICE OUTPUTS
# ============================================================================

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

output "order_service_id" {
  description = "ID of the VPC Lattice order service"
  value       = aws_vpclattice_service.order_service.id
}

output "order_service_arn" {
  description = "ARN of the VPC Lattice order service"
  value       = aws_vpclattice_service.order_service.arn
}

output "order_target_group_id" {
  description = "ID of the order service target group"
  value       = aws_vpclattice_target_group.order_service.id
}

output "order_target_group_arn" {
  description = "ARN of the order service target group"
  value       = aws_vpclattice_target_group.order_service.arn
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "order_service_function_name" {
  description = "Name of the order service Lambda function"
  value       = aws_lambda_function.order_service.function_name
}

output "order_service_function_arn" {
  description = "ARN of the order service Lambda function"
  value       = aws_lambda_function.order_service.arn
}

output "payment_service_function_name" {
  description = "Name of the payment service Lambda function"
  value       = aws_lambda_function.payment_service.function_name
}

output "payment_service_function_arn" {
  description = "ARN of the payment service Lambda function"
  value       = aws_lambda_function.payment_service.arn
}

output "inventory_service_function_name" {
  description = "Name of the inventory service Lambda function"
  value       = aws_lambda_function.inventory_service.function_name
}

output "inventory_service_function_arn" {
  description = "ARN of the inventory service Lambda function"
  value       = aws_lambda_function.inventory_service.arn
}

output "xray_layer_arn" {
  description = "ARN of the X-Ray SDK Lambda layer"
  value       = aws_lambda_layer_version.xray_sdk.arn
}

output "test_generator_function_name" {
  description = "Name of the test generator Lambda function (if enabled)"
  value       = var.test_traffic_generation ? aws_lambda_function.test_generator[0].function_name : "N/A (test generation disabled)"
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# ============================================================================
# CLOUDWATCH OUTPUTS
# ============================================================================

output "order_service_log_group_name" {
  description = "Name of the order service CloudWatch log group"
  value       = aws_cloudwatch_log_group.order_service.name
}

output "payment_service_log_group_name" {
  description = "Name of the payment service CloudWatch log group"
  value       = aws_cloudwatch_log_group.payment_service.name
}

output "inventory_service_log_group_name" {
  description = "Name of the inventory service CloudWatch log group"
  value       = aws_cloudwatch_log_group.inventory_service.name
}

output "vpc_lattice_log_group_name" {
  description = "Name of the VPC Lattice access logs CloudWatch log group"
  value       = var.enable_vpc_lattice_logging ? aws_cloudwatch_log_group.vpc_lattice_access_logs[0].name : "N/A (VPC Lattice logging disabled)"
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch observability dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.observability[0].dashboard_name : "N/A (dashboard disabled)"
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch observability dashboard"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.observability[0].dashboard_name}" : "N/A (dashboard disabled)"
}

# ============================================================================
# X-RAY OUTPUTS
# ============================================================================

output "xray_console_url" {
  description = "URL to access X-Ray console for trace analysis"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/service-map"
}

output "xray_traces_url" {
  description = "URL to access X-Ray traces console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/traces"
}

# ============================================================================
# TESTING AND VALIDATION OUTPUTS
# ============================================================================

output "test_order_service_command" {
  description = "AWS CLI command to test the order service"
  value = "aws lambda invoke --function-name ${aws_lambda_function.order_service.function_name} --payload '{\"order_id\": \"test-order-123\", \"customer_id\": \"test-customer\", \"items\": [{\"product_id\": \"test-product\", \"quantity\": 2, \"price\": 50.00}]}' response.json && cat response.json"
}

output "view_recent_traces_command" {
  description = "AWS CLI command to view recent X-Ray traces"
  value = "aws xray get-trace-summaries --time-range-type TimeRangeByStartTime --start-time $(date -d '5 minutes ago' -u +%%Y-%%m-%%dT%%H:%%M:%%SZ) --end-time $(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ) --query 'TraceSummaries[*].[Id,Duration,ResponseTime]' --output table"
}

output "view_vpc_lattice_metrics_command" {
  description = "AWS CLI command to view VPC Lattice metrics"
  value = "aws cloudwatch get-metric-statistics --namespace AWS/VPC-Lattice --metric-name RequestCount --dimensions Name=ServiceNetwork,Value=${aws_vpclattice_service_network.main.id} --start-time $(date -d '10 minutes ago' -u +%%Y-%%m-%%dT%%H:%%M:%%SZ) --end-time $(date -u +%%Y-%%m-%%dT%%H:%%M:%%SZ) --period 300 --statistics Sum"
}

# ============================================================================
# CONFIGURATION SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    environment               = var.environment
    project_name             = var.project_name
    aws_region               = data.aws_region.current.name
    aws_account_id           = data.aws_caller_identity.current.account_id
    vpc_created              = var.create_vpc
    vpc_lattice_logging      = var.enable_vpc_lattice_logging
    cloudwatch_dashboard     = var.enable_cloudwatch_dashboard
    test_traffic_generation  = var.test_traffic_generation
    lambda_runtime           = var.lambda_runtime
    log_retention_days       = var.log_retention_days
    resource_suffix          = local.name_suffix
  }
}

# ============================================================================
# NEXT STEPS INFORMATION
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test the order service using the provided test command",
    "2. View X-Ray traces in the AWS console using the provided URL",
    "3. Monitor VPC Lattice metrics using the CloudWatch dashboard",
    "4. Generate test traffic using the order service function",
    "5. Analyze distributed traces to understand service dependencies",
    "6. Review CloudWatch logs for detailed application insights",
    "7. Set up custom alarms based on your observability requirements"
  ]
}

# ============================================================================
# CLEANUP INFORMATION
# ============================================================================

output "cleanup_instructions" {
  description = "Instructions for cleaning up deployed resources"
  value = [
    "To destroy all resources: terraform destroy",
    "To delete specific log groups: Use AWS CLI or console",
    "To remove X-Ray traces: Traces automatically expire after 30 days",
    "To stop test traffic generation: Disable EventBridge rule or destroy infrastructure"
  ]
}