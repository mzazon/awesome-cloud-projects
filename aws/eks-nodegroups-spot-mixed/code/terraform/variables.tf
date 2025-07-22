# AWS Configuration
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "production"
}

# EKS Cluster Configuration
variable "cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "Cluster name must not be empty."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.28"
}

# Node Group Configuration
variable "node_group_name_prefix" {
  description = "Prefix for node group names"
  type        = string
  default     = "cost-optimized"
}

# Spot Node Group Configuration
variable "spot_node_group_config" {
  description = "Configuration for spot instance node group"
  type = object({
    min_size       = number
    max_size       = number
    desired_size   = number
    instance_types = list(string)
    disk_size      = number
    ami_type       = string
  })
  default = {
    min_size       = 2
    max_size       = 10
    desired_size   = 4
    instance_types = ["m5.large", "m5a.large", "c5.large", "c5a.large", "m5.xlarge", "c5.xlarge"]
    disk_size      = 30
    ami_type       = "AL2_x86_64"
  }
}

# On-Demand Node Group Configuration
variable "ondemand_node_group_config" {
  description = "Configuration for on-demand instance node group"
  type = object({
    min_size       = number
    max_size       = number
    desired_size   = number
    instance_types = list(string)
    disk_size      = number
    ami_type       = string
  })
  default = {
    min_size       = 1
    max_size       = 3
    desired_size   = 2
    instance_types = ["m5.large", "c5.large"]
    disk_size      = 30
    ami_type       = "AL2_x86_64"
  }
}

# Node Group IAM Configuration
variable "node_group_additional_policies" {
  description = "Additional IAM policies to attach to node groups"
  type        = list(string)
  default     = []
}

# Networking Configuration
variable "subnet_ids" {
  description = "List of subnet IDs for the node groups (if not provided, will use cluster subnets)"
  type        = list(string)
  default     = []
}

# Taints and Labels
variable "spot_node_taints" {
  description = "Taints to apply to spot instances"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = [
    {
      key    = "node-type"
      value  = "spot"
      effect = "NO_SCHEDULE"
    }
  ]
}

variable "spot_node_labels" {
  description = "Labels to apply to spot nodes"
  type        = map(string)
  default = {
    "node-type"          = "spot"
    "cost-optimization"  = "enabled"
    "workload-type"      = "fault-tolerant"
  }
}

variable "ondemand_node_labels" {
  description = "Labels to apply to on-demand nodes"
  type        = map(string)
  default = {
    "node-type"      = "on-demand"
    "workload-type"  = "critical"
  }
}

# Autoscaling Configuration
variable "enable_cluster_autoscaler" {
  description = "Enable cluster autoscaler installation"
  type        = bool
  default     = true
}

variable "cluster_autoscaler_version" {
  description = "Version of cluster autoscaler to install"
  type        = string
  default     = "v1.28.2"
}

# Node Termination Handler Configuration
variable "enable_node_termination_handler" {
  description = "Enable AWS Node Termination Handler installation"
  type        = bool
  default     = true
}

variable "node_termination_handler_version" {
  description = "Version of AWS Node Termination Handler to install"
  type        = string
  default     = "v1.21.0"
}

# Monitoring Configuration
variable "enable_cost_monitoring" {
  description = "Enable cost monitoring and CloudWatch alarms"
  type        = bool
  default     = true
}

variable "spot_interruption_threshold" {
  description = "Threshold for spot interruption rate alarm"
  type        = number
  default     = 5
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for cost monitoring alerts (optional)"
  type        = string
  default     = ""
}

# Additional Configuration
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (will be retrieved automatically if not provided)"
  type        = string
  default     = ""
}