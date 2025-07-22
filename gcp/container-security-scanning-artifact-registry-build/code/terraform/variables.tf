# Project and region configuration
variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_id))
    error_message = "Project ID must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resources"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone."
  }
}

# Resource naming
variable "resource_suffix" {
  description = "Suffix to append to resource names for uniqueness"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.resource_suffix))
    error_message = "Resource suffix must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "secure-app"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.artifact_registry_repository_name))
    error_message = "Repository name must contain only lowercase letters, numbers, and hyphens."
  }
}

# GKE cluster configuration
variable "gke_cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "security-cluster"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.gke_cluster_name))
    error_message = "Cluster name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "gke_node_count" {
  description = "Number of nodes in the GKE cluster node pool"
  type        = number
  default     = 2

  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 10
    error_message = "Node count must be between 1 and 10."
  }
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-medium"

  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n2-standard-2"
    ], var.gke_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "gke_disk_size_gb" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 30

  validation {
    condition     = var.gke_disk_size_gb >= 10 && var.gke_disk_size_gb <= 100
    error_message = "Disk size must be between 10 and 100 GB."
  }
}

# Security service account configuration
variable "security_service_account_name" {
  description = "Name of the service account for security automation"
  type        = string
  default     = "security-scanner"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.security_service_account_name))
    error_message = "Service account name must contain only lowercase letters, numbers, and hyphens."
  }
}

# Binary Authorization configuration
variable "attestor_name" {
  description = "Name of the Binary Authorization attestor"
  type        = string
  default     = "security-attestor"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.attestor_name))
    error_message = "Attestor name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "attestor_note_name" {
  description = "Name of the Container Analysis note for attestation"
  type        = string
  default     = "security-attestor-note"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.attestor_note_name))
    error_message = "Note name must contain only lowercase letters, numbers, and hyphens."
  }
}

# KMS configuration
variable "kms_keyring_name" {
  description = "Name of the KMS keyring for signing keys"
  type        = string
  default     = "security-keyring"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.kms_keyring_name))
    error_message = "Keyring name must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "kms_key_name" {
  description = "Name of the KMS key for signing attestations"
  type        = string
  default     = "security-signing-key"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.kms_key_name))
    error_message = "Key name must contain only letters, numbers, underscores, and hyphens."
  }
}

# Security policy configuration
variable "vulnerability_policy" {
  description = "Vulnerability scanning policy configuration"
  type = object({
    max_critical_vulnerabilities = number
    max_high_vulnerabilities     = number
    scan_timeout_minutes         = number
  })
  default = {
    max_critical_vulnerabilities = 0
    max_high_vulnerabilities     = 5
    scan_timeout_minutes         = 30
  }

  validation {
    condition = (
      var.vulnerability_policy.max_critical_vulnerabilities >= 0 &&
      var.vulnerability_policy.max_high_vulnerabilities >= 0 &&
      var.vulnerability_policy.scan_timeout_minutes >= 5 &&
      var.vulnerability_policy.scan_timeout_minutes <= 60
    )
    error_message = "Vulnerability counts must be non-negative and timeout must be between 5 and 60 minutes."
  }
}

# Network configuration
variable "enable_private_cluster" {
  description = "Enable private GKE cluster"
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master nodes (private cluster)"
  type        = string
  default     = "172.16.0.0/28"

  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "Master CIDR block must be a valid IPv4 CIDR notation."
  }
}

# Resource labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "container-security"
    managed-by  = "terraform"
  }

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", k))
    ])
    error_message = "Label keys must contain only lowercase letters, numbers, underscores, and hyphens."
  }

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]+$", v))
    ])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Feature flags
variable "enable_security_command_center" {
  description = "Enable Security Command Center integration"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for GKE"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable network policy for GKE"
  type        = bool
  default     = true
}