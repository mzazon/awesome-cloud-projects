# ==============================================================================
# TERRAFORM OUTPUTS
# Enterprise Identity Federation Workflows with Cloud IAM and Service Directory
# ==============================================================================

# ==============================================================================
# WORKLOAD IDENTITY FEDERATION OUTPUTS
# ==============================================================================

output "workload_identity_pool_id" {
  description = "The ID of the created Workload Identity Pool"
  value       = google_iam_workload_identity_pool.enterprise_pool.workload_identity_pool_id
}

output "workload_identity_pool_name" {
  description = "The full resource name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.enterprise_pool.name
}

output "workload_identity_provider_id" {
  description = "The ID of the created Workload Identity Pool Provider"
  value       = google_iam_workload_identity_pool_provider.oidc_provider.workload_identity_pool_provider_id
}

output "workload_identity_provider_name" {
  description = "The full resource name of the Workload Identity Pool Provider"
  value       = google_iam_workload_identity_pool_provider.oidc_provider.name
}

output "workload_identity_pool_state" {
  description = "The current state of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.enterprise_pool.state
}

output "workload_identity_provider_state" {
  description = "The current state of the Workload Identity Pool Provider"
  value       = google_iam_workload_identity_pool_provider.oidc_provider.state
}

# ==============================================================================
# SERVICE ACCOUNT OUTPUTS
# ==============================================================================

output "federation_service_account_email" {
  description = "Email address of the main federation service account"
  value       = google_service_account.federation_sa.email
}

output "federation_service_account_unique_id" {
  description = "Unique ID of the main federation service account"
  value       = google_service_account.federation_sa.unique_id
}

output "read_only_service_account_email" {
  description = "Email address of the read-only service account"
  value       = google_service_account.read_only_sa.email
}

output "admin_service_account_email" {
  description = "Email address of the admin service account"
  value       = google_service_account.admin_sa.email
}

output "function_service_account_email" {
  description = "Email address of the Cloud Function service account"
  value       = google_service_account.function_sa.email
}

output "service_accounts" {
  description = "Map of all created service accounts with their details"
  value = {
    federation = {
      email     = google_service_account.federation_sa.email
      unique_id = google_service_account.federation_sa.unique_id
      name      = google_service_account.federation_sa.name
    }
    read_only = {
      email     = google_service_account.read_only_sa.email
      unique_id = google_service_account.read_only_sa.unique_id
      name      = google_service_account.read_only_sa.name
    }
    admin = {
      email     = google_service_account.admin_sa.email
      unique_id = google_service_account.admin_sa.unique_id
      name      = google_service_account.admin_sa.name
    }
    function = {
      email     = google_service_account.function_sa.email
      unique_id = google_service_account.function_sa.unique_id
      name      = google_service_account.function_sa.name
    }
  }
}

# ==============================================================================
# SERVICE DIRECTORY OUTPUTS
# ==============================================================================

output "service_directory_namespace_id" {
  description = "ID of the Service Directory namespace"
  value       = google_service_directory_namespace.enterprise_namespace.namespace_id
}

output "service_directory_namespace_name" {
  description = "Full resource name of the Service Directory namespace"
  value       = google_service_directory_namespace.enterprise_namespace.name
}

output "service_directory_namespace_location" {
  description = "Location of the Service Directory namespace"
  value       = google_service_directory_namespace.enterprise_namespace.location
}

output "service_directory_services" {
  description = "Map of created Service Directory services"
  value = {
    user_management = {
      id       = google_service_directory_service.user_management.service_id
      name     = google_service_directory_service.user_management.name
      metadata = google_service_directory_service.user_management.metadata
    }
    identity_provider = {
      id       = google_service_directory_service.identity_provider.service_id
      name     = google_service_directory_service.identity_provider.name
      metadata = google_service_directory_service.identity_provider.metadata
    }
    resource_manager = {
      id       = google_service_directory_service.resource_manager.service_id
      name     = google_service_directory_service.resource_manager.name
      metadata = google_service_directory_service.resource_manager.metadata
    }
  }
}

# ==============================================================================
# CLOUD FUNCTION OUTPUTS
# ==============================================================================

output "cloud_function_name" {
  description = "Name of the identity provisioning Cloud Function"
  value       = google_cloudfunctions2_function.identity_provisioner.name
}

output "cloud_function_url" {
  description = "URL of the identity provisioning Cloud Function"
  value       = google_cloudfunctions2_function.identity_provisioner.url
}

output "cloud_function_state" {
  description = "Current state of the Cloud Function"
  value       = google_cloudfunctions2_function.identity_provisioner.state
}

output "cloud_function_service_config" {
  description = "Service configuration details of the Cloud Function"
  value = {
    uri                   = google_cloudfunctions2_function.identity_provisioner.service_config[0].uri
    service_account_email = google_cloudfunctions2_function.identity_provisioner.service_config[0].service_account_email
    max_instance_count    = google_cloudfunctions2_function.identity_provisioner.service_config[0].max_instance_count
    min_instance_count    = google_cloudfunctions2_function.identity_provisioner.service_config[0].min_instance_count
    available_memory      = google_cloudfunctions2_function.identity_provisioner.service_config[0].available_memory
    timeout_seconds       = google_cloudfunctions2_function.identity_provisioner.service_config[0].timeout_seconds
  }
}

# ==============================================================================
# SECRET MANAGER OUTPUTS
# ==============================================================================

output "federation_config_secret_id" {
  description = "Secret ID for the federation configuration"
  value       = google_secret_manager_secret.federation_config.secret_id
}

output "federation_config_secret_name" {
  description = "Full resource name of the federation configuration secret"
  value       = google_secret_manager_secret.federation_config.name
}

output "idp_config_secret_id" {
  description = "Secret ID for the IdP configuration"
  value       = google_secret_manager_secret.idp_config.secret_id
}

output "idp_config_secret_name" {
  description = "Full resource name of the IdP configuration secret"
  value       = google_secret_manager_secret.idp_config.name
}

output "secrets" {
  description = "Map of all created secrets with their details"
  value = {
    federation_config = {
      id   = google_secret_manager_secret.federation_config.secret_id
      name = google_secret_manager_secret.federation_config.name
    }
    idp_config = {
      id   = google_secret_manager_secret.idp_config.secret_id
      name = google_secret_manager_secret.idp_config.name
    }
  }
}

# ==============================================================================
# DNS OUTPUTS
# ==============================================================================

output "dns_zone_name" {
  description = "Name of the DNS managed zone"
  value       = google_dns_managed_zone.enterprise_services.name
}

output "dns_zone_dns_name" {
  description = "DNS name of the managed zone"
  value       = google_dns_managed_zone.enterprise_services.dns_name
}

output "dns_zone_name_servers" {
  description = "Name servers for the DNS zone"
  value       = google_dns_managed_zone.enterprise_services.name_servers
}

output "dns_service_aliases" {
  description = "DNS aliases created for service discovery"
  value = {
    user_management   = google_dns_record_set.user_management_alias.name
    identity_provider = google_dns_record_set.identity_provider_alias.name
    resource_manager  = google_dns_record_set.resource_manager_alias.name
  }
}

# ==============================================================================
# STORAGE OUTPUTS
# ==============================================================================

output "function_source_bucket_name" {
  description = "Name of the Cloud Function source code bucket"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Function source code bucket"
  value       = google_storage_bucket.function_source.url
}

output "enterprise_artifacts_bucket_name" {
  description = "Name of the enterprise artifacts storage bucket"
  value       = google_storage_bucket.enterprise_artifacts.name
}

output "enterprise_artifacts_bucket_url" {
  description = "URL of the enterprise artifacts storage bucket"
  value       = google_storage_bucket.enterprise_artifacts.url
}

# ==============================================================================
# FEDERATION CONFIGURATION OUTPUTS
# ==============================================================================

output "oidc_issuer_uri" {
  description = "The configured OIDC issuer URI"
  value       = var.oidc_issuer_uri
}

output "oidc_allowed_audiences" {
  description = "List of allowed OIDC audiences"
  value       = var.oidc_allowed_audiences
}

output "federation_instructions" {
  description = "Instructions for using the identity federation setup"
  value = {
    pool_resource_name     = google_iam_workload_identity_pool.enterprise_pool.name
    provider_resource_name = google_iam_workload_identity_pool_provider.oidc_provider.name
    service_account_email  = google_service_account.federation_sa.email
    
    # Token exchange endpoint
    token_endpoint = "https://sts.googleapis.com/v1/token"
    
    # Example IAM policy binding format
    iam_policy_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.enterprise_pool.name}/attribute.repository/${var.project_id}"
    
    # Example workload identity usage
    workload_identity_usage = {
      audience                = "//iam.googleapis.com/${google_iam_workload_identity_pool_provider.oidc_provider.name}"
      service_account_email   = google_service_account.federation_sa.email
      token_lifetime          = "3600s"
    }
  }
}

# ==============================================================================
# MONITORING OUTPUTS
# ==============================================================================

output "monitoring_enabled" {
  description = "Whether monitoring is enabled"
  value       = var.enable_monitoring
}

output "monitoring_notification_channels" {
  description = "Monitoring notification channels (if enabled)"
  value = var.enable_monitoring ? [
    for channel in google_monitoring_notification_channel.email : {
      id           = channel.id
      display_name = channel.display_name
      type         = channel.type
    }
  ] : []
}

# ==============================================================================
# ENDPOINT INFORMATION FOR INTEGRATION
# ==============================================================================

output "integration_endpoints" {
  description = "Key endpoints for external system integration"
  value = {
    # Cloud Function endpoint for identity provisioning
    identity_provisioner_url = google_cloudfunctions2_function.identity_provisioner.url
    
    # Service Directory endpoints
    service_discovery_namespace = "projects/${var.project_id}/locations/${var.region}/namespaces/${google_service_directory_namespace.enterprise_namespace.namespace_id}"
    
    # DNS endpoints for service resolution
    dns_zone = google_dns_managed_zone.enterprise_services.dns_name
    
    # Secret Manager endpoints
    federation_config_secret = "projects/${var.project_id}/secrets/${google_secret_manager_secret.federation_config.secret_id}/versions/latest"
    idp_config_secret       = "projects/${var.project_id}/secrets/${google_secret_manager_secret.idp_config.secret_id}/versions/latest"
  }
}

# ==============================================================================
# SECURITY AND ACCESS CONTROL OUTPUTS
# ==============================================================================

output "security_configuration" {
  description = "Security configuration summary"
  value = {
    workload_identity_enabled = true
    attribute_mapping_configured = true
    conditional_access_enabled = var.oidc_attribute_condition != ""
    service_accounts_count = 4
    iam_bindings_applied = true
    
    # Access patterns
    federation_access_pattern = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.enterprise_pool.name}/*"
    
    # Security features enabled
    secret_manager_encryption = true
    private_dns_zones = true
    function_ingress_restricted = true
  }
}

# ==============================================================================
# RESOURCE SUMMARY
# ==============================================================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    # Core identity federation resources
    workload_identity_pools = 1
    workload_identity_providers = 1
    service_accounts = 4
    
    # Service discovery resources
    service_directory_namespaces = 1
    service_directory_services = 3
    dns_zones = 1
    dns_records = 3
    
    # Compute resources
    cloud_functions = 1
    
    # Storage resources
    storage_buckets = 2
    secrets = 2
    
    # Network resources
    dns_managed_zones = 1
    
    # IAM bindings
    iam_policy_bindings = "multiple"
    
    # Project APIs enabled
    apis_enabled = length(google_project_service.required_apis)
  }
}

# ==============================================================================
# COST ESTIMATION HELPERS
# ==============================================================================

output "cost_estimation_info" {
  description = "Information to help estimate monthly costs"
  value = {
    # Fixed costs (approximate monthly)
    service_directory_namespace = "Free tier available, then $0.20 per namespace per month"
    secret_manager_secrets = "First 6 active secret versions free per month, then $0.06 per active version"
    cloud_dns_zones = "$0.20 per zone per month (first 25 zones free)"
    
    # Variable costs (based on usage)
    cloud_function_invocations = "First 2M invocations free per month, then $0.40 per 1M invocations"
    cloud_function_compute_time = "First 400,000 GB-seconds free per month"
    storage_buckets = "Regional storage: $0.020 per GB per month"
    workload_identity_federation = "No additional charges for token exchanges"
    
    # Estimated minimum monthly cost
    estimated_minimum_cost = "$0-5 for low usage scenarios"
    estimated_moderate_cost = "$10-50 for moderate enterprise usage"
  }
}

# ==============================================================================
# TROUBLESHOOTING AND VALIDATION OUTPUTS
# ==============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    # Workload Identity Pool validation
    check_wi_pool = "gcloud iam workload-identity-pools describe ${google_iam_workload_identity_pool.enterprise_pool.workload_identity_pool_id} --location=global"
    
    # Service Directory validation
    check_namespace = "gcloud service-directory namespaces describe ${google_service_directory_namespace.enterprise_namespace.namespace_id} --location=${var.region}"
    
    # Cloud Function validation
    check_function = "gcloud functions describe ${google_cloudfunctions2_function.identity_provisioner.name} --region=${var.region} --gen2"
    
    # Secret validation
    check_secrets = "gcloud secrets list --filter='name ~ federation-config OR name ~ idp-config'"
    
    # DNS validation
    check_dns = "gcloud dns managed-zones describe ${google_dns_managed_zone.enterprise_services.name}"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure external identity provider to trust the Workload Identity Pool",
    "2. Test identity federation using sample workloads",
    "3. Configure IAM bindings for your specific use cases",
    "4. Set up monitoring and alerting based on your requirements",
    "5. Test the Cloud Function endpoint for identity provisioning",
    "6. Validate service discovery through DNS resolution",
    "7. Review and adjust security policies as needed",
    "8. Document the integration process for your team"
  ]
}