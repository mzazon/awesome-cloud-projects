# Variable definitions for Privacy-Preserving Analytics with Confidential GKE and BigQuery
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "cluster_name" {
  description = "Name for the Confidential GKE cluster"
  type        = string
  default     = null
  validation {
    condition = var.cluster_name == null || (
      length(var.cluster_name) >= 1 && length(var.cluster_name) <= 40 &&
      can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", var.cluster_name))
    )
    error_message = "Cluster name must be 1-40 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "keyring_name" {
  description = "Name for the Cloud KMS key ring"
  type        = string
  default     = null
  validation {
    condition = var.keyring_name == null || (
      length(var.keyring_name) >= 1 && length(var.keyring_name) <= 63 &&
      can(regex("^[a-zA-Z0-9_-]+$", var.keyring_name))
    )
    error_message = "Keyring name must be 1-63 characters and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "key_name" {
  description = "Name for the Cloud KMS encryption key"
  type        = string
  default     = null
  validation {
    condition = var.key_name == null || (
      length(var.key_name) >= 1 && length(var.key_name) <= 63 &&
      can(regex("^[a-zA-Z0-9_-]+$", var.key_name))
    )
    error_message = "Key name must be 1-63 characters and contain only letters, numbers, underscores, and hyphens."
  }
}

variable "dataset_name" {
  description = "Name for the BigQuery dataset"
  type        = string
  default     = null
  validation {
    condition = var.dataset_name == null || (
      length(var.dataset_name) >= 1 && length(var.dataset_name) <= 1024 &&
      can(regex("^[a-zA-Z0-9_]+$", var.dataset_name))
    )
    error_message = "Dataset name must be 1-1024 characters and contain only letters, numbers, and underscores."
  }
}

variable "bucket_name" {
  description = "Name for the Cloud Storage bucket"
  type        = string
  default     = null
  validation {
    condition = var.bucket_name == null || (
      length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.bucket_name))
    )
    error_message = "Bucket name must be 3-63 characters, start and end with alphanumeric, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "confidential_node_type" {
  description = "Type of confidential computing nodes to use"
  type        = string
  default     = "sev"
  validation {
    condition     = contains(["sev", "tdx"], var.confidential_node_type)
    error_message = "Confidential node type must be either 'sev' or 'tdx'."
  }
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "n2d-standard-4"
  validation {
    condition = contains([
      "n2d-standard-2", "n2d-standard-4", "n2d-standard-8", "n2d-standard-16",
      "n2d-highmem-2", "n2d-highmem-4", "n2d-highmem-8", "n2d-highmem-16",
      "n2d-highcpu-16", "n2d-highcpu-32", "n2d-highcpu-48", "n2d-highcpu-64"
    ], var.machine_type)
    error_message = "Machine type must be a supported N2D instance type for confidential computing."
  }
}

variable "node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
  default     = 2
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
  validation {
    condition     = var.min_node_count >= 0 && var.min_node_count <= 100
    error_message = "Minimum node count must be between 0 and 100."
  }
}

variable "max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 10
  validation {
    condition     = var.max_node_count >= 1 && var.max_node_count <= 1000
    error_message = "Maximum node count must be between 1 and 1000."
  }
}

variable "enable_private_nodes" {
  description = "Enable private nodes for additional security"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private cluster endpoint"
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the master network"
  type        = string
  default     = "172.16.0.0/28"
  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "Master IPv4 CIDR block must be a valid CIDR notation."
  }
}

variable "pods_secondary_range_name" {
  description = "Name for the secondary range for pods"
  type        = string
  default     = "gke-pods"
}

variable "pods_secondary_range_cidr" {
  description = "CIDR range for pods"
  type        = string
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.pods_secondary_range_cidr, 0))
    error_message = "Pods secondary range CIDR must be a valid CIDR notation."
  }
}

variable "services_secondary_range_name" {
  description = "Name for the secondary range for services"
  type        = string
  default     = "gke-services"
}

variable "services_secondary_range_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.2.0.0/16"
  validation {
    condition     = can(cidrhost(var.services_secondary_range_cidr, 0))
    error_message = "Services secondary range CIDR must be a valid CIDR notation."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
  default     = "latest"
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for secure pod-to-service authentication"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policy"
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Disk size in GB for cluster nodes"
  type        = number
  default     = 100
  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 64000
    error_message = "Disk size must be between 10 and 64000 GB."
  }
}

variable "disk_type" {
  description = "Disk type for cluster nodes"
  type        = string
  default     = "pd-standard"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

variable "preemptible" {
  description = "Use preemptible nodes to reduce costs"
  type        = bool
  default     = false
}

variable "oauth_scopes" {
  description = "OAuth scopes for GKE nodes"
  type        = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/devstorage.read_only"
  ]
}

variable "create_sample_data" {
  description = "Create sample healthcare data for testing"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container image security"
  type        = bool
  default     = false
}

variable "maintenance_start_time" {
  description = "Start time for cluster maintenance window in RFC3339 format"
  type        = string
  default     = "2023-01-01T03:00:00Z"
  validation {
    condition     = can(formatdate("RFC3339", var.maintenance_start_time))
    error_message = "Maintenance start time must be in valid RFC3339 format."
  }
}

variable "maintenance_end_time" {
  description = "End time for cluster maintenance window in RFC3339 format"
  type        = string
  default     = "2023-01-01T07:00:00Z"
  validation {
    condition     = can(formatdate("RFC3339", var.maintenance_end_time))
    error_message = "Maintenance end time must be in valid RFC3339 format."
  }
}

variable "resource_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "privacy-analytics"
    managed-by  = "terraform"
    project     = "confidential-computing"
  }
  validation {
    condition = alltrue([
      for k, v in var.resource_labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must be lowercase alphanumeric with underscores and hyphens, max 63 characters."
  }
}

variable "notification_email" {
  description = "Email for monitoring and alerting notifications"
  type        = string
  default     = ""
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address or empty string."
  }
}

variable "deploy_sample_application" {
  description = "Deploy the privacy-preserving analytics sample application"
  type        = bool
  default     = true
}

variable "enable_autopilot" {
  description = "Use GKE Autopilot mode for managed infrastructure"
  type        = bool
  default     = false
}