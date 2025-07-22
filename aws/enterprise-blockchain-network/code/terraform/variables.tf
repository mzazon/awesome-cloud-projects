# Variable definitions for Hyperledger Fabric Managed Blockchain infrastructure
# These variables allow customization of the blockchain network and associated resources

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "network_name" {
  description = "Name for the Hyperledger Fabric network"
  type        = string
  default     = "fabric-network"
  
  validation {
    condition     = length(var.network_name) <= 64 && can(regex("^[a-zA-Z0-9-]+$", var.network_name))
    error_message = "Network name must be 64 characters or less and contain only alphanumeric characters and hyphens."
  }
}

variable "member_name" {
  description = "Name for the founding member organization"
  type        = string
  default     = "member-org"
  
  validation {
    condition     = length(var.member_name) <= 64 && can(regex("^[a-zA-Z0-9-]+$", var.member_name))
    error_message = "Member name must be 64 characters or less and contain only alphanumeric characters and hyphens."
  }
}

variable "network_edition" {
  description = "Edition of the Managed Blockchain network (STARTER or STANDARD)"
  type        = string
  default     = "STARTER"
  
  validation {
    condition     = contains(["STARTER", "STANDARD"], var.network_edition)
    error_message = "Network edition must be either STARTER or STANDARD."
  }
}

variable "fabric_version" {
  description = "Version of Hyperledger Fabric to use"
  type        = string
  default     = "2.2"
  
  validation {
    condition     = contains(["1.4", "2.2"], var.fabric_version)
    error_message = "Fabric version must be either 1.4 or 2.2."
  }
}

variable "admin_username" {
  description = "Username for the member organization admin"
  type        = string
  default     = "admin"
  
  validation {
    condition     = length(var.admin_username) >= 1 && length(var.admin_username) <= 16
    error_message = "Admin username must be between 1 and 16 characters."
  }
}

variable "admin_password" {
  description = "Password for the member organization admin (must meet complexity requirements)"
  type        = string
  sensitive   = true
  default     = "TempPassword123!"
  
  validation {
    condition     = length(var.admin_password) >= 8 && length(var.admin_password) <= 32
    error_message = "Admin password must be between 8 and 32 characters."
  }
}

variable "peer_node_instance_type" {
  description = "Instance type for peer nodes"
  type        = string
  default     = "bc.t3.small"
  
  validation {
    condition = contains([
      "bc.t3.small", "bc.t3.medium", "bc.t3.large", "bc.t3.xlarge",
      "bc.m5.large", "bc.m5.xlarge", "bc.m5.2xlarge", "bc.m5.4xlarge"
    ], var.peer_node_instance_type)
    error_message = "Peer node instance type must be a valid Managed Blockchain instance type."
  }
}

variable "peer_node_availability_zone" {
  description = "Availability zone for peer nodes (if not specified, uses first AZ in region)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "Subnet CIDR must be a valid IPv4 CIDR block."
  }
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to client instances"
  type        = string
  default     = "0.0.0.0/0"
  
  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Allowed SSH CIDR must be a valid IPv4 CIDR block."
  }
}

variable "client_instance_type" {
  description = "Instance type for blockchain client EC2 instance"
  type        = string
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access (must exist in the region)"
  type        = string
  default     = ""
}

variable "create_client_instance" {
  description = "Whether to create an EC2 client instance for blockchain interaction"
  type        = bool
  default     = true
}

variable "voting_threshold_percentage" {
  description = "Percentage threshold for network voting proposals"
  type        = number
  default     = 50
  
  validation {
    condition     = var.voting_threshold_percentage >= 1 && var.voting_threshold_percentage <= 100
    error_message = "Voting threshold percentage must be between 1 and 100."
  }
}

variable "proposal_duration_hours" {
  description = "Duration in hours for network proposals"
  type        = number
  default     = 24
  
  validation {
    condition     = var.proposal_duration_hours >= 1 && var.proposal_duration_hours <= 168
    error_message = "Proposal duration must be between 1 and 168 hours (1 week)."
  }
}

variable "enable_logging" {
  description = "Enable CloudWatch logging for the blockchain network"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 7
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}