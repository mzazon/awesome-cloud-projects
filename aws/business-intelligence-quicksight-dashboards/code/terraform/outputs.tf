# Outputs for QuickSight Business Intelligence Dashboard Infrastructure

# Resource identifiers and connection information
output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# S3 Data Storage
output "s3_bucket_name" {
  description = "Name of the S3 bucket containing sample data for QuickSight"
  value       = aws_s3_bucket.quicksight_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket containing sample data"
  value       = aws_s3_bucket.quicksight_data.arn
}

output "s3_data_location" {
  description = "S3 location of the sample sales data CSV file"
  value       = var.create_sample_data ? "s3://${aws_s3_bucket.quicksight_data.bucket}/${aws_s3_object.sample_sales_data[0].key}" : "s3://${aws_s3_bucket.quicksight_data.bucket}/data/sales_data.csv"
}

# RDS Database Information
output "rds_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.postgresql.identifier
}

output "rds_endpoint" {
  description = "RDS instance endpoint for database connections"
  value       = aws_db_instance.postgresql.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgresql.port
}

output "rds_database_name" {
  description = "Name of the PostgreSQL database"
  value       = aws_db_instance.postgresql.db_name
}

output "rds_username" {
  description = "Master username for RDS instance"
  value       = aws_db_instance.postgresql.username
  sensitive   = true
}

# Security and Access
output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret containing RDS credentials"
  value       = aws_secretsmanager_secret.rds_password.name
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret containing RDS credentials"
  value       = aws_secretsmanager_secret.rds_password.arn
}

output "quicksight_service_role_arn" {
  description = "ARN of the IAM role for QuickSight service access"
  value       = aws_iam_role.quicksight_service_role.arn
}

output "quicksight_vpc_role_arn" {
  description = "ARN of the IAM role for QuickSight VPC connection"
  value       = aws_iam_role.quicksight_vpc_role.arn
}

# Network Infrastructure
output "vpc_id" {
  description = "ID of the VPC created for RDS"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [aws_subnet.public_1.id, aws_subnet.public_2.id]
}

output "rds_security_group_id" {
  description = "ID of the security group for RDS access"
  value       = aws_security_group.rds.id
}

# QuickSight Resources
output "quicksight_s3_data_source_id" {
  description = "QuickSight S3 data source identifier"
  value       = aws_quicksight_data_source.s3_source.data_source_id
}

output "quicksight_s3_data_source_arn" {
  description = "ARN of the QuickSight S3 data source"
  value       = aws_quicksight_data_source.s3_source.arn
}

output "quicksight_rds_data_source_id" {
  description = "QuickSight RDS data source identifier"
  value       = aws_quicksight_data_source.rds_source.data_source_id
}

output "quicksight_rds_data_source_arn" {
  description = "ARN of the QuickSight RDS data source"
  value       = aws_quicksight_data_source.rds_source.arn
}

output "quicksight_vpc_connection_id" {
  description = "QuickSight VPC connection identifier"
  value       = aws_quicksight_vpc_connection.rds_connection.vpc_connection_id
}

output "quicksight_vpc_connection_arn" {
  description = "ARN of the QuickSight VPC connection"
  value       = aws_quicksight_vpc_connection.rds_connection.arn
}

output "quicksight_dataset_id" {
  description = "QuickSight dataset identifier"
  value       = aws_quicksight_data_set.sales_dataset.data_set_id
}

output "quicksight_dataset_arn" {
  description = "ARN of the QuickSight dataset"
  value       = aws_quicksight_data_set.sales_dataset.arn
}

# Monitoring and Management
output "rds_monitoring_role_arn" {
  description = "ARN of the IAM role for RDS enhanced monitoring"
  value       = aws_iam_role.rds_monitoring.arn
}

# Access URLs and Instructions
output "quicksight_console_url" {
  description = "URL to access the QuickSight console"
  value       = "https://quicksight.aws.amazon.com/"
}

output "rds_connection_string" {
  description = "PostgreSQL connection string (without password)"
  value       = "postgresql://${aws_db_instance.postgresql.username}:<password>@${aws_db_instance.postgresql.endpoint}:${aws_db_instance.postgresql.port}/${aws_db_instance.postgresql.db_name}"
  sensitive   = true
}

# Cost Management Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for deployed resources (USD)"
  value = {
    "quicksight_standard_per_user"     = "$9.00"
    "quicksight_enterprise_per_user"   = "$18.00"
    "quicksight_enterprise_account"    = "$250.00"
    "s3_storage_gb"                    = "$0.023"
    "rds_db_t3_micro"                  = "$13.32"
    "rds_storage_20gb"                 = "$2.30"
    "vpc_nat_gateway"                  = "$0.00 (not used)"
    "data_transfer"                    = "varies by usage"
    "note"                             = "Actual costs may vary based on usage patterns and data transfer"
  }
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources and next steps"
  value = {
    "s3_bucket"           = "Created with sample sales data (if enabled)"
    "rds_database"        = "PostgreSQL instance with enhanced monitoring"
    "quicksight_sources"  = "S3 and RDS data sources configured"
    "quicksight_dataset"  = "Sales dataset ready for analysis"
    "iam_roles"          = "Service roles created with least privilege access"
    "vpc_network"        = "VPC with public subnets for RDS access"
    "security"           = "RDS credentials stored in Secrets Manager"
    "next_steps"         = [
      "1. Access QuickSight console to create analyses and dashboards",
      "2. Set up QuickSight users and permissions as needed",
      "3. Create visualizations using the configured dataset",
      "4. Configure dashboard sharing and embedding if required",
      "5. Set up scheduled data refreshes for production use"
    ]
  }
}

# Security Recommendations
output "security_recommendations" {
  description = "Security recommendations for production deployment"
  value = {
    "rds_access"           = "Set publicly_accessible to false and use VPC endpoints"
    "database_credentials" = "Rotate RDS passwords regularly using Secrets Manager"
    "iam_policies"        = "Review and minimize IAM permissions based on actual usage"
    "network_security"    = "Restrict CIDR blocks to specific IP ranges"
    "encryption"          = "Consider using customer-managed KMS keys for additional control"
    "monitoring"          = "Enable CloudTrail logging for QuickSight API calls"
    "backup_strategy"     = "Configure automated backups and test restore procedures"
    "deletion_protection" = "Enable deletion protection for production RDS instances"
  }
}