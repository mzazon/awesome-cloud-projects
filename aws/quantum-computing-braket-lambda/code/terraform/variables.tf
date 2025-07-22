# Variables for Quantum Computing Pipeline Infrastructure
# This file defines all configurable parameters for the quantum computing pipeline

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

variable "project_name" {
  description = "Name of the quantum computing project"
  type        = string
  default     = "quantum-pipeline"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "quantum_algorithm_timeout" {
  description = "Timeout for quantum algorithm execution in seconds"
  type        = number
  default     = 900
  
  validation {
    condition     = var.quantum_algorithm_timeout >= 60 && var.quantum_algorithm_timeout <= 3600
    error_message = "Quantum algorithm timeout must be between 60 and 3600 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "enable_braket_qpu" {
  description = "Enable Amazon Braket QPU access (requires approval)"
  type        = bool
  default     = false
}

variable "braket_device_type" {
  description = "Default Braket device type (simulator or qpu)"
  type        = string
  default     = "simulator"
  
  validation {
    condition     = contains(["simulator", "qpu"], var.braket_device_type)
    error_message = "Braket device type must be either 'simulator' or 'qpu'."
  }
}

variable "quantum_problem_types" {
  description = "Supported quantum problem types"
  type        = list(string)
  default     = ["optimization", "chemistry"]
  
  validation {
    condition     = length(var.quantum_problem_types) > 0
    error_message = "At least one quantum problem type must be specified."
  }
}

variable "optimization_iterations" {
  description = "Default number of optimization iterations"
  type        = number
  default     = 100
  
  validation {
    condition     = var.optimization_iterations > 0 && var.optimization_iterations <= 1000
    error_message = "Optimization iterations must be between 1 and 1000."
  }
}

variable "learning_rate" {
  description = "Default learning rate for quantum optimization"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.learning_rate > 0 && var.learning_rate <= 1
    error_message = "Learning rate must be between 0 and 1."
  }
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_retention_days)
    error_message = "CloudWatch retention days must be a valid retention period."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and dashboards"
  type        = bool
  default     = true
}

variable "alarm_threshold_job_failures" {
  description = "Threshold for job failure alarms"
  type        = number
  default     = 3
  
  validation {
    condition     = var.alarm_threshold_job_failures > 0
    error_message = "Job failure threshold must be greater than 0."
  }
}

variable "alarm_threshold_low_efficiency" {
  description = "Threshold for low optimization efficiency alarms"
  type        = number
  default     = 0.3
  
  validation {
    condition     = var.alarm_threshold_low_efficiency > 0 && var.alarm_threshold_low_efficiency <= 1
    error_message = "Low efficiency threshold must be between 0 and 1."
  }
}

variable "s3_bucket_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "s3_bucket_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "force_destroy_buckets" {
  description = "Force destroy S3 buckets even if they contain objects"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}