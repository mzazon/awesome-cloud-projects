# variables.tf - Input variables for AWS Application Migration Service infrastructure
# This file defines all configurable parameters for the migration infrastructure

variable "aws_region" {
  description = "AWS region for deploying MGN infrastructure"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "migration"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "mgn-migration"
  
  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 50
    error_message = "Project name must be between 3 and 50 characters."
  }
}

# MGN Configuration Variables
variable "mgn_replication_server_instance_type" {
  description = "Instance type for MGN replication servers"
  type        = string
  default     = "t3.small"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.mgn_replication_server_instance_type)
    error_message = "Instance type must be a valid EC2 instance type suitable for MGN replication."
  }
}

variable "mgn_staging_disk_type" {
  description = "EBS volume type for MGN staging areas"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.mgn_staging_disk_type)
    error_message = "Staging disk type must be one of: gp2, gp3, io1, io2."
  }
}

variable "mgn_data_plane_routing" {
  description = "Data plane routing method for MGN replication"
  type        = string
  default     = "PRIVATE_IP"
  
  validation {
    condition     = contains(["PRIVATE_IP", "PUBLIC_IP"], var.mgn_data_plane_routing)
    error_message = "Data plane routing must be either PRIVATE_IP or PUBLIC_IP."
  }
}

variable "mgn_bandwidth_throttling" {
  description = "Bandwidth throttling for MGN replication in Mbps (0 = no throttling)"
  type        = number
  default     = 0
  
  validation {
    condition     = var.mgn_bandwidth_throttling >= 0 && var.mgn_bandwidth_throttling <= 10000
    error_message = "Bandwidth throttling must be between 0 and 10000 Mbps."
  }
}

variable "mgn_create_public_ip" {
  description = "Whether to create public IP for replication servers"
  type        = bool
  default     = false
}

variable "mgn_associate_default_security_group" {
  description = "Whether to associate default security group with replication servers"
  type        = bool
  default     = true
}

variable "mgn_use_dedicated_replication_server" {
  description = "Whether to use dedicated replication servers"
  type        = bool
  default     = false
}

variable "mgn_ebs_encryption" {
  description = "EBS encryption setting for MGN staging volumes"
  type        = string
  default     = "DEFAULT"
  
  validation {
    condition     = contains(["DEFAULT", "CUSTOM"], var.mgn_ebs_encryption)
    error_message = "EBS encryption must be either DEFAULT or CUSTOM."
  }
}

# Migration Wave Configuration
variable "migration_waves" {
  description = "Configuration for migration waves"
  type = list(object({
    name        = string
    description = string
    servers     = list(string)
  }))
  default = [
    {
      name        = "Wave-1-WebServers"
      description = "First wave: Web tier servers"
      servers     = []
    },
    {
      name        = "Wave-2-AppServers"
      description = "Second wave: Application tier servers"
      servers     = []
    },
    {
      name        = "Wave-3-DBServers"
      description = "Third wave: Database tier servers"
      servers     = []
    }
  ]
}

# Network Configuration
variable "staging_subnet_id" {
  description = "Subnet ID for MGN staging area (optional - will use default if not provided)"
  type        = string
  default     = ""
}

variable "replication_security_group_ids" {
  description = "Additional security group IDs for replication servers"
  type        = list(string)
  default     = []
}

# Launch Template Configuration
variable "target_instance_type_right_sizing_method" {
  description = "Right-sizing method for target instances"
  type        = string
  default     = "BASIC"
  
  validation {
    condition     = contains(["BASIC", "IN_AWS"], var.target_instance_type_right_sizing_method)
    error_message = "Right-sizing method must be either BASIC or IN_AWS."
  }
}

variable "launch_disposition" {
  description = "Launch disposition for migrated instances"
  type        = string
  default     = "STARTED"
  
  validation {
    condition     = contains(["STARTED", "STOPPED"], var.launch_disposition)
    error_message = "Launch disposition must be either STARTED or STOPPED."
  }
}

variable "copy_private_ip" {
  description = "Whether to copy private IP addresses from source servers"
  type        = bool
  default     = false
}

variable "copy_tags" {
  description = "Whether to copy tags from source servers"
  type        = bool
  default     = true
}

variable "enable_map_auto_tagging" {
  description = "Whether to enable MAP auto-tagging for migrated instances"
  type        = bool
  default     = true
}

variable "licensing_os_byol" {
  description = "Whether to use BYOL (Bring Your Own License) for operating system"
  type        = bool
  default     = true
}

# Post-Launch Actions Configuration
variable "post_launch_actions_deployment" {
  description = "Post-launch actions deployment type"
  type        = string
  default     = "TEST_AND_CUTOVER"
  
  validation {
    condition     = contains(["TEST_AND_CUTOVER", "CUTOVER_ONLY"], var.post_launch_actions_deployment)
    error_message = "Post-launch actions deployment must be either TEST_AND_CUTOVER or CUTOVER_ONLY."
  }
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for post-launch actions"
  type        = string
  default     = ""
}

variable "s3_log_bucket" {
  description = "S3 bucket for storing post-launch action logs"
  type        = string
  default     = ""
}

variable "s3_output_key_prefix" {
  description = "S3 key prefix for post-launch action outputs"
  type        = string
  default     = "mgn-logs/"
}

# Tagging Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "staging_area_tags" {
  description = "Additional tags for MGN staging area resources"
  type        = map(string)
  default = {
    Purpose = "MGN-Staging"
  }
}

# Monitoring and Alerting
variable "enable_cloudwatch_monitoring" {
  description = "Whether to enable CloudWatch monitoring for MGN resources"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for MGN notifications (optional)"
  type        = string
  default     = ""
}

# Security Configuration
variable "kms_key_id" {
  description = "KMS key ID for encrypting MGN resources (optional)"
  type        = string
  default     = ""
}