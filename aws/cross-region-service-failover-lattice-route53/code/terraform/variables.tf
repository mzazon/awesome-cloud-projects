# Core Configuration Variables
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "microservices-failover"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.project_name))
    error_message = "Project name must be 3-40 characters, lowercase alphanumeric and hyphens only."
  }
}

# Regional Configuration
variable "primary_region" {
  description = "Primary AWS region for service deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region identifier."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for failover deployment"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region identifier."
  }
}

# Networking Configuration
variable "primary_vpc_cidr" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.primary_vpc_cidr, 0))
    error_message = "Primary VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for the secondary VPC"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.secondary_vpc_cidr, 0))
    error_message = "Secondary VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "primary_subnet_cidrs" {
  description = "CIDR blocks for primary region subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.primary_subnet_cidrs) >= 2
    error_message = "At least 2 subnet CIDRs must be provided for high availability."
  }
}

variable "secondary_subnet_cidrs" {
  description = "CIDR blocks for secondary region subnets"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]

  validation {
    condition     = length(var.secondary_subnet_cidrs) >= 2
    error_message = "At least 2 subnet CIDRs must be provided for high availability."
  }
}

# VPC Lattice Configuration
variable "service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = ""

  validation {
    condition     = var.service_network_name == "" || can(regex("^[a-z0-9-]{3,40}$", var.service_network_name))
    error_message = "Service network name must be 3-40 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "service_auth_type" {
  description = "Authentication type for VPC Lattice services"
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.service_auth_type)
    error_message = "Service auth type must be either NONE or AWS_IAM."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Base name for Lambda health check functions"
  type        = string
  default     = ""

  validation {
    condition     = var.lambda_function_name == "" || can(regex("^[a-zA-Z0-9-_]{1,64}$", var.lambda_function_name))
    error_message = "Lambda function name must be 1-64 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.11"

  validation {
    condition = contains([
      "python3.8", "python3.9", "python3.10", "python3.11", "python3.12"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# Route53 Configuration
variable "domain_name" {
  description = "Domain name for health check endpoints (leave empty to generate random subdomain)"
  type        = string
  default     = ""
}

variable "health_check_interval" {
  description = "Health check interval in seconds (10 or 30)"
  type        = number
  default     = 30

  validation {
    condition     = contains([10, 30], var.health_check_interval)
    error_message = "Health check interval must be either 10 or 30 seconds."
  }
}

variable "health_check_failure_threshold" {
  description = "Number of consecutive health check failures before marking unhealthy"
  type        = number
  default     = 3

  validation {
    condition     = var.health_check_failure_threshold >= 1 && var.health_check_failure_threshold <= 10
    error_message = "Health check failure threshold must be between 1 and 10."
  }
}

variable "dns_record_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.dns_record_ttl >= 0 && var.dns_record_ttl <= 86400
    error_message = "DNS record TTL must be between 0 and 86400 seconds."
  }
}

# CloudWatch Configuration
variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for health check monitoring"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 100
    error_message = "Alarm evaluation periods must be between 1 and 100."
  }
}

# Tagging Configuration
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Recipe      = "cross-region-service-failover-lattice-route53"
    ManagedBy   = "terraform"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "create_vpc_resources" {
  description = "Create VPC and networking resources (set to false if using existing VPCs)"
  type        = bool
  default     = true
}

variable "create_hosted_zone" {
  description = "Create Route53 hosted zone (set to false if using existing zone)"
  type        = bool
  default     = true
}

variable "simulate_failure_on_deploy" {
  description = "Deploy with simulated failure in primary region for testing"
  type        = bool
  default     = false
}

# Existing Resource IDs (when create_* flags are false)
variable "existing_primary_vpc_id" {
  description = "ID of existing primary VPC (required if create_vpc_resources = false)"
  type        = string
  default     = ""
}

variable "existing_secondary_vpc_id" {
  description = "ID of existing secondary VPC (required if create_vpc_resources = false)"
  type        = string
  default     = ""
}

variable "existing_primary_subnet_ids" {
  description = "IDs of existing primary subnets (required if create_vpc_resources = false)"
  type        = list(string)
  default     = []
}

variable "existing_secondary_subnet_ids" {
  description = "IDs of existing secondary subnets (required if create_vpc_resources = false)"
  type        = list(string)
  default     = []
}

variable "existing_hosted_zone_id" {
  description = "ID of existing Route53 hosted zone (required if create_hosted_zone = false)"
  type        = string
  default     = ""
}