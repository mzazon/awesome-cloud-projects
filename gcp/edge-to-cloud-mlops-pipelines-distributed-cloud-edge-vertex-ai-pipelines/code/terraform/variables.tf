# =============================================================================
# VARIABLES - Edge-to-Cloud MLOps Pipelines Infrastructure
# =============================================================================
# This file defines all input variables for the MLOps pipeline infrastructure
# supporting edge-to-cloud machine learning operations with Vertex AI and 
# Distributed Cloud Edge integration.

# =============================================================================
# PROJECT AND REGION CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (GKE cluster, storage buckets)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (primarily for node pools)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

# =============================================================================
# ENVIRONMENT AND NAMING
# =============================================================================

variable "environment" {
  description = "Environment designation for resource labeling and organization"
  type        = string
  default     = "development"
  
  validation {
    condition = contains(["development", "staging", "production", "test"], var.environment)
    error_message = "Environment must be one of: development, staging, production, test."
  }
}

variable "resource_prefix" {
  description = "Prefix to apply to all resource names for organization and uniqueness"
  type        = string
  default     = "mlops"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

# =============================================================================
# GKE CLUSTER CONFIGURATION
# =============================================================================

variable "gke_cluster_name" {
  description = "Name for the GKE cluster used for edge simulation and inference workloads"
  type        = string
  default     = "edge-simulation-cluster"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.gke_cluster_name))
    error_message = "Cluster name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "gke_node_count" {
  description = "Initial number of nodes in the default GKE node pool"
  type        = number
  default     = 2
  
  validation {
    condition     = var.gke_node_count >= 1 && var.gke_node_count <= 100
    error_message = "Node count must be between 1 and 100."
  }
}

variable "gke_min_node_count" {
  description = "Minimum number of nodes for GKE cluster autoscaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.gke_min_node_count >= 0 && var.gke_min_node_count <= 50
    error_message = "Minimum node count must be between 0 and 50."
  }
}

variable "gke_max_node_count" {
  description = "Maximum number of nodes for GKE cluster autoscaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.gke_max_node_count >= 1 && var.gke_max_node_count <= 100
    error_message = "Maximum node count must be between 1 and 100."
  }
}

variable "general_purpose_machine_type" {
  description = "Machine type for general-purpose GKE node pool"
  type        = string
  default     = "e2-standard-4"
  
  validation {
    condition = contains([
      "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16"
    ], var.general_purpose_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type suitable for general workloads."
  }
}

variable "ml_inference_machine_type" {
  description = "Machine type for ML inference node pool (optimized for compute-intensive workloads)"
  type        = string
  default     = "n1-standard-8"
  
  validation {
    condition = contains([
      "n1-standard-8", "n1-standard-16", "n1-standard-32",
      "n2-standard-8", "n2-standard-16", "n2-standard-32",
      "c2-standard-8", "c2-standard-16", "c2-standard-30"
    ], var.ml_inference_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type suitable for ML inference workloads."
  }
}

variable "use_preemptible_nodes" {
  description = "Whether to use preemptible instances for cost optimization (not recommended for production)"
  type        = bool
  default     = true
  
  validation {
    condition = contains([true, false], var.use_preemptible_nodes)
    error_message = "Use preemptible nodes must be either true or false."
  }
}

variable "node_disk_size_gb" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 50
  
  validation {
    condition     = var.node_disk_size_gb >= 20 && var.node_disk_size_gb <= 500
    error_message = "Node disk size must be between 20 GB and 500 GB."
  }
}

variable "ml_node_disk_size_gb" {
  description = "Disk size in GB for ML inference nodes (typically larger for model storage)"
  type        = number
  default     = 100
  
  validation {
    condition     = var.ml_node_disk_size_gb >= 50 && var.ml_node_disk_size_gb <= 1000
    error_message = "ML node disk size must be between 50 GB and 1000 GB."
  }
}

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================

variable "storage_class" {
  description = "Default storage class for Cloud Storage buckets"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE, REGIONAL, MULTI_REGIONAL."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable object versioning on storage buckets for model artifact tracking"
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days after which to delete old objects from storage buckets"
  type        = number
  default     = 90
  
  validation {
    condition     = var.bucket_lifecycle_age_days >= 1 && var.bucket_lifecycle_age_days <= 3650
    error_message = "Bucket lifecycle age must be between 1 and 3650 days."
  }
}

variable "nearline_transition_days" {
  description = "Number of days after which to transition objects to NEARLINE storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.nearline_transition_days >= 1 && var.nearline_transition_days <= 365
    error_message = "Nearline transition days must be between 1 and 365 days."
  }
}

variable "telemetry_retention_days" {
  description = "Number of days to retain telemetry data before deletion"
  type        = number
  default     = 365
  
  validation {
    condition     = var.telemetry_retention_days >= 30 && var.telemetry_retention_days <= 2555
    error_message = "Telemetry retention days must be between 30 and 2555 days (7 years)."
  }
}

# =============================================================================
# NETWORKING CONFIGURATION
# =============================================================================

variable "vpc_cidr_range" {
  description = "CIDR range for the main VPC subnet"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr_range, 0))
    error_message = "VPC CIDR range must be a valid CIDR notation."
  }
}

variable "pods_cidr_range" {
  description = "Secondary CIDR range for Kubernetes pods"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.pods_cidr_range, 0))
    error_message = "Pods CIDR range must be a valid CIDR notation."
  }
}

variable "services_cidr_range" {
  description = "Secondary CIDR range for Kubernetes services"
  type        = string
  default     = "10.2.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.services_cidr_range, 0))
    error_message = "Services CIDR range must be a valid CIDR notation."
  }
}

variable "master_cidr_range" {
  description = "CIDR range for GKE master nodes (private cluster)"
  type        = string
  default     = "172.16.0.0/28"
  
  validation {
    condition     = can(cidrhost(var.master_cidr_range, 0))
    error_message = "Master CIDR range must be a valid CIDR notation."
  }
}

variable "enable_private_nodes" {
  description = "Enable private nodes in GKE cluster for enhanced security"
  type        = bool
  default     = true
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint for GKE cluster master (requires VPN or bastion for access)"
  type        = bool
  default     = false
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

variable "alert_email" {
  description = "Email address for receiving monitoring alerts"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address."
  }
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring for the MLOps pipeline"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable detailed logging for the MLOps pipeline"
  type        = bool
  default     = true
}

variable "monitoring_retention_days" {
  description = "Number of days to retain monitoring data"
  type        = number
  default     = 90
  
  validation {
    condition     = var.monitoring_retention_days >= 1 && var.monitoring_retention_days <= 2555
    error_message = "Monitoring retention days must be between 1 and 2555 days."
  }
}

variable "high_latency_threshold_ms" {
  description = "Threshold in milliseconds for high latency alerts"
  type        = number
  default     = 1000
  
  validation {
    condition     = var.high_latency_threshold_ms >= 100 && var.high_latency_threshold_ms <= 10000
    error_message = "High latency threshold must be between 100 and 10000 milliseconds."
  }
}

variable "enable_workload_monitoring" {
  description = "Enable workload-level monitoring for Kubernetes deployments"
  type        = bool
  default     = true
}

variable "enable_managed_prometheus" {
  description = "Enable Google Cloud Managed Service for Prometheus"
  type        = bool
  default     = true
}

# =============================================================================
# CLOUD FUNCTION CONFIGURATION
# =============================================================================

variable "function_timeout_seconds" {
  description = "Timeout in seconds for Cloud Functions"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_memory_mb" {
  description = "Memory allocation in MB for Cloud Functions"
  type        = number
  default     = 512
  
  validation {
    condition = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_max_instances" {
  description = "Maximum number of instances for Cloud Functions"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 100
    error_message = "Function max instances must be between 1 and 100."
  }
}

# =============================================================================
# ML MODEL CONFIGURATION
# =============================================================================

variable "default_model_version" {
  description = "Default version tag for ML models"
  type        = string
  default     = "v1"
  
  validation {
    condition     = can(regex("^v[0-9]+$", var.default_model_version))
    error_message = "Model version must be in format 'v1', 'v2', etc."
  }
}

variable "max_batch_size" {
  description = "Maximum batch size for model inference"
  type        = number
  default     = 32
  
  validation {
    condition     = var.max_batch_size >= 1 && var.max_batch_size <= 128
    error_message = "Max batch size must be between 1 and 128."
  }
}

variable "inference_timeout_seconds" {
  description = "Timeout in seconds for model inference requests"
  type        = number
  default     = 30
  
  validation {
    condition     = var.inference_timeout_seconds >= 5 && var.inference_timeout_seconds <= 300
    error_message = "Inference timeout must be between 5 and 300 seconds."
  }
}

variable "health_check_interval_seconds" {
  description = "Interval in seconds between health checks for inference services"
  type        = number
  default     = 10
  
  validation {
    condition     = var.health_check_interval_seconds >= 5 && var.health_check_interval_seconds <= 60
    error_message = "Health check interval must be between 5 and 60 seconds."
  }
}

# =============================================================================
# SECURITY CONFIGURATION
# =============================================================================

variable "enable_workload_identity" {
  description = "Enable Workload Identity for secure pod authentication"
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Enable Kubernetes network policies for enhanced security"
  type        = bool
  default     = true
}

variable "enable_shielded_nodes" {
  description = "Enable shielded GKE nodes for additional security"
  type        = bool
  default     = true
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container image security"
  type        = bool
  default     = false
}

# =============================================================================
# COST OPTIMIZATION
# =============================================================================

variable "enable_cluster_autoscaling" {
  description = "Enable cluster-level autoscaling for cost optimization"
  type        = bool
  default     = true
}

variable "enable_node_auto_repair" {
  description = "Enable automatic node repair for improved reliability"
  type        = bool
  default     = true
}

variable "enable_node_auto_upgrade" {
  description = "Enable automatic node upgrades for security and features"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*[a-z0-9]$", k))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "enable_vertex_ai_pipelines" {
  description = "Enable Vertex AI Pipelines for ML workflow orchestration"
  type        = bool
  default     = true
}

variable "enable_distributed_cloud_edge" {
  description = "Enable integration with Distributed Cloud Edge (requires additional setup)"
  type        = bool
  default     = false
}

variable "edge_locations" {
  description = "List of edge locations for model deployment"
  type        = list(string)
  default     = ["edge-location-1", "edge-location-2"]
  
  validation {
    condition     = length(var.edge_locations) > 0
    error_message = "At least one edge location must be specified."
  }
}

variable "maintenance_window_start_time" {
  description = "Start time for GKE maintenance window (RFC3339 format)"
  type        = string
  default     = "2025-01-01T03:00:00Z"
  
  validation {
    condition     = can(formatdate("RFC3339", var.maintenance_window_start_time))
    error_message = "Maintenance window start time must be in RFC3339 format."
  }
}

variable "maintenance_window_end_time" {
  description = "End time for GKE maintenance window (RFC3339 format)"
  type        = string
  default     = "2025-01-01T07:00:00Z"
  
  validation {
    condition     = can(formatdate("RFC3339", var.maintenance_window_end_time))
    error_message = "Maintenance window end time must be in RFC3339 format."
  }
}

variable "maintenance_window_recurrence" {
  description = "Recurrence pattern for GKE maintenance window"
  type        = string
  default     = "FREQ=WEEKLY;BYDAY=SA"
  
  validation {
    condition = contains([
      "FREQ=WEEKLY;BYDAY=SA", "FREQ=WEEKLY;BYDAY=SU", 
      "FREQ=DAILY", "FREQ=WEEKLY;BYDAY=MO"
    ], var.maintenance_window_recurrence)
    error_message = "Maintenance window recurrence must be a valid RRULE pattern."
  }
}