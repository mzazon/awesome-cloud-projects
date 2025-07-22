# Main Terraform configuration for GitOps workflow with EKS, ArgoCD, and CodeCommit
# This configuration creates a complete GitOps infrastructure for container deployments

# Data sources for AWS account information and availability zones
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  count   = var.create_random_suffix ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Generate unique names with optional random suffix
  suffix = var.create_random_suffix ? random_string.suffix[0].result : ""
  
  # Resource names with consistent naming convention
  cluster_name    = var.create_random_suffix ? "${var.project_name}-${var.environment}-${local.suffix}" : "${var.project_name}-${var.environment}"
  repository_name = var.codecommit_repository_name != "" ? var.codecommit_repository_name : "${local.cluster_name}-gitops-config"
  
  # Availability zones selection
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "gitops-workflows-eks-argocd-codecommit"
    },
    var.additional_tags
  )
}

# VPC Module for networking infrastructure
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # VPC Configuration
  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  # Availability zones and subnets
  azs             = local.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # Enable NAT Gateway for private subnet internet access
  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = false
  one_nat_gateway_per_az = true

  # Enable DNS support for EKS
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Public subnet configuration for load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  # Private subnet configuration for worker nodes
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }

  # Apply common tags
  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc"
  })
}

# CloudWatch Log Group for EKS cluster logs
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-eks-logs"
  })
}

# EKS Module for Kubernetes cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  # Cluster Configuration
  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  # VPC Configuration
  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  control_plane_subnet_ids       = module.vpc.private_subnets

  # Cluster endpoint configuration
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Cluster logging configuration
  cluster_enabled_log_types              = var.cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = var.cloudwatch_log_retention_days

  # Cluster addons configuration
  cluster_addons = {
    # Core DNS addon for cluster DNS resolution
    coredns = {
      most_recent = true
    }
    
    # Kube proxy addon for network connectivity
    kube-proxy = {
      most_recent = true
    }
    
    # VPC CNI addon for pod networking
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        env = {
          ENABLE_IPV4_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET            = "1"
        }
      })
    }
    
    # EBS CSI driver for persistent storage
    aws-ebs-csi-driver = var.enable_ebs_csi_driver ? {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role[0].iam_role_arn
    } : {}
    
    # EFS CSI driver for shared storage (optional)
    aws-efs-csi-driver = var.enable_efs_csi_driver ? {
      most_recent = true
    } : {}
  }

  # EKS managed node groups configuration
  eks_managed_node_groups = {
    # Primary node group for general workloads
    primary = {
      name           = "${local.cluster_name}-primary"
      description    = "Primary node group for GitOps workloads"
      
      # Instance configuration
      instance_types = var.node_group_instance_types
      capacity_type  = var.node_group_capacity_type
      
      # Scaling configuration
      min_size     = var.node_group_scaling_config.min_size
      max_size     = var.node_group_scaling_config.max_size
      desired_size = var.node_group_scaling_config.desired_size
      
      # Storage configuration
      disk_size = var.node_group_disk_size
      
      # Network configuration
      subnet_ids = module.vpc.private_subnets
      
      # Enable cluster autoscaler tags
      tags = var.enable_cluster_autoscaler ? merge(local.common_tags, {
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      }) : local.common_tags
      
      # Update configuration
      update_config = {
        max_unavailable_percentage = 25
      }
      
      # Launch template configuration
      launch_template_tags = local.common_tags
    }
  }

  # Node security group additional rules
  node_security_group_additional_rules = {
    # Allow nodes to communicate with each other
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    # Allow nodes to pull images from ECR
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

  # Apply common tags
  tags = local.common_tags
}

# IAM Role for EBS CSI Driver (when enabled)
module "ebs_csi_irsa_role" {
  count = var.enable_ebs_csi_driver ? 1 : 0
  
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

# IAM Role for AWS Load Balancer Controller
module "aws_load_balancer_controller_irsa_role" {
  count = var.install_aws_load_balancer_controller ? 1 : 0
  
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${local.cluster_name}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

# Kubernetes namespace for ArgoCD
resource "kubernetes_namespace" "argocd" {
  count = var.install_argocd ? 1 : 0

  metadata {
    name = var.argocd_namespace
    
    labels = {
      name                          = var.argocd_namespace
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }

  depends_on = [module.eks]
}

# Helm release for AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  count = var.install_aws_load_balancer_controller ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.aws_load_balancer_controller_version
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.aws_load_balancer_controller_irsa_role[0].iam_role_arn
  }

  depends_on = [
    module.eks,
    module.aws_load_balancer_controller_irsa_role
  ]
}

# Helm release for ArgoCD
resource "helm_release" "argocd" {
  count = var.install_argocd ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd[0].metadata[0].name

  # ArgoCD configuration values
  values = [
    yamlencode({
      # Global configuration
      global = {
        image = {
          repository = "quay.io/argoproj/argocd"
        }
      }
      
      # Server configuration
      server = {
        # Enable insecure mode for ALB integration
        extraArgs = [
          "--insecure"
        ]
        
        # Service configuration for ALB
        service = {
          type = "ClusterIP"
        }
        
        # Ingress configuration (basic setup, ALB annotations added separately)
        ingress = {
          enabled = false
        }
        
        # Resource limits for server
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      
      # Repository server configuration
      repoServer = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }
      
      # Application controller configuration
      controller = {
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }
      
      # Redis configuration for session storage
      redis = {
        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
      
      # Disable DEX for simplicity (can be enabled for advanced authentication)
      dex = {
        enabled = false
      }
      
      # Configuration for ArgoCD notifications (optional)
      notifications = {
        enabled = false
      }
    })
  ]

  depends_on = [
    module.eks,
    kubernetes_namespace.argocd,
    helm_release.aws_load_balancer_controller
  ]
}

# Kubernetes Ingress for ArgoCD Server
resource "kubernetes_ingress_v1" "argocd_server" {
  count = var.install_argocd ? 1 : 0

  metadata {
    name      = "argocd-server-ingress"
    namespace = kubernetes_namespace.argocd[0].metadata[0].name
    
    annotations = {
      # AWS Load Balancer Controller annotations
      "alb.ingress.kubernetes.io/scheme"       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"  = "ip"
      "alb.ingress.kubernetes.io/listen-ports" = jsonencode([
        { "HTTP" = 80 },
        { "HTTPS" = 443 }
      ])
      "alb.ingress.kubernetes.io/ssl-redirect" = "443"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
      
      # Tags for the ALB
      "alb.ingress.kubernetes.io/tags" = join(",", [
        for k, v in local.common_tags : "${k}=${v}"
      ])
    }
  }

  spec {
    ingress_class_name = "alb"
    
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    helm_release.aws_load_balancer_controller
  ]
}

# CodeCommit Repository for GitOps configuration
resource "aws_codecommit_repository" "gitops_config" {
  repository_name        = local.repository_name
  repository_description = var.codecommit_repository_description

  tags = merge(local.common_tags, {
    Name = local.repository_name
  })
}

# CloudWatch Log Group for ArgoCD (if additional logging is needed)
resource "aws_cloudwatch_log_group" "argocd" {
  count = var.install_argocd ? 1 : 0
  
  name              = "/aws/eks/${local.cluster_name}/argocd"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-argocd-logs"
  })
}