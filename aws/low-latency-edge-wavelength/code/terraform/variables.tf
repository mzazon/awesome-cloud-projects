# ============================================================================
# Variables for Low-Latency Edge Applications with AWS Wavelength and CloudFront
# ============================================================================

# ============================================================================
# Project Configuration
# ============================================================================

variable "project_name" {
  description = "Name of the project (will be prefixed with random suffix)"
  type        = string
  default     = "edge-app"
  
  validation {
    condition     = length(var.project_name) <= 20
    error_message = "Project name must be 20 characters or less."
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

# ============================================================================
# Network Configuration
# ============================================================================

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "wavelength_subnet_cidr" {
  description = "CIDR block for the Wavelength subnet"
  type        = string
  default     = "10.0.1.0/24"
  
  validation {
    condition     = can(cidrhost(var.wavelength_subnet_cidr, 0))
    error_message = "Wavelength subnet CIDR must be a valid CIDR block."
  }
}

variable "regional_subnet_cidr" {
  description = "CIDR block for the regional subnet"
  type        = string
  default     = "10.0.2.0/24"
  
  validation {
    condition     = can(cidrhost(var.regional_subnet_cidr, 0))
    error_message = "Regional subnet CIDR must be a valid CIDR block."
  }
}

variable "wavelength_zone" {
  description = "Specific Wavelength Zone to use (leave empty to use first available)"
  type        = string
  default     = ""
  
  validation {
    condition     = var.wavelength_zone == "" || can(regex("^[a-z0-9-]+$", var.wavelength_zone))
    error_message = "Wavelength zone must be a valid zone name or empty string."
  }
}

# ============================================================================
# Instance Configuration
# ============================================================================

variable "wavelength_instance_type" {
  description = "EC2 instance type for Wavelength edge servers"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge",
      "r5.large", "r5.xlarge", "r5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.wavelength_instance_type)
    error_message = "Instance type must be supported in Wavelength Zones."
  }
}

variable "regional_instance_type" {
  description = "EC2 instance type for regional backend servers"
  type        = string
  default     = "t3.medium"
  
  validation {
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large", "t3.xlarge", "t3.2xlarge",
      "t2.micro", "t2.small", "t2.medium", "t2.large", "t2.xlarge", "t2.2xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge",
      "r5.large", "r5.xlarge", "r5.2xlarge", "r5.4xlarge"
    ], var.regional_instance_type)
    error_message = "Regional instance type must be a valid EC2 instance type."
  }
}

variable "deploy_regional_backend" {
  description = "Whether to deploy regional backend servers"
  type        = bool
  default     = true
}

# ============================================================================
# Application Configuration
# ============================================================================

variable "application_port" {
  description = "Port for the edge application (e.g., game server)"
  type        = number
  default     = 8080
  
  validation {
    condition     = var.application_port > 1024 && var.application_port < 65536
    error_message = "Application port must be between 1025 and 65535."
  }
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 8080
  
  validation {
    condition     = var.health_check_port > 1024 && var.health_check_port < 65536
    error_message = "Health check port must be between 1025 and 65535."
  }
}

variable "health_check_path" {
  description = "Path for health checks"
  type        = string
  default     = "/health"
  
  validation {
    condition     = can(regex("^/", var.health_check_path))
    error_message = "Health check path must start with '/'."
  }
}

# ============================================================================
# CloudFront Configuration
# ============================================================================

variable "cloudfront_price_class" {
  description = "CloudFront price class for global distribution"
  type        = string
  default     = "PriceClass_All"
  
  validation {
    condition = contains([
      "PriceClass_100", "PriceClass_200", "PriceClass_All"
    ], var.cloudfront_price_class)
    error_message = "CloudFront price class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

# ============================================================================
# DNS Configuration
# ============================================================================

variable "domain_name" {
  description = "Domain name for the application (leave empty to skip DNS setup)"
  type        = string
  default     = ""
  
  validation {
    condition = var.domain_name == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain or empty string."
  }
}

# ============================================================================
# Monitoring Configuration
# ============================================================================

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# ============================================================================
# Security Configuration
# ============================================================================

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring for EC2 instances"
  type        = bool
  default     = false
}

variable "enable_session_manager" {
  description = "Enable AWS Systems Manager Session Manager for secure access"
  type        = bool
  default     = true
}

# ============================================================================
# Backup and Disaster Recovery
# ============================================================================

variable "enable_automated_backups" {
  description = "Enable automated EBS volume backups"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# ============================================================================
# Cost Optimization
# ============================================================================

variable "enable_spot_instances" {
  description = "Use Spot instances for cost optimization (not recommended for production)"
  type        = bool
  default     = false
}

variable "spot_instance_interruption_behavior" {
  description = "Behavior when Spot instance is interrupted"
  type        = string
  default     = "terminate"
  
  validation {
    condition     = contains(["hibernate", "stop", "terminate"], var.spot_instance_interruption_behavior)
    error_message = "Spot instance interruption behavior must be hibernate, stop, or terminate."
  }
}

# ============================================================================
# Advanced Configuration
# ============================================================================

variable "custom_user_data" {
  description = "Custom user data script to run on instances (base64 encoded)"
  type        = string
  default     = ""
}

variable "additional_security_group_rules" {
  description = "Additional security group rules to apply"
  type = list(object({
    type        = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
    description = string
  }))
  default = []
}

variable "enable_waf" {
  description = "Enable AWS WAF for CloudFront distribution"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Rate limit for WAF (requests per 5-minute period)"
  type        = number
  default     = 10000
  
  validation {
    condition     = var.waf_rate_limit >= 100 && var.waf_rate_limit <= 2000000000
    error_message = "WAF rate limit must be between 100 and 2,000,000,000."
  }
}

# ============================================================================
# Feature Flags
# ============================================================================

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for distributed tracing"
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = false
}

variable "enable_enhanced_networking" {
  description = "Enable enhanced networking (SR-IOV) for supported instance types"
  type        = bool
  default     = true
}

# ============================================================================
# Compliance and Governance
# ============================================================================

variable "enable_config_rules" {
  description = "Enable AWS Config compliance rules"
  type        = bool
  default     = false
}

variable "enable_cloudtrail" {
  description = "Enable CloudTrail for API auditing"
  type        = bool
  default     = false
}

variable "enable_guardduty" {
  description = "Enable GuardDuty for threat detection"
  type        = bool
  default     = false
}

# ============================================================================
# Tags and Metadata
# ============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition     = length(var.additional_tags) <= 50
    error_message = "Cannot specify more than 50 additional tags."
  }
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = ""
}

variable "business_unit" {
  description = "Business unit for resource organization"
  type        = string
  default     = ""
}

variable "data_classification" {
  description = "Data classification level (public, internal, confidential, restricted)"
  type        = string
  default     = "internal"
  
  validation {
    condition = contains([
      "public", "internal", "confidential", "restricted"
    ], var.data_classification)
    error_message = "Data classification must be public, internal, confidential, or restricted."
  }
}