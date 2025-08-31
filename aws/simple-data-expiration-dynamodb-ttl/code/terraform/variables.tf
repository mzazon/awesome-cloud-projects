# Input variables for DynamoDB TTL infrastructure
# These variables allow customization of the DynamoDB table and TTL configuration

variable "aws_region" {
  description = "AWS region where DynamoDB table will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "table_name_prefix" {
  description = "Prefix for the DynamoDB table name. Random suffix will be added for uniqueness"
  type        = string
  default     = "session-data"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.table_name_prefix))
    error_message = "Table name prefix must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "ttl_attribute_name" {
  description = "Name of the TTL attribute in DynamoDB table"
  type        = string
  default     = "expires_at"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_]+$", var.ttl_attribute_name))
    error_message = "TTL attribute name must contain only alphanumeric characters and underscores."
  }
}

variable "billing_mode" {
  description = "DynamoDB billing mode (ON_DEMAND or PROVISIONED)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "PROVISIONED"], var.billing_mode)
    error_message = "Billing mode must be either ON_DEMAND or PROVISIONED."
  }
}

variable "read_capacity" {
  description = "Read capacity units for DynamoDB table (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5

  validation {
    condition     = var.read_capacity >= 1 && var.read_capacity <= 40000
    error_message = "Read capacity must be between 1 and 40000."
  }
}

variable "write_capacity" {
  description = "Write capacity units for DynamoDB table (only used if billing_mode is PROVISIONED)"
  type        = number
  default     = 5

  validation {
    condition     = var.write_capacity >= 1 && var.write_capacity <= 40000
    error_message = "Write capacity must be between 1 and 40000."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for the DynamoDB table"
  type        = bool
  default     = false
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption for the DynamoDB table"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for server-side encryption (leave empty to use AWS managed key)"
  type        = string
  default     = ""
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring for TTL metrics"
  type        = bool
  default     = true
}

variable "create_sample_data" {
  description = "Create sample data items with various TTL values for demonstration"
  type        = bool
  default     = true
}

variable "cost_center" {
  description = "Cost center for resource tagging and billing allocation"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner of the resources for contact and management purposes"
  type        = string
  default     = "platform-team"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}