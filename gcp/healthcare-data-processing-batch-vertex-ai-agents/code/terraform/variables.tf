# Healthcare Data Processing Variables
# Configuration variables for the healthcare data processing infrastructure

variable "project_id" {
  description = "Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty."
  }
}

variable "region" {
  description = "Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region that supports Healthcare API."
  }
}

variable "zone" {
  description = "Google Cloud zone for resources that require zone specification"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone must not be empty."
  }
}

variable "environment" {
  description = "Environment name for resource labeling and identification"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains([
      "dev", "development", "test", "testing", "staging", "stage", 
      "prod", "production", "demo", "sandbox"
    ], var.environment)
    error_message = "Environment must be one of: dev, development, test, testing, staging, stage, prod, production, demo, sandbox."
  }
}

variable "healthcare_bucket_prefix" {
  description = "Prefix for the healthcare data storage bucket name"
  type        = string
  default     = "healthcare-data"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.healthcare_bucket_prefix))
    error_message = "Bucket prefix must contain only lowercase letters, numbers, and hyphens, and must start and end with a letter or number."
  }
}

variable "healthcare_dataset_prefix" {
  description = "Prefix for the healthcare dataset name"
  type        = string
  default     = "healthcare_dataset"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.healthcare_dataset_prefix))
    error_message = "Dataset prefix must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "fhir_store_prefix" {
  description = "Prefix for the FHIR store name"
  type        = string
  default     = "patient_records"
  
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.fhir_store_prefix))
    error_message = "FHIR store prefix must start with a letter and contain only letters, numbers, and underscores."
  }
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical healthcare resources"
  type        = bool
  default     = true
}

variable "healthcare_data_retention_days" {
  description = "Number of days to retain healthcare data before deletion (minimum 2555 days / 7 years for compliance)"
  type        = number
  default     = 2555
  
  validation {
    condition     = var.healthcare_data_retention_days >= 2555
    error_message = "Healthcare data must be retained for at least 7 years (2555 days) for compliance."
  }
}

variable "batch_job_machine_type" {
  description = "Machine type for Cloud Batch processing jobs"
  type        = string
  default     = "e2-standard-2"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4", "e2-standard-8", "e2-standard-16",
      "n1-standard-1", "n1-standard-2", "n1-standard-4", "n1-standard-8", "n1-standard-16",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-standard-16", "n2-standard-32",
      "c2-standard-4", "c2-standard-8", "c2-standard-16", "c2-standard-30"
    ], var.batch_job_machine_type)
    error_message = "Machine type must be a valid Google Cloud machine type."
  }
}

variable "batch_job_cpu_milli" {
  description = "CPU allocation in millicores for batch processing tasks"
  type        = number
  default     = 2000
  
  validation {
    condition     = var.batch_job_cpu_milli >= 1000 && var.batch_job_cpu_milli <= 8000
    error_message = "CPU allocation must be between 1000 and 8000 millicores."
  }
}

variable "batch_job_memory_mib" {
  description = "Memory allocation in MiB for batch processing tasks"
  type        = number
  default     = 4096
  
  validation {
    condition     = var.batch_job_memory_mib >= 1024 && var.batch_job_memory_mib <= 32768
    error_message = "Memory allocation must be between 1024 and 32768 MiB."
  }
}

variable "batch_job_max_retry_count" {
  description = "Maximum number of retries for failed batch jobs"
  type        = number
  default     = 3
  
  validation {
    condition     = var.batch_job_max_retry_count >= 0 && var.batch_job_max_retry_count <= 10
    error_message = "Max retry count must be between 0 and 10."
  }
}

variable "batch_job_max_run_duration" {
  description = "Maximum runtime duration for batch jobs in seconds"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.batch_job_max_run_duration >= 300 && var.batch_job_max_run_duration <= 86400
    error_message = "Max run duration must be between 300 seconds (5 minutes) and 86400 seconds (24 hours)."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  type        = string
  default     = "512Mi"
  
  validation {
    condition = contains([
      "128Mi", "256Mi", "512Mi", "1Gi", "2Gi", "4Gi", "8Gi"
    ], var.function_memory)
    error_message = "Function memory must be one of: 128Mi, 256Mi, 512Mi, 1Gi, 2Gi, 4Gi, 8Gi."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for the Cloud Function in seconds"
  type        = number
  default     = 540
  
  validation {
    condition     = var.function_timeout_seconds >= 60 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 60 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 100
    error_message = "Max instances must be between 1 and 100."
  }
}

variable "enable_audit_logs" {
  description = "Enable comprehensive audit logging for HIPAA compliance"
  type        = bool
  default     = true
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts for compliance and operational issues"
  type        = bool
  default     = true
}

variable "alert_notification_channels" {
  description = "List of notification channel IDs for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "fhir_version" {
  description = "FHIR version for the healthcare store"
  type        = string
  default     = "R4"
  
  validation {
    condition = contains([
      "DSTU2", "STU3", "R4"
    ], var.fhir_version)
    error_message = "FHIR version must be one of: DSTU2, STU3, R4."
  }
}

variable "enable_fhir_versioning" {
  description = "Enable versioning for FHIR resources to maintain audit trails"
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "Storage class for the healthcare data bucket"
  type        = string
  default     = "STANDARD"
  
  validation {
    condition = contains([
      "STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"
    ], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for enhanced security"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    purpose    = "healthcare-processing"
    compliance = "hipaa"
  }
  
  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z0-9_-]{1,63}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "Label keys and values must contain only lowercase letters, numbers, underscores, and hyphens, with keys being 1-63 characters and values 0-63 characters."
  }
}

variable "vertex_ai_region" {
  description = "Region for Vertex AI services (may differ from main region for service availability)"
  type        = string
  default     = ""
  
  validation {
    condition = var.vertex_ai_region == "" || contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4",
      "asia-east1", "asia-northeast1", "asia-southeast1"
    ], var.vertex_ai_region)
    error_message = "Vertex AI region must be empty (will use main region) or a valid Vertex AI region."
  }
}

variable "bigquery_location" {
  description = "Location for BigQuery dataset (for analytics and audit logs)"
  type        = string
  default     = ""
  
  validation {
    condition = var.bigquery_location == "" || contains([
      "US", "EU", "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west4",
      "europe-north1", "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
      "asia-south1", "asia-southeast1", "asia-southeast2", "australia-southeast1"
    ], var.bigquery_location)
    error_message = "BigQuery location must be empty (will use main region) or a valid BigQuery location."
  }
}

variable "enable_vpc_connector" {
  description = "Enable VPC connector for Cloud Functions to access private resources"
  type        = bool
  default     = false
}

variable "vpc_connector_name" {
  description = "Name of the VPC connector (required if enable_vpc_connector is true)"
  type        = string
  default     = ""
}

variable "monitoring_dashboard_name" {
  description = "Name for the monitoring dashboard"
  type        = string
  default     = "Healthcare Data Processing Dashboard"
  
  validation {
    condition     = length(var.monitoring_dashboard_name) > 0 && length(var.monitoring_dashboard_name) <= 100
    error_message = "Dashboard name must be between 1 and 100 characters."
  }
}