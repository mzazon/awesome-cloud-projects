# Input Variables for Performance Testing Pipeline Infrastructure
# This file defines all configurable parameters for the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
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
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition = contains([
      "dev", "staging", "prod", "test"
    ], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "application_name" {
  description = "Name of the application for consistent resource naming"
  type        = string
  default     = "perf-test-app"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Instance Group Configuration
variable "instance_machine_type" {
  description = "Machine type for application instances"
  type        = string
  default     = "e2-medium"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.instance_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "min_replicas" {
  description = "Minimum number of instances in the managed instance group"
  type        = number
  default     = 2
  validation {
    condition     = var.min_replicas >= 1 && var.min_replicas <= 100
    error_message = "Minimum replicas must be between 1 and 100."
  }
}

variable "max_replicas" {
  description = "Maximum number of instances in the managed instance group"
  type        = number
  default     = 10
  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 100
    error_message = "Maximum replicas must be between 1 and 100."
  }
}

variable "target_cpu_utilization" {
  description = "Target CPU utilization for autoscaling (as a decimal, e.g., 0.7 for 70%)"
  type        = number
  default     = 0.7
  validation {
    condition     = var.target_cpu_utilization > 0 && var.target_cpu_utilization <= 1
    error_message = "Target CPU utilization must be between 0 and 1."
  }
}

# Load Balancer Configuration
variable "health_check_path" {
  description = "HTTP path for health checks"
  type        = string
  default     = "/"
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  validation {
    condition     = var.health_check_timeout >= 1 && var.health_check_timeout <= 300
    error_message = "Health check timeout must be between 1 and 300 seconds."
  }
}

# Cloud Function Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
  type        = number
  default     = 512
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
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

variable "function_max_instances" {
  description = "Maximum number of function instances"
  type        = number
  default     = 10
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Maximum function instances must be between 1 and 1000."
  }
}

# Performance Test Configuration
variable "default_test_duration" {
  description = "Default duration for performance tests in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.default_test_duration >= 10 && var.default_test_duration <= 3600
    error_message = "Test duration must be between 10 and 3600 seconds."
  }
}

variable "default_concurrent_users" {
  description = "Default number of concurrent users for performance tests"
  type        = number
  default     = 20
  validation {
    condition     = var.default_concurrent_users >= 1 && var.default_concurrent_users <= 1000
    error_message = "Concurrent users must be between 1 and 1000."
  }
}

variable "default_requests_per_second" {
  description = "Default requests per second for performance tests"
  type        = number
  default     = 10
  validation {
    condition     = var.default_requests_per_second >= 1 && var.default_requests_per_second <= 10000
    error_message = "Requests per second must be between 1 and 10000."
  }
}

# Scheduling Configuration
variable "daily_test_schedule" {
  description = "Cron schedule for daily performance tests (UTC)"
  type        = string
  default     = "0 2 * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.daily_test_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

variable "hourly_test_schedule" {
  description = "Cron schedule for hourly light performance tests (UTC)"
  type        = string
  default     = "0 * * * *"
  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.hourly_test_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

# Monitoring Configuration
variable "alert_response_time_threshold" {
  description = "Response time threshold for alerting in seconds"
  type        = number
  default     = 2.0
  validation {
    condition     = var.alert_response_time_threshold > 0 && var.alert_response_time_threshold <= 60
    error_message = "Response time threshold must be between 0 and 60 seconds."
  }
}

variable "alert_error_rate_threshold" {
  description = "Error rate threshold for alerting (as a decimal, e.g., 0.05 for 5%)"
  type        = number
  default     = 0.05
  validation {
    condition     = var.alert_error_rate_threshold >= 0 && var.alert_error_rate_threshold <= 1
    error_message = "Error rate threshold must be between 0 and 1."
  }
}

variable "notification_email" {
  description = "Email address for alert notifications (optional)"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

# Resource Naming and Tagging
variable "resource_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "performance-testing"
    managed-by  = "terraform"
    cost-center = "engineering"
  }
  validation {
    condition     = alltrue([for k, v in var.resource_labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}