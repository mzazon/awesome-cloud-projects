# Environment and naming variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "media-workflow"
  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

# MediaConnect configuration
variable "source_whitelist_cidr" {
  description = "CIDR block for MediaConnect source whitelist"
  type        = string
  default     = "0.0.0.0/0"
  validation {
    condition     = can(cidrhost(var.source_whitelist_cidr, 0))
    error_message = "Source whitelist must be a valid CIDR block."
  }
}

variable "ingest_port" {
  description = "Port for MediaConnect stream ingestion"
  type        = number
  default     = 5000
  validation {
    condition     = var.ingest_port > 1024 && var.ingest_port < 65536
    error_message = "Ingest port must be between 1024 and 65535."
  }
}

variable "primary_output_destination" {
  description = "Destination IP for primary output stream"
  type        = string
  default     = "10.0.0.100"
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.primary_output_destination))
    error_message = "Primary output destination must be a valid IP address."
  }
}

variable "backup_output_destination" {
  description = "Destination IP for backup output stream"
  type        = string
  default     = "10.0.0.101"
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.backup_output_destination))
    error_message = "Backup output destination must be a valid IP address."
  }
}

variable "primary_output_port" {
  description = "Port for primary output stream"
  type        = number
  default     = 5001
  validation {
    condition     = var.primary_output_port > 1024 && var.primary_output_port < 65536
    error_message = "Primary output port must be between 1024 and 65535."
  }
}

variable "backup_output_port" {
  description = "Port for backup output stream"
  type        = number
  default     = 5002
  validation {
    condition     = var.backup_output_port > 1024 && var.backup_output_port < 65536
    error_message = "Backup output port must be between 1024 and 65535."
  }
}

# Monitoring thresholds
variable "packet_loss_threshold" {
  description = "Packet loss percentage threshold for alarms"
  type        = number
  default     = 0.1
  validation {
    condition     = var.packet_loss_threshold >= 0 && var.packet_loss_threshold <= 100
    error_message = "Packet loss threshold must be between 0 and 100."
  }
}

variable "jitter_threshold_ms" {
  description = "Jitter threshold in milliseconds for alarms"
  type        = number
  default     = 50
  validation {
    condition     = var.jitter_threshold_ms > 0 && var.jitter_threshold_ms <= 1000
    error_message = "Jitter threshold must be between 1 and 1000 milliseconds."
  }
}

variable "workflow_trigger_threshold" {
  description = "Packet loss threshold for triggering workflow"
  type        = number
  default     = 0.05
  validation {
    condition     = var.workflow_trigger_threshold >= 0 && var.workflow_trigger_threshold <= 100
    error_message = "Workflow trigger threshold must be between 0 and 100."
  }
}

# Notification configuration
variable "notification_email" {
  description = "Email address for SNS notifications"
  type        = string
  default     = "admin@example.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address."
  }
}

# Lambda configuration
variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.lambda_timeout > 0 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# Step Functions configuration
variable "step_functions_type" {
  description = "Type of Step Functions state machine (STANDARD or EXPRESS)"
  type        = string
  default     = "EXPRESS"
  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.step_functions_type)
    error_message = "Step Functions type must be either STANDARD or EXPRESS."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}