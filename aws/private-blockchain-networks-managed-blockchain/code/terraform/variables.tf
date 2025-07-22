# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deploying blockchain resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1)."
  }
}

# -----------------------------------------------------------------------------
# Blockchain Network Configuration
# -----------------------------------------------------------------------------

variable "network_name_prefix" {
  description = "Prefix for blockchain network name (suffix will be auto-generated)"
  type        = string
  default     = "SupplyChainNetwork"

  validation {
    condition     = length(var.network_name_prefix) <= 20
    error_message = "Network name prefix must be 20 characters or less."
  }
}

variable "network_description" {
  description = "Description for the blockchain network"
  type        = string
  default     = "Private blockchain network for supply chain tracking"
}

variable "hyperledger_fabric_version" {
  description = "Hyperledger Fabric framework version"
  type        = string
  default     = "2.2"

  validation {
    condition     = contains(["1.4", "2.2"], var.hyperledger_fabric_version)
    error_message = "Hyperledger Fabric version must be either '1.4' or '2.2'."
  }
}

variable "fabric_edition" {
  description = "Hyperledger Fabric edition (STARTER or STANDARD)"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STARTER", "STANDARD"], var.fabric_edition)
    error_message = "Fabric edition must be either 'STARTER' or 'STANDARD'."
  }
}

# -----------------------------------------------------------------------------
# Member Configuration
# -----------------------------------------------------------------------------

variable "member_name_prefix" {
  description = "Prefix for blockchain member name (suffix will be auto-generated)"
  type        = string
  default     = "OrganizationA"

  validation {
    condition     = length(var.member_name_prefix) <= 20
    error_message = "Member name prefix must be 20 characters or less."
  }
}

variable "member_description" {
  description = "Description for the founding blockchain member"
  type        = string
  default     = "Founding member of supply chain network"
}

variable "admin_username" {
  description = "Administrator username for blockchain member"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.admin_username) >= 1 && length(var.admin_username) <= 16
    error_message = "Admin username must be between 1 and 16 characters."
  }
}

variable "admin_password" {
  description = "Administrator password for blockchain member"
  type        = string
  sensitive   = true
  default     = "TempPassword123!"

  validation {
    condition     = length(var.admin_password) >= 8 && length(var.admin_password) <= 32
    error_message = "Admin password must be between 8 and 32 characters."
  }
}

# -----------------------------------------------------------------------------
# Peer Node Configuration
# -----------------------------------------------------------------------------

variable "peer_node_instance_type" {
  description = "EC2 instance type for peer nodes"
  type        = string
  default     = "bc.t3.small"

  validation {
    condition = contains([
      "bc.t3.small", "bc.t3.medium", "bc.t3.large", "bc.t3.xlarge",
      "bc.m5.large", "bc.m5.xlarge", "bc.m5.2xlarge", "bc.m5.4xlarge",
      "bc.c5.large", "bc.c5.xlarge", "bc.c5.2xlarge", "bc.c5.4xlarge"
    ], var.peer_node_instance_type)
    error_message = "Peer node instance type must be a valid blockchain instance type."
  }
}

variable "peer_node_availability_zone" {
  description = "Availability zone for peer node (if not specified, uses region + 'a')"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# VPC and Networking Configuration
# -----------------------------------------------------------------------------

variable "use_default_vpc" {
  description = "Whether to use the default VPC or create a new one"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (only used if use_default_vpc is false)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidrs" {
  description = "CIDR blocks for subnets (only used if use_default_vpc is false)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.subnet_cidrs) >= 2
    error_message = "At least 2 subnet CIDRs must be provided."
  }
}

# -----------------------------------------------------------------------------
# EC2 Client Configuration
# -----------------------------------------------------------------------------

variable "create_ec2_client" {
  description = "Whether to create an EC2 instance for blockchain client operations"
  type        = bool
  default     = true
}

variable "ec2_instance_type" {
  description = "EC2 instance type for blockchain client"
  type        = string
  default     = "t3.medium"

  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "t3.2xlarge", "m5.large", "m5.xlarge", "m5.2xlarge"
    ], var.ec2_instance_type)
    error_message = "EC2 instance type must be a valid instance type."
  }
}

variable "ec2_key_pair_name" {
  description = "Name of EC2 key pair for SSH access (will be created if not exists)"
  type        = string
  default     = "blockchain-client-key"
}

# -----------------------------------------------------------------------------
# Security Configuration
# -----------------------------------------------------------------------------

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access to EC2 client"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All SSH CIDR blocks must be valid IPv4 CIDR blocks."
  }
}

variable "blockchain_ports" {
  description = "List of ports used for blockchain communication"
  type        = list(number)
  default     = [30001, 30002, 7051, 7053]
}

# -----------------------------------------------------------------------------
# Voting Policy Configuration
# -----------------------------------------------------------------------------

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
  description = "Duration in hours for proposal voting periods"
  type        = number
  default     = 24

  validation {
    condition     = var.proposal_duration_hours >= 1 && var.proposal_duration_hours <= 168
    error_message = "Proposal duration must be between 1 and 168 hours (1 week)."
  }
}

variable "threshold_comparator" {
  description = "Threshold comparator for voting policy (GREATER_THAN, GREATER_THAN_OR_EQUAL_TO)"
  type        = string
  default     = "GREATER_THAN"

  validation {
    condition     = contains(["GREATER_THAN", "GREATER_THAN_OR_EQUAL_TO"], var.threshold_comparator)
    error_message = "Threshold comparator must be either 'GREATER_THAN' or 'GREATER_THAN_OR_EQUAL_TO'."
  }
}

# -----------------------------------------------------------------------------
# Monitoring and Logging Configuration
# -----------------------------------------------------------------------------

variable "enable_cloudwatch_logs" {
  description = "Whether to create CloudWatch log groups for blockchain monitoring"
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Whether to enable VPC Flow Logs for network monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention value."
  }
}

# -----------------------------------------------------------------------------
# Resource Tagging
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "SupplyChain"
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Advanced Configuration
# -----------------------------------------------------------------------------

variable "create_vpc_endpoint" {
  description = "Whether to create VPC endpoint for Managed Blockchain"
  type        = bool
  default     = true
}

variable "create_iam_roles" {
  description = "Whether to create IAM roles for blockchain operations"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Whether to enable deletion protection for critical resources"
  type        = bool
  default     = false
}