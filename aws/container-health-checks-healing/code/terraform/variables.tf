# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
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
  default     = "health-check"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# ECS Configuration
variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "health-check-cluster"
}

variable "ecs_service_name" {
  description = "Name of the ECS service"
  type        = string
  default     = "health-check-service"
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task"
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Memory (MB) for ECS task"
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2
}

variable "ecs_min_capacity" {
  description = "Minimum number of ECS tasks for auto scaling"
  type        = number
  default     = 1
}

variable "ecs_max_capacity" {
  description = "Maximum number of ECS tasks for auto scaling"
  type        = number
  default     = 10
}

# Container Configuration
variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port that the container listens on"
  type        = number
  default     = 80
}

# Health Check Configuration
variable "health_check_path" {
  description = "Path for health check endpoint"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Interval between health checks (seconds)"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Timeout for health check (seconds)"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks"
  type        = number
  default     = 3
}

variable "health_check_grace_period" {
  description = "Grace period for health checks (seconds)"
  type        = number
  default     = 300
}

# Load Balancer Configuration
variable "alb_name" {
  description = "Name of the Application Load Balancer"
  type        = string
  default     = "health-check-alb"
}

variable "target_group_name" {
  description = "Name of the target group"
  type        = string
  default     = "health-check-tg"
}

# Auto Scaling Configuration
variable "cpu_target_value" {
  description = "Target CPU utilization for auto scaling"
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization for auto scaling"
  type        = number
  default     = 80
}

variable "scale_out_cooldown" {
  description = "Cooldown period for scale out actions (seconds)"
  type        = number
  default     = 300
}

variable "scale_in_cooldown" {
  description = "Cooldown period for scale in actions (seconds)"
  type        = number
  default     = 300
}

# CloudWatch Alarms Configuration
variable "unhealthy_host_threshold" {
  description = "Threshold for unhealthy host count alarm"
  type        = number
  default     = 1
}

variable "high_response_time_threshold" {
  description = "Threshold for high response time alarm (seconds)"
  type        = number
  default     = 1.0
}

variable "low_running_tasks_threshold" {
  description = "Threshold for low running tasks alarm"
  type        = number
  default     = 1
}

# Lambda Configuration
variable "lambda_function_name" {
  description = "Name of the self-healing Lambda function"
  type        = string
  default     = "self-healing-function"
}

variable "lambda_timeout" {
  description = "Lambda function timeout (seconds)"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda function memory size (MB)"
  type        = number
  default     = 128
}

# EKS Configuration (optional)
variable "enable_eks" {
  description = "Enable EKS cluster deployment"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "health-check-eks"
}

variable "eks_node_group_name" {
  description = "Name of the EKS node group"
  type        = string
  default     = "health-check-nodes"
}

variable "eks_node_instance_types" {
  description = "Instance types for EKS nodes"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_desired_size" {
  description = "Desired size of EKS node group"
  type        = number
  default     = 2
}

variable "eks_node_min_size" {
  description = "Minimum size of EKS node group"
  type        = number
  default     = 1
}

variable "eks_node_max_size" {
  description = "Maximum size of EKS node group"
  type        = number
  default     = 4
}

# Common Tags
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}