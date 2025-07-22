# =========================================================================
# AWS EC2 Instances Securely with Systems Manager - Variable Definitions
# =========================================================================
# This file defines all input variables for the Terraform configuration,
# providing customization options while maintaining secure defaults.

# =========================================================================
# BASIC CONFIGURATION VARIABLES
# =========================================================================

variable "project_name" {
  description = "Name of the project - used as prefix for all resource names"
  type        = string
  default     = "secure-ssm-demo"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name)) && length(var.project_name) <= 32
    error_message = "Project name must start with a letter, contain only alphanumeric characters and hyphens, and be 32 characters or less."
  }
}

variable "environment" {
  description = "Environment designation (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# =========================================================================
# EC2 INSTANCE CONFIGURATION
# =========================================================================

variable "instance_type" {
  description = "EC2 instance type for the secure server"
  type        = string
  default     = "t2.micro"
  
  validation {
    condition = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.instance_type))
    error_message = "Instance type must be in the format 'family.size' (e.g., t2.micro, t3.small)."
  }
}

variable "operating_system" {
  description = "Operating system for the EC2 instance"
  type        = string
  default     = "amazon-linux"
  
  validation {
    condition     = contains(["amazon-linux", "ubuntu"], var.operating_system)
    error_message = "Operating system must be either 'amazon-linux' or 'ubuntu'."
  }
}

variable "assign_public_ip" {
  description = "Whether to assign a public IP address to the instance"
  type        = bool
  default     = true
  
  # Note: Public IP can be useful for testing but not required for Systems Manager
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for the EC2 instance"
  type        = bool
  default     = true
}

# =========================================================================
# SECURITY AND ACCESS CONFIGURATION
# =========================================================================

variable "allowed_principals" {
  description = "List of IAM principal ARNs allowed to access the instance via Session Manager"
  type        = list(string)
  default     = []
  
  # Example: ["arn:aws:iam::123456789012:user/admin", "arn:aws:iam::123456789012:role/DevOpsRole"]
}

variable "kms_key_id" {
  description = "KMS key ID for encrypting session logs and S3 objects (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.kms_key_id == "" || can(regex("^(arn:aws:kms:|alias/|[a-f0-9-]{36}).*", var.kms_key_id))
    error_message = "KMS key ID must be empty, a valid KMS key ARN, alias, or key ID."
  }
}

# =========================================================================
# LOGGING AND MONITORING CONFIGURATION
# =========================================================================

variable "enable_session_logging" {
  description = "Enable CloudWatch logging for Systems Manager sessions"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be one of the supported CloudWatch values."
  }
}

variable "enable_cloudwatch_agent" {
  description = "Enable CloudWatch Agent for enhanced monitoring"
  type        = bool
  default     = false
  
  # Note: This adds the CloudWatchAgentServerPolicy to the IAM role
}

variable "cloudwatch_encryption_enabled" {
  description = "Enable encryption for CloudWatch logs"
  type        = bool
  default     = false
}

# =========================================================================
# S3 CONFIGURATION FOR SESSION LOGS
# =========================================================================

variable "s3_bucket_name" {
  description = "S3 bucket name for storing session logs (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.s3_bucket_name == "" || can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.s3_bucket_name))
    error_message = "S3 bucket name must be empty or follow S3 naming conventions (lowercase, alphanumeric, hyphens)."
  }
}

variable "s3_key_prefix" {
  description = "S3 key prefix for session logs"
  type        = string
  default     = "session-logs/"
}

variable "s3_encryption_enabled" {
  description = "Enable S3 server-side encryption for session logs"
  type        = bool
  default     = true
}

# =========================================================================
# SESSION MANAGER ADVANCED CONFIGURATION
# =========================================================================

variable "run_as_enabled" {
  description = "Enable Run As support for Session Manager"
  type        = bool
  default     = false
  
  # Note: This allows starting sessions as different user accounts
}

variable "run_as_default_user" {
  description = "Default user for Run As sessions"
  type        = string
  default     = ""
  
  # Example: "ssm-user" for a dedicated session user
}

variable "idle_session_timeout" {
  description = "Session timeout for idle sessions (in minutes)"
  type        = number
  default     = 20
  
  validation {
    condition     = var.idle_session_timeout >= 1 && var.idle_session_timeout <= 60
    error_message = "Idle session timeout must be between 1 and 60 minutes."
  }
}

variable "max_session_duration" {
  description = "Maximum session duration (in minutes)"
  type        = number
  default     = 120
  
  validation {
    condition     = var.max_session_duration >= 1 && var.max_session_duration <= 1440
    error_message = "Maximum session duration must be between 1 and 1440 minutes (24 hours)."
  }
}

# =========================================================================
# NETWORK CONFIGURATION
# =========================================================================

variable "vpc_id" {
  description = "VPC ID to deploy resources (leave empty to use default VPC)"
  type        = string
  default     = ""
  
  validation {
    condition = var.vpc_id == "" || can(regex("^vpc-[a-f0-9]{8,17}$", var.vpc_id))
    error_message = "VPC ID must be empty or a valid VPC identifier (vpc-xxxxxxxx)."
  }
}

variable "subnet_id" {
  description = "Subnet ID for EC2 instance (leave empty to use first subnet in VPC)"
  type        = string
  default     = ""
  
  validation {
    condition = var.subnet_id == "" || can(regex("^subnet-[a-f0-9]{8,17}$", var.subnet_id))
    error_message = "Subnet ID must be empty or a valid subnet identifier (subnet-xxxxxxxx)."
  }
}

variable "availability_zone" {
  description = "Availability zone for the EC2 instance (leave empty for automatic selection)"
  type        = string
  default     = ""
}

# =========================================================================
# ADDITIONAL RESOURCE TAGS
# =========================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  # Example:
  # {
  #   "Owner" = "DevOps Team"
  #   "CostCenter" = "Engineering"
  #   "Backup" = "Daily"
  # }
}

variable "instance_additional_tags" {
  description = "Additional tags specific to the EC2 instance"
  type        = map(string)
  default     = {}
  
  # Example:
  # {
  #   "Patch Group" = "Production"
  #   "Backup Schedule" = "Daily"
  #   "Monitoring Level" = "Enhanced"
  # }
}

# =========================================================================
# ADVANCED CONFIGURATION OPTIONS
# =========================================================================

variable "enable_session_document" {
  description = "Create custom Session Manager document with advanced settings"
  type        = bool
  default     = true
}

variable "user_data_template_vars" {
  description = "Additional variables to pass to the user data template"
  type        = map(string)
  default     = {}
  
  # Example:
  # {
  #   "custom_software" = "docker"
  #   "config_repo" = "https://github.com/company/server-config"
  # }
}

variable "create_instance_backup" {
  description = "Enable automatic backup of the EC2 instance using AWS Backup"
  type        = bool
  default     = false
  
  # Note: This would require additional AWS Backup resources
}

# =========================================================================
# COST OPTIMIZATION VARIABLES
# =========================================================================

variable "enable_spot_instances" {
  description = "Use Spot instances for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

variable "spot_instance_interruption_behavior" {
  description = "Behavior when Spot instance is interrupted"
  type        = string
  default     = "terminate"
  
  validation {
    condition     = contains(["hibernate", "stop", "terminate"], var.spot_instance_interruption_behavior)
    error_message = "Spot interruption behavior must be one of: hibernate, stop, terminate."
  }
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances (leave empty for on-demand price)"
  type        = string
  default     = ""
}

# =========================================================================
# TESTING AND DEVELOPMENT OPTIONS
# =========================================================================

variable "install_test_applications" {
  description = "Install additional applications for testing (nginx web server)"
  type        = bool
  default     = true
}

variable "enable_performance_testing" {
  description = "Install performance testing tools (stress, iperf3)"
  type        = bool
  default     = false
}

variable "enable_debugging_tools" {
  description = "Install debugging and troubleshooting tools"
  type        = bool
  default     = false
}