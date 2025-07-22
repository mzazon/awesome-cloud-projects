# Input variables for multi-region Transit Gateway infrastructure
# This file defines all configurable parameters for the deployment

variable "project_name" {
  description = "Name of the project for resource naming and tagging"
  type        = string
  default     = "multi-region-tgw"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project_name))
    error_message = "Project name must contain only alphanumeric characters and hyphens."
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

variable "primary_region" {
  description = "AWS region for primary Transit Gateway and VPCs"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.primary_region))
    error_message = "Primary region must be a valid AWS region identifier."
  }
}

variable "secondary_region" {
  description = "AWS region for secondary Transit Gateway and VPCs"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region identifier."
  }
}

variable "primary_vpc_a_cidr" {
  description = "CIDR block for primary VPC A"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition = can(cidrhost(var.primary_vpc_a_cidr, 0))
    error_message = "Primary VPC A CIDR must be a valid IPv4 CIDR block."
  }
}

variable "primary_vpc_b_cidr" {
  description = "CIDR block for primary VPC B"
  type        = string
  default     = "10.2.0.0/16"

  validation {
    condition = can(cidrhost(var.primary_vpc_b_cidr, 0))
    error_message = "Primary VPC B CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_vpc_a_cidr" {
  description = "CIDR block for secondary VPC A"
  type        = string
  default     = "10.3.0.0/16"

  validation {
    condition = can(cidrhost(var.secondary_vpc_a_cidr, 0))
    error_message = "Secondary VPC A CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_vpc_b_cidr" {
  description = "CIDR block for secondary VPC B"
  type        = string
  default     = "10.4.0.0/16"

  validation {
    condition = can(cidrhost(var.secondary_vpc_b_cidr, 0))
    error_message = "Secondary VPC B CIDR must be a valid IPv4 CIDR block."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPCs"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPCs"
  type        = bool
  default     = true
}

variable "primary_tgw_asn" {
  description = "BGP ASN for primary Transit Gateway"
  type        = number
  default     = 64512

  validation {
    condition = var.primary_tgw_asn >= 64512 && var.primary_tgw_asn <= 65534
    error_message = "Primary TGW ASN must be in the private ASN range (64512-65534)."
  }
}

variable "secondary_tgw_asn" {
  description = "BGP ASN for secondary Transit Gateway"
  type        = number
  default     = 64513

  validation {
    condition = var.secondary_tgw_asn >= 64512 && var.secondary_tgw_asn <= 65534
    error_message = "Secondary TGW ASN must be in the private ASN range (64512-65534)."
  }
}

variable "enable_default_route_table_association" {
  description = "Enable default route table association for Transit Gateway"
  type        = bool
  default     = false
}

variable "enable_default_route_table_propagation" {
  description = "Enable default route table propagation for Transit Gateway"
  type        = bool
  default     = false
}

variable "enable_auto_accept_shared_attachments" {
  description = "Enable auto accept shared attachments for Transit Gateway"
  type        = bool
  default     = "enable"
}

variable "enable_multicast_support" {
  description = "Enable multicast support for Transit Gateway"
  type        = bool
  default     = false
}

variable "create_cloudwatch_dashboard" {
  description = "Create CloudWatch dashboard for monitoring Transit Gateway metrics"
  type        = bool
  default     = true
}

variable "enable_cross_region_icmp" {
  description = "Enable ICMP traffic for cross-region connectivity testing"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}