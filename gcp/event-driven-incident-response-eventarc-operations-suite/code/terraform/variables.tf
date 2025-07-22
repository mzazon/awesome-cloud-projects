# Variables for Event-Driven Incident Response System
# This file defines all configurable parameters for the infrastructure

# Project Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name for resource labeling and naming"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Resource Naming Configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "incident-response"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix" {
  description = "Random suffix to append to resource names for uniqueness"
  type        = string
  default     = null
}

# Cloud Functions Configuration
variable "triage_function_config" {
  description = "Configuration for the incident triage Cloud Function"
  type = object({
    name               = string
    runtime            = string
    entry_point        = string
    memory_mb          = number
    timeout_seconds    = number
    max_instances      = number
    min_instances      = number
    available_cpu      = string
    environment_variables = map(string)
  })
  
  default = {
    name               = "incident-triage"
    runtime            = "python311"
    entry_point        = "triage_incident"
    memory_mb          = 512
    timeout_seconds    = 540
    max_instances      = 100
    min_instances      = 0
    available_cpu      = "1"
    environment_variables = {}
  }
}

variable "notification_function_config" {
  description = "Configuration for the notification Cloud Function"
  type = object({
    name               = string
    runtime            = string
    entry_point        = string
    memory_mb          = number
    timeout_seconds    = number
    max_instances      = number
    min_instances      = number
    available_cpu      = string
    environment_variables = map(string)
  })
  
  default = {
    name               = "incident-notify"
    runtime            = "python311"
    entry_point        = "send_notifications"
    memory_mb          = 256
    timeout_seconds    = 300
    max_instances      = 50
    min_instances      = 0
    available_cpu      = "1"
    environment_variables = {}
  }
}

# Cloud Run Configuration
variable "remediation_service_config" {
  description = "Configuration for the remediation Cloud Run service"
  type = object({
    name              = string
    image             = string
    cpu               = string
    memory            = string
    timeout_seconds   = number
    max_instances     = number
    min_instances     = number
    port              = number
    environment_variables = map(string)
  })
  
  default = {
    name              = "incident-remediate"
    image             = "us-central1-docker.pkg.dev/PROJECT_ID/incident-response/remediation:latest"
    cpu               = "1"
    memory            = "1Gi"
    timeout_seconds   = 900
    max_instances     = 100
    min_instances     = 0
    port              = 8080
    environment_variables = {}
  }
}

variable "escalation_service_config" {
  description = "Configuration for the escalation Cloud Run service"
  type = object({
    name              = string
    image             = string
    cpu               = string
    memory            = string
    timeout_seconds   = number
    max_instances     = number
    min_instances     = number
    port              = number
    environment_variables = map(string)
  })
  
  default = {
    name              = "incident-escalate"
    image             = "us-central1-docker.pkg.dev/PROJECT_ID/incident-response/escalation:latest"
    cpu               = "1"
    memory            = "512Mi"
    timeout_seconds   = 600
    max_instances     = 50
    min_instances     = 0
    port              = 8080
    environment_variables = {}
  }
}

# Pub/Sub Configuration
variable "pubsub_topics" {
  description = "Configuration for Pub/Sub topics used in the incident response system"
  type = map(object({
    name                         = string
    message_retention_duration   = string
    message_storage_policy_regions = list(string)
    schema_type                  = string
    schema_definition            = string
  }))
  
  default = {
    incident_alerts = {
      name                         = "incident-alerts"
      message_retention_duration   = "86400s"  # 24 hours
      message_storage_policy_regions = []
      schema_type                  = ""
      schema_definition            = ""
    }
    remediation = {
      name                         = "remediation-topic"
      message_retention_duration   = "86400s"
      message_storage_policy_regions = []
      schema_type                  = ""
      schema_definition            = ""
    }
    escalation = {
      name                         = "escalation-topic"
      message_retention_duration   = "86400s"
      message_storage_policy_regions = []
      schema_type                  = ""
      schema_definition            = ""
    }
    notification = {
      name                         = "notification-topic"
      message_retention_duration   = "86400s"
      message_storage_policy_regions = []
      schema_type                  = ""
      schema_definition            = ""
    }
  }
}

# Cloud Storage Configuration
variable "source_bucket_config" {
  description = "Configuration for the source code storage bucket"
  type = object({
    name                     = string
    location                 = string
    storage_class            = string
    uniform_bucket_level_access = bool
    versioning_enabled       = bool
    lifecycle_rules          = list(object({
      condition = object({
        age = number
      })
      action = object({
        type = string
      })
    }))
  })
  
  default = {
    name                     = "incident-response-source"
    location                 = "US"
    storage_class            = "STANDARD"
    uniform_bucket_level_access = true
    versioning_enabled       = true
    lifecycle_rules = [
      {
        condition = {
          age = 30
        }
        action = {
          type = "Delete"
        }
      }
    ]
  }
}

# Monitoring Configuration
variable "monitoring_config" {
  description = "Configuration for Cloud Monitoring alerts and notification channels"
  type = object({
    enabled = bool
    alert_policies = map(object({
      display_name = string
      combiner     = string
      conditions = list(object({
        display_name = string
        condition_threshold = object({
          filter          = string
          duration        = string
          comparison      = string
          threshold_value = number
          aggregations = list(object({
            alignment_period     = string
            per_series_aligner  = string
            cross_series_reducer = string
            group_by_fields     = list(string)
          }))
        })
      }))
      notification_channels = list(string)
      alert_strategy = object({
        auto_close = string
      })
    }))
    notification_channels = map(object({
      display_name = string
      type         = string
      labels       = map(string)
      description  = string
    }))
  })
  
  default = {
    enabled = true
    alert_policies = {
      high_cpu = {
        display_name = "High CPU Utilization Alert"
        combiner     = "OR"
        conditions = [
          {
            display_name = "CPU utilization is high"
            condition_threshold = {
              filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
              duration        = "300s"
              comparison      = "COMPARISON_GT"
              threshold_value = 0.8
              aggregations = [
                {
                  alignment_period     = "60s"
                  per_series_aligner  = "ALIGN_MEAN"
                  cross_series_reducer = "REDUCE_MEAN"
                  group_by_fields     = ["project", "resource.label.instance_id"]
                }
              ]
            }
          }
        ]
        notification_channels = []
        alert_strategy = {
          auto_close = "1800s"
        }
      }
      high_error_rate = {
        display_name = "High Error Rate Alert"
        combiner     = "OR"
        conditions = [
          {
            display_name = "Error rate is high"
            condition_threshold = {
              filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\""
              duration        = "600s"
              comparison      = "COMPARISON_GT"
              threshold_value = 0.05
              aggregations = [
                {
                  alignment_period     = "300s"
                  per_series_aligner  = "ALIGN_RATE"
                  cross_series_reducer = "REDUCE_MEAN"
                  group_by_fields     = ["resource.label.service_name"]
                }
              ]
            }
          }
        ]
        notification_channels = []
        alert_strategy = {
          auto_close = "3600s"
        }
      }
    }
    notification_channels = {
      email = {
        display_name = "Email Notification Channel"
        type         = "email"
        labels       = {}
        description  = "Email notifications for incident alerts"
      }
    }
  }
}

# IAM Configuration
variable "iam_config" {
  description = "Configuration for IAM service accounts and roles"
  type = object({
    service_account_name = string
    roles = list(string)
    custom_roles = map(object({
      title       = string
      description = string
      permissions = list(string)
    }))
  })
  
  default = {
    service_account_name = "incident-response-sa"
    roles = [
      "roles/monitoring.viewer",
      "roles/compute.instanceAdmin.v1",
      "roles/pubsub.publisher",
      "roles/pubsub.subscriber",
      "roles/logging.logWriter",
      "roles/cloudsql.client",
      "roles/run.invoker",
      "roles/cloudfunctions.invoker",
      "roles/eventarc.eventReceiver"
    ]
    custom_roles = {}
  }
}

# Network Configuration
variable "network_config" {
  description = "Network configuration for VPC and firewall rules"
  type = object({
    create_vpc = bool
    vpc_name   = string
    subnet_config = object({
      name          = string
      ip_cidr_range = string
      region        = string
    })
    firewall_rules = list(object({
      name      = string
      direction = string
      priority  = number
      ranges    = list(string)
      ports     = list(string)
      protocols = list(string)
    }))
  })
  
  default = {
    create_vpc = false
    vpc_name   = "default"
    subnet_config = {
      name          = "incident-response-subnet"
      ip_cidr_range = "10.0.0.0/24"
      region        = "us-central1"
    }
    firewall_rules = [
      {
        name      = "allow-incident-response"
        direction = "INGRESS"
        priority  = 1000
        ranges    = ["0.0.0.0/0"]
        ports     = ["8080", "80", "443"]
        protocols = ["tcp"]
      }
    ]
  }
}

# Eventarc Configuration
variable "eventarc_config" {
  description = "Configuration for Eventarc triggers"
  type = object({
    enabled = bool
    triggers = map(object({
      name                  = string
      location              = string
      event_filters         = list(object({
        attribute = string
        value     = string
      }))
      destination_type      = string
      destination_service   = string
      transport_topic       = string
      service_account_email = string
    }))
  })
  
  default = {
    enabled = true
    triggers = {
      monitoring_alert = {
        name     = "monitoring-alert-trigger"
        location = "us-central1"
        event_filters = [
          {
            attribute = "type"
            value     = "google.cloud.monitoring.alert.v1.opened"
          }
        ]
        destination_type      = "cloud_function"
        destination_service   = "incident-triage"
        transport_topic       = ""
        service_account_email = ""
      }
      remediation = {
        name     = "remediation-trigger"
        location = "us-central1"
        event_filters = [
          {
            attribute = "type"
            value     = "google.cloud.pubsub.topic.v1.messagePublished"
          }
        ]
        destination_type      = "cloud_run"
        destination_service   = "incident-remediate"
        transport_topic       = "remediation-topic"
        service_account_email = ""
      }
      escalation = {
        name     = "escalation-trigger"
        location = "us-central1"
        event_filters = [
          {
            attribute = "type"
            value     = "google.cloud.pubsub.topic.v1.messagePublished"
          }
        ]
        destination_type      = "cloud_run"
        destination_service   = "incident-escalate"
        transport_topic       = "escalation-topic"
        service_account_email = ""
      }
    }
  }
}

# API Services Configuration
variable "api_services" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "eventarc.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "secretmanager.googleapis.com"
  ]
}

# Tags Configuration
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    terraform   = "true"
    recipe      = "event-driven-incident-response"
    managed-by  = "terraform"
  }
}