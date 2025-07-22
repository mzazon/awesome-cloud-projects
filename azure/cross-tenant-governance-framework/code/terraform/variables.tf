# MSP Tenant Configuration
variable "msp_tenant_id" {
  description = "The Azure AD tenant ID of the Managed Service Provider (MSP)"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.msp_tenant_id))
    error_message = "MSP tenant ID must be a valid GUID format."
  }
}

variable "msp_subscription_id" {
  description = "The Azure subscription ID for the MSP tenant"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.msp_subscription_id))
    error_message = "MSP subscription ID must be a valid GUID format."
  }
}

variable "msp_resource_group_name" {
  description = "Name of the resource group in the MSP tenant for management resources"
  type        = string
  default     = "rg-msp-lighthouse-management"
}

# Customer Tenant Configuration
variable "customer_tenant_id" {
  description = "The Azure AD tenant ID of the customer tenant"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.customer_tenant_id))
    error_message = "Customer tenant ID must be a valid GUID format."
  }
}

variable "customer_subscription_id" {
  description = "The Azure subscription ID for the customer tenant"
  type        = string
  
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.customer_subscription_id))
    error_message = "Customer subscription ID must be a valid GUID format."
  }
}

variable "customer_resource_group_name" {
  description = "Name of the resource group in the customer tenant for workload resources"
  type        = string
  default     = "rg-customer-workloads"
}

# Azure Lighthouse Configuration
variable "lighthouse_offer_name" {
  description = "Name of the Azure Lighthouse offer"
  type        = string
  default     = "Cross-Tenant Resource Governance"
}

variable "lighthouse_offer_description" {
  description = "Description of the Azure Lighthouse offer"
  type        = string
  default     = "Managed services for automated VM configuration, patching, and compliance monitoring"
}

variable "msp_admin_group_name" {
  description = "Name of the MSP administrators group in Azure AD"
  type        = string
  default     = "MSP-Administrators"
}

variable "msp_engineer_group_name" {
  description = "Name of the MSP engineers group in Azure AD"
  type        = string
  default     = "MSP-Engineers"
}

# Azure Automanage Configuration
variable "automanage_profile_name" {
  description = "Name of the Azure Automanage configuration profile"
  type        = string
  default     = "automanage-profile"
}

variable "enable_antimalware" {
  description = "Enable antimalware protection in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_azure_security_center" {
  description = "Enable Azure Security Center in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_backup" {
  description = "Enable backup in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_boot_diagnostics" {
  description = "Enable boot diagnostics in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_change_tracking" {
  description = "Enable change tracking and inventory in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_guest_configuration" {
  description = "Enable guest configuration in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_update_management" {
  description = "Enable update management in Automanage profile"
  type        = bool
  default     = true
}

variable "enable_vm_insights" {
  description = "Enable VM insights in Automanage profile"
  type        = bool
  default     = true
}

# Virtual Machine Configuration
variable "vm_size" {
  description = "Size of the virtual machines to deploy"
  type        = string
  default     = "Standard_B2s"
}

variable "vm_admin_username" {
  description = "Administrator username for the virtual machines"
  type        = string
  default     = "azureuser"
}

variable "vm_admin_password" {
  description = "Administrator password for the virtual machines"
  type        = string
  sensitive   = true
  
  validation {
    condition     = length(var.vm_admin_password) >= 12 && can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]", var.vm_admin_password))
    error_message = "Password must be at least 12 characters long and contain at least one lowercase letter, one uppercase letter, one digit, and one special character."
  }
}

variable "vm_image_publisher" {
  description = "Publisher of the VM image"
  type        = string
  default     = "MicrosoftWindowsServer"
}

variable "vm_image_offer" {
  description = "Offer of the VM image"
  type        = string
  default     = "WindowsServer"
}

variable "vm_image_sku" {
  description = "SKU of the VM image"
  type        = string
  default     = "2019-Datacenter"
}

variable "vm_image_version" {
  description = "Version of the VM image"
  type        = string
  default     = "latest"
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

# Log Analytics Configuration
variable "log_analytics_workspace_sku" {
  description = "SKU for the Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_analytics_retention_days" {
  description = "Number of days to retain logs in the Log Analytics workspace"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_analytics_retention_days >= 30 && var.log_analytics_retention_days <= 730
    error_message = "Log Analytics retention must be between 30 and 730 days."
  }
}

# Monitoring and Alerting Configuration
variable "alert_email_address" {
  description = "Email address for alert notifications"
  type        = string
  default     = "ops@msp-company.com"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email_address))
    error_message = "Alert email address must be a valid email format."
  }
}

variable "cpu_threshold_percentage" {
  description = "CPU percentage threshold for alerts"
  type        = number
  default     = 80
  
  validation {
    condition     = var.cpu_threshold_percentage >= 0 && var.cpu_threshold_percentage <= 100
    error_message = "CPU threshold must be between 0 and 100."
  }
}

variable "alert_evaluation_frequency" {
  description = "Frequency of alert evaluation (in minutes)"
  type        = number
  default     = 1
}

variable "alert_window_size" {
  description = "Window size for alert evaluation (in minutes)"
  type        = number
  default     = 5
}

variable "alert_severity" {
  description = "Severity level for alerts (0-4, where 0 is critical)"
  type        = number
  default     = 2
  
  validation {
    condition     = var.alert_severity >= 0 && var.alert_severity <= 4
    error_message = "Alert severity must be between 0 and 4."
  }
}

# Location Configuration
variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "East US"
}

# Tags Configuration
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    Purpose     = "Cross-Tenant-Governance"
    Solution    = "Azure-Lighthouse-Automanage"
    ManagedBy   = "Terraform"
  }
}

variable "msp_tags" {
  description = "Tags specific to MSP resources"
  type        = map(string)
  default = {
    TenantType = "MSP"
    Role       = "Management"
  }
}

variable "customer_tags" {
  description = "Tags specific to customer resources"
  type        = map(string)
  default = {
    TenantType = "Customer"
    Role       = "Workload"
  }
}