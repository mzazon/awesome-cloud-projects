# Variables for the code quality gates pipeline infrastructure

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
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "repository_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = "sample-app"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.repository_name))
    error_message = "Repository name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "cluster_name" {
  description = "Name of the GKE cluster for deployments"
  type        = string
  default     = "quality-gates-cluster"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "pipeline_name" {
  description = "Name of the Cloud Deploy pipeline"
  type        = string
  default     = "quality-pipeline"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.pipeline_name))
    error_message = "Pipeline name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "registry_name" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "app-registry"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.registry_name))
    error_message = "Registry name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment_namespaces" {
  description = "Kubernetes namespaces for different environments"
  type        = list(string)
  default     = ["development", "staging", "production"]
  validation {
    condition     = length(var.environment_namespaces) >= 2
    error_message = "At least two environment namespaces must be specified."
  }
}

variable "gke_node_count" {
  description = "Number of nodes in the GKE cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-2"
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2", "n2-standard-4"
    ], var.gke_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "gke_disk_size_gb" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 30
  validation {
    condition     = var.gke_disk_size_gb >= 10 && var.gke_disk_size_gb <= 65536
    error_message = "Disk size must be between 10 and 65536 GB."
  }
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for the GKE cluster"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for the GKE cluster"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for the GKE cluster"
  type        = bool
  default     = true
}

variable "enable_shielded_nodes" {
  description = "Enable shielded nodes for the GKE cluster"
  type        = bool
  default     = true
}

variable "cloud_build_timeout" {
  description = "Timeout for Cloud Build in seconds"
  type        = string
  default     = "1200s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.cloud_build_timeout))
    error_message = "Timeout must be specified in seconds format (e.g., '1200s')."
  }
}

variable "github_repo_owner" {
  description = "GitHub repository owner (if using GitHub instead of Cloud Source Repositories)"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name (if using GitHub instead of Cloud Source Repositories)"
  type        = string
  default     = ""
}

variable "build_trigger_branch_pattern" {
  description = "Branch pattern for Cloud Build trigger"
  type        = string
  default     = "^main$"
}

variable "enable_vulnerability_scanning" {
  description = "Enable container vulnerability scanning"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "code-quality-pipeline"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}