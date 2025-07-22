# Variables for Financial Compliance Monitoring Infrastructure
# This file defines all configurable parameters for the compliance monitoring system

variable "project_id" {
  description = "GCP Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "GCP region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)."
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

# Spanner Configuration
variable "spanner_instance_config" {
  description = "Spanner instance configuration (regional or multi-regional)"
  type        = string
  default     = "regional-us-central1"
  validation {
    condition = can(regex("^(regional|nam|eur|asia)-", var.spanner_instance_config))
    error_message = "Spanner instance config must be a valid regional or multi-regional configuration."
  }
}

variable "spanner_node_count" {
  description = "Number of nodes for the Spanner instance"
  type        = number
  default     = 2
  validation {
    condition     = var.spanner_node_count >= 1 && var.spanner_node_count <= 1000
    error_message = "Spanner node count must be between 1 and 1000."
  }
}

variable "spanner_processing_units" {
  description = "Processing units for Spanner instance (alternative to node count)"
  type        = number
  default     = null
  validation {
    condition = var.spanner_processing_units == null || (var.spanner_processing_units >= 100 && var.spanner_processing_units <= 100000)
    error_message = "Processing units must be between 100 and 100000, or null to use node count."
  }
}

# Cloud Tasks Configuration
variable "task_queue_max_concurrent_dispatches" {
  description = "Maximum number of concurrent task dispatches"
  type        = number
  default     = 10
  validation {
    condition     = var.task_queue_max_concurrent_dispatches >= 1 && var.task_queue_max_concurrent_dispatches <= 1000
    error_message = "Max concurrent dispatches must be between 1 and 1000."
  }
}

variable "task_queue_max_retry_duration" {
  description = "Maximum retry duration for tasks in seconds"
  type        = string
  default     = "3600s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.task_queue_max_retry_duration))
    error_message = "Max retry duration must be in seconds format (e.g., '3600s')."
  }
}

variable "task_queue_max_attempts" {
  description = "Maximum number of retry attempts for failed tasks"
  type        = number
  default     = 5
  validation {
    condition     = var.task_queue_max_attempts >= 1 && var.task_queue_max_attempts <= 100
    error_message = "Max attempts must be between 1 and 100."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions (MB)"
  type        = number
  default     = 512
  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances"
  type        = number
  default     = 0
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Min instances must be between 0 and 1000."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 100
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Max instances must be between 1 and 3000."
  }
}

# Compliance Configuration
variable "compliance_rules" {
  description = "Compliance rules configuration"
  type = object({
    kyc_threshold       = number
    aml_high_risk_score = number
    cross_border_limit  = number
    high_risk_countries = list(string)
  })
  default = {
    kyc_threshold       = 10000
    aml_high_risk_score = 75
    cross_border_limit  = 100000
    high_risk_countries = ["XX", "YY"]
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring and alerting"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Security Configuration
variable "enable_audit_logs" {
  description = "Enable audit logging for compliance"
  type        = bool
  default     = true
}

variable "allowed_ingress_cidrs" {
  description = "CIDR blocks allowed to access the compliance API"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
  validation {
    condition = alltrue([
      for cidr in var.allowed_ingress_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR blocks."
  }
}

# Naming and Tagging
variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "fin-compliance"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "financial-compliance"
    managed-by  = "terraform"
    cost-center = "compliance"
  }
  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Management
variable "budget_amount" {
  description = "Monthly budget amount for the compliance system (USD)"
  type        = number
  default     = 1000
  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages"
  type        = list(number)
  default     = [50, 75, 90, 100]
  validation {
    condition = alltrue([
      for threshold in var.budget_alert_thresholds : threshold > 0 && threshold <= 100
    ])
    error_message = "Budget thresholds must be between 0 and 100."
  }
}