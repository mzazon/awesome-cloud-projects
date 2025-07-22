# Project Configuration
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "The GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

# Cluster Configuration
variable "cluster_name_blue" {
  description = "Name for the blue environment GKE cluster"
  type        = string
  default     = "pwa-cluster-blue"
}

variable "cluster_name_green" {
  description = "Name for the green environment GKE cluster"
  type        = string
  default     = "pwa-cluster-green"
}

variable "node_count" {
  description = "Number of nodes in each GKE cluster"
  type        = number
  default     = 2
}

variable "machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 30
}

variable "min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 5
}

# Application Configuration
variable "app_name" {
  description = "Name of the PWA application"
  type        = string
  default     = "pwa-demo"
}

variable "app_version" {
  description = "Version of the PWA application"
  type        = string
  default     = "1.0.0"
}

# Cloud Storage Configuration
variable "bucket_name" {
  description = "Name for the Cloud Storage bucket for PWA assets"
  type        = string
  default     = null
}

variable "bucket_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Storage class for the Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
}

# Cloud Build Configuration
variable "source_repo_name" {
  description = "Name of the Cloud Source Repository"
  type        = string
  default     = "pwa-demo-app"
}

variable "build_trigger_filename" {
  description = "Filename for the Cloud Build trigger configuration"
  type        = string
  default     = "cloudbuild.yaml"
}

variable "build_trigger_branch" {
  description = "Branch pattern for the Cloud Build trigger"
  type        = string
  default     = "^master$"
}

# SSL Configuration
variable "ssl_certificate_domains" {
  description = "List of domains for SSL certificate"
  type        = list(string)
  default     = ["pwa-demo.example.com"]
}

variable "static_ip_name" {
  description = "Name for the global static IP address"
  type        = string
  default     = "pwa-demo-ip"
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "pwa-demo-network"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "pwa-demo-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/24"
}

variable "pods_cidr" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for services"
  type        = string
  default     = "10.2.0.0/16"
}

# Labels and Tags
variable "labels" {
  description = "A map of labels to apply to resources"
  type        = map(string)
  default = {
    environment = "demo"
    application = "pwa-demo"
    managed-by  = "terraform"
  }
}

# APIs to Enable
variable "enable_apis" {
  description = "List of APIs to enable"
  type        = list(string)
  default = [
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "sourcerepo.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

# Security Configuration
variable "enable_private_nodes" {
  description = "Enable private nodes for GKE clusters"
  type        = bool
  default     = true
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master nodes"
  type        = string
  default     = "172.16.0.0/28"
}

variable "enable_network_policy" {
  description = "Enable network policy for GKE clusters"
  type        = bool
  default     = true
}

variable "enable_workload_identity" {
  description = "Enable workload identity for GKE clusters"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable monitoring for GKE clusters"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable logging for GKE clusters"
  type        = bool
  default     = true
}

variable "monitoring_service" {
  description = "Monitoring service for GKE clusters"
  type        = string
  default     = "monitoring.googleapis.com/kubernetes"
}

variable "logging_service" {
  description = "Logging service for GKE clusters"
  type        = string
  default     = "logging.googleapis.com/kubernetes"
}

# Backup Configuration
variable "enable_backup" {
  description = "Enable backup for GKE clusters"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}