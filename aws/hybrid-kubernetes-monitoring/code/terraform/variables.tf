# ==============================================================================
# CORE CONFIGURATION VARIABLES
# ==============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z][a-z]-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-west-2)."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "owner" {
  description = "Owner of the infrastructure (for tagging and cost allocation)"
  type        = string
  default     = "platform-team"
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "hybrid-monitoring"
  
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ==============================================================================
# EKS CLUSTER CONFIGURATION
# ==============================================================================

variable "cluster_name" {
  description = "Name of the EKS cluster. If not provided, will be generated from project_name and environment"
  type        = string
  default     = ""
  
  validation {
    condition = var.cluster_name == "" || can(regex("^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$", var.cluster_name))
    error_message = "Cluster name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
  
  validation {
    condition = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format X.Y (e.g., 1.31)."
  }
}

variable "cluster_endpoint_private_access" {
  description = "Whether the Amazon EKS private API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  description = "List of EKS cluster control plane logging to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  
  validation {
    condition = alltrue([
      for log_type in var.cluster_enabled_log_types : 
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "Cluster log types must be one of: api, audit, authenticator, controllerManager, scheduler."
  }
}

variable "cluster_log_retention_days" {
  description = "Number of days to retain cluster logs in CloudWatch"
  type        = number
  default     = 14
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cluster_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

# ==============================================================================
# HYBRID NODE CONFIGURATION
# ==============================================================================

variable "remote_node_networks" {
  description = "List of CIDR blocks for remote hybrid nodes"
  type        = list(string)
  default     = ["10.100.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.remote_node_networks : 
      can(cidrhost(cidr, 0))
    ])
    error_message = "All remote node networks must be valid CIDR blocks."
  }
}

variable "remote_pod_networks" {
  description = "List of CIDR blocks for remote pods on hybrid nodes"
  type        = list(string)
  default     = ["10.101.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.remote_pod_networks : 
      can(cidrhost(cidr, 0))
    ])
    error_message = "All remote pod networks must be valid CIDR blocks."
  }
}

# ==============================================================================
# VPC AND NETWORKING CONFIGURATION
# ==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones to use. If empty, will use first 3 AZs in the region"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  
  validation {
    condition = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnets are required for EKS."
  }
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (for Fargate)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  
  validation {
    condition = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnets are required for Fargate."
  }
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway for all private subnets (cost optimization)"
  type        = bool
  default     = true
}

# ==============================================================================
# FARGATE CONFIGURATION
# ==============================================================================

variable "fargate_profile_name" {
  description = "Name of the Fargate profile for cloud workloads"
  type        = string
  default     = "cloud-workloads"
}

variable "fargate_namespace_selectors" {
  description = "List of namespace selectors for Fargate profile"
  type = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  default = [
    {
      namespace = "cloud-apps"
      labels    = {}
    },
    {
      namespace = "kube-system"
      labels = {
        "app.kubernetes.io/name" = "aws-load-balancer-controller"
      }
    }
  ]
}

# ==============================================================================
# CLOUDWATCH OBSERVABILITY CONFIGURATION
# ==============================================================================

variable "cloudwatch_addon_version" {
  description = "Version of the Amazon CloudWatch Observability addon"
  type        = string
  default     = "v2.1.0-eksbuild.1"
}

variable "container_insights_enabled" {
  description = "Whether to enable Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "application_signals_enabled" {
  description = "Whether to enable Application Signals (APM) for the cluster"
  type        = bool
  default     = false
}

variable "cloudwatch_dashboard_enabled" {
  description = "Whether to create CloudWatch dashboards for monitoring"
  type        = bool
  default     = true
}

variable "cloudwatch_alarms_enabled" {
  description = "Whether to create CloudWatch alarms for monitoring"
  type        = bool
  default     = true
}

variable "custom_metrics_namespace" {
  description = "CloudWatch namespace for custom metrics"
  type        = string
  default     = "EKS/HybridMonitoring"
}

# ==============================================================================
# MONITORING AND ALERTING CONFIGURATION
# ==============================================================================

variable "high_cpu_threshold" {
  description = "CPU utilization threshold for high CPU alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.high_cpu_threshold > 0 && var.high_cpu_threshold <= 100
    error_message = "CPU threshold must be between 1 and 100."
  }
}

variable "high_memory_threshold" {
  description = "Memory utilization threshold for high memory alarm (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition = var.high_memory_threshold > 0 && var.high_memory_threshold <= 100
    error_message = "Memory threshold must be between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for CloudWatch alarms"
  type        = number
  default     = 2
  
  validation {
    condition = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications. If not provided, alarms will be created without notifications"
  type        = string
  default     = ""
}

# ==============================================================================
# SECURITY CONFIGURATION
# ==============================================================================

variable "cluster_encryption_enabled" {
  description = "Whether to enable cluster encryption for secrets"
  type        = bool
  default     = true
}

variable "kms_key_deletion_window" {
  description = "Number of days to retain KMS key after deletion"
  type        = number
  default     = 30
  
  validation {
    condition = var.kms_key_deletion_window >= 7 && var.kms_key_deletion_window <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to the EKS cluster"
  type        = list(string)
  default     = []
}

# ==============================================================================
# ADDON CONFIGURATION
# ==============================================================================

variable "install_aws_load_balancer_controller" {
  description = "Whether to install AWS Load Balancer Controller addon"
  type        = bool
  default     = true
}

variable "install_ebs_csi_driver" {
  description = "Whether to install Amazon EBS CSI driver addon"
  type        = bool
  default     = true
}

variable "install_efs_csi_driver" {
  description = "Whether to install Amazon EFS CSI driver addon"
  type        = bool
  default     = false
}

# ==============================================================================
# SAMPLE APPLICATION CONFIGURATION
# ==============================================================================

variable "deploy_sample_applications" {
  description = "Whether to deploy sample applications for testing monitoring"
  type        = bool
  default     = true
}

variable "sample_app_replicas" {
  description = "Number of replicas for sample applications"
  type        = number
  default     = 2
  
  validation {
    condition = var.sample_app_replicas >= 1
    error_message = "Sample app replicas must be at least 1."
  }
}

# ==============================================================================
# COST OPTIMIZATION CONFIGURATION
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Whether to enable cost optimization features (single NAT gateway, etc.)"
  type        = bool
  default     = true
}

variable "enable_spot_instances" {
  description = "Whether to enable Spot instances for cost optimization (for managed node groups if added)"
  type        = bool
  default     = false
}

# ==============================================================================
# ADDITIONAL TAGS
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}