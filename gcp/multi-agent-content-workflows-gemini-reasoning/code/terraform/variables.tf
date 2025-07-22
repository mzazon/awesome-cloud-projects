# =============================================================================
# Variables for GCP Multi-Agent Content Workflows Infrastructure
# =============================================================================
# This file defines all configurable parameters for the multi-agent content
# processing pipeline infrastructure deployment.
# =============================================================================

# Project Configuration
# -----------------------------------------------------------------------------
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region with AI Platform support."
  }
}

# Resource Labeling and Tagging
# -----------------------------------------------------------------------------
variable "labels" {
  description = "Labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    environment   = "development"
    project      = "content-intelligence"
    managed-by   = "terraform"
    component    = "multi-agent-workflows"
    cost-center  = "ai-ml"
  }
  
  validation {
    condition     = length(var.labels) > 0
    error_message = "At least one label must be specified."
  }
}

# Cloud Function Configuration
# -----------------------------------------------------------------------------
variable "function_config" {
  description = "Configuration settings for the Cloud Function trigger"
  type = object({
    memory        = string
    timeout       = number
    max_instances = number
    min_instances = number
  })
  default = {
    memory        = "512Mi"
    timeout       = 540
    max_instances = 10
    min_instances = 0
  }
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_config.memory)
    error_message = "Memory must be a valid Cloud Function memory allocation."
  }
  
  validation {
    condition     = var.function_config.timeout >= 60 && var.function_config.timeout <= 540
    error_message = "Timeout must be between 60 and 540 seconds."
  }
  
  validation {
    condition     = var.function_config.max_instances >= 1 && var.function_config.max_instances <= 100
    error_message = "Max instances must be between 1 and 100."
  }
  
  validation {
    condition     = var.function_config.min_instances >= 0 && var.function_config.min_instances <= var.function_config.max_instances
    error_message = "Min instances must be between 0 and max_instances."
  }
}

# Vertex AI and Gemini Configuration
# -----------------------------------------------------------------------------
variable "gemini_model_config" {
  description = "Configuration for Gemini 2.5 model parameters"
  type = object({
    model_version     = string
    default_temperature = number
    max_output_tokens  = number
    safety_threshold   = string
  })
  default = {
    model_version     = "gemini-2.5-pro"
    default_temperature = 0.1
    max_output_tokens  = 4096
    safety_threshold   = "BLOCK_MEDIUM_AND_ABOVE"
  }
  
  validation {
    condition = contains([
      "gemini-2.5-pro", "gemini-pro", "gemini-pro-vision"
    ], var.gemini_model_config.model_version)
    error_message = "Model version must be a supported Gemini model."
  }
  
  validation {
    condition     = var.gemini_model_config.default_temperature >= 0.0 && var.gemini_model_config.default_temperature <= 2.0
    error_message = "Temperature must be between 0.0 and 2.0."
  }
  
  validation {
    condition     = var.gemini_model_config.max_output_tokens >= 1 && var.gemini_model_config.max_output_tokens <= 8192
    error_message = "Max output tokens must be between 1 and 8192."
  }
}

# Content Processing Configuration
# -----------------------------------------------------------------------------
variable "content_processing_config" {
  description = "Configuration for content processing capabilities"
  type = object({
    supported_text_formats  = list(string)
    supported_image_formats = list(string)
    supported_video_formats = list(string)
    max_file_size_mb       = number
    enable_ocr             = bool
    enable_speech_to_text  = bool
  })
  default = {
    supported_text_formats  = ["txt", "md", "csv", "json", "pdf", "docx"]
    supported_image_formats = ["jpg", "jpeg", "png", "gif", "bmp", "webp"]
    supported_video_formats = ["mp4", "avi", "mov", "wmv", "webm"]
    max_file_size_mb       = 100
    enable_ocr             = true
    enable_speech_to_text  = true
  }
  
  validation {
    condition     = var.content_processing_config.max_file_size_mb > 0 && var.content_processing_config.max_file_size_mb <= 1000
    error_message = "Max file size must be between 1 and 1000 MB."
  }
}

# Storage Configuration
# -----------------------------------------------------------------------------
variable "storage_config" {
  description = "Configuration for Cloud Storage buckets"
  type = object({
    storage_class           = string
    enable_versioning      = bool
    lifecycle_age_nearline = number
    lifecycle_age_coldline = number
    uniform_bucket_access  = bool
  })
  default = {
    storage_class           = "STANDARD"
    enable_versioning      = true
    lifecycle_age_nearline = 90
    lifecycle_age_coldline = 365
    uniform_bucket_access  = true
  }
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_config.storage_class)
    error_message = "Storage class must be a valid GCS storage class."
  }
  
  validation {
    condition     = var.storage_config.lifecycle_age_nearline > 0 && var.storage_config.lifecycle_age_nearline <= 365
    error_message = "Nearline lifecycle age must be between 1 and 365 days."
  }
  
  validation {
    condition     = var.storage_config.lifecycle_age_coldline >= var.storage_config.lifecycle_age_nearline
    error_message = "Coldline lifecycle age must be greater than or equal to nearline age."
  }
}

# Security and Compliance Configuration
# -----------------------------------------------------------------------------
variable "security_config" {
  description = "Security and compliance configuration settings"
  type = object({
    enable_audit_logs        = bool
    enable_vpc_flow_logs     = bool
    enable_private_google_access = bool
    allowed_ip_ranges        = list(string)
    enable_cmek             = bool
  })
  default = {
    enable_audit_logs        = true
    enable_vpc_flow_logs     = true
    enable_private_google_access = true
    allowed_ip_ranges        = ["0.0.0.0/0"]  # Restrict in production
    enable_cmek             = false
  }
  
  validation {
    condition     = length(var.security_config.allowed_ip_ranges) > 0
    error_message = "At least one IP range must be specified."
  }
}

# Monitoring and Alerting Configuration
# -----------------------------------------------------------------------------
variable "monitoring_config" {
  description = "Configuration for monitoring and alerting"
  type = object({
    enable_alerts           = bool
    notification_channels   = list(string)
    alert_threshold_errors  = number
    alert_threshold_latency = number
    log_retention_days     = number
  })
  default = {
    enable_alerts           = true
    notification_channels   = []
    alert_threshold_errors  = 5
    alert_threshold_latency = 10000  # milliseconds
    log_retention_days     = 30
  }
  
  validation {
    condition     = var.monitoring_config.alert_threshold_errors > 0
    error_message = "Error threshold must be greater than 0."
  }
  
  validation {
    condition     = var.monitoring_config.alert_threshold_latency > 0
    error_message = "Latency threshold must be greater than 0."
  }
  
  validation {
    condition     = var.monitoring_config.log_retention_days >= 1 && var.monitoring_config.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Workflow Configuration
# -----------------------------------------------------------------------------
variable "workflow_config" {
  description = "Configuration for Cloud Workflows execution"
  type = object({
    execution_timeout_seconds = number
    max_concurrent_executions = number
    enable_call_log_level     = string
    retry_policy_max_attempts = number
  })
  default = {
    execution_timeout_seconds = 3600  # 1 hour
    max_concurrent_executions = 100
    enable_call_log_level     = "ALL_CALLS"
    retry_policy_max_attempts = 3
  }
  
  validation {
    condition     = var.workflow_config.execution_timeout_seconds >= 60 && var.workflow_config.execution_timeout_seconds <= 31536000
    error_message = "Execution timeout must be between 60 seconds and 1 year."
  }
  
  validation {
    condition     = var.workflow_config.max_concurrent_executions >= 1 && var.workflow_config.max_concurrent_executions <= 1000
    error_message = "Max concurrent executions must be between 1 and 1000."
  }
  
  validation {
    condition = contains([
      "NO_CALLS_LOG", "ERRORS_ONLY", "ALL_CALLS"
    ], var.workflow_config.enable_call_log_level)
    error_message = "Call log level must be NO_CALLS_LOG, ERRORS_ONLY, or ALL_CALLS."
  }
  
  validation {
    condition     = var.workflow_config.retry_policy_max_attempts >= 1 && var.workflow_config.retry_policy_max_attempts <= 5
    error_message = "Max retry attempts must be between 1 and 5."
  }
}

# Optional Features Configuration
# -----------------------------------------------------------------------------
variable "enable_dlp" {
  description = "Enable Data Loss Prevention (DLP) for content scanning"
  type        = bool
  default     = false
}

variable "create_sample_content" {
  description = "Create sample content files for testing the workflow"
  type        = bool
  default     = true
}

variable "create_dedicated_network" {
  description = "Create a dedicated VPC network for enhanced security"
  type        = bool
  default     = false
}

# Cost Management Configuration
# -----------------------------------------------------------------------------
variable "cost_management" {
  description = "Configuration for cost management and optimization"
  type = object({
    budget_amount_usd          = number
    budget_alert_thresholds    = list(number)
    enable_committed_use       = bool
    enable_preemptible_instances = bool
  })
  default = {
    budget_amount_usd          = 1000
    budget_alert_thresholds    = [0.5, 0.8, 1.0]
    enable_committed_use       = false
    enable_preemptible_instances = false
  }
  
  validation {
    condition     = var.cost_management.budget_amount_usd > 0
    error_message = "Budget amount must be greater than 0."
  }
  
  validation {
    condition = alltrue([
      for threshold in var.cost_management.budget_alert_thresholds :
      threshold > 0 && threshold <= 1.0
    ])
    error_message = "Budget alert thresholds must be between 0 and 1.0."
  }
}

# Data Processing Quotas and Limits
# -----------------------------------------------------------------------------
variable "processing_limits" {
  description = "Configuration for processing quotas and rate limits"
  type = object({
    max_requests_per_minute    = number
    max_concurrent_workflows   = number
    max_file_processing_time   = number
    batch_processing_size      = number
  })
  default = {
    max_requests_per_minute    = 60
    max_concurrent_workflows   = 10
    max_file_processing_time   = 1800  # 30 minutes
    batch_processing_size      = 5
  }
  
  validation {
    condition     = var.processing_limits.max_requests_per_minute > 0 && var.processing_limits.max_requests_per_minute <= 1000
    error_message = "Max requests per minute must be between 1 and 1000."
  }
  
  validation {
    condition     = var.processing_limits.max_concurrent_workflows > 0 && var.processing_limits.max_concurrent_workflows <= 100
    error_message = "Max concurrent workflows must be between 1 and 100."
  }
  
  validation {
    condition     = var.processing_limits.max_file_processing_time >= 60 && var.processing_limits.max_file_processing_time <= 3600
    error_message = "Max file processing time must be between 60 and 3600 seconds."
  }
  
  validation {
    condition     = var.processing_limits.batch_processing_size >= 1 && var.processing_limits.batch_processing_size <= 20
    error_message = "Batch processing size must be between 1 and 20."
  }
}

# AI Agent Configuration
# -----------------------------------------------------------------------------
variable "agent_configurations" {
  description = "Configuration for individual AI agents in the multi-agent system"
  type = object({
    text_agent = object({
      temperature      = number
      max_tokens      = number
      confidence_threshold = number
    })
    image_agent = object({
      temperature      = number
      max_features    = number
      confidence_threshold = number
    })
    video_agent = object({
      temperature      = number
      sample_rate     = number
      confidence_threshold = number
    })
  })
  default = {
    text_agent = {
      temperature      = 0.2
      max_tokens      = 2048
      confidence_threshold = 0.8
    }
    image_agent = {
      temperature      = 0.3
      max_features    = 20
      confidence_threshold = 0.7
    }
    video_agent = {
      temperature      = 0.3
      sample_rate     = 16000
      confidence_threshold = 0.75
    }
  }
  
  validation {
    condition = alltrue([
      var.agent_configurations.text_agent.temperature >= 0.0,
      var.agent_configurations.text_agent.temperature <= 2.0,
      var.agent_configurations.image_agent.temperature >= 0.0,
      var.agent_configurations.image_agent.temperature <= 2.0,
      var.agent_configurations.video_agent.temperature >= 0.0,
      var.agent_configurations.video_agent.temperature <= 2.0
    ])
    error_message = "All agent temperatures must be between 0.0 and 2.0."
  }
  
  validation {
    condition = alltrue([
      var.agent_configurations.text_agent.confidence_threshold >= 0.0,
      var.agent_configurations.text_agent.confidence_threshold <= 1.0,
      var.agent_configurations.image_agent.confidence_threshold >= 0.0,
      var.agent_configurations.image_agent.confidence_threshold <= 1.0,
      var.agent_configurations.video_agent.confidence_threshold >= 0.0,
      var.agent_configurations.video_agent.confidence_threshold <= 1.0
    ])
    error_message = "All confidence thresholds must be between 0.0 and 1.0."
  }
}

# Environment-Specific Configuration
# -----------------------------------------------------------------------------
variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production"
    ], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}