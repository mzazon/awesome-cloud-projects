# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = substr(random_id.suffix.hex, 0, 6)
  cluster_name    = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-cluster-${local.resource_suffix}"
  
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# Data sources for existing cluster (if not creating new one)
data "aws_eks_cluster" "cluster" {
  name       = var.create_eks_cluster ? module.eks[0].cluster_name : local.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name       = data.aws_eks_cluster.cluster.name
  depends_on = [module.eks]
}

data "aws_caller_identity" "current" {}

# VPC module for EKS cluster (only if creating new cluster and no VPC provided)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  count = var.create_eks_cluster && var.vpc_id == "" ? 1 : 0

  name = "${var.project_name}-vpc-${local.resource_suffix}"
  cidr = var.vpc_cidr

  azs = length(var.availability_zones) > 0 ? var.availability_zones : [
    "${var.aws_region}a",
    "${var.aws_region}b",
    "${var.aws_region}c"
  ]

  private_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 1),
    cidrsubnet(var.vpc_cidr, 8, 2),
    cidrsubnet(var.vpc_cidr, 8, 3)
  ]

  public_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 101),
    cidrsubnet(var.vpc_cidr, 8, 102),
    cidrsubnet(var.vpc_cidr, 8, 103)
  ]

  enable_nat_gateway     = true
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
  single_nat_gateway     = var.environment == "dev" ? true : false
  one_nat_gateway_per_az = var.environment != "dev" ? true : false

  # Tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.common_tags
}

# EKS cluster module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  count = var.create_eks_cluster ? 1 : 0

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # VPC configuration
  vpc_id = var.vpc_id != "" ? var.vpc_id : module.vpc[0].vpc_id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : concat(
    module.vpc[0].private_subnets,
    module.vpc[0].public_subnets
  )

  # Control plane logging
  cluster_enabled_log_types = var.enable_logging ? [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
  ] : []

  # OIDC provider for IRSA
  enable_irsa = var.enable_irsa

  # Cluster access configuration
  cluster_endpoint_public_access       = true
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]

  # EKS managed node groups
  eks_managed_node_groups = {
    operators_nodegroup = {
      name = "${local.cluster_name}-operators-ng"

      instance_types = var.node_group_config.instance_types
      capacity_type  = var.node_group_config.capacity_type

      min_size     = var.node_group_config.min_size
      max_size     = var.node_group_config.max_size
      desired_size = var.node_group_config.desired_size

      disk_size = var.node_group_config.disk_size
      disk_type = "gp3"

      # Node group configuration
      ami_type       = "AL2_x86_64"
      platform       = "linux"
      
      # Allow pods to be scheduled on all nodes
      taints = {}
      
      # Labels for node selection
      labels = {
        role = "operators"
      }

      # Additional security groups
      vpc_security_group_ids = [aws_security_group.additional_sg.id]

      tags = merge(local.common_tags, {
        "Name" = "${local.cluster_name}-operators-ng"
      })
    }
  }

  # Cluster security groups
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = local.common_tags
}

# Additional security group for operator workloads
resource "aws_security_group" "additional_sg" {
  name_prefix = "${var.project_name}-operators-sg"
  vpc_id      = var.create_eks_cluster ? (var.vpc_id != "" ? var.vpc_id : module.vpc[0].vpc_id) : var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Webhook admission controllers"
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Metrics endpoint"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-operators-sg"
  })
}

# CloudWatch log group for EKS cluster logs
resource "aws_cloudwatch_log_group" "cluster_logs" {
  count = var.create_eks_cluster && var.enable_logging ? 1 : 0

  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id       = aws_kms_key.cluster_logs[0].arn

  tags = local.common_tags
}

# KMS key for encrypting EKS cluster logs
resource "aws_kms_key" "cluster_logs" {
  count = var.create_eks_cluster && var.enable_logging ? 1 : 0

  description             = "KMS key for EKS cluster logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cluster-logs-key"
  })
}

resource "aws_kms_alias" "cluster_logs" {
  count = var.create_eks_cluster && var.enable_logging ? 1 : 0

  name          = "alias/${var.project_name}-cluster-logs-${local.resource_suffix}"
  target_key_id = aws_kms_key.cluster_logs[0].key_id
}

# IAM role for ACK controllers
resource "aws_iam_role" "ack_controller_role" {
  name = "ACK-Controller-Role-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.create_eks_cluster ? module.eks[0].oidc_provider_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:${var.ack_system_namespace}:ack-controller"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policies for ACK controllers
resource "aws_iam_role_policy" "ack_s3_policy" {
  count = var.ack_controllers.s3.enabled ? 1 : 0
  name  = "ACK-S3-Policy"
  role  = aws_iam_role.ack_controller_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketNotification",
          "s3:ListBucket",
          "s3:PutBucketNotification",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketEncryption",
          "s3:PutBucketEncryption",
          "s3:GetBucketLogging",
          "s3:PutBucketLogging",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy"
        ]
        Resource = [
          "arn:aws:s3:::*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ack_iam_policy" {
  count = var.ack_controllers.iam.enabled ? 1 : 0
  name  = "ACK-IAM-Policy"
  role  = aws_iam_role.ack_controller_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:ListRoles",
          "iam:UpdateRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:ListPolicies",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ack_lambda_policy" {
  count = var.ack_controllers.lambda.enabled ? 1 : 0
  name  = "ACK-Lambda-Policy"
  role  = aws_iam_role.ack_controller_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:ListFunctions",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:GetPolicy",
          "lambda:CreateAlias",
          "lambda:DeleteAlias",
          "lambda:GetAlias",
          "lambda:UpdateAlias"
        ]
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:*"
        ]
      }
    ]
  })
}

# Create ACK system namespace
resource "kubernetes_namespace" "ack_system" {
  metadata {
    name = var.ack_system_namespace
    labels = {
      name = var.ack_system_namespace
    }
  }

  depends_on = [data.aws_eks_cluster.cluster]
}

# Install ACK runtime CRDs
resource "kubectl_manifest" "ack_adoptedresources_crd" {
  yaml_body = <<YAML
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: adoptedresources.services.k8s.aws
spec:
  group: services.k8s.aws
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
          status:
            type: object
  scope: Namespaced
  names:
    plural: adoptedresources
    singular: adoptedresource
    kind: AdoptedResource
YAML

  depends_on = [kubernetes_namespace.ack_system]
}

resource "kubectl_manifest" "ack_fieldexports_crd" {
  yaml_body = <<YAML
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: fieldexports.services.k8s.aws
spec:
  group: services.k8s.aws
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
          status:
            type: object
  scope: Namespaced
  names:
    plural: fieldexports
    singular: fieldexport
    kind: FieldExport
YAML

  depends_on = [kubernetes_namespace.ack_system]
}

# Install ACK S3 controller
resource "helm_release" "ack_s3_controller" {
  count = var.ack_controllers.s3.enabled ? 1 : 0

  name       = "ack-s3-controller"
  repository = "oci://public.ecr.aws/aws-controllers-k8s"
  chart      = var.ack_controllers.s3.chart_name
  version    = var.ack_controllers.s3.version
  namespace  = var.ack_controllers.s3.namespace

  values = [
    yamlencode({
      aws = {
        region = var.aws_region
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.ack_controller_role.arn
        }
      }
      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.ack_system,
    kubectl_manifest.ack_adoptedresources_crd,
    kubectl_manifest.ack_fieldexports_crd
  ]
}

# Install ACK IAM controller
resource "helm_release" "ack_iam_controller" {
  count = var.ack_controllers.iam.enabled ? 1 : 0

  name       = "ack-iam-controller"
  repository = "oci://public.ecr.aws/aws-controllers-k8s"
  chart      = var.ack_controllers.iam.chart_name
  version    = var.ack_controllers.iam.version
  namespace  = var.ack_controllers.iam.namespace

  values = [
    yamlencode({
      aws = {
        region = var.aws_region
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.ack_controller_role.arn
        }
      }
      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.ack_system,
    kubectl_manifest.ack_adoptedresources_crd,
    kubectl_manifest.ack_fieldexports_crd
  ]
}

# Install ACK Lambda controller
resource "helm_release" "ack_lambda_controller" {
  count = var.ack_controllers.lambda.enabled ? 1 : 0

  name       = "ack-lambda-controller"
  repository = "oci://public.ecr.aws/aws-controllers-k8s"
  chart      = var.ack_controllers.lambda.chart_name
  version    = var.ack_controllers.lambda.version
  namespace  = var.ack_controllers.lambda.namespace

  values = [
    yamlencode({
      aws = {
        region = var.aws_region
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.ack_controller_role.arn
        }
      }
      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.ack_system,
    kubectl_manifest.ack_adoptedresources_crd,
    kubectl_manifest.ack_fieldexports_crd
  ]
}

# Custom Application CRD
resource "kubectl_manifest" "application_crd" {
  yaml_body = <<YAML
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: applications.platform.example.com
spec:
  group: platform.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name:
                type: string
              environment:
                type: string
                enum: ["dev", "staging", "prod"]
              storageClass:
                type: string
                default: "STANDARD"
              lambdaRuntime:
                type: string
                default: "python3.9"
              enableLogging:
                type: boolean
                default: true
          status:
            type: object
            properties:
              phase:
                type: string
              bucketName:
                type: string
              roleArn:
                type: string
              functionName:
                type: string
              message:
                type: string
  scope: Namespaced
  names:
    plural: applications
    singular: application
    kind: Application
YAML

  depends_on = [data.aws_eks_cluster.cluster]
}

# Custom operator namespace
resource "kubernetes_namespace" "operator_namespace" {
  metadata {
    name = var.operator_namespace
    labels = {
      name = var.operator_namespace
    }
  }

  depends_on = [data.aws_eks_cluster.cluster]
}

# RBAC for custom operator
resource "kubernetes_cluster_role" "platform_operator_manager" {
  metadata {
    name = "platform-operator-manager"
  }

  rule {
    api_groups = ["platform.example.com"]
    resources  = ["applications"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["s3.services.k8s.aws"]
    resources  = ["buckets"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["iam.services.k8s.aws"]
    resources  = ["roles"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = ["lambda.services.k8s.aws"]
    resources  = ["functions"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  depends_on = [kubernetes_namespace.operator_namespace]
}

resource "kubernetes_service_account" "platform_operator_controller_manager" {
  metadata {
    name      = "platform-operator-controller-manager"
    namespace = var.operator_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.ack_controller_role.arn
    }
  }

  depends_on = [kubernetes_namespace.operator_namespace]
}

resource "kubernetes_cluster_role_binding" "platform_operator_manager" {
  metadata {
    name = "platform-operator-manager"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.platform_operator_manager.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.platform_operator_controller_manager.metadata[0].name
    namespace = var.operator_namespace
  }

  depends_on = [
    kubernetes_cluster_role.platform_operator_manager,
    kubernetes_service_account.platform_operator_controller_manager
  ]
}

# Network policy for operator security
resource "kubernetes_network_policy" "platform_operator_network_policy" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "platform-operator-network-policy"
    namespace = var.operator_namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = "platform-operator"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
    }

    egress {
      to {}
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
  }

  depends_on = [kubernetes_namespace.operator_namespace]
}

# Metrics service for operator monitoring
resource "kubernetes_service" "platform_operator_metrics" {
  count = var.enable_monitoring ? 1 : 0

  metadata {
    name      = "platform-operator-metrics"
    namespace = var.operator_namespace
    labels = {
      app = "platform-operator"
    }
  }

  spec {
    selector = {
      app = "platform-operator"
    }

    port {
      name        = "metrics"
      port        = 8080
      target_port = 8080
    }
  }

  depends_on = [kubernetes_namespace.operator_namespace]
}

# Sample application for testing (optional)
resource "kubectl_manifest" "sample_application" {
  count = var.deploy_sample_application ? 1 : 0

  yaml_body = <<YAML
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: ${var.sample_app_config.name}
  namespace: default
spec:
  name: ${var.sample_app_config.name}
  environment: ${var.sample_app_config.environment}
  storageClass: ${var.sample_app_config.storage_class}
  lambdaRuntime: ${var.sample_app_config.lambda_runtime}
  enableLogging: ${var.sample_app_config.enable_logging}
YAML

  depends_on = [
    kubectl_manifest.application_crd,
    helm_release.ack_s3_controller,
    helm_release.ack_iam_controller,
    helm_release.ack_lambda_controller,
    kubernetes_cluster_role_binding.platform_operator_manager
  ]
}