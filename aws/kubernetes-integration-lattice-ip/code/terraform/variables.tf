# variables.tf - Input variables for the Kubernetes VPC Lattice integration

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format xx-xxxx-x (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "k8s-lattice"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.resource_prefix))
    error_message = "Resource prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_a_cidr" {
  description = "CIDR block for VPC A (Kubernetes cluster A)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_a_cidr, 0))
    error_message = "VPC A CIDR must be a valid IPv4 CIDR block."
  }
}

variable "vpc_b_cidr" {
  description = "CIDR block for VPC B (Kubernetes cluster B)"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_b_cidr, 0))
    error_message = "VPC B CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_a_cidr" {
  description = "CIDR block for subnet in VPC A"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_b_cidr" {
  description = "CIDR block for subnet in VPC B"
  type        = string
  default     = "10.1.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for Kubernetes control planes"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.medium", "t3.large", "t3.xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be appropriate for Kubernetes workloads."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.28"
  
  validation {
    condition = can(regex("^1\\.(2[6-9]|[3-9][0-9])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.26 or higher."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and logging"
  type        = bool
  default     = true
}

variable "health_check_interval" {
  description = "Health check interval in seconds for VPC Lattice targets"
  type        = number
  default     = 30
  
  validation {
    condition = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds for VPC Lattice targets"
  type        = number
  default     = 5
  
  validation {
    condition = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access to EC2 instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([for cidr in var.ssh_allowed_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All SSH allowed CIDRs must be valid IPv4 CIDR blocks."
  }
}

variable "create_key_pair" {
  description = "Create a new SSH key pair for EC2 instances"
  type        = bool
  default     = true
}