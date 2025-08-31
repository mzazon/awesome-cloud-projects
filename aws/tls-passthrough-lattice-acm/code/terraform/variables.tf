# Variables for VPC Lattice TLS Passthrough Infrastructure

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "custom_domain_name" {
  description = "Custom domain name for VPC Lattice service (e.g., api-service.example.com)"
  type        = string
  default     = "api-service.example.com"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.custom_domain_name))
    error_message = "Custom domain name must be a valid domain format."
  }
}

variable "certificate_domain" {
  description = "Domain name for SSL certificate (can use wildcard, e.g., *.example.com)"
  type        = string
  default     = "*.example.com"
  
  validation {
    condition     = can(regex("^(\\*\\.)?[a-z0-9.-]+\\.[a-z]{2,}$", var.certificate_domain))
    error_message = "Certificate domain must be a valid domain format, optionally with wildcard."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the target subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "instance_type" {
  description = "EC2 instance type for target instances"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "t4g.micro", "t4g.small", "t4g.medium", "t4g.large"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "target_instance_count" {
  description = "Number of target EC2 instances to create"
  type        = number
  default     = 2
  
  validation {
    condition     = var.target_instance_count >= 1 && var.target_instance_count <= 10
    error_message = "Target instance count must be between 1 and 10."
  }
}

variable "create_certificate" {
  description = "Whether to create an ACM certificate (requires manual DNS validation)"
  type        = bool
  default     = true
}

variable "certificate_arn" {
  description = "Existing ACM certificate ARN (used if create_certificate is false)"
  type        = string
  default     = ""
  
  validation {
    condition = var.certificate_arn == "" || can(regex("^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/[a-f0-9-]+$", var.certificate_arn))
    error_message = "Certificate ARN must be a valid ACM certificate ARN format."
  }
}

variable "create_route53_zone" {
  description = "Whether to create a Route 53 hosted zone for DNS management"
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Existing Route 53 hosted zone ID (required if create_route53_zone is false)"
  type        = string
  default     = ""
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.health_check_grace_period >= 30 && var.health_check_grace_period <= 3600
    error_message = "Health check grace period must be between 30 and 3600 seconds."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the target instances"
  type        = list(string)
  default     = ["10.0.0.0/8"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}