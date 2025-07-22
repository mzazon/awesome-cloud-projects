# Variables for Cloud Operations Automation with Gemini Cloud Assist and Hyperdisk ML

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "Name of the GKE cluster for ML operations"
  type        = string
  default     = "ml-ops-cluster"
}

variable "hyperdisk_name" {
  description = "Name of the Hyperdisk ML volume"
  type        = string
  default     = "ml-storage"
}

variable "hyperdisk_size_gb" {
  description = "Size of the Hyperdisk ML volume in GB"
  type        = number
  default     = 10240 # 10TB
  
  validation {
    condition     = var.hyperdisk_size_gb >= 64
    error_message = "Hyperdisk ML minimum size is 64GB."
  }
}

variable "hyperdisk_provisioned_throughput" {
  description = "Provisioned throughput for Hyperdisk ML in MiB/s"
  type        = number
  default     = 100000
  
  validation {
    condition     = var.hyperdisk_provisioned_throughput >= 1000
    error_message = "Hyperdisk ML minimum provisioned throughput is 1000 MiB/s."
  }
}

variable "cluster_machine_type" {
  description = "Machine type for GKE cluster nodes"
  type        = string
  default     = "c3-standard-4"
}

variable "cluster_min_nodes" {
  description = "Minimum number of nodes in the GKE cluster"
  type        = number
  default     = 1
}

variable "cluster_max_nodes" {
  description = "Maximum number of nodes in the GKE cluster"
  type        = number
  default     = 10
}

variable "cluster_initial_node_count" {
  description = "Initial number of nodes in the GKE cluster"
  type        = number
  default     = 2
}

variable "gpu_machine_type" {
  description = "Machine type for GPU node pool"
  type        = string
  default     = "g2-standard-4"
}

variable "gpu_accelerator_type" {
  description = "Type of GPU accelerator"
  type        = string
  default     = "nvidia-l4"
}

variable "gpu_accelerator_count" {
  description = "Number of GPU accelerators per node"
  type        = number
  default     = 1
}

variable "gpu_min_nodes" {
  description = "Minimum number of nodes in the GPU pool"
  type        = number
  default     = 0
}

variable "gpu_max_nodes" {
  description = "Maximum number of nodes in the GPU pool"
  type        = number
  default     = 5
}

variable "function_name" {
  description = "Name of the Cloud Function for ML operations automation"
  type        = string
  default     = "ml-ops-automation"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 512
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 540
}

variable "dataset_bucket_name" {
  description = "Name of the Cloud Storage bucket for ML datasets"
  type        = string
  default     = "ml-datasets"
}

variable "bucket_location" {
  description = "Location for Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
}

variable "scheduler_frequency" {
  description = "Frequency for automated ML operations scheduling (cron format)"
  type        = string
  default     = "*/15 * * * *"
}

variable "performance_monitor_frequency" {
  description = "Frequency for performance monitoring (cron format)"
  type        = string
  default     = "*/5 * * * *"
}

variable "enable_network_policy" {
  description = "Enable network policy for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_private_cluster" {
  description = "Enable private cluster configuration"
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master in private cluster"
  type        = string
  default     = "172.16.0.0/28"
}

variable "pods_ipv4_cidr_block" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_ipv4_cidr_block" {
  description = "CIDR block for services"
  type        = string
  default     = "10.2.0.0/16"
}

variable "enable_gemini_cloud_assist" {
  description = "Enable Gemini Cloud Assist features (requires private preview access)"
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "ml-ops"
    managed-by  = "terraform"
    recipe      = "cloud-operations-automation"
  }
}

variable "enable_monitoring_dashboards" {
  description = "Create custom monitoring dashboards"
  type        = bool
  default     = true
}

variable "enable_alerting_policies" {
  description = "Create alerting policies for ML workloads"
  type        = bool
  default     = true
}