# Project and Region Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the HPC cluster"
  type        = string
  default     = "video-analysis-cluster"
}

variable "cluster_machine_type" {
  description = "Machine type for compute nodes"
  type        = string
  default     = "c2-standard-16"
}

variable "gpu_machine_type" {
  description = "Machine type for GPU nodes"
  type        = string
  default     = "n1-standard-4"
}

variable "gpu_type" {
  description = "Type of GPU accelerator"
  type        = string
  default     = "nvidia-tesla-t4"
}

variable "max_compute_nodes" {
  description = "Maximum number of compute nodes in the cluster"
  type        = number
  default     = 10
}

variable "max_gpu_nodes" {
  description = "Maximum number of GPU nodes in the cluster"
  type        = number
  default     = 4
}

# Storage Configuration
variable "filestore_tier" {
  description = "Filestore tier for shared filesystem"
  type        = string
  default     = "HIGH_SCALE_SSD"
  validation {
    condition     = contains(["BASIC_HDD", "BASIC_SSD", "HIGH_SCALE_SSD"], var.filestore_tier)
    error_message = "Filestore tier must be one of: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD."
  }
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB"
  type        = number
  default     = 2560
}

variable "bucket_storage_class" {
  description = "Storage class for the data bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.bucket_storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# Vertex AI Configuration
variable "ai_region" {
  description = "Region for Vertex AI resources"
  type        = string
  default     = "us-central1"
}

variable "model_display_name" {
  description = "Display name for the fine-tuned model"
  type        = string
  default     = "scientific-video-gemini"
}

# BigQuery Configuration
variable "dataset_location" {
  description = "Location for BigQuery dataset"
  type        = string
  default     = "US"
}

variable "dataset_id" {
  description = "BigQuery dataset ID for storing analysis results"
  type        = string
  default     = "video_analysis_results"
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "video-analysis-network"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/16"
}

# Service Account Configuration
variable "service_account_id" {
  description = "ID for the service account used by compute instances"
  type        = string
  default     = "video-analysis-sa"
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for the cluster"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for the cluster"
  type        = bool
  default     = true
}

# Resource Labeling
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "scientific-computing"
    workload    = "video-analysis"
    managed-by  = "terraform"
  }
}

# Dataflow Configuration
variable "dataflow_template_gcs_path" {
  description = "GCS path for Dataflow template"
  type        = string
  default     = ""
}

variable "dataflow_temp_location" {
  description = "GCS path for Dataflow temporary files"
  type        = string
  default     = ""
}

variable "dataflow_staging_location" {
  description = "GCS path for Dataflow staging files"
  type        = string
  default     = ""
}