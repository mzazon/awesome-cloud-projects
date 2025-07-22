# Variables for Global Network Performance Optimization with Cloud WAN and Network Intelligence Center
# This file defines all input variables for the Terraform configuration

variable "project_id" {
  description = "The Google Cloud Project ID"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "primary_region" {
  description = "Primary Google Cloud region"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2",
      "europe-west1", "europe-west2", "europe-west3",
      "asia-east1", "asia-southeast1", "asia-northeast1"
    ], var.primary_region)
    error_message = "Primary region must be a valid Google Cloud region."
  }
}

variable "regions" {
  description = "Map of regions for multi-region deployment"
  type = map(object({
    name      = string
    zone      = string
    subnet_cidr = string
  }))
  default = {
    us = {
      name        = "us-central1"
      zone        = "us-central1-a"
      subnet_cidr = "10.10.0.0/16"
    }
    eu = {
      name        = "europe-west1"
      zone        = "europe-west1-b"
      subnet_cidr = "10.20.0.0/16"
    }
    apac = {
      name        = "asia-east1"
      zone        = "asia-east1-a"
      subnet_cidr = "10.30.0.0/16"
    }
  }
}

variable "network_name" {
  description = "Name for the global VPC network"
  type        = string
  default     = "global-wan"
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for Network Intelligence Center"
  type        = bool
  default     = true
}

variable "flow_logs_sampling" {
  description = "Sampling rate for VPC Flow Logs (0.0 to 1.0)"
  type        = number
  default     = 1.0
  validation {
    condition     = var.flow_logs_sampling >= 0.0 && var.flow_logs_sampling <= 1.0
    error_message = "Flow logs sampling must be between 0.0 and 1.0."
  }
}

variable "flow_logs_interval" {
  description = "Aggregation interval for VPC Flow Logs"
  type        = string
  default     = "INTERVAL_5_SEC"
  validation {
    condition = contains([
      "INTERVAL_5_SEC", "INTERVAL_30_SEC", "INTERVAL_1_MIN", 
      "INTERVAL_5_MIN", "INTERVAL_10_MIN", "INTERVAL_15_MIN"
    ], var.flow_logs_interval)
    error_message = "Flow logs interval must be a valid aggregation interval."
  }
}

variable "machine_type" {
  description = "Machine type for compute instances"
  type        = string
  default     = "e2-medium"
}

variable "instance_image" {
  description = "VM instance image configuration"
  type = object({
    family  = string
    project = string
  })
  default = {
    family  = "ubuntu-2004-lts"
    project = "ubuntu-os-cloud"
  }
}

variable "ssl_certificate_domains" {
  description = "List of domains for SSL certificate (use example domains for testing)"
  type        = list(string)
  default     = ["example.com"]
}

variable "health_check_config" {
  description = "Configuration for load balancer health checks"
  type = object({
    port               = number
    request_path       = string
    check_interval_sec = number
    timeout_sec        = number
    healthy_threshold  = number
    unhealthy_threshold = number
  })
  default = {
    port                = 80
    request_path        = "/"
    check_interval_sec  = 30
    timeout_sec         = 10
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

variable "enable_monitoring" {
  description = "Enable Cloud Monitoring and alerting"
  type        = bool
  default     = true
}

variable "monitoring_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Resource tags for organization and cost tracking"
  type        = map(string)
  default = {
    environment = "development"
    project     = "global-network-optimization"
    managed_by  = "terraform"
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain monitoring data and logs"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 3653
    error_message = "Backup retention days must be between 1 and 3653."
  }
}

variable "network_security_config" {
  description = "Network security configuration"
  type = object({
    enable_private_google_access = bool
    allowed_ssh_ranges          = list(string)
    allowed_health_check_ranges = list(string)
  })
  default = {
    enable_private_google_access = true
    allowed_ssh_ranges          = ["0.0.0.0/0"]  # Restrict this in production
    allowed_health_check_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  }
}