# Core configuration variables
variable "aws_region" {
  description = "AWS region for the management account resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name for tagging and naming"
  type        = string
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "stacksets-governance"
}

# Organization configuration
variable "organization_id" {
  description = "AWS Organizations ID (leave empty to auto-discover)"
  type        = string
  default     = ""
}

variable "target_accounts" {
  description = "List of target AWS account IDs for StackSet deployment"
  type        = list(string)
  default     = []
}

variable "target_organizational_units" {
  description = "List of organizational unit IDs for StackSet deployment"
  type        = list(string)
  default     = []
}

variable "target_regions" {
  description = "List of target AWS regions for multi-region deployment"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
}

# StackSet configuration
variable "stackset_name_prefix" {
  description = "Prefix for StackSet names"
  type        = string
  default     = "org-governance"
}

variable "enable_auto_deployment" {
  description = "Enable automatic deployment to new accounts in organizational units"
  type        = bool
  default     = true
}

variable "retain_stacks_on_account_removal" {
  description = "Retain stacks when accounts are removed from organizational units"
  type        = bool
  default     = false
}

# Governance policy configuration
variable "compliance_level" {
  description = "Compliance level for governance policies"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["basic", "standard", "strict"], var.compliance_level)
    error_message = "Compliance level must be one of: basic, standard, strict."
  }
}

variable "password_policy" {
  description = "IAM password policy configuration"
  type = object({
    minimum_password_length        = number
    require_uppercase_characters   = bool
    require_lowercase_characters   = bool
    require_numbers               = bool
    require_symbols               = bool
    max_password_age              = number
    password_reuse_prevention     = number
    hard_expiry                   = bool
    allow_users_to_change_password = bool
  })
  default = {
    minimum_password_length        = 12
    require_uppercase_characters   = true
    require_lowercase_characters   = true
    require_numbers               = true
    require_symbols               = true
    max_password_age              = 90
    password_reuse_prevention     = 12
    hard_expiry                   = false
    allow_users_to_change_password = true
  }
}

# CloudTrail configuration
variable "cloudtrail_config" {
  description = "CloudTrail configuration for audit logging"
  type = object({
    enable_log_file_validation     = bool
    include_global_service_events  = bool
    is_multi_region_trail         = bool
    enable_logging                = bool
    event_selector_read_write_type = string
    s3_key_prefix                 = string
  })
  default = {
    enable_log_file_validation     = true
    include_global_service_events  = true
    is_multi_region_trail         = true
    enable_logging                = true
    event_selector_read_write_type = "All"
    s3_key_prefix                 = "cloudtrail-logs"
  }
}

# S3 configuration
variable "s3_bucket_configuration" {
  description = "S3 bucket configuration for templates and logs"
  type = object({
    versioning_enabled     = bool
    encryption_algorithm   = string
    lifecycle_enabled      = bool
    log_expiration_days    = number
    noncurrent_version_expiration_days = number
    transition_to_ia_days  = number
    transition_to_glacier_days = number
  })
  default = {
    versioning_enabled     = true
    encryption_algorithm   = "AES256"
    lifecycle_enabled      = true
    log_expiration_days    = 2555  # 7 years
    noncurrent_version_expiration_days = 365
    transition_to_ia_days  = 30
    transition_to_glacier_days = 365
  }
}

# GuardDuty configuration
variable "guardduty_config" {
  description = "GuardDuty configuration for threat detection"
  type = object({
    enable                           = bool
    finding_publishing_frequency     = string
    datasources_s3_logs_enable      = bool
    datasources_kubernetes_enable   = bool
    datasources_malware_protection_enable = bool
  })
  default = {
    enable                           = true
    finding_publishing_frequency     = "FIFTEEN_MINUTES"
    datasources_s3_logs_enable      = true
    datasources_kubernetes_enable   = true
    datasources_malware_protection_enable = true
  }
}

# Config configuration
variable "config_configuration" {
  description = "AWS Config configuration for compliance monitoring"
  type = object({
    enable_all_supported                 = bool
    include_global_resource_types        = bool
    delivery_frequency                   = string
    snapshot_delivery_properties_enabled = bool
  })
  default = {
    enable_all_supported                 = true
    include_global_resource_types        = true
    delivery_frequency                   = "TwentyFour_Hours"
    snapshot_delivery_properties_enabled = true
  }
}

# Operational preferences
variable "operation_preferences" {
  description = "StackSet operation preferences"
  type = object({
    region_concurrency_type      = string
    max_concurrent_percentage    = number
    failure_tolerance_percentage = number
  })
  default = {
    region_concurrency_type      = "PARALLEL"
    max_concurrent_percentage    = 50
    failure_tolerance_percentage = 10
  }
}

# Monitoring and alerting
variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alerting"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for StackSet operation alerts"
  type        = string
  default     = ""
}

variable "drift_detection_schedule" {
  description = "CloudWatch Event schedule for drift detection (cron format)"
  type        = string
  default     = "cron(0 2 * * ? *)"  # Daily at 2 AM
}

# Lambda configuration
variable "lambda_config" {
  description = "Lambda function configuration for drift detection"
  type = object({
    runtime       = string
    timeout       = number
    memory_size   = number
    log_retention = number
  })
  default = {
    runtime       = "python3.9"
    timeout       = 900
    memory_size   = 256
    log_retention = 14
  }
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}