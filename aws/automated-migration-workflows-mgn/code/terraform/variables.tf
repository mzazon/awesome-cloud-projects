variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the migration project"
  type        = string
  default     = "migration-project"
}

variable "vpc_cidr" {
  description = "CIDR block for the migration VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least two availability zones are required."
  }
}

variable "mgn_replication_instance_type" {
  description = "Instance type for MGN replication servers"
  type        = string
  default     = "t3.small"
  
  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.mgn_replication_instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "allowed_source_cidr" {
  description = "CIDR block allowed for source server access"
  type        = string
  default     = "10.0.0.0/8"
  
  validation {
    condition     = can(cidrhost(var.allowed_source_cidr, 0))
    error_message = "Allowed source CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for migration monitoring"
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch log retention period."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "migration_workflow_name" {
  description = "Name for the Migration Hub Orchestrator workflow"
  type        = string
  default     = "AutomatedMigrationWorkflow"
}

variable "workflow_description" {
  description = "Description for the Migration Hub Orchestrator workflow"
  type        = string
  default     = "Automated end-to-end migration workflow using MGN"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}