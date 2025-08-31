# Main Terraform configuration for GCP DNS threat detection with Cloud Armor and Security Center

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
  })
  
  # Pub/Sub topic and subscription names
  pubsub_topic_name        = "${var.resource_prefix}-alerts-${local.resource_suffix}"
  pubsub_subscription_name = "${var.resource_prefix}-processor-${local.resource_suffix}"
  
  # DNS zone and policy names
  dns_zone_name   = "security-zone-${local.resource_suffix}"
  dns_policy_name = "${var.resource_prefix}-policy-${local.resource_suffix}"
  
  # Security policy names
  cloud_armor_policy_name = "${var.resource_prefix}-protection-${local.resource_suffix}"
  scc_notification_name   = "${var.resource_prefix}-export-${local.resource_suffix}"
  
  # Cloud Function configuration
  function_name    = "${var.resource_prefix}-processor"
  function_zip     = "function-source.zip"
  
  # Monitoring resources
  log_metric_name = "dns_malware_queries"
  alert_policy_name = "DNS Threat Detection Alert"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
    "logging.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "securitycenter.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Get the default VPC network
data "google_compute_network" "default" {
  name = "default"
  
  depends_on = [google_project_service.required_apis]
}

# DNS Policy with logging enabled for security monitoring
resource "google_dns_policy" "security_policy" {
  count = var.enable_dns_logging ? 1 : 0
  
  name                      = local.dns_policy_name
  description               = "DNS policy with security logging enabled for threat detection"
  enable_inbound_forwarding = false
  enable_logging            = true
  
  networks {
    network_url = data.google_compute_network.default.self_link
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# DNS Managed Zone for demonstration and monitoring
resource "google_dns_managed_zone" "security_zone" {
  name        = local.dns_zone_name
  dns_name    = var.dns_zone_name
  description = "Security monitoring DNS zone for threat detection"
  visibility  = "private"
  
  private_visibility_config {
    networks {
      network_url = data.google_compute_network.default.self_link
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Armor Security Policy for DNS protection
resource "google_compute_security_policy" "dns_protection" {
  count = var.enable_cloud_armor ? 1 : 0
  
  name        = local.cloud_armor_policy_name
  description = "DNS threat protection policy with rate limiting and geo-blocking"
  
  # Default rule - allow all traffic that doesn't match other rules
  rule {
    action   = "allow"
    priority = "2147483647"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    description = "Default allow rule"
  }
  
  # Rate limiting rule for DNS queries
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      
      rate_limit_threshold {
        count        = var.rate_limit_threshold
        interval_sec = 60
      }
      
      ban_duration_sec = var.rate_limit_ban_duration
    }
    
    description = "Rate limit DNS queries to prevent amplification attacks"
  }
  
  # Geo-blocking rule for high-risk countries
  rule {
    action   = "deny(403)"
    priority = "2000"
    
    match {
      expr {
        expression = "origin.region_code in [${join(",", [for country in var.high_risk_countries : "\"${country}\""])}]"
      }
    }
    
    description = "Block traffic from high-risk geographic regions"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for Security Command Center findings
resource "google_pubsub_topic" "security_alerts" {
  name = local.pubsub_topic_name
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for Cloud Function processing
resource "google_pubsub_subscription" "alert_processor" {
  name  = local.pubsub_subscription_name
  topic = google_pubsub_topic.security_alerts.name
  
  ack_deadline_seconds = var.pubsub_ack_deadline
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy for persistently failing messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.security_alerts.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Function
resource "google_service_account" "function_sa" {
  count = var.enable_automated_response ? 1 : 0
  
  account_id   = "${var.resource_prefix}-function-sa"
  display_name = "DNS Security Function Service Account"
  description  = "Service account for DNS threat detection Cloud Function"
}

# IAM binding for Cloud Function service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = var.enable_automated_response ? toset([
    "roles/logging.logWriter",
    "roles/pubsub.subscriber",
    "roles/securitycenter.findingsViewer",
    "roles/compute.securityAdmin",
    "roles/monitoring.metricWriter"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa[0].email}"
  
  depends_on = [google_service_account.function_sa]
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  count = var.enable_automated_response ? 1 : 0
  
  type        = "zip"
  output_path = local.function_zip
  
  source {
    content = templatefile("${path.module}/function/main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  count = var.enable_automated_response ? 1 : 0
  
  name     = "${var.project_id}-function-source-${local.resource_suffix}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  count = var.enable_automated_response ? 1 : 0
  
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source[0].name
  source = data.archive_file.function_source[0].output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for automated threat response
resource "google_cloudfunctions_function" "dns_security_processor" {
  count = var.enable_automated_response ? 1 : 0
  
  name        = local.function_name
  description = "Automated DNS threat detection and response processor"
  runtime     = "python312"
  region      = var.region
  
  available_memory_mb   = var.cloud_function_memory
  timeout               = var.cloud_function_timeout
  entry_point          = "process_security_finding"
  service_account_email = google_service_account.function_sa[0].email
  
  source_archive_bucket = google_storage_bucket.function_source[0].name
  source_archive_object = google_storage_bucket_object.function_source[0].name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.security_alerts.name
  }
  
  environment_variables = {
    PROJECT_ID              = var.project_id
    SECURITY_POLICY_NAME    = var.enable_cloud_armor ? google_compute_security_policy.dns_protection[0].name : ""
    LOG_LEVEL               = "INFO"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles,
    google_storage_bucket_object.function_source
  ]
}

# Security Command Center notification configuration
resource "google_scc_notification_config" "dns_threat_export" {
  count = var.enable_security_center_premium ? 1 : 0
  
  config_id    = local.scc_notification_name
  organization = var.organization_id
  description  = "Export DNS threat findings to Pub/Sub for automated processing"
  pubsub_topic = google_pubsub_topic.security_alerts.id
  
  streaming_config {
    filter = <<-EOT
      category:"Malware: Bad Domain" OR 
      category:"Malware: Bad IP" OR 
      category:"DNS" OR 
      finding_class="THREAT"
    EOT
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log-based metric for DNS malware queries
resource "google_logging_metric" "dns_malware_queries" {
  name   = local.log_metric_name
  filter = <<-EOT
    resource.type="dns_query" AND (
      jsonPayload.queryName:("malware" OR "botnet" OR "c2" OR "malicious") OR 
      jsonPayload.responseCode>=300
    )
  EOT
  
  description = "Count of malware-related DNS queries for threat detection"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "DNS Malware Queries"
  }
  
  label_extractors = {
    "query_name" = "EXTRACT(jsonPayload.queryName)"
    "client_ip"  = "EXTRACT(jsonPayload.sourceIP)"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring alert policy for DNS threats
resource "google_monitoring_alert_policy" "dns_threat_alert" {
  display_name = local.alert_policy_name
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Malware DNS Query Rate"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${local.log_metric_name}\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.monitoring_alert_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  documentation {
    content   = "Alert triggered when malware-related DNS queries exceed threshold"
    mime_type = "text/markdown"
  }
  
  # Auto-close alerts after 24 hours
  alert_strategy {
    auto_close = "86400s"
  }
  
  # Add notification channels if email is provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  user_labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.dns_malware_queries
  ]
}

# Email notification channel (optional)
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "DNS Security Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  user_labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for Security Command Center to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  count = var.enable_security_center_premium ? 1 : 0
  
  topic  = google_pubsub_topic.security_alerts.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-securitycenter.iam.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}