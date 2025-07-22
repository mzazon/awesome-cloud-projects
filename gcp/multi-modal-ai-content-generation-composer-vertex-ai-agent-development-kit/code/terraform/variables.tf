# Variables for Multi-Modal AI Content Generation Pipeline
# This file defines all configurable parameters for the infrastructure deployment
# including Cloud Composer, Vertex AI, Cloud Storage, and Cloud Run configurations

# =============================================================================
# PROJECT AND LOCATION VARIABLES
# =============================================================================

variable "project_id" {
  description = "Google Cloud Project ID where resources will be deployed"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "region" {
  description = "Primary Google Cloud region for multi-region services"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with Vertex AI support."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# =============================================================================
# CLOUD COMPOSER CONFIGURATION
# =============================================================================

variable "composer_environment_name" {
  description = "Name for the Cloud Composer environment"
  type        = string
  default     = "multi-modal-content-pipeline"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.composer_environment_name))
    error_message = "Composer environment name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "composer_node_count" {
  description = "Number of nodes in the Cloud Composer environment"
  type        = number
  default     = 3
  
  validation {
    condition     = var.composer_node_count >= 3 && var.composer_node_count <= 10
    error_message = "Node count must be between 3 and 10 for optimal performance."
  }
}

variable "composer_machine_type" {
  description = "Machine type for Cloud Composer nodes"
  type        = string
  default     = "n1-standard-2"
  
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16"
    ], var.composer_machine_type)
    error_message = "Machine type must be a valid Compute Engine machine type suitable for Composer."
  }
}

variable "composer_disk_size_gb" {
  description = "Disk size in GB for Cloud Composer nodes"
  type        = number
  default     = 50
  
  validation {
    condition     = var.composer_disk_size_gb >= 20 && var.composer_disk_size_gb <= 500
    error_message = "Disk size must be between 20GB and 500GB."
  }
}

variable "composer_python_version" {
  description = "Python version for Cloud Composer environment"
  type        = string
  default     = "3"
  
  validation {
    condition     = contains(["3"], var.composer_python_version)
    error_message = "Python version must be 3 for Composer 2.x environments."
  }
}

variable "composer_airflow_version" {
  description = "Apache Airflow version for the Composer environment"
  type        = string
  default     = "2.9.3"
}

# =============================================================================
# CLOUD STORAGE CONFIGURATION
# =============================================================================

variable "storage_bucket_name" {
  description = "Name for the content storage bucket (will be made globally unique)"
  type        = string
  default     = "content-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.storage_bucket_name))
    error_message = "Storage bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "storage_class" {
  description = "Storage class for the content bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE, REGIONAL."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for the content storage bucket"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "Lifecycle rules for automatic content management"
  type = list(object({
    action = object({
      type          = string
      storage_class = optional(string)
    })
    condition = object({
      age                   = optional(number)
      created_before        = optional(string)
      with_state           = optional(string)
      matches_storage_class = optional(list(string))
      num_newer_versions   = optional(number)
    })
  }))
  default = [
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition = {
        age = 30
      }
    },
    {
      action = {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition = {
        age = 90
      }
    }
  ]
}

# =============================================================================
# VERTEX AI CONFIGURATION
# =============================================================================

variable "vertex_ai_dataset_name" {
  description = "Name for the Vertex AI dataset for model training data"
  type        = string
  default     = "content-generation-dataset"
}

variable "vertex_ai_model_display_name" {
  description = "Display name for custom Vertex AI models"
  type        = string
  default     = "multi-modal-content-model"
}

variable "enable_vertex_ai_monitoring" {
  description = "Enable Vertex AI model monitoring for drift detection"
  type        = bool
  default     = true
}

variable "vertex_ai_endpoint_machine_type" {
  description = "Machine type for Vertex AI prediction endpoints"
  type        = string
  default     = "n1-standard-4"
}

variable "vertex_ai_min_replica_count" {
  description = "Minimum number of replicas for Vertex AI endpoints"
  type        = number
  default     = 1
  
  validation {
    condition     = var.vertex_ai_min_replica_count >= 1 && var.vertex_ai_min_replica_count <= 10
    error_message = "Minimum replica count must be between 1 and 10."
  }
}

variable "vertex_ai_max_replica_count" {
  description = "Maximum number of replicas for Vertex AI endpoints"
  type        = number
  default     = 5
  
  validation {
    condition     = var.vertex_ai_max_replica_count >= 1 && var.vertex_ai_max_replica_count <= 100
    error_message = "Maximum replica count must be between 1 and 100."
  }
}

# =============================================================================
# CLOUD RUN CONFIGURATION
# =============================================================================

variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service hosting the content API"
  type        = string
  default     = "content-api"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cloud_run_service_name))
    error_message = "Cloud Run service name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "2"
  
  validation {
    condition     = contains(["1", "2", "4", "6", "8"], var.cloud_run_cpu)
    error_message = "CPU allocation must be one of: 1, 2, 4, 6, 8."
  }
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "2Gi"
  
  validation {
    condition = can(regex("^[0-9]+(Gi|Mi)$", var.cloud_run_memory))
    error_message = "Memory must be specified in Gi or Mi format (e.g., 2Gi, 512Mi)."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Maximum instances must be between 1 and 1000."
  }
}

variable "cloud_run_timeout" {
  description = "Request timeout for Cloud Run service in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.cloud_run_timeout >= 1 && var.cloud_run_timeout <= 3600
    error_message = "Timeout must be between 1 and 3600 seconds."
  }
}

variable "cloud_run_concurrency" {
  description = "Maximum number of concurrent requests per Cloud Run instance"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cloud_run_concurrency >= 1 && var.cloud_run_concurrency <= 1000
    error_message = "Concurrency must be between 1 and 1000."
  }
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to Cloud Run service"
  type        = bool
  default     = false
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "vpc_name" {
  description = "Name for the VPC network (if creating new VPC)"
  type        = string
  default     = "content-pipeline-vpc"
}

variable "subnet_name" {
  description = "Name for the subnet (if creating new subnet)"
  type        = string
  default     = "content-pipeline-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for the subnet"
  type        = bool
  default     = true
}

# =============================================================================
# SECURITY AND IAM CONFIGURATION
# =============================================================================

variable "service_account_name" {
  description = "Name for the service account used by the content pipeline"
  type        = string
  default     = "content-pipeline-sa"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_audit_logging" {
  description = "Enable audit logging for sensitive operations"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access the content API"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Consider restricting in production
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_ingress_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All ingress CIDRs must be valid CIDR blocks."
  }
}

# =============================================================================
# MONITORING AND OBSERVABILITY
# =============================================================================

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the content pipeline"
  type        = bool
  default     = true
}

variable "notification_channels" {
  description = "List of notification channels for alerts"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

variable "enable_preemptible_instances" {
  description = "Use preemptible instances where possible to reduce costs"
  type        = bool
  default     = false
}

variable "budget_amount" {
  description = "Monthly budget amount for cost monitoring (in USD)"
  type        = number
  default     = 500
  
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

# =============================================================================
# ENVIRONMENT AND DEPLOYMENT
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "multi-modal-content-generation"
    managed-by  = "terraform"
    application = "ai-content-pipeline"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = true
}