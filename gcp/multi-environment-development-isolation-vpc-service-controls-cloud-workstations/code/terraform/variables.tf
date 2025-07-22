# Variables for multi-environment development isolation with VPC Service Controls and Cloud Workstations

# General Configuration
variable "organization_id" {
  description = "The organization ID where the projects will be created"
  type        = string
}

variable "billing_account_id" {
  description = "The billing account ID to associate with the projects"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The zone where resources will be created"
  type        = string
  default     = "us-central1-a"
}

# Project Configuration
variable "project_prefix" {
  description = "Prefix for project names"
  type        = string
  default     = "secure-dev-env"
}

variable "dev_project_id" {
  description = "Project ID for the development environment"
  type        = string
}

variable "test_project_id" {
  description = "Project ID for the testing environment"
  type        = string
}

variable "prod_project_id" {
  description = "Project ID for the production environment"
  type        = string
}

# Network Configuration
variable "dev_vpc_cidr" {
  description = "CIDR block for development VPC subnet"
  type        = string
  default     = "10.1.0.0/24"
}

variable "test_vpc_cidr" {
  description = "CIDR block for testing VPC subnet"
  type        = string
  default     = "10.2.0.0/24"
}

variable "prod_vpc_cidr" {
  description = "CIDR block for production VPC subnet"
  type        = string
  default     = "10.3.0.0/24"
}

# VPC Service Controls Configuration
variable "access_policy_title" {
  description = "Title for the Access Context Manager policy"
  type        = string
  default     = "Multi-Environment Security Policy"
}

variable "internal_users" {
  description = "List of internal users who can access the environments"
  type        = list(string)
  default     = ["user:dev-team@yourdomain.com", "user:admin@yourdomain.com"]
}

# Cloud Filestore Configuration
variable "filestore_tier" {
  description = "Filestore tier for shared storage"
  type        = string
  default     = "BASIC_SSD"
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB"
  type        = number
  default     = 1024
}

# Cloud Workstations Configuration
variable "workstation_machine_type" {
  description = "Machine type for workstations"
  type        = string
  default     = "e2-standard-4"
}

variable "workstation_boot_disk_size_gb" {
  description = "Boot disk size for workstations in GB"
  type        = number
  default     = 50
}

variable "workstation_persistent_disk_size_gb" {
  description = "Persistent disk size for workstations in GB"
  type        = number
  default     = 50
}

variable "workstation_image" {
  description = "Container image for workstations"
  type        = string
  default     = "us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
}

# IAP Configuration
variable "iap_support_email" {
  description = "Support email for IAP OAuth consent screen"
  type        = string
  default     = "admin@yourdomain.com"
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    environment = "multi-env-isolation"
    purpose     = "development"
    terraform   = "true"
  }
}

# Services to enable
variable "services_to_enable" {
  description = "List of services to enable on the projects"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "workstations.googleapis.com",
    "file.googleapis.com",
    "iap.googleapis.com",
    "accesscontextmanager.googleapis.com",
    "sourcerepo.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# VPC Service Controls restricted services
variable "restricted_services" {
  description = "List of services to restrict in VPC Service Controls perimeters"
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "compute.googleapis.com",
    "workstations.googleapis.com",
    "file.googleapis.com"
  ]
}