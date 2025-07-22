# Core configuration variables
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "mixed-instances"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

# Auto Scaling Group configuration
variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition = var.min_size >= 0 && var.min_size <= 100
    error_message = "Minimum size must be between 0 and 100."
  }
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group"
  type        = number
  default     = 10
  
  validation {
    condition = var.max_size >= 1 && var.max_size <= 1000
    error_message = "Maximum size must be between 1 and 1000."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group"
  type        = number
  default     = 4
  
  validation {
    condition = var.desired_capacity >= 0 && var.desired_capacity <= 1000
    error_message = "Desired capacity must be between 0 and 1000."
  }
}

# Mixed instance policy configuration
variable "on_demand_base_capacity" {
  description = "Minimum amount of the ASG's capacity that must be fulfilled by On-Demand instances"
  type        = number
  default     = 1
  
  validation {
    condition = var.on_demand_base_capacity >= 0
    error_message = "On-Demand base capacity must be 0 or greater."
  }
}

variable "on_demand_percentage_above_base_capacity" {
  description = "Percentage of additional capacity that must be fulfilled by On-Demand instances"
  type        = number
  default     = 20
  
  validation {
    condition = var.on_demand_percentage_above_base_capacity >= 0 && var.on_demand_percentage_above_base_capacity <= 100
    error_message = "On-Demand percentage above base capacity must be between 0 and 100."
  }
}

variable "spot_allocation_strategy" {
  description = "Strategy to use when launching Spot instances"
  type        = string
  default     = "diversified"
  
  validation {
    condition = contains(["lowest-price", "diversified", "capacity-optimized", "capacity-optimized-prioritized"], var.spot_allocation_strategy)
    error_message = "Spot allocation strategy must be one of: lowest-price, diversified, capacity-optimized, capacity-optimized-prioritized."
  }
}

variable "spot_instance_pools" {
  description = "Number of Spot Instance pools to diversify across"
  type        = number
  default     = 4
  
  validation {
    condition = var.spot_instance_pools >= 1 && var.spot_instance_pools <= 20
    error_message = "Spot instance pools must be between 1 and 20."
  }
}

variable "spot_max_price" {
  description = "Maximum price per hour you are willing to pay for Spot instances (empty string means On-Demand price)"
  type        = string
  default     = ""
}

# Instance type configuration
variable "instance_types" {
  description = "List of instance types for the mixed instance policy"
  type = list(object({
    instance_type     = string
    weighted_capacity = number
  }))
  default = [
    {
      instance_type     = "m5.large"
      weighted_capacity = 1
    },
    {
      instance_type     = "m5.xlarge"
      weighted_capacity = 2
    },
    {
      instance_type     = "c5.large"
      weighted_capacity = 1
    },
    {
      instance_type     = "c5.xlarge"
      weighted_capacity = 2
    },
    {
      instance_type     = "r5.large"
      weighted_capacity = 1
    },
    {
      instance_type     = "r5.xlarge"
      weighted_capacity = 2
    }
  ]
  
  validation {
    condition = length(var.instance_types) > 0 && length(var.instance_types) <= 20
    error_message = "Must specify between 1 and 20 instance types."
  }
}

# Scaling policy configuration
variable "cpu_target_value" {
  description = "Target value for CPU utilization scaling policy"
  type        = number
  default     = 70.0
  
  validation {
    condition = var.cpu_target_value > 0 && var.cpu_target_value <= 100
    error_message = "CPU target value must be between 0 and 100."
  }
}

variable "network_target_value" {
  description = "Target value for network in bytes scaling policy"
  type        = number
  default     = 1000000.0
  
  validation {
    condition = var.network_target_value > 0
    error_message = "Network target value must be greater than 0."
  }
}

variable "scale_cooldown" {
  description = "Cooldown period in seconds for scaling policies"
  type        = number
  default     = 300
  
  validation {
    condition = var.scale_cooldown >= 0 && var.scale_cooldown <= 3600
    error_message = "Scale cooldown must be between 0 and 3600 seconds."
  }
}

# Health check configuration
variable "health_check_type" {
  description = "Type of health check to use (EC2 or ELB)"
  type        = string
  default     = "ELB"
  
  validation {
    condition = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "Health check type must be either EC2 or ELB."
  }
}

variable "health_check_grace_period" {
  description = "Time in seconds after instance launch before health checks start"
  type        = number
  default     = 300
  
  validation {
    condition = var.health_check_grace_period >= 0 && var.health_check_grace_period <= 7200
    error_message = "Health check grace period must be between 0 and 7200 seconds."
  }
}

# Load balancer configuration
variable "enable_load_balancer" {
  description = "Whether to create an Application Load Balancer"
  type        = bool
  default     = true
}

variable "load_balancer_health_check_interval" {
  description = "Interval in seconds for load balancer health checks"
  type        = number
  default     = 30
  
  validation {
    condition = var.load_balancer_health_check_interval >= 5 && var.load_balancer_health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "load_balancer_health_check_timeout" {
  description = "Timeout in seconds for load balancer health checks"
  type        = number
  default     = 5
  
  validation {
    condition = var.load_balancer_health_check_timeout >= 2 && var.load_balancer_health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "load_balancer_healthy_threshold" {
  description = "Number of consecutive successful health checks before considering target healthy"
  type        = number
  default     = 2
  
  validation {
    condition = var.load_balancer_healthy_threshold >= 2 && var.load_balancer_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "load_balancer_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before considering target unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition = var.load_balancer_unhealthy_threshold >= 2 && var.load_balancer_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

# Capacity rebalancing
variable "enable_capacity_rebalance" {
  description = "Whether to enable capacity rebalancing for Spot instance management"
  type        = bool
  default     = true
}

# Monitoring and notifications
variable "enable_notifications" {
  description = "Whether to enable SNS notifications for Auto Scaling events"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for Auto Scaling notifications (optional)"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

# VPC configuration
variable "create_vpc" {
  description = "Whether to create a new VPC or use existing one"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID to use for resources (if not creating new VPC). Leave empty to use default VPC."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for the Auto Scaling Group (if not creating new VPC). Leave empty to use default VPC subnets."
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (only used if create_vpc is true)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use for subnets (only used if create_vpc is true)"
  type        = list(string)
  default     = []
}

# Security configuration
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the application"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified."
  }
}

variable "enable_ssh_access" {
  description = "Whether to allow SSH access to instances"
  type        = bool
  default     = true
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access (optional)"
  type        = string
  default     = ""
}

# Instance configuration
variable "instance_monitoring" {
  description = "Whether to enable detailed monitoring for instances"
  type        = bool
  default     = true
}

variable "ebs_optimized" {
  description = "Whether to enable EBS optimization for instances"
  type        = bool
  default     = true
}

variable "associate_public_ip_address" {
  description = "Whether to associate public IP addresses with instances"
  type        = bool
  default     = true
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}