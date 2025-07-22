# ============================================================================
# AWS EKS Ingress Controllers with AWS Load Balancer Controller
# Terraform Configuration - Variables
# ============================================================================

# ============================================================================
# AWS Configuration Variables
# ============================================================================

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-west-2"

  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-west-2, eu-west-1, etc."
  }
}

# ============================================================================
# EKS Cluster Configuration
# ============================================================================

variable "cluster_name" {
  description = "Name of the existing EKS cluster to deploy the AWS Load Balancer Controller to"
  type        = string

  validation {
    condition     = length(var.cluster_name) > 0 && length(var.cluster_name) <= 63
    error_message = "Cluster name must be between 1 and 63 characters."
  }
}

# ============================================================================
# AWS Load Balancer Controller Configuration
# ============================================================================

variable "alb_controller_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart to install"
  type        = string
  default     = "1.8.1"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.alb_controller_version))
    error_message = "Version must be in semantic versioning format (e.g., 1.8.1)."
  }
}

variable "controller_image_tag" {
  description = "Tag for the AWS Load Balancer Controller image"
  type        = string
  default     = "v2.8.1"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.controller_image_tag))
    error_message = "Image tag must be in the format v2.8.1."
  }
}

# ============================================================================
# Application Configuration
# ============================================================================

variable "demo_namespace" {
  description = "Kubernetes namespace for demo applications"
  type        = string
  default     = "ingress-demo"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.demo_namespace))
    error_message = "Namespace must be valid Kubernetes namespace name (lowercase alphanumeric and hyphens)."
  }
}

variable "sample_app_replicas" {
  description = "Number of replicas for sample applications"
  type        = number
  default     = 3

  validation {
    condition     = var.sample_app_replicas >= 1 && var.sample_app_replicas <= 10
    error_message = "Sample app replicas must be between 1 and 10."
  }
}

variable "create_sample_ingresses" {
  description = "Whether to create sample ingress resources for demonstration"
  type        = bool
  default     = true
}

# ============================================================================
# Domain and SSL Configuration
# ============================================================================

variable "domain_name" {
  description = "Domain name for SSL certificate and ingress hosts (leave empty to skip SSL configuration)"
  type        = string
  default     = ""

  validation {
    condition = var.domain_name == "" || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.[a-zA-Z]{2,}$", var.domain_name))
    error_message = "Domain name must be a valid domain (e.g., example.com) or empty string."
  }
}

variable "certificate_arn" {
  description = "ARN of existing ACM certificate to use instead of creating a new one"
  type        = string
  default     = ""

  validation {
    condition = var.certificate_arn == "" || can(regex("^arn:aws:acm:", var.certificate_arn))
    error_message = "Certificate ARN must be a valid ACM certificate ARN or empty string."
  }
}

# ============================================================================
# Logging and Monitoring Configuration
# ============================================================================

variable "enable_access_logs" {
  description = "Enable ALB access logs to S3"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket name for ALB access logs (if not provided, a new bucket will be created when enable_access_logs is true)"
  type        = string
  default     = ""

  validation {
    condition = var.access_logs_bucket == "" || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.access_logs_bucket))
    error_message = "S3 bucket name must be valid (3-63 characters, lowercase, alphanumeric and hyphens)."
  }
}

variable "access_logs_prefix" {
  description = "Prefix for ALB access logs in S3"
  type        = string
  default     = "alb-logs"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_-]*$", var.access_logs_prefix))
    error_message = "Access logs prefix can only contain alphanumeric characters, hyphens, underscores, and forward slashes."
  }
}

# ============================================================================
# Load Balancer Configuration
# ============================================================================

variable "load_balancer_scheme" {
  description = "Load balancer scheme: internet-facing or internal"
  type        = string
  default     = "internet-facing"

  validation {
    condition     = contains(["internet-facing", "internal"], var.load_balancer_scheme)
    error_message = "Load balancer scheme must be either 'internet-facing' or 'internal'."
  }
}

variable "target_type" {
  description = "Target type for ALB target groups: ip or instance"
  type        = string
  default     = "ip"

  validation {
    condition     = contains(["ip", "instance"], var.target_type)
    error_message = "Target type must be either 'ip' or 'instance'."
  }
}

variable "healthcheck_path" {
  description = "Path for ALB health checks"
  type        = string
  default     = "/"

  validation {
    condition     = can(regex("^/", var.healthcheck_path))
    error_message = "Health check path must start with '/'."
  }
}

variable "healthcheck_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 10

  validation {
    condition     = var.healthcheck_interval >= 5 && var.healthcheck_interval <= 300
    error_message = "Health check interval must be between 5 and 300 seconds."
  }
}

variable "healthcheck_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5

  validation {
    condition     = var.healthcheck_timeout >= 2 && var.healthcheck_timeout <= 120
    error_message = "Health check timeout must be between 2 and 120 seconds."
  }
}

variable "healthy_threshold_count" {
  description = "Number of consecutive successful health checks to consider target healthy"
  type        = number
  default     = 2

  validation {
    condition     = var.healthy_threshold_count >= 2 && var.healthy_threshold_count <= 10
    error_message = "Healthy threshold count must be between 2 and 10."
  }
}

variable "unhealthy_threshold_count" {
  description = "Number of consecutive failed health checks to consider target unhealthy"
  type        = number
  default     = 3

  validation {
    condition     = var.unhealthy_threshold_count >= 2 && var.unhealthy_threshold_count <= 10
    error_message = "Unhealthy threshold count must be between 2 and 10."
  }
}

# ============================================================================
# SSL/TLS Configuration
# ============================================================================

variable "ssl_policy" {
  description = "SSL security policy for HTTPS listeners"
  type        = string
  default     = "ELBSecurityPolicy-TLS-1-2-2019-07"

  validation {
    condition = contains([
      "ELBSecurityPolicy-TLS-1-0-2015-04",
      "ELBSecurityPolicy-TLS-1-1-2017-01",
      "ELBSecurityPolicy-TLS-1-2-2017-01",
      "ELBSecurityPolicy-TLS-1-2-Ext-2018-06",
      "ELBSecurityPolicy-FS-2018-06",
      "ELBSecurityPolicy-FS-1-1-2019-08",
      "ELBSecurityPolicy-FS-1-2-2019-08",
      "ELBSecurityPolicy-FS-1-2-Res-2019-08",
      "ELBSecurityPolicy-TLS-1-2-2019-07",
      "ELBSecurityPolicy-TLS-1-2-Ext-2019-07",
      "ELBSecurityPolicy-FS-1-2-Res-2020-10"
    ], var.ssl_policy)
    error_message = "SSL policy must be a valid ELB security policy."
  }
}

variable "enable_ssl_redirect" {
  description = "Enable automatic HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

# ============================================================================
# Network Load Balancer Configuration
# ============================================================================

variable "create_nlb_service" {
  description = "Create a Network Load Balancer service for demonstration"
  type        = bool
  default     = true
}

variable "nlb_cross_zone_enabled" {
  description = "Enable cross-zone load balancing for NLB"
  type        = bool
  default     = true
}

# ============================================================================
# Advanced Routing Configuration
# ============================================================================

variable "enable_weighted_routing" {
  description = "Create weighted routing ingress for canary deployments"
  type        = bool
  default     = false
}

variable "traffic_weight_v1" {
  description = "Traffic weight percentage for v1 service (0-100)"
  type        = number
  default     = 70

  validation {
    condition     = var.traffic_weight_v1 >= 0 && var.traffic_weight_v1 <= 100
    error_message = "Traffic weight must be between 0 and 100."
  }
}

variable "traffic_weight_v2" {
  description = "Traffic weight percentage for v2 service (0-100)"
  type        = number
  default     = 30

  validation {
    condition     = var.traffic_weight_v2 >= 0 && var.traffic_weight_v2 <= 100
    error_message = "Traffic weight must be between 0 and 100."
  }
}

# ============================================================================
# WAF and Security Configuration
# ============================================================================

variable "enable_waf" {
  description = "Enable AWS WAF integration with ALB"
  type        = bool
  default     = false
}

variable "waf_acl_arn" {
  description = "ARN of existing WAF Web ACL to associate with ALB"
  type        = string
  default     = ""

  validation {
    condition = var.waf_acl_arn == "" || can(regex("^arn:aws:wafv2:", var.waf_acl_arn))
    error_message = "WAF ACL ARN must be a valid WAFv2 ACL ARN or empty string."
  }
}

variable "enable_shield_advanced" {
  description = "Enable AWS Shield Advanced protection for load balancers"
  type        = bool
  default     = false
}

# ============================================================================
# Performance and Scaling Configuration
# ============================================================================

variable "idle_timeout_seconds" {
  description = "Connection idle timeout for ALB in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.idle_timeout_seconds >= 1 && var.idle_timeout_seconds <= 4000
    error_message = "Idle timeout must be between 1 and 4000 seconds."
  }
}

variable "deregistration_delay_seconds" {
  description = "Target deregistration delay in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay_seconds >= 0 && var.deregistration_delay_seconds <= 3600
    error_message = "Deregistration delay must be between 0 and 3600 seconds."
  }
}

variable "enable_stickiness" {
  description = "Enable session stickiness for target groups"
  type        = bool
  default     = false
}

variable "stickiness_duration" {
  description = "Duration of session stickiness in seconds"
  type        = number
  default     = 86400

  validation {
    condition     = var.stickiness_duration >= 1 && var.stickiness_duration <= 604800
    error_message = "Stickiness duration must be between 1 and 604800 seconds (1 week)."
  }
}

# ============================================================================
# Resource Tagging
# ============================================================================

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default = {
    Environment   = "demo"
    Project       = "eks-ingress-demo"
    ManagedBy     = "terraform"
    Purpose       = "aws-load-balancer-controller-demo"
  }

  validation {
    condition     = length(var.tags) <= 50
    error_message = "Maximum of 50 tags allowed per resource."
  }
}

variable "additional_tags" {
  description = "Additional tags to merge with default tags"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Feature Flags
# ============================================================================

variable "create_oidc_provider" {
  description = "Create OIDC identity provider for IRSA (set to false if already exists)"
  type        = bool
  default     = true
}

variable "wait_for_load_balancer" {
  description = "Wait for load balancers to be fully provisioned before completing"
  type        = bool
  default     = true
}

variable "enable_pod_readiness_gate" {
  description = "Enable pod readiness gate for zero-downtime deployments"
  type        = bool
  default     = true
}

# ============================================================================
# Development and Testing Options
# ============================================================================

variable "deployment_mode" {
  description = "Deployment mode: development, staging, or production"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production"], var.deployment_mode)
    error_message = "Deployment mode must be one of: development, staging, production."
  }
}

variable "enable_debug_logging" {
  description = "Enable debug logging for AWS Load Balancer Controller"
  type        = bool
  default     = false
}

variable "controller_log_level" {
  description = "Log level for AWS Load Balancer Controller (info, debug, warn, error)"
  type        = string
  default     = "info"

  validation {
    condition     = contains(["info", "debug", "warn", "error"], var.controller_log_level)
    error_message = "Log level must be one of: info, debug, warn, error."
  }
}

# ============================================================================
# Backup and Disaster Recovery
# ============================================================================

variable "enable_deletion_protection" {
  description = "Enable deletion protection for load balancers"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Number of days to retain access log backups"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 1 and 365 days."
  }
}

# ============================================================================
# Enhanced Features for Production
# ============================================================================

variable "enable_efa_support" {
  description = "Enable Elastic Fabric Adapter (EFA) support for high performance computing workloads"
  type        = bool
  default     = false
}