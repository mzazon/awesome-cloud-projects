# Variables for threat detection pipeline infrastructure
# This file defines all configurable parameters for the Terraform deployment

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources like Cloud IDS endpoint"
  type        = string
  default     = "us-central1-a"
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "prod"
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "threat-detection"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC network"
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  validation {
    condition = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "ids_severity_level" {
  description = "Cloud IDS severity level for threat detection"
  type        = string
  default     = "INFORMATIONAL"
  validation {
    condition = contains(["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL"], var.ids_severity_level)
    error_message = "IDS severity level must be one of: INFORMATIONAL, LOW, MEDIUM, HIGH, CRITICAL."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (should match or be compatible with region)"
  type        = string
  default     = "US"
  validation {
    condition = contains(["US", "EU", "asia-northeast1", "us-central1", "us-east1", "us-west1", "europe-west1"], var.bigquery_location)
    error_message = "BigQuery location must be a valid location (US, EU, or specific region)."
  }
}

variable "enable_packet_mirroring" {
  description = "Whether to enable packet mirroring for the VMs"
  type        = bool
  default     = true
}

variable "create_test_vms" {
  description = "Whether to create test VMs for traffic generation and monitoring"
  type        = bool
  default     = true
}

variable "vm_machine_type" {
  description = "Machine type for test VMs"
  type        = string
  default     = "e2-medium"
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.vm_machine_type))
    error_message = "VM machine type must be a valid GCP machine type."
  }
}

variable "vm_image_family" {
  description = "Image family for test VMs"
  type        = string
  default     = "debian-11"
}

variable "vm_image_project" {
  description = "Project containing the VM image"
  type        = string
  default     = "debian-cloud"
}

variable "function_runtime" {
  description = "Runtime for Cloud Functions"
  type        = string
  default     = "python39"
  validation {
    condition = contains(["python39", "python310", "python311"], var.function_runtime)
    error_message = "Function runtime must be one of the supported Python versions."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (in MB)"
  type        = number
  default     = 512
  validation {
    condition = var.function_memory >= 128 && var.function_memory <= 8192
    error_message = "Function memory must be between 128 MB and 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions (in seconds)"
  type        = number
  default     = 120
  validation {
    condition = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "pubsub_message_retention_duration" {
  description = "Message retention duration for Pub/Sub subscriptions"
  type        = string
  default     = "604800s" # 7 days
  validation {
    condition = can(regex("^[0-9]+s$", var.pubsub_message_retention_duration))
    error_message = "Message retention duration must be in seconds format (e.g., 604800s)."
  }
}

variable "pubsub_ack_deadline" {
  description = "Acknowledgement deadline for Pub/Sub subscriptions (in seconds)"
  type        = number
  default     = 60
  validation {
    condition = var.pubsub_ack_deadline >= 10 && var.pubsub_ack_deadline <= 600
    error_message = "Pub/Sub ack deadline must be between 10 and 600 seconds."
  }
}

variable "enable_apis" {
  description = "List of Google Cloud APIs to enable"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "ids.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "servicenetworking.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

variable "labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "threat-detection"
    managed-by  = "terraform"
    recipe      = "threat-detection-pipelines"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}