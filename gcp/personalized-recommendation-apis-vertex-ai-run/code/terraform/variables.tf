# Variables for Personalized Recommendation APIs with Vertex AI and Cloud Run
# This file defines all configurable parameters for the ML recommendation system deployment

# Core project configuration
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (e.g., us-central1, europe-west1)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1, europe-west1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (e.g., us-central1-a)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[a-z0-9]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a)."
  }
}

# Environment and deployment configuration
variable "environment" {
  description = "Environment name (dev, staging, prod) for resource naming and tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Security and encryption configuration
variable "kms_key_name" {
  description = "Optional KMS key name for encrypting sensitive resources (format: projects/PROJECT_ID/locations/LOCATION/keyRings/RING_NAME/cryptoKeys/KEY_NAME)"
  type        = string
  default     = null
  
  validation {
    condition = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "KMS key name must be in the format: projects/PROJECT_ID/locations/LOCATION/keyRings/RING_NAME/cryptoKeys/KEY_NAME"
  }
}

variable "vpc_network_name" {
  description = "Optional VPC network name for private networking (format: projects/PROJECT_ID/global/networks/NETWORK_NAME)"
  type        = string
  default     = null
  
  validation {
    condition = var.vpc_network_name == null || can(regex("^projects/[^/]+/global/networks/[^/]+$", var.vpc_network_name))
    error_message = "VPC network name must be in the format: projects/PROJECT_ID/global/networks/NETWORK_NAME"
  }
}

# CI/CD and source code configuration
variable "github_owner" {
  description = "GitHub repository owner/organization name for CI/CD integration"
  type        = string
  default     = null
  
  validation {
    condition = var.github_owner == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-])*[a-zA-Z0-9]$", var.github_owner))
    error_message = "GitHub owner must be a valid GitHub username or organization name."
  }
}

variable "github_repo_name" {
  description = "GitHub repository name for CI/CD integration"
  type        = string
  default     = null
  
  validation {
    condition = var.github_repo_name == null || can(regex("^[a-zA-Z0-9._-]+$", var.github_repo_name))
    error_message = "GitHub repository name must contain only alphanumeric characters, dots, hyphens, and underscores."
  }
}

# Machine learning configuration
variable "ml_model_config" {
  description = "Configuration for ML model training and serving"
  type = object({
    # Model training configuration
    training_machine_type     = optional(string, "n1-standard-4")
    training_accelerator_type = optional(string, "NVIDIA_TESLA_T4")
    training_accelerator_count = optional(number, 1)
    
    # Model serving configuration
    serving_machine_type     = optional(string, "n1-standard-2")
    serving_min_replicas     = optional(number, 1)
    serving_max_replicas     = optional(number, 5)
    
    # Model parameters
    embedding_dimension      = optional(number, 64)
    max_training_epochs      = optional(number, 10)
    learning_rate           = optional(number, 0.1)
    
    # Data configuration
    train_test_split_ratio  = optional(number, 0.8)
    batch_size              = optional(number, 512)
  })
  
  default = {
    training_machine_type     = "n1-standard-4"
    training_accelerator_type = "NVIDIA_TESLA_T4"
    training_accelerator_count = 1
    serving_machine_type     = "n1-standard-2"
    serving_min_replicas     = 1
    serving_max_replicas     = 5
    embedding_dimension      = 64
    max_training_epochs      = 10
    learning_rate           = 0.1
    train_test_split_ratio  = 0.8
    batch_size              = 512
  }
  
  validation {
    condition = var.ml_model_config.embedding_dimension >= 16 && var.ml_model_config.embedding_dimension <= 512
    error_message = "Embedding dimension must be between 16 and 512."
  }
  
  validation {
    condition = var.ml_model_config.max_training_epochs >= 1 && var.ml_model_config.max_training_epochs <= 100
    error_message = "Max training epochs must be between 1 and 100."
  }
  
  validation {
    condition = var.ml_model_config.learning_rate > 0 && var.ml_model_config.learning_rate <= 1
    error_message = "Learning rate must be between 0 and 1."
  }
  
  validation {
    condition = var.ml_model_config.train_test_split_ratio > 0 && var.ml_model_config.train_test_split_ratio < 1
    error_message = "Train test split ratio must be between 0 and 1."
  }
  
  validation {
    condition = var.ml_model_config.batch_size >= 32 && var.ml_model_config.batch_size <= 2048
    error_message = "Batch size must be between 32 and 2048."
  }
}

# Cloud Run API configuration
variable "api_config" {
  description = "Configuration for Cloud Run API service"
  type = object({
    # Resource allocation
    cpu_limit      = optional(string, "2000m")
    memory_limit   = optional(string, "4Gi")
    cpu_request    = optional(string, "1000m")
    memory_request = optional(string, "2Gi")
    
    # Scaling configuration
    min_instances  = optional(number, 1)
    max_instances  = optional(number, 100)
    
    # Timeout and concurrency
    timeout_seconds         = optional(number, 300)
    container_concurrency   = optional(number, 1000)
    
    # Health check configuration
    health_check_path       = optional(string, "/")
    health_check_port       = optional(number, 8080)
    liveness_initial_delay  = optional(number, 30)
    readiness_initial_delay = optional(number, 5)
    
    # API-specific settings
    max_recommendations     = optional(number, 50)
    default_recommendations = optional(number, 10)
    cache_ttl_seconds      = optional(number, 300)
  })
  
  default = {
    cpu_limit      = "2000m"
    memory_limit   = "4Gi"
    cpu_request    = "1000m"
    memory_request = "2Gi"
    min_instances  = 1
    max_instances  = 100
    timeout_seconds         = 300
    container_concurrency   = 1000
    health_check_path       = "/"
    health_check_port       = 8080
    liveness_initial_delay  = 30
    readiness_initial_delay = 5
    max_recommendations     = 50
    default_recommendations = 10
    cache_ttl_seconds      = 300
  }
  
  validation {
    condition = var.api_config.min_instances >= 0 && var.api_config.min_instances <= var.api_config.max_instances
    error_message = "Min instances must be non-negative and not greater than max instances."
  }
  
  validation {
    condition = var.api_config.max_instances >= 1 && var.api_config.max_instances <= 1000
    error_message = "Max instances must be between 1 and 1000."
  }
  
  validation {
    condition = var.api_config.timeout_seconds >= 30 && var.api_config.timeout_seconds <= 3600
    error_message = "Timeout seconds must be between 30 and 3600."
  }
  
  validation {
    condition = var.api_config.container_concurrency >= 1 && var.api_config.container_concurrency <= 10000
    error_message = "Container concurrency must be between 1 and 10000."
  }
  
  validation {
    condition = var.api_config.max_recommendations >= 1 && var.api_config.max_recommendations <= 100
    error_message = "Max recommendations must be between 1 and 100."
  }
  
  validation {
    condition = var.api_config.default_recommendations >= 1 && var.api_config.default_recommendations <= var.api_config.max_recommendations
    error_message = "Default recommendations must be between 1 and max recommendations."
  }
}

# Storage configuration
variable "storage_config" {
  description = "Configuration for Cloud Storage buckets"
  type = object({
    # Storage classes for lifecycle management
    standard_storage_days = optional(number, 30)
    nearline_storage_days = optional(number, 60)
    coldline_storage_days = optional(number, 90)
    
    # Versioning and backup
    enable_versioning = optional(bool, true)
    
    # Data retention policies
    training_data_retention_days = optional(number, 365)
    model_artifacts_retention_days = optional(number, 180)
    
    # Access control
    uniform_bucket_level_access = optional(bool, true)
  })
  
  default = {
    standard_storage_days = 30
    nearline_storage_days = 60
    coldline_storage_days = 90
    enable_versioning = true
    training_data_retention_days = 365
    model_artifacts_retention_days = 180
    uniform_bucket_level_access = true
  }
  
  validation {
    condition = var.storage_config.standard_storage_days < var.storage_config.nearline_storage_days
    error_message = "Standard storage days must be less than nearline storage days."
  }
  
  validation {
    condition = var.storage_config.nearline_storage_days < var.storage_config.coldline_storage_days
    error_message = "Nearline storage days must be less than coldline storage days."
  }
  
  validation {
    condition = var.storage_config.training_data_retention_days >= 90
    error_message = "Training data retention must be at least 90 days."
  }
  
  validation {
    condition = var.storage_config.model_artifacts_retention_days >= 30
    error_message = "Model artifacts retention must be at least 30 days."
  }
}

# BigQuery configuration
variable "bigquery_config" {
  description = "Configuration for BigQuery datasets and tables"
  type = object({
    # Data retention
    default_table_expiration_days = optional(number, 90)
    
    # Partitioning and clustering
    partition_field = optional(string, "timestamp")
    clustering_fields = optional(list(string), ["user_id", "interaction_type"])
    
    # Query optimization
    require_partition_filter = optional(bool, true)
    
    # Data location
    location = optional(string, null) # Uses var.region if not specified
  })
  
  default = {
    default_table_expiration_days = 90
    partition_field = "timestamp"
    clustering_fields = ["user_id", "interaction_type"]
    require_partition_filter = true
    location = null
  }
  
  validation {
    condition = var.bigquery_config.default_table_expiration_days >= 1
    error_message = "Default table expiration must be at least 1 day."
  }
  
  validation {
    condition = length(var.bigquery_config.clustering_fields) <= 4
    error_message = "Maximum 4 clustering fields are supported."
  }
}

# Monitoring and logging configuration
variable "monitoring_config" {
  description = "Configuration for monitoring and alerting"
  type = object({
    # Logging
    enable_audit_logs = optional(bool, true)
    log_retention_days = optional(number, 30)
    
    # Monitoring
    enable_monitoring = optional(bool, true)
    
    # Alerting
    enable_alerting = optional(bool, true)
    notification_email = optional(string, null)
    
    # Performance metrics
    enable_performance_monitoring = optional(bool, true)
    
    # Cost monitoring
    enable_cost_monitoring = optional(bool, true)
    monthly_budget_amount = optional(number, null)
    budget_currency = optional(string, "USD")
  })
  
  default = {
    enable_audit_logs = true
    log_retention_days = 30
    enable_monitoring = true
    enable_alerting = true
    notification_email = null
    enable_performance_monitoring = true
    enable_cost_monitoring = true
    monthly_budget_amount = null
    budget_currency = "USD"
  }
  
  validation {
    condition = var.monitoring_config.log_retention_days >= 1 && var.monitoring_config.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653 (10 years)."
  }
  
  validation {
    condition = var.monitoring_config.notification_email == null || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.monitoring_config.notification_email))
    error_message = "Notification email must be a valid email address."
  }
  
  validation {
    condition = var.monitoring_config.monthly_budget_amount == null || var.monitoring_config.monthly_budget_amount > 0
    error_message = "Monthly budget amount must be positive."
  }
  
  validation {
    condition = contains(["USD", "EUR", "GBP", "CAD", "AUD", "JPY"], var.monitoring_config.budget_currency)
    error_message = "Budget currency must be one of: USD, EUR, GBP, CAD, AUD, JPY."
  }
}

# Feature flags for optional components
variable "feature_flags" {
  description = "Feature flags to enable/disable optional components"
  type = object({
    # CI/CD components
    enable_cloud_build = optional(bool, true)
    enable_github_integration = optional(bool, false)
    
    # Security components
    enable_vpc_connector = optional(bool, false)
    enable_private_endpoints = optional(bool, false)
    enable_workload_identity = optional(bool, true)
    
    # Advanced features
    enable_a_b_testing = optional(bool, false)
    enable_canary_deployments = optional(bool, false)
    enable_auto_scaling = optional(bool, true)
    
    # Data features
    enable_data_lineage = optional(bool, true)
    enable_data_validation = optional(bool, true)
    enable_feature_store = optional(bool, false)
    
    # ML features
    enable_model_monitoring = optional(bool, true)
    enable_drift_detection = optional(bool, false)
    enable_explainability = optional(bool, false)
  })
  
  default = {
    enable_cloud_build = true
    enable_github_integration = false
    enable_vpc_connector = false
    enable_private_endpoints = false
    enable_workload_identity = true
    enable_a_b_testing = false
    enable_canary_deployments = false
    enable_auto_scaling = true
    enable_data_lineage = true
    enable_data_validation = true
    enable_feature_store = false
    enable_model_monitoring = true
    enable_drift_detection = false
    enable_explainability = false
  }
}

# Resource tagging and labeling
variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9-_]*$", k)) && can(regex("^[a-z0-9-_]*$", v))
    ])
    error_message = "Label keys must start with a lowercase letter and contain only lowercase letters, numbers, hyphens, and underscores. Label values must contain only lowercase letters, numbers, hyphens, and underscores."
  }
}

# Cost optimization settings
variable "cost_optimization" {
  description = "Configuration for cost optimization features"
  type = object({
    # Resource scheduling
    enable_scheduled_scaling = optional(bool, false)
    scale_down_schedule = optional(string, "0 18 * * 1-5") # 6 PM weekdays
    scale_up_schedule = optional(string, "0 8 * * 1-5")   # 8 AM weekdays
    
    # Preemptible instances
    use_preemptible_training = optional(bool, false)
    
    # Storage optimization
    enable_lifecycle_management = optional(bool, true)
    
    # Compute optimization
    enable_cpu_scaling = optional(bool, true)
    enable_memory_scaling = optional(bool, true)
    
    # ML optimization
    enable_model_caching = optional(bool, true)
    enable_prediction_caching = optional(bool, true)
  })
  
  default = {
    enable_scheduled_scaling = false
    scale_down_schedule = "0 18 * * 1-5"
    scale_up_schedule = "0 8 * * 1-5"
    use_preemptible_training = false
    enable_lifecycle_management = true
    enable_cpu_scaling = true
    enable_memory_scaling = true
    enable_model_caching = true
    enable_prediction_caching = true
  }
  
  validation {
    condition = var.cost_optimization.scale_down_schedule == null || can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.cost_optimization.scale_down_schedule))
    error_message = "Scale down schedule must be a valid cron expression."
  }
  
  validation {
    condition = var.cost_optimization.scale_up_schedule == null || can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.cost_optimization.scale_up_schedule))
    error_message = "Scale up schedule must be a valid cron expression."
  }
}