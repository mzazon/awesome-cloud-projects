# OpenSearch Domain Outputs
output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.main.domain_name
}

output "opensearch_domain_id" {
  description = "Unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.main.domain_id
}

output "opensearch_endpoint" {
  description = "Domain-specific endpoint used to submit index, search, and data upload requests"
  value       = aws_opensearch_domain.main.endpoint
}

output "opensearch_kibana_endpoint" {
  description = "Domain-specific endpoint for OpenSearch Dashboards"
  value       = aws_opensearch_domain.main.kibana_endpoint
}

output "opensearch_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.main.arn
}

output "opensearch_domain_url" {
  description = "Full HTTPS URL of the OpenSearch domain"
  value       = "https://${aws_opensearch_domain.main.endpoint}"
}

output "opensearch_dashboards_url" {
  description = "Full HTTPS URL of the OpenSearch Dashboards"
  value       = "https://${aws_opensearch_domain.main.kibana_endpoint}"
}

# Authentication Information
output "opensearch_admin_username" {
  description = "Admin username for OpenSearch fine-grained access control"
  value       = var.opensearch_admin_username
}

output "opensearch_admin_password" {
  description = "Admin password for OpenSearch fine-grained access control (sensitive)"
  value       = var.opensearch_admin_password
  sensitive   = true
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.opensearch_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.opensearch_data.arn
}

output "s3_bucket_domain_name" {
  description = "Bucket domain name"
  value       = aws_s3_bucket.opensearch_data.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.opensearch_data.bucket_regional_domain_name
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda indexer function"
  value       = aws_lambda_function.opensearch_indexer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda indexer function"
  value       = aws_lambda_function.opensearch_indexer.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda indexer function"
  value       = aws_lambda_function.opensearch_indexer.invoke_arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda indexer function"
  value       = aws_lambda_function.opensearch_indexer.qualified_arn
}

# IAM Role Outputs
output "opensearch_service_role_arn" {
  description = "ARN of the OpenSearch service IAM role"
  value       = aws_iam_role.opensearch_service_role.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_opensearch_role.arn
}

# CloudWatch Outputs (conditional)
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_monitoring ? aws_cloudwatch_dashboard.opensearch_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.enable_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.opensearch_dashboard[0].dashboard_name}" : null
}

# Log Groups (conditional)
output "index_slow_logs_group" {
  description = "CloudWatch log group for OpenSearch index slow logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.opensearch_index_slow_logs[0].name : null
}

output "search_slow_logs_group" {
  description = "CloudWatch log group for OpenSearch search slow logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.opensearch_search_slow_logs[0].name : null
}

output "application_logs_group" {
  description = "CloudWatch log group for OpenSearch application logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.opensearch_application_logs[0].name : null
}

# Alarm Outputs (conditional)
output "high_search_latency_alarm" {
  description = "CloudWatch alarm for high search latency"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.opensearch_high_search_latency[0].alarm_name : null
}

output "cluster_red_alarm" {
  description = "CloudWatch alarm for cluster red status"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.opensearch_cluster_red[0].alarm_name : null
}

output "high_cpu_alarm" {
  description = "CloudWatch alarm for high CPU utilization"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.opensearch_high_cpu[0].alarm_name : null
}

# Network and Configuration Outputs
output "availability_zones" {
  description = "Availability zones used for the OpenSearch domain"
  value       = local.availability_zones
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Naming Outputs
output "name_prefix" {
  description = "Common name prefix used for all resources"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Configuration Information
output "opensearch_version" {
  description = "OpenSearch version deployed"
  value       = var.opensearch_version
}

output "instance_configuration" {
  description = "OpenSearch instance configuration summary"
  value = {
    data_node_type         = var.opensearch_instance_type
    data_node_count        = var.opensearch_instance_count
    master_node_type       = var.opensearch_master_instance_type
    master_node_count      = var.opensearch_master_instance_count
    availability_zones     = length(local.availability_zones)
    ultrawarm_enabled      = var.enable_ultrawarm
    storage_type          = var.opensearch_ebs_volume_type
    storage_size_gb       = var.opensearch_ebs_volume_size
    storage_iops          = var.opensearch_ebs_iops
  }
}

# Quick Start URLs and Commands
output "opensearch_dashboards_login_info" {
  description = "Login information for OpenSearch Dashboards"
  value = {
    url      = "https://${aws_opensearch_domain.main.kibana_endpoint}"
    username = var.opensearch_admin_username
    note     = "Use the admin password provided during deployment"
  }
}

output "sample_curl_commands" {
  description = "Sample curl commands for testing OpenSearch"
  value = {
    check_cluster_health = "curl -u ${var.opensearch_admin_username}:<password> https://${aws_opensearch_domain.main.endpoint}/_cluster/health"
    list_indices        = "curl -u ${var.opensearch_admin_username}:<password> https://${aws_opensearch_domain.main.endpoint}/_cat/indices?v"
    search_products     = "curl -u ${var.opensearch_admin_username}:<password> 'https://${aws_opensearch_domain.main.endpoint}/products/_search?q=*'"
    get_product         = "curl -u ${var.opensearch_admin_username}:<password> https://${aws_opensearch_domain.main.endpoint}/products/_doc/prod-001"
  }
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Cost optimization recommendations"
  value = {
    estimated_monthly_cost_range = "$200-500 USD for production configuration"
    cost_factors = [
      "Instance types and counts (data and master nodes)",
      "Storage type and size (EBS volumes)",
      "Data transfer costs",
      "UltraWarm storage (if enabled)",
      "CloudWatch logs retention"
    ]
    cost_optimization_tips = [
      "Use smaller instance types for development/testing",
      "Enable UltraWarm for infrequently accessed data",
      "Optimize log retention periods",
      "Monitor and right-size based on actual usage",
      "Consider Reserved Instances for predictable workloads"
    ]
  }
}

# Next Steps Information
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Wait for OpenSearch domain to be fully deployed (15-20 minutes)",
    "2. Access OpenSearch Dashboards using the provided URL and credentials",
    "3. Upload data to S3 bucket to trigger automatic indexing via Lambda",
    "4. Test search functionality using the sample curl commands",
    "5. Set up index templates and mappings for your specific data",
    "6. Configure additional monitoring and alerting as needed",
    "7. Review and optimize security settings for production use",
    "8. Set up backup and restore procedures"
  ]
}