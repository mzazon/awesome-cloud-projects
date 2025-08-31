# Input variables for Energy-Efficient Web Hosting with C4A and Hyperdisk
# These variables allow customization of the infrastructure deployment
# while maintaining energy efficiency and performance optimization

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment (C4A availability required)"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east4", "us-east1", 
      "eu-west1", "eu-west4", "eu-west3", 
      "asia-southeast1"
    ], var.region)
    error_message = "Region must support C4A instances with Axion processors."
  }
}

variable "zone" {
  description = "The Google Cloud zone for compute resources"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name for resource tagging and organization"
  type        = string
  default     = "energy-efficient-web"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "instance_count" {
  description = "Number of C4A instances to deploy for load balancing"
  type        = number
  default     = 3
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}

variable "machine_type" {
  description = "C4A machine type with Axion processors for energy efficiency"
  type        = string
  default     = "c4a-standard-4"
  validation {
    condition = startswith(var.machine_type, "c4a-")
    error_message = "Machine type must be a C4A instance type for ARM-based Axion processors."
  }
}

variable "disk_size_gb" {
  description = "Size of Hyperdisk Balanced volumes in GB for each instance"
  type        = number
  default     = 50
  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 1000
    error_message = "Disk size must be between 10 GB and 1000 GB."
  }
}

variable "disk_provisioned_iops" {
  description = "Provisioned IOPS for Hyperdisk Balanced storage performance"
  type        = number
  default     = 3000
  validation {
    condition     = var.disk_provisioned_iops >= 3000 && var.disk_provisioned_iops <= 100000
    error_message = "Provisioned IOPS must be between 3000 and 100000."
  }
}

variable "disk_provisioned_throughput" {
  description = "Provisioned throughput in MB/s for Hyperdisk Balanced storage"
  type        = number
  default     = 140
  validation {
    condition     = var.disk_provisioned_throughput >= 140 && var.disk_provisioned_throughput <= 7500
    error_message = "Provisioned throughput must be between 140 MB/s and 7500 MB/s."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "web_server_image_family" {
  description = "Operating system image family for web server instances"
  type        = string
  default     = "ubuntu-2004-lts"
}

variable "web_server_image_project" {
  description = "Google Cloud project containing the OS image"
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "health_check_interval" {
  description = "Health check interval in seconds for load balancer monitoring"
  type        = number
  default     = 30
  validation {
    condition     = var.health_check_interval >= 10 && var.health_check_interval <= 300
    error_message = "Health check interval must be between 10 and 300 seconds."
  }
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
  validation {
    condition     = var.health_check_timeout >= 5 && var.health_check_timeout <= 60
    error_message = "Health check timeout must be between 5 and 60 seconds."
  }
}

variable "healthy_threshold" {
  description = "Number of successful health checks before marking instance healthy"
  type        = number
  default     = 2
  validation {
    condition     = var.healthy_threshold >= 1 && var.healthy_threshold <= 10
    error_message = "Healthy threshold must be between 1 and 10."
  }
}

variable "unhealthy_threshold" {
  description = "Number of failed health checks before marking instance unhealthy"
  type        = number
  default     = 3
  validation {
    condition     = var.unhealthy_threshold >= 1 && var.unhealthy_threshold <= 10
    error_message = "Unhealthy threshold must be between 1 and 10."
  }
}

variable "enable_monitoring_dashboard" {
  description = "Whether to create Cloud Monitoring dashboard for energy efficiency tracking"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources for organization and cost tracking"
  type        = map(string)
  default = {
    architecture     = "arm64"
    processor        = "axion"
    energy_efficient = "true"
    workload_type    = "web_hosting"
  }
}