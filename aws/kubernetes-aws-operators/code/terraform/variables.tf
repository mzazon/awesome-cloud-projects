# Core configuration variables
variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-west-2)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "ack-operators"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# EKS cluster configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = ""
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"

  validation {
    condition = can(regex("^1\\.(2[4-9]|[3-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be 1.24 or higher."
  }
}

variable "create_eks_cluster" {
  description = "Whether to create a new EKS cluster or use existing one"
  type        = bool
  default     = true
}

# VPC and networking configuration
variable "vpc_id" {
  description = "VPC ID for EKS cluster (required if create_eks_cluster is true)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for EKS cluster (required if create_eks_cluster is true)"
  type        = list(string)
  default     = []
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (used when creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones for VPC subnets"
  type        = list(string)
  default     = []
}

# ACK controller configuration
variable "ack_controllers" {
  description = "Map of ACK controllers to install"
  type = map(object({
    enabled     = bool
    version     = string
    namespace   = string
    chart_name  = string
  }))
  default = {
    s3 = {
      enabled    = true
      version    = "1.0.9"
      namespace  = "ack-system"
      chart_name = "s3-chart"
    }
    iam = {
      enabled    = true
      version    = "1.3.6"
      namespace  = "ack-system"
      chart_name = "iam-chart"
    }
    lambda = {
      enabled    = true
      version    = "1.4.3"
      namespace  = "ack-system"
      chart_name = "lambda-chart"
    }
  }
}

variable "ack_system_namespace" {
  description = "Namespace for ACK controllers"
  type        = string
  default     = "ack-system"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.ack_system_namespace))
    error_message = "Namespace must contain only lowercase letters, numbers, and hyphens."
  }
}

# Custom operator configuration
variable "operator_namespace" {
  description = "Namespace for custom platform operator"
  type        = string
  default     = "platform-operator-system"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.operator_namespace))
    error_message = "Namespace must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "operator_image" {
  description = "Container image for custom platform operator"
  type        = string
  default     = "platform-operator:latest"
}

variable "operator_replicas" {
  description = "Number of replicas for custom operator"
  type        = number
  default     = 2

  validation {
    condition     = var.operator_replicas > 0
    error_message = "Operator replicas must be greater than 0."
  }
}

# Node group configuration
variable "node_group_config" {
  description = "Configuration for EKS node groups"
  type = object({
    instance_types = list(string)
    capacity_type  = string
    min_size      = number
    max_size      = number
    desired_size  = number
    disk_size     = number
  })
  default = {
    instance_types = ["t3.medium", "t3.large"]
    capacity_type  = "ON_DEMAND"
    min_size      = 1
    max_size      = 5
    desired_size  = 2
    disk_size     = 20
  }

  validation {
    condition = contains(["ON_DEMAND", "SPOT"], var.node_group_config.capacity_type)
    error_message = "Capacity type must be either ON_DEMAND or SPOT."
  }
}

# IRSA (IAM Roles for Service Accounts) configuration
variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

# Monitoring and observability
variable "enable_monitoring" {
  description = "Enable monitoring and metrics collection"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable EKS control plane logging"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7

  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# Application testing configuration
variable "deploy_sample_application" {
  description = "Whether to deploy a sample application for testing"
  type        = bool
  default     = true
}

variable "sample_app_config" {
  description = "Configuration for sample application"
  type = object({
    name             = string
    environment      = string
    storage_class    = string
    lambda_runtime   = string
    enable_logging   = bool
  })
  default = {
    name            = "sample-app"
    environment     = "dev"
    storage_class   = "STANDARD"
    lambda_runtime  = "python3.9"
    enable_logging  = true
  }
}

# Security configuration
variable "enable_network_policy" {
  description = "Enable Kubernetes Network Policies"
  type        = bool
  default     = true
}

variable "enable_pod_security_policy" {
  description = "Enable Pod Security Policies"
  type        = bool
  default     = false
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}