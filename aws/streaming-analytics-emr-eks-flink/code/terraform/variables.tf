# Input variables for the real-time streaming analytics infrastructure

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-west-2'."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "emr-flink-analytics"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_name))
    error_message = "Cluster name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "emr_namespace" {
  description = "Kubernetes namespace for EMR on EKS workloads"
  type        = string
  default     = "emr-flink"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = true
}

variable "node_group_instance_types" {
  description = "Instance types for EKS managed node groups"
  type        = list(string)
  default     = ["m5.xlarge", "m5.2xlarge"]
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the EKS managed node group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.node_group_min_size >= 1
    error_message = "Minimum node group size must be at least 1."
  }
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the EKS managed node group"
  type        = number
  default     = 10
  
  validation {
    condition     = var.node_group_max_size >= var.node_group_min_size
    error_message = "Maximum node group size must be greater than or equal to minimum size."
  }
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the EKS managed node group"
  type        = number
  default     = 4
}

variable "node_group_disk_size" {
  description = "Disk size in GB for EKS managed node group instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.node_group_disk_size >= 20
    error_message = "Node group disk size must be at least 20 GB."
  }
}

variable "trading_stream_shard_count" {
  description = "Number of shards for the trading events Kinesis stream"
  type        = number
  default     = 4
  
  validation {
    condition     = var.trading_stream_shard_count >= 1 && var.trading_stream_shard_count <= 1000
    error_message = "Trading stream shard count must be between 1 and 1000."
  }
}

variable "market_stream_shard_count" {
  description = "Number of shards for the market data Kinesis stream"
  type        = number
  default     = 2
  
  validation {
    condition     = var.market_stream_shard_count >= 1 && var.market_stream_shard_count <= 1000
    error_message = "Market stream shard count must be between 1 and 1000."
  }
}

variable "kinesis_retention_period" {
  description = "Data retention period for Kinesis streams (in hours)"
  type        = number
  default     = 24
  
  validation {
    condition     = var.kinesis_retention_period >= 24 && var.kinesis_retention_period <= 8760
    error_message = "Kinesis retention period must be between 24 and 8760 hours."
  }
}

variable "s3_lifecycle_ia_days" {
  description = "Number of days after which to transition objects to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_ia_days >= 30
    error_message = "S3 IA transition must be at least 30 days."
  }
}

variable "s3_lifecycle_glacier_days" {
  description = "Number of days after which to transition objects to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_glacier_days >= 90
    error_message = "S3 Glacier transition must be at least 90 days."
  }
}

variable "enable_monitoring" {
  description = "Enable Prometheus and Grafana monitoring stack"
  type        = bool
  default     = true
}

variable "enable_data_generator" {
  description = "Deploy data generator for testing"
  type        = bool
  default     = true
}

variable "flink_operator_version" {
  description = "Version of the Flink Kubernetes operator"
  type        = string
  default     = "1.7.0"
}

variable "flink_image_tag" {
  description = "Flink Docker image tag for EMR on EKS"
  type        = string
  default     = "1.17.1-emr-7.0.0"
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}