# Core Configuration Variables
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "advanced-cicd"
  
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

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "engineering"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "devops-team"
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
}

# ECS Configuration
variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "dev_cluster_capacity_providers" {
  description = "Capacity providers for development cluster"
  type        = list(string)
  default     = ["FARGATE", "FARGATE_SPOT"]
}

variable "prod_cluster_capacity_providers" {
  description = "Capacity providers for production cluster"
  type        = list(string)
  default     = ["FARGATE"]
}

variable "dev_service_desired_count" {
  description = "Desired count for development service"
  type        = number
  default     = 2
}

variable "prod_service_desired_count" {
  description = "Desired count for production service"
  type        = number
  default     = 3
}

# Task Definition Configuration
variable "dev_task_cpu" {
  description = "CPU units for development task"
  type        = number
  default     = 256
}

variable "dev_task_memory" {
  description = "Memory for development task"
  type        = number
  default     = 512
}

variable "prod_task_cpu" {
  description = "CPU units for production task"
  type        = number
  default     = 512
}

variable "prod_task_memory" {
  description = "Memory for production task"
  type        = number
  default     = 1024
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Health check path for the application"
  type        = string
  default     = "/health"
}

# ECR Configuration
variable "image_tag_mutability" {
  description = "Image tag mutability setting"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "Image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Enable vulnerability scanning on image push"
  type        = bool
  default     = true
}

# Load Balancer Configuration
variable "alb_idle_timeout" {
  description = "ALB idle timeout in seconds"
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancers"
  type        = bool
  default     = false
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

variable "healthy_threshold" {
  description = "Healthy threshold count"
  type        = number
  default     = 2
}

variable "unhealthy_threshold" {
  description = "Unhealthy threshold count"
  type        = number
  default     = 3
}

# CodeBuild Configuration
variable "build_compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_MEDIUM"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM",
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_XLARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.build_compute_type)
    error_message = "Build compute type must be a valid CodeBuild compute type."
  }
}

variable "build_image" {
  description = "CodeBuild image"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
}

variable "build_timeout" {
  description = "CodeBuild timeout in minutes"
  type        = number
  default     = 60
}

# CodeDeploy Configuration
variable "deployment_config_name" {
  description = "CodeDeploy deployment configuration"
  type        = string
  default     = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  
  validation {
    condition = contains([
      "CodeDeployDefault.ECSAllAtOnce",
      "CodeDeployDefault.ECSLinear10PercentEvery1Minutes",
      "CodeDeployDefault.ECSLinear10PercentEvery3Minutes",
      "CodeDeployDefault.ECSCanary10Percent5Minutes",
      "CodeDeployDefault.ECSCanary10Percent15Minutes"
    ], var.deployment_config_name)
    error_message = "Deployment configuration must be a valid ECS deployment configuration."
  }
}

variable "auto_rollback_enabled" {
  description = "Enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

variable "auto_rollback_events" {
  description = "Events that trigger automatic rollback"
  type        = list(string)
  default     = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
}

variable "blue_green_termination_wait_time" {
  description = "Wait time before terminating blue instances (minutes)"
  type        = number
  default     = 5
}

# CloudWatch Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "dev_log_retention_days" {
  description = "Development environment log retention in days"
  type        = number
  default     = 7
}

variable "alarm_evaluation_periods" {
  description = "Number of periods for alarm evaluation"
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Period for alarm evaluation in seconds"
  type        = number
  default     = 300
}

variable "high_error_rate_threshold" {
  description = "Threshold for high error rate alarm"
  type        = number
  default     = 10
}

variable "high_response_time_threshold" {
  description = "Threshold for high response time alarm (seconds)"
  type        = number
  default     = 2.0
}

# GitHub Configuration (Optional)
variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch to track"
  type        = string
  default     = "main"
}

# Notification Configuration
variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = ""
}

variable "enable_slack_notifications" {
  description = "Enable Slack notifications"
  type        = bool
  default     = false
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

# Security Configuration
variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail logging"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config"
  type        = bool
  default     = true
}

variable "enable_guardduty" {
  description = "Enable GuardDuty"
  type        = bool
  default     = false
}

# Cost Optimization
variable "enable_fargate_spot" {
  description = "Enable Fargate Spot for development workloads"
  type        = bool
  default     = true
}

variable "enable_lifecycle_policies" {
  description = "Enable ECR lifecycle policies"
  type        = bool
  default     = true
}

variable "max_prod_images" {
  description = "Maximum number of production images to retain"
  type        = number
  default     = 10
}

variable "max_dev_images" {
  description = "Maximum number of development images to retain"
  type        = number
  default     = 5
}

# Feature Flags
variable "enable_xray" {
  description = "Enable X-Ray tracing"
  type        = bool
  default     = true
}

variable "enable_blue_green_deployment" {
  description = "Enable blue-green deployment for production"
  type        = bool
  default     = true
}

variable "enable_manual_approval" {
  description = "Enable manual approval stage in pipeline"
  type        = bool
  default     = true
}

variable "enable_security_scanning" {
  description = "Enable security scanning in build process"
  type        = bool
  default     = true
}

variable "enable_performance_monitoring" {
  description = "Enable enhanced performance monitoring"
  type        = bool
  default     = true
}