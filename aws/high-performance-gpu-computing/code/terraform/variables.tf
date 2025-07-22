# Variables for GPU-accelerated workloads infrastructure
# These variables allow customization of the GPU computing environment
# while maintaining security and cost optimization best practices

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "AWS region for resource deployment (should support P4 and G4 instances)"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition = contains([
      "us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"
    ], var.region)
    error_message = "Region must support P4 and G4 instance types."
  }
}

variable "project_name" {
  description = "Project name for resource naming and identification"
  type        = string
  default     = "gpu-workload"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 20
    error_message = "Project name must be between 1 and 20 characters."
  }
}

# Instance Configuration Variables
variable "enable_p4_instance" {
  description = "Whether to launch P4 instance for ML training workloads"
  type        = bool
  default     = true
}

variable "p4_instance_type" {
  description = "P4 instance type for ML training (A100 GPU instances)"
  type        = string
  default     = "p4d.24xlarge"
  
  validation {
    condition = contains([
      "p4d.24xlarge", "p4de.24xlarge"
    ], var.p4_instance_type)
    error_message = "P4 instance type must be a valid P4 instance."
  }
}

variable "enable_g4_instances" {
  description = "Whether to launch G4 instances for inference workloads"
  type        = bool
  default     = true
}

variable "g4_instance_type" {
  description = "G4 instance type for inference (T4 GPU instances)"
  type        = string
  default     = "g4dn.xlarge"
  
  validation {
    condition = contains([
      "g4dn.xlarge", "g4dn.2xlarge", "g4dn.4xlarge", "g4dn.8xlarge", "g4dn.12xlarge", "g4dn.16xlarge"
    ], var.g4_instance_type)
    error_message = "G4 instance type must be a valid G4 instance."
  }
}

variable "g4_instance_count" {
  description = "Number of G4 instances to launch for inference workloads"
  type        = number
  default     = 2
  
  validation {
    condition     = var.g4_instance_count >= 1 && var.g4_instance_count <= 10
    error_message = "G4 instance count must be between 1 and 10."
  }
}

# Spot Instance Configuration
variable "use_spot_instances" {
  description = "Whether to use Spot instances for cost optimization"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Maximum price for Spot instances (USD per hour)"
  type        = string
  default     = "1.00"
}

# Network Configuration Variables
variable "vpc_id" {
  description = "VPC ID for GPU instances (leave empty to use default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID for GPU instances (leave empty to use default subnet)"
  type        = string
  default     = ""
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access to GPU instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_key_name" {
  description = "Name of existing EC2 Key Pair for SSH access (leave empty to create new)"
  type        = string
  default     = ""
}

# Storage Configuration Variables
variable "root_volume_size" {
  description = "Size of root EBS volume in GB for GPU instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.root_volume_size >= 50 && var.root_volume_size <= 1000
    error_message = "Root volume size must be between 50 and 1000 GB."
  }
}

variable "root_volume_type" {
  description = "Type of root EBS volume for GPU instances"
  type        = string
  default     = "gp3"
  
  validation {
    condition     = contains(["gp3", "gp2", "io1", "io2"], var.root_volume_type)
    error_message = "Root volume type must be one of: gp3, gp2, io1, io2."
  }
}

variable "create_efs_storage" {
  description = "Whether to create EFS for shared storage across GPU instances"
  type        = bool
  default     = true
}

# Monitoring Configuration Variables
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for GPU instances"
  type        = bool
  default     = true
}

variable "enable_gpu_monitoring" {
  description = "Enable custom GPU metrics monitoring via CloudWatch"
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address for GPU monitoring alerts"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Please provide a valid email address or leave empty."
  }
}

# Cost Optimization Variables
variable "enable_cost_monitoring" {
  description = "Enable automated cost monitoring and alerts"
  type        = bool
  default     = true
}

variable "gpu_utilization_threshold" {
  description = "GPU utilization threshold (%) for low usage alerts"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gpu_utilization_threshold >= 5 && var.gpu_utilization_threshold <= 50
    error_message = "GPU utilization threshold must be between 5 and 50 percent."
  }
}

variable "temperature_threshold" {
  description = "GPU temperature threshold (°C) for high temperature alerts"
  type        = number
  default     = 85
  
  validation {
    condition     = var.temperature_threshold >= 70 && var.temperature_threshold <= 95
    error_message = "Temperature threshold must be between 70 and 95 degrees Celsius."
  }
}

# Security Configuration Variables
variable "enable_ssm_access" {
  description = "Enable AWS Systems Manager for secure instance access"
  type        = bool
  default     = true
}

variable "enable_imdsv2" {
  description = "Enforce IMDSv2 for enhanced instance metadata security"
  type        = bool
  default     = true
}

# Advanced Configuration Variables
variable "user_data_script" {
  description = "Custom user data script for additional GPU instance configuration"
  type        = string
  default     = ""
}

variable "additional_security_group_rules" {
  description = "Additional security group rules for GPU instances"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}