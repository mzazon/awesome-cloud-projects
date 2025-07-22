# General Configuration Variables
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format 'us-west-2'."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "demo-mesh"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
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

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "microservices-eks-service-mesh"
    Environment = "demo"
    ManagedBy   = "terraform"
    Recipe      = "microservices-eks-service-mesh-app-mesh"
  }
}

# EKS Cluster Configuration
variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"

  validation {
    condition     = can(regex("^1\\.(2[0-9]|[3-9][0-9])$", var.cluster_version))
    error_message = "Cluster version must be a valid Kubernetes version (e.g., 1.28)."
  }
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Node Group Configuration
variable "node_group_instance_types" {
  description = "Instance types for the EKS node group"
  type        = list(string)
  default     = ["m5.large", "m5.xlarge"]
}

variable "node_group_desired_capacity" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 3

  validation {
    condition     = var.node_group_desired_capacity >= 1 && var.node_group_desired_capacity <= 10
    error_message = "Node group desired capacity must be between 1 and 10."
  }
}

variable "node_group_min_capacity" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1

  validation {
    condition     = var.node_group_min_capacity >= 1
    error_message = "Node group minimum capacity must be at least 1."
  }
}

variable "node_group_max_capacity" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 4

  validation {
    condition     = var.node_group_max_capacity >= 1 && var.node_group_max_capacity <= 20
    error_message = "Node group maximum capacity must be between 1 and 20."
  }
}

variable "node_group_disk_size" {
  description = "Disk size for the node group instances (in GB)"
  type        = number
  default     = 50

  validation {
    condition     = var.node_group_disk_size >= 20 && var.node_group_disk_size <= 200
    error_message = "Node group disk size must be between 20 and 200 GB."
  }
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for EKS."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for ALB."
  }
}

# App Mesh Configuration
variable "mesh_name" {
  description = "Name of the App Mesh service mesh"
  type        = string
  default     = "demo-mesh"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.mesh_name))
    error_message = "Mesh name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "app_namespace" {
  description = "Kubernetes namespace for the demo applications"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.app_namespace))
    error_message = "Namespace must contain only lowercase letters, numbers, and hyphens."
  }
}

# Container Registry Configuration
variable "create_ecr_repositories" {
  description = "Whether to create ECR repositories for the demo applications"
  type        = bool
  default     = true
}

variable "ecr_repositories" {
  description = "List of ECR repository names to create"
  type        = list(string)
  default     = ["frontend", "backend", "database"]
}

# Application Configuration
variable "frontend_replicas" {
  description = "Number of frontend application replicas"
  type        = number
  default     = 2

  validation {
    condition     = var.frontend_replicas >= 1 && var.frontend_replicas <= 10
    error_message = "Frontend replicas must be between 1 and 10."
  }
}

variable "backend_replicas" {
  description = "Number of backend application replicas"
  type        = number
  default     = 3

  validation {
    condition     = var.backend_replicas >= 1 && var.backend_replicas <= 10
    error_message = "Backend replicas must be between 1 and 10."
  }
}

variable "database_replicas" {
  description = "Number of database application replicas"
  type        = number
  default     = 1

  validation {
    condition     = var.database_replicas >= 1 && var.database_replicas <= 3
    error_message = "Database replicas must be between 1 and 3."
  }
}

# Load Balancer Configuration
variable "enable_alb_ingress" {
  description = "Whether to create an ALB ingress for the frontend service"
  type        = bool
  default     = true
}

variable "alb_scheme" {
  description = "ALB scheme (internet-facing or internal)"
  type        = string
  default     = "internet-facing"

  validation {
    condition     = contains(["internet-facing", "internal"], var.alb_scheme)
    error_message = "ALB scheme must be either 'internet-facing' or 'internal'."
  }
}

# Monitoring and Observability
variable "enable_xray_tracing" {
  description = "Whether to enable AWS X-Ray distributed tracing"
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Whether to enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

# Canary Deployment Configuration
variable "enable_canary_deployment" {
  description = "Whether to deploy a second version of backend for canary testing"
  type        = bool
  default     = true
}

variable "canary_traffic_percentage" {
  description = "Percentage of traffic to route to canary version (0-100)"
  type        = number
  default     = 10

  validation {
    condition     = var.canary_traffic_percentage >= 0 && var.canary_traffic_percentage <= 100
    error_message = "Canary traffic percentage must be between 0 and 100."
  }
}

variable "primary_traffic_percentage" {
  description = "Percentage of traffic to route to primary version (0-100)"
  type        = number
  default     = 90

  validation {
    condition     = var.primary_traffic_percentage >= 0 && var.primary_traffic_percentage <= 100
    error_message = "Primary traffic percentage must be between 0 and 100."
  }
}

# Security Configuration
variable "enable_irsa" {
  description = "Whether to enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "enable_pod_security_policy" {
  description = "Whether to enable pod security policies"
  type        = bool
  default     = false
}

# Backup and Recovery
variable "enable_cluster_backup" {
  description = "Whether to enable automated EKS cluster backup"
  type        = bool
  default     = false
}