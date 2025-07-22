# Environment Configuration
variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "availability_zone" {
  description = "Availability zone for subnet placement"
  type        = string
  default     = "us-east-1a"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.availability_zone))
    error_message = "Availability zone must be a valid AZ identifier."
  }
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the ParallelCluster HPC cluster"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name)) || var.cluster_name == ""
    error_message = "Cluster name must contain only letters, numbers, and hyphens."
  }
}

variable "head_node_instance_type" {
  description = "Instance type for the head node"
  type        = string
  default     = "m5.large"
  validation {
    condition = contains([
      "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
      "m5.8xlarge", "m5.12xlarge", "m5.16xlarge", "m5.24xlarge",
      "m5a.large", "m5a.xlarge", "m5a.2xlarge", "m5a.4xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge"
    ], var.head_node_instance_type)
    error_message = "Head node instance type must be a valid compute-optimized or general-purpose instance type."
  }
}

variable "compute_instance_type" {
  description = "Instance type for compute nodes"
  type        = string
  default     = "c5n.large"
  validation {
    condition = contains([
      "c5n.large", "c5n.xlarge", "c5n.2xlarge", "c5n.4xlarge", "c5n.9xlarge", "c5n.18xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge", "c5.9xlarge", "c5.18xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge", "m5.8xlarge", "m5.12xlarge",
      "m5n.large", "m5n.xlarge", "m5n.2xlarge", "m5n.4xlarge", "m5n.8xlarge", "m5n.12xlarge"
    ], var.compute_instance_type)
    error_message = "Compute instance type must be a valid HPC-optimized instance type."
  }
}

variable "min_compute_nodes" {
  description = "Minimum number of compute nodes"
  type        = number
  default     = 0
  validation {
    condition     = var.min_compute_nodes >= 0 && var.min_compute_nodes <= 100
    error_message = "Minimum compute nodes must be between 0 and 100."
  }
}

variable "max_compute_nodes" {
  description = "Maximum number of compute nodes"
  type        = number
  default     = 10
  validation {
    condition     = var.max_compute_nodes >= 1 && var.max_compute_nodes <= 1000
    error_message = "Maximum compute nodes must be between 1 and 1000."
  }
}

variable "enable_efa" {
  description = "Enable Elastic Fabric Adapter for high-performance networking"
  type        = bool
  default     = true
}

variable "disable_hyperthreading" {
  description = "Disable simultaneous multithreading for compute nodes"
  type        = bool
  default     = true
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
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

# Storage Configuration
variable "shared_storage_size" {
  description = "Size of shared EBS storage in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.shared_storage_size >= 50 && var.shared_storage_size <= 16384
    error_message = "Shared storage size must be between 50 GB and 16 TB."
  }
}

variable "fsx_storage_capacity" {
  description = "FSx Lustre storage capacity in GB"
  type        = number
  default     = 1200
  validation {
    condition = contains([
      1200, 2400, 3600, 7200, 10800, 14400, 18000, 21600,
      25200, 28800, 32400, 36000, 39600, 43200, 46800, 50400
    ], var.fsx_storage_capacity)
    error_message = "FSx storage capacity must be a valid increment (1200 GB minimum, 1200 GB increments)."
  }
}

variable "fsx_deployment_type" {
  description = "FSx Lustre deployment type"
  type        = string
  default     = "SCRATCH_2"
  validation {
    condition     = contains(["SCRATCH_1", "SCRATCH_2", "PERSISTENT_1", "PERSISTENT_2"], var.fsx_deployment_type)
    error_message = "FSx deployment type must be SCRATCH_1, SCRATCH_2, PERSISTENT_1, or PERSISTENT_2."
  }
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 50
  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size must be between 20 GB and 1000 GB."
  }
}

variable "root_volume_type" {
  description = "Type of root EBS volume"
  type        = string
  default     = "gp3"
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "Root volume type must be gp2, gp3, io1, or io2."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and dashboards"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for the cluster"
  type        = bool
  default     = true
}

# Scheduler Configuration
variable "scheduler_type" {
  description = "Job scheduler type"
  type        = string
  default     = "slurm"
  validation {
    condition     = contains(["slurm", "awsbatch"], var.scheduler_type)
    error_message = "Scheduler type must be slurm or awsbatch."
  }
}

variable "scaledown_idletime" {
  description = "Time in minutes before idle nodes are terminated"
  type        = number
  default     = 5
  validation {
    condition     = var.scaledown_idletime >= 1 && var.scaledown_idletime <= 60
    error_message = "Scaledown idle time must be between 1 and 60 minutes."
  }
}

# Security Configuration
variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH access to head node"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidr : can(cidrhost(cidr, 0))])
    error_message = "All SSH CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "enable_ebs_encryption" {
  description = "Enable EBS encryption for volumes"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for EBS encryption (optional)"
  type        = string
  default     = ""
}

# Additional Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "cluster_config_template" {
  description = "Custom ParallelCluster configuration template"
  type        = string
  default     = ""
}

variable "custom_ami_id" {
  description = "Custom AMI ID for cluster nodes (optional)"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^ami-[a-z0-9]+$", var.custom_ami_id)) || var.custom_ami_id == ""
    error_message = "Custom AMI ID must be a valid AMI identifier or empty."
  }
}