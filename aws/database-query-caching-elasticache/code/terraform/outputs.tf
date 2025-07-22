# Output Values for Database Query Caching Infrastructure
# These outputs provide essential information for connecting to and managing the deployed resources

# ElastiCache Redis Outputs
output "redis_cluster_id" {
  description = "The ID of the ElastiCache Redis replication group"
  value       = aws_elasticache_replication_group.redis.replication_group_id
}

output "redis_primary_endpoint" {
  description = "The primary endpoint address of the Redis cluster"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "The reader endpoint address of the Redis cluster"
  value       = aws_elasticache_replication_group.redis.reader_endpoint_address
}

output "redis_port" {
  description = "The port number on which Redis accepts connections"
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_engine_version" {
  description = "The version of Redis running on the cluster"
  value       = aws_elasticache_replication_group.redis.engine_version
}

output "redis_node_type" {
  description = "The instance type of the Redis nodes"
  value       = aws_elasticache_replication_group.redis.node_type
}

output "redis_security_group_id" {
  description = "The security group ID for the Redis cluster"
  value       = aws_security_group.redis.id
}

# RDS Database Outputs
output "rds_instance_id" {
  description = "The RDS instance identifier"
  value       = var.create_rds_instance ? aws_db_instance.mysql[0].identifier : null
}

output "rds_endpoint" {
  description = "The RDS instance endpoint"
  value       = var.create_rds_instance ? aws_db_instance.mysql[0].endpoint : null
}

output "rds_address" {
  description = "The RDS instance address"
  value       = var.create_rds_instance ? aws_db_instance.mysql[0].address : null
}

output "rds_port" {
  description = "The RDS instance port"
  value       = var.create_rds_instance ? aws_db_instance.mysql[0].port : null
}

output "rds_database_name" {
  description = "The name of the default database"
  value       = var.create_rds_instance ? aws_db_instance.mysql[0].db_name : null
}

output "rds_username" {
  description = "The master username for the RDS instance"
  value       = var.create_rds_instance ? aws_db_instance.mysql[0].username : null
}

output "rds_security_group_id" {
  description = "The security group ID for the RDS instance"
  value       = var.create_rds_instance ? aws_security_group.rds[0].id : null
}

# EC2 Instance Outputs
output "ec2_instance_id" {
  description = "The ID of the EC2 test instance"
  value       = var.create_ec2_instance ? aws_instance.test[0].id : null
}

output "ec2_public_ip" {
  description = "The public IP address of the EC2 test instance"
  value       = var.create_ec2_instance ? aws_instance.test[0].public_ip : null
}

output "ec2_private_ip" {
  description = "The private IP address of the EC2 test instance"
  value       = var.create_ec2_instance ? aws_instance.test[0].private_ip : null
}

output "ec2_public_dns" {
  description = "The public DNS name of the EC2 test instance"
  value       = var.create_ec2_instance ? aws_instance.test[0].public_dns : null
}

output "ec2_security_group_id" {
  description = "The security group ID for the EC2 instance"
  value       = var.create_ec2_instance ? aws_security_group.ec2[0].id : null
}

# Network Configuration Outputs
output "vpc_id" {
  description = "The ID of the VPC where resources are deployed"
  value       = data.aws_vpc.selected.id
}

output "subnet_ids" {
  description = "The list of subnet IDs where resources are deployed"
  value       = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected.ids
}

output "cache_subnet_group_name" {
  description = "The name of the ElastiCache subnet group"
  value       = aws_elasticache_subnet_group.redis.name
}

output "db_subnet_group_name" {
  description = "The name of the RDS subnet group"
  value       = var.create_rds_instance ? aws_db_subnet_group.rds[0].name : null
}

# Monitoring and Management Outputs
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for monitoring cache performance"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cache_monitoring.dashboard_name}"
}

output "redis_log_group_name" {
  description = "The CloudWatch log group name for Redis slow logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.redis_slow[0].name : null
}

# Configuration Outputs
output "parameter_group_name" {
  description = "The name of the ElastiCache parameter group"
  value       = aws_elasticache_parameter_group.redis.name
}

output "redis_configuration" {
  description = "Key Redis configuration settings"
  value = {
    maxmemory_policy         = "allkeys-lru"
    automatic_failover       = var.redis_automatic_failover_enabled
    multi_az                = var.redis_multi_az_enabled
    encryption_at_rest      = var.redis_at_rest_encryption_enabled
    encryption_in_transit   = var.redis_transit_encryption_enabled
    num_cache_clusters      = var.redis_num_cache_clusters
  }
}

# Connection Information for Applications
output "redis_connection_string" {
  description = "Redis connection string for applications (without auth)"
  value       = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}:${aws_elasticache_replication_group.redis.port}"
}

output "mysql_connection_string" {
  description = "MySQL connection string format (password not included)"
  value       = var.create_rds_instance ? "mysql://${aws_db_instance.mysql[0].username}:<password>@${aws_db_instance.mysql[0].endpoint}/${aws_db_instance.mysql[0].db_name}" : null
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Cost Estimation Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources (USD)"
  value = {
    redis_cluster = "~$15-25 (cache.t3.micro nodes)"
    rds_instance  = var.create_rds_instance ? "~$15-20 (db.t3.micro)" : "$0 (not created)"
    ec2_instance  = var.create_ec2_instance ? "~$8-10 (t3.micro)" : "$0 (not created)"
    data_transfer = "~$1-5 (depending on usage)"
    cloudwatch    = "~$1-3 (logs and metrics)"
    total_estimate = "~$40-65 per month"
  }
}

# Testing Commands
output "testing_commands" {
  description = "Useful commands for testing the cache infrastructure"
  value = {
    test_redis_connectivity = "redis-cli -h ${aws_elasticache_replication_group.redis.primary_endpoint_address} ping"
    redis_set_example      = "redis-cli -h ${aws_elasticache_replication_group.redis.primary_endpoint_address} set test:key 'test_value' EX 300"
    redis_get_example      = "redis-cli -h ${aws_elasticache_replication_group.redis.primary_endpoint_address} get test:key"
    redis_info_stats       = "redis-cli -h ${aws_elasticache_replication_group.redis.primary_endpoint_address} info stats"
    mysql_connection_test  = var.create_rds_instance ? "mysql -h ${aws_db_instance.mysql[0].address} -u ${aws_db_instance.mysql[0].username} -p" : "N/A (RDS not created)"
  }
}

# Security Information
output "security_considerations" {
  description = "Important security information for the deployed infrastructure"
  value = {
    redis_access     = "Redis is accessible only from within the VPC (${data.aws_vpc.selected.cidr_block})"
    rds_access       = var.create_rds_instance ? "RDS is accessible only from within the VPC" : "N/A"
    ec2_ssh_access   = var.create_ec2_instance ? "EC2 SSH access is open to 0.0.0.0/0 - consider restricting" : "N/A"
    encryption       = "Redis encryption at rest: ${var.redis_at_rest_encryption_enabled}, in transit: ${var.redis_transit_encryption_enabled}"
    recommendations  = [
      "Consider enabling Redis AUTH for additional security",
      "Use VPC endpoints for enhanced security",
      "Regularly rotate RDS passwords",
      "Enable VPC Flow Logs for network monitoring",
      "Consider using AWS Secrets Manager for credential management"
    ]
  }
}

# Resource ARNs for IAM policies and monitoring
output "resource_arns" {
  description = "ARNs of created resources for IAM policies and monitoring"
  value = {
    redis_cluster = aws_elasticache_replication_group.redis.arn
    rds_instance  = var.create_rds_instance ? aws_db_instance.mysql[0].arn : null
    ec2_instance  = var.create_ec2_instance ? aws_instance.test[0].arn : null
    log_group     = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.redis_slow[0].arn : null
  }
}

# Backup and Recovery Information
output "backup_information" {
  description = "Backup and recovery configuration"
  value = {
    redis_snapshots = {
      retention_limit   = aws_elasticache_replication_group.redis.snapshot_retention_limit
      window           = aws_elasticache_replication_group.redis.snapshot_window
      final_snapshot   = aws_elasticache_replication_group.redis.final_snapshot_identifier
    }
    rds_backups = var.create_rds_instance ? {
      retention_period = aws_db_instance.mysql[0].backup_retention_period
      window          = aws_db_instance.mysql[0].backup_window
    } : null
  }
}