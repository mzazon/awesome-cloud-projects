# Automated Multi-Account Resource Discovery - Terraform Variables
# This file defines all configurable parameters for the resource discovery solution

#============================================================================
# GENERAL CONFIGURATION
#============================================================================

variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = false
}

#============================================================================
# AWS CONFIG CONFIGURATION
#============================================================================

variable "all_regions" {
  description = "Whether to aggregate Config data from all AWS regions (true) or only specified regions (false)"
  type        = bool
  default     = true
}

variable "target_regions" {
  description = "List of AWS regions to include in Config aggregation (only used if all_regions is false)"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
  
  validation {
    condition     = length(var.target_regions) > 0
    error_message = "At least one target region must be specified."
  }
}

#============================================================================
# LAMBDA FUNCTION CONFIGURATION
#============================================================================

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_log_level" {
  description = "Lambda function logging level"
  type        = string
  default     = "INFO"
  
  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.lambda_log_level)
    error_message = "Lambda log level must be one of: DEBUG, INFO, WARNING, ERROR."
  }
}

#============================================================================
# EVENTBRIDGE CONFIGURATION
#============================================================================

variable "discovery_schedule" {
  description = "EventBridge schedule expression for automated resource discovery (CloudWatch Events syntax)"
  type        = string
  default     = "rate(1 day)"
  
  validation {
    condition     = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.discovery_schedule))
    error_message = "Discovery schedule must be a valid rate() or cron() expression."
  }
}

#============================================================================
# NOTIFICATION CONFIGURATION
#============================================================================

variable "notification_topic_arn" {
  description = "ARN of SNS topic for compliance and discovery notifications (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.notification_topic_arn == null || can(regex("^arn:aws:sns:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9-_]+$", var.notification_topic_arn))
    error_message = "Notification topic ARN must be a valid SNS topic ARN or null."
  }
}

variable "dlq_arn" {
  description = "ARN of SQS Dead Letter Queue for failed EventBridge invocations (optional)"
  type        = string
  default     = null
  
  validation {
    condition = var.dlq_arn == null || can(regex("^arn:aws:sqs:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9-_]+$", var.dlq_arn))
    error_message = "DLQ ARN must be a valid SQS queue ARN or null."
  }
}

#============================================================================
# LOGGING CONFIGURATION
#============================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

#============================================================================
# MONITORING CONFIGURATION
#============================================================================

variable "create_dashboard" {
  description = "Whether to create a CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}

#============================================================================
# ADVANCED CONFIGURATION
#============================================================================

variable "enable_config_rules" {
  description = "Map of Config rules to enable with their configurations"
  type = map(object({
    enabled            = bool
    source_identifier  = string
    input_parameters   = map(string)
    description        = string
    severity          = string
  }))
  
  default = {
    s3_bucket_public_access_prohibited = {
      enabled           = true
      source_identifier = "S3_BUCKET_PUBLIC_ACCESS_PROHIBITED"
      input_parameters  = {}
      description       = "Checks that S3 buckets do not allow public access"
      severity          = "HIGH"
    }
    
    ec2_security_group_attached_to_eni = {
      enabled           = true
      source_identifier = "EC2_SECURITY_GROUP_ATTACHED_TO_ENI"
      input_parameters  = {}
      description       = "Checks that security groups are attached to EC2 instances"
      severity          = "MEDIUM"
    }
    
    root_access_key_check = {
      enabled           = true
      source_identifier = "ROOT_ACCESS_KEY_CHECK"
      input_parameters  = {}
      description       = "Checks whether root access key exists"
      severity          = "CRITICAL"
    }
    
    encrypted_volumes = {
      enabled           = true
      source_identifier = "ENCRYPTED_VOLUMES"
      input_parameters  = {}
      description       = "Checks whether EBS volumes are encrypted"
      severity          = "HIGH"
    }
    
    iam_password_policy = {
      enabled           = true
      source_identifier = "IAM_PASSWORD_POLICY"
      input_parameters = {
        RequireUppercaseCharacters = "true"
        RequireLowercaseCharacters = "true"
        RequireSymbols            = "true"
        RequireNumbers            = "true"
        MinimumPasswordLength     = "14"
        PasswordReusePrevention   = "24"
        MaxPasswordAge            = "90"
      }
      description = "Checks IAM password policy compliance"
      severity    = "MEDIUM"
    }
  }
}

variable "resource_discovery_queries" {
  description = "Custom resource discovery queries to execute during scheduled discovery"
  type = list(object({
    name        = string
    query       = string
    description = string
    priority    = string
  }))
  
  default = [
    {
      name        = "EC2 Instances"
      query       = "resourcetype:AWS::EC2::Instance"
      description = "All EC2 instances across organization accounts"
      priority    = "HIGH"
    },
    {
      name        = "S3 Buckets"
      query       = "service:s3"
      description = "All S3 buckets across organization accounts"
      priority    = "HIGH"
    },
    {
      name        = "RDS Databases"
      query       = "service:rds"
      description = "All RDS resources across organization accounts"
      priority    = "MEDIUM"
    },
    {
      name        = "Lambda Functions"
      query       = "service:lambda"
      description = "All Lambda functions across organization accounts"
      priority    = "MEDIUM"
    },
    {
      name        = "IAM Roles"
      query       = "resourcetype:AWS::IAM::Role"
      description = "All IAM roles across organization accounts"
      priority    = "HIGH"
    }
  ]
}

#============================================================================
# COMPLIANCE AND GOVERNANCE
#============================================================================

variable "compliance_notification_threshold" {
  description = "Threshold for number of non-compliant rules before sending notifications"
  type        = number
  default     = 1
  
  validation {
    condition     = var.compliance_notification_threshold >= 0
    error_message = "Compliance notification threshold must be a non-negative integer."
  }
}

variable "high_severity_rules" {
  description = "List of Config rule names considered high severity for immediate notification"
  type        = list(string)
  default = [
    "root-access-key-check",
    "s3-bucket-public-access-prohibited",
    "encrypted-volumes"
  ]
}

#============================================================================
# RESOURCE EXPLORER CONFIGURATION
#============================================================================

variable "resource_explorer_included_properties" {
  description = "List of resource properties to include in Resource Explorer index"
  type        = list(string)
  default = [
    "lastReportedAt",
    "accountId", 
    "region",
    "resourceType",
    "service"
  ]
}

#============================================================================
# COST OPTIMIZATION
#============================================================================

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrency for Lambda function (null for unrestricted)"
  type        = number
  default     = null
  
  validation {
    condition = var.lambda_reserved_concurrency == null || (var.lambda_reserved_concurrency >= 0 && var.lambda_reserved_concurrency <= 1000)
    error_message = "Lambda reserved concurrency must be null or between 0 and 1000."
  }
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle policies for Config bucket cost optimization"
  type        = bool
  default     = true
}

variable "s3_transition_days" {
  description = "Number of days after which Config data transitions to cheaper storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.s3_transition_days >= 1
    error_message = "S3 transition days must be at least 1."
  }
}

#============================================================================
# SECURITY CONFIGURATION
#============================================================================

variable "enable_eventbridge_encryption" {
  description = "Enable encryption for EventBridge custom bus (if using custom bus)"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (optional - will use default AWS managed keys if not provided)"
  type        = string
  default     = null
  
  validation {
    condition = var.kms_key_arn == null || can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_arn))
    error_message = "KMS key ARN must be a valid KMS key ARN or null."
  }
}

#============================================================================
# TAGS CONFIGURATION
#============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9\\s._:/=+\\-@]*$", k)) && can(regex("^[a-zA-Z0-9\\s._:/=+\\-@]*$", v))
    ])
    error_message = "Tag keys and values must contain only valid characters."
  }
}