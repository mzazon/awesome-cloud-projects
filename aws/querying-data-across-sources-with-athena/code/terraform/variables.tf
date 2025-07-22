# General Configuration
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "athena-federated-query"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "athena-federated-query"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# Network Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for resource deployment"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# Database Configuration
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "rds_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "rds_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "rds_master_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "rds_master_password" {
  description = "RDS master password"
  type        = string
  default     = "TempPassword123!"
  sensitive   = true
}

variable "database_name" {
  description = "Name of the database to create"
  type        = string
  default     = "analytics_db"
}

# DynamoDB Configuration
variable "dynamodb_read_capacity" {
  description = "DynamoDB read capacity units"
  type        = number
  default     = 5
}

variable "dynamodb_write_capacity" {
  description = "DynamoDB write capacity units"
  type        = number
  default     = 5
}

# Lambda Configuration
variable "lambda_memory_size" {
  description = "Memory size for Lambda functions"
  type        = number
  default     = 3008
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 900
}

# S3 Configuration
variable "force_destroy_s3_buckets" {
  description = "Force destroy S3 buckets even if they contain objects"
  type        = bool
  default     = true
}

# Athena Configuration
variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  type        = string
  default     = "federated-analytics"
}

variable "athena_enforce_workgroup_config" {
  description = "Enforce workgroup configuration"
  type        = bool
  default     = true
}

# Sample Data Configuration
variable "create_sample_data" {
  description = "Whether to create sample data in RDS and DynamoDB"
  type        = bool
  default     = true
}

variable "sample_orders_table" {
  description = "Name of the sample orders table in RDS"
  type        = string
  default     = "sample_orders"
}