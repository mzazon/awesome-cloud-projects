# Project and Location Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Resource Naming Variables
variable "resource_prefix" {
  description = "Prefix for all resource names to ensure uniqueness"
  type        = string
  default     = "secure-supply-chain"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Artifact Registry Configuration
variable "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository for secure container images"
  type        = string
  default     = "secure-images"
}

variable "artifact_registry_format" {
  description = "Format of the Artifact Registry repository (DOCKER, MAVEN, NPM, etc.)"
  type        = string
  default     = "DOCKER"
  
  validation {
    condition     = contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM"], var.artifact_registry_format)
    error_message = "Repository format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM."
  }
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning for Artifact Registry repository"
  type        = bool
  default     = true
}

# GKE Cluster Configuration
variable "cluster_name" {
  description = "Name of the GKE cluster with Binary Authorization enabled"
  type        = string
  default     = "secure-cluster"
}

variable "cluster_machine_type" {
  description = "Machine type for GKE cluster nodes"
  type        = string
  default     = "e2-medium"
}

variable "cluster_min_nodes" {
  description = "Minimum number of nodes in the GKE cluster"
  type        = number
  default     = 1
}

variable "cluster_max_nodes" {
  description = "Maximum number of nodes in the GKE cluster"
  type        = number
  default     = 3
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for the GKE cluster"
  type        = bool
  default     = true
}

# Cloud KMS Configuration
variable "kms_keyring_name" {
  description = "Name of the Cloud KMS keyring for attestation keys"
  type        = string
  default     = "binauthz-keyring"
}

variable "kms_key_name" {
  description = "Name of the Cloud KMS key for signing attestations"
  type        = string
  default     = "attestor-key"
}

variable "kms_key_algorithm" {
  description = "Algorithm for the KMS key used for signing"
  type        = string
  default     = "RSA_SIGN_PSS_2048_SHA256"
  
  validation {
    condition = contains([
      "RSA_SIGN_PSS_2048_SHA256",
      "RSA_SIGN_PSS_3072_SHA256",
      "RSA_SIGN_PSS_4096_SHA256",
      "RSA_SIGN_PKCS1_2048_SHA256",
      "RSA_SIGN_PKCS1_3072_SHA256",
      "RSA_SIGN_PKCS1_4096_SHA256",
      "EC_SIGN_P256_SHA256",
      "EC_SIGN_P384_SHA384"
    ], var.kms_key_algorithm)
    error_message = "KMS key algorithm must be a valid asymmetric signing algorithm."
  }
}

variable "kms_key_protection_level" {
  description = "Protection level for the KMS key (SOFTWARE, HSM)"
  type        = string
  default     = "SOFTWARE"
  
  validation {
    condition     = contains(["SOFTWARE", "HSM"], var.kms_key_protection_level)
    error_message = "KMS key protection level must be SOFTWARE or HSM."
  }
}

# Binary Authorization Configuration
variable "attestor_name" {
  description = "Name of the Binary Authorization attestor"
  type        = string
  default     = "build-attestor"
}

variable "attestor_description" {
  description = "Description of the Binary Authorization attestor"
  type        = string
  default     = "Attestor for CI/CD pipeline security verification"
}

variable "binary_authorization_policy_mode" {
  description = "Binary Authorization policy enforcement mode"
  type        = string
  default     = "ENFORCED_BLOCK_AND_AUDIT_LOG"
  
  validation {
    condition = contains([
      "ENFORCED_BLOCK_AND_AUDIT_LOG",
      "DRYRUN_AUDIT_LOG_ONLY"
    ], var.binary_authorization_policy_mode)
    error_message = "Policy mode must be ENFORCED_BLOCK_AND_AUDIT_LOG or DRYRUN_AUDIT_LOG_ONLY."
  }
}

variable "whitelisted_image_patterns" {
  description = "List of image patterns to whitelist in Binary Authorization policy"
  type        = list(string)
  default = [
    "gcr.io/google-containers/*",
    "gcr.io/google_containers/*",
    "k8s.gcr.io/*",
    "gcr.io/gke-release/*",
    "registry.k8s.io/*"
  ]
}

# Cloud Build Configuration
variable "enable_cloud_build_trigger" {
  description = "Enable Cloud Build trigger for automated builds"
  type        = bool
  default     = true
}

variable "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  type        = string
  default     = "secure-build-trigger"
}

variable "source_repository_name" {
  description = "Name of the source repository for Cloud Build triggers"
  type        = string
  default     = "secure-app-repo"
}

variable "source_repository_branch" {
  description = "Branch name to trigger builds on"
  type        = string
  default     = "main"
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network for GKE cluster"
  type        = string
  default     = "secure-network"
}

variable "subnet_name" {
  description = "Name of the subnet for GKE cluster"
  type        = string
  default     = "secure-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pods_cidr" {
  description = "CIDR block for GKE pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for GKE services"
  type        = string
  default     = "10.2.0.0/16"
}

# Security Configuration
variable "enable_network_policy" {
  description = "Enable network policy for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_private_nodes" {
  description = "Enable private nodes for GKE cluster"
  type        = bool
  default     = true
}

variable "master_cidr" {
  description = "CIDR block for GKE master nodes"
  type        = string
  default     = "172.16.0.0/28"
}

variable "authorized_networks" {
  description = "List of authorized networks for GKE API server access"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [
    {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  ]
}

# Monitoring and Logging Configuration
variable "enable_logging" {
  description = "Enable Cloud Logging for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for GKE cluster"
  type        = bool
  default     = true
}

variable "logging_components" {
  description = "List of logging components to enable"
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}

variable "monitoring_components" {
  description = "List of monitoring components to enable"
  type        = list(string)
  default     = ["SYSTEM_COMPONENTS"]
}

# Tags and Labels
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    purpose     = "supply-chain-security"
    managed-by  = "terraform"
    environment = "dev"
  }
}