# ==============================================================================
# OUTPUTS
# ==============================================================================

# Database Connection Information
output "database_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.database.endpoint
}

output "database_port" {
  description = "RDS instance port"
  value       = aws_db_instance.database.port
}

output "database_name" {
  description = "Database name"
  value       = aws_db_instance.database.db_name
}

output "database_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.database.id
}

output "database_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.database.arn
}

# RDS Proxy Information
output "proxy_endpoint" {
  description = "RDS Proxy endpoint"
  value       = aws_db_proxy.database.endpoint
}

output "proxy_name" {
  description = "RDS Proxy name"
  value       = aws_db_proxy.database.name
}

output "proxy_arn" {
  description = "RDS Proxy ARN"
  value       = aws_db_proxy.database.arn
}

# Security Information
output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = aws_kms_key.rds_encryption.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = aws_kms_key.rds_encryption.arn
}

output "kms_key_alias" {
  description = "KMS key alias"
  value       = aws_kms_alias.rds_encryption.name
}

output "security_group_id" {
  description = "Security group ID for database access"
  value       = aws_security_group.database.id
}

output "security_group_arn" {
  description = "Security group ARN for database access"
  value       = aws_security_group.database.arn
}

# IAM Information
output "database_access_role_arn" {
  description = "IAM role ARN for database access"
  value       = aws_iam_role.database_access.arn
}

output "database_access_role_name" {
  description = "IAM role name for database access"
  value       = aws_iam_role.database_access.name
}

output "database_access_policy_arn" {
  description = "IAM policy ARN for database access"
  value       = aws_iam_policy.database_access.arn
}

output "monitoring_role_arn" {
  description = "IAM role ARN for enhanced monitoring"
  value       = aws_iam_role.monitoring.arn
}

# Database User Information
output "iam_database_user" {
  description = "Database user configured for IAM authentication"
  value       = var.db_username
}

output "database_admin_user" {
  description = "Database admin username"
  value       = var.db_admin_username
}

# Network Information
output "db_subnet_group_name" {
  description = "Database subnet group name"
  value       = aws_db_subnet_group.database.name
}

output "db_subnet_group_arn" {
  description = "Database subnet group ARN"
  value       = aws_db_subnet_group.database.arn
}

output "vpc_id" {
  description = "VPC ID where resources are deployed"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "Subnet IDs used for database deployment"
  value       = local.subnet_ids
}

# Monitoring Information
output "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for database logs"
  value       = aws_cloudwatch_log_group.database.name
}

output "cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for database logs"
  value       = aws_cloudwatch_log_group.database.arn
}

output "cpu_utilization_alarm_name" {
  description = "CloudWatch alarm name for CPU utilization"
  value       = aws_cloudwatch_metric_alarm.cpu_utilization.alarm_name
}

output "database_connections_alarm_name" {
  description = "CloudWatch alarm name for database connections"
  value       = aws_cloudwatch_metric_alarm.database_connections.alarm_name
}

output "authentication_failures_alarm_name" {
  description = "CloudWatch alarm name for authentication failures"
  value       = aws_cloudwatch_metric_alarm.authentication_failures.alarm_name
}

# Secrets Manager Information
output "connection_secret_arn" {
  description = "Secrets Manager secret ARN for database connection information"
  value       = aws_secretsmanager_secret.database_connection.arn
}

output "connection_secret_name" {
  description = "Secrets Manager secret name for database connection information"
  value       = aws_secretsmanager_secret.database_connection.name
}

# Configuration Information
output "parameter_group_name" {
  description = "Database parameter group name"
  value       = aws_db_parameter_group.database.name
}

output "parameter_group_arn" {
  description = "Database parameter group ARN"
  value       = aws_db_parameter_group.database.arn
}

# Security Features Status
output "encryption_at_rest_enabled" {
  description = "Whether encryption at rest is enabled"
  value       = aws_db_instance.database.storage_encrypted
}

output "iam_authentication_enabled" {
  description = "Whether IAM database authentication is enabled"
  value       = aws_db_instance.database.iam_database_authentication_enabled
}

output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled"
  value       = aws_db_instance.database.performance_insights_enabled
}

output "enhanced_monitoring_enabled" {
  description = "Whether enhanced monitoring is enabled"
  value       = var.enhanced_monitoring_interval > 0
}

output "backup_retention_period" {
  description = "Backup retention period in days"
  value       = aws_db_instance.database.backup_retention_period
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled"
  value       = aws_db_instance.database.deletion_protection
}

# Connection Commands
output "iam_auth_token_command" {
  description = "AWS CLI command to generate IAM authentication token"
  value = "aws rds generate-db-auth-token --hostname ${aws_db_instance.database.endpoint} --port ${aws_db_instance.database.port} --region ${data.aws_region.current.name} --username ${var.db_username}"
}

output "direct_connection_command" {
  description = "PostgreSQL connection command using direct endpoint"
  value = "PGPASSWORD=\"$(aws rds generate-db-auth-token --hostname ${aws_db_instance.database.endpoint} --port ${aws_db_instance.database.port} --region ${data.aws_region.current.name} --username ${var.db_username})\" psql -h ${aws_db_instance.database.endpoint} -U ${var.db_username} -d ${aws_db_instance.database.db_name} -p ${aws_db_instance.database.port}"
}

output "proxy_connection_command" {
  description = "PostgreSQL connection command using RDS Proxy"
  value = "PGPASSWORD=\"$(aws rds generate-db-auth-token --hostname ${aws_db_proxy.database.endpoint} --port ${aws_db_instance.database.port} --region ${data.aws_region.current.name} --username ${var.db_username})\" psql -h ${aws_db_proxy.database.endpoint} -U ${var.db_username} -d ${aws_db_instance.database.db_name} -p ${aws_db_instance.database.port}"
}

# Security Compliance Report
output "security_compliance_report" {
  description = "Comprehensive security compliance report"
  value       = local.security_compliance_report
}

# Resource Identifiers for Cleanup
output "resource_identifiers" {
  description = "Resource identifiers for cleanup operations"
  value = {
    db_instance_identifier     = aws_db_instance.database.id
    db_proxy_name             = aws_db_proxy.database.name
    db_subnet_group_name      = aws_db_subnet_group.database.name
    security_group_id         = aws_security_group.database.id
    parameter_group_name      = aws_db_parameter_group.database.name
    iam_role_name             = aws_iam_role.database_access.name
    iam_policy_arn            = aws_iam_policy.database_access.arn
    monitoring_role_name      = aws_iam_role.monitoring.name
    kms_key_id                = aws_kms_key.rds_encryption.key_id
    kms_key_alias             = aws_kms_alias.rds_encryption.name
    cloudwatch_log_group_name = aws_cloudwatch_log_group.database.name
    secrets_manager_secret_arn = aws_secretsmanager_secret.database_connection.arn
  }
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information and metadata"
  value = {
    region              = data.aws_region.current.name
    account_id          = data.aws_caller_identity.current.account_id
    environment         = var.environment
    project_name        = var.project_name
    random_suffix       = local.random_suffix
    deployment_timestamp = timestamp()
    terraform_version   = "~> 1.0"
    aws_provider_version = "~> 5.0"
  }
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Information for cost optimization and monitoring"
  value = {
    instance_class                = var.db_instance_class
    allocated_storage            = var.db_allocated_storage
    storage_type                 = var.db_storage_type
    backup_retention_period      = var.db_backup_retention_period
    enhanced_monitoring_interval = var.enhanced_monitoring_interval
    performance_insights_retention = var.performance_insights_retention_period
    deletion_protection_enabled  = var.deletion_protection
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_encryption_status = "aws rds describe-db-instances --db-instance-identifier ${aws_db_instance.database.id} --query 'DBInstances[0].{Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId,IAMAuth:IAMDatabaseAuthenticationEnabled}' --output table"
    check_proxy_status     = "aws rds describe-db-proxies --db-proxy-name ${aws_db_proxy.database.name} --query 'DBProxies[0].{Name:DBProxyName,Status:Status,RequireTLS:RequireTLS}' --output table"
    test_ssl_connection    = "PGPASSWORD=\"$(aws rds generate-db-auth-token --hostname ${aws_db_instance.database.endpoint} --port ${aws_db_instance.database.port} --region ${data.aws_region.current.name} --username ${var.db_username})\" psql -h ${aws_db_instance.database.endpoint} -U ${var.db_username} -d ${aws_db_instance.database.db_name} -p ${aws_db_instance.database.port} -c \"SELECT ssl_is_used() AS ssl_enabled;\""
    check_cloudwatch_alarms = "aws cloudwatch describe-alarms --alarm-name-prefix 'RDS-' --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue}' --output table"
  }
}

# Usage Instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    setup_database_user = "Connect to the database as admin and create the IAM user: CREATE USER ${var.db_username}; GRANT rds_iam TO ${var.db_username};"
    assume_role_command = "aws sts assume-role --role-arn ${aws_iam_role.database_access.arn} --role-session-name DatabaseAccess"
    get_connection_info = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.database_connection.name} --query SecretString --output text"
  }
}