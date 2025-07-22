# EKS Multi-Tenant Cluster Security with Namespace Isolation
# This Terraform configuration implements multi-tenant security in EKS using namespaces,
# RBAC, network policies, and resource quotas for tenant isolation.

# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data source for existing EKS cluster
data "aws_eks_cluster" "existing" {
  name = var.cluster_name
}

# Data source for existing EKS cluster authentication
data "aws_eks_cluster_auth" "existing" {
  name = var.cluster_name
}

# Local values for resource naming and configuration
locals {
  common_tags = {
    Environment = var.environment
    Project     = "EKS-Multi-Tenant-Security"
    Recipe      = "eks-multi-tenant-cluster-security-namespace-isolation"
    ManagedBy   = "Terraform"
  }
  
  # Tenant configurations
  tenants = {
    alpha = {
      name             = var.tenant_a_name
      labels = {
        tenant      = "alpha"
        isolation   = "enabled"
        environment = "production"
      }
      rbac_username = "${var.tenant_a_name}-user"
      quota = {
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
      limit_range = {
        default_cpu     = "200m"
        default_memory  = "256Mi"
        request_cpu     = "100m"
        request_memory  = "128Mi"
      }
    }
    beta = {
      name             = var.tenant_b_name
      labels = {
        tenant      = "beta"
        isolation   = "enabled"
        environment = "production"
      }
      rbac_username = "${var.tenant_b_name}-user"
      quota = {
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
      limit_range = {
        default_cpu     = "200m"
        default_memory  = "256Mi"
        request_cpu     = "100m"
        request_memory  = "128Mi"
      }
    }
  }
}

# Trust policy document for tenant IAM roles
data "aws_iam_policy_document" "tenant_trust_policy" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

# IAM roles for tenant access
resource "aws_iam_role" "tenant_roles" {
  for_each = local.tenants

  name               = "${each.value.name}-eks-role"
  assume_role_policy = data.aws_iam_policy_document.tenant_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name   = "${each.value.name}-eks-role"
    Tenant = each.key
  })
}

# Kubernetes namespaces for tenants
resource "kubernetes_namespace" "tenant_namespaces" {
  for_each = local.tenants

  metadata {
    name = each.value.name
    labels = each.value.labels
  }
}

# RBAC roles for tenant access within their namespaces
resource "kubernetes_role" "tenant_roles" {
  for_each = local.tenants

  metadata {
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
    name      = "${each.value.name}-role"
  }

  # Core API group permissions
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Apps API group permissions
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "daemonsets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Networking API group permissions
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

# RBAC role bindings for tenant users
resource "kubernetes_role_binding" "tenant_bindings" {
  for_each = local.tenants

  metadata {
    name      = "${each.value.name}-binding"
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.tenant_roles[each.key].metadata[0].name
  }

  subject {
    kind      = "User"
    name      = each.value.rbac_username
    api_group = "rbac.authorization.k8s.io"
  }
}

# EKS access entries for IAM to RBAC mapping
resource "aws_eks_access_entry" "tenant_access_entries" {
  for_each = local.tenants

  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.tenant_roles[each.key].arn
  kubernetes_groups = []
  type             = "STANDARD"
  user_name        = each.value.rbac_username

  tags = merge(local.common_tags, {
    Name   = "${each.value.name}-access-entry"
    Tenant = each.key
  })
}

# Network policies for tenant isolation
resource "kubernetes_network_policy" "tenant_isolation" {
  for_each = local.tenants

  metadata {
    name      = "${each.value.name}-isolation"
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]

    # Ingress rules - allow traffic from same tenant and kube-system
    ingress {
      from {
        namespace_selector {
          match_labels = {
            tenant = each.value.labels.tenant
          }
        }
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
    }

    # Egress rules - allow traffic to same tenant and kube-system
    egress {
      to {
        namespace_selector {
          match_labels = {
            tenant = each.value.labels.tenant
          }
        }
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
    }

    # Allow DNS resolution
    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }

    egress {
      to {}
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }
  }
}

# Resource quotas for tenant namespaces
resource "kubernetes_resource_quota" "tenant_quotas" {
  for_each = local.tenants

  metadata {
    name      = "${each.value.name}-quota"
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"                = each.value.quota.cpu_requests
      "requests.memory"             = each.value.quota.memory_requests
      "limits.cpu"                  = each.value.quota.cpu_limits
      "limits.memory"               = each.value.quota.memory_limits
      "pods"                        = each.value.quota.pods
      "services"                    = each.value.quota.services
      "secrets"                     = each.value.quota.secrets
      "configmaps"                  = each.value.quota.configmaps
      "persistentvolumeclaims"      = each.value.quota.pvcs
    }
  }
}

# Limit ranges for tenant namespaces
resource "kubernetes_limit_range" "tenant_limits" {
  for_each = local.tenants

  metadata {
    name      = "${each.value.name}-limits"
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = each.value.limit_range.default_cpu
        memory = each.value.limit_range.default_memory
      }
      default_request = {
        cpu    = each.value.limit_range.request_cpu
        memory = each.value.limit_range.request_memory
      }
    }
  }
}

# Optional: Sample applications for testing tenant isolation
resource "kubernetes_deployment" "sample_apps" {
  for_each = var.deploy_sample_apps ? local.tenants : {}

  metadata {
    name      = "${each.value.name}-app"
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
    labels = {
      app = "${each.value.name}-app"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "${each.value.name}-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "${each.value.name}-app"
        }
      }

      spec {
        container {
          image = each.key == "alpha" ? "nginx:1.20" : "httpd:2.4"
          name  = "app"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu    = each.value.limit_range.default_cpu
              memory = each.value.limit_range.default_memory
            }
            requests = {
              cpu    = each.value.limit_range.request_cpu
              memory = each.value.limit_range.request_memory
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_resource_quota.tenant_quotas,
    kubernetes_limit_range.tenant_limits
  ]
}

# Optional: Sample services for testing tenant isolation
resource "kubernetes_service" "sample_services" {
  for_each = var.deploy_sample_apps ? local.tenants : {}

  metadata {
    name      = "${each.value.name}-service"
    namespace = kubernetes_namespace.tenant_namespaces[each.key].metadata[0].name
  }

  spec {
    selector = {
      app = "${each.value.name}-app"
    }

    port {
      port        = 80
      target_port = 80
    }
  }

  depends_on = [kubernetes_deployment.sample_apps]
}