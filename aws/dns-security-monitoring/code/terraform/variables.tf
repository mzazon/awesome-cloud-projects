# =============================================================================
# Variables for DNS Security Monitoring Infrastructure
# =============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
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

variable "vpc_id" {
  description = "VPC ID where DNS firewall will be associated. If not provided, uses default VPC"
  type        = string
  default     = ""
}

variable "malicious_domains" {
  description = "List of malicious domains to block in DNS firewall"
  type        = list(string)
  default = [
    "malware.example",
    "suspicious.tk",
    "phishing.com",
    "badactor.ru",
    "cryptominer.xyz",
    "botnet.info"
  ]

  validation {
    condition     = length(var.malicious_domains) > 0
    error_message = "At least one malicious domain must be specified."
  }
}

variable "email_address" {
  description = "Email address for DNS security alert notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.email_address))
    error_message = "Please provide a valid email address."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain DNS query logs in CloudWatch"
  type        = number
  default     = 30

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch log retention values."
  }
}

variable "blocked_query_threshold" {
  description = "Threshold for high block rate alarm (number of blocked queries in 5 minutes)"
  type        = number
  default     = 50

  validation {
    condition     = var.blocked_query_threshold > 0
    error_message = "Blocked query threshold must be greater than 0."
  }
}

variable "unusual_volume_threshold" {
  description = "Threshold for unusual DNS volume alarm (number of queries in 15 minutes)"
  type        = number
  default     = 1000

  validation {
    condition     = var.unusual_volume_threshold > 0
    error_message = "Unusual volume threshold must be greater than 0."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "resource_name_suffix" {
  description = "Random suffix for resource names. If not provided, one will be generated"
  type        = string
  default     = ""
}