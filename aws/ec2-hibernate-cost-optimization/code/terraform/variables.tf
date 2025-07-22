# Core Configuration Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = can(regex("^(dev|staging|prod)$", var.environment))
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# EC2 Instance Configuration
variable "instance_type" {
  description = "EC2 instance type that supports hibernation"
  type        = string
  default     = "m5.large"
  
  validation {
    condition = can(regex("^(m5|m5d|m5a|m5ad|m5n|m5dn|m5zn|m6i|m6id|m6idn|m6in|m6a|m6gd|m7i|m7id|m7idn|m7in|m7a|m7gd|r5|r5d|r5a|r5ad|r5n|r5dn|r5b|r6i|r6id|r6idn|r6in|r6a|r6gd|r7i|r7id|r7idn|r7in|r7a|r7gd|c5|c5d|c5a|c5ad|c5n|c6i|c6id|c6in|c6a|c6gd|c7i|c7id|c7in|c7a|c7gd|x1|x1e|x2iezn|x2idn|x2iedn|x2gd|z1d|i3|i3en|i4i|i4g|d2|d3|d3en|h1|inf1|inf2|trn1|trn1n|p3|p3dn|p4d|p4de|p5|g4dn|g4ad|g5|g5g|g6|vt1|im4gn|is4gen|mac2|mac2-m2|mac2-m2pro|mac1|f1|x2gd|u-6tb1|u-9tb1|u-12tb1|u-18tb1|u-24tb1|u-3tb1|u-6tb1|u-9tb1|u-12tb1|u-18tb1|u-24tb1|hpc6a|hpc6id|hpc7a|hpc7g|dl1|dl2q)\\.(nano|micro|small|medium|large|xlarge|2xlarge|3xlarge|4xlarge|8xlarge|9xlarge|10xlarge|12xlarge|16xlarge|18xlarge|24xlarge|32xlarge|48xlarge|56xlarge|96xlarge|112xlarge|224xlarge|metal)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type that supports hibernation."
  }
}

variable "ebs_volume_size" {
  description = "Size of the EBS root volume in GB (must be at least as large as RAM)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.ebs_volume_size >= 30
    error_message = "EBS volume size must be at least 30 GB for hibernation."
  }
}

variable "ebs_volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.ebs_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2."
  }
}

variable "key_pair_name" {
  description = "Name for the EC2 key pair (leave empty to generate)"
  type        = string
  default     = ""
}

variable "instance_name" {
  description = "Name for the EC2 instance (leave empty to generate)"
  type        = string
  default     = ""
}

# CloudWatch Monitoring Configuration
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instance"
  type        = bool
  default     = true
}

variable "cpu_threshold" {
  description = "CPU utilization threshold for CloudWatch alarm (percentage)"
  type        = number
  default     = 10
  
  validation {
    condition     = var.cpu_threshold >= 1 && var.cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "cpu_evaluation_periods" {
  description = "Number of periods for CPU utilization evaluation"
  type        = number
  default     = 6
  
  validation {
    condition     = var.cpu_evaluation_periods >= 1
    error_message = "CPU evaluation periods must be at least 1."
  }
}

variable "cpu_alarm_period" {
  description = "Period in seconds for CPU utilization alarm"
  type        = number
  default     = 300
  
  validation {
    condition     = contains([60, 300, 900, 3600], var.cpu_alarm_period)
    error_message = "CPU alarm period must be one of: 60, 300, 900, 3600."
  }
}

# SNS Notification Configuration
variable "notification_email" {
  description = "Email address for SNS notifications (leave empty to skip email subscription)"
  type        = string
  default     = ""
}

variable "sns_topic_name" {
  description = "Name for the SNS topic (leave empty to generate)"
  type        = string
  default     = ""
}

# VPC Configuration
variable "vpc_id" {
  description = "VPC ID to launch resources in (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID to launch instance in (leave empty to use default subnet)"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the instance via SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Resource Naming Configuration
variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "hibernate-demo"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,20}$", var.name_prefix))
    error_message = "Name prefix must be 1-20 characters and contain only letters, numbers, and hyphens."
  }
}

# Tags Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}