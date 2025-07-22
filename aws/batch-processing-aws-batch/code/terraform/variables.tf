# ======================================================================
# AWS Batch Processing Workloads - Terraform Variables
# 
# This file defines all configurable parameters for the AWS Batch 
# infrastructure deployment. Variables are organized by functional area
# for easier management and understanding.
# ======================================================================

# ======================================================================
# ENVIRONMENT CONFIGURATION
# ======================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "batch-processing"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens."
  }
}

# ======================================================================
# VPC AND NETWORKING CONFIGURATION
# ======================================================================

variable "vpc_id" {
  description = "VPC ID where resources will be deployed. If not provided, the default VPC will be used"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the compute environment. If empty, all subnets in the VPC will be used"
  type        = list(string)
  default     = []
}

# ======================================================================
# COMPUTE ENVIRONMENT CONFIGURATION
# ======================================================================

variable "compute_environment_name" {
  description = "Name for the AWS Batch compute environment"
  type        = string
  default     = ""
}

variable "compute_environment_type" {
  description = "Type of compute environment (EC2, SPOT, FARGATE, FARGATE_SPOT)"
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "SPOT", "FARGATE", "FARGATE_SPOT"], var.compute_environment_type)
    error_message = "Compute environment type must be one of: EC2, SPOT, FARGATE, FARGATE_SPOT."
  }
}

variable "allocation_strategy" {
  description = "Allocation strategy for compute resources"
  type        = string
  default     = "BEST_FIT_PROGRESSIVE"

  validation {
    condition     = contains(["BEST_FIT", "BEST_FIT_PROGRESSIVE", "SPOT_CAPACITY_OPTIMIZED"], var.allocation_strategy)
    error_message = "Allocation strategy must be one of: BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED."
  }
}

variable "min_vcpus" {
  description = "Minimum number of vCPUs for the compute environment"
  type        = number
  default     = 0
  
  validation {
    condition     = var.min_vcpus >= 0
    error_message = "Minimum vCPUs must be >= 0."
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
    error_message = "Desired vCPUs must be >= 0."
  }
}

variable "instance_types" {
  description = "List of EC2 instance types for the compute environment. Use ['optimal'] for AWS to choose the best instance types"
  type        = list(string)
  default     = ["optimal"]
}

variable "spot_instance_percentage" {
  description = "Percentage of Spot instances to use (0-100). Only applies when compute_environment_type is SPOT"
  type        = number
  default     = 50
  
  validation {
    condition     = var.spot_instance_percentage >= 0 && var.spot_instance_percentage <= 100
    error_message = "Spot instance percentage must be between 0 and 100."
  }
}

variable "ec2_image_type" {
  description = "The image type to match with the instance type to select an AMI"
  type        = string
  default     = "ECS_AL2"

  validation {
    condition     = contains(["ECS_AL1", "ECS_AL2", "ECS_AL2_X86_64", "ECS_AL2_ARM64"], var.ec2_image_type)
    error_message = "EC2 image type must be one of: ECS_AL1, ECS_AL2, ECS_AL2_X86_64, ECS_AL2_ARM64."
  }
}

variable "ec2_key_pair_name" {
  description = "EC2 Key Pair name for SSH access to compute instances"
  type        = string
  default     = ""
}

# ======================================================================
# LAUNCH TEMPLATE CONFIGURATION
# ======================================================================

variable "launch_template_id" {
  description = "ID of the launch template to use"
  type        = string
  default     = ""
}

variable "launch_template_name" {
  description = "Name of the launch template to use"
  type        = string
  default     = ""
}

variable "launch_template_version" {
  description = "Version of the launch template to use"
  type        = string
  default     = "$Latest"
}

# ======================================================================
# UPDATE POLICY CONFIGURATION
# ======================================================================

variable "enable_update_policy" {
  description = "Whether to enable update policy for the compute environment"
  type        = bool
  default     = false
}

variable "job_execution_timeout_minutes" {
  description = "Job execution timeout when compute environment infrastructure is updated"
  type        = number
  default     = 30

  validation {
    condition     = var.job_execution_timeout_minutes > 0 && var.job_execution_timeout_minutes <= 600
    error_message = "Job execution timeout must be between 1 and 600 minutes."
  }
}

variable "terminate_jobs_on_update" {
  description = "Whether to terminate jobs automatically when compute environment infrastructure is updated"
  type        = bool
  default     = false
}

# ======================================================================
# JOB QUEUE CONFIGURATION
# ======================================================================

variable "job_queue_name" {
  description = "Name for the AWS Batch job queue"
  type        = string
  default     = ""
}

variable "job_queue_priority" {
  description = "Priority of the job queue"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_queue_priority >= 0 && var.job_queue_priority <= 1000
    error_message = "Job queue priority must be between 0 and 1000."
  }
}

variable "scheduling_policy_arn" {
  description = "ARN of the scheduling policy to associate with the job queue"
  type        = string
  default     = ""
}

# ======================================================================
# JOB DEFINITION CONFIGURATION
# ======================================================================

variable "job_definition_name" {
  description = "Name for the AWS Batch job definition"
  type        = string
  default     = ""
}

variable "container_image" {
  description = "Docker image for the batch job. Can be an ECR URI or Docker Hub image"
  type        = string
  default     = "python:3.9-slim"
}

variable "job_vcpus" {
  description = "Number of vCPUs to allocate for each job"
  type        = number
  default     = 1
  
  validation {
    condition     = var.job_vcpus > 0
    error_message = "Job vCPUs must be > 0."
  }
}

variable "job_memory" {
  description = "Amount of memory (in MiB) to allocate for each job"
  type        = number
  default     = 512
  
  validation {
    condition     = var.job_memory >= 128
    error_message = "Job memory must be >= 128 MiB."
  }
}

variable "job_gpu_count" {
  description = "Number of GPUs to allocate for each job (0 for no GPU)"
  type        = number
  default     = 0

  validation {
    condition     = var.job_gpu_count >= 0
    error_message = "Job GPU count must be >= 0."
  }
}

variable "job_timeout_seconds" {
  description = "Timeout for job execution in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.job_timeout_seconds > 0
    error_message = "Job timeout must be > 0 seconds."
  }
}

variable "job_retry_attempts" {
  description = "Number of retry attempts for failed jobs"
  type        = number
  default     = 1

  validation {
    condition     = var.job_retry_attempts >= 1 && var.job_retry_attempts <= 10
    error_message = "Job retry attempts must be between 1 and 10."
  }
}

variable "job_role_arn" {
  description = "IAM role ARN for the job to assume during execution"
  type        = string
  default     = ""
}

variable "job_parameters" {
  description = "Default parameters for the job definition"
  type        = map(string)
  default     = {}
}

# ======================================================================
# JOB ENVIRONMENT CONFIGURATION
# ======================================================================

variable "job_environment_variables" {
  description = "Environment variables to pass to batch jobs"
  type        = map(string)
  default = {
    DATA_SIZE       = "1000"
    PROCESSING_TIME = "60"
  }
}

variable "enable_ulimits" {
  description = "Whether to enable ulimits for the job containers"
  type        = bool
  default     = false
}

# ======================================================================
# FARGATE CONFIGURATION
# ======================================================================

variable "fargate_platform_version" {
  description = "Fargate platform version (only applicable for FARGATE compute environments)"
  type        = string
  default     = ""
}

# ======================================================================
# EFS CONFIGURATION
# ======================================================================

variable "enable_efs" {
  description = "Whether to enable EFS volume mounting for jobs"
  type        = bool
  default     = false
}

variable "efs_file_system_id" {
  description = "EFS file system ID to mount (required if enable_efs is true)"
  type        = string
  default     = ""
}

variable "efs_access_point_id" {
  description = "EFS access point ID to use (required if enable_efs is true)"
  type        = string
  default     = ""
}

# ======================================================================
# ECR REPOSITORY CONFIGURATION
# ======================================================================

variable "create_ecr_repository" {
  description = "Whether to create an ECR repository for storing container images"
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "Name for the ECR repository. If empty, will be auto-generated"
  type        = string
  default     = ""
}

variable "ecr_image_scan_on_push" {
  description = "Enable vulnerability scanning on image push to ECR"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for the ECR repository"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "ecr_image_retention_count" {
  description = "Number of tagged images to retain in ECR"
  type        = number
  default     = 10

  validation {
    condition     = var.ecr_image_retention_count > 0 && var.ecr_image_retention_count <= 1000
    error_message = "ECR image retention count must be between 1 and 1000."
  }
}

# ======================================================================
# CLOUDWATCH LOGGING CONFIGURATION
# ======================================================================

variable "log_group_name" {
  description = "CloudWatch log group name for batch jobs"
  type        = string
  default     = "/aws/batch/job"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_log_encryption" {
  description = "Whether to enable encryption for CloudWatch logs using KMS"
  type        = bool
  default     = false
}

# ======================================================================
# MONITORING AND ALERTING CONFIGURATION
# ======================================================================

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "create_cloudwatch_dashboard" {
  description = "Whether to create a CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

variable "alarm_email_endpoint" {
  description = "Email address to receive alarm notifications. Leave empty to skip SNS topic creation"
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alarm_email_endpoint))
    error_message = "Alarm email endpoint must be a valid email address or empty string."
  }
}

variable "enable_sns_encryption" {
  description = "Whether to enable encryption for SNS topic"
  type        = bool
  default     = true
}

variable "alarm_period" {
  description = "Period in seconds for CloudWatch alarms"
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600, 21600, 86400], var.alarm_period)
    error_message = "Alarm period must be one of: 60, 300, 900, 3600, 21600, 86400 seconds."
  }
}

variable "failed_jobs_threshold" {
  description = "Threshold for failed jobs alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.failed_jobs_threshold >= 1
    error_message = "Failed jobs threshold must be >= 1."
  }
}

variable "failed_jobs_evaluation_periods" {
  description = "Number of evaluation periods for failed jobs alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.failed_jobs_evaluation_periods >= 1 && var.failed_jobs_evaluation_periods <= 5
    error_message = "Failed jobs evaluation periods must be between 1 and 5."
  }
}

variable "queue_utilization_threshold" {
  description = "Threshold for queue utilization alarm"
  type        = number
  default     = 10

  validation {
    condition     = var.queue_utilization_threshold >= 1
    error_message = "Queue utilization threshold must be >= 1."
  }
}

variable "queue_utilization_evaluation_periods" {
  description = "Number of evaluation periods for queue utilization alarm"
  type        = number
  default     = 2

  validation {
    condition     = var.queue_utilization_evaluation_periods >= 1 && var.queue_utilization_evaluation_periods <= 5
    error_message = "Queue utilization evaluation periods must be between 1 and 5."
  }
}

# ======================================================================
# RESOURCE TAGGING
# ======================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.additional_tags) <= 50
    error_message = "Cannot specify more than 50 additional tags."
  }
}