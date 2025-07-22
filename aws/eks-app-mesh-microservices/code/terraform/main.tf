# Data sources for account information and availability zones
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name = "${var.project_name}-${random_id.suffix.hex}"
  
  # Calculate traffic weights ensuring they sum to 100
  primary_weight = var.enable_canary_deployment ? var.primary_traffic_percentage : 100
  canary_weight  = var.enable_canary_deployment ? var.canary_traffic_percentage : 0
  
  # Common tags
  tags = merge(var.default_tags, {
    Name = local.name
  })
}

################################################################################
# VPC and Networking
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable VPC Flow Logs for security monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # Tags required for EKS and ALB discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "kubernetes.io/cluster/${local.name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/cluster/${local.name}" = "shared"
  }

  tags = local.tags
}

################################################################################
# ECR Repositories for Container Images
################################################################################

resource "aws_ecr_repository" "app_repos" {
  for_each = var.create_ecr_repositories ? toset(var.ecr_repositories) : []

  name                 = "${local.name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy {
    policy = jsonencode({
      rules = [
        {
          rulePriority = 1
          description  = "Keep last 30 images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = ["v"]
            countType     = "imageCountMoreThan"
            countNumber   = 30
          }
          action = {
            type = "expire"
          }
        }
      ]
    })
  }

  tags = local.tags
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name                   = local.name
  cluster_version                = var.cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = var.enable_irsa

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Enable cluster logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    standard_workers = {
      name           = "standard-workers"
      instance_types = var.node_group_instance_types
      
      min_size     = var.node_group_min_capacity
      max_size     = var.node_group_max_capacity
      desired_size = var.node_group_desired_capacity

      disk_size = var.node_group_disk_size
      disk_type = "gp3"

      # Use the latest EKS optimized AMI
      ami_type = "AL2_x86_64"

      # Enable Systems Manager for node management
      enable_bootstrap_user_data = true
      bootstrap_extra_args      = "--enable-docker-bridge true"

      # Node group scaling configuration
      update_config = {
        max_unavailable_percentage = 25
      }

      # Additional security groups
      vpc_security_group_ids = [aws_security_group.node_group_additional.id]

      tags = local.tags
    }
  }

  # Configure aws-auth ConfigMap
  manage_aws_auth_configmap = true
  aws_auth_roles = []
  aws_auth_users = []

  tags = local.tags
}

# Additional security group for node groups
resource "aws_security_group" "node_group_additional" {
  name_prefix = "${local.name}-node-additional-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "SSH access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.tags, {
    Name = "${local.name}-node-additional-sg"
  })
}

# IAM role for EBS CSI driver
module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.name}-ebs-csi-driver"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

################################################################################
# AWS App Mesh
################################################################################

# App Mesh service mesh
resource "aws_appmesh_mesh" "service_mesh" {
  name = "${local.name}-mesh"

  spec {
    egress_filter {
      type = "ALLOW_ALL"
    }
  }

  tags = local.tags
}

################################################################################
# IAM Roles for App Mesh
################################################################################

# IAM role for App Mesh Controller
module "appmesh_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-appmesh-controller"

  role_policy_arns = {
    appmesh_full_access    = "arn:aws:iam::aws:policy/AWSAppMeshFullAccess"
    cloudmap_full_access   = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["appmesh-system:appmesh-controller"]
    }
  }

  tags = local.tags
}

# IAM role for AWS Load Balancer Controller
module "load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.name}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

# IAM role for application pods (optional - for enhanced security)
module "app_pods_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name}-app-pods"

  role_policy_arns = {
    xray_daemon_write_access = var.enable_xray_tracing ? "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess" : null
  }

  oidc_providers = {
    ex = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "${var.app_namespace}:frontend-sa",
        "${var.app_namespace}:backend-sa",
        "${var.app_namespace}:database-sa"
      ]
    }
  }

  tags = local.tags
}

################################################################################
# Kubernetes Resources
################################################################################

# Application namespace
resource "kubernetes_namespace" "app_namespace" {
  depends_on = [module.eks]

  metadata {
    name = var.app_namespace

    labels = {
      "mesh"                                          = aws_appmesh_mesh.service_mesh.name
      "appmesh.k8s.aws/sidecarInjectorWebhook"      = "enabled"
      "app.kubernetes.io/name"                       = var.app_namespace
      "app.kubernetes.io/managed-by"                 = "terraform"
    }

    annotations = {
      "appmesh.k8s.aws/mesh" = aws_appmesh_mesh.service_mesh.name
    }
  }
}

# Service accounts for applications
resource "kubernetes_service_account" "app_service_accounts" {
  for_each = toset(["frontend", "backend", "database"])
  
  depends_on = [kubernetes_namespace.app_namespace]

  metadata {
    name      = "${each.key}-sa"
    namespace = var.app_namespace
    
    annotations = {
      "eks.amazonaws.com/role-arn" = module.app_pods_irsa_role.iam_role_arn
    }

    labels = {
      "app.kubernetes.io/name"       = each.key
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

################################################################################
# Helm Releases
################################################################################

# App Mesh Controller
resource "helm_release" "appmesh_controller" {
  depends_on = [
    module.eks,
    module.appmesh_controller_irsa_role
  ]

  name             = "appmesh-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "appmesh-controller"
  namespace        = "appmesh-system"
  create_namespace = true
  version          = "1.12.1"

  values = [
    yamlencode({
      region = var.aws_region
      serviceAccount = {
        create = false
        name   = "appmesh-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.appmesh_controller_irsa_role.iam_role_arn
        }
      }
      tracing = {
        enabled  = var.enable_xray_tracing
        provider = "x-ray"
      }
      log = {
        level = "info"
      }
      resources = {
        limits = {
          cpu    = "100m"
          memory = "64Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "64Mi"
        }
      }
    })
  ]

  timeout = 600
}

# AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  depends_on = [
    module.eks,
    module.load_balancer_controller_irsa_role
  ]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.1"

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      serviceAccount = {
        create = false
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.load_balancer_controller_irsa_role.iam_role_arn
        }
      }
      region = var.aws_region
      vpcId  = module.vpc.vpc_id
      resources = {
        limits = {
          cpu    = "200m"
          memory = "500Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
      }
    })
  ]

  timeout = 600
}

################################################################################
# CloudWatch Container Insights (Optional)
################################################################################

resource "helm_release" "cloudwatch_agent" {
  count = var.enable_container_insights ? 1 : 0

  depends_on = [module.eks]

  name       = "cloudwatch-agent"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-cloudwatch-metrics"
  namespace  = "amazon-cloudwatch"
  create_namespace = true

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      region      = var.aws_region
    })
  ]

  timeout = 300
}

# CloudWatch logging for containers
resource "helm_release" "fluent_bit" {
  count = var.enable_container_insights ? 1 : 0

  depends_on = [module.eks]

  name       = "fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  namespace  = "amazon-cloudwatch"
  create_namespace = true

  values = [
    yamlencode({
      cloudWatchLogs = {
        enabled = true
        region  = var.aws_region
        logGroup = "/aws/containerinsights/${module.eks.cluster_name}/application"
      }
      firehose = {
        enabled = false
      }
      kinesis = {
        enabled = false
      }
      elasticsearch = {
        enabled = false
      }
    })
  ]

  timeout = 300
}

################################################################################
# Wait for Controllers to be Ready
################################################################################

# Wait for App Mesh Controller to be ready
resource "null_resource" "wait_for_appmesh_controller" {
  depends_on = [helm_release.appmesh_controller]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
      kubectl wait --for=condition=available --timeout=300s deployment/appmesh-controller -n appmesh-system
    EOT
  }
}

# Wait for AWS Load Balancer Controller to be ready
resource "null_resource" "wait_for_alb_controller" {
  depends_on = [helm_release.aws_load_balancer_controller]

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
      kubectl wait --for=condition=available --timeout=300s deployment/aws-load-balancer-controller -n kube-system
    EOT
  }
}