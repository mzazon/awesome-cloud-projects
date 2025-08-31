# Output Values for VPC Lattice Cost Analytics Infrastructure
# These outputs provide important information about the deployed resources

output "s3_bucket_name" {
  description = "Name of the S3 bucket for cost analytics data"
  value       = aws_s3_bucket.analytics_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for cost analytics data"
  value       = aws_s3_bucket.analytics_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.analytics_bucket.bucket_domain_name
}

output "lambda_function_name" {
  description = "Name of the Lambda function for cost processing"
  value       = aws_lambda_function.cost_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for cost processing"
  value       = aws_lambda_function.cost_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.cost_processor.invoke_arn
}

output "iam_role_name" {
  description = "Name of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Lambda execution"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "iam_policy_arn" {
  description = "ARN of the custom IAM policy for cost analytics"
  value       = aws_iam_policy.cost_analytics_policy.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scheduled analysis"
  value       = aws_cloudwatch_event_rule.cost_analysis_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled analysis"
  value       = aws_cloudwatch_event_rule.cost_analysis_schedule.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda logs"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda logs"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Conditional outputs for VPC Lattice demo resources
output "demo_service_network_id" {
  description = "ID of the demo VPC Lattice service network (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service_network.demo_network[0].id : null
}

output "demo_service_network_arn" {
  description = "ARN of the demo VPC Lattice service network (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service_network.demo_network[0].arn : null
}

output "demo_service_network_name" {
  description = "Name of the demo VPC Lattice service network (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service_network.demo_network[0].name : null
}

output "demo_service_id" {
  description = "ID of the demo VPC Lattice service (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service.demo_service[0].id : null
}

output "demo_service_arn" {
  description = "ARN of the demo VPC Lattice service (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service.demo_service[0].arn : null
}

output "demo_service_name" {
  description = "Name of the demo VPC Lattice service (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service.demo_service[0].name : null
}

output "demo_association_id" {
  description = "ID of the service network association (if enabled)"
  value       = var.enable_demo_vpc_lattice ? aws_vpclattice_service_network_service_association.demo_association[0].id : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enabled)"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_analytics_dashboard[0].dashboard_name}" : null
}

# Deployment information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = local.resource_prefix
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.tags
}

# Instructions for manual testing
output "manual_test_commands" {
  description = "Commands to manually test the deployed infrastructure"
  value = {
    invoke_lambda = "aws lambda invoke --function-name ${aws_lambda_function.cost_processor.function_name} --payload '{}' response.json"
    check_s3_bucket = "aws s3 ls s3://${aws_s3_bucket.analytics_bucket.id}/ --recursive"
    view_logs = "aws logs describe-log-groups --log-group-name-prefix ${aws_cloudwatch_log_group.lambda_logs.name}"
    check_metrics = "aws cloudwatch list-metrics --namespace VPCLattice/CostAnalytics"
  }
}

# Cost optimization recommendations
output "cost_optimization_notes" {
  description = "Cost optimization recommendations for the deployed infrastructure"
  value = {
    lambda_optimization = "Monitor Lambda execution time and adjust memory allocation if needed"
    s3_lifecycle = "Consider implementing S3 lifecycle policies for older analytics data"
    log_retention = "CloudWatch logs are set to 14-day retention to manage costs"
    demo_resources = var.enable_demo_vpc_lattice ? "Demo VPC Lattice resources are enabled - disable in production" : "Demo resources are disabled"
  }
}