# General Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "web-app"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration Variables
variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, default VPC will be used."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for Auto Scaling Group and Load Balancer. If not provided, default subnets will be used."
  type        = list(string)
  default     = []
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the load balancer"
  type        = bool
  default     = false
}

# Auto Scaling Configuration Variables
variable "min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.min_size >= 1
    error_message = "Minimum size must be at least 1."
  }
}

variable "max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 8
  
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "Maximum size must be greater than or equal to minimum size."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "Desired capacity must be between min_size and max_size."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group"
  type        = string
  default     = "t3.micro"
}

variable "health_check_grace_period" {
  description = "Time (in seconds) after instance launch before health checks start"
  type        = number
  default     = 300
  
  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "Health check grace period must be non-negative."
  }
}

variable "default_cooldown" {
  description = "Default cooldown period (in seconds) for Auto Scaling Group"
  type        = number
  default     = 300
  
  validation {
    condition     = var.default_cooldown >= 0
    error_message = "Default cooldown must be non-negative."
  }
}

# Scaling Policy Configuration Variables
variable "cpu_target_value" {
  description = "Target CPU utilization percentage for target tracking scaling"
  type        = number
  default     = 70.0
  
  validation {
    condition     = var.cpu_target_value > 0 && var.cpu_target_value <= 100
    error_message = "CPU target value must be between 0 and 100."
  }
}

variable "alb_request_count_target" {
  description = "Target request count per target for ALB request count scaling"
  type        = number
  default     = 1000.0
  
  validation {
    condition     = var.alb_request_count_target > 0
    error_message = "ALB request count target must be positive."
  }
}

variable "scale_out_cooldown" {
  description = "Cooldown period (in seconds) for scale out actions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.scale_out_cooldown >= 0
    error_message = "Scale out cooldown must be non-negative."
  }
}

variable "scale_in_cooldown" {
  description = "Cooldown period (in seconds) for scale in actions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.scale_in_cooldown >= 0
    error_message = "Scale in cooldown must be non-negative."
  }
}

# Scheduled Scaling Configuration Variables
variable "enable_scheduled_scaling" {
  description = "Enable scheduled scaling actions"
  type        = bool
  default     = true
}

variable "business_hours_scale_up_recurrence" {
  description = "Cron expression for scaling up during business hours"
  type        = string
  default     = "0 9 * * MON-FRI"
}

variable "business_hours_scale_down_recurrence" {
  description = "Cron expression for scaling down after business hours"
  type        = string
  default     = "0 18 * * MON-FRI"
}

variable "business_hours_min_size" {
  description = "Minimum size during business hours"
  type        = number
  default     = 3
}

variable "business_hours_max_size" {
  description = "Maximum size during business hours"
  type        = number
  default     = 10
}

variable "business_hours_desired_capacity" {
  description = "Desired capacity during business hours"
  type        = number
  default     = 4
}

variable "after_hours_min_size" {
  description = "Minimum size after business hours"
  type        = number
  default     = 1
}

variable "after_hours_max_size" {
  description = "Maximum size after business hours"
  type        = number
  default     = 8
}

variable "after_hours_desired_capacity" {
  description = "Desired capacity after business hours"
  type        = number
  default     = 2
}

# Load Balancer Configuration Variables
variable "load_balancer_type" {
  description = "Type of load balancer (application or network)"
  type        = string
  default     = "application"
  
  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "Load balancer type must be either 'application' or 'network'."
  }
}

variable "internal_load_balancer" {
  description = "Whether the load balancer is internal (true) or internet-facing (false)"
  type        = bool
  default     = false
}

variable "enable_http2" {
  description = "Enable HTTP/2 on the load balancer"
  type        = bool
  default     = true
}

# Target Group Configuration Variables
variable "health_check_enabled" {
  description = "Enable health checks for the target group"
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  
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
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks required"
  type        = number
  default     = 2
  
  validation {
    condition     = var.healthy_threshold >= 2 && var.healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks required"
  type        = number
  default     = 3
  
  validation {
    condition     = var.unhealthy_threshold >= 2 && var.unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

variable "deregistration_delay" {
  description = "Time to wait before deregistering targets (in seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

# CloudWatch Configuration Variables
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for Auto Scaling Group"
  type        = bool
  default     = true
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "high_cpu_threshold" {
  description = "CPU threshold percentage for high CPU alarm"
  type        = number
  default     = 80
  
  validation {
    condition     = var.high_cpu_threshold > 0 && var.high_cpu_threshold <= 100
    error_message = "High CPU threshold must be between 0 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

# Security Configuration Variables
variable "enable_imds_v2" {
  description = "Enable Instance Metadata Service Version 2 (IMDSv2)"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the load balancer"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_access_logs" {
  description = "Enable access logs for the load balancer"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket name for load balancer access logs (required if enable_access_logs is true)"
  type        = string
  default     = ""
}

variable "access_logs_prefix" {
  description = "S3 prefix for load balancer access logs"
  type        = string
  default     = "alb-logs"
}

# Additional Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}