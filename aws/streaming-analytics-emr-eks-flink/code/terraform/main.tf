# Real-time Streaming Analytics with EMR on EKS and Apache Flink
# This Terraform configuration deploys a complete streaming analytics platform

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

# Generate random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Common naming convention
  name_prefix = "${var.cluster_name}-${var.environment}"
  
  # Resource names with random suffix for global uniqueness
  bucket_name           = "emr-flink-analytics-${random_password.suffix.result}"
  trading_stream_name   = "trading-events-${random_password.suffix.result}"
  market_stream_name    = "market-data-${random_password.suffix.result}"
  virtual_cluster_name  = "flink-analytics-cluster"
  
  # Common tags
  common_tags = merge(var.tags, {
    Project     = "flink-streaming-analytics"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

#------------------------------------------------------------------------------
# VPC and Networking
#------------------------------------------------------------------------------

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in slice(data.aws_availability_zones.available.names, 0, 3) : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# EKS Cluster
#------------------------------------------------------------------------------

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # OIDC Identity provider for EMR on EKS
  enable_irsa = true

  # EKS Managed Node Group
  eks_managed_node_groups = {
    emr_flink_workers = {
      name = "emr-flink-workers"

      instance_types = var.node_group_instance_types
      ami_type       = "AL2_x86_64"
      
      min_size     = var.node_group_min_size
      max_size     = var.node_group_max_size
      desired_size = var.node_group_desired_size

      disk_size = var.node_group_disk_size

      # Enable private networking
      subnet_ids = module.vpc.private_subnets

      # Additional IAM policies for EMR on EKS
      iam_role_additional_policies = {
        AmazonS3FullAccess                = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        AmazonKinesisFullAccess          = "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
        CloudWatchAgentServerPolicy      = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      tags = merge(local.common_tags, {
        Environment = var.environment
        Project     = "flink-streaming"
      })
    }
  }

  # EKS Add-ons
  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# IAM Roles for EMR on EKS
#------------------------------------------------------------------------------

# EMR Containers Service Role
resource "aws_iam_role" "emr_containers_service_role" {
  name = "EMRContainersServiceRole-${random_password.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "emr-containers.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "emr_containers_service_role_policy" {
  role       = aws_iam_role.emr_containers_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEMRContainersServiceRolePolicy"
}

# EMR Job Execution Role with OIDC
resource "aws_iam_role" "emr_job_execution_role" {
  name = "EMRFlinkJobExecutionRole-${random_password.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.emr_namespace}:*"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach policies to job execution role
resource "aws_iam_role_policy_attachment" "emr_job_execution_s3" {
  role       = aws_iam_role.emr_job_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "emr_job_execution_kinesis" {
  role       = aws_iam_role.emr_job_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
}

resource "aws_iam_role_policy_attachment" "emr_job_execution_cloudwatch" {
  role       = aws_iam_role.emr_job_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

#------------------------------------------------------------------------------
# Kubernetes Namespace and ServiceAccount
#------------------------------------------------------------------------------

resource "kubernetes_namespace" "emr_namespace" {
  metadata {
    name = var.emr_namespace
    
    labels = {
      name        = var.emr_namespace
      environment = var.environment
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account" "flink_operator" {
  metadata {
    name      = "emr-containers-sa-flink-operator"
    namespace = kubernetes_namespace.emr_namespace.metadata[0].name
    
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.emr_job_execution_role.arn
    }
  }

  depends_on = [kubernetes_namespace.emr_namespace]
}

#------------------------------------------------------------------------------
# EMR Virtual Cluster
#------------------------------------------------------------------------------

resource "aws_emrcontainers_virtual_cluster" "flink_cluster" {
  name = local.virtual_cluster_name

  container_provider {
    id   = module.eks.cluster_name
    type = "EKS"

    info {
      eks_info {
        namespace = kubernetes_namespace.emr_namespace.metadata[0].name
      }
    }
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# S3 Bucket for Checkpoints and Results
#------------------------------------------------------------------------------

resource "aws_s3_bucket" "flink_storage" {
  bucket = local.bucket_name

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "flink_storage" {
  bucket = aws_s3_bucket.flink_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flink_storage" {
  bucket = aws_s3_bucket.flink_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flink_storage" {
  bucket = aws_s3_bucket.flink_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "flink_storage" {
  bucket = aws_s3_bucket.flink_storage.id

  rule {
    id     = "flink_checkpoint_lifecycle"
    status = "Enabled"

    filter {
      prefix = "checkpoints/"
    }

    transition {
      days          = var.s3_lifecycle_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_glacier_days
      storage_class = "GLACIER"
    }
  }
}

#------------------------------------------------------------------------------
# Kinesis Data Streams
#------------------------------------------------------------------------------

resource "aws_kinesis_stream" "trading_events" {
  name             = local.trading_stream_name
  shard_count      = var.trading_stream_shard_count
  retention_period = var.kinesis_retention_period

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = local.common_tags
}

resource "aws_kinesis_stream" "market_data" {
  name             = local.market_stream_name
  shard_count      = var.market_stream_shard_count
  retention_period = var.kinesis_retention_period

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# CloudWatch Log Groups
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flink_logs" {
  name              = "/aws/emr-containers/flink"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# Flink Kubernetes Operator via Helm
#------------------------------------------------------------------------------

resource "helm_release" "flink_operator" {
  name       = "flink-kubernetes-operator"
  repository = "https://downloads.apache.org/flink/flink-kubernetes-operator-1.7.0/"
  chart      = "flink-kubernetes-operator"
  version    = var.flink_operator_version
  namespace  = kubernetes_namespace.emr_namespace.metadata[0].name

  set {
    name  = "image.repository"
    value = "public.ecr.aws/emr-on-eks/flink/flink-kubernetes-operator"
  }

  set {
    name  = "image.tag"
    value = "${var.flink_operator_version}-emr-7.0.0"
  }

  depends_on = [
    kubernetes_namespace.emr_namespace,
    kubernetes_service_account.flink_operator
  ]
}

#------------------------------------------------------------------------------
# Monitoring Stack (Prometheus & Grafana)
#------------------------------------------------------------------------------

resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring ? 1 : 0
  
  metadata {
    name = "monitoring"
    
    labels = {
      name = "monitoring"
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "prometheus" {
  count = var.enable_monitoring ? 1 : 0
  
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring[0].metadata[0].name

  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  depends_on = [kubernetes_namespace.monitoring]
}

#------------------------------------------------------------------------------
# Flink Application Deployments
#------------------------------------------------------------------------------

# Fraud Detection Flink Application
resource "kubectl_manifest" "fraud_detection_app" {
  yaml_body = templatefile("${path.module}/templates/fraud-detection-job.yaml", {
    namespace          = kubernetes_namespace.emr_namespace.metadata[0].name
    flink_image_tag    = var.flink_image_tag
    bucket_name        = aws_s3_bucket.flink_storage.bucket
    aws_region         = var.aws_region
    trading_stream     = aws_kinesis_stream.trading_events.name
    service_account    = kubernetes_service_account.flink_operator.metadata[0].name
  })

  depends_on = [
    helm_release.flink_operator,
    aws_s3_bucket.flink_storage,
    aws_kinesis_stream.trading_events
  ]
}

# Risk Analytics Flink Application
resource "kubectl_manifest" "risk_analytics_app" {
  yaml_body = templatefile("${path.module}/templates/risk-analytics-job.yaml", {
    namespace        = kubernetes_namespace.emr_namespace.metadata[0].name
    flink_image_tag  = var.flink_image_tag
    bucket_name      = aws_s3_bucket.flink_storage.bucket
    aws_region       = var.aws_region
    market_stream    = aws_kinesis_stream.market_data.name
    service_account  = kubernetes_service_account.flink_operator.metadata[0].name
  })

  depends_on = [
    helm_release.flink_operator,
    aws_s3_bucket.flink_storage,
    aws_kinesis_stream.market_data
  ]
}

#------------------------------------------------------------------------------
# Data Generator for Testing
#------------------------------------------------------------------------------

resource "kubectl_manifest" "data_generator" {
  count = var.enable_data_generator ? 1 : 0
  
  yaml_body = templatefile("${path.module}/templates/data-generator.yaml", {
    namespace        = kubernetes_namespace.emr_namespace.metadata[0].name
    aws_region       = var.aws_region
    trading_stream   = aws_kinesis_stream.trading_events.name
  })

  depends_on = [
    kubernetes_namespace.emr_namespace,
    aws_kinesis_stream.trading_events
  ]
}

#------------------------------------------------------------------------------
# Service Monitor for Flink Metrics (if monitoring enabled)
#------------------------------------------------------------------------------

resource "kubectl_manifest" "flink_service_monitor" {
  count = var.enable_monitoring ? 1 : 0
  
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: flink-metrics
  namespace: ${kubernetes_namespace.monitoring[0].metadata[0].name}
  labels:
    app: flink
spec:
  selector:
    matchLabels:
      app: flink
  namespaceSelector:
    matchNames:
      - ${kubernetes_namespace.emr_namespace.metadata[0].name}
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
YAML

  depends_on = [
    helm_release.prometheus,
    kubernetes_namespace.emr_namespace
  ]
}