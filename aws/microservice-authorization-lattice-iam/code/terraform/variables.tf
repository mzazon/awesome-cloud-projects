# Variables for Microservice Authorization with VPC Lattice and IAM
# These variables allow customization of the deployment

variable "project_name" {
  description = "Name of the project, used as prefix for resource names"
  type        = string
  default     = "microservices-auth"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "demo"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, demo."
  }
}

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "lambda_runtime" {
  description = "Lambda runtime version for the functions"
  type        = string
  default     = "python3.12"
  
  validation {
    condition     = contains(["python3.10", "python3.11", "python3.12"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout in seconds for Lambda functions"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 3 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 3 and 900 seconds."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for VPC Lattice access logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "auth_policy_paths" {
  description = "List of paths that the product service can access"
  type        = list(string)
  default     = ["/orders*"]
  
  validation {
    condition     = length(var.auth_policy_paths) > 0
    error_message = "At least one authorized path must be specified."
  }
}

variable "auth_policy_methods" {
  description = "List of HTTP methods that the product service can use"
  type        = list(string)
  default     = ["GET", "POST"]
  
  validation {
    condition = alltrue([
      for method in var.auth_policy_methods : contains(["GET", "POST", "PUT", "DELETE", "PATCH"], method)
    ])
    error_message = "HTTP methods must be valid HTTP verbs."
  }
}

variable "cloudwatch_alarm_threshold" {
  description = "Threshold for CloudWatch alarm on 4XX errors"
  type        = number
  default     = 5
  
  validation {
    condition     = var.cloudwatch_alarm_threshold > 0
    error_message = "CloudWatch alarm threshold must be greater than 0."
  }
}

variable "cloudwatch_alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarm"
  type        = number
  default     = 2
  
  validation {
    condition     = var.cloudwatch_alarm_evaluation_periods >= 1
    error_message = "Evaluation periods must be at least 1."
  }
}

variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
  
  validation {
    condition     = var.random_suffix_length >= 4 && var.random_suffix_length <= 10
    error_message = "Random suffix length must be between 4 and 10."
  }
}