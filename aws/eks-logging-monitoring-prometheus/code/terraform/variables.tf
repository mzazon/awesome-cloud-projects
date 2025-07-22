# Variables for EKS cluster logging and monitoring configuration

# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-observability-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "node_group_name" {
  description = "Name of the EKS node group"
  type        = string
  default     = "eks-observability-nodegroup"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "eks-observability"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

# EKS Node Group Configuration
variable "node_group_config" {
  description = "Configuration for EKS node group"
  type = object({
    instance_types = list(string)
    scaling_config = object({
      desired_size = number
      max_size     = number
      min_size     = number
    })
    disk_size = number
    ami_type  = string
  })
  default = {
    instance_types = ["t3.medium"]
    scaling_config = {
      desired_size = 2
      max_size     = 4
      min_size     = 2
    }
    disk_size = 30
    ami_type  = "AL2_x86_64"
  }
}

# Control Plane Logging Configuration
variable "control_plane_logging" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# Container Insights Configuration
variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for EKS cluster"
  type        = bool
  default     = true
}

# Prometheus Configuration
variable "prometheus_workspace_name" {
  description = "Name for Amazon Managed Service for Prometheus workspace"
  type        = string
  default     = "eks-prometheus-workspace"
}

variable "enable_prometheus" {
  description = "Enable Amazon Managed Service for Prometheus"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

# Alarm thresholds
variable "cpu_utilization_threshold" {
  description = "CPU utilization threshold for CloudWatch alarms"
  type        = number
  default     = 80
}

variable "memory_utilization_threshold" {
  description = "Memory utilization threshold for CloudWatch alarms"
  type        = number
  default     = 80
}

variable "failed_pods_threshold" {
  description = "Failed pods threshold for CloudWatch alarms"
  type        = number
  default     = 5
}

# Fluent Bit Configuration
variable "fluent_bit_config" {
  description = "Configuration for Fluent Bit log collection"
  type = object({
    image_tag       = string
    log_level       = string
    mem_buf_limit   = string
    read_from_head  = bool
  })
  default = {
    image_tag       = "stable"
    log_level       = "info"
    mem_buf_limit   = "50MB"
    read_from_head  = false
  }
}

# Sample Application Configuration
variable "deploy_sample_app" {
  description = "Deploy sample application with Prometheus metrics"
  type        = bool
  default     = true
}

variable "sample_app_config" {
  description = "Configuration for sample application"
  type = object({
    replicas = number
    image    = string
    tag      = string
  })
  default = {
    replicas = 2
    image    = "nginx"
    tag      = "1.21"
  }
}

# SNS Configuration for Alerts
variable "sns_endpoint" {
  description = "SNS endpoint for CloudWatch alarms (email address)"
  type        = string
  default     = ""
}

variable "enable_sns_alerts" {
  description = "Enable SNS alerts for CloudWatch alarms"
  type        = bool
  default     = false
}

# Resource tags
variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# OIDC Provider Configuration
variable "enable_irsa" {
  description = "Enable IAM roles for service accounts"
  type        = bool
  default     = true
}

# Security Configuration
variable "endpoint_config" {
  description = "EKS cluster endpoint configuration"
  type = object({
    private_access = bool
    public_access  = bool
    public_access_cidrs = list(string)
  })
  default = {
    private_access      = true
    public_access       = true
    public_access_cidrs = ["0.0.0.0/0"]
  }
}

# Monitoring Configuration
variable "monitoring_config" {
  description = "Additional monitoring configuration"
  type = object({
    enable_detailed_monitoring = bool
    metrics_collection_interval = number
    enable_logs_insights_queries = bool
  })
  default = {
    enable_detailed_monitoring   = true
    metrics_collection_interval  = 60
    enable_logs_insights_queries = true
  }
}