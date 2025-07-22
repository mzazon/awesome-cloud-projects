# Input Variables for Hybrid Quantum-Classical AI Workflows
# These variables allow customization of the infrastructure deployment

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-south1",
      "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The Google Cloud zone for zonal resources"
  type        = string
  default     = "us-central1-a"
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid Google Cloud zone format (e.g., us-central1-a)."
  }
}

variable "prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = "quantum-portfolio"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.prefix))
    error_message = "Prefix must start with a letter, end with alphanumeric, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "random_suffix" {
  description = "Random suffix for unique resource naming (auto-generated if not provided)"
  type        = string
  default     = ""
}

# Storage Configuration
variable "storage_class" {
  description = "Storage class for Cloud Storage bucket"
  type        = string
  default     = "STANDARD"
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE", "REGIONAL", "MULTI_REGIONAL"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE, REGIONAL, MULTI_REGIONAL."
  }
}

variable "enable_versioning" {
  description = "Enable versioning for Cloud Storage bucket"
  type        = bool
  default     = true
}

# Vertex AI Configuration
variable "notebook_machine_type" {
  description = "Machine type for Vertex AI Workbench instance"
  type        = string
  default     = "n1-standard-4"
  validation {
    condition = contains([
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n1-highmem-2", "n1-highmem-4", "n1-highmem-8", "n1-highmem-16",
      "n1-highcpu-4", "n1-highcpu-8", "n1-highcpu-16"
    ], var.notebook_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "notebook_disk_size" {
  description = "Disk size for Vertex AI Workbench instance in GB"
  type        = number
  default     = 100
  validation {
    condition     = var.notebook_disk_size >= 20 && var.notebook_disk_size <= 1000
    error_message = "Disk size must be between 20 and 1000 GB."
  }
}

variable "notebook_disk_type" {
  description = "Disk type for Vertex AI Workbench instance"
  type        = string
  default     = "pd-standard"
  validation {
    condition = contains([
      "pd-standard", "pd-ssd", "pd-balanced"
    ], var.notebook_disk_type)
    error_message = "Disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# Cloud Functions Configuration
variable "function_memory" {
  description = "Memory allocation for Cloud Function in MB"
  type        = number
  default     = 1024
  validation {
    condition = contains([
      128, 256, 512, 1024, 2048, 4096, 8192
    ], var.function_memory)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout" {
  description = "Timeout for Cloud Function in seconds"
  type        = number
  default     = 540
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime for Cloud Function"
  type        = string
  default     = "python311"
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

# Quantum Computing Configuration
variable "enable_quantum_processor" {
  description = "Enable access to quantum processor (requires special approval)"
  type        = bool
  default     = false
}

variable "quantum_processor_id" {
  description = "Quantum processor ID (when available)"
  type        = string
  default     = ""
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable Cloud Monitoring for custom metrics"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 3653
    error_message = "Log retention must be between 1 and 3653 days."
  }
}

# Security Configuration
variable "enable_private_google_access" {
  description = "Enable Private Google Access for subnet"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

# Portfolio Optimization Configuration
variable "default_portfolio_size" {
  description = "Default number of assets in portfolio optimization"
  type        = number
  default     = 8
  validation {
    condition     = var.default_portfolio_size >= 4 && var.default_portfolio_size <= 20
    error_message = "Portfolio size must be between 4 and 20 assets for quantum processing."
  }
}

variable "default_risk_aversion" {
  description = "Default risk aversion parameter for portfolio optimization"
  type        = number
  default     = 1.0
  validation {
    condition     = var.default_risk_aversion >= 0.1 && var.default_risk_aversion <= 10.0
    error_message = "Risk aversion must be between 0.1 and 10.0."
  }
}

# Labels and Tagging
variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "development"
    project     = "quantum-portfolio-optimization"
    managed-by  = "terraform"
  }
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]*$", k)) && can(regex("^[a-z0-9_-]*$", v))
    ])
    error_message = "Label keys must start with a letter and contain only lowercase letters, numbers, underscores, and hyphens. Values must contain only lowercase letters, numbers, underscores, and hyphens."
  }
}

# Networking Configuration
variable "network_name" {
  description = "Name of the VPC network (creates new if not exists)"
  type        = string
  default     = "quantum-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
  default     = "quantum-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.0.0/24"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR notation."
  }
}