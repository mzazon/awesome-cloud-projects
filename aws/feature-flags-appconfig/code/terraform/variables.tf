# Input Variables for AWS AppConfig Feature Flags Infrastructure
# This file defines all configurable parameters for the feature flags solution

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1' (two letters, dash, region name, dash, number)."
  }
}

variable "environment" {
  description = "Environment name for resource naming and tagging"
  type        = string
  default     = "production"
  
  validation {
    condition = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "app_name" {
  description = "Name of the AppConfig application"
  type        = string
  default     = "feature-demo-app"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-_]{1,62}$", var.app_name))
    error_message = "App name must start with a letter and contain only alphanumeric characters, hyphens, and underscores (2-63 characters)."
  }
}

variable "configuration_profile_name" {
  description = "Name of the AppConfig configuration profile"
  type        = string
  default     = "feature-flags"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-_]{1,62}$", var.configuration_profile_name))
    error_message = "Configuration profile name must start with a letter and contain only alphanumeric characters, hyphens, and underscores (2-63 characters)."
  }
}

variable "deployment_strategy_name" {
  description = "Name of the AppConfig deployment strategy"
  type        = string
  default     = "gradual-rollout"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-_]{1,62}$", var.deployment_strategy_name))
    error_message = "Deployment strategy name must start with a letter and contain only alphanumeric characters, hyphens, and underscores (2-63 characters)."
  }
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for feature flag demonstration"
  type        = string
  default     = "feature-flag-demo"
  
  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9-_]{1,62}$", var.lambda_function_name))
    error_message = "Lambda function name must start with a letter and contain only alphanumeric characters, hyphens, and underscores (2-63 characters)."
  }
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be one of: python3.8, python3.9, python3.10, python3.11."
  }
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 30
  
  validation {
    condition = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 256
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "deployment_duration_minutes" {
  description = "Duration for gradual deployment in minutes"
  type        = number
  default     = 20
  
  validation {
    condition = var.deployment_duration_minutes >= 1 && var.deployment_duration_minutes <= 1440
    error_message = "Deployment duration must be between 1 and 1440 minutes (24 hours)."
  }
}

variable "final_bake_time_minutes" {
  description = "Final bake time after deployment completion in minutes"
  type        = number
  default     = 10
  
  validation {
    condition = var.final_bake_time_minutes >= 0 && var.final_bake_time_minutes <= 1440
    error_message = "Final bake time must be between 0 and 1440 minutes (24 hours)."
  }
}

variable "growth_factor" {
  description = "Percentage growth factor for gradual deployment"
  type        = number
  default     = 25
  
  validation {
    condition = var.growth_factor >= 1 && var.growth_factor <= 100
    error_message = "Growth factor must be between 1 and 100 percent."
  }
}

variable "cloudwatch_alarm_threshold" {
  description = "CloudWatch alarm threshold for Lambda function errors"
  type        = number
  default     = 5
  
  validation {
    condition = var.cloudwatch_alarm_threshold >= 1 && var.cloudwatch_alarm_threshold <= 100
    error_message = "CloudWatch alarm threshold must be between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarm"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 24
    error_message = "Alarm evaluation periods must be between 1 and 24."
  }
}

variable "initial_feature_flags" {
  description = "Initial feature flag configuration"
  type = object({
    new_checkout_flow = object({
      enabled             = bool
      rollout_percentage  = number
      target_audience     = string
    })
    enhanced_search = object({
      enabled          = bool
      search_algorithm = string
      cache_ttl        = number
    })
    premium_features = object({
      enabled      = bool
      feature_list = string
    })
  })
  default = {
    new_checkout_flow = {
      enabled             = false
      rollout_percentage  = 0
      target_audience     = "beta-users"
    }
    enhanced_search = {
      enabled          = true
      search_algorithm = "elasticsearch"
      cache_ttl        = 300
    }
    premium_features = {
      enabled      = false
      feature_list = "advanced-analytics,priority-support"
    }
  }
}

variable "enable_auto_deployment" {
  description = "Whether to automatically deploy the initial feature flag configuration"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}