# ==============================================================================
# OUTPUTS - Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner
# ==============================================================================
# This file defines all outputs from the disaster recovery infrastructure
# deployment. These outputs provide essential information for connecting to
# databases, monitoring resources, and managing disaster recovery operations.
# ==============================================================================

# ==============================================================================
# PROJECT AND DEPLOYMENT INFORMATION
# ==============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources are deployed"
  value       = var.project_id
}

output "deployment_id" {
  description = "Unique deployment identifier for resource tracking"
  value       = random_id.suffix.hex
}

output "primary_region" {
  description = "Primary region for database deployments"
  value       = var.primary_region
}

output "secondary_region" {
  description = "Secondary region for disaster recovery"
  value       = var.secondary_region
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# ==============================================================================
# NETWORKING OUTPUTS
# ==============================================================================

output "vpc_network_id" {
  description = "ID of the VPC network created for AlloyDB connectivity"
  value       = google_compute_network.alloydb_network.id
}

output "vpc_network_name" {
  description = "Name of the VPC network created for AlloyDB connectivity"
  value       = google_compute_network.alloydb_network.name
}

output "primary_subnet_id" {
  description = "ID of the primary region subnet"
  value       = google_compute_subnetwork.primary_subnet.id
}

output "secondary_subnet_id" {
  description = "ID of the secondary region subnet"
  value       = google_compute_subnetwork.secondary_subnet.id
}

output "primary_subnet_cidr" {
  description = "CIDR block of the primary region subnet"
  value       = google_compute_subnetwork.primary_subnet.ip_cidr_range
}

output "secondary_subnet_cidr" {
  description = "CIDR block of the secondary region subnet"
  value       = google_compute_subnetwork.secondary_subnet.ip_cidr_range
}

output "service_networking_connection_id" {
  description = "ID of the service networking connection for AlloyDB"
  value       = google_service_networking_connection.alloydb_connection.network
}

# ==============================================================================
# ALLOYDB CLUSTER OUTPUTS
# ==============================================================================

output "alloydb_primary_cluster_id" {
  description = "ID of the AlloyDB primary cluster"
  value       = google_alloydb_cluster.primary.cluster_id
}

output "alloydb_primary_cluster_name" {
  description = "Fully qualified name of the AlloyDB primary cluster"
  value       = google_alloydb_cluster.primary.name
}

output "alloydb_secondary_cluster_id" {
  description = "ID of the AlloyDB secondary cluster"
  value       = google_alloydb_cluster.secondary.cluster_id
}

output "alloydb_secondary_cluster_name" {
  description = "Fully qualified name of the AlloyDB secondary cluster"
  value       = google_alloydb_cluster.secondary.name
}

output "alloydb_primary_instance_id" {
  description = "ID of the AlloyDB primary instance"
  value       = google_alloydb_instance.primary.instance_id
}

output "alloydb_primary_instance_name" {
  description = "Fully qualified name of the AlloyDB primary instance"
  value       = google_alloydb_instance.primary.name
}

output "alloydb_secondary_read_pool_id" {
  description = "ID of the AlloyDB secondary read pool instance"
  value       = google_alloydb_instance.secondary_read_pool.instance_id
}

output "alloydb_secondary_read_pool_name" {
  description = "Fully qualified name of the AlloyDB secondary read pool instance"
  value       = google_alloydb_instance.secondary_read_pool.name
}

output "alloydb_primary_ip_address" {
  description = "Private IP address of the AlloyDB primary instance"
  value       = google_alloydb_instance.primary.ip_address
  sensitive   = true
}

output "alloydb_database_admin_user" {
  description = "Administrative username for AlloyDB databases"
  value       = var.db_admin_user
}

# ==============================================================================
# CLOUD SPANNER OUTPUTS
# ==============================================================================

output "spanner_instance_id" {
  description = "ID of the Cloud Spanner instance"
  value       = google_spanner_instance.multi_regional.name
}

output "spanner_instance_display_name" {
  description = "Display name of the Cloud Spanner instance"
  value       = google_spanner_instance.multi_regional.display_name
}

output "spanner_instance_config" {
  description = "Configuration of the Cloud Spanner instance"
  value       = google_spanner_instance.multi_regional.config
}

output "spanner_processing_units" {
  description = "Number of processing units allocated to the Cloud Spanner instance"
  value       = google_spanner_instance.multi_regional.processing_units
}

output "spanner_database_name" {
  description = "Name of the Cloud Spanner critical data database"
  value       = google_spanner_database.critical_data.name
}

output "spanner_database_state" {
  description = "Current state of the Cloud Spanner database"
  value       = google_spanner_database.critical_data.state
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "primary_backup_bucket_name" {
  description = "Name of the primary region backup storage bucket"
  value       = google_storage_bucket.primary_backup.name
}

output "secondary_backup_bucket_name" {
  description = "Name of the secondary region backup storage bucket"
  value       = google_storage_bucket.secondary_backup.name
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Functions source code storage bucket"
  value       = google_storage_bucket.function_source.name
}

output "primary_backup_bucket_url" {
  description = "URL of the primary region backup storage bucket"
  value       = google_storage_bucket.primary_backup.url
}

output "secondary_backup_bucket_url" {
  description = "URL of the secondary region backup storage bucket"
  value       = google_storage_bucket.secondary_backup.url
}

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "function_service_account_email" {
  description = "Email address of the Cloud Functions service account"
  value       = google_service_account.function_sa.email
}

output "scheduler_service_account_email" {
  description = "Email address of the Cloud Scheduler service account"
  value       = google_service_account.scheduler_sa.email
}

output "pubsub_service_account_email" {
  description = "Email address of the Pub/Sub service account"
  value       = google_service_account.pubsub_sa.email
}

output "function_service_account_id" {
  description = "Unique ID of the Cloud Functions service account"
  value       = google_service_account.function_sa.unique_id
}

# ==============================================================================
# PUB/SUB MESSAGING OUTPUTS
# ==============================================================================

output "database_sync_topic_name" {
  description = "Name of the Pub/Sub topic for database synchronization events"
  value       = google_pubsub_topic.database_sync_events.name
}

output "database_sync_topic_id" {
  description = "ID of the Pub/Sub topic for database synchronization events"
  value       = google_pubsub_topic.database_sync_events.id
}

output "database_sync_subscription_name" {
  description = "Name of the Pub/Sub subscription for monitoring sync operations"
  value       = google_pubsub_subscription.database_sync_monitoring.name
}

output "database_sync_subscription_id" {
  description = "ID of the Pub/Sub subscription for monitoring sync operations"
  value       = google_pubsub_subscription.database_sync_monitoring.id
}

output "dead_letter_topic_name" {
  description = "Name of the Pub/Sub dead letter topic for failed messages"
  value       = google_pubsub_topic.dead_letter.name
}

# ==============================================================================
# CONNECTION INFORMATION
# ==============================================================================

output "alloydb_connection_info" {
  description = "Connection information for AlloyDB primary instance"
  value = {
    host     = google_alloydb_instance.primary.ip_address
    port     = "5432"
    user     = var.db_admin_user
    database = "postgres"
    region   = var.primary_region
  }
  sensitive = true
}

output "spanner_connection_info" {
  description = "Connection information for Cloud Spanner instance"
  value = {
    instance_id = google_spanner_instance.multi_regional.name
    database_id = google_spanner_database.critical_data.name
    project_id  = var.project_id
    config      = google_spanner_instance.multi_regional.config
  }
}

# ==============================================================================
# DISASTER RECOVERY CONFIGURATION
# ==============================================================================

output "disaster_recovery_configuration" {
  description = "Summary of disaster recovery configuration and objectives"
  value = {
    rpo_minutes                = var.rpo_minutes
    rto_minutes                = var.rto_minutes
    cross_region_backup        = var.enable_cross_region_backup
    backup_verification        = var.backup_verification_enabled
    deletion_protection        = var.enable_deletion_protection
    primary_region             = var.primary_region
    secondary_region           = var.secondary_region
    backup_retention_days      = var.backup_retention_days
  }
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

output "monitoring_configuration" {
  description = "Monitoring and alerting configuration details"
  value = {
    monitoring_enabled     = var.enable_monitoring
    dashboard_name        = var.monitoring_dashboard_name
    notification_channels = var.alert_notification_channels
    backup_schedule       = var.backup_schedule
    validation_schedule   = var.validation_schedule
    timezone             = var.scheduler_timezone
  }
}

# ==============================================================================
# RESOURCE IDENTIFIERS FOR AUTOMATION
# ==============================================================================

output "resource_ids" {
  description = "All resource IDs for automation and management scripts"
  value = {
    # AlloyDB Resources
    alloydb_primary_cluster    = google_alloydb_cluster.primary.name
    alloydb_secondary_cluster  = google_alloydb_cluster.secondary.name
    alloydb_primary_instance   = google_alloydb_instance.primary.name
    alloydb_read_pool         = google_alloydb_instance.secondary_read_pool.name
    
    # Spanner Resources
    spanner_instance          = google_spanner_instance.multi_regional.name
    spanner_database          = google_spanner_database.critical_data.name
    
    # Storage Resources
    primary_backup_bucket     = google_storage_bucket.primary_backup.name
    secondary_backup_bucket   = google_storage_bucket.secondary_backup.name
    function_source_bucket    = google_storage_bucket.function_source.name
    
    # Networking Resources
    vpc_network              = google_compute_network.alloydb_network.name
    primary_subnet           = google_compute_subnetwork.primary_subnet.name
    secondary_subnet         = google_compute_subnetwork.secondary_subnet.name
    
    # Messaging Resources
    sync_topic               = google_pubsub_topic.database_sync_events.name
    sync_subscription        = google_pubsub_subscription.database_sync_monitoring.name
    dead_letter_topic        = google_pubsub_topic.dead_letter.name
    
    # Service Accounts
    function_service_account = google_service_account.function_sa.email
    scheduler_service_account = google_service_account.scheduler_sa.email
    pubsub_service_account   = google_service_account.pubsub_sa.email
  }
}

# ==============================================================================
# DEPLOYMENT VALIDATION COMMANDS
# ==============================================================================

output "validation_commands" {
  description = "Commands to validate the disaster recovery deployment"
  value = {
    check_alloydb_primary = "gcloud alloydb clusters describe ${google_alloydb_cluster.primary.cluster_id} --region=${var.primary_region}"
    check_alloydb_secondary = "gcloud alloydb clusters describe ${google_alloydb_cluster.secondary.cluster_id} --region=${var.secondary_region}"
    check_spanner_instance = "gcloud spanner instances describe ${google_spanner_instance.multi_regional.name}"
    check_spanner_database = "gcloud spanner databases describe ${google_spanner_database.critical_data.name} --instance=${google_spanner_instance.multi_regional.name}"
    list_backup_buckets = "gsutil ls gs://${google_storage_bucket.primary_backup.name} && gsutil ls gs://${google_storage_bucket.secondary_backup.name}"
    check_pubsub_topic = "gcloud pubsub topics describe ${google_pubsub_topic.database_sync_events.name}"
  }
}

# ==============================================================================
# COST ESTIMATION
# ==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for disaster recovery infrastructure (USD)"
  value = {
    alloydb_primary_cluster = "Estimated $400-800/month (varies by usage and region)"
    alloydb_secondary_cluster = "Estimated $200-400/month (read replicas)"
    spanner_multi_regional = "Estimated $600-1200/month (based on ${var.spanner_processing_units} processing units)"
    storage_buckets = "Estimated $50-200/month (varies by data volume and access patterns)"
    cloud_functions = "Estimated $10-50/month (varies by execution frequency)"
    networking = "Estimated $20-100/month (varies by data transfer)"
    total_estimated = "Estimated $1,280-2,550/month total infrastructure cost"
    note = "Actual costs may vary based on usage patterns, data volume, and regional pricing"
  }
}

# ==============================================================================
# NEXT STEPS AND DOCUMENTATION
# ==============================================================================

output "next_steps" {
  description = "Next steps for completing the disaster recovery setup"
  value = [
    "1. Deploy Cloud Functions for backup orchestration using the function source bucket",
    "2. Create Cloud Scheduler jobs for automated backup execution",
    "3. Configure monitoring dashboards and alerting policies",
    "4. Test disaster recovery procedures with controlled failover scenarios",
    "5. Document runbooks for disaster recovery activation and validation",
    "6. Set up automated testing of backup restoration procedures",
    "7. Configure application connection strings to use AlloyDB and Spanner endpoints",
    "8. Implement data synchronization logic between AlloyDB and Spanner as needed"
  ]
}

output "important_security_notes" {
  description = "Important security considerations for the disaster recovery setup"
  value = [
    "Database passwords are marked as sensitive - use secure secret management",
    "AlloyDB instances are deployed with private IP addresses for security",
    "Storage buckets have uniform bucket-level access and public access prevention enabled",
    "Service accounts follow principle of least privilege for IAM permissions",
    "Enable VPC Service Controls for additional network-level security if needed",
    "Configure Cloud KMS for customer-managed encryption keys if required by compliance",
    "Regularly rotate service account keys and database passwords",
    "Monitor access logs and set up alerting for suspicious activities"
  ]
}