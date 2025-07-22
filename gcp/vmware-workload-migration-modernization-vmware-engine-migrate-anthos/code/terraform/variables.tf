# Variables for VMware workload migration and modernization
# This file defines all input variables for the Terraform configuration

variable "project_id" {
  description = "The Google Cloud project ID to deploy resources in"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region to deploy resources in"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-south1",
      "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone to deploy resources in"
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z]+-[a-z0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone (e.g., us-central1-a)."
  }
}

variable "vmware_engine_region" {
  description = "The region for VMware Engine private cloud deployment"
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-south1", "asia-southeast1"
    ], var.vmware_engine_region)
    error_message = "VMware Engine region must be a supported region."
  }
}

variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "organization_name" {
  description = "Organization name for resource naming and tagging"
  type        = string
  default     = "vmware-migration"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.organization_name))
    error_message = "Organization name must contain only lowercase letters, numbers, and hyphens."
  }
}

# VMware Engine Configuration
variable "vmware_private_cloud_name" {
  description = "Name of the VMware Engine private cloud"
  type        = string
  default     = ""
}

variable "vmware_node_type" {
  description = "Node type for VMware Engine private cloud"
  type        = string
  default     = "standard-72"

  validation {
    condition = contains([
      "standard-72", "standard-52", "standard-36", "standard-28",
      "highmem-72", "highmem-52", "highmem-36", "highmem-28"
    ], var.vmware_node_type)
    error_message = "VMware node type must be a supported VMware Engine node type."
  }
}

variable "vmware_node_count" {
  description = "Number of nodes in the VMware Engine private cloud"
  type        = number
  default     = 3

  validation {
    condition     = var.vmware_node_count >= 3 && var.vmware_node_count <= 64
    error_message = "VMware node count must be between 3 and 64."
  }
}

variable "vmware_management_range" {
  description = "CIDR range for VMware Engine management network"
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.vmware_management_range, 0))
    error_message = "VMware management range must be a valid CIDR block."
  }
}

# GKE Configuration
variable "gke_cluster_name" {
  description = "Name of the GKE cluster for modernized applications"
  type        = string
  default     = ""
}

variable "gke_node_count" {
  description = "Initial number of nodes in the GKE cluster"
  type        = number
  default     = 2

  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 1000
    error_message = "GKE node count must be between 1 and 1000."
  }
}

variable "gke_min_node_count" {
  description = "Minimum number of nodes in the GKE cluster"
  type        = number
  default     = 1

  validation {
    condition     = var.gke_min_node_count >= 1
    error_message = "GKE minimum node count must be at least 1."
  }
}

variable "gke_max_node_count" {
  description = "Maximum number of nodes in the GKE cluster"
  type        = number
  default     = 10

  validation {
    condition     = var.gke_max_node_count >= 1 && var.gke_max_node_count <= 1000
    error_message = "GKE maximum node count must be between 1 and 1000."
  }
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"

  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16"
    ], var.gke_machine_type)
    error_message = "GKE machine type must be a supported Google Cloud machine type."
  }
}

variable "gke_disk_size_gb" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 100

  validation {
    condition     = var.gke_disk_size_gb >= 10 && var.gke_disk_size_gb <= 65536
    error_message = "GKE disk size must be between 10 and 65536 GB."
  }
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "secondary_pod_range" {
  description = "CIDR range for GKE pods"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.secondary_pod_range, 0))
    error_message = "Secondary pod range must be a valid CIDR block."
  }
}

variable "secondary_service_range" {
  description = "CIDR range for GKE services"
  type        = string
  default     = "10.2.0.0/16"

  validation {
    condition     = can(cidrhost(var.secondary_service_range, 0))
    error_message = "Secondary service range must be a valid CIDR block."
  }
}

# Artifact Registry Configuration
variable "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "modernized-apps"
}

variable "artifact_registry_format" {
  description = "Format of the Artifact Registry repository"
  type        = string
  default     = "DOCKER"

  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM"], var.artifact_registry_format)
    error_message = "Artifact Registry format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM."
  }
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Google Cloud monitoring and logging"
  type        = bool
  default     = true
}

variable "monitoring_dashboard_name" {
  description = "Name of the monitoring dashboard"
  type        = string
  default     = "vmware-migration-dashboard"
}

# Security Configuration
variable "enable_private_nodes" {
  description = "Enable private nodes for GKE cluster"
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master nodes"
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "Master IPv4 CIDR block must be a valid CIDR block."
  }
}

variable "enable_network_policy" {
  description = "Enable network policy for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable binary authorization for GKE cluster"
  type        = bool
  default     = true
}

# Resource Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "vmware-migration"
    environment = "dev"
    managed-by  = "terraform"
  }

  validation {
    condition     = alltrue([for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k)) && can(regex("^[a-z0-9_-]+$", v))])
    error_message = "Labels must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Cost Management
variable "enable_cost_management" {
  description = "Enable cost management features"
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 5000

  validation {
    condition     = var.budget_amount > 0
    error_message = "Budget amount must be greater than 0."
  }
}

variable "budget_threshold_percent" {
  description = "Budget threshold percentage for alerts"
  type        = number
  default     = 80

  validation {
    condition     = var.budget_threshold_percent > 0 && var.budget_threshold_percent <= 100
    error_message = "Budget threshold percentage must be between 1 and 100."
  }
}