# variables.tf
# Variable definitions for real-time data quality monitoring with Deequ on EMR

# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
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

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "deequ-quality-monitor"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# EMR Configuration
variable "emr_release_label" {
  description = "EMR release version"
  type        = string
  default     = "emr-6.15.0"
  
  validation {
    condition = can(regex("^emr-[0-9]+\\.[0-9]+\\.[0-9]+$", var.emr_release_label))
    error_message = "EMR release label must be in format emr-X.Y.Z."
  }
}

variable "emr_instance_type" {
  description = "EC2 instance type for EMR cluster nodes"
  type        = string
  default     = "m5.xlarge"
  
  validation {
    condition = can(regex("^[a-z][0-9][a-z]?\\.[a-z0-9]+$", var.emr_instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "emr_instance_count" {
  description = "Number of instances in EMR cluster"
  type        = number
  default     = 3
  
  validation {
    condition = var.emr_instance_count >= 1 && var.emr_instance_count <= 20
    error_message = "EMR instance count must be between 1 and 20."
  }
}

variable "emr_auto_termination_timeout" {
  description = "Auto-termination timeout in seconds for EMR cluster (0 to disable)"
  type        = number
  default     = 3600
  
  validation {
    condition = var.emr_auto_termination_timeout >= 0
    error_message = "Auto-termination timeout must be non-negative."
  }
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for S3 bucket (will be made unique with random suffix)"
  type        = string
  default     = "deequ-data-quality"
  
  validation {
    condition = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.s3_bucket_name))
    error_message = "S3 bucket name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

# SNS Configuration
variable "notification_email" {
  description = "Email address for data quality alerts"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# CloudWatch Configuration
variable "create_dashboard" {
  description = "Create CloudWatch dashboard for data quality metrics"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Deequ Configuration
variable "deequ_version" {
  description = "Deequ library version"
  type        = string
  default     = "2.0.4-spark-3.4"
}

variable "spark_configurations" {
  description = "Additional Spark configurations for EMR"
  type        = map(string)
  default = {
    "spark.sql.adaptive.enabled"                = "true"
    "spark.sql.adaptive.coalescePartitions.enabled" = "true"
    "spark.serializer"                          = "org.apache.spark.serializer.KryoSerializer"
    "spark.dynamicAllocation.enabled"           = "true"
    "spark.dynamicAllocation.minExecutors"      = "1"
    "spark.dynamicAllocation.maxExecutors"      = "10"
  }
}

# Security Configuration
variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for EMR cluster"
  type        = bool
  default     = true
}

variable "enable_encryption_in_transit" {
  description = "Enable encryption in transit for EMR cluster"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access EMR cluster"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid."
  }
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID for EMR cluster deployment (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for EMR cluster deployment (leave empty to use default subnet)"
  type        = string
  default     = ""
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Use Spot instances for EMR cluster to reduce costs"
  type        = bool
  default     = false
}

variable "spot_instance_percentage" {
  description = "Percentage of Spot instances in the cluster (when spot instances are enabled)"
  type        = number
  default     = 50
  
  validation {
    condition = var.spot_instance_percentage >= 0 && var.spot_instance_percentage <= 100
    error_message = "Spot instance percentage must be between 0 and 100."
  }
}