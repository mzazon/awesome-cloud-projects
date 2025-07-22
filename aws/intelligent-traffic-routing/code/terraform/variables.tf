# Project Configuration Variables
variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "global-lb"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "Secondary AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "tertiary_region" {
  description = "Tertiary AWS region for deployment"
  type        = string
  default     = "ap-southeast-1"
}

# Domain Configuration
variable "domain_name" {
  description = "Domain name for the hosted zone (will be created as demo domain)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.domain_name == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain format."
  }
}

variable "create_hosted_zone" {
  description = "Whether to create a new Route53 hosted zone or use existing"
  type        = bool
  default     = true
}

variable "hosted_zone_id" {
  description = "Existing hosted zone ID (required if create_hosted_zone is false)"
  type        = string
  default     = ""
}

# Auto Scaling Configuration
variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t2.micro", "t2.small", "t2.medium", "t2.large"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "min_capacity" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_capacity >= 1 && var.min_capacity <= 10
    error_message = "Minimum capacity must be between 1 and 10."
  }
}

variable "max_capacity" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 3
  
  validation {
    condition     = var.max_capacity >= 1 && var.max_capacity <= 20
    error_message = "Maximum capacity must be between 1 and 20."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 20
    error_message = "Desired capacity must be between 1 and 20."
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC (will be modified per region)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones_count" {
  description = "Number of availability zones to use per region"
  type        = number
  default     = 2
  
  validation {
    condition     = var.availability_zones_count >= 2 && var.availability_zones_count <= 4
    error_message = "Availability zones count must be between 2 and 4."
  }
}

# Health Check Configuration
variable "health_check_interval" {
  description = "Route53 health check interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "Health check interval must be either 10 or 30 seconds."
  }
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive failures before marking endpoint unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition     = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Health check failure threshold must be between 1 and 10."
  }
}

variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/health"
  
  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

# Route53 Routing Configuration
variable "primary_weight" {
  description = "Weight for primary region in weighted routing"
  type        = number
  default     = 100
  
  validation {
    condition     = var.primary_weight >= 0 && var.primary_weight <= 255
    error_message = "Primary weight must be between 0 and 255."
  }
}

variable "secondary_weight" {
  description = "Weight for secondary region in weighted routing"
  type        = number
  default     = 50
  
  validation {
    condition     = var.secondary_weight >= 0 && var.secondary_weight <= 255
    error_message = "Secondary weight must be between 0 and 255."
  }
}

variable "tertiary_weight" {
  description = "Weight for tertiary region in weighted routing"
  type        = number
  default     = 25
  
  validation {
    condition     = var.tertiary_weight >= 0 && var.tertiary_weight <= 255
    error_message = "Tertiary weight must be between 0 and 255."
  }
}

# CloudFront Configuration
variable "cloudfront_price_class" {
  description = "CloudFront distribution price class"
  type        = string
  default     = "PriceClass_100"
  
  validation {
    condition = contains([
      "PriceClass_All", "PriceClass_200", "PriceClass_100"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_All, PriceClass_200, or PriceClass_100."
  }
}

variable "cloudfront_minimum_protocol_version" {
  description = "Minimum SSL/TLS protocol version for CloudFront"
  type        = string
  default     = "TLSv1.2_2021"
  
  validation {
    condition = contains([
      "TLSv1.2_2021", "TLSv1.2_2019", "TLSv1.1_2016", "TLSv1_2016"
    ], var.cloudfront_minimum_protocol_version)
    error_message = "CloudFront minimum protocol version must be a valid TLS version."
  }
}

# ALB Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

variable "target_group_health_check_interval" {
  description = "Target group health check interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.target_group_health_check_interval >= 5 && var.target_group_health_check_interval <= 300
    error_message = "Target group health check interval must be between 5 and 300 seconds."
  }
}

variable "target_group_health_check_timeout" {
  description = "Target group health check timeout in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.target_group_health_check_timeout >= 2 && var.target_group_health_check_timeout <= 120
    error_message = "Target group health check timeout must be between 2 and 120 seconds."
  }
}

variable "target_group_healthy_threshold" {
  description = "Number of consecutive successful health checks before marking target healthy"
  type        = number
  default     = 2
  
  validation {
    condition     = var.target_group_healthy_threshold >= 2 && var.target_group_healthy_threshold <= 10
    error_message = "Target group healthy threshold must be between 2 and 10."
  }
}

variable "target_group_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before marking target unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition     = var.target_group_unhealthy_threshold >= 2 && var.target_group_unhealthy_threshold <= 10
    error_message = "Target group unhealthy threshold must be between 2 and 10."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

# S3 Fallback Configuration
variable "create_fallback_bucket" {
  description = "Create S3 bucket for fallback content"
  type        = bool
  default     = true
}

variable "fallback_bucket_force_destroy" {
  description = "Force destroy S3 fallback bucket even if not empty"
  type        = bool
  default     = false
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}