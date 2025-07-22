# ==============================================================================
# Service Discovery with Traffic Director and Cloud DNS - Variables
# ==============================================================================

# Project Configuration
variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region (e.g., us-central1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and naming"
  type        = string
  default     = "dev"
  validation {
    condition = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# Service Configuration
variable "service_name" {
  description = "Base name for the microservice (will have random suffix added)"
  type        = string
  default     = "microservice"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_name))
    error_message = "Service name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "dns_zone_name" {
  description = "Base name for the DNS zone (will have random suffix added)"
  type        = string
  default     = "discovery-zone"
  validation {
    condition = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.dns_zone_name))
    error_message = "DNS zone name must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number."
  }
}

variable "base_domain" {
  description = "Base domain for service discovery (e.g., example.com)"
  type        = string
  default     = "example.com"
  validation {
    condition = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\\.[a-zA-Z]{2,}$", var.base_domain))
    error_message = "Base domain must be a valid domain name."
  }
}

# Network Configuration
variable "subnet_cidr" {
  description = "CIDR block for the service mesh subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "service_vip" {
  description = "Virtual IP address for the Traffic Director forwarding rule"
  type        = string
  default     = "10.0.1.100"
  validation {
    condition = can(regex("^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.service_vip))
    error_message = "Service VIP must be a valid IPv4 address."
  }
}

# Compute Configuration
variable "machine_type" {
  description = "Machine type for service instances"
  type        = string
  default     = "e2-medium"
  validation {
    condition = can(regex("^[a-z][0-9]+-[a-z]+$", var.machine_type))
    error_message = "Machine type must be a valid Google Cloud machine type (e.g., e2-medium)."
  }
}

variable "source_image" {
  description = "Source image for service instances"
  type        = string
  default     = "projects/debian-cloud/global/images/family/debian-11"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB for service instances"
  type        = number
  default     = 20
  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 1000
    error_message = "Disk size must be between 10 and 1000 GB."
  }
}

variable "instances_per_zone" {
  description = "Number of service instances to deploy per zone"
  type        = number
  default     = 2
  validation {
    condition     = var.instances_per_zone >= 1 && var.instances_per_zone <= 10
    error_message = "Instances per zone must be between 1 and 10."
  }
}

variable "assign_external_ip" {
  description = "Whether to assign external IP addresses to instances"
  type        = bool
  default     = false
}

# DNS Configuration
variable "create_public_dns" {
  description = "Whether to create a public DNS zone for external access"
  type        = bool
  default     = false
}

variable "dns_ttl" {
  description = "TTL for DNS records in seconds"
  type        = number
  default     = 300
  validation {
    condition     = var.dns_ttl >= 60 && var.dns_ttl <= 86400
    error_message = "DNS TTL must be between 60 and 86400 seconds."
  }
}

variable "health_dns_ttl" {
  description = "TTL for health check DNS records in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.health_dns_ttl >= 30 && var.health_dns_ttl <= 300
    error_message = "Health DNS TTL must be between 30 and 300 seconds."
  }
}

# Health Check Configuration
variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
  validation {
    condition     = var.health_check_timeout >= 1 && var.health_check_timeout <= 300
    error_message = "Health check timeout must be between 1 and 300 seconds."
  }
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10
  validation {
    condition     = var.health_check_interval >= 5 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "health_check_healthy_threshold" {
  description = "Number of consecutive successful health checks before marking healthy"
  type        = number
  default     = 2
  validation {
    condition     = var.health_check_healthy_threshold >= 1 && var.health_check_healthy_threshold <= 10
    error_message = "Healthy threshold must be between 1 and 10."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Number of consecutive failed health checks before marking unhealthy"
  type        = number
  default     = 3
  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 2 and 10."
  }
}

# Traffic Director Configuration
variable "locality_lb_policy" {
  description = "Load balancing policy for Traffic Director"
  type        = string
  default     = "ROUND_ROBIN"
  validation {
    condition = contains([
      "ROUND_ROBIN",
      "LEAST_REQUEST",
      "RING_HASH",
      "RANDOM",
      "ORIGINAL_DESTINATION",
      "MAGLEV"
    ], var.locality_lb_policy)
    error_message = "Locality LB policy must be one of: ROUND_ROBIN, LEAST_REQUEST, RING_HASH, RANDOM, ORIGINAL_DESTINATION, MAGLEV."
  }
}

variable "connection_draining_timeout" {
  description = "Connection draining timeout in seconds"
  type        = number
  default     = 60
  validation {
    condition     = var.connection_draining_timeout >= 0 && var.connection_draining_timeout <= 3600
    error_message = "Connection draining timeout must be between 0 and 3600 seconds."
  }
}

variable "max_rate_per_endpoint" {
  description = "Maximum requests per second per endpoint"
  type        = number
  default     = 100
  validation {
    condition     = var.max_rate_per_endpoint >= 1 && var.max_rate_per_endpoint <= 10000
    error_message = "Max rate per endpoint must be between 1 and 10000."
  }
}

# Circuit Breaker Configuration
variable "max_requests_per_connection" {
  description = "Maximum requests per connection for circuit breaker"
  type        = number
  default     = 1000
  validation {
    condition     = var.max_requests_per_connection >= 1
    error_message = "Max requests per connection must be at least 1."
  }
}

variable "max_connections" {
  description = "Maximum connections for circuit breaker"
  type        = number
  default     = 1000
  validation {
    condition     = var.max_connections >= 1
    error_message = "Max connections must be at least 1."
  }
}

variable "max_pending_requests" {
  description = "Maximum pending requests for circuit breaker"
  type        = number
  default     = 100
  validation {
    condition     = var.max_pending_requests >= 1
    error_message = "Max pending requests must be at least 1."
  }
}

variable "max_retries" {
  description = "Maximum retries for circuit breaker"
  type        = number
  default     = 3
  validation {
    condition     = var.max_retries >= 0 && var.max_retries <= 10
    error_message = "Max retries must be between 0 and 10."
  }
}

# Outlier Detection Configuration
variable "consecutive_errors" {
  description = "Number of consecutive errors before ejection"
  type        = number
  default     = 3
  validation {
    condition     = var.consecutive_errors >= 1 && var.consecutive_errors <= 10
    error_message = "Consecutive errors must be between 1 and 10."
  }
}

variable "outlier_detection_interval" {
  description = "Outlier detection interval in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.outlier_detection_interval >= 1 && var.outlier_detection_interval <= 300
    error_message = "Outlier detection interval must be between 1 and 300 seconds."
  }
}

variable "base_ejection_time" {
  description = "Base ejection time in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.base_ejection_time >= 1 && var.base_ejection_time <= 300
    error_message = "Base ejection time must be between 1 and 300 seconds."
  }
}

variable "max_ejection_percent" {
  description = "Maximum percentage of endpoints that can be ejected"
  type        = number
  default     = 50
  validation {
    condition     = var.max_ejection_percent >= 0 && var.max_ejection_percent <= 100
    error_message = "Max ejection percent must be between 0 and 100."
  }
}

variable "min_health_percent" {
  description = "Minimum percentage of healthy endpoints required"
  type        = number
  default     = 50
  validation {
    condition     = var.min_health_percent >= 0 && var.min_health_percent <= 100
    error_message = "Min health percent must be between 0 and 100."
  }
}

# Security Configuration
variable "enable_ssh" {
  description = "Whether to enable SSH access to instances"
  type        = bool
  default     = true
}

variable "ssh_source_ranges" {
  description = "Source IP ranges allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for cidr in var.ssh_source_ranges : can(cidrhost(cidr, 0))
    ])
    error_message = "All SSH source ranges must be valid CIDR blocks."
  }
}

# Testing Configuration
variable "create_test_client" {
  description = "Whether to create a test client instance for validation"
  type        = bool
  default     = true
}