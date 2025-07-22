# ===================================================
# Outputs for Legacy Database Migration Solution
# ===================================================

# ===================================================
# Network Information
# ===================================================

output "network_details" {
  description = "Details about the VPC network created for migration"
  value = {
    network_id   = google_compute_network.migration_network.id
    network_name = google_compute_network.migration_network.name
    network_uri  = google_compute_network.migration_network.self_link
    subnet_id    = google_compute_subnetwork.migration_subnet.id
    subnet_name  = google_compute_subnetwork.migration_subnet.name
    subnet_cidr  = google_compute_subnetwork.migration_subnet.ip_cidr_range
  }
}

output "private_services_connection" {
  description = "Details about the private services connection"
  value = {
    connection_name      = google_service_networking_connection.private_vpc_connection.network
    reserved_ranges      = google_service_networking_connection.private_vpc_connection.reserved_peering_ranges
    private_ip_address   = google_compute_global_address.private_services_access.address
    private_ip_range     = "${google_compute_global_address.private_services_access.address}/${google_compute_global_address.private_services_access.prefix_length}"
  }
}

# ===================================================
# Cloud SQL PostgreSQL Information
# ===================================================

output "postgres_instance_details" {
  description = "Details about the Cloud SQL PostgreSQL instance"
  value = {
    instance_name        = google_sql_database_instance.postgres_target.name
    instance_id          = google_sql_database_instance.postgres_target.id
    connection_name      = google_sql_database_instance.postgres_target.connection_name
    database_version     = google_sql_database_instance.postgres_target.database_version
    region              = google_sql_database_instance.postgres_target.region
    tier                = google_sql_database_instance.postgres_target.settings[0].tier
    availability_type   = google_sql_database_instance.postgres_target.settings[0].availability_type
    disk_size           = google_sql_database_instance.postgres_target.settings[0].disk_size
    disk_type           = google_sql_database_instance.postgres_target.settings[0].disk_type
    self_link           = google_sql_database_instance.postgres_target.self_link
  }
}

output "postgres_connection_details" {
  description = "Connection details for the PostgreSQL instance"
  value = {
    private_ip_address    = google_sql_database_instance.postgres_target.private_ip_address
    public_ip_address     = var.enable_public_ip ? google_sql_database_instance.postgres_target.public_ip_address : null
    first_ip_address      = google_sql_database_instance.postgres_target.first_ip_address
    connection_name       = google_sql_database_instance.postgres_target.connection_name
    dns_name             = google_sql_database_instance.postgres_target.dns_name
    service_account_email = google_sql_database_instance.postgres_target.service_account_email_address
  }
}

output "postgres_user_details" {
  description = "Details about the PostgreSQL migration user"
  value = {
    username = google_sql_user.migration_user.name
    instance = google_sql_user.migration_user.instance
  }
  sensitive = false
}

output "postgres_ssl_certificate" {
  description = "SSL certificate information for secure connections"
  value = {
    common_name       = google_sql_ssl_cert.postgres_client_cert.common_name
    sha1_fingerprint = google_sql_ssl_cert.postgres_client_cert.sha1_fingerprint
    create_time      = google_sql_ssl_cert.postgres_client_cert.create_time
    expiration_time  = google_sql_ssl_cert.postgres_client_cert.expiration_time
  }
  sensitive = false
}

# ===================================================
# Database Migration Service Information
# ===================================================

output "migration_connection_profiles" {
  description = "Details about the Database Migration Service connection profiles"
  value = {
    source_profile = {
      id           = google_database_migration_service_connection_profile.source_sqlserver.id
      name         = google_database_migration_service_connection_profile.source_sqlserver.name
      display_name = google_database_migration_service_connection_profile.source_sqlserver.display_name
      state        = google_database_migration_service_connection_profile.source_sqlserver.state
      create_time  = google_database_migration_service_connection_profile.source_sqlserver.create_time
    }
    destination_profile = {
      id           = google_database_migration_service_connection_profile.dest_postgres.id
      name         = google_database_migration_service_connection_profile.dest_postgres.name
      display_name = google_database_migration_service_connection_profile.dest_postgres.display_name
      state        = google_database_migration_service_connection_profile.dest_postgres.state
      create_time  = google_database_migration_service_connection_profile.dest_postgres.create_time
    }
  }
}

output "migration_job_details" {
  description = "Details about the Database Migration Service migration job"
  value = {
    job_id       = google_database_migration_service_migration_job.legacy_modernization.id
    name         = google_database_migration_service_migration_job.legacy_modernization.name
    display_name = google_database_migration_service_migration_job.legacy_modernization.display_name
    type         = google_database_migration_service_migration_job.legacy_modernization.type
    state        = google_database_migration_service_migration_job.legacy_modernization.state
    phase        = google_database_migration_service_migration_job.legacy_modernization.phase
    create_time  = google_database_migration_service_migration_job.legacy_modernization.create_time
  }
}

# ===================================================
# Application Modernization Resources
# ===================================================

output "source_repository_details" {
  description = "Details about the source repository for application modernization"
  value = {
    repository_name = google_sourcerepo_repository.modernization_repo.name
    repository_url  = google_sourcerepo_repository.modernization_repo.url
    clone_url       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.modernization_repo.name}"
  }
}

# ===================================================
# Monitoring and Logging Information
# ===================================================

output "monitoring_details" {
  description = "Details about monitoring and alerting configuration"
  value = {
    alert_policy_id   = google_monitoring_alert_policy.migration_failure.id
    alert_policy_name = google_monitoring_alert_policy.migration_failure.name
  }
}

output "logging_details" {
  description = "Details about logging configuration"
  value = {
    log_sink_name            = google_logging_project_sink.migration_logs.name
    log_sink_destination     = google_logging_project_sink.migration_logs.destination
    log_sink_filter         = google_logging_project_sink.migration_logs.filter
    log_sink_writer_identity = google_logging_project_sink.migration_logs.writer_identity
    logs_bucket_name        = google_storage_bucket.migration_logs.name
    logs_bucket_url         = google_storage_bucket.migration_logs.url
  }
}

# ===================================================
# Security and Access Information
# ===================================================

output "firewall_rules" {
  description = "Details about firewall rules created"
  value = {
    internal_rule = {
      name         = google_compute_firewall.allow_internal.name
      source_ranges = google_compute_firewall.allow_internal.source_ranges
    }
    ssh_rule = {
      name         = google_compute_firewall.allow_ssh.name
      source_ranges = google_compute_firewall.allow_ssh.source_ranges
    }
    dms_rule = {
      name         = google_compute_firewall.allow_dms.name
      source_ranges = google_compute_firewall.allow_dms.source_ranges
    }
  }
}

# ===================================================
# Resource Identifiers and Names
# ===================================================

output "resource_names" {
  description = "Names of all created resources for reference"
  value = {
    project_id                = var.project_id
    region                   = local.region
    zone                     = local.zone
    random_suffix            = random_id.suffix.hex
    network_name             = google_compute_network.migration_network.name
    subnet_name              = google_compute_subnetwork.migration_subnet.name
    postgres_instance_name   = google_sql_database_instance.postgres_target.name
    source_profile_name      = google_database_migration_service_connection_profile.source_sqlserver.name
    dest_profile_name        = google_database_migration_service_connection_profile.dest_postgres.name
    migration_job_name       = google_database_migration_service_migration_job.legacy_modernization.name
    repository_name          = google_sourcerepo_repository.modernization_repo.name
    logs_bucket_name         = google_storage_bucket.migration_logs.name
  }
}

# ===================================================
# Connection Strings and Commands
# ===================================================

output "connection_commands" {
  description = "Useful connection commands for accessing resources"
  value = {
    # Cloud SQL Proxy connection command
    cloud_sql_proxy = "cloud_sql_proxy -instances=${google_sql_database_instance.postgres_target.connection_name}=tcp:5432"
    
    # gcloud SQL connect command
    gcloud_sql_connect = "gcloud sql connect ${google_sql_database_instance.postgres_target.name} --user=${google_sql_user.migration_user.name}"
    
    # psql connection string (when using Cloud SQL Proxy)
    psql_connection = "psql 'host=127.0.0.1 port=5432 user=${google_sql_user.migration_user.name} dbname=postgres sslmode=require'"
    
    # Source repository clone command
    git_clone = "gcloud source repos clone ${google_sourcerepo_repository.modernization_repo.name} --project=${var.project_id}"
  }
  sensitive = false
}

# ===================================================
# Migration Status and Next Steps
# ===================================================

output "migration_status" {
  description = "Current migration status and next steps"
  value = {
    migration_job_state = google_database_migration_service_migration_job.legacy_modernization.state
    migration_job_phase = google_database_migration_service_migration_job.legacy_modernization.phase
    
    next_steps = [
      "1. Configure source database connection details in the source connection profile",
      "2. Update source database firewall to allow Database Migration Service access",
      "3. Start the migration job using: gcloud datamigration migration-jobs start ${google_database_migration_service_migration_job.legacy_modernization.name}",
      "4. Monitor migration progress in the Google Cloud Console",
      "5. Begin application modernization using Application Design Center",
      "6. Use Gemini Code Assist for code generation and optimization",
      "7. Test modernized application with the PostgreSQL database",
      "8. Perform cutover when ready"
    ]
  }
}

# ===================================================
# Cost Information
# ===================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    note = "Costs are estimates and may vary based on actual usage"
    cloud_sql_postgres = "Approximately $50-200/month depending on tier and usage"
    network_resources  = "Minimal - mostly covered by free tier"
    storage_costs      = "Variable based on data volume and backup retention"
    migration_service  = "Usage-based pricing during active migration"
    monitoring_logging = "Based on log volume and metric usage"
    
    cost_optimization_tips = [
      "Use ZONAL availability for non-production environments",
      "Configure appropriate disk autoresize limits",
      "Review and adjust backup retention periods",
      "Monitor and optimize query performance",
      "Consider scheduled scaling for development environments"
    ]
  }
}

# ===================================================
# Documentation and Resources
# ===================================================

output "useful_resources" {
  description = "Useful documentation and resource links"
  value = {
    documentation = {
      database_migration_service = "https://cloud.google.com/database-migration/docs"
      cloud_sql_postgres        = "https://cloud.google.com/sql/docs/postgres"
      application_design_center  = "https://cloud.google.com/application-design-center"
      gemini_code_assist        = "https://cloud.google.com/gemini/docs/codeassist"
    }
    
    console_links = {
      migration_jobs     = "https://console.cloud.google.com/datamigration/migration-jobs"
      cloud_sql         = "https://console.cloud.google.com/sql/instances"
      source_repos      = "https://console.cloud.google.com/source/repos"
      monitoring        = "https://console.cloud.google.com/monitoring"
      logs_explorer     = "https://console.cloud.google.com/logs/query"
    }
    
    gcloud_commands = {
      list_migration_jobs = "gcloud datamigration migration-jobs list --region=${local.region}"
      describe_migration  = "gcloud datamigration migration-jobs describe ${google_database_migration_service_migration_job.legacy_modernization.migration_job_id} --region=${local.region}"
      sql_instances      = "gcloud sql instances list"
      logs_tail          = "gcloud logging read 'resource.type=\"database_migration_service_migration_job\"' --follow"
    }
  }
}

# ===================================================
# Sensitive Outputs (password references)
# ===================================================

output "sensitive_information" {
  description = "References to sensitive information (not the actual values)"
  value = {
    postgres_password_secret = "Password stored in Terraform state - use 'terraform output -json' to retrieve"
    ssl_certificates_note   = "SSL certificates and keys are stored in Terraform state"
    source_db_credentials   = "Source database credentials should be updated with actual values"
    
    security_notes = [
      "Change default passwords before production use",
      "Store sensitive values in Google Secret Manager for production",
      "Rotate SSL certificates according to your security policy",
      "Use IAM-based authentication where possible",
      "Enable audit logging for compliance requirements"
    ]
  }
}

# ===================================================
# Terraform Workspace Information
# ===================================================

output "terraform_workspace_info" {
  description = "Information about the Terraform workspace and state"
  value = {
    workspace_name    = terraform.workspace
    random_suffix     = random_id.suffix.hex
    terraform_version = "Use 'terraform version' to see current version"
    state_location   = "Terraform state location depends on backend configuration"
    
    management_commands = [
      "terraform plan - Preview changes",
      "terraform apply - Apply changes", 
      "terraform destroy - Destroy resources",
      "terraform state list - List all resources",
      "terraform output - Show all outputs"
    ]
  }
}