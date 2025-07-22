# Input variables for the VPN Site-to-Site infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
  
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in format: us-east-1, eu-west-1, etc."
  }
}

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "vpn-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.31.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "172.31.0.0/20"
  
  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "172.31.16.0/20"
  
  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "customer_gateway_ip" {
  description = "Public IP address of the customer gateway (on-premises VPN device)"
  type        = string
  default     = "203.0.113.12"
  
  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.customer_gateway_ip))
    error_message = "Customer gateway IP must be a valid IPv4 address."
  }
}

variable "customer_gateway_bgp_asn" {
  description = "BGP ASN for the customer gateway (on-premises network)"
  type        = number
  default     = 65000
  
  validation {
    condition     = var.customer_gateway_bgp_asn >= 64512 && var.customer_gateway_bgp_asn <= 65534
    error_message = "Customer gateway BGP ASN must be in the private ASN range (64512-65534)."
  }
}

variable "aws_bgp_asn" {
  description = "BGP ASN for the AWS Virtual Private Gateway"
  type        = number
  default     = 64512
  
  validation {
    condition     = var.aws_bgp_asn >= 64512 && var.aws_bgp_asn <= 65534
    error_message = "AWS BGP ASN must be in the private ASN range (64512-65534)."
  }
}

variable "on_premises_cidr" {
  description = "CIDR block for the on-premises network (for security group rules)"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.on_premises_cidr, 0))
    error_message = "On-premises CIDR must be a valid IPv4 CIDR block."
  }
}

variable "create_test_instance" {
  description = "Whether to create a test EC2 instance in the private subnet"
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the test instance"
  type        = string
  default     = "t3.micro"
  
  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.[a-z]+$", var.instance_type))
    error_message = "Instance type must be valid (e.g., t3.micro, t3.small, etc.)."
  }
}

variable "create_cloudwatch_dashboard" {
  description = "Whether to create a CloudWatch dashboard for VPN monitoring"
  type        = bool
  default     = true
}

variable "enable_vpn_logs" {
  description = "Whether to enable VPN connection logging"
  type        = bool
  default     = true
}

variable "tunnel_inside_cidr_blocks" {
  description = "CIDR blocks for VPN tunnel inside IP addresses (optional)"
  type        = list(string)
  default     = []
  
  validation {
    condition = alltrue([
      for cidr in var.tunnel_inside_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All tunnel inside CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}