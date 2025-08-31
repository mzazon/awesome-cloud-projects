# Input Variables for Simple Website Hosting with Lightsail
# These variables allow customization of the WordPress hosting infrastructure

variable "aws_region" {
  description = "AWS region where Lightsail resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., us-east-1, eu-west-1)."
  }
}

variable "environment" {
  description = "Environment name for resource tagging and identification"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "instance_bundle_id" {
  description = "Lightsail instance bundle (plan) for WordPress hosting"
  type        = string
  default     = "nano_3_0"

  validation {
    condition = contains([
      "nano_3_0",    # $5/month  - 1 vCPU, 0.5 GB RAM, 20 GB SSD
      "micro_3_0",   # $10/month - 1 vCPU, 1 GB RAM, 40 GB SSD
      "small_3_0",   # $20/month - 1 vCPU, 2 GB RAM, 60 GB SSD
      "medium_3_0",  # $40/month - 2 vCPU, 4 GB RAM, 80 GB SSD
      "large_3_0",   # $80/month - 2 vCPU, 8 GB RAM, 160 GB SSD
      "xlarge_3_0"   # $160/month - 4 vCPU, 16 GB RAM, 320 GB SSD
    ], var.instance_bundle_id)
    error_message = "Instance bundle must be a valid Lightsail bundle ID (nano_3_0, micro_3_0, small_3_0, medium_3_0, large_3_0, xlarge_3_0)."
  }
}

variable "blueprint_id" {
  description = "Lightsail blueprint (application) to install on the instance"
  type        = string
  default     = "wordpress"

  validation {
    condition = contains([
      "wordpress",
      "wordpress_multisite",
      "lamp_8_0",
      "nginx",
      "apache"
    ], var.blueprint_id)
    error_message = "Blueprint must be a valid Lightsail application blueprint."
  }
}

variable "project_name" {
  description = "Name prefix for all resources (will be combined with random suffix)"
  type        = string
  default     = "wordpress-site"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "enable_static_ip" {
  description = "Whether to create and attach a static IP address to the instance"
  type        = bool
  default     = true
}

variable "enable_automatic_backups" {
  description = "Whether to enable automatic daily backups for the instance"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain automatic backups (7 days max for Lightsail)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 7
    error_message = "Backup retention must be between 1 and 7 days."
  }
}

variable "custom_domain" {
  description = "Custom domain name for the website (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.custom_domain == "" || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.custom_domain))
    error_message = "Domain must be a valid domain name (e.g., example.com) or empty string."
  }
}

variable "create_dns_zone" {
  description = "Whether to create a Lightsail DNS zone for the custom domain"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9 ._:/=+@-]{1,255}$", k))])
    error_message = "Tag keys must be valid AWS tag keys (1-255 characters, letters, numbers, spaces, and ._:/=+@- characters)."
  }
}

variable "instance_key_pair_name" {
  description = "Name of existing AWS key pair for SSH access (optional)"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed SSH access to the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for cidr in var.allowed_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "All values must be valid CIDR blocks (e.g., 0.0.0.0/0, 10.0.0.0/8)."
  }
}

variable "enable_monitoring" {
  description = "Whether to enable detailed monitoring for the instance"
  type        = bool
  default     = true
}