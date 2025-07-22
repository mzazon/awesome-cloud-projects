# Outputs for Database Disaster Recovery with Backup and DR Service and Cloud SQL

# Primary Cloud SQL Instance Information
output "primary_instance_name" {
  description = "Name of the primary Cloud SQL instance"
  value       = google_sql_database_instance.primary.name
}

output "primary_instance_connection_name" {
  description = "Connection name for the primary Cloud SQL instance"
  value       = google_sql_database_instance.primary.connection_name
}

output "primary_instance_ip_address" {
  description = "IP address of the primary Cloud SQL instance"
  value       = google_sql_database_instance.primary.ip_address
  sensitive   = true
}

output "primary_instance_region" {
  description = "Region of the primary Cloud SQL instance"
  value       = google_sql_database_instance.primary.region
}

output "primary_instance_self_link" {
  description = "Self link of the primary Cloud SQL instance"
  value       = google_sql_database_instance.primary.self_link
}

# Disaster Recovery Replica Information
output "dr_replica_name" {
  description = "Name of the disaster recovery replica"
  value       = google_sql_database_instance.dr_replica.name
}

output "dr_replica_connection_name" {
  description = "Connection name for the disaster recovery replica"
  value       = google_sql_database_instance.dr_replica.connection_name
}

output "dr_replica_ip_address" {
  description = "IP address of the disaster recovery replica"
  value       = google_sql_database_instance.dr_replica.ip_address
  sensitive   = true
}

output "dr_replica_region" {
  description = "Region of the disaster recovery replica"
  value       = google_sql_database_instance.dr_replica.region
}

output "dr_replica_self_link" {
  description = "Self link of the disaster recovery replica"
  value       = google_sql_database_instance.dr_replica.self_link
}

# Backup and DR Service Information
output "primary_backup_vault_id" {
  description = "ID of the primary backup vault"
  value       = google_backup_dr_backup_vault.primary_vault.backup_vault_id
}

output "primary_backup_vault_name" {
  description = "Full name of the primary backup vault"
  value       = google_backup_dr_backup_vault.primary_vault.name
}

output "secondary_backup_vault_id" {
  description = "ID of the secondary backup vault"
  value       = google_backup_dr_backup_vault.secondary_vault.backup_vault_id
}

output "secondary_backup_vault_name" {
  description = "Full name of the secondary backup vault"
  value       = google_backup_dr_backup_vault.secondary_vault.name
}

output "backup_plan_id" {
  description = "ID of the backup plan for the primary instance"
  value       = google_backup_dr_backup_plan.primary_backup_plan.backup_plan_id
}

output "backup_plan_name" {
  description = "Full name of the backup plan"
  value       = google_backup_dr_backup_plan.primary_backup_plan.name
}

# Cloud Functions Information
output "dr_orchestrator_function_name" {
  description = "Name of the disaster recovery orchestrator function"
  value       = google_cloudfunctions2_function.dr_orchestrator.name
}

output "dr_orchestrator_function_url" {
  description = "URL of the disaster recovery orchestrator function"
  value       = google_cloudfunctions2_function.dr_orchestrator.service_config[0].uri
}

output "backup_validator_function_name" {
  description = "Name of the backup validator function"
  value       = google_cloudfunctions2_function.backup_validator.name
}

output "backup_validator_function_url" {
  description = "URL of the backup validator function"
  value       = google_cloudfunctions2_function.backup_validator.service_config[0].uri
}

# Pub/Sub Information
output "dr_alerts_topic_name" {
  description = "Name of the disaster recovery alerts Pub/Sub topic"
  value       = google_pubsub_topic.dr_alerts.name
}

output "dr_alerts_topic_id" {
  description = "ID of the disaster recovery alerts Pub/Sub topic"
  value       = google_pubsub_topic.dr_alerts.id
}

output "alert_processor_subscription_name" {
  description = "Name of the alert processor subscription"
  value       = google_pubsub_subscription.alert_processor.name
}

# Cloud Scheduler Information
output "dr_monitoring_job_name" {
  description = "Name of the disaster recovery monitoring job"
  value       = google_cloud_scheduler_job.dr_monitoring.name
}

output "backup_validation_job_name" {
  description = "Name of the backup validation job"
  value       = google_cloud_scheduler_job.backup_validation.name
}

# Service Account Information
output "function_service_account_email" {
  description = "Email of the Cloud Functions service account"
  value       = google_service_account.function_sa.email
}

output "scheduler_service_account_email" {
  description = "Email of the Cloud Scheduler service account"
  value       = google_service_account.scheduler_sa.email
}

# Storage Information
output "function_source_bucket_name" {
  description = "Name of the Cloud Function source code bucket"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Function source code bucket"
  value       = google_storage_bucket.function_source.url
}

# Database Information
output "test_database_name" {
  description = "Name of the test database created for validation"
  value       = google_sql_database.test_db.name
}

# Monitoring Information
output "sql_health_alert_policy_name" {
  description = "Name of the SQL instance health alert policy"
  value       = google_monitoring_alert_policy.sql_instance_down.name
}

output "backup_failure_alert_policy_name" {
  description = "Name of the backup failure alert policy"
  value       = google_monitoring_alert_policy.backup_failure.name
}

# Connection Commands
output "connect_to_primary_psql" {
  description = "Command to connect to the primary database using psql"
  value       = "gcloud sql connect ${google_sql_database_instance.primary.name} --user=postgres --database=postgres"
  sensitive   = false
}

output "connect_to_replica_psql" {
  description = "Command to connect to the replica database using psql"
  value       = "gcloud sql connect ${google_sql_database_instance.dr_replica.name} --user=postgres --database=postgres"
  sensitive   = false
}

# Resource Summary
output "resource_summary" {
  description = "Summary of all created disaster recovery resources"
  value = {
    primary_sql_instance = {
      name   = google_sql_database_instance.primary.name
      region = google_sql_database_instance.primary.region
      tier   = google_sql_database_instance.primary.settings[0].tier
    }
    dr_replica = {
      name   = google_sql_database_instance.dr_replica.name
      region = google_sql_database_instance.dr_replica.region
      tier   = google_sql_database_instance.dr_replica.settings[0].tier
    }
    backup_vaults = {
      primary = {
        id       = google_backup_dr_backup_vault.primary_vault.backup_vault_id
        location = google_backup_dr_backup_vault.primary_vault.location
      }
      secondary = {
        id       = google_backup_dr_backup_vault.secondary_vault.backup_vault_id
        location = google_backup_dr_backup_vault.secondary_vault.location
      }
    }
    functions = {
      orchestrator = google_cloudfunctions2_function.dr_orchestrator.name
      validator    = google_cloudfunctions2_function.backup_validator.name
    }
    monitoring = {
      topic        = google_pubsub_topic.dr_alerts.name
      subscription = google_pubsub_subscription.alert_processor.name
    }
    automation = {
      monitoring_schedule = google_cloud_scheduler_job.dr_monitoring.schedule
      validation_schedule = google_cloud_scheduler_job.backup_validation.schedule
    }
  }
}

# Disaster Recovery Testing Commands
output "disaster_recovery_test_commands" {
  description = "Commands for testing disaster recovery procedures"
  value = {
    simulate_failover = "gcloud sql instances failover ${google_sql_database_instance.primary.name}"
    check_backup_status = "gcloud backup-dr backup-plans list --location=${var.primary_region}"
    trigger_health_check = "curl -X POST '${google_cloudfunctions2_function.dr_orchestrator.service_config[0].uri}' -H 'Authorization: Bearer $(gcloud auth print-identity-token)' -H 'Content-Type: application/json' -d '{\"action\": \"health_check\"}'"
    validate_backups = "curl -X POST '${google_cloudfunctions2_function.backup_validator.service_config[0].uri}' -H 'Authorization: Bearer $(gcloud auth print-identity-token)' -H 'Content-Type: application/json' -d '{\"action\": \"validate_backups\"}'"
  }
  sensitive = false
}

# Cost Estimation Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the disaster recovery setup"
  value = {
    note = "Estimated costs based on us-central1 and us-east1 regions"
    cloud_sql_primary = "~$200-400/month (depends on tier and storage)"
    cloud_sql_replica = "~$200-400/month (depends on tier and storage)"
    backup_storage = "~$50-100/month (depends on backup size and retention)"
    cloud_functions = "~$10-30/month (depends on invocations)"
    cloud_scheduler = "~$1-5/month"
    pub_sub = "~$1-10/month (depends on message volume)"
    monitoring = "~$5-20/month"
    total_estimated = "~$467-965/month"
    disclaimer = "Actual costs may vary based on usage patterns, data transfer, and regional pricing differences"
  }
}

# Security Information
output "security_recommendations" {
  description = "Security recommendations for the disaster recovery setup"
  value = {
    enable_private_ip = "Consider enabling private IP for Cloud SQL instances in production"
    network_security = "Configure VPC firewall rules to restrict database access"
    iam_audit = "Regularly audit IAM permissions for service accounts"
    backup_encryption = "Backup data is encrypted at rest by default"
    ssl_enforcement = "Enable SSL enforcement for database connections"
    audit_logging = "Enable Cloud SQL audit logging for compliance"
  }
}