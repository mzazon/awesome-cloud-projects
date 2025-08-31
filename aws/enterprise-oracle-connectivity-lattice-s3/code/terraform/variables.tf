# Variables for Enterprise Oracle Database Connectivity with VPC Lattice and S3
# Comprehensive configuration options for the Oracle Database@AWS integration

# =============================================================================
# BASIC CONFIGURATION
# =============================================================================

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "enterprise-oracle"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# =============================================================================
# ORACLE DATABASE@AWS CONFIGURATION
# =============================================================================

variable "odb_network_id" {
  description = "Existing Oracle Database@AWS network ID. If not provided, will attempt to find default network."
  type        = string
  default     = ""
}

variable "enable_s3_access" {
  description = "Enable S3 access for Oracle Database@AWS network"
  type        = bool
  default     = true
}

variable "enable_zero_etl_access" {
  description = "Enable Zero-ETL access for Oracle Database@AWS network"
  type        = bool
  default     = true
}

# =============================================================================
# S3 CONFIGURATION
# =============================================================================

variable "s3_bucket_name" {
  description = "Name for the S3 backup bucket. If empty, will be auto-generated."
  type        = string
  default     = ""
}

variable "enable_s3_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_ia_days" {
  description = "Number of days before transitioning to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_lifecycle_transition_ia_days >= 1
    error_message = "IA transition days must be at least 1."
  }
}

variable "s3_lifecycle_transition_glacier_days" {
  description = "Number of days before transitioning to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.s3_lifecycle_transition_glacier_days >= 1
    error_message = "Glacier transition days must be at least 1."
  }
}

variable "s3_encryption_algorithm" {
  description = "Server-side encryption algorithm for S3 bucket"
  type        = string
  default     = "AES256"
  
  validation {
    condition     = contains(["AES256", "aws:kms"], var.s3_encryption_algorithm)
    error_message = "Encryption algorithm must be either AES256 or aws:kms."
  }
}

# =============================================================================
# REDSHIFT CONFIGURATION
# =============================================================================

variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster. If empty, will be auto-generated."
  type        = string
  default     = ""
}

variable "redshift_node_type" {
  description = "Node type for the Redshift cluster"
  type        = string
  default     = "dc2.large"
  
  validation {
    condition = contains([
      "dc2.large", "dc2.8xlarge", "ds2.xlarge", "ds2.8xlarge",
      "ra3.xlplus", "ra3.4xlarge", "ra3.16xlarge"
    ], var.redshift_node_type)
    error_message = "Invalid Redshift node type specified."
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
  default     = 2
  
  validation {
    condition     = var.redshift_number_of_nodes >= 2
    error_message = "Number of nodes must be at least 2 for multi-node clusters."
  }
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster"
  type        = string
  default     = "oracleadmin"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.redshift_master_username))
    error_message = "Master username must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "redshift_master_password" {
  description = "Master password for the Redshift cluster"
  type        = string
  default     = "OracleAnalytics123!"
  sensitive   = true
  
  validation {
    condition     = length(var.redshift_master_password) >= 8
    error_message = "Master password must be at least 8 characters long."
  }
}

variable "redshift_database_name" {
  description = "Name of the default database in the Redshift cluster"
  type        = string
  default     = "oracleanalytics"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.redshift_database_name))
    error_message = "Database name must start with a letter and contain only lowercase letters, numbers, and underscores."
  }
}

variable "redshift_port" {
  description = "Port for the Redshift cluster"
  type        = number
  default     = 5439
  
  validation {
    condition     = var.redshift_port >= 1024 && var.redshift_port <= 65535
    error_message = "Port must be between 1024 and 65535."
  }
}

variable "redshift_encrypted" {
  description = "Enable encryption at rest for the Redshift cluster"
  type        = bool
  default     = true
}

variable "redshift_publicly_accessible" {
  description = "Make the Redshift cluster publicly accessible"
  type        = bool
  default     = false
}

# =============================================================================
# CLOUDWATCH CONFIGURATION
# =============================================================================

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and dashboard"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "vpc_id" {
  description = "VPC ID for resources that require it. If empty, will use default VPC."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for resources that require them"
  type        = list(string)
  default     = []
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "enable_s3_bucket_policy" {
  description = "Enable custom S3 bucket policy for Oracle Database access"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access resources"
  type        = list(string)
  default     = ["10.0.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid."
  }
}

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

variable "enable_spot_instances" {
  description = "Use spot instances where possible for cost optimization"
  type        = bool
  default     = false
}

variable "enable_auto_pause" {
  description = "Enable auto-pause for Redshift cluster (where supported)"
  type        = bool
  default     = false
}

# =============================================================================
# ADDITIONAL TAGS
# =============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}