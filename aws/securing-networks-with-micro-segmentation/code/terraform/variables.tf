# Variables for Network Micro-Segmentation Infrastructure

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  description = "Availability zone for subnet placement"
  type        = string
  default     = ""
}

variable "subnet_cidrs" {
  description = "CIDR blocks for each security zone subnet"
  type = object({
    dmz        = string
    web        = string
    app        = string
    database   = string
    management = string
    monitoring = string
  })
  default = {
    dmz        = "10.0.1.0/24"
    web        = "10.0.2.0/24"
    app        = "10.0.3.0/24"
    database   = "10.0.4.0/24"
    management = "10.0.5.0/24"
    monitoring = "10.0.6.0/24"
  }
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for traffic monitoring"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch log retention in days for VPC Flow Logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.flow_logs_retention_days)
    error_message = "Flow logs retention days must be a valid CloudWatch log retention period."
  }
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for security monitoring"
  type        = bool
  default     = true
}

variable "rejected_traffic_threshold" {
  description = "Threshold for rejected traffic alarm (packets per 5-minute period)"
  type        = number
  default     = 1000
}

variable "create_key_pair" {
  description = "Create EC2 key pair for instance access"
  type        = bool
  default     = true
}

variable "key_pair_name" {
  description = "Name for the EC2 key pair (if not provided, will be generated)"
  type        = string
  default     = ""
}

variable "management_access_cidr" {
  description = "CIDR block allowed for management access (SSH, etc.)"
  type        = string
  default     = "10.0.0.0/8"
  
  validation {
    condition     = can(cidrhost(var.management_access_cidr, 0))
    error_message = "Management access CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnet internet access"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}