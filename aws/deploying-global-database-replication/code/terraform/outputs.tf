# Outputs for Aurora Global Database Infrastructure
# This file provides all necessary connection information and resource identifiers
# for applications and additional infrastructure components

# Global Database Information
output "global_database_id" {
  description = "Global cluster identifier for Aurora Global Database"
  value       = aws_rds_global_cluster.global_database.global_cluster_identifier
}

output "global_database_arn" {
  description = "ARN of the Aurora Global Database"
  value       = aws_rds_global_cluster.global_database.arn
}

output "global_database_engine" {
  description = "Database engine used by the global database"
  value       = aws_rds_global_cluster.global_database.engine
}

output "global_database_engine_version" {
  description = "Database engine version used by the global database"
  value       = aws_rds_global_cluster.global_database.engine_version
}

# Primary Cluster Information
output "primary_cluster_id" {
  description = "Primary cluster identifier"
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Primary cluster writer endpoint"
  value       = aws_rds_cluster.primary.endpoint
  sensitive   = false
}

output "primary_cluster_reader_endpoint" {
  description = "Primary cluster reader endpoint"
  value       = aws_rds_cluster.primary.reader_endpoint
  sensitive   = false
}

output "primary_cluster_port" {
  description = "Primary cluster database port"
  value       = aws_rds_cluster.primary.port
}

output "primary_cluster_database_name" {
  description = "Primary cluster database name"
  value       = aws_rds_cluster.primary.database_name
}

output "primary_cluster_master_username" {
  description = "Primary cluster master username"
  value       = aws_rds_cluster.primary.master_username
  sensitive   = false
}

output "primary_cluster_master_user_secret_arn" {
  description = "ARN of the master user secret for primary cluster"
  value       = aws_rds_cluster.primary.master_user_secret != null ? aws_rds_cluster.primary.master_user_secret[0].secret_arn : null
}

# Primary Cluster Instance Information
output "primary_writer_instance_id" {
  description = "Primary writer instance identifier"
  value       = aws_rds_cluster_instance.primary_writer.identifier
}

output "primary_writer_instance_endpoint" {
  description = "Primary writer instance endpoint"
  value       = aws_rds_cluster_instance.primary_writer.endpoint
  sensitive   = false
}

output "primary_reader_instance_ids" {
  description = "List of primary reader instance identifiers"
  value       = aws_rds_cluster_instance.primary_reader[*].identifier
}

output "primary_reader_instance_endpoints" {
  description = "List of primary reader instance endpoints"
  value       = aws_rds_cluster_instance.primary_reader[*].endpoint
  sensitive   = false
}

# Secondary EU Cluster Information
output "secondary_eu_cluster_id" {
  description = "Secondary EU cluster identifier"
  value       = aws_rds_cluster.secondary_eu.cluster_identifier
}

output "secondary_eu_cluster_arn" {
  description = "ARN of the secondary EU Aurora cluster"
  value       = aws_rds_cluster.secondary_eu.arn
}

output "secondary_eu_cluster_endpoint" {
  description = "Secondary EU cluster writer endpoint (with write forwarding)"
  value       = aws_rds_cluster.secondary_eu.endpoint
  sensitive   = false
}

output "secondary_eu_cluster_reader_endpoint" {
  description = "Secondary EU cluster reader endpoint"
  value       = aws_rds_cluster.secondary_eu.reader_endpoint
  sensitive   = false
}

output "secondary_eu_cluster_port" {
  description = "Secondary EU cluster database port"
  value       = aws_rds_cluster.secondary_eu.port
}

output "secondary_eu_global_write_forwarding_status" {
  description = "Write forwarding status for secondary EU cluster"
  value       = aws_rds_cluster.secondary_eu.global_write_forwarding_status
}

# Secondary EU Instance Information
output "secondary_eu_writer_instance_id" {
  description = "Secondary EU writer instance identifier"
  value       = aws_rds_cluster_instance.secondary_eu_writer.identifier
}

output "secondary_eu_writer_instance_endpoint" {
  description = "Secondary EU writer instance endpoint"
  value       = aws_rds_cluster_instance.secondary_eu_writer.endpoint
  sensitive   = false
}

output "secondary_eu_reader_instance_ids" {
  description = "List of secondary EU reader instance identifiers"
  value       = aws_rds_cluster_instance.secondary_eu_reader[*].identifier
}

output "secondary_eu_reader_instance_endpoints" {
  description = "List of secondary EU reader instance endpoints"
  value       = aws_rds_cluster_instance.secondary_eu_reader[*].endpoint
  sensitive   = false
}

# Secondary Asia Cluster Information
output "secondary_asia_cluster_id" {
  description = "Secondary Asia cluster identifier"
  value       = aws_rds_cluster.secondary_asia.cluster_identifier
}

output "secondary_asia_cluster_arn" {
  description = "ARN of the secondary Asia Aurora cluster"
  value       = aws_rds_cluster.secondary_asia.arn
}

output "secondary_asia_cluster_endpoint" {
  description = "Secondary Asia cluster writer endpoint (with write forwarding)"
  value       = aws_rds_cluster.secondary_asia.endpoint
  sensitive   = false
}

output "secondary_asia_cluster_reader_endpoint" {
  description = "Secondary Asia cluster reader endpoint"
  value       = aws_rds_cluster.secondary_asia.reader_endpoint
  sensitive   = false
}

output "secondary_asia_cluster_port" {
  description = "Secondary Asia cluster database port"
  value       = aws_rds_cluster.secondary_asia.port
}

output "secondary_asia_global_write_forwarding_status" {
  description = "Write forwarding status for secondary Asia cluster"
  value       = aws_rds_cluster.secondary_asia.global_write_forwarding_status
}

# Secondary Asia Instance Information
output "secondary_asia_writer_instance_id" {
  description = "Secondary Asia writer instance identifier"
  value       = aws_rds_cluster_instance.secondary_asia_writer.identifier
}

output "secondary_asia_writer_instance_endpoint" {
  description = "Secondary Asia writer instance endpoint"
  value       = aws_rds_cluster_instance.secondary_asia_writer.endpoint
  sensitive   = false
}

output "secondary_asia_reader_instance_ids" {
  description = "List of secondary Asia reader instance identifiers"
  value       = aws_rds_cluster_instance.secondary_asia_reader[*].identifier
}

output "secondary_asia_reader_instance_endpoints" {
  description = "List of secondary Asia reader instance endpoints"
  value       = aws_rds_cluster_instance.secondary_asia_reader[*].endpoint
  sensitive   = false
}

# Connection Information for Applications
output "connection_information" {
  description = "Connection information for applications in different regions"
  value = {
    primary_region = {
      region          = var.primary_region
      writer_endpoint = aws_rds_cluster.primary.endpoint
      reader_endpoint = aws_rds_cluster.primary.reader_endpoint
      port           = aws_rds_cluster.primary.port
      database_name  = aws_rds_cluster.primary.database_name
      username       = aws_rds_cluster.primary.master_username
      supports_writes = true
      supports_reads  = true
    }
    
    european_region = {
      region          = var.secondary_region_eu
      writer_endpoint = aws_rds_cluster.secondary_eu.endpoint
      reader_endpoint = aws_rds_cluster.secondary_eu.reader_endpoint
      port           = aws_rds_cluster.secondary_eu.port
      database_name  = aws_rds_cluster.primary.database_name
      username       = aws_rds_cluster.primary.master_username
      supports_writes = var.enable_global_write_forwarding
      supports_reads  = true
      write_forwarding_enabled = var.enable_global_write_forwarding
    }
    
    asian_region = {
      region          = var.secondary_region_asia
      writer_endpoint = aws_rds_cluster.secondary_asia.endpoint
      reader_endpoint = aws_rds_cluster.secondary_asia.reader_endpoint
      port           = aws_rds_cluster.secondary_asia.port
      database_name  = aws_rds_cluster.primary.database_name
      username       = aws_rds_cluster.primary.master_username
      supports_writes = var.enable_global_write_forwarding
      supports_reads  = true
      write_forwarding_enabled = var.enable_global_write_forwarding
    }
  }
  sensitive = false
}

# Monitoring Information
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard for global database monitoring"
  value = var.create_cloudwatch_dashboard ? "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${local.dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.create_cloudwatch_dashboard ? local.dashboard_name : null
}

# Performance Insights Information
output "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled for the clusters"
  value       = var.enable_performance_insights
}

# Security Information
output "storage_encrypted" {
  description = "Whether storage encryption is enabled"
  value       = var.storage_encrypted
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled"
  value       = var.deletion_protection
}

# Auto Scaling Information
output "auto_scaling_enabled" {
  description = "Whether auto scaling is enabled"
  value       = var.enable_auto_scaling
}

output "auto_scaling_configuration" {
  description = "Auto scaling configuration details"
  value = var.enable_auto_scaling ? {
    min_capacity = var.auto_scaling_min_capacity
    max_capacity = var.auto_scaling_max_capacity
    target_cpu   = var.auto_scaling_target_cpu
  } : null
}

# Resource Tags
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Database Connection Examples
output "connection_examples" {
  description = "Example connection strings for different programming languages"
  value = {
    mysql_cli_primary = "mysql -h ${aws_rds_cluster.primary.endpoint} -P ${aws_rds_cluster.primary.port} -u ${aws_rds_cluster.primary.master_username} -p${var.master_password != null ? "[PROVIDED_PASSWORD]" : "[MANAGED_PASSWORD]"} ${aws_rds_cluster.primary.database_name}"
    
    mysql_cli_eu = "mysql -h ${aws_rds_cluster.secondary_eu.endpoint} -P ${aws_rds_cluster.secondary_eu.port} -u ${aws_rds_cluster.primary.master_username} -p${var.master_password != null ? "[PROVIDED_PASSWORD]" : "[MANAGED_PASSWORD]"} ${aws_rds_cluster.primary.database_name}"
    
    mysql_cli_asia = "mysql -h ${aws_rds_cluster.secondary_asia.endpoint} -P ${aws_rds_cluster.secondary_asia.port} -u ${aws_rds_cluster.primary.master_username} -p${var.master_password != null ? "[PROVIDED_PASSWORD]" : "[MANAGED_PASSWORD]"} ${aws_rds_cluster.primary.database_name}"
    
    python_connection = {
      primary = "mysql://username:password@${aws_rds_cluster.primary.endpoint}:${aws_rds_cluster.primary.port}/${aws_rds_cluster.primary.database_name}"
      eu      = "mysql://username:password@${aws_rds_cluster.secondary_eu.endpoint}:${aws_rds_cluster.secondary_eu.port}/${aws_rds_cluster.primary.database_name}"
      asia    = "mysql://username:password@${aws_rds_cluster.secondary_asia.endpoint}:${aws_rds_cluster.secondary_asia.port}/${aws_rds_cluster.primary.database_name}"
    }
  }
  sensitive = false
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Notes about cost optimization for the global database"
  value = {
    instance_class = "Current instance class: ${var.db_instance_class}. Consider smaller instances for development/testing."
    reader_instances = "Reader instances: ${var.create_reader_instances ? var.reader_instance_count : 0} per region. Adjust based on read workload."
    backup_retention = "Backup retention: ${var.backup_retention_period} days. Longer retention increases storage costs."
    performance_insights = "Performance Insights retention: ${var.performance_insights_retention_period} days. Consider 7 days for cost optimization."
    auto_scaling = var.enable_auto_scaling ? "Auto scaling enabled. Monitor scaling events to optimize capacity." : "Auto scaling disabled. Consider enabling for variable workloads."
  }
}

# Regional Availability Information
output "regional_availability" {
  description = "Regional availability and configuration"
  value = {
    primary_region = {
      region = var.primary_region
      availability_zones = data.aws_availability_zones.primary.names
      cluster_type = "primary"
      write_capability = "native"
    }
    
    secondary_regions = {
      europe = {
        region = var.secondary_region_eu
        availability_zones = data.aws_availability_zones.secondary_eu.names
        cluster_type = "secondary"
        write_capability = var.enable_global_write_forwarding ? "write_forwarding" : "read_only"
      }
      
      asia = {
        region = var.secondary_region_asia
        availability_zones = data.aws_availability_zones.secondary_asia.names
        cluster_type = "secondary"
        write_capability = var.enable_global_write_forwarding ? "write_forwarding" : "read_only"
      }
    }
  }
}

# Disaster Recovery Information
output "disaster_recovery_configuration" {
  description = "Disaster recovery configuration and capabilities"
  value = {
    global_database_id = aws_rds_global_cluster.global_database.global_cluster_identifier
    primary_region = var.primary_region
    secondary_regions = [var.secondary_region_eu, var.secondary_region_asia]
    failover_capability = "automated_failover_to_secondary_regions"
    recovery_time_objective = "minutes"
    recovery_point_objective = "sub_second_replication"
    backup_retention_days = var.backup_retention_period
    deletion_protection = var.deletion_protection
  }
}