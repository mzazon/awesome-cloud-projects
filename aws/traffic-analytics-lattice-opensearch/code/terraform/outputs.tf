# Outputs for Traffic Analytics with VPC Lattice and OpenSearch
# These outputs provide important information for verification, integration, and management

# OpenSearch Service Outputs
output "opensearch_domain_name" {
  description = "Name of the OpenSearch domain"
  value       = aws_opensearch_domain.traffic_analytics.domain_name
}

output "opensearch_domain_id" {
  description = "Unique identifier for the OpenSearch domain"
  value       = aws_opensearch_domain.traffic_analytics.domain_id
}

output "opensearch_endpoint" {
  description = "Domain-specific endpoint used to submit index, search, and data upload requests"
  value       = aws_opensearch_domain.traffic_analytics.endpoint
}

output "opensearch_dashboards_endpoint" {
  description = "Domain-specific endpoint for OpenSearch Dashboards"
  value       = aws_opensearch_domain.traffic_analytics.dashboard_endpoint
}

output "opensearch_arn" {
  description = "ARN of the OpenSearch domain"
  value       = aws_opensearch_domain.traffic_analytics.arn
}

output "opensearch_domain_url" {
  description = "Full HTTPS URL for accessing the OpenSearch domain"
  value       = "https://${aws_opensearch_domain.traffic_analytics.endpoint}"
}

output "opensearch_dashboards_url" {
  description = "Full HTTPS URL for accessing OpenSearch Dashboards"
  value       = "https://${aws_opensearch_domain.traffic_analytics.dashboard_endpoint}/_dashboards"
}

# Kinesis Data Firehose Outputs
output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.traffic_analytics.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.traffic_analytics.arn
}

output "firehose_role_arn" {
  description = "ARN of the IAM role used by Kinesis Data Firehose"
  value       = aws_iam_role.firehose.arn
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda transformation function"
  value       = aws_lambda_function.transform.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda transformation function"
  value       = aws_lambda_function.transform.arn
}

output "lambda_role_arn" {
  description = "ARN of the IAM role used by the Lambda function"
  value       = aws_iam_role.lambda_transform.arn
}

# S3 Backup Bucket Outputs
output "s3_backup_bucket_name" {
  description = "Name of the S3 bucket used for backup and error records"
  value       = aws_s3_bucket.backup.bucket
}

output "s3_backup_bucket_arn" {
  description = "ARN of the S3 backup bucket"
  value       = aws_s3_bucket.backup.arn
}

output "s3_backup_bucket_domain_name" {
  description = "Bucket domain name for the S3 backup bucket"
  value       = aws_s3_bucket.backup.bucket_domain_name
}

# VPC Lattice Outputs
output "vpc_lattice_service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.demo.id
}

output "vpc_lattice_service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.demo.arn
}

output "vpc_lattice_service_id" {
  description = "ID of the demo VPC Lattice service"
  value       = aws_vpclattice_service.demo.id
}

output "vpc_lattice_service_arn" {
  description = "ARN of the demo VPC Lattice service"
  value       = aws_vpclattice_service.demo.arn
}

output "access_log_subscription_id" {
  description = "ID of the VPC Lattice access log subscription"
  value       = aws_vpclattice_access_log_subscription.traffic_analytics.id
}

output "access_log_subscription_arn" {
  description = "ARN of the VPC Lattice access log subscription"
  value       = aws_vpclattice_access_log_subscription.traffic_analytics.arn
}

# CloudWatch Monitoring Outputs
output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.traffic_analytics.dashboard_name}"
}

output "firehose_log_group_name" {
  description = "CloudWatch log group name for Firehose delivery stream"
  value       = aws_cloudwatch_log_group.firehose.name
}

# Resource Identifiers for Automation
output "resource_names" {
  description = "Map of all resource names created by this configuration"
  value = {
    opensearch_domain     = aws_opensearch_domain.traffic_analytics.domain_name
    firehose_stream      = aws_kinesis_firehose_delivery_stream.traffic_analytics.name
    lambda_function      = aws_lambda_function.transform.function_name
    s3_bucket           = aws_s3_bucket.backup.bucket
    service_network     = aws_vpclattice_service_network.demo.id
    demo_service        = aws_vpclattice_service.demo.id
    dashboard           = aws_cloudwatch_dashboard.traffic_analytics.dashboard_name
  }
}

output "resource_arns" {
  description = "Map of all resource ARNs created by this configuration"
  value = {
    opensearch_domain    = aws_opensearch_domain.traffic_analytics.arn
    firehose_stream     = aws_kinesis_firehose_delivery_stream.traffic_analytics.arn
    lambda_function     = aws_lambda_function.transform.arn
    s3_bucket          = aws_s3_bucket.backup.arn
    service_network    = aws_vpclattice_service_network.demo.arn
    demo_service       = aws_vpclattice_service.demo.arn
    access_log_sub     = aws_vpclattice_access_log_subscription.traffic_analytics.arn
    firehose_role      = aws_iam_role.firehose.arn
    lambda_role        = aws_iam_role.lambda_transform.arn
  }
}

# Cost and Usage Information
output "estimated_monthly_cost_info" {
  description = "Information about estimated monthly costs (approximate)"
  value = {
    opensearch_instance = "OpenSearch ${var.opensearch_instance_type} instance: ~$20-40/month"
    opensearch_storage  = "EBS storage ${var.opensearch_volume_size}GB: ~$2-5/month"
    firehose           = "Kinesis Data Firehose: Pay per GB ingested"
    lambda             = "Lambda: Pay per invocation and duration"
    s3_storage         = "S3 storage: Pay per GB stored"
    note               = "Actual costs depend on usage patterns and data volume"
  }
}

# Quick Access Commands
output "useful_commands" {
  description = "Useful AWS CLI commands for managing the deployed resources"
  value = {
    check_opensearch_health = "aws opensearch describe-domain --domain-name ${aws_opensearch_domain.traffic_analytics.domain_name} --query 'DomainStatus.Processing'"
    check_firehose_status   = "aws firehose describe-delivery-stream --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.traffic_analytics.name} --query 'DeliveryStreamDescription.DeliveryStreamStatus'"
    test_firehose_delivery  = "echo '{\"test\":\"data\"}' | aws firehose put-record --delivery-stream-name ${aws_kinesis_firehose_delivery_stream.traffic_analytics.name} --record Data=blob://dev/stdin"
    view_lambda_logs        = "aws logs describe-log-streams --log-group-name /aws/lambda/${aws_lambda_function.transform.function_name} --order-by LastEventTime --descending"
    check_access_logs       = "aws vpc-lattice get-access-log-subscription --access-log-subscription-identifier ${aws_vpclattice_access_log_subscription.traffic_analytics.id}"
  }
}

# Integration Information
output "integration_endpoints" {
  description = "Key endpoints for integrating with external systems"
  value = {
    opensearch_api         = "https://${aws_opensearch_domain.traffic_analytics.endpoint}"
    opensearch_dashboards  = "https://${aws_opensearch_domain.traffic_analytics.dashboard_endpoint}/_dashboards"
    firehose_stream_name   = aws_kinesis_firehose_delivery_stream.traffic_analytics.name
    s3_backup_location     = "s3://${aws_s3_bucket.backup.bucket}/firehose-backup/"
    service_network_domain = aws_vpclattice_service_network.demo.id
  }
}

# Security and Access Information
output "security_information" {
  description = "Security-related information and access details"
  value = {
    opensearch_encryption_at_rest   = "Enabled"
    opensearch_node_to_node_encryption = "Enabled"
    opensearch_https_enforcement    = "Enabled"
    s3_bucket_encryption           = "AES256"
    s3_public_access_blocked       = "True"
    iam_roles_created             = "Firehose role, Lambda role"
    access_policy_note            = "OpenSearch domain has open access policy - restrict for production use"
  }
}

# Environment Information
output "deployment_info" {
  description = "Information about the deployment environment"
  value = {
    aws_region      = data.aws_region.current.name
    aws_account_id  = data.aws_caller_identity.current.account_id
    project_name    = var.project_name
    environment     = var.environment
    name_suffix     = local.name_suffix
    terraform_version = ">=1.0"
    deployment_time = timestamp()
  }
}