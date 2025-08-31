# Environment and naming variables
variable "environment" {
  description = "Environment name for resource tagging"
  type        = string
  default     = "demo"
  
  validation {
    condition     = length(var.environment) <= 10
    error_message = "Environment name must be 10 characters or less."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "private-api-integration"
}

# Network configuration variables
variable "vpc_cidr" {
  description = "CIDR block for the target VPC"
  type        = string
  default     = "10.1.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block."
  }
}

variable "subnet_cidrs" {
  description = "CIDR blocks for subnets in different availability zones"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  
  validation {
    condition     = length(var.subnet_cidrs) >= 2
    error_message = "At least 2 subnet CIDRs must be provided for high availability."
  }
}

# API Gateway configuration
variable "api_gateway_name" {
  description = "Name for the private API Gateway"
  type        = string
  default     = "private-demo-api"
}

variable "api_gateway_stage_name" {
  description = "Stage name for API Gateway deployment"
  type        = string
  default     = "prod"
}

# VPC Lattice configuration
variable "vpc_lattice_service_network_name" {
  description = "Name for the VPC Lattice service network"
  type        = string
  default     = "private-api-network"
}

variable "resource_gateway_name" {
  description = "Name for the VPC Lattice resource gateway"
  type        = string
  default     = "api-gateway-resource-gateway"
}

variable "resource_configuration_name" {
  description = "Name for the VPC Lattice resource configuration"
  type        = string
  default     = "private-api-config"
}

# EventBridge configuration
variable "eventbridge_bus_name" {
  description = "Name for the custom EventBridge bus"
  type        = string
  default     = "private-api-bus"
}

variable "eventbridge_connection_name" {
  description = "Name for the EventBridge connection"
  type        = string
  default     = "private-api-connection"
}

variable "eventbridge_rule_name" {
  description = "Name for the EventBridge rule"
  type        = string
  default     = "trigger-private-api-workflow"
}

# Step Functions configuration
variable "step_function_name" {
  description = "Name for the Step Functions state machine"
  type        = string
  default     = "private-api-workflow"
}

# IAM configuration
variable "iam_role_name" {
  description = "Name for the EventBridge and Step Functions IAM role"
  type        = string
  default     = "EventBridgeStepFunctionsVPCLatticeRole"
}

# Resource configuration
variable "api_port" {
  description = "Port for API Gateway private endpoint access"
  type        = number
  default     = 443
  
  validation {
    condition     = var.api_port > 0 && var.api_port <= 65535
    error_message = "API port must be between 1 and 65535."
  }
}

variable "enable_resource_sharing" {
  description = "Enable sharing resource configuration across service networks"
  type        = bool
  default     = true
}

# Additional tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}