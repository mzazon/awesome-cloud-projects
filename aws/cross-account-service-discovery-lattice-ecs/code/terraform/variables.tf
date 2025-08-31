# Input variables for cross-account service discovery with VPC Lattice and ECS

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "cross-account-discovery"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Account Configuration Variables
variable "account_a_id" {
  description = "AWS Account ID for Account A (Producer account)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_a_id))
    error_message = "Account ID must be a 12-digit number."
  }
}

variable "account_b_id" {
  description = "AWS Account ID for Account B (Consumer account)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_b_id))
    error_message = "Account ID must be a 12-digit number."
  }
}

variable "account_b_assume_role_arn" {
  description = "ARN of the IAM role to assume in Account B for cross-account resource creation"
  type        = string
  default     = ""

  validation {
    condition = var.account_b_assume_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/.+", var.account_b_assume_role_arn))
    error_message = "Account B assume role ARN must be a valid IAM role ARN or empty string."
  }
}

# VPC Configuration Variables
variable "vpc_id" {
  description = "VPC ID for Account A (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS service deployment (leave empty to use default VPC subnets)"
  type        = list(string)
  default     = []
}

# VPC Lattice Configuration Variables
variable "service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = ""

  validation {
    condition     = var.service_network_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.service_network_name))
    error_message = "Service network name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lattice_service_name" {
  description = "Name for the VPC Lattice service"
  type        = string
  default     = ""

  validation {
    condition     = var.lattice_service_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.lattice_service_name))
    error_message = "Lattice service name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "lattice_auth_type" {
  description = "Authentication type for VPC Lattice service network and services"
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.lattice_auth_type)
    error_message = "Authentication type must be either 'AWS_IAM' or 'NONE'."
  }
}

# ECS Configuration Variables
variable "cluster_name" {
  description = "Name for the ECS cluster"
  type        = string
  default     = ""

  validation {
    condition     = var.cluster_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "service_name" {
  description = "Name for the ECS service"
  type        = string
  default     = ""

  validation {
    condition     = var.service_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.service_name))
    error_message = "Service name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "task_cpu" {
  description = "CPU units for ECS task (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 256

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory (MiB) for ECS task (512, 1024, 2048, 3072, 4096, 5120, 6144, 7168, 8192)"
  type        = number
  default     = 512

  validation {
    condition     = contains([512, 1024, 2048, 3072, 4096, 5120, 6144, 7168, 8192], var.task_memory)
    error_message = "Task memory must be a valid value for the specified CPU."
  }
}

variable "desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 1 && var.desired_count <= 10
    error_message = "Desired count must be between 1 and 10."
  }
}

variable "container_image" {
  description = "Container image for the producer service"
  type        = string
  default     = "nginx:latest"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]+(/[a-zA-Z0-9.-]+)*:[a-zA-Z0-9.-]+$", var.container_image))
    error_message = "Container image must be a valid Docker image reference."
  }
}

variable "container_port" {
  description = "Port exposed by the container"
  type        = number
  default     = 80

  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

# Target Group Configuration Variables
variable "target_group_protocol" {
  description = "Protocol for the VPC Lattice target group"
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.target_group_protocol)
    error_message = "Target group protocol must be either 'HTTP' or 'HTTPS'."
  }
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/.*", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold_count" {
  description = "Number of consecutive successful health checks required"
  type        = number
  default     = 2

  validation {
    condition     = var.healthy_threshold_count >= 2 && var.healthy_threshold_count <= 10
    error_message = "Healthy threshold count must be between 2 and 10."
  }
}

variable "unhealthy_threshold_count" {
  description = "Number of consecutive failed health checks required"
  type        = number
  default     = 3

  validation {
    condition     = var.unhealthy_threshold_count >= 2 && var.unhealthy_threshold_count <= 10
    error_message = "Unhealthy threshold count must be between 2 and 10."
  }
}

# Monitoring Configuration Variables
variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and EventBridge rules"
  type        = bool
  default     = true
}

variable "enable_dashboard" {
  description = "Enable CloudWatch dashboard creation"
  type        = bool
  default     = true
}

# Resource Sharing Configuration Variables
variable "enable_resource_sharing" {
  description = "Enable AWS RAM resource sharing with Account B"
  type        = bool
  default     = true
}

variable "resource_share_name" {
  description = "Name for the AWS RAM resource share"
  type        = string
  default     = ""

  validation {
    condition     = var.resource_share_name == "" || can(regex("^[a-zA-Z0-9-_]+$", var.resource_share_name))
    error_message = "Resource share name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "allow_external_principals" {
  description = "Allow sharing resources with external AWS accounts"
  type        = bool
  default     = true
}

# Security Configuration Variables
variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = false
}

variable "create_security_groups" {
  description = "Create custom security groups for ECS tasks"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the service (default allows all)"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All CIDR blocks must be valid CIDR notation."
  }
}