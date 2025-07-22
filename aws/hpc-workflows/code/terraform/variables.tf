variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "hpc-workflow"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "spot_fleet_target_capacity" {
  description = "Target capacity for Spot Fleet"
  type        = number
  default     = 4
  
  validation {
    condition     = var.spot_fleet_target_capacity > 0 && var.spot_fleet_target_capacity <= 100
    error_message = "Spot Fleet target capacity must be between 1 and 100."
  }
}

variable "spot_fleet_max_price" {
  description = "Maximum price for Spot instances (USD per hour)"
  type        = string
  default     = "0.50"
}

variable "instance_types" {
  description = "List of instance types for Spot Fleet"
  type        = list(string)
  default     = ["c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"]
}

variable "ami_id" {
  description = "AMI ID for EC2 instances (leave empty for latest Amazon Linux 2)"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "EC2 Key Pair name for SSH access"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID for resources (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for resources (leave empty to use default subnets)"
  type        = list(string)
  default     = []
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = ""
}

variable "workflow_timeout_minutes" {
  description = "Timeout for workflow execution in minutes"
  type        = number
  default     = 1440 # 24 hours
  
  validation {
    condition     = var.workflow_timeout_minutes > 0 && var.workflow_timeout_minutes <= 10080 # 7 days
    error_message = "Workflow timeout must be between 1 and 10080 minutes (7 days)."
  }
}

variable "checkpoint_retention_days" {
  description = "Number of days to retain checkpoints"
  type        = number
  default     = 30
  
  validation {
    condition     = var.checkpoint_retention_days >= 1 && var.checkpoint_retention_days <= 365
    error_message = "Checkpoint retention must be between 1 and 365 days."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and dashboards"
  type        = bool
  default     = true
}

variable "enable_alerts" {
  description = "Enable CloudWatch alarms and notifications"
  type        = bool
  default     = true
}

variable "lambda_runtime" {
  description = "Lambda runtime version"
  type        = string
  default     = "python3.9"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode"
  type        = string
  default     = "PAY_PER_REQUEST"
  
  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "DynamoDB billing mode must be either PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "s3_force_destroy" {
  description = "Force destroy S3 bucket on deletion (WARNING: This will delete all data)"
  type        = bool
  default     = false
}

variable "batch_compute_environment_type" {
  description = "Batch compute environment type"
  type        = string
  default     = "MANAGED"
  
  validation {
    condition     = contains(["MANAGED", "UNMANAGED"], var.batch_compute_environment_type)
    error_message = "Batch compute environment type must be either MANAGED or UNMANAGED."
  }
}

variable "batch_instance_role" {
  description = "IAM instance profile for Batch instances"
  type        = string
  default     = ""
}

variable "batch_service_role" {
  description = "IAM service role for Batch"
  type        = string
  default     = ""
}

variable "enable_encryption" {
  description = "Enable encryption for S3 and DynamoDB"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "spot_fleet_allocation_strategy" {
  description = "Spot Fleet allocation strategy"
  type        = string
  default     = "diversified"
  
  validation {
    condition     = contains(["lowest-price", "diversified", "balanced"], var.spot_fleet_allocation_strategy)
    error_message = "Spot Fleet allocation strategy must be one of: lowest-price, diversified, balanced."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}