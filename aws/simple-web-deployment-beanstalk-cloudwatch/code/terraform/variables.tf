# Input variables for the Elastic Beanstalk and CloudWatch deployment

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1)."
  }
}

variable "application_name" {
  description = "Name of the Elastic Beanstalk application"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.application_name)) || var.application_name == ""
    error_message = "Application name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment_name" {
  description = "Name of the Elastic Beanstalk environment"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.environment_name)) || var.environment_name == ""
    error_message = "Environment name must contain only alphanumeric characters and hyphens."
  }
}

variable "solution_stack_name" {
  description = "Elastic Beanstalk solution stack name"
  type        = string
  default     = "64bit Amazon Linux 2023 v4.6.1 running Python 3.11"
}

variable "instance_type" {
  description = "EC2 instance type for Elastic Beanstalk environment"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling group"
  type        = number
  default     = 1
  
  validation {
    condition = var.min_size >= 1 && var.min_size <= 10
    error_message = "Minimum size must be between 1 and 10."
  }
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling group"
  type        = number
  default     = 2
  
  validation {
    condition = var.max_size >= 1 && var.max_size <= 20
    error_message = "Maximum size must be between 1 and 20."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

variable "enhanced_health_reporting" {
  description = "Enable enhanced health reporting for the Elastic Beanstalk environment"
  type        = bool
  default     = true
}

variable "health_streaming_enabled" {
  description = "Enable health log streaming to CloudWatch"
  type        = bool
  default     = true
}

variable "stream_logs" {
  description = "Enable application log streaming to CloudWatch"
  type        = bool
  default     = true
}

variable "delete_logs_on_terminate" {
  description = "Delete CloudWatch logs when environment is terminated"
  type        = bool
  default     = false
}

variable "enable_alarms" {
  description = "Create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "alarm_notification_email" {
  description = "Email address for alarm notifications (leave empty to skip SNS topic creation)"
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alarm_notification_email)) || var.alarm_notification_email == ""
    error_message = "Email must be a valid email address or empty string."
  }
}

variable "health_alarm_threshold" {
  description = "Threshold for environment health alarm (higher values indicate worse health)"
  type        = number
  default     = 15
  
  validation {
    condition = var.health_alarm_threshold >= 0 && var.health_alarm_threshold <= 25
    error_message = "Health alarm threshold must be between 0 and 25."
  }
}

variable "error_4xx_threshold" {
  description = "Threshold for 4xx error alarm (number of errors per evaluation period)"
  type        = number
  default     = 10
  
  validation {
    condition = var.error_4xx_threshold >= 1 && var.error_4xx_threshold <= 1000
    error_message = "4xx error threshold must be between 1 and 1000."
  }
}

variable "vpc_id" {
  description = "VPC ID for the Elastic Beanstalk environment (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Elastic Beanstalk environment (leave empty for default subnets)"
  type        = list(string)
  default     = []
}

variable "associate_public_ip_address" {
  description = "Associate public IP addresses with EC2 instances"
  type        = bool
  default     = true
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "SimpleWebApp"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Recipe      = "simple-web-deployment-beanstalk-cloudwatch"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}