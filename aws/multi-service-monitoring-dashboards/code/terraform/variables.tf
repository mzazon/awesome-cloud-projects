# Variables for Advanced Multi-Service Monitoring Dashboards
# This file defines all input variables for the monitoring infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "project_name" {
  description = "Name of the project (used for resource naming and tagging)"
  type        = string
  default     = "advanced-monitoring"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "cost_center" {
  description = "Cost center for resource billing and tracking"
  type        = string
  default     = "operations"
}

variable "notification_email" {
  description = "Email address for critical alert notifications"
  type        = string
  default     = "alerts@example.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address."
  }
}

variable "business_unit" {
  description = "Business unit for business metrics tracking"
  type        = string
  default     = "ecommerce"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 120
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
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

variable "metric_collection_schedule" {
  description = "Schedule for business metrics collection (EventBridge expression)"
  type        = string
  default     = "rate(5 minutes)"
  
  validation {
    condition     = can(regex("^rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)$", var.metric_collection_schedule))
    error_message = "Schedule must be a valid EventBridge rate expression."
  }
}

variable "infrastructure_health_schedule" {
  description = "Schedule for infrastructure health checks (EventBridge expression)"
  type        = string
  default     = "rate(10 minutes)"
  
  validation {
    condition     = can(regex("^rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)$", var.infrastructure_health_schedule))
    error_message = "Schedule must be a valid EventBridge rate expression."
  }
}

variable "cost_monitoring_schedule" {
  description = "Schedule for cost monitoring (EventBridge expression)"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition     = can(regex("^rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)$", var.cost_monitoring_schedule))
    error_message = "Schedule must be a valid EventBridge rate expression."
  }
}

variable "anomaly_detection_enabled" {
  description = "Enable CloudWatch anomaly detection for key metrics"
  type        = bool
  default     = true
}

variable "anomaly_detection_band" {
  description = "Anomaly detection band (standard deviations from the mean)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.anomaly_detection_band >= 1 && var.anomaly_detection_band <= 10
    error_message = "Anomaly detection band must be between 1 and 10."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for all services"
  type        = bool
  default     = true
}

variable "dashboard_timezone" {
  description = "Timezone for dashboard display"
  type        = string
  default     = "UTC"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "additional_sns_subscriptions" {
  description = "Additional SNS subscriptions for alerts"
  type = list(object({
    protocol = string
    endpoint = string
    topic    = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for sub in var.additional_sns_subscriptions : contains(["email", "sms", "lambda", "sqs"], sub.protocol)
    ])
    error_message = "SNS subscription protocol must be one of: email, sms, lambda, sqs."
  }
}

variable "custom_metric_namespaces" {
  description = "Custom metric namespaces to create"
  type        = list(string)
  default     = ["Business/Metrics", "Business/Health", "Infrastructure/Health", "Cost/Management"]
}

variable "dashboard_period" {
  description = "Default period for dashboard widgets in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 900, 3600, 21600, 86400], var.dashboard_period)
    error_message = "Dashboard period must be one of: 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

variable "enable_cross_region_monitoring" {
  description = "Enable cross-region monitoring capabilities"
  type        = bool
  default     = false
}

variable "monitoring_regions" {
  description = "List of regions to monitor (when cross-region monitoring is enabled)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "enable_cost_anomaly_detection" {
  description = "Enable cost anomaly detection"
  type        = bool
  default     = true
}

variable "create_sample_resources" {
  description = "Create sample ECS, RDS, and ElastiCache resources for demonstration"
  type        = bool
  default     = false
}

variable "sample_resource_config" {
  description = "Configuration for sample resources"
  type = object({
    ecs_service_name    = string
    rds_instance_id     = string
    elasticache_cluster = string
  })
  default = {
    ecs_service_name    = "web-service"
    rds_instance_id     = "production-db"
    elasticache_cluster = "production-cache"
  }
}