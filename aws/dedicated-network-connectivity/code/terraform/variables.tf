# General Configuration
variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "hybrid-cloud-connectivity"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Network Configuration
variable "prod_vpc_cidr" {
  description = "CIDR block for production VPC"
  type        = string
  default     = "10.1.0.0/16"
  validation {
    condition     = can(cidrhost(var.prod_vpc_cidr, 0))
    error_message = "Production VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "dev_vpc_cidr" {
  description = "CIDR block for development VPC"
  type        = string
  default     = "10.2.0.0/16"
  validation {
    condition     = can(cidrhost(var.dev_vpc_cidr, 0))
    error_message = "Development VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "shared_vpc_cidr" {
  description = "CIDR block for shared services VPC"
  type        = string
  default     = "10.3.0.0/16"
  validation {
    condition     = can(cidrhost(var.shared_vpc_cidr, 0))
    error_message = "Shared services VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "on_premises_cidr" {
  description = "CIDR block for on-premises network"
  type        = string
  default     = "10.0.0.0/8"
  validation {
    condition     = can(cidrhost(var.on_premises_cidr, 0))
    error_message = "On-premises CIDR must be a valid IPv4 CIDR block."
  }
}

# BGP Configuration
variable "on_premises_asn" {
  description = "BGP ASN for on-premises network"
  type        = number
  default     = 65000
  validation {
    condition     = var.on_premises_asn >= 64512 && var.on_premises_asn <= 65534
    error_message = "On-premises ASN must be in the private ASN range (64512-65534)."
  }
}

variable "aws_asn" {
  description = "BGP ASN for AWS Direct Connect Gateway"
  type        = number
  default     = 64512
  validation {
    condition     = var.aws_asn >= 64512 && var.aws_asn <= 65534
    error_message = "AWS ASN must be in the private ASN range (64512-65534)."
  }
}

# Direct Connect Configuration
variable "dx_connection_id" {
  description = "Existing Direct Connect connection ID (optional - for virtual interfaces)"
  type        = string
  default     = ""
}

variable "dx_gateway_name" {
  description = "Name for the Direct Connect Gateway"
  type        = string
  default     = "corporate-dx-gateway"
}

variable "private_vif_vlan" {
  description = "VLAN ID for private virtual interface"
  type        = number
  default     = 100
  validation {
    condition     = var.private_vif_vlan >= 1 && var.private_vif_vlan <= 4094
    error_message = "VLAN ID must be between 1 and 4094."
  }
}

variable "transit_vif_vlan" {
  description = "VLAN ID for transit virtual interface"
  type        = number
  default     = 200
  validation {
    condition     = var.transit_vif_vlan >= 1 && var.transit_vif_vlan <= 4094
    error_message = "VLAN ID must be between 1 and 4094."
  }
}

variable "dx_bandwidth" {
  description = "Bandwidth for Direct Connect connection"
  type        = string
  default     = "1Gbps"
  validation {
    condition = contains([
      "50Mbps", "100Mbps", "200Mbps", "300Mbps", "400Mbps", "500Mbps",
      "1Gbps", "2Gbps", "5Gbps", "10Gbps", "100Gbps"
    ], var.dx_bandwidth)
    error_message = "Bandwidth must be one of the supported Direct Connect speeds."
  }
}

# Virtual Interface IP Configuration
variable "customer_address" {
  description = "Customer side IP address for transit VIF (/30 subnet)"
  type        = string
  default     = "192.168.100.1/30"
}

variable "amazon_address" {
  description = "Amazon side IP address for transit VIF (/30 subnet)"
  type        = string
  default     = "192.168.100.2/30"
}

variable "bgp_auth_key" {
  description = "BGP authentication key for virtual interface"
  type        = string
  default     = ""
  sensitive   = true
}

# DNS Configuration
variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPCs"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPCs"
  type        = bool
  default     = true
}

variable "dns_resolver_endpoints" {
  description = "Enable Route 53 Resolver endpoints for hybrid DNS"
  type        = bool
  default     = true
}

# Monitoring Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring and alerting"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention period for VPC Flow Logs in days"
  type        = number
  default     = 7
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.flow_logs_retention_days)
    error_message = "Flow logs retention must be a valid CloudWatch Logs retention period."
  }
}

# Security Configuration
variable "enable_nacl_rules" {
  description = "Enable additional Network ACL rules for security"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "allowed_https_cidr" {
  description = "CIDR blocks allowed for HTTPS access"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

# Availability Zone Configuration
variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = []
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}