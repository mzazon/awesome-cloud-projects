# Input Variables for Progressive Web App Amplify Hosting Infrastructure
# These variables allow customization of the PWA deployment

variable "aws_region" {
  description = "AWS region for deploying resources"
  type        = string
  default     = "us-east-1"

  validation {
    condition = can(regex("^[a-z0-9-]+$", var.aws_region))
    error_message = "AWS region must be a valid region identifier."
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

variable "app_name" {
  description = "Name of the Progressive Web App"
  type        = string
  default     = "pwa-amplify-app"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.app_name))
    error_message = "App name must contain only alphanumeric characters and hyphens."
  }
}

variable "repository_url" {
  description = "Git repository URL for the PWA source code"
  type        = string
  default     = ""

  validation {
    condition = var.repository_url == "" || can(regex("^https://github\\.com/[^/]+/[^/]+$", var.repository_url))
    error_message = "Repository URL must be a valid GitHub HTTPS URL or empty string."
  }
}

variable "branch_name" {
  description = "Git branch name to deploy"
  type        = string
  default     = "main"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]+$", var.branch_name))
    error_message = "Branch name must contain only alphanumeric characters, hyphens, underscores, and forward slashes."
  }
}

variable "domain_name" {
  description = "Custom domain name for the PWA (leave empty to skip domain configuration)"
  type        = string
  default     = ""

  validation {
    condition = var.domain_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]?\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid fully qualified domain name or empty string."
  }
}

variable "subdomain_prefix" {
  description = "Subdomain prefix for the PWA (e.g., 'pwa' for pwa.example.com)"
  type        = string
  default     = "pwa"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.subdomain_prefix))
    error_message = "Subdomain prefix must contain only alphanumeric characters and hyphens."
  }
}

variable "enable_auto_branch_creation" {
  description = "Enable automatic branch creation for new repository branches"
  type        = bool
  default     = true
}

variable "enable_pull_request_preview" {
  description = "Enable pull request preview deployments"
  type        = bool
  default     = true
}

variable "build_spec" {
  description = "Build specification for Amplify (amplify.yml content)"
  type        = string
  default     = ""
}

variable "environment_variables" {
  description = "Environment variables for the Amplify application"
  type        = map(string)
  default     = {}
}

variable "access_token" {
  description = "GitHub access token for repository access (sensitive)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_basic_auth" {
  description = "Enable basic authentication for branch access"
  type        = bool
  default     = false
}

variable "basic_auth_username" {
  description = "Username for basic authentication"
  type        = string
  default     = ""
}

variable "basic_auth_password" {
  description = "Password for basic authentication (sensitive)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "custom_rules" {
  description = "List of custom redirect and rewrite rules for the PWA"
  type = list(object({
    source    = string
    target    = string
    status    = string
    condition = optional(string)
  }))
  default = [
    {
      source = "/<*>"
      target = "/index.html"
      status = "404-200"
    }
  ]
}

variable "framework" {
  description = "Framework detection for build optimization"
  type        = string
  default     = "Web"

  validation {
    condition = contains([
      "Web", "React", "Angular", "Vue", "Next.js", "Gatsby", "Hugo", "Jekyll",
      "Nuxt", "Gridsome", "Svelte", "Ionic React", "Ionic Angular"
    ], var.framework)
    error_message = "Framework must be a supported Amplify framework."
  }
}

variable "performance_mode" {
  description = "Performance mode for the application (DYNAMIC or COMPUTE_OPTIMIZED)"
  type        = string
  default     = "COMPUTE_OPTIMIZED"

  validation {
    condition     = contains(["DYNAMIC", "COMPUTE_OPTIMIZED"], var.performance_mode)
    error_message = "Performance mode must be either DYNAMIC or COMPUTE_OPTIMIZED."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}