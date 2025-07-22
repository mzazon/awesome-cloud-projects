# Variables for ECS Service Discovery with Route 53 and ALB Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "microservices"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, default VPC will be used"
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB. If not provided, will use available subnets from VPC"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks. If not provided, will use available subnets from VPC"
  type        = list(string)
  default     = []
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = ""
}

variable "namespace_name" {
  description = "Name of the Cloud Map private DNS namespace"
  type        = string
  default     = "internal.local"
}

variable "alb_name" {
  description = "Name of the Application Load Balancer"
  type        = string
  default     = ""
}

variable "web_service_desired_count" {
  description = "Desired number of web service tasks"
  type        = number
  default     = 2
  
  validation {
    condition     = var.web_service_desired_count >= 1 && var.web_service_desired_count <= 10
    error_message = "Web service desired count must be between 1 and 10."
  }
}

variable "api_service_desired_count" {
  description = "Desired number of API service tasks"
  type        = number
  default     = 2
  
  validation {
    condition     = var.api_service_desired_count >= 1 && var.api_service_desired_count <= 10
    error_message = "API service desired count must be between 1 and 10."
  }
}

variable "web_service_cpu" {
  description = "CPU units for web service tasks (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.web_service_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "web_service_memory" {
  description = "Memory (MB) for web service tasks"
  type        = number
  default     = 512
  
  validation {
    condition     = var.web_service_memory >= 512 && var.web_service_memory <= 30720
    error_message = "Memory must be between 512 and 30720 MB."
  }
}

variable "api_service_cpu" {
  description = "CPU units for API service tasks (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.api_service_cpu)
    error_message = "CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "api_service_memory" {
  description = "Memory (MB) for API service tasks"
  type        = number
  default     = 512
  
  validation {
    condition     = var.api_service_memory >= 512 && var.api_service_memory <= 30720
    error_message = "Memory must be between 512 and 30720 MB."
  }
}

variable "web_service_image" {
  description = "Docker image for web service"
  type        = string
  default     = "nginx:alpine"
}

variable "api_service_image" {
  description = "Docker image for API service"
  type        = string
  default     = "httpd:alpine"
}

variable "web_service_port" {
  description = "Port number for web service"
  type        = number
  default     = 3000
}

variable "api_service_port" {
  description = "Port number for API service"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path for ALB target groups"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "healthy_threshold_count" {
  description = "Number of consecutive health checks successes required"
  type        = number
  default     = 2
}

variable "unhealthy_threshold_count" {
  description = "Number of consecutive health check failures required"
  type        = number
  default     = 3
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for ECS tasks"
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch retention period."
  }
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}