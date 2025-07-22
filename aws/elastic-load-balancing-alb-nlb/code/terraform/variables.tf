# variables.tf - Input variables for the Elastic Load Balancing infrastructure

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "elb-demo"
}

variable "vpc_id" {
  description = "VPC ID where resources will be created (uses default VPC if not specified)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for load balancer placement (uses default VPC subnets if not specified)"
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = can(regex("^t3\\.(nano|micro|small|medium|large|xlarge|2xlarge)$", var.instance_type))
    error_message = "Instance type must be a valid t3 instance type."
  }
}

variable "instance_count" {
  description = "Number of EC2 instances to create"
  type        = number
  default     = 2
  
  validation {
    condition     = var.instance_count >= 2 && var.instance_count <= 10
    error_message = "Instance count must be between 2 and 10."
  }
}

variable "alb_name" {
  description = "Name for the Application Load Balancer"
  type        = string
  default     = ""
}

variable "nlb_name" {
  description = "Name for the Network Load Balancer"
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancers"
  type        = bool
  default     = false
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing for Network Load Balancer"
  type        = bool
  default     = false
}

variable "alb_idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle"
  type        = number
  default     = 60
  
  validation {
    condition     = var.alb_idle_timeout >= 1 && var.alb_idle_timeout <= 4000
    error_message = "ALB idle timeout must be between 1 and 4000 seconds."
  }
}

variable "health_check_interval" {
  description = "The approximate amount of time between health checks"
  type        = number
  default     = 30
  
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "The amount of time to wait for health check response"
  type        = number
  default     = 5
  
  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold" {
  description = "The number of consecutive health checks successes required"
  type        = number
  default     = 2
  
  validation {
    condition     = var.healthy_threshold >= 2 && var.healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "unhealthy_threshold" {
  description = "The number of consecutive health check failures required"
  type        = number
  default     = 5
  
  validation {
    condition     = var.unhealthy_threshold >= 2 && var.unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

variable "enable_stickiness" {
  description = "Enable sticky sessions for ALB target group"
  type        = bool
  default     = true
}

variable "stickiness_duration" {
  description = "Duration of sticky sessions in seconds"
  type        = number
  default     = 86400
  
  validation {
    condition     = var.stickiness_duration >= 1 && var.stickiness_duration <= 604800
    error_message = "Stickiness duration must be between 1 and 604800 seconds (7 days)."
  }
}

variable "deregistration_delay" {
  description = "Time to wait before deregistering a target"
  type        = number
  default     = 30
  
  validation {
    condition     = var.deregistration_delay >= 0 && var.deregistration_delay <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

variable "allow_ssh_access" {
  description = "Allow SSH access to EC2 instances"
  type        = bool
  default     = true
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}