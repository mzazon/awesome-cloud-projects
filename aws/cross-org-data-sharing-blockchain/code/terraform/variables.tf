# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
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

# Blockchain Network Configuration
variable "network_name" {
  description = "Name for the managed blockchain network"
  type        = string
  default     = "cross-org-network"
}

variable "network_description" {
  description = "Description for the blockchain network"
  type        = string
  default     = "Cross-Organization Data Sharing Network"
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
  description = "Version of the blockchain framework"
  type        = string
  default     = "2.2"
}

variable "network_edition" {
  description = "Network edition (STARTER or STANDARD)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STARTER", "STANDARD"], var.network_edition)
    error_message = "Network edition must be either STARTER or STANDARD."
  }
}

# Organization Configuration
variable "organization_a_name" {
  description = "Name for Organization A"
  type        = string
  default     = "financial-institution"
}

variable "organization_a_description" {
  description = "Description for Organization A"
  type        = string
  default     = "Financial Institution Member"
}

variable "organization_b_name" {
  description = "Name for Organization B"
  type        = string
  default     = "healthcare-provider"
}

variable "organization_b_description" {
  description = "Description for Organization B"
  type        = string
  default     = "Healthcare Provider Member"
}

variable "admin_username" {
  description = "Admin username for blockchain members"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Admin password for blockchain members"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
}

# Node Configuration
variable "node_instance_type" {
  description = "Instance type for blockchain nodes"
  type        = string
  default     = "bc.t3.medium"
  
  validation {
    condition = contains([
      "bc.t3.small", "bc.t3.medium", "bc.t3.large", "bc.t3.xlarge",
      "bc.m5.large", "bc.m5.xlarge", "bc.m5.2xlarge", "bc.m5.4xlarge"
    ], var.node_instance_type)
    error_message = "Invalid node instance type. Must be a valid blockchain instance type."
  }
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name for the data validation Lambda function"
  type        = string
  default     = "CrossOrgDataValidator"
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 60
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# DynamoDB Configuration
variable "audit_table_name" {
  description = "Name for the audit trail DynamoDB table"
  type        = string
  default     = "CrossOrgAuditTrail"
}

variable "audit_table_read_capacity" {
  description = "Read capacity units for the audit table"
  type        = number
  default     = 5
}

variable "audit_table_write_capacity" {
  description = "Write capacity units for the audit table"
  type        = number
  default     = 5
}

# Storage Configuration
variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be suffixed with random string)"
  type        = string
  default     = "cross-org-data"
}

# EventBridge Configuration
variable "eventbridge_rule_name" {
  description = "Name for the EventBridge rule"
  type        = string
  default     = "CrossOrgDataSharingRule"
}

variable "sns_topic_name" {
  description = "Name for the SNS topic"
  type        = string
  default     = "cross-org-notifications"
}

# Voting Policy Configuration
variable "voting_threshold_percentage" {
  description = "Percentage threshold for voting approval"
  type        = number
  default     = 66
  
  validation {
    condition     = var.voting_threshold_percentage >= 50 && var.voting_threshold_percentage <= 100
    error_message = "Voting threshold percentage must be between 50 and 100."
  }
}

variable "proposal_duration_hours" {
  description = "Duration in hours for proposal voting"
  type        = number
  default     = 24
  
  validation {
    condition     = var.proposal_duration_hours >= 1 && var.proposal_duration_hours <= 168
    error_message = "Proposal duration must be between 1 and 168 hours (1 week)."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_dashboard" {
  description = "Enable CloudWatch dashboard creation"
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
    error_message = "Invalid log retention period."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}