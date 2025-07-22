# ==============================================================================
# CORE VARIABLES
# ==============================================================================

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-west-2)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "cost_center" {
  description = "Cost center for billing attribution"
  type        = string
  default     = "IT-Infrastructure"
}

variable "admin_email" {
  description = "Administrator email for notifications"
  type        = string
  
  validation {
    condition = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.admin_email))
    error_message = "Admin email must be a valid email address."
  }
}

# ==============================================================================
# NETWORKING VARIABLES
# ==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VMware Cloud connectivity VPC"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for VMware Cloud connectivity subnet"
  type        = string
  default     = "10.1.1.0/24"
  
  validation {
    condition = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid CIDR block."
  }
}

variable "availability_zone" {
  description = "Availability zone for subnet placement (will be suffixed to region)"
  type        = string
  default     = "a"
  
  validation {
    condition = can(regex("^[a-z]$", var.availability_zone))
    error_message = "Availability zone must be a single lowercase letter."
  }
}

variable "enable_direct_connect" {
  description = "Enable Direct Connect gateway for hybrid connectivity"
  type        = bool
  default     = false
}

variable "direct_connect_connection_id" {
  description = "Existing Direct Connect connection ID (required if enable_direct_connect is true)"
  type        = string
  default     = ""
}

variable "direct_connect_vlan" {
  description = "VLAN ID for Direct Connect virtual interface"
  type        = number
  default     = 100
  
  validation {
    condition = var.direct_connect_vlan >= 1 && var.direct_connect_vlan <= 4094
    error_message = "VLAN ID must be between 1 and 4094."
  }
}

variable "direct_connect_asn" {
  description = "BGP ASN for Direct Connect (customer side)"
  type        = number
  default     = 65000
  
  validation {
    condition = var.direct_connect_asn >= 1 && var.direct_connect_asn <= 4294967294
    error_message = "ASN must be between 1 and 4294967294."
  }
}

variable "direct_connect_customer_address" {
  description = "Customer side IP address for Direct Connect BGP peering"
  type        = string
  default     = "192.168.1.1/30"
}

variable "direct_connect_amazon_address" {
  description = "Amazon side IP address for Direct Connect BGP peering"
  type        = string
  default     = "192.168.1.2/30"
}

# ==============================================================================
# VMWARE CLOUD ON AWS VARIABLES
# ==============================================================================

variable "sddc_name" {
  description = "Name for the VMware Cloud on AWS SDDC"
  type        = string
  default     = "vmware-migration-sddc"
  
  validation {
    condition = can(regex("^[a-zA-Z0-9-]+$", var.sddc_name))
    error_message = "SDDC name must contain only alphanumeric characters and hyphens."
  }
}

variable "management_subnet_cidr" {
  description = "CIDR block for VMware SDDC management subnet"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition = can(cidrhost(var.management_subnet_cidr, 0))
    error_message = "Management subnet CIDR must be a valid CIDR block."
  }
}

variable "vmware_host_type" {
  description = "VMware Cloud on AWS host instance type"
  type        = string
  default     = "i3.metal"
  
  validation {
    condition = contains(["i3.metal", "i3en.metal", "i4i.metal"], var.vmware_host_type)
    error_message = "VMware host type must be one of: i3.metal, i3en.metal, i4i.metal."
  }
}

variable "vmware_host_count" {
  description = "Number of hosts in the VMware SDDC cluster"
  type        = number
  default     = 3
  
  validation {
    condition = var.vmware_host_count >= 3 && var.vmware_host_count <= 16
    error_message = "VMware host count must be between 3 and 16."
  }
}

# ==============================================================================
# MIGRATION VARIABLES
# ==============================================================================

variable "enable_mgn" {
  description = "Enable AWS Application Migration Service"
  type        = bool
  default     = true
}

variable "mgn_replication_server_instance_type" {
  description = "Instance type for MGN replication servers"
  type        = string
  default     = "m5.large"
  
  validation {
    condition = can(regex("^[a-z0-9]+\\.[a-z0-9]+$", var.mgn_replication_server_instance_type))
    error_message = "Instance type must be a valid AWS instance type format."
  }
}

variable "mgn_bandwidth_throttling" {
  description = "Bandwidth throttling for MGN replication (Mbps)"
  type        = number
  default     = 100
  
  validation {
    condition = var.mgn_bandwidth_throttling >= 1 && var.mgn_bandwidth_throttling <= 10000
    error_message = "Bandwidth throttling must be between 1 and 10000 Mbps."
  }
}

variable "mgn_default_large_staging_disk_type" {
  description = "Default EBS volume type for large staging disks"
  type        = string
  default     = "gp3"
  
  validation {
    condition = contains(["gp2", "gp3", "io1", "io2"], var.mgn_default_large_staging_disk_type)
    error_message = "Staging disk type must be one of: gp2, gp3, io1, io2."
  }
}

variable "migration_waves" {
  description = "Migration wave configuration"
  type = list(object({
    wave        = number
    description = string
    priority    = string
    vms         = list(string)
    migration_type = string
  }))
  default = [
    {
      wave        = 1
      description = "Test/Dev workloads"
      priority    = "Low"
      vms         = ["test-vm-01", "dev-vm-01"]
      migration_type = "HCX_vMotion"
    },
    {
      wave        = 2
      description = "Non-critical production"
      priority    = "Medium"
      vms         = ["web-server-01", "app-server-01"]
      migration_type = "HCX_Bulk_Migration"
    },
    {
      wave        = 3
      description = "Critical production"
      priority    = "High"
      vms         = ["db-server-01", "core-app-01"]
      migration_type = "HCX_RAV"
    }
  ]
}

# ==============================================================================
# BACKUP AND STORAGE VARIABLES
# ==============================================================================

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 90
  
  validation {
    condition = var.backup_retention_days >= 1 && var.backup_retention_days <= 3653
    error_message = "Backup retention days must be between 1 and 3653."
  }
}

variable "backup_transition_to_ia_days" {
  description = "Number of days after which to transition backups to Infrequent Access"
  type        = number
  default     = 30
  
  validation {
    condition = var.backup_transition_to_ia_days >= 1 && var.backup_transition_to_ia_days <= 365
    error_message = "IA transition days must be between 1 and 365."
  }
}

variable "backup_transition_to_glacier_days" {
  description = "Number of days after which to transition backups to Glacier"
  type        = number
  default     = 90
  
  validation {
    condition = var.backup_transition_to_glacier_days >= 1 && var.backup_transition_to_glacier_days <= 3653
    error_message = "Glacier transition days must be between 1 and 3653."
  }
}

# ==============================================================================
# MONITORING AND ALERTING VARIABLES
# ==============================================================================

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid retention period."
  }
}

variable "enable_cost_budget" {
  description = "Enable AWS Budgets for cost monitoring"
  type        = bool
  default     = true
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = number
  default     = 15000
  
  validation {
    condition = var.monthly_budget_limit >= 100
    error_message = "Monthly budget limit must be at least $100."
  }
}

variable "budget_alert_threshold" {
  description = "Budget alert threshold percentage"
  type        = number
  default     = 80
  
  validation {
    condition = var.budget_alert_threshold >= 1 && var.budget_alert_threshold <= 100
    error_message = "Budget alert threshold must be between 1 and 100."
  }
}

variable "enable_cost_anomaly_detection" {
  description = "Enable AWS Cost Anomaly Detection"
  type        = bool
  default     = true
}

# ==============================================================================
# SECURITY VARIABLES
# ==============================================================================

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access VMware infrastructure"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  
  validation {
    condition = length(var.allowed_cidr_blocks) > 0
    error_message = "At least one CIDR block must be specified."
  }
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for API logging"
  type        = bool
  default     = true
}

# ==============================================================================
# LAMBDA FUNCTION VARIABLES
# ==============================================================================

variable "lambda_runtime" {
  description = "Runtime for Lambda functions"
  type        = string
  default     = "python3.9"
  
  validation {
    condition = contains(["python3.8", "python3.9", "python3.10", "python3.11"], var.lambda_runtime)
    error_message = "Lambda runtime must be a supported Python version."
  }
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 128
  
  validation {
    condition = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 3008
    error_message = "Lambda memory size must be between 128 and 3008 MB."
  }
}