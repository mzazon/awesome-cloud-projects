# Network Infrastructure Outputs
output "network_name" {
  description = "Name of the VPC network created for migration infrastructure"
  value       = google_compute_network.migration_network.name
}

output "network_id" {
  description = "ID of the VPC network created for migration infrastructure"
  value       = google_compute_network.migration_network.id
}

output "subnet_name" {
  description = "Name of the subnet created for migration infrastructure"
  value       = google_compute_subnetwork.migration_subnet.name
}

output "subnet_ip_range" {
  description = "IP range of the migration subnet"
  value       = google_compute_subnetwork.migration_subnet.ip_cidr_range
}

# Migration Worker Infrastructure Outputs
output "instance_template_name" {
  description = "Name of the instance template for migration workers"
  value       = google_compute_instance_template.migration_workers.name
}

output "instance_template_id" {
  description = "ID of the instance template for migration workers"
  value       = google_compute_instance_template.migration_workers.id
}

output "instance_group_manager_name" {
  description = "Name of the managed instance group for migration workers"
  value       = google_compute_region_instance_group_manager.migration_workers.name
}

output "instance_group_manager_id" {
  description = "ID of the managed instance group for migration workers"
  value       = google_compute_region_instance_group_manager.migration_workers.id
}

output "autoscaler_name" {
  description = "Name of the autoscaler for migration workers"
  value       = google_compute_region_autoscaler.migration_workers.name
}

# Dynamic Workload Scheduler Outputs
output "future_reservation_name" {
  description = "Name of the future reservation for migration capacity"
  value       = google_compute_future_reservation.migration_capacity.name
}

output "future_reservation_id" {
  description = "ID of the future reservation for migration capacity"
  value       = google_compute_future_reservation.migration_capacity.id
}

output "reservation_capacity" {
  description = "Number of instances reserved for migration workloads"
  value       = var.reservation_capacity
}

# Cloud SQL Outputs
output "cloudsql_instance_name" {
  description = "Name of the Cloud SQL MySQL instance"
  value       = google_sql_database_instance.mysql_target.name
}

output "cloudsql_connection_name" {
  description = "Connection name for the Cloud SQL MySQL instance"
  value       = google_sql_database_instance.mysql_target.connection_name
  sensitive   = true
}

output "cloudsql_private_ip" {
  description = "Private IP address of the Cloud SQL MySQL instance"
  value       = google_sql_database_instance.mysql_target.private_ip_address
  sensitive   = true
}

output "cloudsql_database_name" {
  description = "Name of the sample database created in Cloud SQL"
  value       = google_sql_database.sample_db.name
}

# AlloyDB Outputs
output "alloydb_cluster_name" {
  description = "Name of the AlloyDB cluster"
  value       = google_alloydb_cluster.postgres_target.name
}

output "alloydb_cluster_id" {
  description = "ID of the AlloyDB cluster"
  value       = google_alloydb_cluster.postgres_target.cluster_id
}

output "alloydb_primary_instance_name" {
  description = "Name of the AlloyDB primary instance"
  value       = google_alloydb_instance.postgres_primary.name
}

output "alloydb_primary_instance_id" {
  description = "ID of the AlloyDB primary instance"
  value       = google_alloydb_instance.postgres_primary.instance_id
}

# Database Migration Service Outputs
output "source_mysql_connection_profile_id" {
  description = "ID of the source MySQL connection profile"
  value       = google_database_migration_service_connection_profile.source_mysql.connection_profile_id
}

output "dest_cloudsql_connection_profile_id" {
  description = "ID of the destination Cloud SQL connection profile"
  value       = google_database_migration_service_connection_profile.dest_cloudsql.connection_profile_id
}

output "source_postgres_connection_profile_id" {
  description = "ID of the source PostgreSQL connection profile"
  value       = google_database_migration_service_connection_profile.source_postgres.connection_profile_id
}

output "dest_alloydb_connection_profile_id" {
  description = "ID of the destination AlloyDB connection profile"
  value       = google_database_migration_service_connection_profile.dest_alloydb.connection_profile_id
}

# Cloud Function Outputs
output "migration_orchestrator_function_name" {
  description = "Name of the migration orchestrator Cloud Function"
  value       = google_cloudfunctions2_function.migration_orchestrator.name
}

output "migration_orchestrator_function_url" {
  description = "HTTP trigger URL for the migration orchestrator Cloud Function"
  value       = google_cloudfunctions2_function.migration_orchestrator.service_config[0].uri
  sensitive   = true
}

output "migration_orchestrator_service_account" {
  description = "Email of the service account used by the migration orchestrator"
  value       = google_service_account.migration_orchestrator.email
}

# Storage Outputs
output "migration_bucket_name" {
  description = "Name of the Cloud Storage bucket for migration artifacts"
  value       = google_storage_bucket.migration_bucket.name
}

output "migration_bucket_url" {
  description = "URL of the Cloud Storage bucket for migration artifacts"
  value       = google_storage_bucket.migration_bucket.url
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard for migration metrics"
  value       = google_monitoring_dashboard.migration_dashboard.id
}

output "alert_policy_name" {
  description = "Name of the alert policy for migration worker failures"
  value       = google_monitoring_alert_policy.migration_worker_failure.name
}

# Networking and Security Outputs
output "private_ip_range" {
  description = "Private IP range allocated for database services"
  value       = google_compute_global_address.private_ip_address.address
}

output "vpc_peering_connection" {
  description = "VPC peering connection for private services"
  value       = google_service_networking_connection.private_vpc_connection.network
}

# Configuration Summary Outputs
output "deployment_summary" {
  description = "Summary of the deployed migration infrastructure"
  value = {
    project_id                = var.project_id
    region                   = var.region
    zone                     = var.zone
    network_name             = google_compute_network.migration_network.name
    cloudsql_instance        = google_sql_database_instance.mysql_target.name
    alloydb_cluster          = google_alloydb_cluster.postgres_target.name
    max_worker_instances     = var.max_worker_instances
    reservation_capacity     = var.reservation_capacity
    migration_bucket         = google_storage_bucket.migration_bucket.name
    orchestrator_function    = google_cloudfunctions2_function.migration_orchestrator.name
    environment              = var.environment
    created_with_terraform   = true
  }
}

# Cost Optimization Outputs
output "cost_optimization_features" {
  description = "Cost optimization features enabled in the deployment"
  value = {
    dynamic_workload_scheduler = "Enabled with flex-start mode for up to 60% cost savings"
    autoscaling               = "Configured to scale workers from 0 to ${var.max_worker_instances} based on demand"
    future_reservations       = "Reserved ${var.reservation_capacity} instances for guaranteed capacity"
    storage_lifecycle         = "30-day lifecycle policy on migration bucket"
    regional_resources        = "High availability with regional deployment"
    private_networking        = "Private IP configuration reduces data transfer costs"
  }
}

# Security Configuration Outputs
output "security_features" {
  description = "Security features configured in the deployment"
  value = {
    private_networking        = "All database connections use private IPs"
    encryption_at_rest       = "Enabled for Cloud SQL and AlloyDB"
    encryption_in_transit    = "SSL/TLS enabled for all database connections"
    iam_service_accounts     = "Dedicated service accounts with least privilege access"
    deletion_protection      = var.enable_deletion_protection
    automated_backups        = "Configured with ${var.backup_retention_days} days retention"
    vpc_firewall_rules       = "Restrictive firewall rules for migration workers"
  }
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands to get started with the migration infrastructure"
  value = {
    scale_workers = "gcloud compute instance-groups managed resize ${google_compute_region_instance_group_manager.migration_workers.name} --size=<desired_count> --region=${var.region}"
    check_cloudsql = "gcloud sql instances describe ${google_sql_database_instance.mysql_target.name}"
    check_alloydb = "gcloud alloydb clusters describe ${google_alloydb_cluster.postgres_target.cluster_id} --region=${var.region}"
    invoke_orchestrator = "curl -X POST '${google_cloudfunctions2_function.migration_orchestrator.service_config[0].uri}' -H 'Content-Type: application/json' -d '{\"priority\": \"high\", \"size_gb\": 500}'"
    view_logs = "gcloud logging read 'resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.migration_orchestrator.name}\"' --limit=50 --format=table"
  }
  sensitive = true
}

# Resource Names for Easy Reference
output "resource_names" {
  description = "Names of all major resources for easy reference"
  value = {
    # Networking
    vpc_network                = google_compute_network.migration_network.name
    subnet                     = google_compute_subnetwork.migration_subnet.name
    
    # Compute
    instance_template          = google_compute_instance_template.migration_workers.name
    instance_group_manager     = google_compute_region_instance_group_manager.migration_workers.name
    autoscaler                 = google_compute_region_autoscaler.migration_workers.name
    future_reservation         = google_compute_future_reservation.migration_capacity.name
    
    # Databases
    cloudsql_instance          = google_sql_database_instance.mysql_target.name
    alloydb_cluster            = google_alloydb_cluster.postgres_target.name
    alloydb_primary_instance   = google_alloydb_instance.postgres_primary.name
    
    # Migration Service
    source_mysql_profile       = google_database_migration_service_connection_profile.source_mysql.connection_profile_id
    dest_cloudsql_profile      = google_database_migration_service_connection_profile.dest_cloudsql.connection_profile_id
    source_postgres_profile    = google_database_migration_service_connection_profile.source_postgres.connection_profile_id
    dest_alloydb_profile       = google_database_migration_service_connection_profile.dest_alloydb.connection_profile_id
    
    # Functions and Storage
    orchestrator_function      = google_cloudfunctions2_function.migration_orchestrator.name
    migration_bucket           = google_storage_bucket.migration_bucket.name
    
    # Monitoring
    dashboard                  = google_monitoring_dashboard.migration_dashboard.id
    alert_policy               = google_monitoring_alert_policy.migration_worker_failure.name
  }
}