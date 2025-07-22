# Variables for AWS App2Container Infrastructure
# This file defines all the configurable variables for the App2Container Terraform deployment

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^(dev|test|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, test, staging, prod."
  }
}

variable "task_cpu" {
  description = "CPU units for the ECS task (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "512"
  validation {
    condition     = can(regex("^(256|512|1024|2048|4096)$", var.task_cpu))
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory in MB for the ECS task. Must be compatible with CPU value."
  type        = string
  default     = "1024"
  validation {
    condition     = can(regex("^(512|1024|2048|3072|4096|5120|6144|7168|8192|16384|30720)$", var.task_memory))
    error_message = "Task memory must be a valid value compatible with the selected CPU."
  }
}

variable "container_port" {
  description = "Port on which the containerized application listens"
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

variable "health_check_path" {
  description = "Path for ALB health checks"
  type        = string
  default     = "/"
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "desired_count" {
  description = "Desired number of ECS tasks to run"
  type        = number
  default     = 2
  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 100
    error_message = "Desired count must be between 1 and 100."
  }
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto scaling"
  type        = number
  default     = 1
  validation {
    condition     = var.min_capacity >= 1
    error_message = "Minimum capacity must be at least 1."
  }
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto scaling"
  type        = number
  default     = 10
  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 100
    error_message = "Maximum capacity must be between 1 and 100."
  }
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70.0
  validation {
    condition     = var.cpu_target_value > 0 && var.cpu_target_value <= 100
    error_message = "CPU target value must be between 0 and 100."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the ECS cluster"
  type        = bool
  default     = true
}

variable "enable_execute_command" {
  description = "Enable ECS Exec for debugging containers"
  type        = bool
  default     = false
}

variable "codebuild_compute_type" {
  description = "Compute type for CodeBuild projects"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM",
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.codebuild_compute_type)
    error_message = "CodeBuild compute type must be a valid value."
  }
}

variable "codebuild_image" {
  description = "Docker image for CodeBuild projects"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
}

variable "enable_spot_instances" {
  description = "Enable Fargate Spot for cost optimization"
  type        = bool
  default     = false
}

variable "spot_allocation_strategy" {
  description = "Allocation strategy for Fargate Spot instances"
  type        = string
  default     = "diversified"
  validation {
    condition     = can(regex("^(diversified|spread)$", var.spot_allocation_strategy))
    error_message = "Spot allocation strategy must be 'diversified' or 'spread'."
  }
}

variable "alb_deletion_protection" {
  description = "Enable deletion protection for the Application Load Balancer"
  type        = bool
  default     = false
}

variable "enable_alb_access_logs" {
  description = "Enable access logs for the Application Load Balancer"
  type        = bool
  default     = true
}

variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS listener (optional)"
  type        = string
  default     = ""
}

variable "enable_https_redirect" {
  description = "Enable automatic HTTP to HTTPS redirect"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where resources will be created (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for ALB and ECS tasks (leave empty to use default VPC subnets)"
  type        = list(string)
  default     = []
}

variable "custom_domain_name" {
  description = "Custom domain name for the application (optional)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for custom domain (required if custom_domain_name is set)"
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Enable AWS WAF for the Application Load Balancer"
  type        = bool
  default     = false
}

variable "waf_rules" {
  description = "List of WAF rules to apply"
  type = list(object({
    name     = string
    priority = number
    action   = string
  }))
  default = []
}

variable "backup_retention_days" {
  description = "Number of days to retain backup artifacts"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup for disaster recovery"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "Secondary region for cross-region backups"
  type        = string
  default     = ""
}

variable "notification_email" {
  description = "Email address for receiving alerts and notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "alarm_threshold_cpu" {
  description = "CPU utilization threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 80
  validation {
    condition     = var.alarm_threshold_cpu > 0 && var.alarm_threshold_cpu <= 100
    error_message = "CPU alarm threshold must be between 0 and 100."
  }
}

variable "alarm_threshold_memory" {
  description = "Memory utilization threshold for CloudWatch alarms (percentage)"
  type        = number
  default     = 80
  validation {
    condition     = var.alarm_threshold_memory > 0 && var.alarm_threshold_memory <= 100
    error_message = "Memory alarm threshold must be between 0 and 100."
  }
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for the application"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting sensitive data (leave empty to use default AWS managed keys)"
  type        = string
  default     = ""
}

variable "enable_secrets_manager" {
  description = "Use AWS Secrets Manager for storing application secrets"
  type        = bool
  default     = true
}

variable "secrets_rotation_days" {
  description = "Number of days for automatic secrets rotation"
  type        = number
  default     = 90
  validation {
    condition     = var.secrets_rotation_days >= 1 && var.secrets_rotation_days <= 365
    error_message = "Secrets rotation days must be between 1 and 365."
  }
}

variable "enable_blue_green_deployment" {
  description = "Enable blue/green deployment strategy"
  type        = bool
  default     = false
}

variable "deployment_configuration" {
  description = "ECS deployment configuration"
  type = object({
    maximum_percent         = number
    minimum_healthy_percent = number
  })
  default = {
    maximum_percent         = 200
    minimum_healthy_percent = 50
  }
  validation {
    condition = (
      var.deployment_configuration.maximum_percent >= 100 &&
      var.deployment_configuration.maximum_percent <= 200 &&
      var.deployment_configuration.minimum_healthy_percent >= 0 &&
      var.deployment_configuration.minimum_healthy_percent <= 100
    )
    error_message = "Deployment configuration values must be within valid ranges."
  }
}

variable "enable_service_discovery" {
  description = "Enable AWS Cloud Map service discovery"
  type        = bool
  default     = false
}

variable "service_discovery_namespace" {
  description = "Cloud Map namespace for service discovery"
  type        = string
  default     = ""
}

variable "enable_app_mesh" {
  description = "Enable AWS App Mesh for service mesh capabilities"
  type        = bool
  default     = false
}

variable "app_mesh_name" {
  description = "Name of the App Mesh"
  type        = string
  default     = ""
}

variable "performance_mode" {
  description = "Performance mode for the application (standard, optimized)"
  type        = string
  default     = "standard"
  validation {
    condition     = can(regex("^(standard|optimized)$", var.performance_mode))
    error_message = "Performance mode must be 'standard' or 'optimized'."
  }
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features (Spot instances, scheduling, etc.)"
  type        = bool
  default     = true
}

variable "maintenance_window" {
  description = "Preferred maintenance window for automated updates (format: day:HH:MM-day:HH:MM)"
  type        = string
  default     = "sun:03:00-sun:04:00"
  validation {
    condition = can(regex("^(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):[0-2][0-9]:[0-5][0-9]$", var.maintenance_window))
    error_message = "Maintenance window must be in format 'day:HH:MM-day:HH:MM'."
  }
}

variable "compliance_mode" {
  description = "Compliance mode for additional security and governance features"
  type        = string
  default     = "none"
  validation {
    condition     = can(regex("^(none|basic|strict|pci|hipaa)$", var.compliance_mode))
    error_message = "Compliance mode must be one of: none, basic, strict, pci, hipaa."
  }
}