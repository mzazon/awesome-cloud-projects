# ==============================================================================
# TERRAFORM VARIABLES
# Enterprise Identity Federation Workflows with Cloud IAM and Service Directory
# ==============================================================================

# ==============================================================================
# PROJECT AND LOCATION VARIABLES
# ==============================================================================

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The GCP region where regional resources will be created"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = contains([
      "us-central1", "us-east1", "us-west1", "us-west2", "us-west3", "us-west4",
      "europe-west1", "europe-west2", "europe-west3", "europe-west4", "europe-west6",
      "asia-east1", "asia-northeast1", "asia-southeast1", "australia-southeast1"
    ], var.region)
    error_message = "Region must be a valid Google Cloud region."
  }
}

variable "zone" {
  description = "The GCP zone where zonal resources will be created"
  type        = string
  default     = "us-central1-a"
  
  validation {
    condition     = length(var.zone) > 0
    error_message = "Zone cannot be empty."
  }
}

# ==============================================================================
# ENVIRONMENT AND LABELING
# ==============================================================================

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test."
  }
}

variable "resource_prefix" {
  description = "Prefix to add to all resource names for uniqueness"
  type        = string
  default     = ""
  
  validation {
    condition     = length(var.resource_prefix) <= 10
    error_message = "Resource prefix must be 10 characters or less."
  }
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.labels) <= 64
    error_message = "Maximum of 64 labels can be specified."
  }
}

# ==============================================================================
# WORKLOAD IDENTITY FEDERATION CONFIGURATION
# ==============================================================================

variable "oidc_issuer_uri" {
  description = "The OIDC issuer URI for external identity provider"
  type        = string
  default     = "https://token.actions.githubusercontent.com"
  
  validation {
    condition     = can(regex("^https://", var.oidc_issuer_uri))
    error_message = "OIDC issuer URI must start with https://."
  }
}

variable "oidc_allowed_audiences" {
  description = "List of allowed audiences for OIDC token validation"
  type        = list(string)
  default     = ["sts.googleapis.com"]
  
  validation {
    condition     = length(var.oidc_allowed_audiences) > 0
    error_message = "At least one allowed audience must be specified."
  }
}

variable "oidc_attribute_condition" {
  description = "CEL expression for conditional access based on external identity attributes"
  type        = string
  default     = "assertion.repository_owner_id == \"123456789\""
  
  validation {
    condition     = length(var.oidc_attribute_condition) <= 4096
    error_message = "Attribute condition must be 4096 characters or less."
  }
}

variable "workload_identity_pool_description" {
  description = "Description for the Workload Identity Pool"
  type        = string
  default     = "Enterprise identity federation pool for external workload authentication"
  
  validation {
    condition     = length(var.workload_identity_pool_description) <= 256
    error_message = "Description must be 256 characters or less."
  }
}

variable "external_identity_repositories" {
  description = "List of external repositories allowed for identity federation"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.external_identity_repositories) <= 50
    error_message = "Maximum of 50 repositories can be specified."
  }
}

# ==============================================================================
# CLOUD FUNCTION CONFIGURATION
# ==============================================================================

variable "function_runtime" {
  description = "Runtime for the Cloud Function"
  type        = string
  default     = "python311"
  
  validation {
    condition = contains([
      "python39", "python310", "python311", "python312",
      "nodejs18", "nodejs20",
      "go119", "go120", "go121"
    ], var.function_runtime)
    error_message = "Function runtime must be a supported Google Cloud Functions runtime."
  }
}

variable "function_memory" {
  description = "Memory allocation for the Cloud Function"
  type        = string
  default     = "256M"
  
  validation {
    condition = contains([
      "128M", "256M", "512M", "1G", "2G", "4G", "8G"
    ], var.function_memory)
    error_message = "Function memory must be a valid memory allocation."
  }
}

variable "function_timeout" {
  description = "Timeout in seconds for the Cloud Function"
  type        = number
  default     = 60
  
  validation {
    condition     = var.function_timeout >= 1 && var.function_timeout <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of Cloud Function instances"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 1000
    error_message = "Function max instances must be between 1 and 1000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of Cloud Function instances"
  type        = number
  default     = 0
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 100
    error_message = "Function min instances must be between 0 and 100."
  }
}

variable "function_environment_variables" {
  description = "Additional environment variables for the Cloud Function"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.function_environment_variables) <= 100
    error_message = "Maximum of 100 environment variables can be specified."
  }
}

# ==============================================================================
# SERVICE DIRECTORY CONFIGURATION
# ==============================================================================

variable "service_directory_region" {
  description = "Region for Service Directory namespace (defaults to main region)"
  type        = string
  default     = ""
}

variable "enterprise_services" {
  description = "Map of enterprise services to create in Service Directory"
  type = map(object({
    description = string
    metadata    = map(string)
  }))
  default = {
    user-management = {
      description = "Enterprise user management service"
      metadata = {
        version     = "v1"
        tier        = "production"
        owner       = "identity-team"
      }
    }
    identity-provider = {
      description = "External identity provider integration service"
      metadata = {
        version     = "v2"
        tier        = "production"
        owner       = "security-team"
      }
    }
    resource-manager = {
      description = "Enterprise resource management service"
      metadata = {
        version     = "v1"
        tier        = "production"
        owner       = "platform-team"
      }
    }
  }
  
  validation {
    condition     = length(var.enterprise_services) <= 100
    error_message = "Maximum of 100 enterprise services can be defined."
  }
}

variable "namespace_labels" {
  description = "Additional labels for the Service Directory namespace"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.namespace_labels) <= 64
    error_message = "Maximum of 64 namespace labels can be specified."
  }
}

# ==============================================================================
# SECRET MANAGER CONFIGURATION
# ==============================================================================

variable "secret_replication_policy" {
  description = "Replication policy for Secret Manager secrets"
  type        = string
  default     = "auto"
  
  validation {
    condition     = contains(["auto", "user_managed"], var.secret_replication_policy)
    error_message = "Secret replication policy must be 'auto' or 'user_managed'."
  }
}

variable "secret_replication_locations" {
  description = "Locations for user-managed secret replication"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.secret_replication_locations) <= 10
    error_message = "Maximum of 10 replication locations can be specified."
  }
}

variable "secret_labels" {
  description = "Additional labels for Secret Manager secrets"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.secret_labels) <= 64
    error_message = "Maximum of 64 secret labels can be specified."
  }
}

# ==============================================================================
# DNS CONFIGURATION
# ==============================================================================

variable "dns_zone_visibility" {
  description = "Visibility of the DNS zone (private or public)"
  type        = string
  default     = "private"
  
  validation {
    condition     = contains(["private", "public"], var.dns_zone_visibility)
    error_message = "DNS zone visibility must be 'private' or 'public'."
  }
}

variable "dns_networks" {
  description = "List of VPC networks for private DNS zone visibility"
  type        = list(string)
  default     = ["default"]
  
  validation {
    condition     = length(var.dns_networks) >= 1
    error_message = "At least one VPC network must be specified for private DNS zones."
  }
}

variable "dns_record_ttl" {
  description = "TTL (time to live) for DNS records in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.dns_record_ttl >= 60 && var.dns_record_ttl <= 86400
    error_message = "DNS record TTL must be between 60 and 86400 seconds."
  }
}

# ==============================================================================
# SECURITY AND ACCESS CONTROL
# ==============================================================================

variable "enable_audit_logs" {
  description = "Enable comprehensive audit logging for all resources"
  type        = bool
  default     = true
}

variable "service_account_permissions" {
  description = "Additional IAM roles to grant to the federation service account"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for role in var.service_account_permissions : can(regex("^roles/", role))
    ])
    error_message = "All service account permissions must start with 'roles/'."
  }
}

variable "workload_identity_conditions" {
  description = "Additional workload identity conditions for enhanced security"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.workload_identity_conditions) <= 10
    error_message = "Maximum of 10 workload identity conditions can be specified."
  }
}

# ==============================================================================
# STORAGE CONFIGURATION
# ==============================================================================

variable "storage_bucket_location" {
  description = "Location for storage buckets (defaults to main region)"
  type        = string
  default     = ""
}

variable "storage_lifecycle_age" {
  description = "Age in days after which objects are deleted from storage buckets"
  type        = number
  default     = 90
  
  validation {
    condition     = var.storage_lifecycle_age >= 1 && var.storage_lifecycle_age <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

variable "enable_storage_versioning" {
  description = "Enable versioning for storage buckets"
  type        = bool
  default     = true
}

# ==============================================================================
# MONITORING AND ALERTING
# ==============================================================================

variable "enable_monitoring" {
  description = "Enable monitoring and alerting for the infrastructure"
  type        = bool
  default     = false
}

variable "monitoring_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""
  
  validation {
    condition = var.monitoring_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.monitoring_email))
    error_message = "Monitoring email must be a valid email address."
  }
}

variable "alert_thresholds" {
  description = "Thresholds for various monitoring alerts"
  type = object({
    function_error_rate    = optional(number, 0.1)
    function_duration_p99  = optional(number, 30000)
    secret_access_rate     = optional(number, 100)
  })
  default = {}
}

# ==============================================================================
# NETWORK CONFIGURATION
# ==============================================================================

variable "vpc_network" {
  description = "VPC network for resources that require network connectivity"
  type        = string
  default     = "default"
  
  validation {
    condition     = length(var.vpc_network) > 0
    error_message = "VPC network cannot be empty."
  }
}

variable "subnet_name" {
  description = "Subnet name for resources that require subnet placement"
  type        = string
  default     = ""
}

variable "enable_private_google_access" {
  description = "Enable Private Google Access for subnet"
  type        = bool
  default     = true
}

# ==============================================================================
# COST OPTIMIZATION
# ==============================================================================

variable "enable_cost_optimization" {
  description = "Enable cost optimization features where applicable"
  type        = bool
  default     = true
}

variable "preemptible_instances" {
  description = "Use preemptible instances where supported to reduce costs"
  type        = bool
  default     = false
}

# ==============================================================================
# FEATURE FLAGS
# ==============================================================================

variable "enable_advanced_security" {
  description = "Enable advanced security features like VPC Service Controls"
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = "Enable integration with external secret management systems"
  type        = bool
  default     = false
}

variable "enable_multi_region" {
  description = "Enable multi-region deployment for high availability"
  type        = bool
  default     = false
}

variable "enable_custom_domains" {
  description = "Enable custom domain configuration for services"
  type        = bool
  default     = false
}

# ==============================================================================
# BACKUP AND DISASTER RECOVERY
# ==============================================================================

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 30
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for applicable resources"
  type        = bool
  default     = false
}

# ==============================================================================
# COMPLIANCE AND GOVERNANCE
# ==============================================================================

variable "compliance_standards" {
  description = "List of compliance standards to adhere to (e.g., SOC2, PCI-DSS, HIPAA)"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.compliance_standards) <= 10
    error_message = "Maximum of 10 compliance standards can be specified."
  }
}

variable "data_residency_regions" {
  description = "List of regions where data must reside for compliance"
  type        = list(string)
  default     = []
  
  validation {
    condition     = length(var.data_residency_regions) <= 20
    error_message = "Maximum of 20 data residency regions can be specified."
  }
}