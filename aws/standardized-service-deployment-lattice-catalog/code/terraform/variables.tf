# Input variables for the VPC Lattice Service Catalog solution
# These variables allow customization of the deployment for different environments and use cases

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "vpc-lattice-catalog"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "portfolio_name" {
  description = "Name for the Service Catalog portfolio"
  type        = string
  default     = ""
}

variable "portfolio_description" {
  description = "Description for the Service Catalog portfolio"
  type        = string
  default     = "Standardized VPC Lattice service deployment templates"
}

variable "portfolio_provider_name" {
  description = "Provider name for the Service Catalog portfolio"
  type        = string
  default     = "Platform Engineering Team"
}

variable "service_network_product_name" {
  description = "Name for the VPC Lattice service network product"
  type        = string
  default     = "standardized-service-network"
}

variable "lattice_service_product_name" {
  description = "Name for the VPC Lattice service product"
  type        = string
  default     = "standardized-lattice-service"
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket to store CloudFormation templates (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "create_test_vpc" {
  description = "Whether to create a test VPC for demonstration purposes"
  type        = bool
  default     = true
}

variable "test_vpc_cidr" {
  description = "CIDR block for the test VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.test_vpc_cidr, 0))
    error_message = "Test VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "test_subnet_cidrs" {
  description = "CIDR blocks for test subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition     = length(var.test_subnet_cidrs) >= 2
    error_message = "At least two subnet CIDRs must be provided for high availability."
  }
}

variable "deploy_test_resources" {
  description = "Whether to deploy test VPC Lattice resources"
  type        = bool
  default     = false
}

variable "test_service_network_name" {
  description = "Name for the test service network"
  type        = string
  default     = ""
}

variable "test_service_name" {
  description = "Name for the test VPC Lattice service"
  type        = string
  default     = ""
}

variable "test_service_port" {
  description = "Port for the test service"
  type        = number
  default     = 80
  
  validation {
    condition     = var.test_service_port > 0 && var.test_service_port <= 65535
    error_message = "Service port must be between 1 and 65535."
  }
}

variable "test_service_protocol" {
  description = "Protocol for the test service"
  type        = string
  default     = "HTTP"
  
  validation {
    condition     = contains(["HTTP", "HTTPS"], var.test_service_protocol)
    error_message = "Service protocol must be either HTTP or HTTPS."
  }
}

variable "test_target_type" {
  description = "Target type for the test target group"
  type        = string
  default     = "IP"
  
  validation {
    condition     = contains(["IP", "LAMBDA", "ALB"], var.test_target_type)
    error_message = "Target type must be one of: IP, LAMBDA, ALB."
  }
}

variable "principal_arns" {
  description = "List of IAM principal ARNs to grant Service Catalog portfolio access"
  type        = list(string)
  default     = []
}

variable "enable_cloudtrail_logging" {
  description = "Whether to enable CloudTrail logging for Service Catalog events"
  type        = bool
  default     = true
}

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket name for CloudTrail logs (leave empty for auto-generation)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}