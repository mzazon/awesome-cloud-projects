# =============================================================================
# AWS Batch Multi-Node Parallel Jobs - Variables
# Configurable parameters for distributed scientific computing infrastructure
# =============================================================================

# -----------------------------------------------------------------------------
# Project Configuration
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used as prefix for resource naming"
  type        = string
  default     = "scientific-computing"

  validation {
    condition     = length(var.project_name) <= 20 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must be 20 characters or less and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

# -----------------------------------------------------------------------------
# Networking Configuration
# -----------------------------------------------------------------------------

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all private subnets (cost optimization)"
  type        = bool
  default     = true
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services to reduce NAT gateway costs"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# AWS Batch Configuration
# -----------------------------------------------------------------------------

variable "batch_min_vcpus" {
  description = "Minimum number of vCPUs in the compute environment"
  type        = number
  default     = 0

  validation {
    condition     = var.batch_min_vcpus >= 0 && var.batch_min_vcpus <= 10000
    error_message = "Minimum vCPUs must be between 0 and 10000."
  }
}

variable "batch_max_vcpus" {
  description = "Maximum number of vCPUs in the compute environment"
  type        = number
  default     = 256

  validation {
    condition     = var.batch_max_vcpus >= 1 && var.batch_max_vcpus <= 10000
    error_message = "Maximum vCPUs must be between 1 and 10000."
  }
}

variable "batch_desired_vcpus" {
  description = "Desired number of vCPUs in the compute environment"
  type        = number
  default     = 0

  validation {
    condition     = var.batch_desired_vcpus >= 0 && var.batch_desired_vcpus <= 10000
    error_message = "Desired vCPUs must be between 0 and 10000."
  }
}

variable "batch_instance_types" {
  description = "List of EC2 instance types for the compute environment"
  type        = list(string)
  default     = ["c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"]

  validation {
    condition     = length(var.batch_instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

# -----------------------------------------------------------------------------
# Job Definition Configuration
# -----------------------------------------------------------------------------

variable "default_num_nodes" {
  description = "Default number of nodes for multi-node parallel jobs"
  type        = number
  default     = 2

  validation {
    condition     = var.default_num_nodes >= 2 && var.default_num_nodes <= 50
    error_message = "Number of nodes must be between 2 and 50 for multi-node parallel jobs."
  }
}

variable "default_vcpus_per_node" {
  description = "Default number of vCPUs per node"
  type        = number
  default     = 2

  validation {
    condition     = var.default_vcpus_per_node >= 1 && var.default_vcpus_per_node <= 96
    error_message = "vCPUs per node must be between 1 and 96."
  }
}

variable "default_memory_per_node" {
  description = "Default memory per node in MiB"
  type        = number
  default     = 4096

  validation {
    condition     = var.default_memory_per_node >= 512 && var.default_memory_per_node <= 786432
    error_message = "Memory per node must be between 512 MiB and 786432 MiB (768 GiB)."
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

variable "job_timeout_seconds" {
  description = "Job timeout in seconds"
  type        = number
  default     = 3600

  validation {
    condition     = var.job_timeout_seconds >= 60 && var.job_timeout_seconds <= 604800
    error_message = "Job timeout must be between 60 seconds (1 minute) and 604800 seconds (7 days)."
  }
}

# -----------------------------------------------------------------------------
# EFS Configuration
# -----------------------------------------------------------------------------

variable "efs_performance_mode" {
  description = "Performance mode for EFS file system"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.efs_performance_mode)
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  description = "Throughput mode for EFS file system"
  type        = string
  default     = "provisioned"

  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput for EFS in MiB/s (only used when throughput_mode is 'provisioned')"
  type        = number
  default     = 100

  validation {
    condition     = var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 1024
    error_message = "EFS provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

variable "efs_transition_to_ia" {
  description = "Transition files to Infrequent Access storage class after this period"
  type        = string
  default     = "AFTER_30_DAYS"

  validation {
    condition = contains([
      "AFTER_7_DAYS",
      "AFTER_14_DAYS", 
      "AFTER_30_DAYS",
      "AFTER_60_DAYS",
      "AFTER_90_DAYS"
    ], var.efs_transition_to_ia)
    error_message = "EFS transition to IA must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

# -----------------------------------------------------------------------------
# Monitoring and Logging Configuration
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention periods."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (optional)"
  type        = string
  default     = null

  validation {
    condition     = var.sns_topic_arn == null || can(regex("^arn:aws:sns:", var.sns_topic_arn))
    error_message = "SNS topic ARN must be a valid ARN starting with 'arn:aws:sns:' or null."
  }
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for ECS"
  type        = bool
  default     = false
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Cost Optimization Configuration
# -----------------------------------------------------------------------------

variable "enable_spot_instances" {
  description = "Enable Spot instances in the compute environment (not recommended for multi-node jobs)"
  type        = bool
  default     = false

  validation {
    condition     = var.enable_spot_instances == false
    error_message = "Spot instances are not supported for multi-node parallel jobs."
  }
}

variable "allocation_strategy" {
  description = "Allocation strategy for compute environment"
  type        = string
  default     = "BEST_FIT_PROGRESSIVE"

  validation {
    condition = contains([
      "BEST_FIT",
      "BEST_FIT_PROGRESSIVE", 
      "SPOT_CAPACITY_OPTIMIZED"
    ], var.allocation_strategy)
    error_message = "Allocation strategy must be one of: BEST_FIT, BEST_FIT_PROGRESSIVE, SPOT_CAPACITY_OPTIMIZED."
  }
}

# -----------------------------------------------------------------------------
# Advanced Configuration
# -----------------------------------------------------------------------------

variable "ec2_key_pair" {
  description = "EC2 Key Pair name for SSH access to compute instances (optional)"
  type        = string
  default     = null
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to compute instances"
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "User data script for compute instances (base64 encoded)"
  type        = string
  default     = null
}

variable "placement_group_strategy" {
  description = "Placement group strategy for enhanced networking"
  type        = string
  default     = "cluster"

  validation {
    condition     = contains(["cluster", "partition", "spread"], var.placement_group_strategy)
    error_message = "Placement group strategy must be one of: cluster, partition, spread."
  }
}

# -----------------------------------------------------------------------------
# HPC-Specific Configuration
# -----------------------------------------------------------------------------

variable "enable_enhanced_networking" {
  description = "Enable enhanced networking (SR-IOV) for supported instance types"
  type        = bool
  default     = true
}

variable "enable_placement_group" {
  description = "Create and use placement group for enhanced networking"
  type        = bool
  default     = true
}

variable "mpi_slots_per_node" {
  description = "Number of MPI slots per node (usually equal to vCPUs)"
  type        = number
  default     = null

  validation {
    condition     = var.mpi_slots_per_node == null || (var.mpi_slots_per_node >= 1 && var.mpi_slots_per_node <= 96)
    error_message = "MPI slots per node must be between 1 and 96 or null."
  }
}

# -----------------------------------------------------------------------------
# Container Configuration
# -----------------------------------------------------------------------------

variable "container_image_tag" {
  description = "Docker image tag for the MPI container"
  type        = string
  default     = "latest"
}

variable "container_working_directory" {
  description = "Working directory inside the container"
  type        = string
  default     = "/app"
}

variable "container_ulimits" {
  description = "Container ulimits configuration"
  type = list(object({
    name      = string
    softLimit = number
    hardLimit = number
  }))
  default = [
    {
      name      = "memlock"
      softLimit = -1
      hardLimit = -1
    },
    {
      name      = "stack"
      softLimit = 67108864
      hardLimit = 67108864
    }
  ]
}

# -----------------------------------------------------------------------------
# Data Management Configuration
# -----------------------------------------------------------------------------

variable "create_input_bucket" {
  description = "Create an S3 bucket for input data"
  type        = bool
  default     = false
}

variable "create_output_bucket" {
  description = "Create an S3 bucket for output data"
  type        = bool
  default     = false
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "scientific-computing"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# -----------------------------------------------------------------------------
# Development and Testing Configuration
# -----------------------------------------------------------------------------

variable "create_bastion_host" {
  description = "Create a bastion host for SSH access to private subnets"
  type        = bool
  default     = false
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host"
  type        = string
  default     = "t3.micro"
}

variable "enable_ssh_access" {
  description = "Enable SSH access to compute instances from within VPC"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Backup and Disaster Recovery
# -----------------------------------------------------------------------------

variable "enable_efs_backup" {
  description = "Enable automatic backups for EFS file system"
  type        = bool
  default     = true
}

variable "efs_backup_retention_days" {
  description = "Number of days to retain EFS backups"
  type        = number
  default     = 30

  validation {
    condition     = var.efs_backup_retention_days >= 1 && var.efs_backup_retention_days <= 3653
    error_message = "EFS backup retention must be between 1 and 3653 days."
  }
}

# -----------------------------------------------------------------------------
# Tagging Configuration
# -----------------------------------------------------------------------------

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}