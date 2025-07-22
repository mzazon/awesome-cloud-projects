# Variables for decentralized identity management blockchain infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-east-1)."
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
  default     = "identity-blockchain"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

# Blockchain Network Configuration
variable "network_name" {
  description = "Name for the Managed Blockchain network"
  type        = string
  default     = ""
}

variable "member_name" {
  description = "Name for the blockchain network member"
  type        = string
  default     = ""
}

variable "blockchain_framework" {
  description = "Blockchain framework to use"
  type        = string
  default     = "HYPERLEDGER_FABRIC"
  validation {
    condition     = var.blockchain_framework == "HYPERLEDGER_FABRIC"
    error_message = "Currently only HYPERLEDGER_FABRIC is supported."
  }
}

variable "framework_version" {
  description = "Version of Hyperledger Fabric to use"
  type        = string
  default     = "2.2"
  validation {
    condition     = contains(["2.2"], var.framework_version)
    error_message = "Framework version must be 2.2."
  }
}

variable "admin_username" {
  description = "Admin username for blockchain member"
  type        = string
  default     = "admin"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.admin_username))
    error_message = "Admin username must start with a letter and contain only alphanumeric characters."
  }
}

variable "admin_password" {
  description = "Admin password for blockchain member (minimum 8 characters)"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "Admin password must be at least 8 characters long."
  }
}

# Peer Node Configuration
variable "peer_instance_type" {
  description = "Instance type for blockchain peer nodes"
  type        = string
  default     = "bc.t3.small"
  validation {
    condition = contains([
      "bc.t3.small", "bc.t3.medium", "bc.t3.large",
      "bc.m5.large", "bc.m5.xlarge", "bc.m5.2xlarge", "bc.m5.4xlarge"
    ], var.peer_instance_type)
    error_message = "Peer instance type must be a valid blockchain instance type."
  }
}

variable "peer_availability_zone" {
  description = "Availability zone for peer node (will be appended to region)"
  type        = string
  default     = "a"
  validation {
    condition     = can(regex("^[a-z]$", var.peer_availability_zone))
    error_message = "Availability zone must be a single lowercase letter."
  }
}

# QLDB Configuration
variable "qldb_ledger_name" {
  description = "Name for the QLDB ledger"
  type        = string
  default     = ""
}

variable "qldb_permissions_mode" {
  description = "Permissions mode for QLDB ledger"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["ALLOW_ALL", "STANDARD"], var.qldb_permissions_mode)
    error_message = "QLDB permissions mode must be ALLOW_ALL or STANDARD."
  }
}

variable "qldb_deletion_protection" {
  description = "Enable deletion protection for QLDB ledger"
  type        = bool
  default     = false
}

# DynamoDB Configuration
variable "dynamodb_table_name" {
  description = "Name for the DynamoDB credentials table"
  type        = string
  default     = ""
}

variable "dynamodb_read_capacity" {
  description = "Read capacity units for DynamoDB table"
  type        = number
  default     = 5
  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40000."
  }
}

variable "dynamodb_write_capacity" {
  description = "Write capacity units for DynamoDB table"
  type        = number
  default     = 5
  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40000."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = ""
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "nodejs18.x"
  validation {
    condition = contains([
      "nodejs18.x", "nodejs20.x", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported runtime version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 256
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# API Gateway Configuration
variable "api_name" {
  description = "Name for the API Gateway"
  type        = string
  default     = ""
}

variable "api_description" {
  description = "Description for the API Gateway"
  type        = string
  default     = "Decentralized Identity Management API"
}

variable "api_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.api_stage_name))
    error_message = "API stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (leave empty for auto-generated name)"
  type        = string
  default     = ""
}

variable "s3_versioning_enabled" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}

variable "s3_encryption_enabled" {
  description = "Enable encryption for S3 bucket"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for enhanced security"
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the API"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid."
  }
}

# Cost Optimization
variable "enable_spot_instances" {
  description = "Use spot instances where applicable for cost optimization"
  type        = bool
  default     = false
}

variable "auto_scaling_enabled" {
  description = "Enable auto-scaling for applicable resources"
  type        = bool
  default     = true
}

# Monitoring and Logging
variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for resources"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Backup and Recovery
variable "enable_backups" {
  description = "Enable automated backups where applicable"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention days must be between 1 and 35."
  }
}

# Advanced Configuration
variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "secondary_region" {
  description = "Secondary AWS region for disaster recovery"
  type        = string
  default     = "us-west-2"
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "Secondary region must be in valid AWS region format."
  }
}

# Compliance and Governance
variable "enable_compliance_logging" {
  description = "Enable additional logging for compliance requirements"
  type        = bool
  default     = true
}

variable "data_classification" {
  description = "Data classification level for the system"
  type        = string
  default     = "confidential"
  validation {
    condition     = contains(["public", "internal", "confidential", "restricted"], var.data_classification)
    error_message = "Data classification must be one of: public, internal, confidential, restricted."
  }
}

# Resource Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}