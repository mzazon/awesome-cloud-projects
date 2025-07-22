# Project and resource identification outputs
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone for zonal resources"
  value       = var.zone
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Service account outputs
output "service_accounts" {
  description = "Service accounts created for the secure development environment"
  value = {
    secure_app = {
      name  = google_service_account.secure_app_sa.name
      email = google_service_account.secure_app_sa.email
      id    = google_service_account.secure_app_sa.unique_id
    }
    gemini_code_assist = {
      name  = google_service_account.gemini_code_assist_sa.name
      email = google_service_account.gemini_code_assist_sa.email
      id    = google_service_account.gemini_code_assist_sa.unique_id
    }
    cloud_build = {
      name  = google_service_account.cloud_build_sa.name
      email = google_service_account.cloud_build_sa.email
      id    = google_service_account.cloud_build_sa.unique_id
    }
  }
}

# KMS encryption outputs
output "kms_configuration" {
  description = "KMS encryption configuration details"
  value = {
    keyring_name = google_kms_key_ring.secure_dev_keyring.name
    keyring_id   = google_kms_key_ring.secure_dev_keyring.id
    key_name     = google_kms_crypto_key.secret_encryption_key.name
    key_id       = google_kms_crypto_key.secret_encryption_key.id
  }
}

# Secrets management outputs
output "secrets" {
  description = "Secret Manager configuration and access information"
  value = {
    database_secret = {
      name = google_secret_manager_secret.db_secret.name
      id   = google_secret_manager_secret.db_secret.secret_id
    }
    api_secret = {
      name = google_secret_manager_secret.api_secret.name
      id   = google_secret_manager_secret.api_secret.secret_id
    }
  }
  sensitive = false
}

# Cloud Run application outputs
output "cloud_run_service" {
  description = "Cloud Run service configuration and access information"
  value = {
    name            = google_cloud_run_v2_service.secure_app.name
    url             = google_cloud_run_v2_service.secure_app.uri
    location        = google_cloud_run_v2_service.secure_app.location
    service_account = google_cloud_run_v2_service.secure_app.template[0].service_account
    latest_revision = google_cloud_run_v2_service.secure_app.latest_ready_revision
  }
}

# Cloud Workstations outputs
output "workstation_configuration" {
  description = "Cloud Workstations cluster and configuration details"
  value = {
    cluster = {
      name     = google_workstations_workstation_cluster.secure_dev_cluster.name
      id       = google_workstations_workstation_cluster.secure_dev_cluster.workstation_cluster_id
      location = google_workstations_workstation_cluster.secure_dev_cluster.location
      network  = google_workstations_workstation_cluster.secure_dev_cluster.network
    }
    config = {
      name         = google_workstations_workstation_config.secure_dev_config.name
      id           = google_workstations_workstation_config.secure_dev_config.workstation_config_id
      machine_type = google_workstations_workstation_config.secure_dev_config.host[0].gce_instance[0].machine_type
      disk_size    = google_workstations_workstation_config.secure_dev_config.host[0].gce_instance[0].boot_disk_size_gb
    }
    workstation = {
      name = google_workstations_workstation.secure_workstation.name
      id   = google_workstations_workstation.secure_workstation.workstation_id
    }
  }
}

# Workstation access URL
output "workstation_access_url" {
  description = "URL to access the Cloud Workstation through the web interface"
  value       = "https://workstations.googleusercontent.com/"
}

# Artifact Registry outputs
output "artifact_registry" {
  description = "Artifact Registry repository information"
  value = {
    repository_name = google_artifact_registry_repository.secure_dev_images.name
    repository_id   = google_artifact_registry_repository.secure_dev_images.repository_id
    location        = google_artifact_registry_repository.secure_dev_images.location
    format          = google_artifact_registry_repository.secure_dev_images.format
    docker_config = {
      registry_url = "${var.region}-docker.pkg.dev"
      image_prefix = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_dev_images.repository_id}"
    }
  }
}

# Source repository outputs
output "source_repository" {
  description = "Cloud Source Repository information"
  value = {
    name = google_sourcerepo_repository.secure_dev_repo.name
    url  = google_sourcerepo_repository.secure_dev_repo.url
    clone_urls = {
      https = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.secure_dev_repo.name}"
      ssh   = "ssh://source.developers.google.com:2022/p/${var.project_id}/r/${google_sourcerepo_repository.secure_dev_repo.name}"
    }
  }
}

# Cloud Build outputs
output "cloud_build_trigger" {
  description = "Cloud Build trigger configuration"
  value = {
    name        = google_cloudbuild_trigger.secure_app_trigger.name
    id          = google_cloudbuild_trigger.secure_app_trigger.trigger_id
    description = google_cloudbuild_trigger.secure_app_trigger.description
    repo_name   = google_cloudbuild_trigger.secure_app_trigger.trigger_template[0].repo_name
    branch_name = google_cloudbuild_trigger.secure_app_trigger.trigger_template[0].branch_name
  }
}

# IAP and OAuth configuration outputs
output "iap_configuration" {
  description = "Identity-Aware Proxy and OAuth configuration"
  value = {
    oauth_brand = {
      name              = google_iap_brand.oauth_brand.name
      application_title = google_iap_brand.oauth_brand.application_title
      support_email     = google_iap_brand.oauth_brand.support_email
    }
    oauth_client = {
      name         = google_iap_client.oauth_client.name
      display_name = google_iap_client.oauth_client.display_name
      client_id    = google_iap_client.oauth_client.client_id
    }
  }
  sensitive = true
}

# Binary Authorization outputs (if enabled)
output "binary_authorization" {
  description = "Binary Authorization configuration (if enabled)"
  value = var.enable_binary_authorization ? {
    policy_name = google_binary_authorization_policy.secure_dev_policy[0].name
    attestor = {
      name        = google_binary_authorization_attestor.secure_dev_attestor[0].name
      description = google_binary_authorization_attestor.secure_dev_attestor[0].description
    }
    note = {
      name = google_container_analysis_note.secure_dev_note[0].name
    }
  } : null
}

# Budget configuration outputs (if enabled)
output "budget_configuration" {
  description = "Budget and cost monitoring configuration (if enabled)"
  value = var.budget_amount > 0 ? {
    budget_name    = google_billing_budget.secure_dev_budget[0].display_name
    budget_amount  = var.budget_amount
    alert_thresholds = var.budget_alert_thresholds
  } : null
}

# Security and access control outputs
output "security_configuration" {
  description = "Security configuration and access control details"
  value = {
    allowed_users = var.allowed_users
    iap_enabled   = true
    encryption = {
      secrets_encrypted_at_rest = true
      kms_managed_encryption   = true
    }
    service_accounts = {
      count                = 3
      least_privilege_mode = true
    }
    network_security = {
      private_workstations = true
      no_public_cloud_run = true
    }
  }
}

# Environment and application configuration
output "application_environment" {
  description = "Application environment configuration"
  value = {
    environment = var.environment
    labels      = local.common_labels
    secrets = {
      db_secret_name  = local.secret_names.db
      api_secret_name = local.secret_names.api
    }
    features = {
      gemini_code_assist_enabled = true
      binary_authorization       = var.enable_binary_authorization
      vpc_service_controls       = var.enable_vpc_sc
    }
  }
}

# Next steps and access instructions
output "deployment_instructions" {
  description = "Instructions for accessing and using the deployed environment"
  value = {
    cloud_run_access = "Use IAP-authenticated requests to access the Cloud Run service at ${google_cloud_run_v2_service.secure_app.uri}"
    workstation_access = "Access your secure workstation at https://workstations.googleusercontent.com/"
    source_code_setup = "Clone the source repository: gcloud source repos clone ${google_sourcerepo_repository.secure_dev_repo.name}"
    gemini_setup = "Gemini Code Assist is pre-configured in your workstation environment"
    secret_access = "Secrets are automatically accessible to authorized applications via service accounts"
  }
}

# Monitoring and observability
output "monitoring_links" {
  description = "Links to monitoring and management consoles"
  value = {
    cloud_console     = "https://console.cloud.google.com/home/dashboard?project=${var.project_id}"
    cloud_run_console = "https://console.cloud.google.com/run?project=${var.project_id}"
    workstations_console = "https://console.cloud.google.com/workstations?project=${var.project_id}"
    secret_manager    = "https://console.cloud.google.com/security/secret-manager?project=${var.project_id}"
    cloud_build       = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    artifact_registry = "https://console.cloud.google.com/artifacts?project=${var.project_id}"
    iap_console      = "https://console.cloud.google.com/security/iap?project=${var.project_id}"
  }
}

# Cost optimization recommendations
output "cost_optimization_tips" {
  description = "Cost optimization recommendations for the deployment"
  value = {
    workstation_management = "Stop workstations when not in use to reduce costs"
    cloud_run_scaling = "Cloud Run scales to zero when not in use"
    storage_lifecycle = "Configure lifecycle policies for Artifact Registry images"
    monitoring = var.budget_amount > 0 ? "Budget alerts are configured to monitor spending" : "Consider enabling budget alerts for cost monitoring"
    idle_timeout = "Workstations are configured with ${var.workstation_idle_timeout}s idle timeout"
  }
}