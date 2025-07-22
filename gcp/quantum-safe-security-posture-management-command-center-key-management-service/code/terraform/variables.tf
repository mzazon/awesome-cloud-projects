# ============================================================================
# Variables for Quantum-Safe Security Posture Management
# ============================================================================
# This file defines all configurable parameters for the quantum-safe security
# posture management infrastructure deployment on Google Cloud Platform.

# ============================================================================
# Project and Organization Configuration
# ============================================================================

variable "project_id" {
  description = "GCP Project ID for quantum security implementation. Must be globally unique."
  type        = string
  default     = "quantum-security-posture"

  validation {
    condition     = can(regex("^[a-z0-9-]{6,30}$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "organization_id" {
  description = "GCP Organization ID where quantum security policies will be applied. Required for Security Command Center Enterprise."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "Organization ID must be a numeric string."
  }
}

variable "billing_account" {
  description = "Billing account ID to associate with the quantum security project. Format: XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "Billing account must be in format XXXXXX-XXXXXX-XXXXXX."
  }
}

# ============================================================================
# Regional and Zone Configuration
# ============================================================================

variable "region" {
  description = "Primary GCP region for quantum security infrastructure deployment."
  type        = string
  default     = "us-central1"

  validation {
    condition = contains([
      "us-central1", "us-east1", "us-east4", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-east2", "asia-northeast1", "asia-southeast1", "asia-south1"
    ], var.region)
    error_message = "Region must be a valid GCP region that supports all required services."
  }
}

variable "zone" {
  description = "Primary GCP zone within the specified region for resource placement."
  type        = string
  default     = "us-central1-a"

  validation {
    condition     = can(regex("^[a-z0-9-]+-[a-z]$", var.zone))
    error_message = "Zone must be a valid GCP zone format (region-letter)."
  }
}

# ============================================================================
# KMS and Post-Quantum Cryptography Configuration
# ============================================================================

variable "kms_keyring_name" {
  description = "Name for the quantum-safe KMS keyring. Must be unique within the region."
  type        = string
  default     = "quantum-safe-keyring"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,63}$", var.kms_keyring_name))
    error_message = "KMS keyring name must be 1-63 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "kms_key_name" {
  description = "Base name for quantum-safe cryptographic keys. Algorithm suffixes will be appended."
  type        = string
  default     = "quantum-safe-key"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,63}$", var.kms_key_name))
    error_message = "KMS key name must be 1-63 characters, alphanumeric, hyphens, and underscores only."
  }
}

variable "kms_key_rotation_period" {
  description = "Automatic key rotation period for quantum agility. Format: seconds (s). Minimum 24 hours."
  type        = string
  default     = "2592000s" # 30 days

  validation {
    condition     = can(regex("^[0-9]+s$", var.kms_key_rotation_period))
    error_message = "Rotation period must be in seconds format (e.g., '2592000s' for 30 days)."
  }
}

variable "pq_algorithms" {
  description = "Post-quantum cryptography algorithms to deploy for quantum-resistant security."
  type = object({
    ml_dsa  = string
    slh_dsa = string
  })
  default = {
    ml_dsa  = "PQ_SIGN_ML_DSA_65"     # NIST FIPS 204 - Module-Lattice-Based Digital Signature Algorithm
    slh_dsa = "PQ_SIGN_SLH_DSA_SHA2_128S" # NIST FIPS 205 - Stateless Hash-Based Digital Signature Algorithm
  }

  validation {
    condition = alltrue([
      contains(["PQ_SIGN_ML_DSA_65", "PQ_SIGN_ML_DSA_87"], var.pq_algorithms.ml_dsa),
      contains(["PQ_SIGN_SLH_DSA_SHA2_128S", "PQ_SIGN_SLH_DSA_SHA2_192S", "PQ_SIGN_SLH_DSA_SHA2_256S"], var.pq_algorithms.slh_dsa)
    ])
    error_message = "Algorithm values must be valid NIST-approved post-quantum cryptography algorithms."
  }
}

# ============================================================================
# Security and Compliance Configuration
# ============================================================================

variable "notification_email" {
  description = "Email address for quantum security alerts and compliance notifications."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Must be a valid email address format."
  }
}

variable "compliance_schedule" {
  description = "Cron schedule for automated compliance report generation. Default: Quarterly at 9 AM UTC."
  type        = string
  default     = "0 9 1 */3 *"

  validation {
    condition     = can(regex("^[0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+ [0-9*,-/]+$", var.compliance_schedule))
    error_message = "Must be a valid cron expression (minute hour day month day-of-week)."
  }
}

variable "security_posture_assessment_frequency" {
  description = "Frequency for automated security posture assessments in hours."
  type        = number
  default     = 24

  validation {
    condition     = var.security_posture_assessment_frequency >= 1 && var.security_posture_assessment_frequency <= 168
    error_message = "Assessment frequency must be between 1 and 168 hours (1 week)."
  }
}

# ============================================================================
# Asset Inventory Configuration
# ============================================================================

variable "asset_types_to_track" {
  description = "List of Google Cloud asset types to track for cryptographic inventory and quantum vulnerability assessment."
  type        = list(string)
  default = [
    "cloudkms.googleapis.com/CryptoKey",
    "cloudkms.googleapis.com/KeyRing",
    "compute.googleapis.com/Disk",
    "compute.googleapis.com/Instance",
    "storage.googleapis.com/Bucket",
    "sql.googleapis.com/DatabaseInstance"
  ]

  validation {
    condition     = length(var.asset_types_to_track) > 0
    error_message = "At least one asset type must be specified for tracking."
  }
}

variable "asset_feed_content_type" {
  description = "Content type for asset inventory feed. Determines the level of detail in asset tracking."
  type        = string
  default     = "RESOURCE"

  validation {
    condition     = contains(["RESOURCE", "IAM_POLICY", "ORG_POLICY", "ACCESS_POLICY"], var.asset_feed_content_type)
    error_message = "Content type must be one of: RESOURCE, IAM_POLICY, ORG_POLICY, ACCESS_POLICY."
  }
}

variable "asset_retention_days" {
  description = "Number of days to retain asset inventory data for compliance and audit purposes."
  type        = number
  default     = 2555 # ~7 years for compliance

  validation {
    condition     = var.asset_retention_days >= 90 && var.asset_retention_days <= 3650
    error_message = "Asset retention must be between 90 days and 10 years."
  }
}

# ============================================================================
# Organization Policy Configuration
# ============================================================================

variable "enforce_os_login" {
  description = "Enforce OS Login organization policy for enhanced security and access control."
  type        = bool
  default     = true
}

variable "disable_service_account_keys" {
  description = "Disable creation of service account keys to improve security posture."
  type        = bool
  default     = true
}

variable "enforce_uniform_bucket_level_access" {
  description = "Enforce uniform bucket-level access for Cloud Storage to prevent ACL-based access."
  type        = bool
  default     = true
}

variable "restrict_vpc_peering" {
  description = "Restrict VPC peering to approved organizations only."
  type        = bool
  default     = true
}

# ============================================================================
# Monitoring and Alerting Configuration
# ============================================================================

variable "monitoring_retention_days" {
  description = "Number of days to retain monitoring data for quantum security metrics."
  type        = number
  default     = 400

  validation {
    condition     = var.monitoring_retention_days >= 30 && var.monitoring_retention_days <= 1000
    error_message = "Monitoring retention must be between 30 and 1000 days."
  }
}

variable "alert_threshold_quantum_vulnerabilities" {
  description = "Threshold for quantum vulnerability alerts. Alert when vulnerabilities exceed this count."
  type        = number
  default     = 0

  validation {
    condition     = var.alert_threshold_quantum_vulnerabilities >= 0
    error_message = "Alert threshold must be non-negative."
  }
}

variable "key_rotation_alert_days" {
  description = "Number of days overdue before alerting on missed key rotations."
  type        = number
  default     = 35

  validation {
    condition     = var.key_rotation_alert_days >= 1 && var.key_rotation_alert_days <= 365
    error_message = "Key rotation alert days must be between 1 and 365."
  }
}

# ============================================================================
# Cloud Functions Configuration
# ============================================================================

variable "function_memory_mb" {
  description = "Memory allocation for Cloud Functions in MB. Higher memory provides better performance."
  type        = number
  default     = 256

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 4096, 8192], var.function_memory_mb)
    error_message = "Function memory must be one of: 128, 256, 512, 1024, 2048, 4096, 8192 MB."
  }
}

variable "function_timeout_seconds" {
  description = "Timeout for Cloud Functions in seconds. Maximum time a function can run."
  type        = number
  default     = 540

  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_runtime" {
  description = "Runtime environment for Cloud Functions. Must support required dependencies."
  type        = string
  default     = "python39"

  validation {
    condition     = contains(["python39", "python310", "python311"], var.function_runtime)
    error_message = "Function runtime must be a supported Python version."
  }
}

# ============================================================================
# Storage Configuration
# ============================================================================

variable "storage_class" {
  description = "Default storage class for buckets. STANDARD for frequently accessed data."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "NEARLINE", "COLDLINE", "ARCHIVE"], var.storage_class)
    error_message = "Storage class must be one of: STANDARD, NEARLINE, COLDLINE, ARCHIVE."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning on storage buckets for audit trail and data protection."
  type        = bool
  default     = true
}

variable "bucket_lifecycle_age_days" {
  description = "Number of days before objects are moved to colder storage classes for cost optimization."
  type        = number
  default     = 90

  validation {
    condition     = var.bucket_lifecycle_age_days >= 1 && var.bucket_lifecycle_age_days <= 365
    error_message = "Bucket lifecycle age must be between 1 and 365 days."
  }
}

# ============================================================================
# Security Command Center Configuration
# ============================================================================

variable "scc_notification_config" {
  description = "Configuration for Security Command Center notifications and finding filters."
  type = object({
    enable_high_severity_alerts = bool
    enable_medium_severity_alerts = bool
    enable_finding_updates = bool
    filter_quantum_related_only = bool
  })
  default = {
    enable_high_severity_alerts = true
    enable_medium_severity_alerts = true
    enable_finding_updates = true
    filter_quantum_related_only = false
  }
}

# ============================================================================
# Networking Configuration
# ============================================================================

variable "allowed_ingress_cidr_blocks" {
  description = "CIDR blocks allowed for ingress traffic to quantum security infrastructure."
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  validation {
    condition     = length(var.allowed_ingress_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified for ingress traffic."
  }
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for enhanced security and reduced data egress costs."
  type        = bool
  default     = true
}

# ============================================================================
# Cost Management Configuration
# ============================================================================

variable "budget_amount_usd" {
  description = "Monthly budget amount in USD for quantum security infrastructure. Set to 0 to disable budgeting."
  type        = number
  default     = 1000

  validation {
    condition     = var.budget_amount_usd >= 0
    error_message = "Budget amount must be non-negative."
  }
}

variable "budget_alert_thresholds" {
  description = "Budget alert thresholds as percentages (0.0-1.0) for cost monitoring."
  type        = list(number)
  default     = [0.5, 0.75, 0.9, 1.0]

  validation {
    condition = alltrue([
      for threshold in var.budget_alert_thresholds : threshold >= 0.0 && threshold <= 1.0
    ])
    error_message = "Budget thresholds must be between 0.0 and 1.0."
  }
}

# ============================================================================
# Tagging and Labeling Configuration
# ============================================================================

variable "resource_labels" {
  description = "Common labels to apply to all resources for organization and cost tracking."
  type        = map(string)
  default = {
    environment       = "quantum-security"
    project          = "post-quantum-cryptography"
    managed_by       = "terraform"
    security_level   = "high"
    compliance_scope = "quantum-safe"
    cost_center      = "security"
  }

  validation {
    condition     = length(var.resource_labels) <= 64
    error_message = "Maximum of 64 labels allowed per resource."
  }
}

# ============================================================================
# Development and Testing Configuration
# ============================================================================

variable "enable_deletion_protection" {
  description = "Enable deletion protection for critical resources. Recommended for production."
  type        = bool
  default     = true
}

variable "create_test_resources" {
  description = "Create additional resources for testing quantum vulnerability detection."
  type        = bool
  default     = false
}

variable "enable_debug_logging" {
  description = "Enable detailed logging for troubleshooting and development."
  type        = bool
  default     = false
}