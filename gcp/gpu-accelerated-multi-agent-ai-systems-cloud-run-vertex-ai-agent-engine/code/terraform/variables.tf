# GPU-Accelerated Multi-Agent AI Systems - Terraform Variables
# This file defines all configurable variables for the multi-agent AI infrastructure

# Project and Location Configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports GPU workloads."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network for multi-agent system"
  type        = string
  default     = "multi-agent-network"
}

variable "subnet_name" {
  description = "Name of the subnet for multi-agent system resources"
  type        = string
  default     = "multi-agent-subnet"
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

# Cloud Run Service Names
variable "vision_agent_name" {
  description = "Name of the Vision Agent Cloud Run service"
  type        = string
  default     = "vision-agent"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.vision_agent_name))
    error_message = "Vision agent name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "language_agent_name" {
  description = "Name of the Language Agent Cloud Run service"
  type        = string
  default     = "language-agent"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.language_agent_name))
    error_message = "Language agent name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "reasoning_agent_name" {
  description = "Name of the Reasoning Agent Cloud Run service"
  type        = string
  default     = "reasoning-agent"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.reasoning_agent_name))
    error_message = "Reasoning agent name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "tool_agent_name" {
  description = "Name of the Tool Agent Cloud Run service"
  type        = string
  default     = "tool-agent"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.tool_agent_name))
    error_message = "Tool agent name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Container Configuration
variable "container_image_tag" {
  description = "Tag for container images (e.g., latest, v1.0.0)"
  type        = string
  default     = "latest"
}

variable "artifact_registry_repo" {
  description = "Name of the Artifact Registry repository for agent images"
  type        = string
  default     = "agent-images"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.artifact_registry_repo))
    error_message = "Artifact Registry repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# GPU Configuration
variable "gpu_type" {
  description = "Type of GPU to use for Cloud Run services (nvidia-l4 or nvidia-t4)"
  type        = string
  default     = "nvidia-l4"
  
  validation {
    condition     = contains(["nvidia-l4", "nvidia-t4"], var.gpu_type)
    error_message = "GPU type must be either 'nvidia-l4' (recommended for inference) or 'nvidia-t4' (cost-effective option)."
  }
}

# Scaling Configuration
variable "min_instances" {
  description = "Minimum number of instances for each Cloud Run service"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_instances >= 0 && var.min_instances <= 5
    error_message = "Minimum instances must be between 0 and 5."
  }
}

variable "max_instances_gpu" {
  description = "Maximum number of instances for GPU-enabled Cloud Run services"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_instances_gpu >= 1 && var.max_instances_gpu <= 100
    error_message = "Maximum GPU instances must be between 1 and 100."
  }
}

variable "max_instances_cpu" {
  description = "Maximum number of instances for CPU-only Cloud Run services"
  type        = number
  default     = 5
  
  validation {
    condition     = var.max_instances_cpu >= 1 && var.max_instances_cpu <= 50
    error_message = "Maximum CPU instances must be between 1 and 50."
  }
}

# Redis Configuration
variable "redis_instance_name" {
  description = "Name of the Cloud Memorystore Redis instance"
  type        = string
  default     = "agent-cache"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.redis_instance_name))
    error_message = "Redis instance name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "redis_memory_size_gb" {
  description = "Memory size in GB for the Redis instance"
  type        = number
  default     = 4
  
  validation {
    condition     = var.redis_memory_size_gb >= 1 && var.redis_memory_size_gb <= 300
    error_message = "Redis memory size must be between 1 and 300 GB."
  }
}

variable "redis_tier" {
  description = "Redis service tier (BASIC for development, STANDARD_HA for production)"
  type        = string
  default     = "STANDARD_HA"
  
  validation {
    condition     = contains(["BASIC", "STANDARD_HA"], var.redis_tier)
    error_message = "Redis tier must be either 'BASIC' (development) or 'STANDARD_HA' (production)."
  }
}

variable "redis_version" {
  description = "Redis version to use"
  type        = string
  default     = "REDIS_7_0"
  
  validation {
    condition     = contains(["REDIS_6_X", "REDIS_7_0"], var.redis_version)
    error_message = "Redis version must be either 'REDIS_6_X' or 'REDIS_7_0'."
  }
}

# Pub/Sub Configuration
variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for agent coordination"
  type        = string
  default     = "agent-tasks"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-_]*[a-zA-Z0-9]$", var.pubsub_topic_name))
    error_message = "Pub/Sub topic name must start with a letter, contain only letters, numbers, hyphens, and underscores, and end with a letter or number."
  }
}

# Monitoring and Alerting Configuration
variable "enable_cost_alerts" {
  description = "Whether to enable cost alerting for GPU usage"
  type        = bool
  default     = true
}

variable "cost_alert_threshold" {
  description = "Threshold value for cost alerts (in USD per day)"
  type        = number
  default     = 100.0
  
  validation {
    condition     = var.cost_alert_threshold >= 10.0 && var.cost_alert_threshold <= 1000.0
    error_message = "Cost alert threshold must be between $10 and $1000 per day."
  }
}

variable "enable_performance_monitoring" {
  description = "Whether to enable detailed performance monitoring"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_vpc_connector" {
  description = "Whether to use VPC connector for secure communication"
  type        = bool
  default     = true
}

variable "enable_private_endpoints" {
  description = "Whether to use private endpoints for Cloud Run services"
  type        = bool
  default     = false
}

# Development and Testing Configuration
variable "enable_debug_logging" {
  description = "Whether to enable debug-level logging (useful for development)"
  type        = bool
  default     = false
}

variable "resource_deletion_protection" {
  description = "Whether to enable deletion protection for critical resources"
  type        = bool
  default     = true
}

# Resource Tagging
variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k))
    ])
    error_message = "Label keys must start with a letter, contain only lowercase letters, numbers, underscores, and hyphens, and end with a letter or number."
  }
}

# Vertex AI Configuration
variable "vertex_ai_region" {
  description = "Region for Vertex AI services (may differ from main region)"
  type        = string
  default     = ""
}

variable "vertex_ai_endpoint_name" {
  description = "Name of the Vertex AI endpoint for model serving"
  type        = string
  default     = "multi-agent-endpoint"
}

# Advanced GPU Configuration
variable "gpu_partition_size" {
  description = "GPU partition size for sharing GPUs across containers (not supported for all GPU types)"
  type        = string
  default     = ""
  
  validation {
    condition = var.gpu_partition_size == "" || contains([
      "1g.5gb", "2g.10gb", "3g.20gb", "4g.20gb", "7g.40gb"
    ], var.gpu_partition_size)
    error_message = "GPU partition size must be empty or one of: 1g.5gb, 2g.10gb, 3g.20gb, 4g.20gb, 7g.40gb."
  }
}

variable "enable_gpu_sharing" {
  description = "Whether to enable GPU sharing across multiple containers"
  type        = bool
  default     = false
}

# Cost Optimization Configuration
variable "use_spot_instances" {
  description = "Whether to use Spot/Preemptible instances for cost optimization (experimental)"
  type        = bool
  default     = false
}

variable "auto_scaling_metrics" {
  description = "Metrics to use for auto-scaling decisions"
  type = object({
    cpu_utilization    = optional(number, 70)
    memory_utilization = optional(number, 80)
    request_rate      = optional(number, 100)
  })
  default = {
    cpu_utilization    = 70
    memory_utilization = 80
    request_rate      = 100
  }
  
  validation {
    condition = (
      var.auto_scaling_metrics.cpu_utilization >= 10 && var.auto_scaling_metrics.cpu_utilization <= 95 &&
      var.auto_scaling_metrics.memory_utilization >= 10 && var.auto_scaling_metrics.memory_utilization <= 95 &&
      var.auto_scaling_metrics.request_rate >= 1 && var.auto_scaling_metrics.request_rate <= 1000
    )
    error_message = "Auto-scaling metrics must be within valid ranges: CPU (10-95%), Memory (10-95%), Request rate (1-1000 req/s)."
  }
}

# Backup and Disaster Recovery
variable "enable_backup" {
  description = "Whether to enable automatic backups for Redis and other stateful services"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

# Experimental Features
variable "enable_experimental_features" {
  description = "Whether to enable experimental features (may incur additional costs or instability)"
  type        = bool
  default     = false
}