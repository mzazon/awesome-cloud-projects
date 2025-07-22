# Variables for Container Security Pipeline with Binary Authorization and Cloud Deploy
# This file defines all configurable parameters for the infrastructure

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
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = null
  validation {
    condition     = var.resource_suffix == null || can(regex("^[a-z0-9-]+$", var.resource_suffix))
    error_message = "Resource suffix must only contain lowercase letters, numbers, and hyphens."
  }
}

# Artifact Registry Configuration
variable "artifact_registry_repository_id" {
  description = "The ID of the Artifact Registry repository for container images"
  type        = string
  default     = "secure-apps-repo"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.artifact_registry_repository_id))
    error_message = "Repository ID must only contain lowercase letters, numbers, and hyphens."
  }
}

variable "artifact_registry_description" {
  description = "Description for the Artifact Registry repository"
  type        = string
  default     = "Secure container repository with vulnerability scanning"
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for container images"
  type        = bool
  default     = true
}

# GKE Cluster Configuration
variable "gke_cluster_config" {
  description = "Configuration for GKE clusters"
  type = object({
    staging_cluster_name     = optional(string, "staging-cluster")
    production_cluster_name  = optional(string, "prod-cluster")
    node_count              = optional(number, 3)
    machine_type            = optional(string, "e2-standard-2")
    disk_size_gb            = optional(number, 100)
    disk_type               = optional(string, "pd-standard")
    enable_private_nodes    = optional(bool, true)
    enable_private_endpoint = optional(bool, false)
    master_ipv4_cidr_block  = optional(string, "10.0.0.0/28")
    enable_network_policy   = optional(bool, true)
    enable_autorepair       = optional(bool, true)
    enable_autoupgrade      = optional(bool, true)
  })
  default = {}
}

# Binary Authorization Configuration
variable "binary_authorization_config" {
  description = "Configuration for Binary Authorization"
  type = object({
    attestor_name           = optional(string, "build-attestor")
    note_name              = optional(string, "build-note")
    global_policy_evaluation_mode = optional(string, "ENABLE")
    default_enforcement_mode = optional(string, "ENFORCED_BLOCK_AND_AUDIT_LOG")
    staging_enforcement_mode = optional(string, "DRYRUN_AUDIT_LOG_ONLY")
    production_enforcement_mode = optional(string, "ENFORCED_BLOCK_AND_AUDIT_LOG")
  })
  default = {}
}

# Cloud Deploy Configuration
variable "cloud_deploy_config" {
  description = "Configuration for Cloud Deploy pipeline"
  type = object({
    pipeline_name = optional(string, "secure-app-pipeline")
    staging_target_name = optional(string, "staging")
    production_target_name = optional(string, "production")
    canary_percentages = optional(list(number), [20, 50, 80])
    enable_canary_verification = optional(bool, false)
    deployment_timeout = optional(string, "3600s")
    require_approval = optional(bool, true)
  })
  default = {}
}

# Service Account Configuration
variable "service_account_config" {
  description = "Configuration for service accounts"
  type = object({
    cloud_build_sa_id = optional(string, "cloud-build-sa")
    cloud_deploy_sa_id = optional(string, "cloud-deploy-sa")
    gke_workload_sa_id = optional(string, "gke-workload-sa")
  })
  default = {}
}

# Networking Configuration
variable "network_config" {
  description = "Network configuration for the infrastructure"
  type = object({
    network_name = optional(string, "container-security-network")
    subnet_name = optional(string, "container-security-subnet")
    subnet_cidr = optional(string, "10.1.0.0/24")
    enable_private_google_access = optional(bool, true)
    enable_flow_logs = optional(bool, true)
  })
  default = {}
}

# Monitoring and Logging Configuration
variable "monitoring_config" {
  description = "Configuration for monitoring and logging"
  type = object({
    enable_logging = optional(bool, true)
    enable_monitoring = optional(bool, true)
    log_retention_days = optional(number, 30)
    enable_audit_logs = optional(bool, true)
  })
  default = {}
}

# Backup and Disaster Recovery Configuration
variable "backup_config" {
  description = "Configuration for backup and disaster recovery"
  type = object({
    enable_etcd_backup = optional(bool, true)
    backup_retention_days = optional(number, 7)
    backup_schedule = optional(string, "0 2 * * *")
  })
  default = {}
}

# Security Configuration
variable "security_config" {
  description = "Security configuration settings"
  type = object({
    enable_workload_identity = optional(bool, true)
    enable_shielded_nodes = optional(bool, true)
    enable_secure_boot = optional(bool, true)
    enable_integrity_monitoring = optional(bool, true)
    authorized_networks = optional(list(object({
      cidr_block   = string
      display_name = string
    })), [])
  })
  default = {}
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    purpose     = "container-security"
    managed_by  = "terraform"
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}