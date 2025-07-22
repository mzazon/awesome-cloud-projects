# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for AWS account and availability zones
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Use provided AZs or auto-detect
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Generate unique names
  cluster_name = "${var.cluster_name}-${random_id.suffix.hex}"
  mesh_name    = "${var.app_mesh_name}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# VPC for EKS cluster
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc-${random_id.suffix.hex}"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true

  # Enable VPC flow logs for security monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # Kubernetes-specific tags for subnets
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

# ECR repositories for microservices
resource "aws_ecr_repository" "microservices" {
  for_each = var.microservices

  name                 = "${var.ecr_repository_prefix}-${each.key}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  lifecycle_policy {
    policy = jsonencode({
      rules = [
        {
          rulePriority = 1
          description  = "Keep last 10 images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = ["v"]
            countType     = "imageCountMoreThan"
            countNumber   = 10
          }
          action = {
            type = "expire"
          }
        },
        {
          rulePriority = 2
          description  = "Delete untagged images older than 1 day"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = 1
          }
          action = {
            type = "expire"
          }
        }
      ]
    })
  }

  tags = local.common_tags
}

# EKS cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Enable encryption at rest
  cluster_encryption_config = var.enable_encryption_at_rest ? [
    {
      provider_key_arn = aws_kms_key.eks[0].arn
      resources        = ["secrets"]
    }
  ] : []

  # EKS add-ons
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
      most_recent = true
    }
  }

  # Managed node groups
  eks_managed_node_groups = {
    microservices_nodes = {
      name = "microservices-nodes"

      instance_types = var.node_group_instance_types
      
      min_size     = var.node_group_capacity.min_size
      max_size     = var.node_group_capacity.max_size
      desired_size = var.node_group_capacity.desired_size

      disk_size = var.node_group_disk_size

      # IAM policies for App Mesh, CloudWatch, and ECR
      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        AWSAppMeshEnvoyAccess      = "arn:aws:iam::aws:policy/AWSAppMeshEnvoyAccess"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        AWSXRayDaemonWriteAccess   = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
      }

      labels = {
        Environment = var.environment
        NodeGroup   = "microservices-nodes"
      }

      tags = merge(local.common_tags, {
        Name = "microservices-nodes"
      })
    }
  }

  # Enable IRSA
  enable_irsa = var.enable_irsa

  tags = local.common_tags
}

# KMS key for EKS encryption (if enabled)
resource "aws_kms_key" "eks" {
  count = var.enable_encryption_at_rest ? 1 : 0

  description             = "EKS Secret Encryption Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-eks-encryption-key"
  })
}

resource "aws_kms_alias" "eks" {
  count = var.enable_encryption_at_rest ? 1 : 0

  name          = "alias/${var.project_name}-eks-encryption-key"
  target_key_id = aws_kms_key.eks[0].key_id
}

# CloudWatch log group for Container Insights
resource "aws_cloudwatch_log_group" "container_insights" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/containerinsights/${local.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# Helm release for AWS Load Balancer Controller
resource "helm_release" "aws_load_balancer_controller" {
  depends_on = [module.eks]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.5.4"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.aws_load_balancer_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }
}

# Service account for AWS Load Balancer Controller
resource "kubernetes_service_account_v1" "aws_load_balancer_controller" {
  depends_on = [module.eks]

  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
    }
  }
}

# IAM role for AWS Load Balancer Controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.project_name}-alb-controller-${random_id.suffix.hex}"

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
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for AWS Load Balancer Controller
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${var.project_name}-alb-controller-policy-${random_id.suffix.hex}"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DescribeSubscription",
          "shield:ListProtections",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "CreateSecurityGroup"
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# App Mesh namespace
resource "kubernetes_namespace_v1" "app_mesh_system" {
  depends_on = [module.eks]

  metadata {
    name = "appmesh-system"
  }
}

# Production namespace for microservices
resource "kubernetes_namespace_v1" "production" {
  depends_on = [module.eks]

  metadata {
    name = var.mesh_namespace
    labels = {
      "mesh"                                        = local.mesh_name
      "appmesh.k8s.aws/sidecarInjectorWebhook"    = "enabled"
    }
  }
}

# Service account for App Mesh Controller
resource "kubernetes_service_account_v1" "appmesh_controller" {
  depends_on = [kubernetes_namespace_v1.app_mesh_system]

  metadata {
    name      = "appmesh-controller"
    namespace = "appmesh-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.appmesh_controller.arn
    }
  }
}

# IAM role for App Mesh Controller
resource "aws_iam_role" "appmesh_controller" {
  name = "${var.project_name}-appmesh-controller-${random_id.suffix.hex}"

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
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:appmesh-system:appmesh-controller"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach managed policies to App Mesh Controller role
resource "aws_iam_role_policy_attachment" "appmesh_controller_cloudmap" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCloudMapFullAccess"
  role       = aws_iam_role.appmesh_controller.name
}

resource "aws_iam_role_policy_attachment" "appmesh_controller_appmesh" {
  policy_arn = "arn:aws:iam::aws:policy/AWSAppMeshFullAccess"
  role       = aws_iam_role.appmesh_controller.name
}

# Install App Mesh Controller CRDs
resource "kubectl_manifest" "appmesh_crds" {
  depends_on = [module.eks]
  count      = length(local.appmesh_crds)

  yaml_body = local.appmesh_crds[count.index]
}

locals {
  appmesh_crds = [
    # This would typically be loaded from the CRD files
    # For brevity, including just the basic structure
    yamlencode({
      apiVersion = "apiextensions.k8s.io/v1"
      kind       = "CustomResourceDefinition"
      metadata = {
        name = "meshes.appmesh.k8s.aws"
      }
      spec = {
        group = "appmesh.k8s.aws"
        scope = "Cluster"
        names = {
          plural   = "meshes"
          singular = "mesh"
          kind     = "Mesh"
        }
        versions = [
          {
            name    = "v1beta2"
            served  = true
            storage = true
            schema = {
              openAPIV3Schema = {
                type = "object"
                properties = {
                  spec = {
                    type = "object"
                  }
                  status = {
                    type = "object"
                  }
                }
              }
            }
          }
        ]
      }
    })
  ]
}

# Helm release for App Mesh Controller
resource "helm_release" "appmesh_controller" {
  depends_on = [
    kubernetes_service_account_v1.appmesh_controller,
    kubectl_manifest.appmesh_crds
  ]

  name       = "appmesh-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "appmesh-controller"
  namespace  = "appmesh-system"
  version    = "1.12.1"

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.appmesh_controller.metadata[0].name
  }
}

# App Mesh
resource "kubectl_manifest" "app_mesh" {
  depends_on = [helm_release.appmesh_controller]

  yaml_body = yamlencode({
    apiVersion = "appmesh.k8s.aws/v1beta2"
    kind       = "Mesh"
    metadata = {
      name = local.mesh_name
    }
    spec = {
      namespaceSelector = {
        matchLabels = {
          mesh = local.mesh_name
        }
      }
    }
  })
}

# Virtual Nodes for each microservice
resource "kubectl_manifest" "virtual_nodes" {
  depends_on = [kubectl_manifest.app_mesh]
  for_each   = var.microservices

  yaml_body = yamlencode({
    apiVersion = "appmesh.k8s.aws/v1beta2"
    kind       = "VirtualNode"
    metadata = {
      name      = each.key
      namespace = var.mesh_namespace
    }
    spec = {
      podSelector = {
        matchLabels = {
          app = each.key
        }
      }
      listeners = [
        {
          portMapping = {
            port     = 5000
            protocol = "http"
          }
          healthCheck = {
            protocol         = "http"
            path             = "/"
            healthyThreshold = 2
            unhealthyThreshold = 2
            timeoutMillis    = 2000
            intervalMillis   = 5000
          }
        }
      ]
      backends = each.key == "service-a" ? [
        {
          virtualService = {
            virtualServiceRef = {
              name = "service-b"
            }
          }
        }
      ] : each.key == "service-b" ? [
        {
          virtualService = {
            virtualServiceRef = {
              name = "service-c"
            }
          }
        }
      ] : []
      serviceDiscovery = {
        dns = {
          hostname = "${each.key}.${var.mesh_namespace}.svc.cluster.local"
        }
      }
    }
  })
}

# Virtual Services for each microservice
resource "kubectl_manifest" "virtual_services" {
  depends_on = [kubectl_manifest.virtual_nodes]
  for_each   = var.microservices

  yaml_body = yamlencode({
    apiVersion = "appmesh.k8s.aws/v1beta2"
    kind       = "VirtualService"
    metadata = {
      name      = each.key
      namespace = var.mesh_namespace
    }
    spec = {
      awsName = "${each.key}.${var.mesh_namespace}.svc.cluster.local"
      provider = {
        virtualNode = {
          virtualNodeRef = {
            name = each.key
          }
        }
      }
    }
  })
}

# Microservice deployments
resource "kubernetes_deployment_v1" "microservices" {
  depends_on = [kubectl_manifest.virtual_services]
  for_each   = var.microservices

  metadata {
    name      = each.key
    namespace = var.mesh_namespace
    labels = {
      app = each.key
    }
  }

  spec {
    replicas = each.value.replicas

    selector {
      match_labels = {
        app = each.key
      }
    }

    template {
      metadata {
        labels = {
          app = each.key
        }
      }

      spec {
        container {
          name  = each.key
          image = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.microservices[each.key].name}:latest"
          
          port {
            container_port = 5000
          }

          env {
            name  = "SERVICE_NAME"
            value = each.key
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 5000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Kubernetes services for microservices
resource "kubernetes_service_v1" "microservices" {
  for_each = var.microservices

  metadata {
    name      = each.key
    namespace = var.mesh_namespace
  }

  spec {
    selector = {
      app = each.key
    }

    port {
      port        = 5000
      target_port = 5000
    }

    type = "ClusterIP"
  }
}

# Ingress for external access to service-a
resource "kubernetes_ingress_v1" "service_a" {
  depends_on = [helm_release.aws_load_balancer_controller]

  metadata {
    name      = "service-a-ingress"
    namespace = var.mesh_namespace
    annotations = {
      "kubernetes.io/ingress.class"                = "alb"
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/load-balancer-name" = "${var.project_name}-alb-${random_id.suffix.hex}"
      "alb.ingress.kubernetes.io/tags"             = "Environment=${var.environment},Project=${var.project_name}"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "service-a"
              port {
                number = 5000
              }
            }
          }
        }
      }
    }
  }
}

# X-Ray daemon (if enabled)
resource "kubernetes_service_account_v1" "xray_daemon" {
  count = var.enable_xray_tracing ? 1 : 0

  metadata {
    name      = "xray-daemon"
    namespace = var.mesh_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.xray_daemon[0].arn
    }
  }
}

resource "aws_iam_role" "xray_daemon" {
  count = var.enable_xray_tracing ? 1 : 0
  name  = "${var.project_name}-xray-daemon-${random_id.suffix.hex}"

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
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.mesh_namespace}:xray-daemon"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "xray_daemon" {
  count      = var.enable_xray_tracing ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.xray_daemon[0].name
}

resource "kubernetes_daemonset_v1" "xray_daemon" {
  count = var.enable_xray_tracing ? 1 : 0

  metadata {
    name      = "xray-daemon"
    namespace = var.mesh_namespace
  }

  spec {
    selector {
      match_labels = {
        app = "xray-daemon"
      }
    }

    template {
      metadata {
        labels = {
          app = "xray-daemon"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.xray_daemon[0].metadata[0].name

        container {
          name  = "xray-daemon"
          image = "public.ecr.aws/xray/aws-xray-daemon:latest"
          
          command = ["/xray", "-o", "-b", "xray-service:2000"]

          resources {
            limits = {
              memory = "32Mi"
            }
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
          }

          port {
            name           = "xray-udp"
            container_port = 2000
            protocol       = "UDP"
          }

          port {
            name           = "xray-tcp"
            container_port = 2000
            protocol       = "TCP"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "xray_service" {
  count = var.enable_xray_tracing ? 1 : 0

  metadata {
    name      = "xray-service"
    namespace = var.mesh_namespace
  }

  spec {
    selector = {
      app = "xray-daemon"
    }

    port {
      name        = "xray-udp"
      port        = 2000
      protocol    = "UDP"
      target_port = 2000
    }

    port {
      name        = "xray-tcp"
      port        = 2000
      protocol    = "TCP"
      target_port = 2000
    }
  }
}