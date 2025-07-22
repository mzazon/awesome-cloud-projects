# ==============================================================================
# CORE CONFIGURATION VARIABLES
# ==============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "production"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cost-optimized-ecs"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# NETWORKING CONFIGURATION
# ==============================================================================

variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, will use default VPC"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Auto Scaling Group. If not provided, will use default VPC subnets"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones to use. If not provided, will use all AZs in the region"
  type        = list(string)
  default     = []
}

# ==============================================================================
# ECS CLUSTER CONFIGURATION
# ==============================================================================

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "cost-optimized-cluster"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]+$", var.cluster_name))
    error_message = "Cluster name must contain only letters, numbers, hyphens, and underscores."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the ECS cluster"
  type        = bool
  default     = true
}

# ==============================================================================
# AUTO SCALING GROUP CONFIGURATION
# ==============================================================================

variable "instance_types" {
  description = "List of EC2 instance types for mixed instances policy"
  type        = list(string)
  default     = ["m5.large", "m4.large", "c5.large", "c4.large", "r5.large"]
  
  validation {
    condition     = length(var.instance_types) >= 2
    error_message = "At least 2 instance types must be specified for diversification."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 1
  
  validation {
    condition     = var.min_size >= 0
    error_message = "Minimum size must be non-negative."
  }
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 10
  
  validation {
    condition     = var.max_size >= var.min_size
    error_message = "Maximum size must be greater than or equal to minimum size."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 3
  
  validation {
    condition     = var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size
    error_message = "Desired capacity must be between min_size and max_size."
  }
}

variable "on_demand_base_capacity" {
  description = "Minimum number of On-Demand instances in the Auto Scaling Group"
  type        = number
  default     = 1
  
  validation {
    condition     = var.on_demand_base_capacity >= 0
    error_message = "On-Demand base capacity must be non-negative."
  }
}

variable "on_demand_percentage_above_base" {
  description = "Percentage of On-Demand instances above base capacity"
  type        = number
  default     = 20
  
  validation {
    condition     = var.on_demand_percentage_above_base >= 0 && var.on_demand_percentage_above_base <= 100
    error_message = "On-Demand percentage must be between 0 and 100."
  }
}

variable "spot_instance_pools" {
  description = "Number of Spot instance pools to use for diversification"
  type        = number
  default     = 4
  
  validation {
    condition     = var.spot_instance_pools >= 2
    error_message = "At least 2 Spot instance pools are recommended for diversification."
  }
}

variable "spot_max_price" {
  description = "Maximum price per hour for Spot instances (empty string for On-Demand price)"
  type        = string
  default     = "0.10"
}

# ==============================================================================
# CAPACITY PROVIDER CONFIGURATION
# ==============================================================================

variable "capacity_provider_name" {
  description = "Name of the ECS capacity provider"
  type        = string
  default     = "spot-capacity-provider"
}

variable "target_capacity" {
  description = "Target capacity percentage for the capacity provider"
  type        = number
  default     = 80
  
  validation {
    condition     = var.target_capacity >= 1 && var.target_capacity <= 100
    error_message = "Target capacity must be between 1 and 100."
  }
}

variable "minimum_scaling_step_size" {
  description = "Minimum scaling step size for capacity provider"
  type        = number
  default     = 1
  
  validation {
    condition     = var.minimum_scaling_step_size >= 1
    error_message = "Minimum scaling step size must be at least 1."
  }
}

variable "maximum_scaling_step_size" {
  description = "Maximum scaling step size for capacity provider"
  type        = number
  default     = 3
  
  validation {
    condition     = var.maximum_scaling_step_size >= var.minimum_scaling_step_size
    error_message = "Maximum scaling step size must be greater than or equal to minimum scaling step size."
  }
}

# ==============================================================================
# ECS SERVICE CONFIGURATION
# ==============================================================================

variable "service_name" {
  description = "Name of the ECS service"
  type        = string
  default     = "spot-resilient-service"
}

variable "service_desired_count" {
  description = "Desired number of tasks for the ECS service"
  type        = number
  default     = 6
  
  validation {
    condition     = var.service_desired_count >= 1
    error_message = "Service desired count must be at least 1."
  }
}

variable "service_base_capacity" {
  description = "Base capacity for the ECS service using the capacity provider"
  type        = number
  default     = 2
  
  validation {
    condition     = var.service_base_capacity >= 0
    error_message = "Service base capacity must be non-negative."
  }
}

variable "deployment_maximum_percent" {
  description = "Maximum percentage of desired count allowed during deployment"
  type        = number
  default     = 200
  
  validation {
    condition     = var.deployment_maximum_percent >= 100
    error_message = "Deployment maximum percent must be at least 100."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Minimum healthy percentage during deployment"
  type        = number
  default     = 50
  
  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "Deployment minimum healthy percent must be between 0 and 100."
  }
}

variable "enable_deployment_circuit_breaker" {
  description = "Enable deployment circuit breaker for the ECS service"
  type        = bool
  default     = true
}

variable "enable_deployment_rollback" {
  description = "Enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

# ==============================================================================
# TASK DEFINITION CONFIGURATION
# ==============================================================================

variable "task_family" {
  description = "Family name for the ECS task definition"
  type        = string
  default     = "spot-resilient-app"
}

variable "task_cpu" {
  description = "CPU units for the task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
  
  validation {
    condition     = contains([256, 512, 1024, 2048, 4096], var.task_cpu)
    error_message = "Task CPU must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "task_memory" {
  description = "Memory (MB) for the task"
  type        = number
  default     = 512
  
  validation {
    condition     = var.task_memory >= 256
    error_message = "Task memory must be at least 256 MB."
  }
}

variable "container_image" {
  description = "Docker image for the container"
  type        = string
  default     = "public.ecr.aws/docker/library/nginx:latest"
}

variable "container_port" {
  description = "Port that the container listens on"
  type        = number
  default     = 80
  
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "Container port must be between 1 and 65535."
  }
}

# ==============================================================================
# AUTO SCALING CONFIGURATION
# ==============================================================================

variable "enable_service_auto_scaling" {
  description = "Enable auto scaling for the ECS service"
  type        = bool
  default     = true
}

variable "auto_scaling_min_capacity" {
  description = "Minimum capacity for service auto scaling"
  type        = number
  default     = 2
  
  validation {
    condition     = var.auto_scaling_min_capacity >= 1
    error_message = "Auto scaling minimum capacity must be at least 1."
  }
}

variable "auto_scaling_max_capacity" {
  description = "Maximum capacity for service auto scaling"
  type        = number
  default     = 20
  
  validation {
    condition     = var.auto_scaling_max_capacity >= var.auto_scaling_min_capacity
    error_message = "Auto scaling maximum capacity must be greater than or equal to minimum capacity."
  }
}

variable "auto_scaling_target_cpu" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 60
  
  validation {
    condition     = var.auto_scaling_target_cpu >= 10 && var.auto_scaling_target_cpu <= 90
    error_message = "Auto scaling target CPU must be between 10 and 90."
  }
}

variable "auto_scaling_scale_out_cooldown" {
  description = "Cooldown period (seconds) after scale out"
  type        = number
  default     = 300
  
  validation {
    condition     = var.auto_scaling_scale_out_cooldown >= 60
    error_message = "Scale out cooldown must be at least 60 seconds."
  }
}

variable "auto_scaling_scale_in_cooldown" {
  description = "Cooldown period (seconds) after scale in"
  type        = number
  default     = 300
  
  validation {
    condition     = var.auto_scaling_scale_in_cooldown >= 60
    error_message = "Scale in cooldown must be at least 60 seconds."
  }
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the application"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring for EC2 instances"
  type        = bool
  default     = false
}

# ==============================================================================
# LOGGING CONFIGURATION
# ==============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# ==============================================================================
# TAGS
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}