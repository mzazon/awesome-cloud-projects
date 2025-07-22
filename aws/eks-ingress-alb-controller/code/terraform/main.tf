# ============================================================================
# AWS EKS Ingress Controllers with AWS Load Balancer Controller
# Terraform Configuration - Main Resources
# ============================================================================

# ============================================================================
# Provider Configuration
# ============================================================================

# Configure providers
provider "aws" {
  region = var.aws_region
}

# Data source for EKS cluster
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Configure Kubernetes provider
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Configure Helm provider
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# ============================================================================
# Data Sources
# ============================================================================

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get VPC information for the EKS cluster
data "aws_vpc" "cluster_vpc" {
  id = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}

# Get EKS cluster OIDC issuer URL for IRSA
data "tls_certificate" "cluster" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# ============================================================================
# Random Resources for Unique Naming
# ============================================================================

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ============================================================================
# IAM Resources for AWS Load Balancer Controller
# ============================================================================

# OIDC identity provider for the cluster (conditionally created)
resource "aws_iam_openid_connect_provider" "eks" {
  count = var.create_oidc_provider ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  tags = merge(var.tags, var.additional_tags, {
    Name = "${var.cluster_name}-eks-irsa"
  })
}

# IAM policy for AWS Load Balancer Controller
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name_prefix = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:GetManagedPrefixListEntries",
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
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
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
          "shield:ListProtections"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup",
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
          "elasticloadbalancing:DeleteRule"
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
          "elasticloadbalancing:AddTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = [
              "CreateTargetGroup",
              "CreateLoadBalancer"
            ]
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
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
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

# Data source for existing OIDC provider if not creating one
data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Local values for OIDC provider
locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.eks[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
  oidc_provider_url = var.create_oidc_provider ? aws_iam_openid_connect_provider.eks[0].url : data.aws_iam_openid_connect_provider.existing[0].url
}

# IAM role for AWS Load Balancer Controller
resource "aws_iam_role" "aws_load_balancer_controller" {
  name_prefix = "AmazonEKSLoadBalancerControllerRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Condition = {
          StringEquals = {
            "${replace(local.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(local.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
        Principal = {
          Federated = local.oidc_provider_arn
        }
      }
    ]
  })

  tags = merge(var.tags, var.additional_tags)
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# ============================================================================
# Kubernetes Resources
# ============================================================================

# Create namespace for demo applications
resource "kubernetes_namespace" "ingress_demo" {
  metadata {
    name = var.demo_namespace
    labels = {
      name = var.demo_namespace
    }
  }
}

# Service account for AWS Load Balancer Controller
resource "kubernetes_service_account" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
  }
}

# ============================================================================
# Helm Release for AWS Load Balancer Controller
# ============================================================================

# Time delay to allow IAM role propagation
resource "time_sleep" "wait_for_iam" {
  depends_on      = [aws_iam_role_policy_attachment.aws_load_balancer_controller]
  create_duration = "10s"
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.alb_controller_version

  # Wait for load balancer to be ready before completing
  wait          = var.wait_for_load_balancer
  wait_for_jobs = true
  timeout       = 300

  # Enable debug logging if specified
  set {
    name  = "logLevel"
    value = var.controller_log_level
  }

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = data.aws_vpc.cluster_vpc.id
  }

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.${var.aws_region}.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  set {
    name  = "image.tag"
    value = var.controller_image_tag
  }

  # Enable pod readiness gate
  set {
    name  = "enablePodReadinessGate"
    value = var.enable_pod_readiness_gate
  }

  # Enable EFA support if specified
  set {
    name  = "enableEFA"
    value = var.enable_efa_support
  }

  # Resource limits for controller pods
  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "500Mi"
  }

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "200Mi"
  }

  # Enable metrics and monitoring
  set {
    name  = "enableServiceMutatorWebhook"
    value = "true"
  }

  depends_on = [
    kubernetes_service_account.aws_load_balancer_controller,
    time_sleep.wait_for_iam
  ]
}

# ============================================================================
# Sample Applications for Testing
# ============================================================================

# Sample application v1 deployment
resource "kubernetes_deployment" "sample_app_v1" {
  metadata {
    name      = "sample-app-v1"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
    labels = {
      app     = "sample-app"
      version = "v1"
    }
  }

  spec {
    replicas = var.sample_app_replicas

    selector {
      match_labels = {
        app     = "sample-app"
        version = "v1"
      }
    }

    template {
      metadata {
        labels = {
          app     = "sample-app"
          version = "v1"
        }
      }

      spec {
        container {
          image = "nginx:1.21"
          name  = "app"

          port {
            container_port = 80
          }

          env {
            name  = "VERSION"
            value = "v1"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }
}

# Sample application v1 service
resource "kubernetes_service" "sample_app_v1" {
  metadata {
    name      = "sample-app-v1"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
  }

  spec {
    selector = {
      app     = "sample-app"
      version = "v1"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# Sample application v2 deployment
resource "kubernetes_deployment" "sample_app_v2" {
  metadata {
    name      = "sample-app-v2"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
    labels = {
      app     = "sample-app"
      version = "v2"
    }
  }

  spec {
    replicas = var.sample_app_replicas

    selector {
      match_labels = {
        app     = "sample-app"
        version = "v2"
      }
    }

    template {
      metadata {
        labels = {
          app     = "sample-app"
          version = "v2"
        }
      }

      spec {
        container {
          image = "nginx:1.21"
          name  = "app"

          port {
            container_port = 80
          }

          env {
            name  = "VERSION"
            value = "v2"
          }

          resources {
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }
}

# Sample application v2 service
resource "kubernetes_service" "sample_app_v2" {
  metadata {
    name      = "sample-app-v2"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
  }

  spec {
    selector = {
      app     = "sample-app"
      version = "v2"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# ============================================================================
# Certificate Manager (Optional)
# ============================================================================

# Request SSL certificate if domain is provided
resource "aws_acm_certificate" "ingress_cert" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    var.domain_name
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ingress-certificate"
  })
}

# ============================================================================
# S3 Bucket for ALB Access Logs (Optional)
# ============================================================================

resource "aws_s3_bucket" "alb_access_logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = "alb-access-logs-${var.cluster_name}-${random_string.suffix.result}"

  tags = merge(var.tags, {
    Name        = "ALB Access Logs"
    Environment = "demo"
  })
}

resource "aws_s3_bucket_versioning" "alb_access_logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Get the AWS Load Balancer service account for the region
data "aws_elb_service_account" "main" {}

# S3 bucket policy for ALB access logs
resource "aws_s3_bucket_policy" "alb_access_logs" {
  count  = var.enable_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_access_logs[0].arn}/alb-logs/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_access_logs[0].arn}/alb-logs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_access_logs[0].arn
      }
    ]
  })
}

# ============================================================================
# Ingress Resources (Optional - for demonstration)
# ============================================================================

# Basic ALB Ingress
resource "kubernetes_ingress_v1" "basic_alb" {
  count = var.create_sample_ingresses ? 1 : 0

  metadata {
    name      = "sample-app-basic-alb"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"                    = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"              = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"         = "/"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "10"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "5"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "3"
      "alb.ingress.kubernetes.io/tags" = "Environment=demo,Team=platform,ManagedBy=terraform"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = var.domain_name != "" ? "basic.${var.domain_name}" : null
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.sample_app_v1.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Advanced ALB Ingress with SSL (if certificate is available)
resource "kubernetes_ingress_v1" "advanced_alb" {
  count = var.create_sample_ingresses && var.domain_name != "" ? 1 : 0

  metadata {
    name      = "sample-app-advanced-alb"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"         = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"   = "ip"
      "alb.ingress.kubernetes.io/listen-ports"  = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"  = "443"
      "alb.ingress.kubernetes.io/certificate-arn" = var.domain_name != "" ? aws_acm_certificate.ingress_cert[0].arn : ""
      "alb.ingress.kubernetes.io/ssl-policy"    = "ELBSecurityPolicy-TLS-1-2-2019-07"
      "alb.ingress.kubernetes.io/load-balancer-attributes" = var.enable_access_logs ? "access_logs.s3.enabled=true,access_logs.s3.bucket=${aws_s3_bucket.alb_access_logs[0].bucket},access_logs.s3.prefix=alb-logs,idle_timeout.timeout_seconds=60" : "access_logs.s3.enabled=false,idle_timeout.timeout_seconds=60"
      "alb.ingress.kubernetes.io/target-group-attributes" = "deregistration_delay.timeout_seconds=30,stickiness.enabled=false"
      "alb.ingress.kubernetes.io/healthcheck-path"        = "/"
      "alb.ingress.kubernetes.io/healthcheck-protocol"    = "HTTP"
      "alb.ingress.kubernetes.io/group.name"              = "advanced-ingress"
      "alb.ingress.kubernetes.io/group.order"             = "1"
      "alb.ingress.kubernetes.io/tags" = "Environment=demo,Team=platform,ManagedBy=terraform"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = "advanced.${var.domain_name}"
      http {
        path {
          path      = "/v1"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.sample_app_v1.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path      = "/v2"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.sample_app_v2.metadata[0].name
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
    helm_release.aws_load_balancer_controller,
    aws_acm_certificate.ingress_cert
  ]
}

# Network Load Balancer Service
resource "kubernetes_service" "sample_app_nlb" {
  count = var.create_sample_ingresses ? 1 : 0

  metadata {
    name      = "sample-app-nlb"
    namespace = kubernetes_namespace.ingress_demo.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"                           = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                 = "tcp"
      "service.beta.kubernetes.io/aws-load-balancer-target-type"                      = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-attributes"                       = "load_balancing.cross_zone.enabled=true"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"             = "HTTP"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"                 = "/"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval"             = "10"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout"              = "5"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold"    = "2"
      "service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold"  = "3"
    }
  }

  spec {
    selector = {
      app     = "sample-app"
      version = "v1"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# Custom IngressClass
resource "kubernetes_manifest" "custom_ingress_class" {
  count = var.create_sample_ingresses ? 1 : 0

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = "custom-alb"
      annotations = {
        "ingressclass.kubernetes.io/is-default-class" = "false"
      }
    }
    spec = {
      controller = "ingress.k8s.aws/alb"
      parameters = {
        apiVersion = "elbv2.k8s.aws/v1beta1"
        kind       = "IngressClassParams"
        name       = "custom-alb-params"
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# IngressClassParams for custom configuration
resource "kubernetes_manifest" "custom_ingress_class_params" {
  count = var.create_sample_ingresses ? 1 : 0

  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "IngressClassParams"
    metadata = {
      name = "custom-alb-params"
    }
    spec = {
      scheme     = "internet-facing"
      targetType = "ip"
      tags = {
        Environment = "demo"
        Team        = "platform"
        ManagedBy   = "aws-load-balancer-controller"
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}