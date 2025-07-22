# Input variables for the App Runner and RDS infrastructure

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "webapp"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.project_name))
    error_message = "Project name must be lowercase, start with a letter, and contain only letters, numbers, and hyphens (2-32 chars)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Networking Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnet CIDRs are required for RDS."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (for NAT gateways if needed)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnet CIDRs are required for high availability."
  }
}

# ECR Configuration
variable "container_image_tag" {
  description = "Tag for the container image"
  type        = string
  default     = "latest"
}

variable "ecr_image_tag_mutability" {
  description = "Image tag mutability setting for ECR repository"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "enable_ecr_image_scan" {
  description = "Enable image scanning on push to ECR"
  type        = bool
  default     = true
}

# RDS Configuration
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.", var.db_instance_class))
    error_message = "DB instance class must be a valid RDS instance class."
  }
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "14.9"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS instance (GB)"
  type        = number
  default     = 20

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536
    error_message = "DB allocated storage must be between 20 and 65536 GB."
  }
}

variable "db_storage_type" {
  description = "Storage type for RDS instance"
  type        = string
  default     = "gp2"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.db_storage_type)
    error_message = "DB storage type must be gp2, gp3, io1, or io2."
  }
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "DB backup retention period must be between 0 and 35 days."
  }
}

variable "db_backup_window" {
  description = "Preferred backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "db_multi_az" {
  description = "Enable multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

variable "db_storage_encrypted" {
  description = "Enable storage encryption for RDS"
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = false
}

# App Runner Configuration
variable "apprunner_cpu" {
  description = "CPU allocation for App Runner service"
  type        = string
  default     = "0.25 vCPU"

  validation {
    condition = contains([
      "0.25 vCPU", "0.5 vCPU", "1 vCPU", "2 vCPU", "4 vCPU"
    ], var.apprunner_cpu)
    error_message = "App Runner CPU must be one of: 0.25 vCPU, 0.5 vCPU, 1 vCPU, 2 vCPU, 4 vCPU."
  }
}

variable "apprunner_memory" {
  description = "Memory allocation for App Runner service"
  type        = string
  default     = "0.5 GB"

  validation {
    condition = contains([
      "0.5 GB", "1 GB", "2 GB", "3 GB", "4 GB", "6 GB", "8 GB", "10 GB", "12 GB"
    ], var.apprunner_memory)
    error_message = "App Runner memory must be a valid memory allocation."
  }
}

variable "apprunner_port" {
  description = "Port that the App Runner service listens on"
  type        = string
  default     = "8080"
}

variable "apprunner_health_check_path" {
  description = "Health check path for App Runner service"
  type        = string
  default     = "/health"
}

variable "apprunner_health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10

  validation {
    condition     = var.apprunner_health_check_interval >= 5 && var.apprunner_health_check_interval <= 20
    error_message = "Health check interval must be between 5 and 20 seconds."
  }
}

variable "apprunner_health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5

  validation {
    condition     = var.apprunner_health_check_timeout >= 2 && var.apprunner_health_check_timeout <= 20
    error_message = "Health check timeout must be between 2 and 20 seconds."
  }
}

variable "apprunner_health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks required"
  type        = number
  default     = 1

  validation {
    condition     = var.apprunner_health_check_healthy_threshold >= 1 && var.apprunner_health_check_healthy_threshold <= 20
    error_message = "Health check healthy threshold must be between 1 and 20."
  }
}

variable "apprunner_health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks required"
  type        = number
  default     = 5

  validation {
    condition     = var.apprunner_health_check_unhealthy_threshold >= 2 && var.apprunner_health_check_unhealthy_threshold <= 20
    error_message = "Health check unhealthy threshold must be between 2 and 20."
  }
}

variable "enable_auto_deployments" {
  description = "Enable automatic deployments on image push"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "log_retention_in_days" {
  description = "Log retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_in_days)
    error_message = "Log retention must be a valid CloudWatch Logs retention period."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# SNS Configuration for Alarms
variable "alarm_notification_email" {
  description = "Email address for alarm notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.alarm_notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alarm_notification_email))
    error_message = "Alarm notification email must be a valid email address or empty."
  }
}

# Tagging
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Project     = "containerized-web-app"
    Environment = "dev"
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}