# variables.tf
# Input variables for GCP multiplayer gaming infrastructure

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region for deploying resources"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.region)
    error_message = "Region must be a valid GCP region."
  }
}

variable "zone" {
  description = "The GCP zone for deploying zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "game_name" {
  description = "Name of the game for resource naming"
  type        = string
  default     = "multiplayer-game"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.game_name))
    error_message = "Game name must contain only lowercase letters, numbers, and hyphens."
  }
}

# GKE Cluster Configuration
variable "gke_cluster_name" {
  description = "Name of the GKE cluster for game servers"
  type        = string
  default     = ""
}

variable "gke_node_count" {
  description = "Initial number of nodes in the GKE cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 20
    error_message = "Node count must be between 1 and 20."
  }
}

variable "gke_min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
}

variable "gke_max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 10
  validation {
    condition     = var.gke_max_node_count >= var.gke_min_node_count
    error_message = "Maximum node count must be greater than or equal to minimum node count."
  }
}

variable "gke_machine_type" {
  description = "Machine type for GKE nodes"
  type        = string
  default     = "e2-standard-4"
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8",
      "n1-standard-2", "n1-standard-4", "n1-standard-8",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.gke_machine_type)
    error_message = "Machine type must be a valid GCE machine type suitable for gaming workloads."
  }
}

variable "gke_disk_size" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 100
  validation {
    condition     = var.gke_disk_size >= 20 && var.gke_disk_size <= 500
    error_message = "Disk size must be between 20 and 500 GB."
  }
}

variable "gke_disk_type" {
  description = "Disk type for GKE nodes"
  type        = string
  default     = "pd-standard"
  validation {
    condition     = contains(["pd-standard", "pd-ssd", "pd-balanced"], var.gke_disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# Agones Configuration
variable "agones_version" {
  description = "Version of Agones to install"
  type        = string
  default     = "1.39.0"
}

variable "agones_gameserver_min_port" {
  description = "Minimum port for game servers"
  type        = number
  default     = 7000
  validation {
    condition     = var.agones_gameserver_min_port >= 1024 && var.agones_gameserver_min_port <= 65535
    error_message = "Game server minimum port must be between 1024 and 65535."
  }
}

variable "agones_gameserver_max_port" {
  description = "Maximum port for game servers"
  type        = number
  default     = 8000
  validation {
    condition     = var.agones_gameserver_max_port >= var.agones_gameserver_min_port && var.agones_gameserver_max_port <= 65535
    error_message = "Game server maximum port must be greater than minimum port and less than 65535."
  }
}

# Game Server Fleet Configuration
variable "gameserver_fleet_replicas" {
  description = "Initial number of game server replicas"
  type        = number
  default     = 2
  validation {
    condition     = var.gameserver_fleet_replicas >= 1 && var.gameserver_fleet_replicas <= 50
    error_message = "Game server fleet replicas must be between 1 and 50."
  }
}

variable "gameserver_image" {
  description = "Container image for game servers"
  type        = string
  default     = "gcr.io/agones-images/simple-game-server:0.12"
}

variable "gameserver_cpu_request" {
  description = "CPU request for game server containers"
  type        = string
  default     = "20m"
}

variable "gameserver_memory_request" {
  description = "Memory request for game server containers"
  type        = string
  default     = "64Mi"
}

variable "gameserver_cpu_limit" {
  description = "CPU limit for game server containers"
  type        = string
  default     = "50m"
}

variable "gameserver_memory_limit" {
  description = "Memory limit for game server containers"
  type        = string
  default     = "128Mi"
}

# Cloud Firestore Configuration
variable "firestore_location" {
  description = "Location for Firestore database"
  type        = string
  default     = "us-central"
  validation {
    condition = contains([
      "us-central", "us-east1", "us-west2", "us-west3", "us-west4",
      "europe-west", "europe-west2", "europe-west3", "europe-west6",
      "asia-northeast1", "asia-south1", "asia-southeast2"
    ], var.firestore_location)
    error_message = "Firestore location must be a valid multi-region or region."
  }
}

variable "firestore_type" {
  description = "Type of Firestore database"
  type        = string
  default     = "FIRESTORE_NATIVE"
  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.firestore_type)
    error_message = "Firestore type must be either FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

# Cloud Run Configuration
variable "cloud_run_service_name" {
  description = "Name of the Cloud Run matchmaking service"
  type        = string
  default     = ""
}

variable "cloud_run_image" {
  description = "Container image for Cloud Run matchmaking service"
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "512Mi"
  validation {
    condition     = contains(["128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi"], var.cloud_run_memory)
    error_message = "Cloud Run memory must be a valid memory allocation."
  }
}

variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "1000m"
  validation {
    condition     = contains(["1000m", "2000m", "4000m"], var.cloud_run_cpu)
    error_message = "Cloud Run CPU must be a valid CPU allocation."
  }
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 100
  validation {
    condition     = var.cloud_run_max_instances >= 1 && var.cloud_run_max_instances <= 1000
    error_message = "Cloud Run max instances must be between 1 and 1000."
  }
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = number
  default     = 0
  validation {
    condition     = var.cloud_run_min_instances >= 0 && var.cloud_run_min_instances <= var.cloud_run_max_instances
    error_message = "Cloud Run min instances must be between 0 and max instances."
  }
}

# Load Balancer Configuration
variable "enable_global_load_balancer" {
  description = "Enable global HTTP(S) load balancer"
  type        = bool
  default     = true
}

variable "enable_ssl" {
  description = "Enable SSL for load balancer"
  type        = bool
  default     = false
}

variable "ssl_certificate_domains" {
  description = "List of domains for SSL certificate"
  type        = list(string)
  default     = []
}

# Monitoring and Logging
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for resources"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable Cloud Logging for resources"
  type        = bool
  default     = true
}

# Network Configuration
variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = ""
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "pods_cidr" {
  description = "CIDR block for pods"
  type        = string
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.pods_cidr, 0))
    error_message = "Pods CIDR must be a valid CIDR block."
  }
}

variable "services_cidr" {
  description = "CIDR block for services"
  type        = string
  default     = "10.2.0.0/16"
  validation {
    condition     = can(cidrhost(var.services_cidr, 0))
    error_message = "Services CIDR must be a valid CIDR block."
  }
}

# Security Configuration
variable "enable_private_nodes" {
  description = "Enable private nodes for GKE cluster"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for GKE cluster"
  type        = bool
  default     = false
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for GKE master nodes"
  type        = string
  default     = "172.16.0.0/28"
  validation {
    condition     = can(cidrhost(var.master_ipv4_cidr_block, 0))
    error_message = "Master IPv4 CIDR must be a valid CIDR block."
  }
}

# Resource Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "multiplayer-gaming"
    managed-by  = "terraform"
    component   = "gaming-infrastructure"
  }
}