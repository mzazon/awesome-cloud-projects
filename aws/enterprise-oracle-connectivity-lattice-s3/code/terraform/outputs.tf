# Outputs for Enterprise Oracle Database Connectivity with VPC Lattice and S3
# Comprehensive output values for integration verification and external reference

# =============================================================================
# GENERAL INFORMATION
# =============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Oracle Database backups"
  value       = aws_s3_bucket.oracle_backup.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Oracle Database backups"
  value       = aws_s3_bucket.oracle_backup.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.oracle_backup.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.oracle_backup.bucket_regional_domain_name
}

output "s3_bucket_hosted_zone_id" {
  description = "Route 53 Hosted Zone ID for the S3 bucket"
  value       = aws_s3_bucket.oracle_backup.hosted_zone_id
}

output "s3_bucket_versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled"
  value       = var.enable_s3_versioning
}

output "s3_lifecycle_policy_enabled" {
  description = "Whether S3 lifecycle policy is configured"
  value       = true
}

output "s3_lifecycle_ia_transition_days" {
  description = "Number of days before transitioning to IA storage class"
  value       = var.s3_lifecycle_transition_ia_days
}

output "s3_lifecycle_glacier_transition_days" {
  description = "Number of days before transitioning to Glacier storage class"
  value       = var.s3_lifecycle_transition_glacier_days
}

# =============================================================================
# REDSHIFT CLUSTER OUTPUTS
# =============================================================================

output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "Endpoint of the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.endpoint
}

output "redshift_cluster_port" {
  description = "Port of the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.port
}

output "redshift_database_name" {
  description = "Name of the default database in the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.database_name
}

output "redshift_master_username" {
  description = "Master username for the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.master_username
  sensitive   = true
}

output "redshift_cluster_arn" {
  description = "ARN of the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.arn
}

output "redshift_cluster_type" {
  description = "Type of the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.cluster_type
}

output "redshift_node_type" {
  description = "Node type of the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.node_type
}

output "redshift_number_of_nodes" {
  description = "Number of nodes in the Redshift cluster"
  value       = aws_redshift_cluster.oracle_analytics.number_of_nodes
}

output "redshift_encrypted" {
  description = "Whether the Redshift cluster is encrypted"
  value       = aws_redshift_cluster.oracle_analytics.encrypted
}

output "redshift_publicly_accessible" {
  description = "Whether the Redshift cluster is publicly accessible"
  value       = aws_redshift_cluster.oracle_analytics.publicly_accessible
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "redshift_iam_role_arn" {
  description = "ARN of the IAM role for Redshift cluster"
  value       = aws_iam_role.redshift_role.arn
}

output "redshift_iam_role_name" {
  description = "Name of the IAM role for Redshift cluster"
  value       = aws_iam_role.redshift_role.name
}

# =============================================================================
# NETWORKING OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "VPC ID used for resources"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for resources"
  value       = local.subnet_ids
}

output "redshift_security_group_id" {
  description = "Security group ID for the Redshift cluster"
  value       = aws_security_group.redshift.id
}

output "redshift_subnet_group_name" {
  description = "Name of the Redshift subnet group"
  value       = aws_redshift_subnet_group.oracle_analytics.name
}

# =============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# =============================================================================

output "cloudwatch_monitoring_enabled" {
  description = "Whether CloudWatch monitoring is enabled"
  value       = var.enable_cloudwatch_monitoring
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Oracle operations"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.oracle_operations[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Oracle operations"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.oracle_operations[0].arn : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for Oracle integration"
  value       = var.enable_cloudwatch_monitoring ? aws_cloudwatch_dashboard.oracle_integration[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard for Oracle integration"
  value = var.enable_cloudwatch_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.oracle_integration[0].dashboard_name}" : null
}

# =============================================================================
# CONFIGURATION OUTPUTS
# =============================================================================

output "s3_access_enabled" {
  description = "Whether S3 access is configured to be enabled for Oracle Database@AWS"
  value       = var.enable_s3_access
}

output "zero_etl_access_enabled" {
  description = "Whether Zero-ETL access is configured to be enabled for Oracle Database@AWS"
  value       = var.enable_zero_etl_access
}

output "s3_bucket_policy_enabled" {
  description = "Whether custom S3 bucket policy is enabled"
  value       = var.enable_s3_bucket_policy
}

# =============================================================================
# CONNECTION INFORMATION
# =============================================================================

output "redshift_connection_string" {
  description = "Connection string for the Redshift cluster (without password)"
  value       = "host=${aws_redshift_cluster.oracle_analytics.endpoint} port=${aws_redshift_cluster.oracle_analytics.port} dbname=${aws_redshift_cluster.oracle_analytics.database_name} user=${aws_redshift_cluster.oracle_analytics.master_username}"
  sensitive   = false
}

output "redshift_jdbc_url" {
  description = "JDBC URL for the Redshift cluster"
  value       = "jdbc:redshift://${aws_redshift_cluster.oracle_analytics.endpoint}:${aws_redshift_cluster.oracle_analytics.port}/${aws_redshift_cluster.oracle_analytics.database_name}"
}

# =============================================================================
# INTEGRATION VERIFICATION COMMANDS
# =============================================================================

output "verification_commands" {
  description = "Commands to verify the Oracle Database@AWS integration"
  value = {
    s3_bucket_check = "aws s3 ls s3://${aws_s3_bucket.oracle_backup.bucket}/"
    redshift_status = "aws redshift describe-clusters --cluster-identifier ${aws_redshift_cluster.oracle_analytics.cluster_identifier}"
    cloudwatch_logs = var.enable_cloudwatch_monitoring ? "aws logs describe-log-groups --log-group-name-prefix ${aws_cloudwatch_log_group.oracle_operations[0].name}" : "CloudWatch monitoring not enabled"
  }
}

# =============================================================================
# COST INFORMATION
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for deployed resources (approximate)"
  value = {
    redshift_cluster = "~$${var.redshift_node_type == "dc2.large" ? "160" : "varies"}/month (${var.redshift_node_type})"
    s3_storage      = "~$23/TB/month (Standard storage)"
    cloudwatch_logs = "~$0.50/GB ingested"
    data_transfer   = "Variable based on usage"
    note            = "Costs are estimates and may vary based on actual usage, region, and current AWS pricing"
  }
}

# =============================================================================
# RESOURCE TAGS
# =============================================================================

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}