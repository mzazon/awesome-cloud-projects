# Core configuration variables
variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "ml-models-sagemaker"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
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

variable "region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

# Model configuration
variable "model_name" {
  description = "Name of the SageMaker model"
  type        = string
  default     = "sklearn-iris-classifier"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.model_name))
    error_message = "Model name must contain only alphanumeric characters and hyphens."
  }
}

variable "container_image_uri" {
  description = "URI of the ECR container image for inference (optional, will be built if not provided)"
  type        = string
  default     = ""
}

variable "model_data_url" {
  description = "S3 URL of the model artifacts (optional, will be uploaded if not provided)"
  type        = string
  default     = ""
}

# Endpoint configuration
variable "endpoint_instance_type" {
  description = "EC2 instance type for the SageMaker endpoint"
  type        = string
  default     = "ml.t2.medium"
  
  validation {
    condition = can(regex("^ml\\.", var.endpoint_instance_type))
    error_message = "Instance type must be a valid SageMaker instance type (starting with 'ml.')."
  }
}

variable "endpoint_initial_instance_count" {
  description = "Initial number of instances for the endpoint"
  type        = number
  default     = 1
  
  validation {
    condition     = var.endpoint_initial_instance_count >= 1 && var.endpoint_initial_instance_count <= 10
    error_message = "Initial instance count must be between 1 and 10."
  }
}

variable "endpoint_initial_variant_weight" {
  description = "Initial weight for traffic distribution to the variant"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.endpoint_initial_variant_weight >= 0.0 && var.endpoint_initial_variant_weight <= 1.0
    error_message = "Initial variant weight must be between 0.0 and 1.0."
  }
}

# Auto-scaling configuration
variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the SageMaker endpoint"
  type        = bool
  default     = true
}

variable "auto_scaling_min_capacity" {
  description = "Minimum number of instances for auto-scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.auto_scaling_min_capacity >= 1 && var.auto_scaling_min_capacity <= 10
    error_message = "Minimum capacity must be between 1 and 10."
  }
}

variable "auto_scaling_max_capacity" {
  description = "Maximum number of instances for auto-scaling"
  type        = number
  default     = 5
  
  validation {
    condition     = var.auto_scaling_max_capacity >= 1 && var.auto_scaling_max_capacity <= 20
    error_message = "Maximum capacity must be between 1 and 20."
  }
}

variable "auto_scaling_target_value" {
  description = "Target value for the auto-scaling metric (invocations per instance)"
  type        = number
  default     = 70.0
  
  validation {
    condition     = var.auto_scaling_target_value > 0.0 && var.auto_scaling_target_value <= 1000.0
    error_message = "Target value must be between 0.0 and 1000.0."
  }
}

# ECR configuration
variable "ecr_repository_name" {
  description = "Name of the ECR repository for the inference container"
  type        = string
  default     = "sagemaker-sklearn-inference"
  
  validation {
    condition     = can(regex("^[a-z0-9-_/]+$", var.ecr_repository_name))
    error_message = "ECR repository name must contain only lowercase letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "ecr_image_scan_on_push" {
  description = "Enable vulnerability scanning on image push to ECR"
  type        = bool
  default     = true
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for ECR repository"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

# S3 configuration
variable "s3_bucket_name" {
  description = "Name of the S3 bucket for model artifacts (optional, will be generated if not provided)"
  type        = string
  default     = ""
}

variable "s3_force_destroy" {
  description = "Allow destruction of non-empty S3 bucket"
  type        = bool
  default     = false
}

# CloudWatch configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logging for the endpoint"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Monitoring and alerting
variable "enable_endpoint_monitoring" {
  description = "Enable CloudWatch monitoring and alarms for the endpoint"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Evaluation periods must be between 1 and 10."
  }
}

variable "alarm_datapoints_to_alarm" {
  description = "Number of datapoints that must be breaching to trigger alarm"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alarm_datapoints_to_alarm >= 1 && var.alarm_datapoints_to_alarm <= 10
    error_message = "Datapoints to alarm must be between 1 and 10."
  }
}

# SNS notification configuration
variable "enable_sns_notifications" {
  description = "Enable SNS notifications for endpoint alerts"
  type        = bool
  default     = false
}

variable "sns_email_endpoint" {
  description = "Email address for SNS notifications"
  type        = string
  default     = ""
  
  validation {
    condition = var.sns_email_endpoint == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "SNS email endpoint must be a valid email address or empty string."
  }
}

# Security configuration
variable "enable_vpc_config" {
  description = "Enable VPC configuration for SageMaker resources"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for SageMaker resources (required if enable_vpc_config is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for SageMaker resources (required if enable_vpc_config is true)"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of security group IDs for SageMaker resources"
  type        = list(string)
  default     = []
}

# KMS encryption
variable "enable_encryption" {
  description = "Enable KMS encryption for SageMaker resources and S3 bucket"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (optional, will create new key if not provided)"
  type        = string
  default     = ""
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}