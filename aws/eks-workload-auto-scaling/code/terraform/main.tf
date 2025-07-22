# Main Terraform configuration for EKS Auto Scaling Infrastructure

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values for resource naming and configuration
locals {
  cluster_name = "${var.cluster_name}-${random_id.suffix.hex}"
  
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Recipe      = "auto-scaling-eks-workloads"
  }
  
  # Cluster Autoscaler tags for node groups
  cluster_autoscaler_tags = {
    "k8s.io/cluster-autoscaler/enabled"     = "true"
    "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
  }
}

# VPC Configuration using the official AWS VPC module
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  tags = local.common_tags
}

# EKS Cluster using the official AWS EKS module
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Cluster endpoint configuration
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    # General purpose node group
    general_purpose = {
      name = var.general_purpose_node_group.name
      
      instance_types = var.general_purpose_node_group.instance_types
      capacity_type  = var.general_purpose_node_group.capacity_type
      ami_type       = var.general_purpose_node_group.ami_type
      
      min_size     = var.general_purpose_node_group.min_size
      max_size     = var.general_purpose_node_group.max_size
      desired_size = var.general_purpose_node_group.desired_size
      
      disk_size = var.general_purpose_node_group.disk_size
      
      labels = var.general_purpose_node_group.labels
      
      # Cluster Autoscaler tags
      tags = merge(local.common_tags, local.cluster_autoscaler_tags)
    }
    
    # Compute optimized node group
    compute_optimized = {
      name = var.compute_optimized_node_group.name
      
      instance_types = var.compute_optimized_node_group.instance_types
      capacity_type  = var.compute_optimized_node_group.capacity_type
      ami_type       = var.compute_optimized_node_group.ami_type
      
      min_size     = var.compute_optimized_node_group.min_size
      max_size     = var.compute_optimized_node_group.max_size
      desired_size = var.compute_optimized_node_group.desired_size
      
      disk_size = var.compute_optimized_node_group.disk_size
      
      labels = var.compute_optimized_node_group.labels
      
      # Cluster Autoscaler tags
      tags = merge(local.common_tags, local.cluster_autoscaler_tags)
    }
  }

  # EKS Addons
  cluster_addons = {
    for addon, config in var.eks_addons : addon => {
      most_recent = config.version == null ? true : false
      addon_version = config.version
      resolve_conflicts = config.resolve_conflicts
      service_account_role_arn = config.service_account_role_arn
    }
  }

  # OIDC Identity provider configuration
  cluster_identity_providers = {
    sts = {
      client_id = "sts.amazonaws.com"
    }
  }

  tags = local.common_tags
}

# IAM Role for Cluster Autoscaler
resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.cluster_name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for Cluster Autoscaler
resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${local.cluster_name}-cluster-autoscaler"
  description = "Policy for Cluster Autoscaler"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "cluster_autoscaler" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = aws_iam_policy.cluster_autoscaler.arn
}

# Kubernetes Service Account for Cluster Autoscaler
resource "kubernetes_service_account" "cluster_autoscaler" {
  depends_on = [module.eks]
  
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
}

# Cluster Autoscaler Deployment
resource "kubectl_manifest" "cluster_autoscaler" {
  depends_on = [
    module.eks,
    kubernetes_service_account.cluster_autoscaler
  ]
  
  yaml_body = templatefile("${path.module}/cluster-autoscaler.yaml", {
    cluster_name = local.cluster_name
    image_tag    = var.cluster_autoscaler_image_tag
    settings     = var.cluster_autoscaler_settings
  })
}

# Metrics Server using Helm
resource "helm_release" "metrics_server" {
  depends_on = [module.eks]
  
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  set {
    name  = "resources.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.limits.memory"
    value = "300Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "300Mi"
  }
}

# KEDA Installation
resource "helm_release" "keda" {
  count = var.enable_keda ? 1 : 0
  
  depends_on = [module.eks]
  
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  namespace  = var.keda_namespace
  version    = "2.12.0"
  
  create_namespace = true

  set {
    name  = "prometheus.metricServer.enabled"
    value = "true"
  }

  set {
    name  = "prometheus.operator.enabled"
    value = "true"
  }

  set {
    name  = "resources.operator.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.operator.limits.memory"
    value = "128Mi"
  }

  set {
    name  = "resources.metricServer.limits.cpu"
    value = "100m"
  }

  set {
    name  = "resources.metricServer.limits.memory"
    value = "128Mi"
  }
}

# Prometheus monitoring stack
resource "helm_release" "prometheus" {
  count = var.enable_prometheus ? 1 : 0
  
  depends_on = [module.eks]
  
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = "monitoring"
  version    = "25.0.0"
  
  create_namespace = true

  set {
    name  = "server.persistentVolume.size"
    value = var.prometheus_storage_size
  }

  set {
    name  = "server.retention"
    value = var.prometheus_retention
  }

  set {
    name  = "alertmanager.persistentVolume.size"
    value = "10Gi"
  }

  set {
    name  = "pushgateway.enabled"
    value = "false"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "1Gi"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "512Mi"
  }
}

# Grafana for visualization
resource "helm_release" "grafana" {
  count = var.enable_grafana ? 1 : 0
  
  depends_on = [module.eks]
  
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = "monitoring"
  version    = "7.0.0"
  
  create_namespace = true

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = var.grafana_storage_size
  }

  set {
    name  = "adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }
}

# Demo applications namespace
resource "kubernetes_namespace" "demo_apps" {
  count = var.deploy_demo_applications ? 1 : 0
  
  depends_on = [module.eks]
  
  metadata {
    name = var.demo_namespace
  }
}

# Demo applications deployment
resource "kubectl_manifest" "demo_applications" {
  count = var.deploy_demo_applications ? 1 : 0
  
  depends_on = [
    module.eks,
    kubernetes_namespace.demo_apps[0],
    helm_release.metrics_server
  ]
  
  yaml_body = templatefile("${path.module}/demo-applications.yaml", {
    namespace = var.demo_namespace
  })
}

# VPA Installation (Optional)
resource "kubectl_manifest" "vpa" {
  count = var.enable_vpa ? 1 : 0
  
  depends_on = [module.eks]
  
  yaml_body = file("${path.module}/vpa-installation.yaml")
}

# Pod Disruption Budgets
resource "kubectl_manifest" "pod_disruption_budgets" {
  count = var.deploy_demo_applications ? 1 : 0
  
  depends_on = [
    module.eks,
    kubectl_manifest.demo_applications[0]
  ]
  
  yaml_body = templatefile("${path.module}/pod-disruption-budgets.yaml", {
    namespace = var.demo_namespace
  })
}