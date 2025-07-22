# Input Variables for Code Review Automation Infrastructure
# This file defines all configurable parameters for the deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must be provided and cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
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

variable "repository_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = "intelligent-review-system"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.repository_name))
    error_message = "Repository name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "function_name" {
  description = "Name of the Cloud Function for code review triggers"
  type        = string
  default     = "code-review-trigger"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.function_name))
    error_message = "Function name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "agent_name" {
  description = "Name of the Firebase Studio AI agent"
  type        = string
  default     = "code-review-agent"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.agent_name))
    error_message = "Agent name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vertex_ai_model" {
  description = "Vertex AI model to use for code analysis"
  type        = string
  default     = "gemini-2.0-flash-thinking"
  validation {
    condition = contains([
      "gemini-2.0-flash-thinking",
      "gemini-1.5-pro",
      "gemini-1.5-flash",
      "gemini-1.0-pro"
    ], var.vertex_ai_model)
    error_message = "Must be a valid Vertex AI Gemini model."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function execution in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 60 && var.function_timeout <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = string
  default     = "512Mi"
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be a valid Cloud Functions Gen2 memory setting."
  }
}

variable "enable_firebase_studio" {
  description = "Enable Firebase Studio integration (requires preview access)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and Logging for the solution"
  type        = bool
  default     = true
}

variable "enable_security_scanning" {
  description = "Enable security scanning features in code review"
  type        = bool
  default     = true
}

variable "max_concurrent_reviews" {
  description = "Maximum number of concurrent code reviews to process"
  type        = number
  default     = 5
  validation {
    condition     = var.max_concurrent_reviews >= 1 && var.max_concurrent_reviews <= 20
    error_message = "Max concurrent reviews must be between 1 and 20."
  }
}

variable "notification_channels" {
  description = "List of notification channels for alerts (email addresses)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for email in var.notification_channels : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification channels must be valid email addresses."
  }
}

variable "code_analysis_config" {
  description = "Configuration for AI code analysis parameters"
  type = object({
    temperature           = number
    max_tokens           = number
    analysis_depth       = string
    include_suggestions  = bool
    check_security       = bool
    check_performance    = bool
    check_best_practices = bool
  })
  default = {
    temperature           = 0.3
    max_tokens           = 4096
    analysis_depth       = "comprehensive"
    include_suggestions  = true
    check_security       = true
    check_performance    = true
    check_best_practices = true
  }
  validation {
    condition = (
      var.code_analysis_config.temperature >= 0.0 &&
      var.code_analysis_config.temperature <= 1.0 &&
      var.code_analysis_config.max_tokens >= 100 &&
      var.code_analysis_config.max_tokens <= 8192 &&
      contains(["basic", "detailed", "comprehensive"], var.code_analysis_config.analysis_depth)
    )
    error_message = "Code analysis configuration values must be within valid ranges."
  }
}

variable "supported_languages" {
  description = "List of programming languages to analyze"
  type        = list(string)
  default     = ["javascript", "typescript", "python", "java", "go", "rust"]
  validation {
    condition = alltrue([
      for lang in var.supported_languages : contains([
        "javascript", "typescript", "python", "java", "go", "rust", "cpp", "csharp", "php", "ruby"
      ], lang)
    ])
    error_message = "All supported languages must be from the approved list."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "code-review-automation"
    component   = "ai-development"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for key, value in var.labels : can(regex("^[a-z0-9_-]+$", key)) && can(regex("^[a-z0-9_-]+$", value))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}