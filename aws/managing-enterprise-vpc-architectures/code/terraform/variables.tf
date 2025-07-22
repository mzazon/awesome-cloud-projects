# Variables for Multi-VPC Transit Gateway Architecture
# This file defines all customizable parameters for the infrastructure deployment

variable "aws_region" {
  description = "Primary AWS region for the Transit Gateway deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
  }
}

variable "dr_region" {
  description = "Disaster recovery AWS region for cross-region peering"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.dr_region))
    error_message = "DR region must be a valid region identifier."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "enterprise-network"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment designation (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# VPC CIDR Block Configuration
variable "vpc_cidrs" {
  description = "CIDR blocks for each VPC in the architecture"
  type = object({
    production = string
    development = string
    test = string
    shared = string
    dr = string
  })
  default = {
    production  = "10.0.0.0/16"
    development = "10.1.0.0/16"
    test        = "10.2.0.0/16"
    shared      = "10.3.0.0/16"
    dr          = "10.10.0.0/16"
  }

  validation {
    condition = alltrue([
      can(cidrhost(var.vpc_cidrs.production, 0)),
      can(cidrhost(var.vpc_cidrs.development, 0)),
      can(cidrhost(var.vpc_cidrs.test, 0)),
      can(cidrhost(var.vpc_cidrs.shared, 0)),
      can(cidrhost(var.vpc_cidrs.dr, 0))
    ])
    error_message = "All VPC CIDRs must be valid CIDR blocks."
  }
}

# Subnet Configuration
variable "subnet_cidrs" {
  description = "CIDR blocks for subnets within each VPC"
  type = object({
    production = object({
      private_a = string
      private_b = string
    })
    development = object({
      private_a = string
      private_b = string
    })
    test = object({
      private_a = string
      private_b = string
    })
    shared = object({
      private_a = string
      private_b = string
    })
    dr = object({
      private_a = string
      private_b = string
    })
  })
  default = {
    production = {
      private_a = "10.0.1.0/24"
      private_b = "10.0.2.0/24"
    }
    development = {
      private_a = "10.1.1.0/24"
      private_b = "10.1.2.0/24"
    }
    test = {
      private_a = "10.2.1.0/24"
      private_b = "10.2.2.0/24"
    }
    shared = {
      private_a = "10.3.1.0/24"
      private_b = "10.3.2.0/24"
    }
    dr = {
      private_a = "10.10.1.0/24"
      private_b = "10.10.2.0/24"
    }
  }
}

# Availability Zones
variable "availability_zones" {
  description = "List of availability zones to use for subnet deployment"
  type        = list(string)
  default     = ["a", "b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones must be specified for high availability."
  }
}

# Transit Gateway Configuration
variable "transit_gateway_asn" {
  description = "Amazon side ASN for the Transit Gateway"
  type        = number
  default     = 64512

  validation {
    condition     = var.transit_gateway_asn >= 64512 && var.transit_gateway_asn <= 65534
    error_message = "Transit Gateway ASN must be between 64512 and 65534."
  }
}

variable "dr_transit_gateway_asn" {
  description = "Amazon side ASN for the DR Transit Gateway"
  type        = number
  default     = 64513

  validation {
    condition     = var.dr_transit_gateway_asn >= 64512 && var.dr_transit_gateway_asn <= 65534
    error_message = "DR Transit Gateway ASN must be between 64512 and 65534."
  }
}

# Cross-Region Peering Configuration
variable "enable_cross_region_peering" {
  description = "Enable cross-region Transit Gateway peering for disaster recovery"
  type        = bool
  default     = true
}

# Monitoring and Logging Configuration
variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs for all VPCs"
  type        = bool
  default     = true
}

variable "enable_transit_gateway_monitoring" {
  description = "Enable CloudWatch monitoring for Transit Gateway"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Retention period for VPC Flow Logs in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.flow_logs_retention_days)
    error_message = "Flow logs retention must be a valid CloudWatch Logs retention period."
  }
}

# Security Configuration
variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPCs"
  type        = bool
  default     = true
}

variable "enable_dns_resolution" {
  description = "Enable DNS resolution in VPCs"
  type        = bool
  default     = true
}

# Cost Optimization
variable "tgw_data_processing_alarm_threshold" {
  description = "CloudWatch alarm threshold for Transit Gateway data processing (in bytes)"
  type        = number
  default     = 10000000000  # 10 GB

  validation {
    condition     = var.tgw_data_processing_alarm_threshold > 0
    error_message = "Data processing alarm threshold must be greater than 0."
  }
}

# Tagging Configuration
variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "enterprise-network"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = "infrastructure-team"
    CostCenter  = "it-operations"
  }
}

# Resource Naming
variable "resource_prefix" {
  description = "Prefix for resource names to ensure uniqueness"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]*$", var.resource_prefix))
    error_message = "Resource prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "enable_resource_suffix" {
  description = "Add random suffix to resource names for uniqueness"
  type        = bool
  default     = true
}