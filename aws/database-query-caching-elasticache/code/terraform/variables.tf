# Input Variables for Database Query Caching Infrastructure
# These variables allow customization of the infrastructure deployment

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-east-1', 'eu-west-1', etc."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "cache-demo"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VPC Configuration Variables
variable "vpc_id" {
  description = "VPC ID where resources will be created. If not provided, the default VPC will be used"
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "List of subnet IDs for ElastiCache and RDS deployment. If not provided, default VPC subnets will be used"
  type        = list(string)
  default     = []
}

# ElastiCache Configuration Variables
variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"

  validation {
    condition = can(regex("^cache\\.", var.redis_node_type))
    error_message = "Redis node type must start with 'cache.' (e.g., cache.t3.micro, cache.r6g.large)."
  }
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"

  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+$", var.redis_engine_version))
    error_message = "Redis engine version must be in format 'X.Y' (e.g., '7.0', '6.2')."
  }
}

variable "redis_port" {
  description = "Port number for Redis cluster"
  type        = number
  default     = 6379

  validation {
    condition = var.redis_port >= 1024 && var.redis_port <= 65535
    error_message = "Redis port must be between 1024 and 65535."
  }
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters in the replication group"
  type        = number
  default     = 2

  validation {
    condition = var.redis_num_cache_clusters >= 1 && var.redis_num_cache_clusters <= 6
    error_message = "Number of cache clusters must be between 1 and 6."
  }
}

variable "redis_automatic_failover_enabled" {
  description = "Enable automatic failover for Redis replication group"
  type        = bool
  default     = true
}

variable "redis_multi_az_enabled" {
  description = "Enable Multi-AZ deployment for Redis"
  type        = bool
  default     = true
}

variable "redis_at_rest_encryption_enabled" {
  description = "Enable encryption at rest for Redis"
  type        = bool
  default     = true
}

variable "redis_transit_encryption_enabled" {
  description = "Enable encryption in transit for Redis"
  type        = bool
  default     = false
}

# RDS Configuration Variables
variable "create_rds_instance" {
  description = "Whether to create an RDS instance for testing"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"

  validation {
    condition = can(regex("^db\\.", var.rds_instance_class))
    error_message = "RDS instance class must start with 'db.' (e.g., db.t3.micro, db.r5.large)."
  }
}

variable "rds_engine" {
  description = "RDS database engine"
  type        = string
  default     = "mysql"

  validation {
    condition = contains(["mysql", "postgres", "mariadb"], var.rds_engine)
    error_message = "RDS engine must be one of: mysql, postgres, mariadb."
  }
}

variable "rds_engine_version" {
  description = "RDS engine version"
  type        = string
  default     = "8.0"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20

  validation {
    condition = var.rds_allocated_storage >= 20 && var.rds_allocated_storage <= 1000
    error_message = "RDS allocated storage must be between 20 and 1000 GB."
  }
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"

  validation {
    condition = can(regex("^[a-zA-Z][a-zA-Z0-9_]+$", var.rds_master_username))
    error_message = "RDS master username must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "rds_master_password" {
  description = "RDS master password. If not provided, a random password will be generated"
  type        = string
  default     = null
  sensitive   = true
}

variable "rds_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 0

  validation {
    condition = var.rds_backup_retention_period >= 0 && var.rds_backup_retention_period <= 35
    error_message = "RDS backup retention period must be between 0 and 35 days."
  }
}

variable "rds_multi_az" {
  description = "Enable Multi-AZ deployment for RDS"
  type        = bool
  default     = false
}

variable "rds_publicly_accessible" {
  description = "Make RDS instance publicly accessible"
  type        = bool
  default     = false
}

# EC2 Configuration Variables
variable "create_ec2_instance" {
  description = "Whether to create an EC2 instance for testing"
  type        = bool
  default     = true
}

variable "ec2_instance_type" {
  description = "EC2 instance type for testing"
  type        = string
  default     = "t3.micro"

  validation {
    condition = can(regex("^[a-z][0-9]+[a-z]*\\.", var.ec2_instance_type))
    error_message = "EC2 instance type must be valid AWS instance type (e.g., t3.micro, c5.large)."
  }
}

variable "ec2_key_pair_name" {
  description = "EC2 key pair name for SSH access. If not provided, no key pair will be associated"
  type        = string
  default     = null
}

# Security Configuration Variables
variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access Redis and RDS"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All entries in allowed_cidr_blocks must be valid CIDR notation."
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs for ElastiCache"
  type        = bool
  default     = true
}

# Tagging Variables
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition = length(var.additional_tags) <= 50
    error_message = "Cannot specify more than 50 additional tags."
  }
}