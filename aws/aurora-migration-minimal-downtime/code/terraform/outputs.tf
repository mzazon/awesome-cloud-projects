# Outputs for Aurora database migration infrastructure
# These outputs provide important information for post-deployment configuration and monitoring

# ========================================
# VPC and Networking Outputs
# ========================================

output "vpc_id" {
  description = "ID of the VPC created for the migration"
  value       = aws_vpc.migration_vpc.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.migration_vpc.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public_subnets[*].id
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets"
  value       = aws_subnet.private_subnets[*].cidr_block
}

# ========================================
# Security Group Outputs
# ========================================

output "aurora_security_group_id" {
  description = "ID of the Aurora security group"
  value       = aws_security_group.aurora_sg.id
}

output "dms_security_group_id" {
  description = "ID of the DMS security group"
  value       = aws_security_group.dms_sg.id
}

# ========================================
# Aurora Database Outputs
# ========================================

output "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.aurora_cluster.cluster_identifier
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster endpoint for write operations"
  value       = aws_rds_cluster.aurora_cluster.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint for read operations"
  value       = aws_rds_cluster.aurora_cluster.reader_endpoint
}

output "aurora_cluster_port" {
  description = "Aurora cluster port"
  value       = aws_rds_cluster.aurora_cluster.port
}

output "aurora_cluster_arn" {
  description = "Aurora cluster ARN"
  value       = aws_rds_cluster.aurora_cluster.arn
}

output "aurora_cluster_engine" {
  description = "Aurora cluster engine"
  value       = aws_rds_cluster.aurora_cluster.engine
}

output "aurora_cluster_engine_version" {
  description = "Aurora cluster engine version"
  value       = aws_rds_cluster.aurora_cluster.engine_version
}

output "aurora_database_name" {
  description = "Name of the Aurora database"
  value       = aws_rds_cluster.aurora_cluster.database_name
}

output "aurora_master_username" {
  description = "Aurora cluster master username"
  value       = aws_rds_cluster.aurora_cluster.master_username
  sensitive   = true
}

output "aurora_master_password_secret_arn" {
  description = "ARN of the secret containing Aurora master password"
  value       = aws_secretsmanager_secret.aurora_master_password.arn
  sensitive   = true
}

output "aurora_primary_instance_id" {
  description = "Aurora primary instance identifier"
  value       = aws_rds_cluster_instance.aurora_primary.identifier
}

output "aurora_reader_instance_id" {
  description = "Aurora reader instance identifier"
  value       = aws_rds_cluster_instance.aurora_reader.identifier
}

output "aurora_cluster_parameter_group_name" {
  description = "Name of the Aurora cluster parameter group"
  value       = aws_rds_cluster_parameter_group.aurora_cluster_pg.name
}

# ========================================
# DMS Outputs
# ========================================

output "dms_replication_instance_id" {
  description = "DMS replication instance identifier"
  value       = aws_dms_replication_instance.dms_replication_instance.replication_instance_id
}

output "dms_replication_instance_arn" {
  description = "DMS replication instance ARN"
  value       = aws_dms_replication_instance.dms_replication_instance.replication_instance_arn
}

output "dms_replication_instance_class" {
  description = "DMS replication instance class"
  value       = aws_dms_replication_instance.dms_replication_instance.replication_instance_class
}

output "dms_replication_instance_allocated_storage" {
  description = "DMS replication instance allocated storage"
  value       = aws_dms_replication_instance.dms_replication_instance.allocated_storage
}

output "dms_subnet_group_id" {
  description = "DMS replication subnet group identifier"
  value       = aws_dms_replication_subnet_group.dms_subnet_group.replication_subnet_group_id
}

output "dms_source_endpoint_id" {
  description = "DMS source endpoint identifier"
  value       = aws_dms_endpoint.source_endpoint.endpoint_id
}

output "dms_source_endpoint_arn" {
  description = "DMS source endpoint ARN"
  value       = aws_dms_endpoint.source_endpoint.endpoint_arn
}

output "dms_target_endpoint_id" {
  description = "DMS target endpoint identifier"
  value       = aws_dms_endpoint.target_endpoint.endpoint_id
}

output "dms_target_endpoint_arn" {
  description = "DMS target endpoint ARN"
  value       = aws_dms_endpoint.target_endpoint.endpoint_arn
}

output "dms_migration_task_id" {
  description = "DMS migration task identifier"
  value       = aws_dms_replication_task.migration_task.replication_task_id
}

output "dms_migration_task_arn" {
  description = "DMS migration task ARN"
  value       = aws_dms_replication_task.migration_task.replication_task_arn
}

# ========================================
# Route 53 Outputs
# ========================================

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.database_zone.zone_id
}

output "route53_zone_name" {
  description = "Route 53 hosted zone name"
  value       = aws_route53_zone.database_zone.name
}

output "route53_record_name" {
  description = "Route 53 database record name"
  value       = aws_route53_record.database_record.name
}

output "route53_record_fqdn" {
  description = "Fully qualified domain name for database access"
  value       = aws_route53_record.database_record.fqdn
}

# ========================================
# IAM Outputs
# ========================================

output "dms_vpc_role_arn" {
  description = "ARN of the DMS VPC role"
  value       = aws_iam_role.dms_vpc_role.arn
}

output "dms_cloudwatch_role_arn" {
  description = "ARN of the DMS CloudWatch role"
  value       = aws_iam_role.dms_cloudwatch_role.arn
}

output "aurora_monitoring_role_arn" {
  description = "ARN of the Aurora monitoring role"
  value       = aws_iam_role.aurora_monitoring_role.arn
}

# ========================================
# CloudWatch Outputs
# ========================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for DMS"
  value       = aws_cloudwatch_log_group.dms_logs.name
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for migration monitoring"
  value       = aws_cloudwatch_dashboard.migration_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.migration_dashboard.dashboard_name}"
}

# ========================================
# Encryption Outputs
# ========================================

output "aurora_kms_key_id" {
  description = "KMS key ID used for Aurora encryption"
  value       = var.enable_encryption ? aws_kms_key.aurora_encryption[0].key_id : null
}

output "aurora_kms_key_arn" {
  description = "KMS key ARN used for Aurora encryption"
  value       = var.enable_encryption ? aws_kms_key.aurora_encryption[0].arn : null
}

output "aurora_kms_alias" {
  description = "KMS key alias for Aurora encryption"
  value       = var.enable_encryption ? aws_kms_alias.aurora_encryption[0].name : null
}

# ========================================
# Connection Information Outputs
# ========================================

output "connection_information" {
  description = "Important connection information for the migration"
  value = {
    aurora_cluster_endpoint = aws_rds_cluster.aurora_cluster.endpoint
    aurora_reader_endpoint  = aws_rds_cluster.aurora_cluster.reader_endpoint
    aurora_port            = aws_rds_cluster.aurora_cluster.port
    aurora_database_name   = aws_rds_cluster.aurora_cluster.database_name
    aurora_username        = aws_rds_cluster.aurora_cluster.master_username
    dns_endpoint           = aws_route53_record.database_record.fqdn
    vpc_id                 = aws_vpc.migration_vpc.id
    security_group_id      = aws_security_group.aurora_sg.id
  }
}

# ========================================
# Migration Commands Outputs
# ========================================

output "migration_commands" {
  description = "Useful commands for managing the migration"
  value = {
    start_migration_task = "aws dms start-replication-task --replication-task-arn ${aws_dms_replication_task.migration_task.replication_task_arn} --start-replication-task-type start-replication"
    stop_migration_task  = "aws dms stop-replication-task --replication-task-arn ${aws_dms_replication_task.migration_task.replication_task_arn}"
    check_task_status    = "aws dms describe-replication-tasks --filters Name=replication-task-id,Values=${aws_dms_replication_task.migration_task.replication_task_id}"
    test_source_connection = "aws dms test-connection --replication-instance-arn ${aws_dms_replication_instance.dms_replication_instance.replication_instance_arn} --endpoint-arn ${aws_dms_endpoint.source_endpoint.endpoint_arn}"
    test_target_connection = "aws dms test-connection --replication-instance-arn ${aws_dms_replication_instance.dms_replication_instance.replication_instance_arn} --endpoint-arn ${aws_dms_endpoint.target_endpoint.endpoint_arn}"
  }
}

# ========================================
# Resource Summary Output
# ========================================

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_id                     = aws_vpc.migration_vpc.id
    aurora_cluster_id          = aws_rds_cluster.aurora_cluster.cluster_identifier
    aurora_endpoint            = aws_rds_cluster.aurora_cluster.endpoint
    dms_replication_instance   = aws_dms_replication_instance.dms_replication_instance.replication_instance_id
    dms_migration_task         = aws_dms_replication_task.migration_task.replication_task_id
    route53_zone               = aws_route53_zone.database_zone.name
    cloudwatch_dashboard       = aws_cloudwatch_dashboard.migration_dashboard.dashboard_name
    environment                = var.environment
    region                     = var.aws_region
  }
}

# ========================================
# Next Steps Output
# ========================================

output "next_steps" {
  description = "Next steps to complete the migration setup"
  value = [
    "1. Update source database configuration variables with your actual source database details",
    "2. Ensure source database has binary logging enabled (MySQL) or appropriate CDC configuration",
    "3. Test connectivity to source database from DMS replication instance",
    "4. Start the DMS migration task using the provided AWS CLI command",
    "5. Monitor migration progress using CloudWatch dashboard: ${aws_cloudwatch_dashboard.migration_dashboard.dashboard_name}",
    "6. Once full load completes and CDC is synchronized, update Route 53 record to point to Aurora",
    "7. Test application connectivity through DNS endpoint: ${aws_route53_record.database_record.fqdn}",
    "8. Monitor Aurora performance and adjust instance classes if needed"
  ]
}