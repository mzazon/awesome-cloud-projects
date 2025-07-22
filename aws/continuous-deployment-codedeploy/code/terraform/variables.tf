# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
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

variable "project_name" {
  description = "Base name for the project resources"
  type        = string
  default     = "webapp"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# Networking Configuration
variable "vpc_id" {
  description = "VPC ID to deploy resources into. If not specified, default VPC will be used"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for deployment. If not specified, default VPC subnets will be used"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "List of availability zones to use. If not specified, will auto-discover"
  type        = list(string)
  default     = []
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition = can(regex("^[a-z][0-9][a-z]?\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type format."
  }
}

variable "key_pair_name" {
  description = "EC2 Key Pair name for SSH access. If not specified, a new key pair will be created"
  type        = string
  default     = ""
}

variable "create_key_pair" {
  description = "Whether to create a new EC2 key pair"
  type        = bool
  default     = true
}

variable "enable_ssh_access" {
  description = "Whether to enable SSH access to EC2 instances"
  type        = bool
  default     = true
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Auto Scaling Configuration
variable "min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.min_size >= 1 && var.min_size <= 10
    error_message = "Minimum size must be between 1 and 10."
  }
}

variable "max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 4
  
  validation {
    condition     = var.max_size >= 2 && var.max_size <= 20
    error_message = "Maximum size must be between 2 and 20."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 2
  
  validation {
    condition     = var.desired_capacity >= 1 && var.desired_capacity <= 10
    error_message = "Desired capacity must be between 1 and 10."
  }
}

# CodeCommit Configuration
variable "repository_name" {
  description = "Name for the CodeCommit repository. If not specified, will be auto-generated"
  type        = string
  default     = ""
}

variable "repository_description" {
  description = "Description for the CodeCommit repository"
  type        = string
  default     = "Repository for webapp continuous deployment with CodeDeploy"
}

# CodeBuild Configuration
variable "build_project_name" {
  description = "Name for the CodeBuild project. If not specified, will be auto-generated"
  type        = string
  default     = ""
}

variable "build_compute_type" {
  description = "CodeBuild compute type"
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
  
  validation {
    condition = contains([
      "BUILD_GENERAL1_SMALL",
      "BUILD_GENERAL1_MEDIUM", 
      "BUILD_GENERAL1_LARGE",
      "BUILD_GENERAL1_2XLARGE"
    ], var.build_compute_type)
    error_message = "Build compute type must be a valid CodeBuild compute type."
  }
}

variable "build_image" {
  description = "CodeBuild Docker image"
  type        = string
  default     = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
}

# CodeDeploy Configuration
variable "deployment_config_name" {
  description = "CodeDeploy deployment configuration"
  type        = string
  default     = "CodeDeployDefault.AllAtOnceBlueGreen"
  
  validation {
    condition = contains([
      "CodeDeployDefault.AllAtOnce",
      "CodeDeployDefault.AllAtOnceBlueGreen",
      "CodeDeployDefault.BlueGreenCanary10Percent30Minutes",
      "CodeDeployDefault.BlueGreenLinear10PercentEvery10Minutes"
    ], var.deployment_config_name)
    error_message = "Deployment config must be a valid CodeDeploy configuration."
  }
}

variable "termination_wait_time" {
  description = "Time to wait before terminating blue instances (in minutes)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.termination_wait_time >= 0 && var.termination_wait_time <= 60
    error_message = "Termination wait time must be between 0 and 60 minutes."
  }
}

# Monitoring Configuration
variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "enable_auto_rollback" {
  description = "Whether to enable automatic rollback on deployment failure"
  type        = bool
  default     = true
}

variable "health_check_grace_period" {
  description = "Health check grace period for Auto Scaling Group (seconds)"
  type        = number
  default     = 300
  
  validation {
    condition     = var.health_check_grace_period >= 0 && var.health_check_grace_period <= 7200
    error_message = "Health check grace period must be between 0 and 7200 seconds."
  }
}

# Load Balancer Configuration
variable "health_check_interval" {
  description = "Health check interval for target groups (seconds)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout for target groups (seconds)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.health_check_timeout >= 2 && var.health_check_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold" {
  description = "Number of consecutive successful health checks before considering target healthy"
  type        = number
  default     = 2
  
  validation {
    condition     = var.healthy_threshold >= 2 && var.healthy_threshold <= 10
    error_message = "Healthy threshold must be between 2 and 10."
  }
}

variable "unhealthy_threshold" {
  description = "Number of consecutive failed health checks before considering target unhealthy"
  type        = number
  default     = 3
  
  validation {
    condition     = var.unhealthy_threshold >= 2 && var.unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}