# variables.tf
# Variables for Security Compliance Auditing with VPC Lattice and GuardDuty

# ==============================================================================
# GENERAL CONFIGURATION
# ==============================================================================

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "project_name" {
  description = "Name of the project for resource tagging"
  type        = string
  default     = "security-compliance-auditing"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# S3 BUCKET CONFIGURATION
# ==============================================================================

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name that will store compliance reports"
  type        = string
  default     = "security-audit-logs"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# GUARDDUTY CONFIGURATION
# ==============================================================================

variable "guardduty_finding_frequency" {
  description = "Frequency of GuardDuty findings publication to CloudWatch Events"
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_frequency)
    error_message = "GuardDuty finding frequency must be one of: FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

# ==============================================================================
# SNS CONFIGURATION
# ==============================================================================

variable "sns_topic_prefix" {
  description = "Prefix for the SNS topic name for security alerts"
  type        = string
  default     = "security-alerts"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.sns_topic_prefix))
    error_message = "SNS topic prefix must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "notification_email" {
  description = "Email address to receive security alerts (leave empty to skip email subscription)"
  type        = string
  default     = ""

  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# ==============================================================================
# CLOUDWATCH LOGS CONFIGURATION
# ==============================================================================

variable "log_group_name" {
  description = "Name of the CloudWatch log group for VPC Lattice access logs"
  type        = string
  default     = "/aws/vpclattice/security-audit"

  validation {
    condition     = can(regex("^/[a-zA-Z0-9-_/]+$", var.log_group_name))
    error_message = "Log group name must start with / and contain only letters, numbers, hyphens, underscores, and slashes."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 90

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "cloudwatch_kms_key_id" {
  description = "KMS key ID for CloudWatch Logs encryption (leave empty for default encryption)"
  type        = string
  default     = ""
}

# ==============================================================================
# LAMBDA FUNCTION CONFIGURATION
# ==============================================================================

variable "lambda_function_name" {
  description = "Name of the Lambda function for security log processing"
  type        = string
  default     = "security-compliance-processor"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.lambda_function_name))
    error_message = "Lambda function name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "lambda_runtime" {
  description = "Runtime environment for the Lambda function"
  type        = string
  default     = "python3.12"

  validation {
    condition     = contains(["python3.9", "python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for the Lambda function in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_log_level" {
  description = "Log level for the Lambda function"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], var.lambda_log_level)
    error_message = "Lambda log level must be one of: DEBUG, INFO, WARNING, ERROR, CRITICAL."
  }
}

# ==============================================================================
# CLOUDWATCH DASHBOARD CONFIGURATION
# ==============================================================================

variable "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for security monitoring"
  type        = string
  default     = "SecurityComplianceDashboard"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.cloudwatch_dashboard_name))
    error_message = "Dashboard name must contain only letters, numbers, hyphens, and underscores."
  }
}

# ==============================================================================
# VPC LATTICE CONFIGURATION
# ==============================================================================

variable "create_demo_vpc_lattice" {
  description = "Whether to create a demo VPC Lattice service network for testing"
  type        = bool
  default     = true
}

variable "vpc_lattice_service_network_prefix" {
  description = "Prefix for the VPC Lattice service network name"
  type        = string
  default     = "security-demo-network"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.vpc_lattice_service_network_prefix))
    error_message = "VPC Lattice service network prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# MONITORING AND ALERTING CONFIGURATION
# ==============================================================================

variable "error_rate_threshold" {
  description = "Threshold for error rate CloudWatch alarm (number of errors per period)"
  type        = number
  default     = 10

  validation {
    condition     = var.error_rate_threshold >= 1 && var.error_rate_threshold <= 1000
    error_message = "Error rate threshold must be between 1 and 1000."
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring features including additional CloudWatch alarms"
  type        = bool
  default     = true
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "enable_guardduty_malware_protection" {
  description = "Enable GuardDuty malware protection features"
  type        = bool
  default     = true
}

variable "enable_guardduty_kubernetes_protection" {
  description = "Enable GuardDuty Kubernetes protection features"
  type        = bool
  default     = true
}

variable "enable_guardduty_s3_protection" {
  description = "Enable GuardDuty S3 protection features"
  type        = bool
  default     = true
}

# ==============================================================================
# COST OPTIMIZATION CONFIGURATION
# ==============================================================================

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle policies for cost optimization"
  type        = bool
  default     = true
}

variable "s3_intelligent_tiering_enabled" {
  description = "Enable S3 Intelligent Tiering for automatic cost optimization"
  type        = bool
  default     = false
}

# ==============================================================================
# COMPLIANCE CONFIGURATION
# ==============================================================================

variable "compliance_retention_years" {
  description = "Number of years to retain compliance data for regulatory requirements"
  type        = number
  default     = 7

  validation {
    condition     = var.compliance_retention_years >= 1 && var.compliance_retention_years <= 10
    error_message = "Compliance retention years must be between 1 and 10."
  }
}

variable "enable_encryption_in_transit" {
  description = "Enable encryption in transit for all communications"
  type        = bool
  default     = true
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for all storage"
  type        = bool
  default     = true
}

# ==============================================================================
# ADVANCED CONFIGURATION
# ==============================================================================

variable "custom_lambda_environment_variables" {
  description = "Additional custom environment variables for the Lambda function"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.custom_lambda_environment_variables : can(regex("^[a-zA-Z_][a-zA-Z0-9_]*$", k))
    ])
    error_message = "Environment variable names must start with a letter or underscore and contain only letters, numbers, and underscores."
  }
}

variable "additional_lambda_layers" {
  description = "Additional Lambda layers to attach to the security processor function"
  type        = list(string)
  default     = []
}

variable "vpc_config" {
  description = "VPC configuration for Lambda function (leave empty for no VPC)"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

# ==============================================================================
# FEATURE FLAGS
# ==============================================================================

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for compliance reports (requires additional configuration)"
  type        = bool
  default     = false
}

variable "enable_automated_remediation" {
  description = "Enable automated remediation responses to security threats"
  type        = bool
  default     = false
}

variable "enable_machine_learning_analysis" {
  description = "Enable machine learning-based analysis for advanced threat detection"
  type        = bool
  default     = false
}

# ==============================================================================
# TAGGING CONFIGURATION
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", k)) && can(regex("^[a-zA-Z0-9+\\-=._:/@\\s]*$", v))
    ])
    error_message = "Tag keys and values must contain only valid characters as per AWS tagging requirements."
  }
}