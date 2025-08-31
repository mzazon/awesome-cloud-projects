# Input Variables for Distributed Service Tracing Infrastructure
# These variables allow customization of the deployment

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
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "lattice-xray-tracing"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
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
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_vpc_lattice_logging" {
  description = "Enable access logging for VPC Lattice"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "create_vpc" {
  description = "Whether to create a new VPC or use existing one"
  type        = bool
  default     = true
}

variable "existing_vpc_id" {
  description = "ID of existing VPC to use (when create_vpc is false)"
  type        = string
  default     = ""
  
  validation {
    condition = var.create_vpc || (
      !var.create_vpc && can(regex("^vpc-[0-9a-f]{8,17}$", var.existing_vpc_id))
    )
    error_message = "When using existing VPC, existing_vpc_id must be a valid VPC ID."
  }
}

variable "existing_subnet_id" {
  description = "ID of existing subnet to use (when create_vpc is false)"
  type        = string
  default     = ""
  
  validation {
    condition = var.create_vpc || (
      !var.create_vpc && can(regex("^subnet-[0-9a-f]{8,17}$", var.existing_subnet_id))
    )
    error_message = "When using existing VPC, existing_subnet_id must be a valid subnet ID."
  }
}

variable "availability_zone" {
  description = "Availability zone for subnet creation (e.g., 'a', 'b', 'c')"
  type        = string
  default     = "a"
  
  validation {
    condition     = can(regex("^[a-z]$", var.availability_zone))
    error_message = "Availability zone must be a single lowercase letter."
  }
}

variable "enable_cloudwatch_dashboard" {
  description = "Whether to create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "test_traffic_generation" {
  description = "Whether to include test traffic generation Lambda"
  type        = bool
  default     = false
}