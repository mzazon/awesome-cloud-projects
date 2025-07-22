# Environment Configuration
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Domain Configuration
variable "domain_name" {
  description = "Primary domain name for the hosted zone"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid DNS domain."
  }
}

variable "subdomain" {
  description = "Subdomain for the API endpoint"
  type        = string
  default     = "api"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.subdomain))
    error_message = "Subdomain must contain only lowercase letters, numbers, and hyphens."
  }
}

# Region Configuration
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

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnet CIDRs must be provided for ALB."
  }
}

# Load Balancer Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancers"
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 60
  
  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

# Health Check Configuration
variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "Health check interval must be either 10 or 30 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  
  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 60
    error_message = "Health check timeout must be between 2 and 60 seconds."
  }
}

variable "health_check_path" {
  description = "Health check path"
  type        = string
  default     = "/health"
}

variable "failure_threshold" {
  description = "Number of consecutive failed health checks required to mark endpoint as failed"
  type        = number
  default     = 3
  
  validation {
    condition     = var.failure_threshold >= 1 && var.failure_threshold <= 10
    error_message = "Failure threshold must be between 1 and 10."
  }
}

# Route 53 Routing Configuration
variable "weighted_routing" {
  description = "Weight distribution for weighted routing policy"
  type = object({
    primary   = number
    secondary = number
    tertiary  = number
  })
  default = {
    primary   = 50
    secondary = 30
    tertiary  = 20
  }
  
  validation {
    condition     = var.weighted_routing.primary + var.weighted_routing.secondary + var.weighted_routing.tertiary == 100
    error_message = "Weighted routing values must sum to 100."
  }
}

variable "dns_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.dns_ttl >= 60 && var.dns_ttl <= 86400
    error_message = "DNS TTL must be between 60 and 86400 seconds."
  }
}

variable "enable_routing_policies" {
  description = "Enable different Route 53 routing policies"
  type = object({
    weighted        = bool
    latency         = bool
    geolocation     = bool
    failover        = bool
    multivalue      = bool
  })
  default = {
    weighted        = true
    latency         = true
    geolocation     = true
    failover        = true
    multivalue      = true
  }
}

# SNS Configuration
variable "enable_health_check_notifications" {
  description = "Enable SNS notifications for health check failures"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for health check notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}