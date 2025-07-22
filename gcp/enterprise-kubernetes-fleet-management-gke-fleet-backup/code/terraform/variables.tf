# Variable definitions for GCP Enterprise Kubernetes Fleet Management
# These variables allow customization of the infrastructure deployment

# Project Configuration
variable "fleet_host_project_id" {
  description = "The project ID for the fleet host project that manages the entire fleet"
  type        = string
  default     = null
  
  validation {
    condition     = var.fleet_host_project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.fleet_host_project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "workload_project_prod_id" {
  description = "The project ID for the production workload project"
  type        = string
  default     = null
  
  validation {
    condition     = var.workload_project_prod_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.workload_project_prod_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "workload_project_staging_id" {
  description = "The project ID for the staging workload project"
  type        = string
  default     = null
  
  validation {
    condition     = var.workload_project_staging_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.workload_project_staging_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "billing_account" {
  description = "The billing account ID to associate with the projects"
  type        = string
  default     = ""
  
  validation {
    condition     = var.billing_account == "" || can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account))
    error_message = "Billing account must be in the format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "organization_id" {
  description = "The organization ID for creating projects (optional)"
  type        = string
  default     = ""
}

# Geographic Configuration
variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Fleet Configuration
variable "fleet_name" {
  description = "The name of the GKE fleet for centralized management"
  type        = string
  default     = "enterprise-fleet"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.fleet_name))
    error_message = "Fleet name must be 2-63 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

# GKE Cluster Configuration
variable "cluster_name_prefix" {
  description = "Prefix for GKE cluster names across environments"
  type        = string
  default     = "gke-cluster"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.cluster_name_prefix))
    error_message = "Cluster name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "prod_cluster_config" {
  description = "Configuration for the production GKE cluster"
  type = object({
    initial_node_count = number
    min_node_count     = number
    max_node_count     = number
    machine_type       = string
    disk_size_gb       = number
    disk_type          = string
    enable_autoscaling = bool
    enable_autorepair  = bool
    enable_autoupgrade = bool
  })
  default = {
    initial_node_count = 2
    min_node_count     = 1
    max_node_count     = 5
    machine_type       = "e2-standard-4"
    disk_size_gb       = 50
    disk_type          = "pd-standard"
    enable_autoscaling = true
    enable_autorepair  = true
    enable_autoupgrade = true
  }
}

variable "staging_cluster_config" {
  description = "Configuration for the staging GKE cluster"
  type = object({
    initial_node_count = number
    min_node_count     = number
    max_node_count     = number
    machine_type       = string
    disk_size_gb       = number
    disk_type          = string
    enable_autoscaling = bool
    enable_autorepair  = bool
    enable_autoupgrade = bool
  })
  default = {
    initial_node_count = 1
    min_node_count     = 1
    max_node_count     = 3
    machine_type       = "e2-standard-2"
    disk_size_gb       = 50
    disk_type          = "pd-standard"
    enable_autoscaling = true
    enable_autorepair  = true
    enable_autoupgrade = true
  }
}

# Backup Configuration
variable "backup_plan_config" {
  description = "Configuration for GKE backup plans"
  type = object({
    prod_schedule       = string
    prod_retention_days = number
    staging_schedule    = string
    staging_retention_days = number
    include_volume_data = bool
    include_secrets     = bool
  })
  default = {
    prod_schedule          = "0 2 * * *"      # Daily at 2 AM
    prod_retention_days    = 30
    staging_schedule       = "0 3 * * 0"      # Weekly on Sunday at 3 AM
    staging_retention_days = 14
    include_volume_data    = true
    include_secrets        = true
  }
}

# Network Configuration
variable "network_config" {
  description = "Configuration for VPC networks and subnets"
  type = object({
    create_vpc_network    = bool
    network_name          = string
    subnet_name           = string
    subnet_cidr           = string
    pods_cidr             = string
    services_cidr         = string
    enable_private_nodes  = bool
    master_cidr           = string
    enable_ip_alias       = bool
  })
  default = {
    create_vpc_network   = true
    network_name         = "fleet-network"
    subnet_name          = "fleet-subnet"
    subnet_cidr          = "10.0.0.0/24"
    pods_cidr            = "10.1.0.0/16"
    services_cidr        = "10.2.0.0/16"
    enable_private_nodes = true
    master_cidr          = "172.16.0.0/28"
    enable_ip_alias      = true
  }
}

# Security Configuration
variable "security_config" {
  description = "Security configuration for clusters and fleet"
  type = object({
    enable_workload_identity    = bool
    enable_shielded_nodes      = bool
    enable_network_policy      = bool
    enable_private_endpoint    = bool
    enable_binary_authorization = bool
    enable_pod_security_policy = bool
  })
  default = {
    enable_workload_identity    = true
    enable_shielded_nodes      = true
    enable_network_policy      = true
    enable_private_endpoint    = false
    enable_binary_authorization = true
    enable_pod_security_policy = false
  }
}

# Config Management Configuration
variable "config_management" {
  description = "Configuration for Anthos Config Management"
  type = object({
    enable_config_sync          = bool
    enable_policy_controller    = bool
    enable_multi_repo          = bool
    referential_rules_enabled  = bool
    log_denies_enabled         = bool
    mutation_enabled           = bool
  })
  default = {
    enable_config_sync         = true
    enable_policy_controller   = true
    enable_multi_repo          = true
    referential_rules_enabled  = true
    log_denies_enabled         = true
    mutation_enabled           = true
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_prefix == "" || can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

# Labels and Tags
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    environment   = "production"
    project       = "enterprise-k8s-fleet"
    managed-by    = "terraform"
    team          = "platform-engineering"
  }
}

# Feature Flags
variable "enable_sample_applications" {
  description = "Whether to deploy sample applications for testing"
  type        = bool
  default     = true
}

variable "enable_config_connector" {
  description = "Whether to enable Config Connector for GitOps"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable enhanced monitoring and logging"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Whether to enable backup for GKE clusters"
  type        = bool
  default     = true
}