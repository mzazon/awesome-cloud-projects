# General Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]+-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format of region-zone-number (e.g., us-east-1)."
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
  description = "Name of the project"
  type        = string
  default     = "supply-chain-tracking"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Blockchain Network Configuration
variable "network_name" {
  description = "Name of the blockchain network"
  type        = string
  default     = "supply-chain-network"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.network_name))
    error_message = "Network name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "network_edition" {
  description = "Amazon Managed Blockchain network edition"
  type        = string
  default     = "STARTER"

  validation {
    condition     = contains(["STARTER", "STANDARD"], var.network_edition)
    error_message = "Network edition must be either STARTER or STANDARD."
  }
}

variable "fabric_version" {
  description = "Hyperledger Fabric version"
  type        = string
  default     = "2.2"

  validation {
    condition     = contains(["1.4", "2.2"], var.fabric_version)
    error_message = "Fabric version must be either 1.4 or 2.2."
  }
}

variable "member_name" {
  description = "Name of the blockchain network member"
  type        = string
  default     = "manufacturer"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.member_name))
    error_message = "Member name must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "admin_username" {
  description = "Admin username for blockchain member"
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.admin_username))
    error_message = "Admin username must start with a letter and contain only letters and numbers."
  }
}

variable "admin_password" {
  description = "Admin password for blockchain member"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 8
    error_message = "Admin password must be at least 8 characters long."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for blockchain node"
  type        = string
  default     = "bc.t3.small"

  validation {
    condition = can(regex("^bc\\.(t3|m5|c5)\\.(small|medium|large|xlarge)$", var.node_instance_type))
    error_message = "Node instance type must be a valid blockchain instance type (e.g., bc.t3.small, bc.m5.large)."
  }
}

variable "node_availability_zone" {
  description = "Availability zone for blockchain node (will be appended to region)"
  type        = string
  default     = "a"

  validation {
    condition     = can(regex("^[a-z]$", var.node_availability_zone))
    error_message = "Availability zone must be a single lowercase letter (a, b, c, etc.)."
  }
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"

  validation {
    condition = contains([
      "nodejs14.x", "nodejs16.x", "nodejs18.x", "nodejs20.x",
      "python3.8", "python3.9", "python3.10", "python3.11"
    ], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported runtime version."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions (MB)"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions (seconds)"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

# IoT Configuration
variable "iot_thing_type_name" {
  description = "IoT Thing Type name for supply chain trackers"
  type        = string
  default     = "SupplyChainTracker"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.iot_thing_type_name))
    error_message = "IoT Thing Type name must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "iot_policy_name" {
  description = "IoT policy name for supply chain devices"
  type        = string
  default     = "SupplyChainTrackerPolicy"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.iot_policy_name))
    error_message = "IoT policy name must start with a letter and contain only letters, numbers, and underscores."
  }
}

# DynamoDB Configuration
variable "dynamodb_table_name" {
  description = "DynamoDB table name for supply chain metadata"
  type        = string
  default     = "SupplyChainMetadata"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_.-]*$", var.dynamodb_table_name))
    error_message = "DynamoDB table name must start with a letter and contain only letters, numbers, underscores, periods, and hyphens."
  }
}

variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_read_capacity >= 1 && var.dynamodb_read_capacity <= 40000
    error_message = "DynamoDB read capacity must be between 1 and 40,000."
  }
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units"
  type        = number
  default     = 5

  validation {
    condition     = var.dynamodb_write_capacity >= 1 && var.dynamodb_write_capacity <= 40000
    error_message = "DynamoDB write capacity must be between 1 and 40,000."
  }
}

# EventBridge Configuration
variable "eventbridge_rule_name" {
  description = "EventBridge rule name for supply chain events"
  type        = string
  default     = "SupplyChainTrackingRule"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_.-]*$", var.eventbridge_rule_name))
    error_message = "EventBridge rule name must start with a letter and contain only letters, numbers, underscores, periods, and hyphens."
  }
}

# SNS Configuration
variable "sns_topic_name" {
  description = "SNS topic name for supply chain notifications"
  type        = string
  default     = "supply-chain-notifications"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.sns_topic_name))
    error_message = "SNS topic name must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "notification_emails" {
  description = "List of email addresses for supply chain notifications"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.notification_emails :
      can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All notification emails must be valid email addresses."
  }
}

# CloudWatch Configuration
variable "dashboard_name" {
  description = "CloudWatch dashboard name"
  type        = string
  default     = "SupplyChainTracking"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]*$", var.dashboard_name))
    error_message = "Dashboard name must start with a letter and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "enable_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# Security Configuration
variable "enable_encryption" {
  description = "Enable encryption for storage services"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7

  validation {
    condition     = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

# Cost Management
variable "enable_cost_allocation_tags" {
  description = "Enable cost allocation tags for billing"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days."
  }
}