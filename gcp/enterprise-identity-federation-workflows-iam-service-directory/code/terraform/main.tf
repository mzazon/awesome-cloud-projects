# ==============================================================================
# Enterprise Identity Federation Workflows with Cloud IAM and Service Directory
# ==============================================================================
# This Terraform configuration deploys a complete enterprise identity federation
# system using Google Cloud's Workload Identity Federation, Service Directory,
# Secret Manager, and Cloud Functions for automated provisioning workflows.
# ==============================================================================

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for resource naming and configuration
locals {
  random_suffix = random_id.suffix.hex
  
  # Identity Federation configuration
  workload_identity_pool_id     = "enterprise-pool-${local.random_suffix}"
  workload_identity_provider_id = "oidc-provider-${local.random_suffix}"
  
  # Service accounts
  federation_sa_name = "federation-sa-${local.random_suffix}"
  read_only_sa_name  = "read-only-sa-${local.random_suffix}"
  admin_sa_name      = "admin-sa-${local.random_suffix}"
  
  # Service Directory
  namespace_name = "enterprise-services-${local.random_suffix}"
  
  # Cloud Function
  function_name = "identity-provisioner-${local.random_suffix}"
  
  # DNS
  dns_zone_name = "enterprise-services-${local.random_suffix}"
  
  # Secret names
  federation_config_secret = "federation-config-${local.random_suffix}"
  idp_config_secret       = "idp-config-${local.random_suffix}"
  
  # Common tags for all resources
  common_labels = {
    environment = var.environment
    purpose     = "enterprise-identity-federation"
    managed_by  = "terraform"
    project     = var.project_id
  }
}

# ==============================================================================
# API SERVICES
# ==============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "servicedirectory.googleapis.com",
    "cloudfunctions.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "dns.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "eventarc.googleapis.com"
  ])
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# ==============================================================================
# WORKLOAD IDENTITY FEDERATION
# ==============================================================================

# Create Workload Identity Pool for Enterprise Federation
resource "google_iam_workload_identity_pool" "enterprise_pool" {
  workload_identity_pool_id = local.workload_identity_pool_id
  display_name              = "Enterprise Identity Federation Pool"
  description               = "Enterprise identity federation pool for external workload authentication"
  disabled                  = false
  
  depends_on = [google_project_service.required_apis]
}

# Configure OIDC Provider for External Identity Integration
resource "google_iam_workload_identity_pool_provider" "oidc_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.enterprise_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = local.workload_identity_provider_id
  display_name                       = "Enterprise OIDC Provider"
  description                        = "OIDC identity pool provider for external identity federation"
  disabled                           = false
  
  # Attribute mapping for identity token claims
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
    "attribute.audience"   = "assertion.aud"
  }
  
  # Conditional access based on external identity attributes
  attribute_condition = var.oidc_attribute_condition
  
  oidc {
    issuer_uri        = var.oidc_issuer_uri
    allowed_audiences = var.oidc_allowed_audiences
  }
  
  depends_on = [google_iam_workload_identity_pool.enterprise_pool]
}

# ==============================================================================
# SERVICE ACCOUNTS
# ==============================================================================

# Main service account for federated access
resource "google_service_account" "federation_sa" {
  account_id   = local.federation_sa_name
  display_name = "Federation Service Account"
  description  = "Service account for identity federation operations"
  project      = var.project_id
}

# Read-only service account for limited access
resource "google_service_account" "read_only_sa" {
  account_id   = local.read_only_sa_name
  display_name = "Read-Only Service Account"
  description  = "Read-only access for federated identities"
  project      = var.project_id
}

# Administrative service account for elevated access
resource "google_service_account" "admin_sa" {
  account_id   = local.admin_sa_name
  display_name = "Admin Service Account"
  description  = "Administrative access for federated identities"
  project      = var.project_id
}

# Service account for Cloud Function execution
resource "google_service_account" "function_sa" {
  account_id   = "cf-identity-provisioner-${local.random_suffix}"
  display_name = "Cloud Function Service Account"
  description  = "Service account for identity provisioning Cloud Function"
  project      = var.project_id
}

# ==============================================================================
# IAM BINDINGS FOR WORKLOAD IDENTITY FEDERATION
# ==============================================================================

# Allow federated identities to impersonate the main service account
resource "google_service_account_iam_binding" "federation_sa_workload_identity" {
  service_account_id = google_service_account.federation_sa.name
  role              = "roles/iam.workloadIdentityUser"
  
  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.enterprise_pool.name}/attribute.repository/${var.project_id}"
  ]
}

# Grant service account permissions for Service Directory operations
resource "google_project_iam_member" "federation_sa_service_directory" {
  project = var.project_id
  role    = "roles/servicedirectory.editor"
  member  = "serviceAccount:${google_service_account.federation_sa.email}"
}

# Grant service account permissions for Secret Manager access
resource "google_project_iam_member" "federation_sa_secret_manager" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.federation_sa.email}"
}

# Grant Cloud Function service account necessary permissions
resource "google_project_iam_member" "function_sa_secret_manager" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_service_directory" {
  project = var.project_id
  role    = "roles/servicedirectory.editor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_iam_viewer" {
  project = var.project_id
  role    = "roles/iam.serviceAccountViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# ==============================================================================
# SERVICE DIRECTORY
# ==============================================================================

# Create Service Directory namespace for enterprise services
resource "google_service_directory_namespace" "enterprise_namespace" {
  provider     = google-beta
  namespace_id = local.namespace_name
  location     = var.region
  
  labels = merge(local.common_labels, {
    component = "service-discovery"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create enterprise services in the namespace
resource "google_service_directory_service" "user_management" {
  provider   = google-beta
  service_id = "user-management"
  namespace  = google_service_directory_namespace.enterprise_namespace.id
  
  metadata = {
    version     = "v1"
    environment = var.environment
    tier        = "production"
    owner       = "identity-team"
  }
}

resource "google_service_directory_service" "identity_provider" {
  provider   = google-beta
  service_id = "identity-provider"
  namespace  = google_service_directory_namespace.enterprise_namespace.id
  
  metadata = {
    version     = "v2"
    environment = var.environment
    tier        = "production"
    owner       = "security-team"
  }
}

resource "google_service_directory_service" "resource_manager" {
  provider   = google-beta
  service_id = "resource-manager"
  namespace  = google_service_directory_namespace.enterprise_namespace.id
  
  metadata = {
    version     = "v1"
    environment = var.environment
    tier        = "production"
    owner       = "platform-team"
  }
}

# ==============================================================================
# SECRET MANAGER
# ==============================================================================

# Create secret for identity federation configuration
resource "google_secret_manager_secret" "federation_config" {
  secret_id = local.federation_config_secret
  
  labels = merge(local.common_labels, {
    component = "identity-federation"
    type      = "configuration"
  })
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

# Store federation configuration data
resource "google_secret_manager_secret_version" "federation_config" {
  secret = google_secret_manager_secret.federation_config.id
  
  secret_data = jsonencode({
    pool_id                = google_iam_workload_identity_pool.enterprise_pool.workload_identity_pool_id
    provider_id            = google_iam_workload_identity_pool_provider.oidc_provider.workload_identity_pool_provider_id
    service_account_email  = google_service_account.federation_sa.email
    namespace              = google_service_directory_namespace.enterprise_namespace.namespace_id
    pool_resource_name     = google_iam_workload_identity_pool.enterprise_pool.name
    provider_resource_name = google_iam_workload_identity_pool_provider.oidc_provider.name
  })
}

# Create secret for external IdP configuration
resource "google_secret_manager_secret" "idp_config" {
  secret_id = local.idp_config_secret
  
  labels = merge(local.common_labels, {
    component = "identity-provider"
    type      = "configuration"
  })
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

# Store external IdP configuration
resource "google_secret_manager_secret_version" "idp_config" {
  secret = google_secret_manager_secret.idp_config.id
  
  secret_data = jsonencode({
    issuer_url     = var.oidc_issuer_uri
    audience       = "sts.googleapis.com"
    allowed_repos  = [var.project_id]
    provider_type  = "oidc"
  })
}

# ==============================================================================
# CLOUD FUNCTION SOURCE CODE PREPARATION
# ==============================================================================

# Create a storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-identity-provisioner-source-${local.random_suffix}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    component = "cloud-function"
    type      = "source-code"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code as a zip file
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/identity-provisioner-${local.random_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id             = var.project_id
      region                = var.region
      federation_config_secret = google_secret_manager_secret.federation_config.secret_id
      idp_config_secret     = google_secret_manager_secret.idp_config.secret_id
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_source/requirements.txt", {})
    filename = "requirements.txt"
  }
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "identity-provisioner-${local.random_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# ==============================================================================
# CLOUD FUNCTION FOR AUTOMATED IDENTITY PROVISIONING
# ==============================================================================

# Deploy Cloud Function for automated identity provisioning
resource "google_cloudfunctions2_function" "identity_provisioner" {
  name        = local.function_name
  location    = var.region
  description = "Automated identity provisioning workflow for enterprise federation"
  
  labels = merge(local.common_labels, {
    component = "identity-provisioning"
    type      = "automation"
  })
  
  build_config {
    runtime     = "python311"
    entry_point = "provision_identity"
    
    environment_variables = {
      FUNCTION_SOURCE = "terraform"
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      GCP_PROJECT             = var.project_id
      REGION                  = var.region
      FEDERATION_CONFIG_SECRET = google_secret_manager_secret.federation_config.secret_id
      IDP_CONFIG_SECRET       = google_secret_manager_secret.idp_config.secret_id
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_sa_secret_manager,
    google_project_iam_member.function_sa_service_directory,
    google_project_iam_member.function_sa_iam_viewer
  ]
}

# ==============================================================================
# DNS INTEGRATION FOR SERVICE DISCOVERY
# ==============================================================================

# Create private DNS zone for service discovery
resource "google_dns_managed_zone" "enterprise_services" {
  name        = local.dns_zone_name
  dns_name    = "services.${var.project_id}.internal."
  description = "DNS zone for enterprise service discovery"
  visibility  = "private"
  
  private_visibility_config {
    networks {
      network_url = "projects/${var.project_id}/global/networks/default"
    }
  }
  
  labels = merge(local.common_labels, {
    component = "dns"
    type      = "service-discovery"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Configure Service Directory DNS integration
resource "google_service_directory_namespace_iam_binding" "dns_integration" {
  provider = google-beta
  location = var.region
  name     = google_service_directory_namespace.enterprise_namespace.namespace_id
  role     = "roles/servicedirectory.viewer"
  
  members = [
    "serviceAccount:${google_service_account.federation_sa.email}",
    "serviceAccount:${google_service_account.function_sa.email}"
  ]
}

# Create DNS records for service discovery aliases
resource "google_dns_record_set" "user_management_alias" {
  managed_zone = google_dns_managed_zone.enterprise_services.name
  name         = "user-mgmt.services.${var.project_id}.internal."
  type         = "CNAME"
  ttl          = 300
  
  rrdatas = [
    "user-management.${google_service_directory_namespace.enterprise_namespace.namespace_id}.${var.region}.sd.internal."
  ]
}

resource "google_dns_record_set" "identity_provider_alias" {
  managed_zone = google_dns_managed_zone.enterprise_services.name
  name         = "idp.services.${var.project_id}.internal."
  type         = "CNAME"
  ttl          = 300
  
  rrdatas = [
    "identity-provider.${google_service_directory_namespace.enterprise_namespace.namespace_id}.${var.region}.sd.internal."
  ]
}

resource "google_dns_record_set" "resource_manager_alias" {
  managed_zone = google_dns_managed_zone.enterprise_services.name
  name         = "resource-mgmt.services.${var.project_id}.internal."
  type         = "CNAME"
  ttl          = 300
  
  rrdatas = [
    "resource-manager.${google_service_directory_namespace.enterprise_namespace.namespace_id}.${var.region}.sd.internal."
  ]
}

# ==============================================================================
# ADDITIONAL IAM BINDINGS FOR COMPREHENSIVE ACCESS CONTROL
# ==============================================================================

# Grant different access levels based on service account tiers
resource "google_project_iam_member" "read_only_sa_permissions" {
  for_each = toset([
    "roles/viewer",
    "roles/servicedirectory.viewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.read_only_sa.email}"
}

resource "google_project_iam_member" "admin_sa_permissions" {
  for_each = toset([
    "roles/editor",
    "roles/servicedirectory.admin",
    "roles/secretmanager.admin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.admin_sa.email}"
}

# ==============================================================================
# CLOUD STORAGE BUCKET FOR ENTERPRISE RESOURCES
# ==============================================================================

# Create a bucket for storing enterprise identity artifacts
resource "google_storage_bucket" "enterprise_artifacts" {
  name                        = "${var.project_id}-enterprise-identity-artifacts-${local.random_suffix}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  labels = merge(local.common_labels, {
    component = "storage"
    type      = "enterprise-artifacts"
  })
}

# Grant appropriate access to the enterprise artifacts bucket
resource "google_storage_bucket_iam_member" "federation_sa_artifacts_access" {
  bucket = google_storage_bucket.enterprise_artifacts.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.federation_sa.email}"
}

# ==============================================================================
# MONITORING AND LOGGING
# ==============================================================================

# Create a notification channel for alerts (if monitoring is enabled)
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Enterprise Identity Federation Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.monitoring_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alert policy for Cloud Function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Identity Provisioner Function Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\""
      comparison     = "COMPARISON_GT"
      threshold_value = 0.1
      duration       = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  depends_on = [google_cloudfunctions2_function.identity_provisioner]
}