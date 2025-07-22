# ==============================================================================
# VARIABLES
# ==============================================================================

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "batch-fargate-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# COMPUTE ENVIRONMENT CONFIGURATION
# ==============================================================================

variable "max_vcpus" {
  description = "Maximum number of vCPUs for the compute environment"
  type        = number
  default     = 256

  validation {
    condition     = var.max_vcpus >= 1 && var.max_vcpus <= 10000
    error_message = "Max vCPUs must be between 1 and 10000."
  }
}

variable "compute_environment_state" {
  description = "State of the compute environment (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.compute_environment_state)
    error_message = "Compute environment state must be ENABLED or DISABLED."
  }
}

# ==============================================================================
# JOB QUEUE CONFIGURATION
# ==============================================================================

variable "job_queue_priority" {
  description = "Priority of the job queue"
  type        = number
  default     = 1

  validation {
    condition     = var.job_queue_priority >= 0 && var.job_queue_priority <= 1000
    error_message = "Job queue priority must be between 0 and 1000."
  }
}

variable "job_queue_state" {
  description = "State of the job queue (ENABLED or DISABLED)"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.job_queue_state)
    error_message = "Job queue state must be ENABLED or DISABLED."
  }
}

# ==============================================================================
# JOB DEFINITION CONFIGURATION
# ==============================================================================

variable "job_vcpu" {
  description = "vCPU allocation for batch jobs"
  type        = string
  default     = "0.25"

  validation {
    condition = contains([
      "0.25", "0.5", "1", "2", "4", "8", "16"
    ], var.job_vcpu)
    error_message = "Job vCPU must be one of: 0.25, 0.5, 1, 2, 4, 8, 16."
  }
}

variable "job_memory" {
  description = "Memory allocation for batch jobs (in MB)"
  type        = string
  default     = "512"

  validation {
    condition = can(regex("^[0-9]+$", var.job_memory)) && tonumber(var.job_memory) >= 512
    error_message = "Job memory must be a number >= 512 MB."
  }
}

variable "container_image" {
  description = "Container image URI for batch jobs (will use default Python image if not specified)"
  type        = string
  default     = ""
}

# ==============================================================================
# NETWORKING CONFIGURATION
# ==============================================================================

variable "vpc_id" {
  description = "VPC ID where resources will be created (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for Fargate tasks (leave empty to use default VPC subnets)"
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Whether to assign public IP to Fargate tasks"
  type        = bool
  default     = true
}

variable "create_security_group" {
  description = "Whether to create a new security group for batch jobs"
  type        = bool
  default     = true
}

variable "allowed_egress_cidr_blocks" {
  description = "CIDR blocks allowed for egress traffic"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ==============================================================================
# LOGGING CONFIGURATION
# ==============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "log_group_name" {
  description = "Name of the CloudWatch log group"
  type        = string
  default     = "/aws/batch/job"
}

# ==============================================================================
# ECR CONFIGURATION
# ==============================================================================

variable "create_ecr_repository" {
  description = "Whether to create an ECR repository for container images"
  type        = bool
  default     = true
}

variable "ecr_image_scanning" {
  description = "Whether to enable image scanning on the ECR repository"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for ECR repository"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

# ==============================================================================
# RESOURCE TAGGING
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}