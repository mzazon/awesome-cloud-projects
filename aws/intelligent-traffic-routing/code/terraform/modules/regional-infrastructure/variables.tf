# Regional Infrastructure Module Variables

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
}

variable "region" {
  description = "AWS region for this infrastructure"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  
  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for ALB."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web servers"
  type        = string
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
}

variable "min_capacity" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
}

variable "max_capacity" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
}

variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/health"
}

variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
}

variable "target_group_health_check_interval" {
  description = "Target group health check interval in seconds"
  type        = number
  default     = 30
}

variable "target_group_health_check_timeout" {
  description = "Target group health check timeout in seconds"
  type        = number
  default     = 5
}

variable "target_group_healthy_threshold" {
  description = "Number of consecutive successful health checks before marking target healthy"
  type        = number
  default     = 2
}

variable "target_group_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before marking target unhealthy"
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}