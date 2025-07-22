# Variables for Real-Time Inventory Intelligence Infrastructure

# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "inventory-intel"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Cloud SQL Configuration
variable "db_instance_tier" {
  description = "The machine type for the Cloud SQL instance"
  type        = string
  default     = "db-f1-micro"
  validation {
    condition = contains([
      "db-f1-micro", "db-g1-small", "db-n1-standard-1",
      "db-n1-standard-2", "db-n1-standard-4"
    ], var.db_instance_tier)
    error_message = "Database tier must be a valid Cloud SQL machine type."
  }
}

variable "db_disk_size" {
  description = "Size of the Cloud SQL disk in GB"
  type        = number
  default     = 20
  validation {
    condition     = var.db_disk_size >= 10 && var.db_disk_size <= 3000
    error_message = "Database disk size must be between 10 and 3000 GB."
  }
}

variable "db_backup_start_time" {
  description = "Start time for automated backups in HH:MM format"
  type        = string
  default     = "03:00"
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.db_backup_start_time))
    error_message = "Backup start time must be in HH:MM format (24-hour)."
  }
}

variable "db_name" {
  description = "Name of the database to create"
  type        = string
  default     = "inventory_intelligence"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only letters, numbers, and underscores."
  }
}

# GKE Edge Cluster Configuration
variable "edge_cluster_node_count" {
  description = "Initial number of nodes in the edge cluster"
  type        = number
  default     = 2
  validation {
    condition     = var.edge_cluster_node_count >= 1 && var.edge_cluster_node_count <= 10
    error_message = "Edge cluster node count must be between 1 and 10."
  }
}

variable "edge_cluster_machine_type" {
  description = "Machine type for edge cluster nodes"
  type        = string
  default     = "e2-medium"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2",
      "n1-standard-1", "n1-standard-2", "n2-standard-2"
    ], var.edge_cluster_machine_type)
    error_message = "Machine type must be a valid GCE machine type."
  }
}

variable "edge_cluster_disk_size" {
  description = "Disk size for edge cluster nodes in GB"
  type        = number
  default     = 50
  validation {
    condition     = var.edge_cluster_disk_size >= 10 && var.edge_cluster_disk_size <= 500
    error_message = "Edge cluster disk size must be between 10 and 500 GB."
  }
}

# Storage Configuration
variable "image_storage_location" {
  description = "Location for the image storage bucket"
  type        = string
  default     = "US"
  validation {
    condition = contains([
      "US", "EU", "ASIA",
      "us-central1", "us-east1", "europe-west1", "asia-east1"
    ], var.image_storage_location)
    error_message = "Storage location must be a valid Cloud Storage location."
  }
}

variable "image_storage_class" {
  description = "Storage class for the image bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.image_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "image_retention_days" {
  description = "Number of days to retain images before automatic deletion"
  type        = number
  default     = 30
  validation {
    condition     = var.image_retention_days >= 1 && var.image_retention_days <= 365
    error_message = "Image retention days must be between 1 and 365."
  }
}

# Vision API Configuration
variable "vision_api_location" {
  description = "Location for Vision API resources"
  type        = string
  default     = "us-central1"
}

variable "product_set_display_name" {
  description = "Display name for the Vision API product set"
  type        = string
  default     = "Retail Inventory Products"
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "inventory_threshold" {
  description = "Inventory count threshold for low stock alerts"
  type        = number
  default     = 10
  validation {
    condition     = var.inventory_threshold >= 1 && var.inventory_threshold <= 100
    error_message = "Inventory threshold must be between 1 and 100."
  }
}

variable "notification_email" {
  description = "Email address for inventory alerts"
  type        = string
  default     = ""
  validation {
    condition     = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Application Configuration
variable "processor_replicas" {
  description = "Number of inventory processor replicas to deploy"
  type        = number
  default     = 2
  validation {
    condition     = var.processor_replicas >= 1 && var.processor_replicas <= 10
    error_message = "Processor replicas must be between 1 and 10."
  }
}

variable "processor_image" {
  description = "Container image for the inventory processor"
  type        = string
  default     = "gcr.io/google-samples/vision-product-search:latest"
}

variable "processor_cpu_request" {
  description = "CPU request for processor containers"
  type        = string
  default     = "250m"
}

variable "processor_memory_request" {
  description = "Memory request for processor containers"
  type        = string
  default     = "256Mi"
}

variable "processor_cpu_limit" {
  description = "CPU limit for processor containers"
  type        = string
  default     = "500m"
}

variable "processor_memory_limit" {
  description = "Memory limit for processor containers"
  type        = string
  default     = "512Mi"
}

# Networking Configuration
variable "authorized_networks" {
  description = "List of authorized networks for Cloud SQL access"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "enable_private_ip" {
  description = "Enable private IP for Cloud SQL instance"
  type        = bool
  default     = false
}

# Security Configuration
variable "enable_network_policy" {
  description = "Enable Kubernetes network policy"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for secure service account access"
  type        = bool
  default     = true
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    application = "inventory-intelligence"
    managed-by  = "terraform"
  }
}