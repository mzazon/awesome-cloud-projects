# Outputs for zero-downtime database migration infrastructure

# ============================================================================
# CLOUD SQL INSTANCE OUTPUTS
# ============================================================================

output "cloudsql_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.name
}

output "cloudsql_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.connection_name
}

output "cloudsql_instance_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.private_ip_address
}

output "cloudsql_instance_public_ip" {
  description = "Public IP address of the Cloud SQL instance (if enabled)"
  value       = google_sql_database_instance.target_mysql.public_ip_address
}

output "cloudsql_instance_self_link" {
  description = "Self-link URL of the Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.self_link
}

output "cloudsql_instance_server_ca_cert" {
  description = "Server CA certificate for secure connections"
  value       = google_sql_database_instance.target_mysql.server_ca_cert
  sensitive   = true
}

output "cloudsql_replica_name" {
  description = "Name of the Cloud SQL read replica"
  value       = google_sql_database_instance.read_replica.name
}

output "cloudsql_replica_connection_name" {
  description = "Connection name for the Cloud SQL read replica"
  value       = google_sql_database_instance.read_replica.connection_name
}

# ============================================================================
# DATABASE AND USER OUTPUTS
# ============================================================================

output "database_name" {
  description = "Name of the production database"
  value       = google_sql_database.production_db.name
}

output "migration_user" {
  description = "Username for database migration operations"
  value       = google_sql_user.migration_user.name
}

output "app_user" {
  description = "Username for application connections"
  value       = google_sql_user.app_user.name
}

output "app_user_password" {
  description = "Password for application user (use with caution)"
  value       = google_sql_user.app_user.password
  sensitive   = true
}

# ============================================================================
# DATABASE MIGRATION SERVICE OUTPUTS
# ============================================================================

output "migration_job_id" {
  description = "ID of the database migration job"
  value       = google_database_migration_service_migration_job.mysql_migration.migration_job_id
}

output "migration_job_name" {
  description = "Full resource name of the migration job"
  value       = google_database_migration_service_migration_job.mysql_migration.name
}

output "migration_job_state" {
  description = "Current state of the migration job"
  value       = google_database_migration_service_migration_job.mysql_migration.state
}

output "connection_profile_id" {
  description = "ID of the source connection profile"
  value       = google_database_migration_service_connection_profile.source_mysql.connection_profile_id
}

output "connection_profile_name" {
  description = "Full resource name of the source connection profile"
  value       = google_database_migration_service_connection_profile.source_mysql.name
}

# ============================================================================
# NETWORKING OUTPUTS
# ============================================================================

output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "vpc_self_link" {
  description = "Self-link URL of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "Name of the subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "subnet_self_link" {
  description = "Self-link URL of the subnet"
  value       = google_compute_subnetwork.subnet.self_link
}

output "private_ip_range_name" {
  description = "Name of the private IP range allocation"
  value       = google_compute_global_address.private_ip_range.name
}

output "private_ip_range_address" {
  description = "Allocated private IP range"
  value       = google_compute_global_address.private_ip_range.address
}

# ============================================================================
# MONITORING AND ALERTING OUTPUTS
# ============================================================================

output "notification_channel_id" {
  description = "ID of the monitoring notification channel (if created)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email[0].id : null
}

output "cpu_alert_policy_id" {
  description = "ID of the CPU utilization alert policy (if created)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.sql_cpu_alert[0].id : null
}

output "memory_alert_policy_id" {
  description = "ID of the memory utilization alert policy (if created)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.sql_memory_alert[0].id : null
}

output "migration_failure_alert_policy_id" {
  description = "ID of the migration failure alert policy (if created)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.migration_failure_alert[0].id : null
}

output "dashboard_id" {
  description = "ID of the monitoring dashboard (if created)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.migration_dashboard[0].id : null
}

output "log_metric_name" {
  description = "Name of the log-based metric for migration errors (if created)"
  value       = var.enable_logging ? google_logging_metric.migration_errors[0].name : null
}

# ============================================================================
# PROJECT AND ENVIRONMENT OUTPUTS
# ============================================================================

output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone for zonal resources"
  value       = var.zone
}

output "environment" {
  description = "Environment name (dev, staging, prod)"
  value       = var.environment
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# ============================================================================
# CONNECTION INFORMATION FOR APPLICATIONS
# ============================================================================

output "connection_instructions" {
  description = "Instructions for connecting applications to the migrated database"
  value = <<-EOT
    # Cloud SQL Connection Information:
    
    ## Private IP Connection (Recommended):
    Host: ${google_sql_database_instance.target_mysql.private_ip_address}
    Port: 3306
    Database: ${google_sql_database.production_db.name}
    Username: ${google_sql_user.app_user.name}
    Password: [Check Terraform output 'app_user_password']
    
    ## Connection String Examples:
    
    ### MySQL CLI:
    mysql -h ${google_sql_database_instance.target_mysql.private_ip_address} -u ${google_sql_user.app_user.name} -p ${google_sql_database.production_db.name}
    
    ### Application Connection (Java/JDBC):
    jdbc:mysql://${google_sql_database_instance.target_mysql.private_ip_address}:3306/${google_sql_database.production_db.name}?useSSL=true&requireSSL=true
    
    ### Application Connection (Python):
    import mysql.connector
    connection = mysql.connector.connect(
        host='${google_sql_database_instance.target_mysql.private_ip_address}',
        port=3306,
        database='${google_sql_database.production_db.name}',
        user='${google_sql_user.app_user.name}',
        password='[password]',
        ssl_verify_cert=True
    )
    
    ## Cloud SQL Proxy Connection:
    cloud-sql-proxy ${google_sql_database_instance.target_mysql.connection_name}
    
    ## Read Replica Connection:
    Host: ${google_sql_database_instance.read_replica.private_ip_address}
    Connection Name: ${google_sql_database_instance.read_replica.connection_name}
  EOT
}

# ============================================================================
# MIGRATION OPERATION OUTPUTS
# ============================================================================

output "migration_commands" {
  description = "Commands for managing the database migration"
  value = <<-EOT
    # Database Migration Management Commands:
    
    ## Check Migration Status:
    gcloud datamigration migration-jobs describe ${local.migration_job_id} --region=${var.region}
    
    ## Start Migration (if not auto-started):
    gcloud datamigration migration-jobs start ${local.migration_job_id} --region=${var.region}
    
    ## Promote Migration (Cutover):
    gcloud datamigration migration-jobs promote ${local.migration_job_id} --region=${var.region}
    
    ## Verify Migration:
    gcloud datamigration migration-jobs verify ${local.migration_job_id} --region=${var.region}
    
    ## Monitor Migration Logs:
    gcloud logging read "resource.type=\"datamigration.googleapis.com/MigrationJob\" AND resource.labels.migration_job_id=\"${local.migration_job_id}\"" --limit=50
    
    ## Connect to Cloud SQL Instance:
    gcloud sql connect ${google_sql_database_instance.target_mysql.name} --user=${google_sql_user.app_user.name} --database=${google_sql_database.production_db.name}
    
    ## Check Cloud SQL Status:
    gcloud sql instances describe ${google_sql_database_instance.target_mysql.name}
  EOT
}

# ============================================================================
# COST ESTIMATION OUTPUT
# ============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for the infrastructure"
  value = <<-EOT
    # Estimated Monthly Costs (USD, subject to change):
    
    ## Cloud SQL Instance (${var.database_tier}):
    - Instance: ~$${var.database_tier == "db-n1-standard-2" ? "200-300" : "varies"}
    - Storage (${var.disk_size}GB SSD): ~$${var.disk_size * 0.17}
    - Backup Storage: ~$${var.disk_size * 0.08}
    
    ## Read Replica (db-n1-standard-1):
    - Instance: ~$100-150
    - Storage: ~$${var.disk_size * 0.5 * 0.17}
    
    ## Database Migration Service:
    - Migration Job: ~$0.10 per GB migrated
    - Connection Profile: No additional charge
    
    ## Networking:
    - VPC: No charge
    - Private Service Connect: No charge
    - Egress: Varies by usage
    
    ## Monitoring & Logging:
    - Cloud Monitoring: First 150MB free, then ~$0.2580/MB
    - Cloud Logging: First 50GB free, then ~$0.50/GB
    
    Total Estimated Range: $300-500/month
    
    Note: Actual costs depend on usage patterns, data transfer, and region.
    Use the Google Cloud Pricing Calculator for precise estimates.
  EOT
}