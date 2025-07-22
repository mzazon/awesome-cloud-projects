# Variables for AWS Elastic Disaster Recovery (DRS) Automation Infrastructure
# These variables allow customization of the disaster recovery solution
# for different environments and requirements

# ===================================================================
# Environment and General Configuration
# ===================================================================

variable "environment" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["production", "staging", "development", "test"], var.environment)
    error_message = "Environment must be one of: production, staging, development, test."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "notification_email" {
  description = "Email address for DR notifications and alerts"
  type        = string
  default     = ""
  
  validation {
    condition = var.notification_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "If provided, notification_email must be a valid email address."
  }
}

# ===================================================================
# Network Configuration
# ===================================================================

variable "dr_vpc_cidr" {
  description = "CIDR block for the disaster recovery VPC"
  type        = string
  default     = "10.100.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.dr_vpc_cidr, 0))
    error_message = "DR VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "dr_public_subnet_cidr" {
  description = "CIDR block for the public subnet in DR region"
  type        = string
  default     = "10.100.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.dr_public_subnet_cidr, 0))
    error_message = "DR public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "dr_private_subnet_cidr" {
  description = "CIDR block for the private subnet in DR region"
  type        = string
  default     = "10.100.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.dr_private_subnet_cidr, 0))
    error_message = "DR private subnet CIDR must be a valid IPv4 CIDR block."
  }
}

# ===================================================================
# DRS Configuration
# ===================================================================

variable "replication_bandwidth_throttling" {
  description = "Bandwidth throttling for DRS replication in Mbps (0 = unlimited)"
  type        = number
  default     = 50000
  
  validation {
    condition     = var.replication_bandwidth_throttling >= 0 && var.replication_bandwidth_throttling <= 100000
    error_message = "Replication bandwidth throttling must be between 0 and 100000 Mbps."
  }
}

variable "create_public_ip" {
  description = "Whether to create public IP addresses for replication servers"
  type        = bool
  default     = true
}

variable "data_plane_routing" {
  description = "Data plane routing for DRS replication (PRIVATE_IP or PUBLIC_IP)"
  type        = string
  default     = "PRIVATE_IP"
  
  validation {
    condition     = contains(["PRIVATE_IP", "PUBLIC_IP"], var.data_plane_routing)
    error_message = "Data plane routing must be either PRIVATE_IP or PUBLIC_IP."
  }
}

variable "staging_disk_type" {
  description = "EBS disk type for staging area (GP2, GP3, ST1, SC1)"
  type        = string
  default     = "GP3"
  
  validation {
    condition     = contains(["GP2", "GP3", "ST1", "SC1"], var.staging_disk_type)
    error_message = "Staging disk type must be one of: GP2, GP3, ST1, SC1."
  }
}

variable "ebs_encryption" {
  description = "EBS encryption setting for DRS (DEFAULT, CUSTOM)"
  type        = string
  default     = "DEFAULT"
  
  validation {
    condition     = contains(["DEFAULT", "CUSTOM"], var.ebs_encryption)
    error_message = "EBS encryption must be either DEFAULT or CUSTOM."
  }
}

variable "replication_server_instance_type" {
  description = "EC2 instance type for DRS replication servers"
  type        = string
  default     = "m5.large"
  
  validation {
    condition = can(regex("^[a-z][0-9]*[a-z]*\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.replication_server_instance_type))
    error_message = "Replication server instance type must be a valid EC2 instance type."
  }
}

variable "use_dedicated_replication_server" {
  description = "Whether to use dedicated replication servers for better performance"
  type        = bool
  default     = true
}

# ===================================================================
# Automation Configuration
# ===================================================================

variable "dr_test_schedule" {
  description = "Schedule expression for automated DR testing (EventBridge format)"
  type        = string
  default     = "rate(30 days)"
  
  validation {
    condition = can(regex("^(rate\\([0-9]+ (minute|minutes|hour|hours|day|days)\\)|cron\\(.+\\))$", var.dr_test_schedule))
    error_message = "DR test schedule must be a valid EventBridge schedule expression."
  }
}

variable "enable_auto_failover" {
  description = "Whether to enable automatic failover based on CloudWatch alarms"
  type        = bool
  default     = false
}

variable "failover_alarm_threshold" {
  description = "Number of consecutive alarm periods before triggering failover"
  type        = number
  default     = 3
  
  validation {
    condition     = var.failover_alarm_threshold >= 1 && var.failover_alarm_threshold <= 10
    error_message = "Failover alarm threshold must be between 1 and 10."
  }
}

variable "replication_lag_threshold" {
  description = "Maximum acceptable replication lag in seconds before alerting"
  type        = number
  default     = 300
  
  validation {
    condition     = var.replication_lag_threshold >= 60 && var.replication_lag_threshold <= 3600
    error_message = "Replication lag threshold must be between 60 and 3600 seconds."
  }
}

# ===================================================================
# Lambda Configuration
# ===================================================================

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 30 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 30 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda functions in MB"
  type        = number
  default     = 256
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

# ===================================================================
# Security Configuration
# ===================================================================

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs for security monitoring"
  type        = bool
  default     = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access DR resources"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  
  validation {
    condition = alltrue([
      for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All allowed CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "enable_detailed_monitoring" {
  description = "Whether to enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

# ===================================================================
# Route 53 Configuration
# ===================================================================

variable "hosted_zone_name" {
  description = "Route 53 hosted zone name for DNS failover (optional)"
  type        = string
  default     = ""
}

variable "application_dns_name" {
  description = "DNS name for application endpoint (e.g., app.example.com)"
  type        = string
  default     = ""
}

variable "primary_endpoint_ip" {
  description = "Primary region application IP address for Route 53 failover"
  type        = string
  default     = ""
  
  validation {
    condition = var.primary_endpoint_ip == "" || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.primary_endpoint_ip))
    error_message = "If provided, primary endpoint IP must be a valid IPv4 address."
  }
}

variable "dr_endpoint_ip" {
  description = "DR region application IP address for Route 53 failover"
  type        = string
  default     = "10.100.1.100"
  
  validation {
    condition = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.dr_endpoint_ip))
    error_message = "DR endpoint IP must be a valid IPv4 address."
  }
}

# ===================================================================
# Cost Optimization
# ===================================================================

variable "enable_spot_instances" {
  description = "Whether to use Spot instances for cost optimization (non-production)"
  type        = bool
  default     = false
}

variable "instance_tenancy" {
  description = "Tenancy of instances (default, dedicated, host)"
  type        = string
  default     = "default"
  
  validation {
    condition     = contains(["default", "dedicated", "host"], var.instance_tenancy)
    error_message = "Instance tenancy must be one of: default, dedicated, host."
  }
}

# ===================================================================
# Backup and Retention
# ===================================================================

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch log retention value."
  }
}

variable "snapshot_retention_days" {
  description = "Number of days to retain DRS snapshots"
  type        = number
  default     = 7
  
  validation {
    condition     = var.snapshot_retention_days >= 1 && var.snapshot_retention_days <= 365
    error_message = "Snapshot retention days must be between 1 and 365."
  }
}

# ===================================================================
# Advanced Configuration
# ===================================================================

variable "enable_cross_region_backup" {
  description = "Whether to enable cross-region backup for additional protection"
  type        = bool
  default     = false
}

variable "disaster_recovery_tier" {
  description = "DR tier for RTO/RPO requirements (pilot-light, warm-standby, hot-standby)"
  type        = string
  default     = "warm-standby"
  
  validation {
    condition     = contains(["pilot-light", "warm-standby", "hot-standby"], var.disaster_recovery_tier)
    error_message = "Disaster recovery tier must be one of: pilot-light, warm-standby, hot-standby."
  }
}

variable "compliance_requirements" {
  description = "List of compliance requirements (HIPAA, PCI-DSS, SOX, etc.)"
  type        = list(string)
  default     = []
}

variable "enable_config_rules" {
  description = "Whether to enable AWS Config rules for compliance monitoring"
  type        = bool
  default     = false
}

variable "kms_key_rotation" {
  description = "Whether to enable automatic KMS key rotation"
  type        = bool
  default     = true
}