# Variables for GitOps Development Workflow Infrastructure
# This file defines all input variables for configuring the GitOps infrastructure

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
      "us-central1", "us-west1", "us-west2", "us-east1", "us-east4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name_prefix" {
  description = "Prefix for GKE cluster names"
  type        = string
  default     = "gitops-cluster"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name_prefix))
    error_message = "Cluster name prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "workstation_config_prefix" {
  description = "Prefix for Cloud Workstation configuration names"
  type        = string
  default     = "dev-config"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workstation_config_prefix))
    error_message = "Workstation config prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "app_repo_name" {
  description = "Name for the application source repository"
  type        = string
  default     = "hello-app"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_repo_name))
    error_message = "Repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "env_repo_name" {
  description = "Name for the environment configuration repository"
  type        = string
  default     = "hello-env"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.env_repo_name))
    error_message = "Repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "artifact_registry_repo_name" {
  description = "Name for the Artifact Registry repository"
  type        = string
  default     = "gitops-images"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.artifact_registry_repo_name))
    error_message = "Artifact Registry repository name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "workstation_machine_type" {
  description = "Machine type for Cloud Workstation instances"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8",
      "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.workstation_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "workstation_disk_size_gb" {
  description = "Persistent disk size in GB for Cloud Workstation instances"
  type        = number
  default     = 100
  
  validation {
    condition     = var.workstation_disk_size_gb >= 50 && var.workstation_disk_size_gb <= 3000
    error_message = "Disk size must be between 50 GB and 3000 GB."
  }
}

variable "workstation_container_image" {
  description = "Container image for Cloud Workstation instances"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
}

variable "gke_node_count" {
  description = "Initial number of nodes in each GKE cluster node pool"
  type        = number
  default     = 1
  
  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "gke_node_machine_type" {
  description = "Machine type for GKE cluster nodes"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4"
    ], var.gke_node_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type suitable for GKE."
  }
}

variable "gke_autopilot_enabled" {
  description = "Whether to use GKE Autopilot mode for simplified cluster management"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Whether to enable network policy for GKE clusters"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Whether to enable Workload Identity for secure pod-to-GCP service authentication"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Whether to enable Binary Authorization for container image security"
  type        = bool
  default     = false
}

variable "enable_vulnerability_scanning" {
  description = "Whether to enable container vulnerability scanning in Artifact Registry"
  type        = bool
  default     = true
}

variable "cloud_build_trigger_filename" {
  description = "Filename for Cloud Build configuration in the repository"
  type        = string
  default     = "cloudbuild.yaml"
}

variable "cloud_deploy_pipeline_name" {
  description = "Name for the Cloud Deploy delivery pipeline"
  type        = string
  default     = "gitops-pipeline"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cloud_deploy_pipeline_name))
    error_message = "Pipeline name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "environment_labels" {
  description = "Labels to apply to all resources for organization and billing"
  type        = map(string)
  default = {
    environment = "development"
    purpose     = "gitops-workflow"
    managed-by  = "terraform"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.environment_labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k))
    ])
    error_message = "Label keys must start with a letter, contain only lowercase letters, numbers, underscores, and hyphens, and end with a letter or number."
  }
}

variable "required_apis" {
  description = "List of Google Cloud APIs to enable for this deployment"
  type        = list(string)
  default = [
    "container.googleapis.com",
    "cloudbuild.googleapis.com",
    "sourcerepo.googleapis.com",
    "artifactregistry.googleapis.com",
    "workstations.googleapis.com",
    "clouddeploy.googleapis.com",
    "compute.googleapis.com",
    "containeranalysis.googleapis.com",
    "binaryauthorization.googleapis.com"
  ]
}

variable "network_name" {
  description = "Name of the VPC network to use (uses default network if not specified)"
  type        = string
  default     = "default"
}

variable "subnet_name" {
  description = "Name of the subnet to use (uses default subnet if not specified)"
  type        = string
  default     = "default"
}

variable "create_custom_network" {
  description = "Whether to create a custom VPC network instead of using the default network"
  type        = bool
  default     = false
}

variable "network_cidr" {
  description = "CIDR block for the custom VPC network (only used if create_custom_network is true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet (only used if create_custom_network is true)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "pod_cidr" {
  description = "CIDR block for GKE pod IP addresses (only used if create_custom_network is true)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "service_cidr" {
  description = "CIDR block for GKE service IP addresses (only used if create_custom_network is true)"
  type        = string
  default     = "10.2.0.0/16"
}