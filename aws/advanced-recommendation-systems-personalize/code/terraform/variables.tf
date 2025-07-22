# =============================================================================
# Variables for Amazon Personalize Recommendation System
# =============================================================================

variable "aws_region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "recommendation-system"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "RecommendationSystem"
    Environment = "dev"
    Owner       = "DataScience"
    CostCenter  = "ML-Operations"
  }
}

# =============================================================================
# S3 Configuration
# =============================================================================

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket naming (will be combined with random suffix)"
  type        = string
  default     = "personalize-comprehensive"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.s3_bucket_prefix))
    error_message = "S3 bucket prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 bucket"
  type        = bool
  default     = true
}

variable "s3_lifecycle_days" {
  description = "Number of days before transitioning objects to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition = var.s3_lifecycle_days >= 30
    error_message = "S3 lifecycle transition must be at least 30 days."
  }
}

# =============================================================================
# Amazon Personalize Configuration
# =============================================================================

variable "dataset_group_name" {
  description = "Name for the Personalize dataset group"
  type        = string
  default     = "ecommerce-recommendation"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.dataset_group_name))
    error_message = "Dataset group name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "solution_names" {
  description = "Names for different Personalize solutions"
  type = object({
    user_personalization = string
    similar_items        = string
    trending_now         = string
    popularity           = string
  })
  default = {
    user_personalization = "user-personalization"
    similar_items        = "similar-items"
    trending_now         = "trending-now"
    popularity           = "popularity-count"
  }
}

variable "campaign_min_tps" {
  description = "Minimum TPS configuration for Personalize campaigns"
  type = object({
    user_personalization = number
    similar_items        = number
    trending_now         = number
    popularity           = number
  })
  default = {
    user_personalization = 2
    similar_items        = 1
    trending_now         = 1
    popularity           = 1
  }
  
  validation {
    condition = alltrue([
      var.campaign_min_tps.user_personalization >= 1,
      var.campaign_min_tps.similar_items >= 1,
      var.campaign_min_tps.trending_now >= 1,
      var.campaign_min_tps.popularity >= 1
    ])
    error_message = "All campaign TPS values must be at least 1."
  }
}

variable "user_personalization_config" {
  description = "Configuration for User-Personalization solution"
  type = object({
    hidden_dimension = string
    bptt            = string
    recency_mask    = string
    max_hist_len    = string
  })
  default = {
    hidden_dimension = "100"
    bptt            = "32"
    recency_mask    = "true"
    max_hist_len    = "100"
  }
}

# =============================================================================
# Lambda Configuration
# =============================================================================

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 MB and 10,240 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

# =============================================================================
# EventBridge Configuration
# =============================================================================

variable "retraining_schedule" {
  description = "Schedule expression for automated model retraining"
  type        = string
  default     = "rate(7 days)"
  
  validation {
    condition = can(regex("^(rate|cron)\\(.+\\)$", var.retraining_schedule))
    error_message = "Retraining schedule must be a valid EventBridge schedule expression."
  }
}

variable "enable_auto_retraining" {
  description = "Enable automated model retraining"
  type        = bool
  default     = true
}

# =============================================================================
# CloudWatch Configuration
# =============================================================================

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be a valid retention period."
  }
}

variable "enable_cloudwatch_insights" {
  description = "Enable CloudWatch Insights for Lambda logs"
  type        = bool
  default     = true
}

# =============================================================================
# Sample Data Configuration
# =============================================================================

variable "generate_sample_data" {
  description = "Generate sample datasets for testing"
  type        = bool
  default     = true
}

variable "sample_data_config" {
  description = "Configuration for sample data generation"
  type = object({
    num_users        = number
    num_items        = number
    num_interactions = number
    categories       = list(string)
  })
  default = {
    num_users        = 500
    num_items        = 1000
    num_interactions = 25000
    categories       = ["electronics", "clothing", "books", "sports", "home", "beauty"]
  }
  
  validation {
    condition = var.sample_data_config.num_users >= 25
    error_message = "Number of users must be at least 25 for Personalize training."
  }
  
  validation {
    condition = var.sample_data_config.num_items >= 100
    error_message = "Number of items must be at least 100 for Personalize training."
  }
  
  validation {
    condition = var.sample_data_config.num_interactions >= 1000
    error_message = "Number of interactions must be at least 1000 for Personalize training."
  }
}

# =============================================================================
# API Gateway Configuration
# =============================================================================

variable "enable_api_gateway" {
  description = "Create API Gateway for recommendation endpoints"
  type        = bool
  default     = false
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-_]+$", var.api_gateway_stage_name))
    error_message = "API Gateway stage name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

# =============================================================================
# Security Configuration
# =============================================================================

variable "enable_kms_encryption" {
  description = "Enable KMS encryption for S3 bucket"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access API Gateway (if enabled)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "All entries must be valid CIDR blocks."
  }
}

variable "enable_vpc_endpoints" {
  description = "Create VPC endpoints for enhanced security"
  type        = bool
  default     = false
}

# =============================================================================
# Cost Optimization
# =============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "auto_scale_campaigns" {
  description = "Enable auto-scaling for Personalize campaigns"
  type        = bool
  default     = false
}