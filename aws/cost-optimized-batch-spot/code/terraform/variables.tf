# Variables for Cost-Optimized Batch Processing with AWS Batch and Spot Instances

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "batch-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for batch container images"
  type        = string
  default     = ""
}

variable "batch_service_role_name" {
  description = "Name of the AWS Batch service role"
  type        = string
  default     = "AWSBatchServiceRole"
}

variable "instance_role_name" {
  description = "Name of the EC2 instance role for batch compute environments"
  type        = string
  default     = "ecsInstanceRole"
}

variable "job_execution_role_name" {
  description = "Name of the ECS task execution role for batch jobs"
  type        = string
  default     = "BatchJobExecutionRole"
}

variable "compute_environment_name" {
  description = "Name of the AWS Batch compute environment"
  type        = string
  default     = ""
}

variable "job_queue_name" {
  description = "Name of the AWS Batch job queue"
  type        = string
  default     = ""
}

variable "job_definition_name" {
  description = "Name of the AWS Batch job definition"
  type        = string
  default     = ""
}

variable "min_vcpus" {
  description = "Minimum number of vCPUs for the compute environment"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_vcpus >= 0
    error_message = "Minimum vCPUs must be greater than or equal to 0."
  }
}

variable "max_vcpus" {
  description = "Maximum number of vCPUs for the compute environment"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_vcpus > 0 && var.max_vcpus <= 10000
    error_message = "Maximum vCPUs must be between 1 and 10000."
  }
}

variable "desired_vcpus" {
  description = "Desired number of vCPUs for the compute environment"
  type        = number
  default     = 0
  
  validation {
    condition     = var.desired_vcpus >= 0
    error_message = "Desired vCPUs must be greater than or equal to 0."
  }
}

variable "instance_types" {
  description = "List of EC2 instance types for the compute environment"
  type        = list(string)
  default     = ["c5.large", "c5.xlarge", "c5.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"]
  
  validation {
    condition     = length(var.instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "spot_bid_percentage" {
  description = "Percentage of On-Demand price to bid for Spot instances"
  type        = number
  default     = 80
  
  validation {
    condition     = var.spot_bid_percentage > 0 && var.spot_bid_percentage <= 100
    error_message = "Spot bid percentage must be between 1 and 100."
  }
}

variable "job_vcpus" {
  description = "Number of vCPUs required for each batch job"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_vcpus > 0
    error_message = "Job vCPUs must be greater than 0."
  }
}

variable "job_memory" {
  description = "Amount of memory (in MB) required for each batch job"
  type        = number
  default     = 512
  
  validation {
    condition     = var.job_memory > 0
    error_message = "Job memory must be greater than 0."
  }
}

variable "job_timeout_seconds" {
  description = "Timeout for batch jobs in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.job_timeout_seconds > 0
    error_message = "Job timeout must be greater than 0."
  }
}

variable "retry_attempts" {
  description = "Number of retry attempts for failed batch jobs"
  type        = number
  default     = 3
  
  validation {
    condition     = var.retry_attempts >= 1 && var.retry_attempts <= 10
    error_message = "Retry attempts must be between 1 and 10."
  }
}

variable "use_default_vpc" {
  description = "Whether to use the default VPC for batch compute environment"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for the batch compute environment (required if use_default_vpc is false)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the batch compute environment (required if use_default_vpc is false)"
  type        = list(string)
  default     = []
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}