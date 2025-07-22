# Variables for the EKS Auto Scaling Infrastructure

# Basic Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "eks-autoscaling"
}

# EKS Cluster Configuration
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-autoscaling-demo"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
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
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

# Node Group Configuration
variable "general_purpose_node_group" {
  description = "Configuration for general purpose node group"
  type = object({
    name             = string
    instance_types   = list(string)
    capacity_type    = string
    ami_type         = string
    desired_size     = number
    max_size         = number
    min_size         = number
    disk_size        = number
    labels           = map(string)
  })
  default = {
    name             = "general-purpose"
    instance_types   = ["m5.large", "m5.xlarge"]
    capacity_type    = "ON_DEMAND"
    ami_type         = "AL2_x86_64"
    desired_size     = 2
    max_size         = 10
    min_size         = 1
    disk_size        = 20
    labels = {
      "workload-type" = "general"
    }
  }
}

variable "compute_optimized_node_group" {
  description = "Configuration for compute optimized node group"
  type = object({
    name             = string
    instance_types   = list(string)
    capacity_type    = string
    ami_type         = string
    desired_size     = number
    max_size         = number
    min_size         = number
    disk_size        = number
    labels           = map(string)
  })
  default = {
    name             = "compute-optimized"
    instance_types   = ["c5.large", "c5.xlarge"]
    capacity_type    = "ON_DEMAND"
    ami_type         = "AL2_x86_64"
    desired_size     = 1
    max_size         = 5
    min_size         = 0
    disk_size        = 20
    labels = {
      "workload-type" = "compute"
    }
  }
}

# Cluster Autoscaler Configuration
variable "cluster_autoscaler_image_tag" {
  description = "Cluster Autoscaler image tag"
  type        = string
  default     = "v1.28.2"
}

variable "cluster_autoscaler_settings" {
  description = "Cluster Autoscaler configuration settings"
  type = object({
    scale_down_delay_after_add       = string
    scale_down_unneeded_time        = string
    scale_down_delay_after_delete   = string
    scale_down_utilization_threshold = string
    skip_nodes_with_local_storage   = bool
    skip_nodes_with_system_pods     = bool
    expander                        = string
    balance_similar_node_groups     = bool
  })
  default = {
    scale_down_delay_after_add       = "10m"
    scale_down_unneeded_time        = "10m"
    scale_down_delay_after_delete   = "10s"
    scale_down_utilization_threshold = "0.5"
    skip_nodes_with_local_storage   = false
    skip_nodes_with_system_pods     = false
    expander                        = "least-waste"
    balance_similar_node_groups     = true
  }
}

# Monitoring Configuration
variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}

variable "enable_grafana" {
  description = "Enable Grafana dashboards"
  type        = bool
  default     = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  default     = "admin123"
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "7d"
}

variable "prometheus_storage_size" {
  description = "Prometheus storage size"
  type        = string
  default     = "20Gi"
}

variable "grafana_storage_size" {
  description = "Grafana storage size"
  type        = string
  default     = "10Gi"
}

# KEDA Configuration
variable "enable_keda" {
  description = "Enable KEDA for custom metrics scaling"
  type        = bool
  default     = true
}

variable "keda_namespace" {
  description = "Namespace for KEDA installation"
  type        = string
  default     = "keda-system"
}

# Demo Applications Configuration
variable "deploy_demo_applications" {
  description = "Deploy demo applications for testing"
  type        = bool
  default     = true
}

variable "demo_namespace" {
  description = "Namespace for demo applications"
  type        = string
  default     = "demo-apps"
}

# VPA Configuration
variable "enable_vpa" {
  description = "Enable Vertical Pod Autoscaler"
  type        = bool
  default     = false
}

# EKS Addons Configuration
variable "eks_addons" {
  description = "EKS addons to install"
  type = map(object({
    version                  = string
    resolve_conflicts        = string
    service_account_role_arn = string
  }))
  default = {
    coredns = {
      version                  = "v1.10.1-eksbuild.4"
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = null
    }
    kube-proxy = {
      version                  = "v1.28.2-eksbuild.2"
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = null
    }
    vpc-cni = {
      version                  = "v1.15.1-eksbuild.1"
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = null
    }
    aws-ebs-csi-driver = {
      version                  = "v1.24.0-eksbuild.1"
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = null
    }
  }
}

# Random suffix for unique resource names
variable "random_suffix_length" {
  description = "Length of random suffix for resource names"
  type        = number
  default     = 6
}