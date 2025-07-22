variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "Environment name must contain only alphanumeric characters and hyphens."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "data-encryption-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 7
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ec2_volume_size" {
  description = "EC2 root volume size in GB"
  type        = number
  default     = 8
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "cloudtrail_retention_days" {
  description = "CloudTrail log retention period in days"
  type        = number
  default     = 90
}

variable "enable_certificate_request" {
  description = "Enable ACM certificate request (requires domain)"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Domain name for ACM certificate"
  type        = string
  default     = ""
}

variable "enable_ssh_access" {
  description = "Enable SSH access to EC2 instances"
  type        = bool
  default     = true
}

variable "ssh_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "force_destroy_s3_buckets" {
  description = "Force destroy S3 buckets even if they contain objects"
  type        = bool
  default     = false
}