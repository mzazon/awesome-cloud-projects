# Variables for GCP Enterprise Deployment Pipeline Infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The GCP region for regional resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "cluster_name_prefix" {
  description = "Prefix for GKE cluster names"
  type        = string
  default     = "enterprise-gke"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.cluster_name_prefix))
    error_message = "Cluster name prefix must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "artifact_repository_name" {
  description = "Name of the Artifact Registry repository for container images"
  type        = string
  default     = "enterprise-apps"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.artifact_repository_name))
    error_message = "Repository name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "pipeline_name" {
  description = "Name of the Cloud Deploy delivery pipeline"
  type        = string
  default     = "enterprise-pipeline"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.pipeline_name))
    error_message = "Pipeline name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "source_repo_names" {
  description = "Names of Cloud Source Repositories to create"
  type        = list(string)
  default     = ["pipeline-templates", "sample-app"]
  validation {
    condition     = length(var.source_repo_names) > 0
    error_message = "At least one source repository name must be provided."
  }
}

variable "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  type        = string
  default     = "enterprise-deployment-trigger"
  validation {
    condition     = length(var.build_trigger_name) <= 64
    error_message = "Build trigger name must be 64 characters or less."
  }
}

variable "service_account_name" {
  description = "Name for the Cloud Build service account"
  type        = string
  default     = "cloudbuild-deploy"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_account_name))
    error_message = "Service account name must start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_apis" {
  description = "Whether to enable required Google Cloud APIs"
  type        = bool
  default     = true
}

variable "enable_shielded_nodes" {
  description = "Whether to enable shielded nodes on production GKE cluster"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Whether to enable network policy on GKE clusters"
  type        = bool
  default     = true
}

variable "enable_ip_alias" {
  description = "Whether to enable IP aliasing on GKE clusters"
  type        = bool
  default     = true
}

variable "gke_autopilot_enabled" {
  description = "Whether to use GKE Autopilot clusters (recommended for simplified management)"
  type        = bool
  default     = true
}

variable "environments" {
  description = "List of deployment environments"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
  validation {
    condition     = length(var.environments) >= 2
    error_message = "At least two environments must be specified for a deployment pipeline."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed-by  = "terraform"
    project     = "enterprise-cicd"
    environment = "multi"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Labels must use lowercase letters, numbers, underscores, and hyphens only."
  }
}

variable "annotations" {
  description = "Annotations to apply to Cloud Deploy resources"
  type        = map(string)
  default = {
    "deployment.cloud.google.com/managed-by" = "terraform"
    "deployment.cloud.google.com/environment" = "enterprise"
  }
}

variable "cloudbuild_timeout" {
  description = "Timeout for Cloud Build operations in seconds"
  type        = string
  default     = "1200s"
  validation {
    condition     = can(regex("^[0-9]+s$", var.cloudbuild_timeout))
    error_message = "Timeout must be specified in seconds format (e.g., '1200s')."
  }
}

variable "cloudbuild_machine_type" {
  description = "Machine type for Cloud Build operations"
  type        = string
  default     = "E2_STANDARD_4"
  validation {
    condition = contains([
      "E2_STANDARD_2", "E2_STANDARD_4", "E2_STANDARD_8", "E2_STANDARD_16", "E2_STANDARD_32",
      "E2_HIGHCPU_8", "E2_HIGHCPU_16", "E2_HIGHCPU_32", "E2_HIGHMEM_2", "E2_HIGHMEM_4", "E2_HIGHMEM_8"
    ], var.cloudbuild_machine_type)
    error_message = "Machine type must be a valid Cloud Build machine type."
  }
}