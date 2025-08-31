# Variables for gRPC microservices with VPC Lattice and CloudWatch

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"

  validation {
    condition = contains(["development", "staging", "production", "testing"], var.environment)
    error_message = "Environment must be one of: development, staging, production, testing."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "instance_type" {
  description = "EC2 instance type for gRPC microservices"
  type        = string
  default     = "t3.micro"

  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t3a.micro", "t3a.small", "t3a.medium", "t3a.large",
      "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type suitable for microservices."
  }
}

variable "microservices" {
  description = "Configuration for gRPC microservices"
  type = map(object({
    name        = string
    port        = number
    health_port = number
  }))
  default = {
    user = {
      name        = "user-service"
      port        = 50051
      health_port = 8080
    }
    order = {
      name        = "order-service"
      port        = 50052
      health_port = 8080
    }
    inventory = {
      name        = "inventory-service"
      port        = 50053
      health_port = 8080
    }
  }

  validation {
    condition = alltrue([
      for service in values(var.microservices) : 
      service.port >= 1024 && service.port <= 65535 &&
      service.health_port >= 1024 && service.health_port <= 65535
    ])
    error_message = "All service ports must be between 1024 and 65535."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be one of the valid CloudWatch retention periods."
  }
}

variable "enable_monitoring" {
  description = "Enable comprehensive CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2

  validation {
    condition = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "Alarm evaluation periods must be between 1 and 10."
  }
}

variable "high_error_rate_threshold" {
  description = "Threshold for high error rate alarm (count per 5 minutes)"
  type        = number
  default     = 10

  validation {
    condition = var.high_error_rate_threshold > 0
    error_message = "High error rate threshold must be greater than 0."
  }
}

variable "high_latency_threshold_ms" {
  description = "Threshold for high latency alarm in milliseconds"
  type        = number
  default     = 1000

  validation {
    condition = var.high_latency_threshold_ms > 0
    error_message = "High latency threshold must be greater than 0 milliseconds."
  }
}

variable "connection_failure_threshold" {
  description = "Threshold for connection failure alarm (count per 5 minutes)"
  type        = number
  default     = 5

  validation {
    condition = var.connection_failure_threshold > 0
    error_message = "Connection failure threshold must be greater than 0."
  }
}

variable "enable_access_logs" {
  description = "Enable VPC Lattice access logging to CloudWatch"
  type        = bool
  default     = true
}

variable "create_dashboard" {
  description = "Create CloudWatch dashboard for monitoring"
  type        = bool
  default     = true
}