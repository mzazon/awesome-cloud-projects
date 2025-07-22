# Variables for Redshift Spectrum operational analytics infrastructure

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
  description = "Name of the project for resource naming"
  type        = string
  default     = "spectrum-analytics"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region for resources deployment"
  type        = string
  default     = "us-east-1"
}

# S3 Data Lake Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 data lake bucket (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "s3_storage_class" {
  description = "Default storage class for S3 objects"
  type        = string
  default     = "STANDARD"

  validation {
    condition = contains([
      "STANDARD",
      "STANDARD_IA",
      "ONEZONE_IA",
      "INTELLIGENT_TIERING"
    ], var.s3_storage_class)
    error_message = "Storage class must be a valid S3 storage class."
  }
}

# Redshift Cluster Configuration
variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "redshift_node_type" {
  description = "Node type for Redshift cluster"
  type        = string
  default     = "dc2.large"

  validation {
    condition = contains([
      "dc2.large",
      "dc2.8xlarge",
      "ds2.xlarge",
      "ds2.8xlarge",
      "ra3.xlplus",
      "ra3.4xlarge",
      "ra3.16xlarge"
    ], var.redshift_node_type)
    error_message = "Node type must be a valid Redshift node type."
  }
}

variable "redshift_cluster_type" {
  description = "Type of Redshift cluster (single-node or multi-node)"
  type        = string
  default     = "single-node"

  validation {
    condition     = contains(["single-node", "multi-node"], var.redshift_cluster_type)
    error_message = "Cluster type must be either single-node or multi-node."
  }
}

variable "redshift_number_of_nodes" {
  description = "Number of nodes in the Redshift cluster (only for multi-node)"
  type        = number
  default     = 1

  validation {
    condition     = var.redshift_number_of_nodes >= 1 && var.redshift_number_of_nodes <= 128
    error_message = "Number of nodes must be between 1 and 128."
  }
}

variable "redshift_master_username" {
  description = "Master username for Redshift cluster"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.redshift_master_username))
    error_message = "Master username must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "redshift_master_password" {
  description = "Master password for Redshift cluster"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.redshift_master_password == "" || (length(var.redshift_master_password) >= 8 && length(var.redshift_master_password) <= 64)
    error_message = "Password must be between 8 and 64 characters long if provided."
  }
}

variable "redshift_database_name" {
  description = "Name of the database to create in Redshift"
  type        = string
  default     = "analytics"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.redshift_database_name))
    error_message = "Database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "redshift_publicly_accessible" {
  description = "Whether the Redshift cluster is publicly accessible"
  type        = bool
  default     = false
}

variable "redshift_skip_final_snapshot" {
  description = "Whether to skip the final snapshot when deleting the cluster"
  type        = bool
  default     = true
}

# Glue Data Catalog Configuration
variable "glue_database_name" {
  description = "Name for the Glue database (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "glue_crawler_schedule" {
  description = "Schedule for Glue crawlers (cron expression)"
  type        = string
  default     = "cron(0 6 * * ? *)" # Daily at 6 AM UTC

  validation {
    condition     = can(regex("^cron\\(.*\\)$", var.glue_crawler_schedule))
    error_message = "Schedule must be a valid cron expression."
  }
}

# VPC and Networking Configuration
variable "vpc_id" {
  description = "VPC ID for Redshift cluster (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for Redshift cluster (leave empty for auto-selection)"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access Redshift cluster"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

# Sample Data Configuration
variable "create_sample_data" {
  description = "Whether to create sample operational data in S3"
  type        = bool
  default     = true
}

variable "sample_data_prefix" {
  description = "Prefix for sample data in S3"
  type        = string
  default     = "operational-data"
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}