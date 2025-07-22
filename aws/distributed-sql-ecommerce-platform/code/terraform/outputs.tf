# ================================
# Aurora DSQL Outputs
# ================================

output "dsql_cluster_id" {
  description = "The ID of the Aurora DSQL cluster"
  value       = aws_dsql_cluster.ecommerce_cluster.id
}

output "dsql_cluster_name" {
  description = "The name of the Aurora DSQL cluster"
  value       = aws_dsql_cluster.ecommerce_cluster.cluster_name
}

output "dsql_cluster_endpoint" {
  description = "The endpoint of the Aurora DSQL cluster"
  value       = aws_dsql_cluster.ecommerce_cluster.cluster_endpoint
}

output "dsql_cluster_arn" {
  description = "The ARN of the Aurora DSQL cluster"
  value       = aws_dsql_cluster.ecommerce_cluster.arn
}

output "dsql_cluster_status" {
  description = "The status of the Aurora DSQL cluster"
  value       = aws_dsql_cluster.ecommerce_cluster.status
}

# ================================
# Lambda Function Outputs
# ================================

output "products_lambda_function_name" {
  description = "Name of the products Lambda function"
  value       = aws_lambda_function.products_handler.function_name
}

output "products_lambda_function_arn" {
  description = "ARN of the products Lambda function"
  value       = aws_lambda_function.products_handler.arn
}

output "products_lambda_invoke_arn" {
  description = "Invoke ARN of the products Lambda function"
  value       = aws_lambda_function.products_handler.invoke_arn
}

output "orders_lambda_function_name" {
  description = "Name of the orders Lambda function"
  value       = aws_lambda_function.orders_handler.function_name
}

output "orders_lambda_function_arn" {
  description = "ARN of the orders Lambda function"
  value       = aws_lambda_function.orders_handler.arn
}

output "orders_lambda_invoke_arn" {
  description = "Invoke ARN of the orders Lambda function"
  value       = aws_lambda_function.orders_handler.invoke_arn
}

# ================================
# IAM Outputs
# ================================

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "aurora_dsql_policy_name" {
  description = "Name of the Aurora DSQL access policy"
  value       = aws_iam_policy.aurora_dsql_access.name
}

output "aurora_dsql_policy_arn" {
  description = "ARN of the Aurora DSQL access policy"
  value       = aws_iam_policy.aurora_dsql_access.arn
}

# ================================
# API Gateway Outputs
# ================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.ecommerce_api.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.ecommerce_api.name
}

output "api_gateway_root_resource_id" {
  description = "Root resource ID of the API Gateway"
  value       = aws_api_gateway_rest_api.ecommerce_api.root_resource_id
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.ecommerce_api.execution_arn
}

output "api_gateway_stage_name" {
  description = "Name of the API Gateway stage"
  value       = aws_api_gateway_stage.ecommerce_api_stage.stage_name
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.ecommerce_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${aws_api_gateway_stage.ecommerce_api_stage.stage_name}"
}

output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_api_gateway_stage.ecommerce_api_stage.invoke_url
}

# ================================
# CloudFront Outputs
# ================================

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.ecommerce_api_distribution.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.ecommerce_api_distribution.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.ecommerce_api_distribution.domain_name
}

output "cloudfront_distribution_url" {
  description = "URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.ecommerce_api_distribution.domain_name}"
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront hosted zone ID"
  value       = aws_cloudfront_distribution.ecommerce_api_distribution.hosted_zone_id
}

output "cloudfront_status" {
  description = "Status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.ecommerce_api_distribution.status
}

# ================================
# CloudWatch Outputs
# ================================

output "products_lambda_log_group_name" {
  description = "Name of the products Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.products_lambda_logs.name
}

output "products_lambda_log_group_arn" {
  description = "ARN of the products Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.products_lambda_logs.arn
}

output "orders_lambda_log_group_name" {
  description = "Name of the orders Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.orders_lambda_logs.name
}

output "orders_lambda_log_group_arn" {
  description = "ARN of the orders Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.orders_lambda_logs.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

output "api_gateway_log_group_arn" {
  description = "ARN of the API Gateway CloudWatch log group"
  value       = var.enable_api_gateway_logging ? aws_cloudwatch_log_group.api_gateway_logs[0].arn : null
}

# ================================
# Resource Names and Identifiers
# ================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "primary_region" {
  description = "Primary AWS region"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# ================================
# API Endpoints for Testing
# ================================

output "products_api_endpoint" {
  description = "API Gateway endpoint for products operations"
  value       = "${aws_api_gateway_stage.ecommerce_api_stage.invoke_url}/products"
}

output "orders_api_endpoint" {
  description = "API Gateway endpoint for orders operations"
  value       = "${aws_api_gateway_stage.ecommerce_api_stage.invoke_url}/orders"
}

output "cloudfront_products_endpoint" {
  description = "CloudFront endpoint for products operations"
  value       = "https://${aws_cloudfront_distribution.ecommerce_api_distribution.domain_name}/products"
}

output "cloudfront_orders_endpoint" {
  description = "CloudFront endpoint for orders operations"
  value       = "https://${aws_cloudfront_distribution.ecommerce_api_distribution.domain_name}/orders"
}

# ================================
# Database Connection Information
# ================================

output "database_connection_info" {
  description = "Database connection information"
  value = {
    cluster_name = aws_dsql_cluster.ecommerce_cluster.cluster_name
    cluster_endpoint = aws_dsql_cluster.ecommerce_cluster.cluster_endpoint
    database_name = var.initial_database_name
    region = data.aws_region.current.name
  }
  sensitive = false
}

# ================================
# Monitoring and Logging
# ================================

output "cloudwatch_dashboard_url" {
  description = "URL to view CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards"
}

output "api_gateway_console_url" {
  description = "URL to view API Gateway in AWS console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.ecommerce_api.id}/stages/${aws_api_gateway_stage.ecommerce_api_stage.stage_name}"
}

output "cloudfront_console_url" {
  description = "URL to view CloudFront distribution in AWS console"
  value       = "https://console.aws.amazon.com/cloudfront/home#/distributions/${aws_cloudfront_distribution.ecommerce_api_distribution.id}"
}

# ================================
# Security Information
# ================================

output "lambda_security_groups" {
  description = "Security groups for Lambda functions (if VPC configured)"
  value       = []
  # Note: This would be populated if Lambda functions were deployed in a VPC
}

output "api_gateway_resource_policy" {
  description = "API Gateway resource policy status"
  value       = "No resource policy configured - using default open access"
}

# ================================
# Cost and Resource Information
# ================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (USD)"
  value = {
    aurora_dsql = "Variable based on usage - starts at $0"
    lambda = "Variable based on requests and duration"
    api_gateway = "Variable based on requests - first 1M free"
    cloudfront = "Variable based on data transfer and requests"
    cloudwatch = "Variable based on logs and metrics stored"
    note = "Actual costs depend on usage patterns and data volume"
  }
}

output "created_resources_count" {
  description = "Number of AWS resources created"
  value = {
    aurora_dsql_clusters = 1
    lambda_functions = 2
    api_gateway_apis = 1
    cloudfront_distributions = 1
    iam_roles = 1
    iam_policies = 1
    cloudwatch_log_groups = var.enable_api_gateway_logging ? 3 : 2
    cloudwatch_alarms = var.enable_detailed_monitoring ? 3 : 0
  }
}

# ================================
# Deployment Information
# ================================

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "Managed by Terraform"
}

output "required_lambda_deployment_packages" {
  description = "Lambda deployment packages that need to be created"
  value = [
    "${path.module}/lambda_functions/products_handler.zip",
    "${path.module}/lambda_functions/orders_handler.zip"
  ]
}