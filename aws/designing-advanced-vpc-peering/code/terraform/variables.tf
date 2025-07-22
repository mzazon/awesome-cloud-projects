# Variables for Multi-Region VPC Peering with Complex Routing Scenarios
# This file defines all configurable parameters for the infrastructure deployment

# Project Configuration Variables
variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "global-peering"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be between 1 and 50 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Regional Configuration Variables
variable "primary_region" {
  description = "Primary AWS region for hub deployment"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for disaster recovery hub"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., us-west-2)."
  }
}

variable "eu_region" {
  description = "European AWS region for regional hub"
  type        = string
  default     = "eu-west-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.eu_region))
    error_message = "EU region must be a valid AWS region format (e.g., eu-west-1)."
  }
}

variable "apac_region" {
  description = "Asia-Pacific AWS region for spoke deployment"
  type        = string
  default     = "ap-southeast-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.apac_region))
    error_message = "APAC region must be a valid AWS region format (e.g., ap-southeast-1)."
  }
}

# VPC CIDR Block Configuration
variable "vpc_cidrs" {
  description = "CIDR blocks for VPCs in each region"
  type = object({
    hub_vpc      = string
    prod_vpc     = string
    dev_vpc      = string
    dr_hub_vpc   = string
    dr_prod_vpc  = string
    eu_hub_vpc   = string
    eu_prod_vpc  = string
    apac_vpc     = string
  })
  
  default = {
    hub_vpc     = "10.0.0.0/16"    # US-East-1 Hub VPC
    prod_vpc    = "10.1.0.0/16"    # US-East-1 Production VPC
    dev_vpc     = "10.2.0.0/16"    # US-East-1 Development VPC
    dr_hub_vpc  = "10.10.0.0/16"   # US-West-2 DR Hub VPC
    dr_prod_vpc = "10.11.0.0/16"   # US-West-2 DR Production VPC
    eu_hub_vpc  = "10.20.0.0/16"   # EU-West-1 Hub VPC
    eu_prod_vpc = "10.21.0.0/16"   # EU-West-1 Production VPC
    apac_vpc    = "10.30.0.0/16"   # AP-Southeast-1 VPC
  }
  
  validation {
    condition = alltrue([
      for cidr in values(var.vpc_cidrs) : can(cidrhost(cidr, 0))
    ])
    error_message = "All VPC CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# Subnet Configuration
variable "subnet_cidrs" {
  description = "CIDR blocks for subnets in each VPC"
  type = object({
    hub_subnet      = string
    prod_subnet     = string
    dev_subnet      = string
    dr_hub_subnet   = string
    dr_prod_subnet  = string
    eu_hub_subnet   = string
    eu_prod_subnet  = string
    apac_subnet     = string
  })
  
  default = {
    hub_subnet     = "10.0.1.0/24"
    prod_subnet    = "10.1.1.0/24"
    dev_subnet     = "10.2.1.0/24"
    dr_hub_subnet  = "10.10.1.0/24"
    dr_prod_subnet = "10.11.1.0/24"
    eu_hub_subnet  = "10.20.1.0/24"
    eu_prod_subnet = "10.21.1.0/24"
    apac_subnet    = "10.30.1.0/24"
  }
  
  validation {
    condition = alltrue([
      for cidr in values(var.subnet_cidrs) : can(cidrhost(cidr, 0))
    ])
    error_message = "All subnet CIDR blocks must be valid IPv4 CIDR notation."
  }
}

# Availability Zone Configuration
variable "availability_zones" {
  description = "Availability zones for subnet placement in each region"
  type = object({
    primary   = string
    secondary = string
    eu        = string
    apac      = string
  })
  
  default = {
    primary   = "a"  # us-east-1a
    secondary = "a"  # us-west-2a
    eu        = "a"  # eu-west-1a
    apac      = "a"  # ap-southeast-1a
  }
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

# Route 53 Resolver Configuration
variable "enable_route53_resolver" {
  description = "Enable Route 53 Resolver for cross-region DNS"
  type        = bool
  default     = true
}

variable "internal_domain_name" {
  description = "Internal domain name for Route 53 Resolver"
  type        = string
  default     = "internal.global.local"
  
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.internal_domain_name))
    error_message = "Internal domain name must be a valid domain format."
  }
}

# CloudWatch Monitoring Configuration
variable "enable_cloudwatch_monitoring" {
  description = "Enable CloudWatch monitoring for VPC peering and DNS"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14
  
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Security Configuration
variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Type of traffic to capture in VPC Flow Logs"
  type        = string
  default     = "ALL"
  
  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "Flow logs traffic type must be one of: ACCEPT, REJECT, ALL."
  }
}

# Resource Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Network Performance Configuration
variable "enable_enhanced_networking" {
  description = "Enable enhanced networking features where supported"
  type        = bool
  default     = true
}

# Cost Optimization Configuration
variable "enable_cost_optimization_tags" {
  description = "Enable additional tags for cost optimization and tracking"
  type        = bool
  default     = true
}