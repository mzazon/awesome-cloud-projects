# ==============================================================================
# Real-Time Event Processing Variables
# ==============================================================================
# Variable definitions for the real-time event processing infrastructure
# Configure these values according to your requirements and environment.
# ==============================================================================

# ==============================================================================
# Project Configuration
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "prefix" {
  description = "Prefix for resource names to ensure uniqueness and organization"
  type        = string
  default     = "event-processing"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}[a-z0-9]$", var.prefix))
    error_message = "Prefix must be 4-22 characters, start and end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    project     = "event-processing"
    environment = "production"
    managed-by  = "terraform"
  }

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "organization_domain" {
  description = "Organization domain for BigQuery access control (e.g., 'example.com')"
  type        = string
  default     = ""

  validation {
    condition     = var.organization_domain == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.organization_domain))
    error_message = "Organization domain must be a valid domain name or empty string."
  }
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources (Redis, BigQuery)"
  type        = bool
  default     = true
}

# ==============================================================================
# Networking Configuration
# ==============================================================================

variable "main_subnet_cidr" {
  description = "CIDR block for the main subnet where application resources are deployed"
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrhost(var.main_subnet_cidr, 0))
    error_message = "Main subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "connector_subnet_cidr" {
  description = "CIDR block for the VPC connector subnet (must be /28 for connector)"
  type        = string
  default     = "10.0.1.0/28"

  validation {
    condition     = can(cidrhost(var.connector_subnet_cidr, 0)) && split("/", var.connector_subnet_cidr)[1] == "28"
    error_message = "Connector subnet CIDR must be a valid /28 IPv4 CIDR block for VPC connectors."
  }
}

# ==============================================================================
# Cloud Memorystore Redis Configuration
# ==============================================================================

variable "redis_shard_count" {
  description = "Number of shards for the Redis instance (affects performance and cost)"
  type        = number
  default     = 1

  validation {
    condition     = var.redis_shard_count >= 1 && var.redis_shard_count <= 100
    error_message = "Redis shard count must be between 1 and 100."
  }
}

variable "redis_replica_count" {
  description = "Number of replica nodes per shard for Redis high availability"
  type        = number
  default     = 0

  validation {
    condition     = var.redis_replica_count >= 0 && var.redis_replica_count <= 5
    error_message = "Redis replica count must be between 0 and 5."
  }
}

variable "redis_node_type" {
  description = "Machine type for Redis nodes (affects performance and cost)"
  type        = string
  default     = "SHARED_CORE_NANO"

  validation {
    condition = contains([
      "SHARED_CORE_NANO",
      "HIGHMEM_MEDIUM", 
      "HIGHMEM_XLARGE",
      "STANDARD_SMALL"
    ], var.redis_node_type)
    error_message = "Redis node type must be one of: SHARED_CORE_NANO, HIGHMEM_MEDIUM, HIGHMEM_XLARGE, STANDARD_SMALL."
  }
}

variable "redis_auth_enabled" {
  description = "Enable IAM authentication for Redis instance"
  type        = bool
  default     = false
}

variable "redis_encryption_enabled" {
  description = "Enable transit encryption for Redis instance"
  type        = bool
  default     = false
}

variable "redis_multi_zone" {
  description = "Enable multi-zone deployment for Redis high availability"
  type        = bool
  default     = false
}

variable "redis_persistence_enabled" {
  description = "Enable RDB persistence for Redis data durability"
  type        = bool
  default     = true
}

variable "redis_cache_ttl_seconds" {
  description = "Default TTL for cache entries in seconds"
  type        = number
  default     = 3600

  validation {
    condition     = var.redis_cache_ttl_seconds >= 60 && var.redis_cache_ttl_seconds <= 86400
    error_message = "Redis cache TTL must be between 60 seconds (1 minute) and 86400 seconds (24 hours)."
  }
}

# ==============================================================================
# Pub/Sub Configuration
# ==============================================================================

variable "pubsub_message_retention" {
  description = "Message retention duration for Pub/Sub topics"
  type        = string
  default     = "86400s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_message_retention))
    error_message = "Pub/Sub message retention must be in seconds format (e.g., '86400s')."
  }
}

variable "pubsub_subscription_retention" {
  description = "Message retention duration for Pub/Sub subscriptions"
  type        = string
  default     = "1200s"

  validation {
    condition     = can(regex("^[0-9]+s$", var.pubsub_subscription_retention))
    error_message = "Pub/Sub subscription retention must be in seconds format (e.g., '1200s')."
  }
}

variable "pubsub_ack_deadline_seconds" {
  description = "Message acknowledgment deadline in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.pubsub_ack_deadline_seconds >= 10 && var.pubsub_ack_deadline_seconds <= 600
    error_message = "Pub/Sub ack deadline must be between 10 and 600 seconds."
  }
}

variable "pubsub_max_delivery_attempts" {
  description = "Maximum delivery attempts before sending to dead letter topic"
  type        = number
  default     = 5

  validation {
    condition     = var.pubsub_max_delivery_attempts >= 1 && var.pubsub_max_delivery_attempts <= 100
    error_message = "Pub/Sub max delivery attempts must be between 1 and 100."
  }
}

# ==============================================================================
# BigQuery Configuration
# ==============================================================================

variable "bigquery_location" {
  description = "Location for BigQuery dataset (US, EU, or specific region)"
  type        = string
  default     = "US"

  validation {
    condition = contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be a valid location (US, EU, or specific region)."
  }
}

variable "bigquery_table_expiration_ms" {
  description = "Default table expiration time in milliseconds (null for no expiration)"
  type        = number
  default     = 7776000000 # 90 days

  validation {
    condition     = var.bigquery_table_expiration_ms == null || var.bigquery_table_expiration_ms >= 3600000
    error_message = "BigQuery table expiration must be at least 1 hour (3600000 ms) or null."
  }
}

variable "bigquery_partition_expiration_ms" {
  description = "Partition expiration time in milliseconds for time-partitioned tables"
  type        = number
  default     = 7776000000 # 90 days

  validation {
    condition     = var.bigquery_partition_expiration_ms >= 3600000
    error_message = "BigQuery partition expiration must be at least 1 hour (3600000 ms)."
  }
}

# ==============================================================================
# Cloud Functions Configuration
# ==============================================================================

variable "function_memory" {
  description = "Memory allocation for Cloud Functions (e.g., '512Mi', '1Gi')"
  type        = string
  default     = "512Mi"

  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "function_cpu" {
  description = "CPU allocation for Cloud Functions (in CPU units)"
  type        = string
  default     = "1"

  validation {
    condition = contains([
      "0.08", "0.17", "0.33", "0.5", "1", "2", "4", "6", "8"
    ], var.function_cpu)
    error_message = "Function CPU must be one of: 0.08, 0.17, 0.33, 0.5, 1, 2, 4, 6, 8."
  }
}

variable "function_timeout_seconds" {
  description = "Maximum execution time for Cloud Functions in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances for auto-scaling"
  type        = number
  default     = 100

  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances (0 for scale-to-zero)"
  type        = number
  default     = 0

  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

variable "function_concurrency" {
  description = "Maximum number of concurrent requests per function instance"
  type        = number
  default     = 80

  validation {
    condition     = var.function_concurrency >= 1 && var.function_concurrency <= 1000
    error_message = "Function concurrency must be between 1 and 1000."
  }
}

# ==============================================================================
# VPC Access Connector Configuration
# ==============================================================================

variable "vpc_connector_machine_type" {
  description = "Machine type for VPC Access Connector instances"
  type        = string
  default     = "e2-micro"

  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-4", "e2-standard-8"
    ], var.vpc_connector_machine_type)
    error_message = "VPC connector machine type must be one of: e2-micro, e2-small, e2-medium, e2-standard-4, e2-standard-8."
  }
}

variable "vpc_connector_min_instances" {
  description = "Minimum number of VPC connector instances"
  type        = number
  default     = 2

  validation {
    condition     = var.vpc_connector_min_instances >= 2 && var.vpc_connector_min_instances <= 10
    error_message = "VPC connector min instances must be between 2 and 10."
  }
}

variable "vpc_connector_max_instances" {
  description = "Maximum number of VPC connector instances"
  type        = number
  default     = 10

  validation {
    condition     = var.vpc_connector_max_instances >= 2 && var.vpc_connector_max_instances <= 10
    error_message = "VPC connector max instances must be between 2 and 10."
  }
}

# ==============================================================================
# Monitoring Configuration
# ==============================================================================

variable "monitoring_enabled" {
  description = "Enable Cloud Monitoring alerts and policies"
  type        = bool
  default     = true
}

variable "error_rate_threshold" {
  description = "Error rate threshold (%) for alerting"
  type        = number
  default     = 5.0

  validation {
    condition     = var.error_rate_threshold >= 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 0 and 100 percent."
  }
}