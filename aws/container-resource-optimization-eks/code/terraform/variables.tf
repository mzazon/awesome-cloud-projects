# Input variables for EKS container resource optimization infrastructure
# These variables allow customization of the deployment for different environments

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster to configure for cost optimization"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name)) && length(var.cluster_name) <= 100
    error_message = "Cluster name must contain only alphanumeric characters and hyphens, and be less than 100 characters."
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

variable "namespace_name" {
  description = "Kubernetes namespace for cost optimization workloads"
  type        = string
  default     = "cost-optimization"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.namespace_name)) && length(var.namespace_name) <= 63
    error_message = "Namespace name must be lowercase alphanumeric with hyphens only, max 63 characters."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "enable_vpa_auto_mode" {
  description = "Enable VPA automatic mode (will restart pods automatically)"
  type        = bool
  default     = false
}

variable "vpa_update_mode" {
  description = "VPA update mode: Off, Initial, Recreation, or Auto"
  type        = string
  default     = "Off"
  
  validation {
    condition     = contains(["Off", "Initial", "Recreation", "Auto"], var.vpa_update_mode)
    error_message = "VPA update mode must be one of: Off, Initial, Recreation, Auto."
  }
}

variable "test_app_replicas" {
  description = "Number of replicas for the test application"
  type        = number
  default     = 3
  
  validation {
    condition     = var.test_app_replicas >= 1 && var.test_app_replicas <= 10
    error_message = "Test app replicas must be between 1 and 10."
  }
}

variable "test_app_cpu_request" {
  description = "CPU request for test application (intentionally overprovisioned)"
  type        = string
  default     = "500m"
}

variable "test_app_memory_request" {
  description = "Memory request for test application (intentionally overprovisioned)"
  type        = string
  default     = "512Mi"
}

variable "test_app_cpu_limit" {
  description = "CPU limit for test application"
  type        = string
  default     = "1000m"
}

variable "test_app_memory_limit" {
  description = "Memory limit for test application"
  type        = string
  default     = "1024Mi"
}

variable "vpa_min_cpu" {
  description = "Minimum CPU that VPA can recommend"
  type        = string
  default     = "50m"
}

variable "vpa_min_memory" {
  description = "Minimum memory that VPA can recommend"
  type        = string
  default     = "64Mi"
}

variable "vpa_max_cpu" {
  description = "Maximum CPU that VPA can recommend"
  type        = string
  default     = "2000m"
}

variable "vpa_max_memory" {
  description = "Maximum memory that VPA can recommend"
  type        = string
  default     = "2048Mi"
}

variable "cost_alert_threshold" {
  description = "CPU utilization threshold (%) below which cost alerts are triggered"
  type        = number
  default     = 30
  
  validation {
    condition     = var.cost_alert_threshold >= 10 && var.cost_alert_threshold <= 90
    error_message = "Cost alert threshold must be between 10 and 90 percent."
  }
}

variable "notification_email" {
  description = "Email address for cost optimization notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification_email must be a valid email address."
  }
}

variable "enable_cost_dashboard" {
  description = "Create CloudWatch dashboard for cost monitoring"
  type        = bool
  default     = true
}

variable "metrics_server_replicas" {
  description = "Number of replicas for metrics server"
  type        = number
  default     = 2
  
  validation {
    condition     = var.metrics_server_replicas >= 1 && var.metrics_server_replicas <= 5
    error_message = "Metrics server replicas must be between 1 and 5."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "create_test_application" {
  description = "Create the test application for demonstrating VPA functionality"
  type        = bool
  default     = true
}

variable "enable_cost_alerts" {
  description = "Enable automated cost alerting via CloudWatch alarms"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}