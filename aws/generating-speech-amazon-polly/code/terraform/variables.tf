# ========================================
# Variables for Amazon Polly Text-to-Speech Infrastructure
# ========================================
# This file defines all configurable variables for the Polly TTS infrastructure,
# including AWS region, S3 bucket configuration, IAM settings, and optional features.

# ========================================
# AWS Configuration Variables
# ========================================

variable "aws_region" {
  description = "AWS region for deploying Polly text-to-speech infrastructure"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid AWS region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production", "testing"], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing."
  }
}

# ========================================
# S3 Bucket Configuration Variables
# ========================================

variable "bucket_name_prefix" {
  description = "Prefix for S3 bucket name (random suffix will be added for uniqueness)"
  type        = string
  default     = "polly-audio-output"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning for audio files"
  type        = bool
  default     = true
}

variable "audio_file_retention_days" {
  description = "Number of days to retain audio files in S3 before deletion"
  type        = number
  default     = 365
  
  validation {
    condition = var.audio_file_retention_days >= 1 && var.audio_file_retention_days <= 3650
    error_message = "Audio file retention must be between 1 and 3650 days."
  }
}

# ========================================
# IAM and Security Configuration Variables
# ========================================

variable "create_instance_profile" {
  description = "Create IAM instance profile for EC2 instances"
  type        = bool
  default     = true
}

variable "allowed_principals" {
  description = "List of AWS principals allowed to assume the Polly application role"
  type        = list(string)
  default     = []
}

# ========================================
# Monitoring and Logging Variables
# ========================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention period."
  }
}

variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alarms for Polly operations"
  type        = bool
  default     = true
}

variable "synthesis_failure_threshold" {
  description = "Number of synthesis failures before triggering alarm"
  type        = number
  default     = 5
  
  validation {
    condition = var.synthesis_failure_threshold >= 1 && var.synthesis_failure_threshold <= 100
    error_message = "Synthesis failure threshold must be between 1 and 100."
  }
}

# ========================================
# Polly Service Configuration Variables
# ========================================

variable "default_voice_id" {
  description = "Default voice ID for Amazon Polly synthesis"
  type        = string
  default     = "Joanna"
  
  validation {
    condition = contains([
      "Aditi", "Amy", "Astrid", "Bianca", "Brian", "Camila", "Carla", "Carmen", 
      "Celine", "Chant", "Conchita", "Cristiano", "Dora", "Emma", "Enrique", 
      "Ewa", "Filiz", "Geraint", "Giorgio", "Gwyneth", "Hans", "Ines", "Ivy", 
      "Jacek", "Jan", "Joanna", "Joey", "Justin", "Karl", "Kendra", "Kimberly", 
      "Lea", "Liv", "Lotte", "Lucia", "Lupe", "Mads", "Maja", "Marlene", 
      "Mathieu", "Matthew", "Maxim", "Mia", "Miguel", "Mizuki", "Naja", 
      "Nicole", "Penelope", "Raveena", "Ricardo", "Ruben", "Russell", "Salli", 
      "Seoyeon", "Takumi", "Tatyana", "Vicki", "Vitoria", "Zeina", "Zhiyu"
    ], var.default_voice_id)
    error_message = "Voice ID must be a valid Amazon Polly voice."
  }
}

variable "default_engine" {
  description = "Default synthesis engine for Amazon Polly"
  type        = string
  default     = "neural"
  
  validation {
    condition = contains(["standard", "neural"], var.default_engine)
    error_message = "Engine must be either 'standard' or 'neural'."
  }
}

variable "default_output_format" {
  description = "Default output format for synthesized audio"
  type        = string
  default     = "mp3"
  
  validation {
    condition = contains(["mp3", "ogg_vorbis", "pcm"], var.default_output_format)
    error_message = "Output format must be one of: mp3, ogg_vorbis, pcm."
  }
}

variable "supported_languages" {
  description = "List of supported languages for text-to-speech synthesis"
  type        = list(string)
  default     = ["en-US", "en-GB", "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "ja-JP"]
  
  validation {
    condition = length(var.supported_languages) > 0
    error_message = "At least one supported language must be specified."
  }
}

# ========================================
# Lambda Function Configuration Variables
# ========================================

variable "create_lambda_function" {
  description = "Create Lambda function for Polly text processing"
  type        = bool
  default     = false
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda function in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda function in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11", "nodejs16.x", "nodejs18.x"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported AWS Lambda runtime."
  }
}

# ========================================
# VPC Configuration Variables (Optional)
# ========================================

variable "vpc_id" {
  description = "VPC ID for creating VPC endpoints (optional)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for VPC endpoints"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC for security group rules"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for private access to AWS services"
  type        = bool
  default     = false
}

# ========================================
# Cost Optimization Variables
# ========================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features like S3 lifecycle policies"
  type        = bool
  default     = true
}

variable "standard_to_ia_days" {
  description = "Days after which to transition objects to Standard-IA"
  type        = number
  default     = 30
  
  validation {
    condition = var.standard_to_ia_days >= 30
    error_message = "Standard to IA transition must be at least 30 days."
  }
}

variable "ia_to_glacier_days" {
  description = "Days after which to transition objects to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition = var.ia_to_glacier_days >= 90
    error_message = "IA to Glacier transition must be at least 90 days."
  }
}

# ========================================
# Notification Configuration Variables
# ========================================

variable "notification_email" {
  description = "Email address for SNS notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty."
  }
}

variable "enable_sns_notifications" {
  description = "Enable SNS notifications for synthesis task completion"
  type        = bool
  default     = true
}

# ========================================
# Application Configuration Variables
# ========================================

variable "application_name" {
  description = "Name of the text-to-speech application"
  type        = string
  default     = "polly-tts-app"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.application_name))
    error_message = "Application name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "max_synthesis_tasks" {
  description = "Maximum number of concurrent synthesis tasks"
  type        = number
  default     = 10
  
  validation {
    condition = var.max_synthesis_tasks >= 1 && var.max_synthesis_tasks <= 100
    error_message = "Maximum synthesis tasks must be between 1 and 100."
  }
}

variable "enable_batch_synthesis" {
  description = "Enable batch synthesis functionality"
  type        = bool
  default     = true
}

variable "enable_ssml_support" {
  description = "Enable SSML (Speech Synthesis Markup Language) support"
  type        = bool
  default     = true
}

variable "enable_lexicon_support" {
  description = "Enable pronunciation lexicon support"
  type        = bool
  default     = true
}

# ========================================
# Security Configuration Variables
# ========================================

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for S3 bucket"
  type        = bool
  default     = true
}

variable "enable_encryption_in_transit" {
  description = "Enable encryption in transit for all API calls"
  type        = bool
  default     = true
}

variable "enable_access_logging" {
  description = "Enable access logging for S3 bucket"
  type        = bool
  default     = true
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges allowed to access the application"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ========================================
# Performance Configuration Variables
# ========================================

variable "enable_performance_monitoring" {
  description = "Enable performance monitoring with CloudWatch metrics"
  type        = bool
  default     = true
}

variable "synthesis_timeout_seconds" {
  description = "Timeout for synthesis operations in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.synthesis_timeout_seconds >= 30 && var.synthesis_timeout_seconds <= 3600
    error_message = "Synthesis timeout must be between 30 and 3600 seconds."
  }
}

variable "enable_caching" {
  description = "Enable caching for synthesized audio files"
  type        = bool
  default     = true
}

# ========================================
# Backup and Disaster Recovery Variables
# ========================================

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for S3 bucket"
  type        = bool
  default     = false
}

variable "backup_region" {
  description = "AWS region for backup and disaster recovery"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.backup_region))
    error_message = "Backup region must be a valid AWS region identifier."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for supported services"
  type        = bool
  default     = false
}

# ========================================
# Compliance and Governance Variables
# ========================================

variable "compliance_framework" {
  description = "Compliance framework to adhere to (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.compliance_framework == "" || contains(["HIPAA", "PCI-DSS", "SOC2", "GDPR", "CCPA"], var.compliance_framework)
    error_message = "Compliance framework must be one of: HIPAA, PCI-DSS, SOC2, GDPR, CCPA, or empty."
  }
}

variable "data_residency_region" {
  description = "AWS region for data residency requirements"
  type        = string
  default     = ""
}

variable "enable_audit_logging" {
  description = "Enable audit logging for compliance requirements"
  type        = bool
  default     = false
}

# ========================================
# Resource Tagging Variables
# ========================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "cost_center" {
  description = "Cost center for resource billing"
  type        = string
  default     = ""
}

variable "project_owner" {
  description = "Owner of the project for resource management"
  type        = string
  default     = ""
}

variable "business_unit" {
  description = "Business unit responsible for the resources"
  type        = string
  default     = ""
}