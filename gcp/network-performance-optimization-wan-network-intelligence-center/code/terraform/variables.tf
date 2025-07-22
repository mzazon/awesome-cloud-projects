# ==============================================================================
# TERRAFORM VARIABLES FOR NETWORK PERFORMANCE OPTIMIZATION
# ==============================================================================
# This file defines all configurable variables for the network performance
# optimization solution, allowing customization for different environments
# and deployment scenarios.
# ==============================================================================

# ------------------------------------------------------------------------------
# PROJECT AND LOCATION VARIABLES
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "The Google Cloud Project ID where resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID cannot be empty."
  }
}

variable "region" {
  description = "The primary Google Cloud region for resource deployment"
  type        = string
  default     = "us-central1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.region))
    error_message = "Region must be a valid Google Cloud region format (e.g., us-central1, europe-west1)."
  }
}

variable "secondary_region" {
  description = "The secondary Google Cloud region for multi-region testing and redundancy"
  type        = string
  default     = "us-west1"
  
  validation {
    condition = can(regex("^[a-z]+-[a-z0-9]+-[0-9]+$", var.secondary_region))
    error_message = "Secondary region must be a valid Google Cloud region format."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod) for resource labeling and organization"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["dev", "staging", "production", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, production, test."
  }
}

# ------------------------------------------------------------------------------
# NETWORK CONFIGURATION VARIABLES
# ------------------------------------------------------------------------------

variable "primary_subnet_cidr" {
  description = "CIDR block for the primary subnet in the network optimization VPC"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition = can(cidrhost(var.primary_subnet_cidr, 0))
    error_message = "Primary subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_subnet_cidr" {
  description = "CIDR block for the secondary subnet in the network optimization VPC"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition = can(cidrhost(var.secondary_subnet_cidr, 0))
    error_message = "Secondary subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "vpc_flow_logs_sampling" {
  description = "Sampling rate for VPC Flow Logs (0.0 to 1.0). Higher values provide more data but increase costs"
  type        = number
  default     = 0.1
  
  validation {
    condition     = var.vpc_flow_logs_sampling >= 0.0 && var.vpc_flow_logs_sampling <= 1.0
    error_message = "VPC Flow Logs sampling rate must be between 0.0 and 1.0."
  }
}

variable "network_mtu" {
  description = "Maximum Transmission Unit (MTU) for the VPC network"
  type        = number
  default     = 1500
  
  validation {
    condition     = var.network_mtu >= 1460 && var.network_mtu <= 8896
    error_message = "Network MTU must be between 1460 and 8896 bytes."
  }
}

# ------------------------------------------------------------------------------
# MONITORING AND ALERTING VARIABLES
# ------------------------------------------------------------------------------

variable "notification_email" {
  description = "Email address for receiving network performance alerts and notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Notification email must be a valid email address format."
  }
}

variable "latency_threshold_ms" {
  description = "Network latency threshold in milliseconds that triggers alerts when exceeded"
  type        = number
  default     = 100
  
  validation {
    condition     = var.latency_threshold_ms > 0 && var.latency_threshold_ms <= 10000
    error_message = "Latency threshold must be between 1 and 10000 milliseconds."
  }
}

variable "throughput_threshold_bps" {
  description = "Network throughput threshold in bytes per second for performance monitoring"
  type        = number
  default     = 1000000  # 1 MB/s
  
  validation {
    condition     = var.throughput_threshold_bps > 0
    error_message = "Throughput threshold must be greater than 0 bytes per second."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring with higher frequency metrics collection (increases costs)"
  type        = bool
  default     = true
}

variable "alert_auto_close_duration" {
  description = "Duration in seconds after which alerts auto-close if conditions are resolved"
  type        = number
  default     = 1800  # 30 minutes
  
  validation {
    condition     = var.alert_auto_close_duration >= 300 && var.alert_auto_close_duration <= 86400
    error_message = "Alert auto-close duration must be between 300 seconds (5 minutes) and 86400 seconds (24 hours)."
  }
}

# ------------------------------------------------------------------------------
# CLOUD FUNCTION CONFIGURATION VARIABLES
# ------------------------------------------------------------------------------

variable "function_memory" {
  description = "Memory allocation for Cloud Functions in MB"
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
  description = "Maximum execution time for Cloud Functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.function_timeout_seconds >= 1 && var.function_timeout_seconds <= 540
    error_message = "Function timeout must be between 1 and 540 seconds."
  }
}

variable "function_max_instances" {
  description = "Maximum number of function instances that can run concurrently"
  type        = number
  default     = 10
  
  validation {
    condition     = var.function_max_instances >= 1 && var.function_max_instances <= 3000
    error_message = "Function max instances must be between 1 and 3000."
  }
}

variable "function_min_instances" {
  description = "Minimum number of function instances to keep warm for faster response times"
  type        = number
  default     = 1
  
  validation {
    condition     = var.function_min_instances >= 0 && var.function_min_instances <= 1000
    error_message = "Function min instances must be between 0 and 1000."
  }
}

# ------------------------------------------------------------------------------
# SCHEDULING AND AUTOMATION VARIABLES
# ------------------------------------------------------------------------------

variable "analysis_schedule" {
  description = "Cron schedule for periodic network analysis (in UTC timezone)"
  type        = string
  default     = "0 */6 * * *"  # Every 6 hours
  
  validation {
    condition = can(regex("^[0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+$", var.analysis_schedule))
    error_message = "Analysis schedule must be a valid cron expression (5 fields)."
  }
}

variable "report_schedule" {
  description = "Cron schedule for daily network health reports (in UTC timezone)"
  type        = string
  default     = "0 9 * * *"  # Daily at 9 AM UTC
  
  validation {
    condition = can(regex("^[0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+ [0-9\\*,/-]+$", var.report_schedule))
    error_message = "Report schedule must be a valid cron expression (5 fields)."
  }
}

variable "enable_scheduler_jobs" {
  description = "Enable Cloud Scheduler jobs for automated network analysis and reporting"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# PUB/SUB CONFIGURATION VARIABLES
# ------------------------------------------------------------------------------

variable "message_retention_duration" {
  description = "How long to retain messages in Pub/Sub topics (in seconds)"
  type        = number
  default     = 604800  # 7 days
  
  validation {
    condition     = var.message_retention_duration >= 600 && var.message_retention_duration <= 2678400
    error_message = "Message retention duration must be between 600 seconds (10 minutes) and 2678400 seconds (31 days)."
  }
}

variable "subscription_ack_deadline" {
  description = "Maximum time in seconds a subscriber has to acknowledge a received message"
  type        = number
  default     = 60
  
  validation {
    condition     = var.subscription_ack_deadline >= 10 && var.subscription_ack_deadline <= 600
    error_message = "Subscription ack deadline must be between 10 and 600 seconds."
  }
}

variable "dead_letter_max_attempts" {
  description = "Maximum number of delivery attempts before sending message to dead letter queue"
  type        = number
  default     = 5
  
  validation {
    condition     = var.dead_letter_max_attempts >= 1 && var.dead_letter_max_attempts <= 100
    error_message = "Dead letter max attempts must be between 1 and 100."
  }
}

# ------------------------------------------------------------------------------
# COMPUTE INSTANCE CONFIGURATION VARIABLES
# ------------------------------------------------------------------------------

variable "test_instance_machine_type" {
  description = "Machine type for network test instances"
  type        = string
  default     = "e2-medium"
  
  validation {
    condition = contains([
      "e2-micro", "e2-small", "e2-medium", "e2-standard-2", "e2-standard-4",
      "n2-standard-2", "n2-standard-4", "n2-standard-8", "n2-highmem-2"
    ], var.test_instance_machine_type)
    error_message = "Test instance machine type must be a valid Google Cloud machine type."
  }
}

variable "test_instance_disk_size" {
  description = "Boot disk size for test instances in GB"
  type        = number
  default     = 10
  
  validation {
    condition     = var.test_instance_disk_size >= 10 && var.test_instance_disk_size <= 1000
    error_message = "Test instance disk size must be between 10 and 1000 GB."
  }
}

variable "test_instance_disk_type" {
  description = "Boot disk type for test instances"
  type        = string
  default     = "pd-standard"
  
  validation {
    condition = contains([
      "pd-standard", "pd-ssd", "pd-balanced"
    ], var.test_instance_disk_type)
    error_message = "Test instance disk type must be one of: pd-standard, pd-ssd, pd-balanced."
  }
}

# ------------------------------------------------------------------------------
# CONNECTIVITY TEST CONFIGURATION VARIABLES
# ------------------------------------------------------------------------------

variable "external_test_ip" {
  description = "External IP address for connectivity testing (default: Google DNS)"
  type        = string
  default     = "8.8.8.8"
  
  validation {
    condition = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.external_test_ip))
    error_message = "External test IP must be a valid IPv4 address."
  }
}

variable "external_test_port" {
  description = "Port number for external connectivity testing"
  type        = number
  default     = 53
  
  validation {
    condition     = var.external_test_port >= 1 && var.external_test_port <= 65535
    error_message = "External test port must be between 1 and 65535."
  }
}

variable "external_test_protocol" {
  description = "Protocol for external connectivity testing"
  type        = string
  default     = "UDP"
  
  validation {
    condition = contains(["TCP", "UDP", "ICMP"], var.external_test_protocol)
    error_message = "External test protocol must be one of: TCP, UDP, ICMP."
  }
}

# ------------------------------------------------------------------------------
# SECURITY AND ACCESS CONFIGURATION VARIABLES
# ------------------------------------------------------------------------------

variable "enable_os_login" {
  description = "Enable OS Login for secure instance access management"
  type        = bool
  default     = true
}

variable "enable_private_ip_google_access" {
  description = "Enable private Google access for subnets to access Google services without external IPs"
  type        = bool
  default     = true
}

variable "enable_uniform_bucket_level_access" {
  description = "Enable uniform bucket-level access for Cloud Storage buckets"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# COST OPTIMIZATION VARIABLES
# ------------------------------------------------------------------------------

variable "storage_lifecycle_age_days" {
  description = "Number of days after which to delete objects in storage buckets for cost optimization"
  type        = number
  default     = 30
  
  validation {
    condition     = var.storage_lifecycle_age_days >= 1 && var.storage_lifecycle_age_days <= 365
    error_message = "Storage lifecycle age must be between 1 and 365 days."
  }
}

variable "enable_bucket_versioning" {
  description = "Enable versioning for Cloud Storage buckets (increases storage costs but improves recovery options)"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# RESOURCE LABELING VARIABLES
# ------------------------------------------------------------------------------

variable "additional_labels" {
  description = "Additional labels to apply to all resources for organization and cost tracking"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_labels) <= 64
    error_message = "Additional labels cannot exceed 64 key-value pairs."
  }
}

variable "created_by" {
  description = "Identifier for who or what created these resources (for tracking and governance)"
  type        = string
  default     = "terraform"
  
  validation {
    condition     = length(var.created_by) > 0 && length(var.created_by) <= 63
    error_message = "Created by value must be between 1 and 63 characters."
  }
}