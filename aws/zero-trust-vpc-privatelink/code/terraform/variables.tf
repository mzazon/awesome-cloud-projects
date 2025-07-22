# Input variables for Zero Trust Network Architecture with VPC Endpoints and PrivateLink

variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-west-2)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "zero-trust"
  
  validation {
    condition     = length(var.environment) <= 20
    error_message = "Environment name must be 20 characters or less."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "zero-trust-network"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "consumer_vpc_cidr" {
  description = "CIDR block for the consumer VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.consumer_vpc_cidr, 0))
    error_message = "Consumer VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "provider_vpc_cidr" {
  description = "CIDR block for the provider VPC"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.provider_vpc_cidr, 0))
    error_message = "Provider VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "consumer_private_subnet_cidrs" {
  description = "CIDR blocks for consumer VPC private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  
  validation {
    condition = alltrue([
      for cidr in var.consumer_private_subnet_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All consumer private subnet CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "provider_subnet_cidr" {
  description = "CIDR block for provider VPC subnet"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.provider_subnet_cidr, 0))
    error_message = "Provider subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["a", "b"]
  
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones must be specified for high availability."
  }
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPCs"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPCs"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Number of days to retain VPC Flow Logs"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_log_retention_days)
    error_message = "Flow log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "private_dns_enabled" {
  description = "Enable private DNS for VPC endpoints"
  type        = bool
  default     = true
}

variable "vpc_endpoint_policy_s3" {
  description = "IAM policy document for S3 VPC endpoint"
  type        = string
  default     = null
}

variable "custom_service_name" {
  description = "Name for the custom PrivateLink service"
  type        = string
  default     = "zero-trust-custom-service"
}

variable "endpoint_service_acceptance_required" {
  description = "Whether acceptance is required for the endpoint service"
  type        = bool
  default     = true
}

variable "nlb_enable_deletion_protection" {
  description = "Enable deletion protection for the Network Load Balancer"
  type        = bool
  default     = false
}

variable "create_test_lambda" {
  description = "Create a test Lambda function for validation"
  type        = bool
  default     = true
}

variable "lambda_timeout" {
  description = "Timeout for the test Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}