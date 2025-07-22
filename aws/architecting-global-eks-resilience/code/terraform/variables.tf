# Core configuration variables
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "multi-cluster-eks"
  
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 32
    error_message = "Project name must be between 1 and 32 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Region configuration
variable "primary_region" {
  description = "Primary AWS region for EKS cluster and resources"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.primary_region))
    error_message = "Primary region must be a valid AWS region format (e.g., us-east-1)."
  }
}

variable "secondary_region" {
  description = "Secondary AWS region for EKS cluster and resources"
  type        = string
  default     = "us-west-2"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.secondary_region))
    error_message = "Secondary region must be a valid AWS region format (e.g., us-west-2)."
  }
}

# VPC configuration
variable "primary_vpc_cidr" {
  description = "CIDR block for primary VPC"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.primary_vpc_cidr, 0))
    error_message = "Primary VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for secondary VPC"
  type        = string
  default     = "10.2.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.secondary_vpc_cidr, 0))
    error_message = "Secondary VPC CIDR must be a valid IPv4 CIDR block."
  }
}

# EKS configuration
variable "kubernetes_version" {
  description = "Kubernetes version for EKS clusters"
  type        = string
  default     = "1.28"
  
  validation {
    condition     = contains(["1.26", "1.27", "1.28", "1.29"], var.kubernetes_version)
    error_message = "Kubernetes version must be a supported EKS version."
  }
}

variable "node_instance_types" {
  description = "Instance types for EKS node groups"
  type        = list(string)
  default     = ["m5.large"]
  
  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "At least one instance type must be specified."
  }
}

variable "node_capacity_type" {
  description = "Capacity type for EKS node groups (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
  
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "Node capacity type must be either ON_DEMAND or SPOT."
  }
}

variable "node_scaling_config" {
  description = "Scaling configuration for EKS node groups"
  type = object({
    min_size     = number
    max_size     = number
    desired_size = number
  })
  default = {
    min_size     = 2
    max_size     = 6
    desired_size = 3
  }
  
  validation {
    condition     = var.node_scaling_config.min_size <= var.node_scaling_config.desired_size && var.node_scaling_config.desired_size <= var.node_scaling_config.max_size
    error_message = "min_size <= desired_size <= max_size must be true."
  }
}

# Transit Gateway configuration
variable "transit_gateway_amazon_side_asn" {
  description = "Amazon side ASN for Transit Gateways"
  type = object({
    primary   = number
    secondary = number
  })
  default = {
    primary   = 64512
    secondary = 64513
  }
  
  validation {
    condition = (
      var.transit_gateway_amazon_side_asn.primary >= 64512 && 
      var.transit_gateway_amazon_side_asn.primary <= 65534 &&
      var.transit_gateway_amazon_side_asn.secondary >= 64512 && 
      var.transit_gateway_amazon_side_asn.secondary <= 65534 &&
      var.transit_gateway_amazon_side_asn.primary != var.transit_gateway_amazon_side_asn.secondary
    )
    error_message = "Transit Gateway ASNs must be in the private ASN range (64512-65534) and different from each other."
  }
}

# VPC Lattice configuration
variable "enable_vpc_lattice" {
  description = "Enable VPC Lattice service network for cross-cluster communication"
  type        = bool
  default     = true
}

variable "vpc_lattice_auth_type" {
  description = "Authentication type for VPC Lattice service network"
  type        = string
  default     = "AWS_IAM"
  
  validation {
    condition     = contains(["NONE", "AWS_IAM"], var.vpc_lattice_auth_type)
    error_message = "VPC Lattice auth type must be either NONE or AWS_IAM."
  }
}

# Route 53 configuration
variable "create_route53_health_checks" {
  description = "Create Route 53 health checks for global load balancing"
  type        = bool
  default     = false
}

variable "health_check_fqdn_primary" {
  description = "FQDN for primary region health check"
  type        = string
  default     = ""
}

variable "health_check_fqdn_secondary" {
  description = "FQDN for secondary region health check"
  type        = string
  default     = ""
}

# Logging configuration
variable "enable_control_plane_logging" {
  description = "Enable EKS control plane logging"
  type        = bool
  default     = true
}

variable "control_plane_log_types" {
  description = "List of control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
  
  validation {
    condition = alltrue([
      for log_type in var.control_plane_log_types : 
      contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
    ])
    error_message = "Control plane log types must be valid EKS log types."
  }
}

# Security configuration
variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Tagging
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}