# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# LOCAL VALUES AND COMPUTED VARIABLES
# ==============================================================================

locals {
  # Cluster naming
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Availability zones - use provided or first 3 from region
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Common tags
  common_tags = merge(
    var.additional_tags,
    {
      Environment     = var.environment
      Project         = var.project_name
      ClusterName     = local.cluster_name
      ManagedBy       = "Terraform"
      HybridMonitoring = "enabled"
    }
  )

  # CloudWatch namespace
  cloudwatch_namespace = var.custom_metrics_namespace
}

# ==============================================================================
# VPC AND NETWORKING INFRASTRUCTURE
# ==============================================================================

# Create VPC for EKS cluster
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-igw"
  })
}

# Public subnets for EKS control plane and Load Balancers
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-public-subnet-${count.index + 1}"
    Type = "Public"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  })
}

# Private subnets for Fargate workloads
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-private-subnet-${count.index + 1}"
    Type = "Private"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb"             = "1"
  })
}

# Elastic IP for NAT Gateway(s)
resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : length(var.private_subnet_cidrs)

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway(s) for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : length(var.private_subnet_cidrs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-public-rt"
    Type = "Public"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : length(var.private_subnet_cidrs)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-private-rt-${count.index + 1}"
    Type = "Private"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# ==============================================================================
# KMS KEY FOR CLUSTER ENCRYPTION
# ==============================================================================

resource "aws_kms_key" "cluster" {
  count = var.cluster_encryption_enabled ? 1 : 0

  description             = "KMS key for EKS cluster ${local.cluster_name} encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-encryption-key"
  })
}

resource "aws_kms_alias" "cluster" {
  count = var.cluster_encryption_enabled ? 1 : 0

  name          = "alias/${local.cluster_name}-encryption"
  target_key_id = aws_kms_key.cluster[0].key_id
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# EKS Cluster Service Role
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# Fargate Pod Execution Role
data "aws_iam_policy_document" "fargate_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "fargate" {
  name               = "${local.cluster_name}-fargate-role"
  assume_role_policy = data.aws_iam_policy_document.fargate_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-fargate-role"
  })
}

resource "aws_iam_role_policy_attachment" "fargate_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate.name
}

# ==============================================================================
# CLOUDWATCH LOGS
# ==============================================================================

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cluster_log_retention_days
  kms_key_id        = var.cluster_encryption_enabled ? aws_kms_key.cluster[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-cluster-logs"
  })
}

# ==============================================================================
# EKS CLUSTER
# ==============================================================================

resource "aws_eks_cluster" "hybrid_monitoring" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  # Access configuration for modern EKS authentication
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  # VPC configuration
  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = var.additional_security_group_ids
  }

  # Remote network configuration for hybrid nodes
  remote_network_config {
    remote_node_networks {
      cidrs = var.remote_node_networks
    }
    
    remote_pod_networks {
      cidrs = var.remote_pod_networks
    }
  }

  # Cluster encryption configuration
  dynamic "encryption_config" {
    for_each = var.cluster_encryption_enabled ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.cluster[0].arn
      }
      resources = ["secrets"]
    }
  }

  # Control plane logging
  enabled_cluster_log_types = var.cluster_enabled_log_types

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ==============================================================================
# OIDC IDENTITY PROVIDER
# ==============================================================================

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.hybrid_monitoring.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.hybrid_monitoring.identity[0].oidc[0].issuer

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-oidc-provider"
  })
}

# ==============================================================================
# FARGATE PROFILE
# ==============================================================================

resource "aws_eks_fargate_profile" "cloud_workloads" {
  cluster_name           = aws_eks_cluster.hybrid_monitoring.name
  fargate_profile_name   = var.fargate_profile_name
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = aws_subnet.private[*].id

  dynamic "selector" {
    for_each = var.fargate_namespace_selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-${var.fargate_profile_name}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.fargate_policy,
  ]
}

# ==============================================================================
# CLOUDWATCH OBSERVABILITY ADDON CONFIGURATION
# ==============================================================================

# IAM role for CloudWatch Observability addon
data "aws_iam_policy_document" "cloudwatch_observability_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudwatch_observability" {
  name               = "${local.cluster_name}-cloudwatch-observability-role"
  assume_role_policy = data.aws_iam_policy_document.cloudwatch_observability_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-cloudwatch-observability-role"
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability.name
}

# Additional permissions for Container Insights
resource "aws_iam_role_policy_attachment" "cloudwatch_observability_container_insights" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability.name
}

# CloudWatch Observability addon
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = aws_eks_cluster.hybrid_monitoring.name
  addon_name               = "amazon-cloudwatch-observability"
  addon_version            = var.cloudwatch_addon_version
  service_account_role_arn = aws_iam_role.cloudwatch_observability.arn
  
  configuration_values = jsonencode({
    containerInsights = {
      enabled = var.container_insights_enabled
    }
    applicationSignals = {
      enabled = var.application_signals_enabled
    }
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-cloudwatch-observability"
  })

  depends_on = [
    aws_eks_fargate_profile.cloud_workloads,
    aws_iam_role_policy_attachment.cloudwatch_observability,
  ]
}

# ==============================================================================
# ADDITIONAL EKS ADDONS
# ==============================================================================

# CoreDNS addon for DNS resolution
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.hybrid_monitoring.name
  addon_name   = "coredns"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-coredns"
  })

  depends_on = [aws_eks_fargate_profile.cloud_workloads]
}

# kube-proxy addon for networking
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.hybrid_monitoring.name
  addon_name   = "kube-proxy"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-kube-proxy"
  })
}

# VPC CNI addon for pod networking
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.hybrid_monitoring.name
  addon_name   = "vpc-cni"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc-cni"
  })
}

# EBS CSI driver addon (optional)
resource "aws_eks_addon" "ebs_csi" {
  count = var.install_ebs_csi_driver ? 1 : 0

  cluster_name = aws_eks_cluster.hybrid_monitoring.name
  addon_name   = "aws-ebs-csi-driver"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-ebs-csi"
  })
}

# EFS CSI driver addon (optional)
resource "aws_eks_addon" "efs_csi" {
  count = var.install_efs_csi_driver ? 1 : 0

  cluster_name = aws_eks_cluster.hybrid_monitoring.name
  addon_name   = "aws-efs-csi-driver"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-efs-csi"
  })
}

# ==============================================================================
# SAMPLE APPLICATIONS FOR TESTING (OPTIONAL)
# ==============================================================================

# Create namespace for cloud applications
resource "kubernetes_namespace" "cloud_apps" {
  count = var.deploy_sample_applications ? 1 : 0

  metadata {
    name = "cloud-apps"
    labels = {
      "monitoring" = "enabled"
      "environment" = var.environment
    }
  }

  depends_on = [aws_eks_addon.cloudwatch_observability]
}

# Sample application deployment on Fargate
resource "kubernetes_deployment" "sample_app" {
  count = var.deploy_sample_applications ? 1 : 0

  metadata {
    name      = "cloud-sample-app"
    namespace = kubernetes_namespace.cloud_apps[0].metadata[0].name
    labels = {
      app = "cloud-sample-app"
    }
  }

  spec {
    replicas = var.sample_app_replicas

    selector {
      match_labels = {
        app = "cloud-sample-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloud-sample-app"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "80"
        }
      }

      spec {
        container {
          name  = "sample-app"
          image = "public.ecr.aws/docker/library/nginx:latest"

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          env {
            name  = "ENVIRONMENT"
            value = "fargate"
          }

          env {
            name  = "CLUSTER_NAME"
            value = local.cluster_name
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_fargate_profile.cloud_workloads,
    kubernetes_namespace.cloud_apps
  ]
}

# Service for sample application
resource "kubernetes_service" "sample_app" {
  count = var.deploy_sample_applications ? 1 : 0

  metadata {
    name      = "cloud-sample-service"
    namespace = kubernetes_namespace.cloud_apps[0].metadata[0].name
  }

  spec {
    selector = {
      app = "cloud-sample-app"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.sample_app]
}