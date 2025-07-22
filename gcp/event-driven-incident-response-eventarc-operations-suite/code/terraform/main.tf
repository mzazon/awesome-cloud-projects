# Event-Driven Incident Response System
# This Terraform configuration deploys a complete incident response system using
# Eventarc, Cloud Functions, Cloud Run, and Cloud Operations Suite

# Local values for resource naming and configuration
locals {
  # Generate random suffix if not provided
  random_suffix = var.random_suffix != null ? var.random_suffix : random_string.suffix.result
  
  # Resource naming with prefix and suffix
  resource_names = {
    triage_function      = "${var.resource_prefix}-${var.triage_function_config.name}-${local.random_suffix}"
    notification_function = "${var.resource_prefix}-${var.notification_function_config.name}-${local.random_suffix}"
    remediation_service  = "${var.resource_prefix}-${var.remediation_service_config.name}-${local.random_suffix}"
    escalation_service   = "${var.resource_prefix}-${var.escalation_service_config.name}-${local.random_suffix}"
    service_account     = "${var.resource_prefix}-${var.iam_config.service_account_name}-${local.random_suffix}"
    source_bucket       = "${var.resource_prefix}-${var.source_bucket_config.name}-${local.random_suffix}"
  }
  
  # Common labels for all resources
  common_labels = merge(var.tags, {
    environment = var.environment
    component   = "incident-response"
    created-by  = "terraform"
    recipe      = "event-driven-incident-response"
  })
  
  # Project-specific image URLs
  remediation_image = replace(var.remediation_service_config.image, "PROJECT_ID", var.project_id)
  escalation_image  = replace(var.escalation_service_config.image, "PROJECT_ID", var.project_id)
}

# Generate random suffix for resource uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.api_services)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create IAM Service Account for incident response automation
resource "google_service_account" "incident_response" {
  account_id   = local.resource_names.service_account
  display_name = "Incident Response Service Account"
  description  = "Service account for automated incident response system"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# Assign IAM roles to the service account
resource "google_project_iam_member" "incident_response_roles" {
  for_each = toset(var.iam_config.roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.incident_response.email}"
  
  depends_on = [google_service_account.incident_response]
}

# Create Cloud Storage bucket for source code
resource "google_storage_bucket" "source_bucket" {
  name          = local.resource_names.source_bucket
  location      = var.source_bucket_config.location
  project       = var.project_id
  storage_class = var.source_bucket_config.storage_class
  
  uniform_bucket_level_access = var.source_bucket_config.uniform_bucket_level_access
  
  dynamic "versioning" {
    for_each = var.source_bucket_config.versioning_enabled ? [1] : []
    content {
      enabled = true
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.source_bucket_config.lifecycle_rules
    content {
      condition {
        age = lifecycle_rule.value.condition.age
      }
      action {
        type = lifecycle_rule.value.action.type
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create Pub/Sub topics for event routing
resource "google_pubsub_topic" "incident_topics" {
  for_each = var.pubsub_topics
  
  name    = "${var.resource_prefix}-${each.value.name}-${local.random_suffix}"
  project = var.project_id
  
  message_retention_duration = each.value.message_retention_duration
  
  dynamic "message_storage_policy" {
    for_each = length(each.value.message_storage_policy_regions) > 0 ? [1] : []
    content {
      allowed_persistence_regions = each.value.message_storage_policy_regions
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create source code archives for Cloud Functions
data "archive_file" "triage_function_source" {
  type        = "zip"
  output_path = "${path.module}/triage_function_source.zip"
  
  source {
    content = file("${path.module}/function_code/triage/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/triage/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "notification_function_source" {
  type        = "zip"
  output_path = "${path.module}/notification_function_source.zip"
  
  source {
    content = file("${path.module}/function_code/notification/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/notification/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "triage_function_source" {
  name         = "triage_function_source_${data.archive_file.triage_function_source.output_md5}.zip"
  bucket       = google_storage_bucket.source_bucket.name
  source       = data.archive_file.triage_function_source.output_path
  content_type = "application/zip"
  
  depends_on = [google_storage_bucket.source_bucket]
}

resource "google_storage_bucket_object" "notification_function_source" {
  name         = "notification_function_source_${data.archive_file.notification_function_source.output_md5}.zip"
  bucket       = google_storage_bucket.source_bucket.name
  source       = data.archive_file.notification_function_source.output_path
  content_type = "application/zip"
  
  depends_on = [google_storage_bucket.source_bucket]
}

# Create Cloud Function for incident triage
resource "google_cloudfunctions2_function" "triage_function" {
  name        = local.resource_names.triage_function
  location    = var.region
  project     = var.project_id
  description = "Function to triage and analyze incoming monitoring alerts"
  
  build_config {
    runtime     = var.triage_function_config.runtime
    entry_point = var.triage_function_config.entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.triage_function_source.name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
  }
  
  service_config {
    max_instance_count               = var.triage_function_config.max_instances
    min_instance_count               = var.triage_function_config.min_instances
    available_memory                 = "${var.triage_function_config.memory_mb}M"
    timeout_seconds                  = var.triage_function_config.timeout_seconds
    available_cpu                    = var.triage_function_config.available_cpu
    service_account_email            = google_service_account.incident_response.email
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision   = true
    
    environment_variables = merge(var.triage_function_config.environment_variables, {
      GCP_PROJECT = var.project_id
      REGION      = var.region
    })
  }
  
  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.incident_topics["incident_alerts"].id
    retry_policy = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.incident_response.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.incident_response,
    google_storage_bucket_object.triage_function_source,
    google_pubsub_topic.incident_topics
  ]
}

# Create Cloud Function for notifications
resource "google_cloudfunctions2_function" "notification_function" {
  name        = local.resource_names.notification_function
  location    = var.region
  project     = var.project_id
  description = "Function to send incident notifications through multiple channels"
  
  build_config {
    runtime     = var.notification_function_config.runtime
    entry_point = var.notification_function_config.entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.source_bucket.name
        object = google_storage_bucket_object.notification_function_source.name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
  }
  
  service_config {
    max_instance_count               = var.notification_function_config.max_instances
    min_instance_count               = var.notification_function_config.min_instances
    available_memory                 = "${var.notification_function_config.memory_mb}M"
    timeout_seconds                  = var.notification_function_config.timeout_seconds
    available_cpu                    = var.notification_function_config.available_cpu
    service_account_email            = google_service_account.incident_response.email
    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision   = true
    
    environment_variables = merge(var.notification_function_config.environment_variables, {
      GCP_PROJECT = var.project_id
      REGION      = var.region
    })
  }
  
  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.incident_topics["notification"].id
    retry_policy = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.incident_response.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.incident_response,
    google_storage_bucket_object.notification_function_source,
    google_pubsub_topic.incident_topics
  ]
}

# Create Cloud Run service for remediation
resource "google_cloud_run_v2_service" "remediation_service" {
  name     = local.resource_names.remediation_service
  location = var.region
  project  = var.project_id
  
  template {
    service_account = google_service_account.incident_response.email
    
    timeout = "${var.remediation_service_config.timeout_seconds}s"
    
    containers {
      image = local.remediation_image
      
      ports {
        container_port = var.remediation_service_config.port
      }
      
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      
      env {
        name  = "GCP_ZONE"
        value = var.zone
      }
      
      dynamic "env" {
        for_each = var.remediation_service_config.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
      
      resources {
        limits = {
          cpu    = var.remediation_service_config.cpu
          memory = var.remediation_service_config.memory
        }
        
        cpu_idle = true
        startup_cpu_boost = true
      }
    }
    
    scaling {
      min_instance_count = var.remediation_service_config.min_instances
      max_instance_count = var.remediation_service_config.max_instances
    }
    
    annotations = {
      "autoscaling.knative.dev/minScale"        = tostring(var.remediation_service_config.min_instances)
      "autoscaling.knative.dev/maxScale"        = tostring(var.remediation_service_config.max_instances)
      "run.googleapis.com/execution-environment" = "gen2"
    }
  }
  
  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.incident_response
  ]
}

# Create Cloud Run service for escalation
resource "google_cloud_run_v2_service" "escalation_service" {
  name     = local.resource_names.escalation_service
  location = var.region
  project  = var.project_id
  
  template {
    service_account = google_service_account.incident_response.email
    
    timeout = "${var.escalation_service_config.timeout_seconds}s"
    
    containers {
      image = local.escalation_image
      
      ports {
        container_port = var.escalation_service_config.port
      }
      
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "GCP_REGION"
        value = var.region
      }
      
      env {
        name  = "GCP_ZONE"
        value = var.zone
      }
      
      dynamic "env" {
        for_each = var.escalation_service_config.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
      
      resources {
        limits = {
          cpu    = var.escalation_service_config.cpu
          memory = var.escalation_service_config.memory
        }
        
        cpu_idle = true
        startup_cpu_boost = true
      }
    }
    
    scaling {
      min_instance_count = var.escalation_service_config.min_instances
      max_instance_count = var.escalation_service_config.max_instances
    }
    
    annotations = {
      "autoscaling.knative.dev/minScale"        = tostring(var.escalation_service_config.min_instances)
      "autoscaling.knative.dev/maxScale"        = tostring(var.escalation_service_config.max_instances)
      "run.googleapis.com/execution-environment" = "gen2"
    }
  }
  
  ingress = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.incident_response
  ]
}

# Create Eventarc triggers for event routing
resource "google_eventarc_trigger" "monitoring_alert_trigger" {
  count = var.eventarc_config.enabled ? 1 : 0
  
  name     = "${var.resource_prefix}-${var.eventarc_config.triggers.monitoring_alert.name}-${local.random_suffix}"
  location = var.eventarc_config.triggers.monitoring_alert.location
  project  = var.project_id
  
  dynamic "matching_criteria" {
    for_each = var.eventarc_config.triggers.monitoring_alert.event_filters
    content {
      attribute = matching_criteria.value.attribute
      value     = matching_criteria.value.value
    }
  }
  
  destination {
    cloud_function = google_cloudfunctions2_function.triage_function.name
  }
  
  service_account = google_service_account.incident_response.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions2_function.triage_function,
    google_service_account.incident_response
  ]
}

resource "google_eventarc_trigger" "remediation_trigger" {
  count = var.eventarc_config.enabled ? 1 : 0
  
  name     = "${var.resource_prefix}-${var.eventarc_config.triggers.remediation.name}-${local.random_suffix}"
  location = var.eventarc_config.triggers.remediation.location
  project  = var.project_id
  
  dynamic "matching_criteria" {
    for_each = var.eventarc_config.triggers.remediation.event_filters
    content {
      attribute = matching_criteria.value.attribute
      value     = matching_criteria.value.value
    }
  }
  
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.remediation_service.name
      region  = var.region
    }
  }
  
  transport {
    pubsub {
      topic = google_pubsub_topic.incident_topics["remediation"].id
    }
  }
  
  service_account = google_service_account.incident_response.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_cloud_run_v2_service.remediation_service,
    google_pubsub_topic.incident_topics,
    google_service_account.incident_response
  ]
}

resource "google_eventarc_trigger" "escalation_trigger" {
  count = var.eventarc_config.enabled ? 1 : 0
  
  name     = "${var.resource_prefix}-${var.eventarc_config.triggers.escalation.name}-${local.random_suffix}"
  location = var.eventarc_config.triggers.escalation.location
  project  = var.project_id
  
  dynamic "matching_criteria" {
    for_each = var.eventarc_config.triggers.escalation.event_filters
    content {
      attribute = matching_criteria.value.attribute
      value     = matching_criteria.value.value
    }
  }
  
  destination {
    cloud_run_service {
      service = google_cloud_run_v2_service.escalation_service.name
      region  = var.region
    }
  }
  
  transport {
    pubsub {
      topic = google_pubsub_topic.incident_topics["escalation"].id
    }
  }
  
  service_account = google_service_account.incident_response.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_cloud_run_v2_service.escalation_service,
    google_pubsub_topic.incident_topics,
    google_service_account.incident_response
  ]
}

# Create Cloud Monitoring notification channels
resource "google_monitoring_notification_channel" "notification_channels" {
  for_each = var.monitoring_config.enabled ? var.monitoring_config.notification_channels : {}
  
  display_name = each.value.display_name
  type         = each.value.type
  project      = var.project_id
  
  labels = each.value.labels
  
  description = each.value.description
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Monitoring alert policies
resource "google_monitoring_alert_policy" "alert_policies" {
  for_each = var.monitoring_config.enabled ? var.monitoring_config.alert_policies : {}
  
  display_name = each.value.display_name
  combiner     = each.value.combiner
  project      = var.project_id
  
  dynamic "conditions" {
    for_each = each.value.conditions
    content {
      display_name = conditions.value.display_name
      
      condition_threshold {
        filter          = conditions.value.condition_threshold.filter
        duration        = conditions.value.condition_threshold.duration
        comparison      = conditions.value.condition_threshold.comparison
        threshold_value = conditions.value.condition_threshold.threshold_value
        
        dynamic "aggregations" {
          for_each = conditions.value.condition_threshold.aggregations
          content {
            alignment_period     = aggregations.value.alignment_period
            per_series_aligner   = aggregations.value.per_series_aligner
            cross_series_reducer = aggregations.value.cross_series_reducer
            group_by_fields      = aggregations.value.group_by_fields
          }
        }
      }
    }
  }
  
  notification_channels = [
    for channel_key in each.value.notification_channels :
    google_monitoring_notification_channel.notification_channels[channel_key].name
  ]
  
  alert_strategy {
    auto_close = each.value.alert_strategy.auto_close
  }
  
  depends_on = [
    google_project_service.apis,
    google_monitoring_notification_channel.notification_channels
  ]
}

# Create IAM binding for Eventarc to invoke Cloud Run services
resource "google_cloud_run_service_iam_binding" "remediation_invoker" {
  location = google_cloud_run_v2_service.remediation_service.location
  service  = google_cloud_run_v2_service.remediation_service.name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.incident_response.email}"
  ]
}

resource "google_cloud_run_service_iam_binding" "escalation_invoker" {
  location = google_cloud_run_v2_service.escalation_service.location
  service  = google_cloud_run_v2_service.escalation_service.name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.incident_response.email}"
  ]
}

# Create IAM binding for Eventarc to invoke Cloud Functions
resource "google_cloudfunctions2_function_iam_binding" "triage_invoker" {
  location      = google_cloudfunctions2_function.triage_function.location
  cloud_function = google_cloudfunctions2_function.triage_function.name
  role          = "roles/cloudfunctions.invoker"
  members = [
    "serviceAccount:${google_service_account.incident_response.email}"
  ]
}

resource "google_cloudfunctions2_function_iam_binding" "notification_invoker" {
  location      = google_cloudfunctions2_function.notification_function.location
  cloud_function = google_cloudfunctions2_function.notification_function.name
  role          = "roles/cloudfunctions.invoker"
  members = [
    "serviceAccount:${google_service_account.incident_response.email}"
  ]
}