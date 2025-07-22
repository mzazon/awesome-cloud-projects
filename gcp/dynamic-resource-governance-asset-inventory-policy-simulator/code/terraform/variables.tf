# Variables for Dynamic Resource Governance Infrastructure
# This file defines all configurable parameters for the governance system

# Project Configuration
variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]){4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a, europe-west1-b)."
  }
}

# Resource Naming Configuration
variable "environment" {
  description = "Environment name for resource naming (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.environment))
    error_message = "Environment must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "governance"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Asset Inventory Configuration
variable "asset_feed_name" {
  description = "Name for the Cloud Asset Inventory feed"
  type        = string
  default     = "governance-feed"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.asset_feed_name))
    error_message = "Asset feed name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "asset_types" {
  description = "List of asset types to monitor (use '*' for all types)"
  type        = list(string)
  default     = ["*"]
}

variable "asset_content_type" {
  description = "Content type for asset feed (RESOURCE, IAM_POLICY, or ORG_POLICY)"
  type        = string
  default     = "RESOURCE"
  validation {
    condition     = contains(["RESOURCE", "IAM_POLICY", "ORG_POLICY"], var.asset_content_type)
    error_message = "Asset content type must be one of: RESOURCE, IAM_POLICY, or ORG_POLICY."
  }
}

# Pub/Sub Configuration
variable "pubsub_topic_name" {
  description = "Name for the Pub/Sub topic for asset change notifications"
  type        = string
  default     = "asset-changes"
}

variable "pubsub_subscription_name" {
  description = "Name for the Pub/Sub subscription for compliance processing"
  type        = string
  default     = "compliance-subscription"
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgment deadline for Pub/Sub messages in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Acknowledgment deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_message_retention" {
  description = "Message retention duration for Pub/Sub topic"
  type        = string
  default     = "1209600s" # 14 days
}

# Cloud Functions Configuration
variable "functions_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python38", "python39", "python310", "python311", "python312",
      "nodejs16", "nodejs18", "nodejs20",
      "go116", "go118", "go119", "go120", "go121",
      "java11", "java17", "java21"
    ], var.functions_runtime)
    error_message = "Runtime must be a supported Cloud Functions runtime version."
  }
}

variable "asset_analyzer_config" {
  description = "Configuration for the asset analyzer function"
  type = object({
    memory_mb          = number
    timeout_seconds    = number
    max_instances      = number
    min_instances      = number
    cpu                = string
    ingress_settings   = string
    egress_settings    = string
  })
  default = {
    memory_mb          = 512
    timeout_seconds    = 300
    max_instances      = 100
    min_instances      = 0
    cpu                = "1"
    ingress_settings   = "ALLOW_INTERNAL_ONLY"
    egress_settings    = "PRIVATE_RANGES_ONLY"
  }
}

variable "policy_validator_config" {
  description = "Configuration for the policy validator function"
  type = object({
    memory_mb          = number
    timeout_seconds    = number
    max_instances      = number
    min_instances      = number
    cpu                = string
    ingress_settings   = string
    egress_settings    = string
  })
  default = {
    memory_mb          = 1024
    timeout_seconds    = 540
    max_instances      = 50
    min_instances      = 0
    cpu                = "1"
    ingress_settings   = "ALLOW_ALL"
    egress_settings    = "ALLOW_ALL"
  }
}

variable "compliance_engine_config" {
  description = "Configuration for the compliance engine function"
  type = object({
    memory_mb          = number
    timeout_seconds    = number
    max_instances      = number
    min_instances      = number
    cpu                = string
    ingress_settings   = string
    egress_settings    = string
  })
  default = {
    memory_mb          = 1024
    timeout_seconds    = 540
    max_instances      = 100
    min_instances      = 1
    cpu                = "1"
    ingress_settings   = "ALLOW_INTERNAL_ONLY"
    egress_settings    = "ALLOW_ALL"
  }
}

# Service Account Configuration
variable "service_account_name" {
  description = "Name for the governance automation service account"
  type        = string
  default     = "governance-automation"
}

variable "service_account_display_name" {
  description = "Display name for the governance automation service account"
  type        = string
  default     = "Governance Automation Service Account"
}

# IAM Roles Configuration
variable "governance_roles" {
  description = "List of IAM roles to assign to the governance service account"
  type        = list(string)
  default = [
    "roles/cloudasset.viewer",
    "roles/iam.securityReviewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber"
  ]
}

# API Services Configuration
variable "required_apis" {
  description = "List of Google Cloud APIs required for the governance system"
  type        = list(string)
  default = [
    "cloudasset.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "policysimulator.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ]
}

# Monitoring and Alerting Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting for the governance system"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for governance alerts"
  type        = list(string)
  default     = []
}

# Compliance Configuration
variable "high_risk_asset_types" {
  description = "List of asset types considered high risk for compliance"
  type        = list(string)
  default = [
    "compute.googleapis.com/Instance",
    "storage.googleapis.com/Bucket",
    "iam.googleapis.com/ServiceAccount",
    "container.googleapis.com/Cluster",
    "sqladmin.googleapis.com/Instance"
  ]
}

variable "compliance_policies" {
  description = "Map of compliance policies and their configurations"
  type = map(object({
    enabled        = bool
    risk_level     = string
    auto_remediate = bool
    alert_channels = list(string)
  }))
  default = {
    "public-storage-bucket" = {
      enabled        = true
      risk_level     = "HIGH"
      auto_remediate = false
      alert_channels = []
    }
    "unrestricted-firewall" = {
      enabled        = true
      risk_level     = "HIGH"
      auto_remediate = false
      alert_channels = []
    }
    "overprivileged-sa" = {
      enabled        = true
      risk_level     = "MEDIUM"
      auto_remediate = false
      alert_channels = []
    }
  }
}

# Labeling Configuration
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "governance"
    managed-by  = "terraform"
    environment = "dev"
    owner       = "platform-team"
  }
}