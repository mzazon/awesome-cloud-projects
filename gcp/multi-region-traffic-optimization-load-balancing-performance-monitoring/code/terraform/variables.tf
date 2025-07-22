# Project and Resource Naming Variables
variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "traffic-opt"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_prefix))
    error_message = "Resource prefix must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

# Regional Configuration Variables
variable "primary_region" {
  description = "Primary region for resource deployment (US)"
  type        = string
  default     = "us-central1"
}

variable "secondary_region" {
  description = "Secondary region for resource deployment (Europe)"
  type        = string
  default     = "europe-west1"
}

variable "tertiary_region" {
  description = "Tertiary region for resource deployment (Asia-Pacific)"
  type        = string
  default     = "asia-southeast1"
}

variable "primary_zone" {
  description = "Primary zone within the primary region"
  type        = string
  default     = "us-central1-a"
}

variable "secondary_zone" {
  description = "Secondary zone within the secondary region"
  type        = string
  default     = "europe-west1-b"
}

variable "tertiary_zone" {
  description = "Tertiary zone within the tertiary region"
  type        = string
  default     = "asia-southeast1-a"
}

# Network Configuration Variables
variable "vpc_cidr_ranges" {
  description = "CIDR ranges for regional subnets"
  type = object({
    us_subnet   = string
    eu_subnet   = string
    apac_subnet = string
  })
  default = {
    us_subnet   = "10.1.0.0/24"
    eu_subnet   = "10.2.0.0/24"
    apac_subnet = "10.3.0.0/24"
  }
}

# Compute Configuration Variables
variable "instance_machine_type" {
  description = "Machine type for compute instances"
  type        = string
  default     = "e2-medium"
  validation {
    condition     = contains(["e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4"], var.instance_machine_type)
    error_message = "Machine type must be a valid e2 instance type."
  }
}

variable "instance_group_size" {
  description = "Number of instances per regional instance group"
  type        = number
  default     = 2
  validation {
    condition     = var.instance_group_size >= 1 && var.instance_group_size <= 10
    error_message = "Instance group size must be between 1 and 10."
  }
}

variable "instance_image_family" {
  description = "OS image family for compute instances"
  type        = string
  default     = "debian-11"
}

variable "instance_image_project" {
  description = "Project containing the OS image"
  type        = string
  default     = "debian-cloud"
}

# Load Balancer Configuration Variables
variable "health_check_settings" {
  description = "Health check configuration for load balancer"
  type = object({
    port                = number
    request_path        = string
    check_interval_sec  = number
    timeout_sec         = number
    healthy_threshold   = number
    unhealthy_threshold = number
  })
  default = {
    port                = 8080
    request_path        = "/"
    check_interval_sec  = 10
    timeout_sec         = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

variable "backend_service_settings" {
  description = "Backend service configuration for load balancing"
  type = object({
    capacity_scaler    = number
    max_utilization    = number
    balancing_mode     = string
    locality_lb_policy = string
  })
  default = {
    capacity_scaler    = 1.0
    max_utilization    = 0.8
    balancing_mode     = "UTILIZATION"
    locality_lb_policy = "ROUND_ROBIN"
  }
}

# CDN Configuration Variables
variable "cdn_settings" {
  description = "Cloud CDN configuration settings"
  type = object({
    cache_mode      = string
    default_ttl     = number
    max_ttl         = number
    client_ttl      = number
    compression     = bool
    negative_caching = bool
  })
  default = {
    cache_mode       = "CACHE_ALL_STATIC"
    default_ttl      = 3600
    max_ttl          = 86400
    client_ttl       = 3600
    compression      = true
    negative_caching = true
  }
}

# Circuit Breaker Configuration Variables
variable "circuit_breaker_settings" {
  description = "Circuit breaker configuration for resilience"
  type = object({
    max_requests         = number
    max_pending_requests = number
    max_retries          = number
    max_connections      = number
  })
  default = {
    max_requests         = 1000
    max_pending_requests = 100
    max_retries          = 3
    max_connections      = 1000
  }
}

# Outlier Detection Configuration Variables
variable "outlier_detection_settings" {
  description = "Outlier detection configuration for backend health"
  type = object({
    consecutive_errors           = number
    consecutive_gateway_failure  = number
    interval_sec                = number
    base_ejection_time_sec      = number
    max_ejection_percent        = number
  })
  default = {
    consecutive_errors          = 5
    consecutive_gateway_failure = 3
    interval_sec               = 30
    base_ejection_time_sec     = 30
    max_ejection_percent       = 10
  }
}

# Monitoring Configuration Variables
variable "monitoring_settings" {
  description = "Cloud Monitoring configuration"
  type = object({
    uptime_check_timeout     = string
    uptime_check_period      = string
    alert_latency_threshold  = number
    alert_duration           = string
  })
  default = {
    uptime_check_timeout    = "10s"
    uptime_check_period     = "60s"
    alert_latency_threshold = 1.0
    alert_duration          = "120s"
  }
}

# Enable Services Configuration
variable "enable_apis" {
  description = "Whether to enable required GCP APIs"
  type        = bool
  default     = true
}

variable "enable_network_intelligence" {
  description = "Whether to enable Network Intelligence Center features"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable Cloud Monitoring features"
  type        = bool
  default     = true
}

# Security and Access Variables
variable "allowed_source_ranges" {
  description = "CIDR ranges allowed to access the application"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssl_certificates" {
  description = "List of SSL certificate names for HTTPS load balancing"
  type        = list(string)
  default     = []
}

# Labels and Tags
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "production"
    project     = "traffic-optimization"
    managed-by  = "terraform"
  }
}