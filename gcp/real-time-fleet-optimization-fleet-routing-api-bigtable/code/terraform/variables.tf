# ============================================================================
# Terraform Variables for Real-Time Fleet Optimization Infrastructure
# ============================================================================
# This file defines all configurable parameters for the fleet optimization
# system including project settings, resource sizing, security options,
# and feature toggles for production deployments.

# ============================================================================
# Core Project Configuration
# ============================================================================

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "Google Cloud region for primary resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "Google Cloud zone for Bigtable primary cluster deployment"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "backup_region" {
  description = "Secondary region for disaster recovery and data replication"
  type        = string
  default     = "us-east1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.backup_region)
    error_message = "Backup region must be a valid Google Cloud region."
  }
}

variable "replica_zone" {
  description = "Zone for Bigtable replica cluster (used when replication is enabled)"
  type        = string
  default     = "us-east1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.replica_zone))
    error_message = "Replica zone must be a valid Google Cloud zone format."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and configuration (affects deletion protection)"
  type        = string
  default     = "development"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

# ============================================================================
# Cloud Bigtable Configuration
# ============================================================================

variable "bigtable_min_nodes" {
  description = "Minimum number of nodes for Bigtable cluster autoscaling"
  type        = number
  default     = 3
  
  validation {
    condition     = var.bigtable_min_nodes >= 1 && var.bigtable_min_nodes <= 100
    error_message = "Bigtable minimum nodes must be between 1 and 100."
  }
}

variable "bigtable_max_nodes" {
  description = "Maximum number of nodes for Bigtable cluster autoscaling"
  type        = number
  default     = 10
  
  validation {
    condition     = var.bigtable_max_nodes >= 1 && var.bigtable_max_nodes <= 1000
    error_message = "Bigtable maximum nodes must be between 1 and 1000."
  }
}

variable "enable_bigtable_replication" {
  description = "Enable Bigtable replication cluster for high availability and disaster recovery"
  type        = bool
  default     = false
}

# ============================================================================
# Cloud Functions Configuration
# ============================================================================

variable "max_function_instances" {
  description = "Maximum number of Cloud Function instances for auto-scaling"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_function_instances >= 1 && var.max_function_instances <= 3000
    error_message = "Maximum function instances must be between 1 and 3000."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout in seconds for Cloud Functions execution"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 3600
    error_message = "Function timeout must be between 1 and 3600 seconds."
  }
}

# ============================================================================
# Security and Access Configuration
# ============================================================================

variable "dashboard_public_access" {
  description = "Allow public access to fleet management dashboard (set false for internal-only access)"
  type        = bool
  default     = false
}

variable "enable_kms_encryption" {
  description = "Enable customer-managed encryption keys for data at rest"
  type        = bool
  default     = true
}

variable "allowed_source_ips" {
  description = "List of IP addresses/CIDR blocks allowed to access fleet services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = alltrue([
      for ip in var.allowed_source_ips : can(cidrhost(ip, 0))
    ])
    error_message = "All allowed source IPs must be valid CIDR notation."
  }
}

# ============================================================================
# Fleet Routing API Configuration
# ============================================================================

variable "maps_api_key" {
  description = "Google Maps Platform API key for Fleet Routing API (stored in Secret Manager)"
  type        = string
  default     = ""
  sensitive   = true
  
  validation {
    condition     = length(var.maps_api_key) == 0 || length(var.maps_api_key) >= 30
    error_message = "Maps API key must be empty (will be generated) or at least 30 characters long."
  }
}

variable "enable_route_optimization" {
  description = "Enable real-time route optimization using Fleet Routing API"
  type        = bool
  default     = true
}

variable "optimization_batch_size" {
  description = "Number of route optimization requests to process in a single batch"
  type        = number
  default     = 50
  
  validation {
    condition     = var.optimization_batch_size >= 1 && var.optimization_batch_size <= 1000
    error_message = "Optimization batch size must be between 1 and 1000."
  }
}

# ============================================================================
# Data Management Configuration
# ============================================================================

variable "data_retention_days" {
  description = "Number of days to retain historical traffic and location data"
  type        = number
  default     = 30
  
  validation {
    condition     = var.data_retention_days >= 1 && var.data_retention_days <= 365
    error_message = "Data retention must be between 1 and 365 days."
  }
}

variable "enable_data_cleanup" {
  description = "Enable automated data cleanup jobs for cost optimization"
  type        = bool
  default     = true
}

variable "backup_frequency_hours" {
  description = "Frequency in hours for automated data backups"
  type        = number
  default     = 24
  
  validation {
    condition     = contains([1, 2, 4, 6, 8, 12, 24], var.backup_frequency_hours)
    error_message = "Backup frequency must be one of: 1, 2, 4, 6, 8, 12, 24 hours."
  }
}

# ============================================================================
# Monitoring and Alerting Configuration
# ============================================================================

variable "enable_monitoring_alerts" {
  description = "Enable Cloud Monitoring alerts for system health and performance"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain Cloud Function and system logs"
  type        = number
  default     = 7
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days (10 years)."
  }
}

# ============================================================================
# Performance and Scaling Configuration
# ============================================================================

variable "pubsub_message_retention_hours" {
  description = "Hours to retain Pub/Sub messages for replay capability"
  type        = number
  default     = 168 # 7 days
  
  validation {
    condition     = var.pubsub_message_retention_hours >= 1 && var.pubsub_message_retention_hours <= 8760
    error_message = "Pub/Sub message retention must be between 1 hour and 1 year."
  }
}

variable "bigtable_cpu_target" {
  description = "Target CPU utilization percentage for Bigtable autoscaling"
  type        = number
  default     = 70
  
  validation {
    condition     = var.bigtable_cpu_target >= 10 && var.bigtable_cpu_target <= 90
    error_message = "Bigtable CPU target must be between 10% and 90%."
  }
}

variable "enable_high_availability" {
  description = "Enable high availability features (multi-region deployment, replication)"
  type        = bool
  default     = false
}

# ============================================================================
# Cost Optimization Configuration
# ============================================================================

variable "use_preemptible_instances" {
  description = "Use preemptible instances for non-critical workloads to reduce costs"
  type        = bool
  default     = false
}

variable "enable_committed_use_discounts" {
  description = "Enable committed use discounts for predictable workloads"
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "Storage class for Cloud Storage buckets (affects cost and performance)"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

# ============================================================================
# Development and Testing Configuration
# ============================================================================

variable "enable_debug_logging" {
  description = "Enable debug-level logging for development and troubleshooting"
  type        = bool
  default     = false
}

variable "simulate_traffic_events" {
  description = "Deploy traffic simulation functions for testing and development"
  type        = bool
  default     = false
}

variable "test_data_generation" {
  description = "Enable test data generation for development environments"
  type        = bool
  default     = false
}

# ============================================================================
# Compliance and Governance Configuration
# ============================================================================

variable "enable_audit_logging" {
  description = "Enable audit logging for compliance and security monitoring"
  type        = bool
  default     = true
}

variable "data_residency_region" {
  description = "Required data residency region for compliance (if different from primary region)"
  type        = string
  default     = ""
}

variable "encryption_key_rotation_days" {
  description = "Number of days between automatic encryption key rotations"
  type        = number
  default     = 90
  
  validation {
    condition     = var.encryption_key_rotation_days >= 30 && var.encryption_key_rotation_days <= 365
    error_message = "Key rotation period must be between 30 and 365 days."
  }
}

# ============================================================================
# Resource Tagging and Organization
# ============================================================================

variable "resource_labels" {
  description = "Additional labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default = {
    application = "fleet-optimization"
    managed-by  = "terraform"
    team        = "logistics"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.resource_labels : can(regex("^[a-z][a-z0-9_-]*$", k))
    ])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "cost_center" {
  description = "Cost center code for billing and resource allocation tracking"
  type        = string
  default     = "logistics"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cost_center))
    error_message = "Cost center must contain only lowercase letters, numbers, and hyphens."
  }
}

# ============================================================================
# Network and Connectivity Configuration
# ============================================================================

variable "vpc_network_name" {
  description = "Name of existing VPC network for resource deployment (leave empty to use default)"
  type        = string
  default     = ""
}

variable "subnet_name" {
  description = "Name of existing subnet for resource deployment (leave empty to use default)"
  type        = string
  default     = ""
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for secure communication with Google APIs"
  type        = bool
  default     = true
}

# ============================================================================
# Fleet-Specific Configuration
# ============================================================================

variable "max_vehicles_per_optimization" {
  description = "Maximum number of vehicles to include in a single route optimization request"
  type        = number
  default     = 100
  
  validation {
    condition     = var.max_vehicles_per_optimization >= 1 && var.max_vehicles_per_optimization <= 1000
    error_message = "Maximum vehicles per optimization must be between 1 and 1000."
  }
}

variable "vehicle_capacity_units" {
  description = "Units for vehicle capacity measurement (e.g., 'kg', 'lbs', 'cubic_meters')"
  type        = string
  default     = "kg"
  
  validation {
    condition     = contains(["kg", "lbs", "cubic_meters", "cubic_feet", "packages"], var.vehicle_capacity_units)
    error_message = "Vehicle capacity units must be one of: kg, lbs, cubic_meters, cubic_feet, packages."
  }
}

variable "default_vehicle_speed_kmh" {
  description = "Default vehicle speed in km/h for route calculations when real-time data is unavailable"
  type        = number
  default     = 50
  
  validation {
    condition     = var.default_vehicle_speed_kmh >= 1 && var.default_vehicle_speed_kmh <= 150
    error_message = "Default vehicle speed must be between 1 and 150 km/h."
  }
}

variable "optimization_objectives" {
  description = "List of optimization objectives (e.g., minimize_travel_time, minimize_distance, minimize_cost)"
  type        = list(string)
  default     = ["minimize_travel_time", "minimize_distance"]
  
  validation {
    condition = alltrue([
      for obj in var.optimization_objectives : contains([
        "minimize_travel_time", "minimize_distance", "minimize_cost", 
        "maximize_utilization", "minimize_emissions"
      ], obj)
    ])
    error_message = "Optimization objectives must be valid values: minimize_travel_time, minimize_distance, minimize_cost, maximize_utilization, minimize_emissions."
  }
}