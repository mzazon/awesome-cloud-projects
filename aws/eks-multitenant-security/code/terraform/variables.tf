# Variables for EKS Multi-Tenant Cluster Security with Namespace Isolation
# This file defines all configurable parameters for the multi-tenant security implementation

variable "cluster_name" {
  description = "Name of the existing EKS cluster where multi-tenant security will be implemented"
  type        = string
  default     = "my-multi-tenant-cluster"
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment designation for resource tagging and identification"
  type        = string
  default     = "production"
  
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be one of: development, staging, production."
  }
}

variable "tenant_a_name" {
  description = "Name for the first tenant (alpha). Used for namespace, IAM role, and resource naming"
  type        = string
  default     = "tenant-alpha"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tenant_a_name))
    error_message = "Tenant name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "tenant_b_name" {
  description = "Name for the second tenant (beta). Used for namespace, IAM role, and resource naming"
  type        = string
  default     = "tenant-beta"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.tenant_b_name))
    error_message = "Tenant name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "deploy_sample_apps" {
  description = "Whether to deploy sample applications for testing tenant isolation"
  type        = bool
  default     = true
}

variable "network_policy_enabled" {
  description = "Whether to create network policies for tenant isolation (requires compatible CNI)"
  type        = bool
  default     = true
}

variable "tenant_a_quota" {
  description = "Resource quota configuration for tenant A"
  type = object({
    cpu_requests    = string
    memory_requests = string
    cpu_limits      = string
    memory_limits   = string
    pods            = string
    services        = string
    secrets         = string
    configmaps      = string
    pvcs            = string
  })
  default = {
    cpu_requests    = "2"
    memory_requests = "4Gi"
    cpu_limits      = "4"
    memory_limits   = "8Gi"
    pods            = "10"
    services        = "5"
    secrets         = "10"
    configmaps      = "10"
    pvcs            = "4"
  }
}

variable "tenant_b_quota" {
  description = "Resource quota configuration for tenant B"
  type = object({
    cpu_requests    = string
    memory_requests = string
    cpu_limits      = string
    memory_limits   = string
    pods            = string
    services        = string
    secrets         = string
    configmaps      = string
    pvcs            = string
  })
  default = {
    cpu_requests    = "2"
    memory_requests = "4Gi"
    cpu_limits      = "4"
    memory_limits   = "8Gi"
    pods            = "10"
    services        = "5"
    secrets         = "10"
    configmaps      = "10"
    pvcs            = "4"
  }
}

variable "tenant_a_limit_range" {
  description = "Default resource limits and requests for containers in tenant A namespace"
  type = object({
    default_cpu     = string
    default_memory  = string
    request_cpu     = string
    request_memory  = string
  })
  default = {
    default_cpu     = "200m"
    default_memory  = "256Mi"
    request_cpu     = "100m"
    request_memory  = "128Mi"
  }
}

variable "tenant_b_limit_range" {
  description = "Default resource limits and requests for containers in tenant B namespace"
  type = object({
    default_cpu     = string
    default_memory  = string
    request_cpu     = string
    request_memory  = string
  })
  default = {
    default_cpu     = "200m"
    default_memory  = "256Mi"
    request_cpu     = "100m"
    request_memory  = "128Mi"
  }
}

variable "rbac_permissions" {
  description = "RBAC permissions to grant to tenant users within their namespaces"
  type = object({
    core_resources = list(string)
    apps_resources = list(string)
    networking_resources = list(string)
    verbs = list(string)
  })
  default = {
    core_resources = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
    apps_resources = ["deployments", "replicasets", "daemonsets", "statefulsets"]
    networking_resources = ["ingresses", "networkpolicies"]
    verbs = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

variable "additional_tenant_labels" {
  description = "Additional labels to apply to tenant namespaces"
  type        = map(string)
  default     = {}
}

variable "sample_app_images" {
  description = "Container images to use for sample applications"
  type = object({
    tenant_a = string
    tenant_b = string
  })
  default = {
    tenant_a = "nginx:1.20"
    tenant_b = "httpd:2.4"
  }
}

variable "sample_app_replicas" {
  description = "Number of replicas for sample applications"
  type        = number
  default     = 2
  
  validation {
    condition     = var.sample_app_replicas >= 1 && var.sample_app_replicas <= 10
    error_message = "Sample app replicas must be between 1 and 10."
  }
}

variable "network_policy_dns_ports" {
  description = "DNS ports to allow in network policies"
  type = list(object({
    protocol = string
    port     = string
  }))
  default = [
    {
      protocol = "TCP"
      port     = "53"
    },
    {
      protocol = "UDP"
      port     = "53"
    }
  ]
}

variable "iam_role_path" {
  description = "Path for IAM roles created for tenant access"
  type        = string
  default     = "/"
  
  validation {
    condition     = can(regex("^/.*/$", var.iam_role_path))
    error_message = "IAM role path must start and end with '/'."
  }
}

variable "iam_role_max_session_duration" {
  description = "Maximum session duration for tenant IAM roles (in seconds)"
  type        = number
  default     = 3600
  
  validation {
    condition     = var.iam_role_max_session_duration >= 3600 && var.iam_role_max_session_duration <= 43200
    error_message = "IAM role max session duration must be between 3600 and 43200 seconds."
  }
}

variable "enforce_pod_security_standards" {
  description = "Whether to enforce Pod Security Standards on tenant namespaces"
  type        = bool
  default     = false
}

variable "pod_security_standard_level" {
  description = "Pod Security Standard level to enforce (baseline, restricted)"
  type        = string
  default     = "baseline"
  
  validation {
    condition     = contains(["baseline", "restricted"], var.pod_security_standard_level)
    error_message = "Pod Security Standard level must be either 'baseline' or 'restricted'."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}