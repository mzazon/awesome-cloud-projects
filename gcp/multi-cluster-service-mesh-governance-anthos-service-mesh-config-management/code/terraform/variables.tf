# Project and region configuration variables
variable "project_id" {
  type        = string
  description = "Google Cloud project ID for deploying resources"
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  type        = string
  description = "Google Cloud region for deploying resources"
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  type        = string
  description = "Google Cloud zone for deploying zonal resources"
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

# Cluster configuration variables
variable "clusters" {
  type = map(object({
    name         = string
    machine_type = string
    num_nodes    = number
    environment  = string
    labels       = map(string)
  }))
  description = "Configuration for GKE clusters across different environments"
  default = {
    production = {
      name         = "prod-cluster"
      machine_type = "e2-standard-4"
      num_nodes    = 3
      environment  = "production"
      labels = {
        env  = "production"
        mesh = "enabled"
      }
    }
    staging = {
      name         = "staging-cluster"
      machine_type = "e2-standard-2"
      num_nodes    = 2
      environment  = "staging"
      labels = {
        env  = "staging"
        mesh = "enabled"
      }
    }
    development = {
      name         = "dev-cluster"
      machine_type = "e2-standard-2"
      num_nodes    = 2
      environment  = "development"
      labels = {
        env  = "development"
        mesh = "enabled"
      }
    }
  }
}

# Networking configuration variables
variable "network_name" {
  type        = string
  description = "Name of the VPC network for GKE clusters"
  default     = "service-mesh-network"
}

variable "subnet_name" {
  type        = string
  description = "Name of the subnet for GKE clusters"
  default     = "service-mesh-subnet"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR range for the subnet"
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "pods_cidr" {
  type        = string
  description = "CIDR range for pods in the cluster"
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.pods_cidr, 0))
    error_message = "Pods CIDR must be a valid CIDR block."
  }
}

variable "services_cidr" {
  type        = string
  description = "CIDR range for services in the cluster"
  default     = "10.2.0.0/16"
  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "Services CIDR must be a valid CIDR block."
  }
}

# Anthos Service Mesh configuration variables
variable "enable_anthos_service_mesh" {
  type        = bool
  description = "Enable Anthos Service Mesh on clusters"
  default     = true
}

variable "service_mesh_release_channel" {
  type        = string
  description = "Release channel for Anthos Service Mesh"
  default     = "rapid"
  validation {
    condition     = contains(["rapid", "regular", "stable"], var.service_mesh_release_channel)
    error_message = "Service mesh release channel must be 'rapid', 'regular', or 'stable'."
  }
}

# Config Management configuration variables
variable "enable_config_management" {
  type        = bool
  description = "Enable Anthos Config Management on clusters"
  default     = true
}

variable "config_sync_git_repo" {
  type        = string
  description = "Git repository URL for Config Management synchronization"
  default     = ""
}

variable "config_sync_git_branch" {
  type        = string
  description = "Git branch for Config Management synchronization"
  default     = "main"
}

variable "config_sync_policy_dir" {
  type        = string
  description = "Directory in Git repository containing configuration policies"
  default     = "config-root"
}

# Binary Authorization configuration variables
variable "enable_binary_authorization" {
  type        = bool
  description = "Enable Binary Authorization for container image security"
  default     = true
}

variable "binary_auth_enforcement_mode" {
  type        = string
  description = "Binary Authorization enforcement mode"
  default     = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  validation {
    condition = contains([
      "ENFORCED_BLOCK_AND_AUDIT_LOG",
      "DRYRUN_AUDIT_LOG_ONLY"
    ], var.binary_auth_enforcement_mode)
    error_message = "Binary Authorization enforcement mode must be valid."
  }
}

# Artifact Registry configuration variables
variable "artifact_registry_repository" {
  type        = string
  description = "Name of the Artifact Registry repository for container images"
  default     = "secure-apps"
}

variable "artifact_registry_format" {
  type        = string
  description = "Format of the Artifact Registry repository"
  default     = "DOCKER"
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON"], var.artifact_registry_format)
    error_message = "Artifact Registry format must be valid."
  }
}

# Monitoring and logging configuration variables
variable "enable_monitoring" {
  type        = bool
  description = "Enable Google Cloud Monitoring for service mesh observability"
  default     = true
}

variable "enable_logging" {
  type        = bool
  description = "Enable Google Cloud Logging for service mesh logs"
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain logs"
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention days must be between 1 and 3653."
  }
}

# Resource naming and tagging variables
variable "resource_prefix" {
  type        = string
  description = "Prefix for resource names to ensure uniqueness"
  default     = "service-mesh-gov"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "resource_labels" {
  type        = map(string)
  description = "Common labels to apply to all resources"
  default = {
    purpose     = "service-mesh-governance"
    managed-by  = "terraform"
    environment = "multi-cluster"
  }
}

# Security configuration variables
variable "enable_workload_identity" {
  type        = bool
  description = "Enable Workload Identity for secure pod-to-service authentication"
  default     = true
}

variable "enable_network_policy" {
  type        = bool
  description = "Enable network policy enforcement"
  default     = true
}

variable "enable_pod_security_policy" {
  type        = bool
  description = "Enable Pod Security Policy"
  default     = true
}

variable "authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "List of authorized networks for cluster API access"
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks (change for production)"
    }
  ]
}

# Cost optimization variables
variable "enable_cluster_autoscaling" {
  type        = bool
  description = "Enable cluster autoscaling for cost optimization"
  default     = true
}

variable "enable_preemptible_nodes" {
  type        = bool
  description = "Enable preemptible nodes for cost optimization in non-production environments"
  default     = false
}

variable "node_auto_upgrade" {
  type        = bool
  description = "Enable automatic node upgrades"
  default     = true
}

variable "node_auto_repair" {
  type        = bool
  description = "Enable automatic node repairs"
  default     = true
}