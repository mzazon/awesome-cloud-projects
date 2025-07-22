# Core project configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource naming configuration
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "ai-inference"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Bigtable configuration
variable "bigtable_instance_display_name" {
  description = "Display name for the Bigtable instance"
  type        = string
  default     = "AI Feature Store Instance"
}

variable "bigtable_cluster_num_nodes" {
  description = "Number of nodes in the Bigtable cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.bigtable_cluster_num_nodes >= 1 && var.bigtable_cluster_num_nodes <= 30
    error_message = "Bigtable cluster must have between 1 and 30 nodes."
  }
}

variable "bigtable_cluster_storage_type" {
  description = "Storage type for the Bigtable cluster"
  type        = string
  default     = "SSD"
  validation {
    condition     = contains(["SSD", "HDD"], var.bigtable_cluster_storage_type)
    error_message = "Storage type must be either SSD or HDD."
  }
}

variable "bigtable_tables" {
  description = "Configuration for Bigtable tables and column families"
  type = map(object({
    column_families = map(object({
      max_versions = number
      gc_rule      = string
    }))
  }))
  default = {
    "user_features" = {
      column_families = {
        "embeddings" = {
          max_versions = 1
          gc_rule      = ""
        }
        "demographics" = {
          max_versions = 1
          gc_rule      = ""
        }
        "behavior" = {
          max_versions = 3
          gc_rule      = ""
        }
      }
    }
    "item_features" = {
      column_families = {
        "content" = {
          max_versions = 1
          gc_rule      = ""
        }
        "metadata" = {
          max_versions = 1
          gc_rule      = ""
        }
        "statistics" = {
          max_versions = 1
          gc_rule      = ""
        }
      }
    }
    "contextual_features" = {
      column_families = {
        "temporal" = {
          max_versions = 1
          gc_rule      = ""
        }
        "location" = {
          max_versions = 1
          gc_rule      = ""
        }
        "device" = {
          max_versions = 1
          gc_rule      = ""
        }
      }
    }
  }
}

# Redis configuration
variable "redis_memory_size_gb" {
  description = "Memory size in GB for the Redis instance"
  type        = number
  default     = 5
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "redis_version" {
  description = "Redis version to use"
  type        = string
  default     = "REDIS_7_0"
}

variable "redis_tier" {
  description = "Redis service tier"
  type        = string
  default     = "STANDARD_HA"
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Redis tier must be either BASIC or STANDARD_HA."
  }
}

variable "redis_config" {
  description = "Redis configuration parameters"
  type        = map(string)
  default = {
    "maxmemory-policy" = "allkeys-lru"
  }
}

# Vertex AI configuration
variable "vertex_ai_model_display_name" {
  description = "Display name for the Vertex AI model"
  type        = string
  default     = "high-performance-recommendation-model"
}

variable "vertex_ai_endpoint_display_name" {
  description = "Display name for the Vertex AI endpoint"
  type        = string
  default     = "high-perf-inference"
}

variable "vertex_ai_machine_type" {
  description = "Machine type for the Vertex AI endpoint"
  type        = string
  default     = "cloud-tpu"
}

variable "vertex_ai_accelerator_type" {
  description = "Accelerator type for the Vertex AI endpoint"
  type        = string
  default     = "TPU_V5_LITE_POD_SLICE"
}

variable "vertex_ai_accelerator_count" {
  description = "Number of accelerators for the Vertex AI endpoint"
  type        = number
  default     = 1
}

variable "vertex_ai_min_replica_count" {
  description = "Minimum number of replicas for the Vertex AI endpoint"
  type        = number
  default     = 1
}

variable "vertex_ai_max_replica_count" {
  description = "Maximum number of replicas for the Vertex AI endpoint"
  type        = number
  default     = 5
}

# Cloud Functions configuration
variable "cloud_function_name" {
  description = "Name of the Cloud Function for inference orchestration"
  type        = string
  default     = "inference-pipeline"
}

variable "cloud_function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python311"
}

variable "cloud_function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "2Gi"
}

variable "cloud_function_timeout" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 60
}

variable "cloud_function_max_instances" {
  description = "Maximum number of instances for the Cloud Function"
  type        = number
  default     = 100
}

variable "cloud_function_min_instances" {
  description = "Minimum number of instances for the Cloud Function"
  type        = number
  default     = 2
}

# Storage configuration
variable "enable_storage_bucket" {
  description = "Whether to create a Cloud Storage bucket for model artifacts"
  type        = bool
  default     = true
}

variable "storage_bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "storage_bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
}

# Monitoring configuration
variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring resources"
  type        = bool
  default     = true
}

variable "monitoring_notification_channels" {
  description = "List of notification channels for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "monitoring_alert_latency_threshold" {
  description = "Latency threshold in milliseconds for monitoring alerts"
  type        = number
  default     = 500
}

variable "monitoring_alert_error_rate_threshold" {
  description = "Error rate threshold for monitoring alerts"
  type        = number
  default     = 0.05
}

# IAM configuration
variable "enable_custom_service_accounts" {
  description = "Whether to create custom service accounts for each service"
  type        = bool
  default     = true
}

variable "additional_iam_members" {
  description = "Additional IAM members to grant permissions to resources"
  type        = list(string)
  default     = []
}

# Networking configuration
variable "enable_private_networking" {
  description = "Whether to enable private networking for resources"
  type        = bool
  default     = false
}

variable "vpc_network_name" {
  description = "Name of the VPC network to use (if private networking is enabled)"
  type        = string
  default     = ""
}

variable "vpc_subnet_name" {
  description = "Name of the VPC subnet to use (if private networking is enabled)"
  type        = string
  default     = ""
}

# Labels and tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    "purpose"     = "ai-inference-pipeline"
    "managed-by"  = "terraform"
    "cost-center" = "ai-ml"
  }
}

# Feature flags
variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection on critical resources"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Whether to enable detailed logging for all resources"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Whether to enable backup for stateful resources"
  type        = bool
  default     = true
}