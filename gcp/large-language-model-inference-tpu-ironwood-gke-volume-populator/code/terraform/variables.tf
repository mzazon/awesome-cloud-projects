# ================================================================
# Variables for Large Language Model Inference with TPU Ironwood
# 
# This file defines all configurable parameters for deploying
# a high-performance LLM inference pipeline using TPU Ironwood
# accelerators with GKE Volume Populator integration.
# ================================================================

# ----------------------------------------------------------------
# Project and Location Configuration
# ----------------------------------------------------------------
variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region with TPU support."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (must support TPU Ironwood)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = contains([
      "us-central1-a", "us-central1-b", "us-central1-c", "us-central1-f",
      "us-east1-b", "us-east1-c", "us-east1-d",
      "us-west1-a", "us-west1-b", "us-west1-c",
      "europe-west1-b", "europe-west1-c", "europe-west1-d",
      "asia-east1-a", "asia-east1-b", "asia-east1-c"
    ], var.zone)
    error_message = "Zone must support TPU Ironwood accelerators."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and organization"
  type        = string
  default     = "development"
  
  validation {
    condition = contains([
      "development", "staging", "production", "test"
    ], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

# ----------------------------------------------------------------
# GKE Cluster Configuration
# ----------------------------------------------------------------
variable "cluster_name" {
  description = "Name prefix for the GKE cluster"
  type        = string
  default     = "tpu-ironwood-cluster"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_ipv4_cidr" {
  description = "CIDR block for cluster pods"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.cluster_ipv4_cidr, 0))
    error_message = "Cluster IPv4 CIDR must be a valid CIDR block."
  }
}

variable "services_ipv4_cidr" {
  description = "CIDR block for cluster services"
  type        = string
  default     = "10.2.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.services_ipv4_cidr, 0))
    error_message = "Services IPv4 CIDR must be a valid CIDR block."
  }
}

variable "maintenance_start_time" {
  description = "Daily maintenance window start time (HH:MM format in UTC)"
  type        = string
  default     = "03:00"
  
  validation {
    condition     = can(regex("^([01]?[0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_start_time))
    error_message = "Maintenance start time must be in HH:MM format (24-hour UTC)."
  }
}

# ----------------------------------------------------------------
# Standard Node Pool Configuration
# ----------------------------------------------------------------
variable "standard_machine_type" {
  description = "Machine type for standard node pool"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16",
      "c2-standard-4", "c2-standard-8", "c2-standard-16"
    ], var.standard_machine_type)
    error_message = "Standard machine type must be a valid Google Cloud machine type."
  }
}

variable "standard_node_count" {
  description = "Initial number of nodes in the standard pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.standard_node_count >= 1 && var.standard_node_count <= 10
    error_message = "Standard node count must be between 1 and 10."
  }
}

variable "standard_min_nodes" {
  description = "Minimum number of nodes in standard pool autoscaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.standard_min_nodes >= 1 && var.standard_min_nodes <= 100
    error_message = "Standard minimum nodes must be between 1 and 100."
  }
}

variable "standard_max_nodes" {
  description = "Maximum number of nodes in standard pool autoscaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.standard_max_nodes >= 1 && var.standard_max_nodes <= 100
    error_message = "Standard maximum nodes must be between 1 and 100."
  }
}

# ----------------------------------------------------------------
# TPU Node Pool Configuration
# ----------------------------------------------------------------
variable "tpu_machine_type" {
  description = "Machine type for TPU node pool (must support TPU attachment)"
  type        = string
  default     = "n1-standard-8"
  
  validation {
    condition = contains([
      "n1-standard-8", "n1-standard-16", "n1-standard-32",
      "n2-standard-8", "n2-standard-16", "n2-standard-32",
      "c2-standard-8", "c2-standard-16", "c2-standard-30"
    ], var.tpu_machine_type)
    error_message = "TPU machine type must support TPU attachment."
  }
}

variable "tpu_accelerator_type" {
  description = "TPU accelerator type (TPU Ironwood v7)"
  type        = string
  default     = "tpu-v7-pod-slice"
  
  validation {
    condition = contains([
      "tpu-v7-pod-slice", "tpu-v7-podslice", "tpu-ironwood-v7"
    ], var.tpu_accelerator_type)
    error_message = "TPU accelerator type must be a valid TPU Ironwood variant."
  }
}

variable "tpu_accelerator_count" {
  description = "Number of TPU accelerators per node (typically 8 for TPU v7 pods)"
  type        = number
  default     = 8
  
  validation {
    condition     = contains([2, 4, 8, 16, 32], var.tpu_accelerator_count)
    error_message = "TPU accelerator count must be 2, 4, 8, 16, or 32."
  }
}

variable "tpu_node_count" {
  description = "Initial number of nodes in the TPU pool"
  type        = number
  default     = 1
  
  validation {
    condition     = var.tpu_node_count >= 1 && var.tpu_node_count <= 5
    error_message = "TPU node count must be between 1 and 5."
  }
}

variable "tpu_min_nodes" {
  description = "Minimum number of nodes in TPU pool autoscaling"
  type        = number
  default     = 0
  
  validation {
    condition     = var.tpu_min_nodes >= 0 && var.tpu_min_nodes <= 10
    error_message = "TPU minimum nodes must be between 0 and 10."
  }
}

variable "tpu_max_nodes" {
  description = "Maximum number of nodes in TPU pool autoscaling"
  type        = number
  default     = 3
  
  validation {
    condition     = var.tpu_max_nodes >= 1 && var.tpu_max_nodes <= 10
    error_message = "TPU maximum nodes must be between 1 and 10."
  }
}

# ----------------------------------------------------------------
# Cloud Storage Configuration
# ----------------------------------------------------------------
variable "bucket_name_prefix" {
  description = "Prefix for the Cloud Storage bucket name (random suffix will be added)"
  type        = string
  default     = "llm-models"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must contain only lowercase letters, numbers, and hyphens."
  }
}

# ----------------------------------------------------------------
# Parallelstore Configuration
# ----------------------------------------------------------------
variable "parallelstore_name" {
  description = "Name prefix for the Parallelstore instance"
  type        = string
  default     = "model-storage"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.parallelstore_name))
    error_message = "Parallelstore name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "parallelstore_capacity_gib" {
  description = "Capacity of Parallelstore instance in GiB (minimum 1024 GiB)"
  type        = number
  default     = 1024
  
  validation {
    condition     = var.parallelstore_capacity_gib >= 1024 && var.parallelstore_capacity_gib <= 100000
    error_message = "Parallelstore capacity must be between 1024 GiB and 100,000 GiB."
  }
}

variable "parallelstore_performance_tier" {
  description = "Performance tier for Parallelstore (SSD or HDD)"
  type        = string
  default     = "SSD"
  
  validation {
    condition     = contains(["SSD", "HDD"], var.parallelstore_performance_tier)
    error_message = "Parallelstore performance tier must be either SSD or HDD."
  }
}

# ----------------------------------------------------------------
# IAM and Security Configuration
# ----------------------------------------------------------------
variable "service_account_name" {
  description = "Name prefix for the TPU inference service account"
  type        = string
  default     = "tpu-inference-sa"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for workload identity binding"
  type        = string
  default     = "default"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.k8s_namespace))
    error_message = "Kubernetes namespace must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "k8s_service_account" {
  description = "Kubernetes service account name for workload identity"
  type        = string
  default     = "tpu-inference-pod"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.k8s_service_account))
    error_message = "Kubernetes service account name must contain only lowercase letters, numbers, and hyphens."
  }
}

# ----------------------------------------------------------------
# Model Configuration
# ----------------------------------------------------------------
variable "model_name" {
  description = "Name of the LLM model for labeling and organization"
  type        = string
  default     = "llm-7b"
  
  validation {
    condition     = length(var.model_name) > 0 && length(var.model_name) <= 50
    error_message = "Model name must be between 1 and 50 characters."
  }
}

variable "model_version" {
  description = "Version of the LLM model"
  type        = string
  default     = "v1.0"
  
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+$", var.model_version))
    error_message = "Model version must follow semantic versioning format (e.g., v1.0, v2.1)."
  }
}

# ----------------------------------------------------------------
# Cost and Resource Management
# ----------------------------------------------------------------
variable "enable_cost_optimization" {
  description = "Enable cost optimization features (preemptible nodes, automated scaling)"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies for enhanced security"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

# ----------------------------------------------------------------
# Advanced Configuration
# ----------------------------------------------------------------
variable "custom_labels" {
  description = "Additional custom labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.custom_labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k))
    ])
    error_message = "Custom label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "node_pool_taints" {
  description = "Additional taints to apply to TPU node pool"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
  
  validation {
    condition = alltrue([
      for taint in var.node_pool_taints : contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], taint.effect)
    ])
    error_message = "Taint effect must be one of: NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE."
  }
}