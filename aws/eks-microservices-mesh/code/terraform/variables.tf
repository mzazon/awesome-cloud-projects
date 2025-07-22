# Core configuration variables
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-west-2)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "microservices-mesh"
  
  validation {
    condition = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name can only contain lowercase letters, numbers, and hyphens."
  }
}

# EKS cluster configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "microservices-mesh-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "node_group_instance_types" {
  description = "Instance types for EKS managed node groups"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_capacity" {
  description = "Node group capacity configuration"
  type = object({
    min_size     = number
    max_size     = number
    desired_size = number
  })
  default = {
    min_size     = 3
    max_size     = 6
    desired_size = 3
  }
  
  validation {
    condition = var.node_group_capacity.min_size <= var.node_group_capacity.desired_size && var.node_group_capacity.desired_size <= var.node_group_capacity.max_size
    error_message = "Node group capacity must satisfy: min_size <= desired_size <= max_size."
  }
}

variable "node_group_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 20
  
  validation {
    condition = var.node_group_disk_size >= 20 && var.node_group_disk_size <= 1000
    error_message = "Node group disk size must be between 20 and 1000 GB."
  }
}

# VPC configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for the VPC"
  type        = list(string)
  default     = []
}

# App Mesh configuration
variable "app_mesh_name" {
  description = "Name of the App Mesh"
  type        = string
  default     = "microservices-mesh"
}

variable "mesh_namespace" {
  description = "Kubernetes namespace for microservices"
  type        = string
  default     = "production"
}

# Microservices configuration
variable "microservices" {
  description = "Configuration for microservices"
  type = map(object({
    replicas = number
    image    = string
  }))
  default = {
    service-a = {
      replicas = 2
      image    = "microservices-demo-service-a:latest"
    }
    service-b = {
      replicas = 2
      image    = "microservices-demo-service-b:latest"
    }
    service-c = {
      replicas = 2
      image    = "microservices-demo-service-c:latest"
    }
  }
}

# ECR configuration
variable "ecr_repository_prefix" {
  description = "Prefix for ECR repository names"
  type        = string
  default     = "microservices-demo"
}

variable "ecr_image_tag_mutability" {
  description = "The tag mutability setting for ECR repositories"
  type        = string
  default     = "MUTABLE"
  
  validation {
    condition = contains(["MUTABLE", "IMMUTABLE"], var.ecr_image_tag_mutability)
    error_message = "ECR image tag mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "ecr_scan_on_push" {
  description = "Indicates whether images are scanned after being pushed to ECR"
  type        = bool
  default     = true
}

# Observability configuration
variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

# Security configuration
variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "enable_encryption_at_rest" {
  description = "Enable encryption at rest for EKS cluster"
  type        = bool
  default     = true
}

# Load balancer configuration
variable "load_balancer_type" {
  description = "Type of load balancer to create"
  type        = string
  default     = "application"
  
  validation {
    condition = contains(["application", "network"], var.load_balancer_type)
    error_message = "Load balancer type must be either 'application' or 'network'."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancer"
  type        = bool
  default     = false
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}