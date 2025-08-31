# Variables for Advanced Request Routing with VPC Lattice and ALB

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "lattice-routing"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix" {
  description = "Random suffix for unique resource naming"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.random_suffix) <= 8
    error_message = "Random suffix must be 8 characters or less."
  }
}

# Networking Variables
variable "default_vpc_id" {
  description = "ID of the default VPC to use (leave empty to auto-detect)"
  type        = string
  default     = ""
}

variable "target_vpc_cidr" {
  description = "CIDR block for the target VPC"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.target_vpc_cidr, 0))
    error_message = "Target VPC CIDR must be a valid CIDR block."
  }
}

variable "target_subnet_cidr" {
  description = "CIDR block for the target VPC subnet"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.target_subnet_cidr, 0))
    error_message = "Target subnet CIDR must be a valid CIDR block."
  }
}

# VPC Lattice Variables
variable "lattice_auth_type" {
  description = "Authentication type for VPC Lattice services"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.lattice_auth_type)
    error_message = "Auth type must be either AWS_IAM or NONE."
  }
}

variable "enable_lattice_auth_policy" {
  description = "Whether to enable IAM authentication policy for VPC Lattice service"
  type        = bool
  default     = true
}

# EC2 Variables
variable "instance_type" {
  description = "EC2 instance type for application servers"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large"], var.instance_type)
    error_message = "Instance type must be a valid t3 instance type."
  }
}

variable "instance_count" {
  description = "Number of EC2 instances to launch per service"
  type        = number
  default     = 1
  
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "Instance count must be between 1 and 5."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

# Load Balancer Variables
variable "alb_deletion_protection" {
  description = "Enable deletion protection for ALBs"
  type        = bool
  default     = false
}

variable "alb_access_logs_enabled" {
  description = "Enable access logs for ALBs"
  type        = bool
  default     = false
}

variable "target_group_health_check_interval" {
  description = "Health check interval for ALB target groups (seconds)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.target_group_health_check_interval >= 5 && var.target_group_health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "target_group_healthy_threshold" {
  description = "Number of consecutive health checks before considering target healthy"
  type        = number
  default     = 2
  
  validation {
    condition     = var.target_group_healthy_threshold >= 2 && var.target_group_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

# Routing Rules Variables
variable "enable_path_routing" {
  description = "Enable path-based routing rules"
  type        = bool
  default     = true
}

variable "enable_header_routing" {
  description = "Enable header-based routing rules"
  type        = bool
  default     = true
}

variable "enable_method_routing" {
  description = "Enable HTTP method-based routing rules"
  type        = bool
  default     = true
}

variable "api_path_prefix" {
  description = "Path prefix for API routing rule"
  type        = string
  default     = "/api/v1"
  
  validation {
    condition     = can(regex("^/[a-zA-Z0-9/_-]+$", var.api_path_prefix))
    error_message = "API path prefix must start with / and contain valid URL characters."
  }
}

variable "beta_header_name" {
  description = "Header name for beta service routing"
  type        = string
  default     = "X-Service-Version"
  
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]*$", var.beta_header_name))
    error_message = "Header name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "beta_header_value" {
  description = "Header value for beta service routing"
  type        = string
  default     = "beta"
  
  validation {
    condition     = length(var.beta_header_value) > 0
    error_message = "Header value cannot be empty."
  }
}

# Security Variables
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access ALB"
  type        = list(string)
  default     = ["10.0.0.0/8"]
  
  validation {
    condition     = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified."
  }
}

variable "enable_https" {
  description = "Enable HTTPS listener (requires certificate_arn)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of SSL certificate for HTTPS listener"
  type        = string
  default     = ""
  
  validation {
    condition     = var.certificate_arn == "" || can(regex("^arn:aws:acm:", var.certificate_arn))
    error_message = "Certificate ARN must be a valid ACM ARN or empty string."
  }
}