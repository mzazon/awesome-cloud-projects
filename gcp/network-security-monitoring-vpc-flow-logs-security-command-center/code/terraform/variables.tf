# Input variables for Network Security Monitoring Infrastructure
# This file defines all configurable parameters for the security monitoring solution

variable "project_id" {
  description = "The Google Cloud project ID where resources will be created"
  type        = string
  default     = null
  
  validation {
    condition     = var.project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for regional resources (VPC subnet, etc.)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1)."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources (VM instances)"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "environment" {
  description = "Environment name for resource labeling (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

# Network Configuration Variables

variable "vpc_name" {
  description = "Base name for the VPC network (will have random suffix appended)"
  type        = string
  default     = "security-monitoring-vpc"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}$", var.vpc_name))
    error_message = "VPC name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 62 chars)."
  }
}

variable "subnet_name" {
  description = "Base name for the VPC subnet (will have random suffix appended)"
  type        = string
  default     = "monitored-subnet"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}$", var.subnet_name))
    error_message = "Subnet name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 62 chars)."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the monitored subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block (e.g., 10.0.1.0/24)."
  }
}

variable "allowed_ssh_sources" {
  description = "List of CIDR blocks allowed to SSH to test instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_sources : can(cidrhost(cidr, 0))])
    error_message = "All SSH source ranges must be valid CIDR blocks."
  }
}

# Compute Instance Variables

variable "instance_name" {
  description = "Base name for the test VM instance (will have random suffix appended)"
  type        = string
  default     = "test-vm"
  
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}$", var.instance_name))
    error_message = "Instance name must start with lowercase letter and contain only lowercase letters, numbers, and hyphens (max 62 chars)."
  }
}

variable "machine_type" {
  description = "Machine type for the test VM instance"
  type        = string
  default     = "e2-micro"
  
  validation {
    condition     = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n1-standard-1", "n1-standard-2", "n1-standard-4",
      "n2-standard-2", "n2-standard-4", "n2-standard-8"
    ], var.machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

# Logging and Monitoring Variables

variable "log_sink_name" {
  description = "Base name for the logging sink (will have random suffix appended)"
  type        = string
  default     = "vpc-flow-security-sink"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,99}$", var.log_sink_name))
    error_message = "Log sink name must start with letter and contain only letters, numbers, underscores, and hyphens (max 100 chars)."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (US, EU, or specific region)"
  type        = string
  default     = "US"
  
  validation {
    condition     = contains(["US", "EU"] ++ [
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "europe-north1", "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2",
      "asia-northeast3", "asia-south1", "asia-southeast1", "asia-southeast2"
    ], var.bigquery_location)
    error_message = "BigQuery location must be US, EU, or a valid Google Cloud region."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain logs in BigQuery (0 = never delete)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 0 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 0 and 365."
  }
}

# Monitoring and Alerting Variables

variable "enable_monitoring_alerts" {
  description = "Whether to enable Cloud Monitoring alert policies"
  type        = bool
  default     = true
}

variable "notification_emails" {
  description = "List of email addresses for monitoring alert notifications"
  type        = list(string)
  default     = []
  
  validation {
    condition     = alltrue([for email in var.notification_emails : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All notification emails must be valid email addresses."
  }
}

variable "high_traffic_threshold_bytes" {
  description = "Threshold in bytes per second for high traffic alert"
  type        = number
  default     = 1000000000  # 1 GB/s
  
  validation {
    condition     = var.high_traffic_threshold_bytes > 0
    error_message = "High traffic threshold must be greater than 0."
  }
}

variable "suspicious_connections_threshold" {
  description = "Threshold for number of connections per minute that triggers suspicious activity alert"
  type        = number
  default     = 100
  
  validation {
    condition     = var.suspicious_connections_threshold > 0
    error_message = "Suspicious connections threshold must be greater than 0."
  }
}

# Security Configuration Variables

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs (should generally be true for security monitoring)"
  type        = bool
  default     = true
}

variable "flow_log_sampling_rate" {
  description = "Sampling rate for VPC Flow Logs (0.0 to 1.0, where 1.0 = 100% sampling)"
  type        = number
  default     = 1.0
  
  validation {
    condition     = var.flow_log_sampling_rate >= 0.0 && var.flow_log_sampling_rate <= 1.0
    error_message = "Flow log sampling rate must be between 0.0 and 1.0."
  }
}

variable "flow_log_aggregation_interval" {
  description = "Aggregation interval for VPC Flow Logs"
  type        = string
  default     = "INTERVAL_5_SEC"
  
  validation {
    condition     = contains(["INTERVAL_5_SEC", "INTERVAL_30_SEC", "INTERVAL_1_MIN", "INTERVAL_5_MIN", "INTERVAL_10_MIN", "INTERVAL_15_MIN"], var.flow_log_aggregation_interval)
    error_message = "Flow log aggregation interval must be one of: INTERVAL_5_SEC, INTERVAL_30_SEC, INTERVAL_1_MIN, INTERVAL_5_MIN, INTERVAL_10_MIN, INTERVAL_15_MIN."
  }
}

# Resource Naming and Tagging

variable "resource_prefix" {
  description = "Prefix to add to all resource names (optional)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.resource_prefix == "" || can(regex("^[a-z][a-z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must start with lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "additional_labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = alltrue([for k, v in var.additional_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k))])
    error_message = "Label keys must start with lowercase letter and contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
  
  validation {
    condition     = alltrue([for k, v in var.additional_labels : can(regex("^[a-z0-9_-]{0,63}$", v))])
    error_message = "Label values must contain only lowercase letters, numbers, underscores, and hyphens (max 63 chars)."
  }
}

# Cost Control Variables

variable "enable_preemptible_instances" {
  description = "Whether to use preemptible instances for cost savings (not recommended for production)"
  type        = bool
  default     = false
}

variable "auto_delete_boot_disks" {
  description = "Whether to automatically delete boot disks when instances are deleted"
  type        = bool
  default     = true
}

# Advanced Configuration

variable "enable_oslogin" {
  description = "Whether to enable OS Login for SSH access management"
  type        = bool
  default     = false
}

variable "enable_confidential_computing" {
  description = "Whether to enable Confidential Computing for VM instances"
  type        = bool
  default     = false
}

variable "custom_metadata" {
  description = "Custom metadata to apply to VM instances"
  type        = map(string)
  default     = {}
}

# Network Security Variables

variable "enable_private_google_access" {
  description = "Whether to enable Private Google Access for the subnet"
  type        = bool
  default     = true
}

variable "enable_cloud_nat" {
  description = "Whether to create Cloud NAT for outbound internet access from private instances"
  type        = bool
  default     = false
}

variable "allowed_ports" {
  description = "List of additional ports to allow in firewall rules"
  type        = list(number)
  default     = []
  
  validation {
    condition     = alltrue([for port in var.allowed_ports : port >= 1 && port <= 65535])
    error_message = "All ports must be between 1 and 65535."
  }
}