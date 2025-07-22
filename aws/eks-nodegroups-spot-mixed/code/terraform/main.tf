# Data sources for existing EKS cluster
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get VPC and subnet information from existing cluster
data "aws_subnets" "cluster_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.cluster.vpc_config[0].vpc_id]
  }

  filter {
    name   = "tag:kubernetes.io/cluster/${var.cluster_name}"
    values = ["owned", "shared"]
  }
}

# Get OIDC provider for IRSA
data "aws_eks_cluster" "cluster_oidc" {
  name = var.cluster_name
}

data "tls_certificate" "cluster_oidc" {
  url = data.aws_eks_cluster.cluster_oidc.identity[0].oidc[0].issuer
}

# Create OIDC provider if it doesn't exist
resource "aws_iam_openid_connect_provider" "cluster_oidc" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster_oidc.certificates[0].sha1_fingerprint]
  url             = data.aws_eks_cluster.cluster_oidc.identity[0].oidc[0].issuer

  tags = merge(
    {
      Name = "${var.cluster_name}-oidc"
    },
    var.additional_tags
  )
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# IAM Role for EKS Node Groups
resource "aws_iam_role" "node_group_role" {
  name = "${var.cluster_name}-node-group-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    {
      Name = "${var.cluster_name}-node-group-role"
    },
    var.additional_tags
  )
}

# Attach required policies to node group role
resource "aws_iam_role_policy_attachment" "node_group_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

# Attach additional policies if specified
resource "aws_iam_role_policy_attachment" "node_group_additional_policies" {
  count      = length(var.node_group_additional_policies)
  policy_arn = var.node_group_additional_policies[count.index]
  role       = aws_iam_role.node_group_role.name
}

# Local values for subnet selection
locals {
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.cluster_subnets.ids
  
  # Common tags for all resources
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "eks-cost-optimization"
      ManagedBy   = "terraform"
      Cluster     = var.cluster_name
    },
    var.additional_tags
  )
}

# Spot Instance Node Group
resource "aws_eks_node_group" "spot_node_group" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.node_group_name_prefix}-spot-${random_string.suffix.result}"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = local.subnet_ids

  # Capacity configuration for spot instances
  capacity_type  = "SPOT"
  instance_types = var.spot_node_group_config.instance_types
  ami_type       = var.spot_node_group_config.ami_type
  disk_size      = var.spot_node_group_config.disk_size

  # Scaling configuration
  scaling_config {
    desired_size = var.spot_node_group_config.desired_size
    max_size     = var.spot_node_group_config.max_size
    min_size     = var.spot_node_group_config.min_size
  }

  # Update configuration to minimize disruption
  update_config {
    max_unavailable = 1
  }

  # Remote access configuration (optional)
  # remote_access {
  #   ec2_ssh_key = var.ssh_key_name
  #   source_security_group_ids = [aws_security_group.node_group_sg.id]
  # }

  # Taints for spot instances
  dynamic "taint" {
    for_each = var.spot_node_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  # Labels for spot instances
  labels = var.spot_node_labels

  # Tags
  tags = merge(
    local.common_tags,
    {
      Name         = "${var.node_group_name_prefix}-spot-${random_string.suffix.result}"
      NodeType     = "spot"
      CapacityType = "SPOT"
    }
  )

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling
  depends_on = [
    aws_iam_role_policy_attachment.node_group_worker_policy,
    aws_iam_role_policy_attachment.node_group_cni_policy,
    aws_iam_role_policy_attachment.node_group_registry_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# On-Demand Instance Node Group
resource "aws_eks_node_group" "ondemand_node_group" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.node_group_name_prefix}-ondemand-${random_string.suffix.result}"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = local.subnet_ids

  # Capacity configuration for on-demand instances
  capacity_type  = "ON_DEMAND"
  instance_types = var.ondemand_node_group_config.instance_types
  ami_type       = var.ondemand_node_group_config.ami_type
  disk_size      = var.ondemand_node_group_config.disk_size

  # Scaling configuration
  scaling_config {
    desired_size = var.ondemand_node_group_config.desired_size
    max_size     = var.ondemand_node_group_config.max_size
    min_size     = var.ondemand_node_group_config.min_size
  }

  # Update configuration to minimize disruption
  update_config {
    max_unavailable = 1
  }

  # Labels for on-demand instances
  labels = var.ondemand_node_labels

  # Tags
  tags = merge(
    local.common_tags,
    {
      Name         = "${var.node_group_name_prefix}-ondemand-${random_string.suffix.result}"
      NodeType     = "on-demand"
      CapacityType = "ON_DEMAND"
    }
  )

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling
  depends_on = [
    aws_iam_role_policy_attachment.node_group_worker_policy,
    aws_iam_role_policy_attachment.node_group_cni_policy,
    aws_iam_role_policy_attachment.node_group_registry_policy,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# IAM Role for Cluster Autoscaler
resource "aws_iam_role" "cluster_autoscaler_role" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.cluster_name}-cluster-autoscaler-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Federated = var.enable_irsa ? (
            var.oidc_provider_arn != "" ? var.oidc_provider_arn : aws_iam_openid_connect_provider.cluster_oidc[0].arn
          ) : null
        }
        Condition = var.enable_irsa ? {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:cluster-autoscaler"
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        } : null
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-cluster-autoscaler-role"
    }
  )
}

# IAM Policy for Cluster Autoscaler
resource "aws_iam_policy" "cluster_autoscaler_policy" {
  count = var.enable_cluster_autoscaler ? 1 : 0
  name  = "${var.cluster_name}-cluster-autoscaler-policy-${random_string.suffix.result}"

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
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-cluster-autoscaler-policy"
    }
  )
}

# Attach policy to Cluster Autoscaler role
resource "aws_iam_role_policy_attachment" "cluster_autoscaler_policy_attachment" {
  count      = var.enable_cluster_autoscaler ? 1 : 0
  policy_arn = aws_iam_policy.cluster_autoscaler_policy[0].arn
  role       = aws_iam_role.cluster_autoscaler_role[0].name
}

# Kubernetes Service Account for Cluster Autoscaler
resource "kubernetes_service_account" "cluster_autoscaler_sa" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = var.enable_irsa ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler_role[0].arn
    } : {}
  }

  depends_on = [
    aws_eks_node_group.spot_node_group,
    aws_eks_node_group.ondemand_node_group
  ]
}

# Cluster Autoscaler Deployment
resource "kubernetes_deployment" "cluster_autoscaler" {
  count = var.enable_cluster_autoscaler ? 1 : 0

  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    labels = {
      app = "cluster-autoscaler"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "cluster-autoscaler"
      }
    }

    template {
      metadata {
        labels = {
          app = "cluster-autoscaler"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8085"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cluster_autoscaler_sa[0].metadata[0].name
        priority_class_name  = "system-cluster-critical"

        security_context {
          run_as_non_root = true
          run_as_user     = 65534
          fs_group        = 65534
        }

        container {
          image = "registry.k8s.io/autoscaling/cluster-autoscaler:${var.cluster_autoscaler_version}"
          name  = "cluster-autoscaler"

          resources {
            limits = {
              cpu    = "100m"
              memory = "600Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "600Mi"
            }
          }

          command = [
            "./cluster-autoscaler",
            "--v=4",
            "--stderrthreshold=info",
            "--cloud-provider=aws",
            "--skip-nodes-with-local-storage=false",
            "--expander=least-waste",
            "--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${var.cluster_name}",
            "--balance-similar-node-groups",
            "--skip-nodes-with-system-pods=false"
          ]

          volume_mount {
            name       = "ssl-certs"
            mount_path = "/etc/ssl/certs/ca-certificates.crt"
            read_only  = true
          }

          image_pull_policy = "Always"

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
            read_only_root_filesystem = true
          }
        }

        volume {
          name = "ssl-certs"
          host_path {
            path = "/etc/ssl/certs/ca-bundle.crt"
          }
        }

        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        toleration {
          key    = "CriticalAddonsOnly"
          value  = ""
          effect = "NoSchedule"
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.cluster_autoscaler_sa,
    aws_eks_node_group.spot_node_group,
    aws_eks_node_group.ondemand_node_group
  ]
}

# AWS Node Termination Handler
resource "helm_release" "node_termination_handler" {
  count = var.enable_node_termination_handler ? 1 : 0

  name       = "aws-node-termination-handler"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-node-termination-handler"
  version    = var.node_termination_handler_version
  namespace  = "kube-system"

  set {
    name  = "enableSpotInterruptionDraining"
    value = "true"
  }

  set {
    name  = "enableRebalanceMonitoring"
    value = "true"
  }

  set {
    name  = "enableScheduledEventDraining"
    value = "true"
  }

  set {
    name  = "nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }

  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }

  set {
    name  = "tolerations[0].effect"
    value = "NoSchedule"
  }

  depends_on = [
    aws_eks_node_group.spot_node_group,
    aws_eks_node_group.ondemand_node_group
  ]
}

# CloudWatch Log Group for Spot interruptions
resource "aws_cloudwatch_log_group" "spot_interruptions" {
  count             = var.enable_cost_monitoring ? 1 : 0
  name              = "/aws/eks/${var.cluster_name}/spot-interruptions"
  retention_in_days = 7

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-spot-interruptions-logs"
    }
  )
}

# CloudWatch Alarm for high spot interruption rate
resource "aws_cloudwatch_metric_alarm" "spot_interruption_alarm" {
  count = var.enable_cost_monitoring && var.sns_topic_arn != "" ? 1 : 0

  alarm_name          = "EKS-${var.cluster_name}-HighSpotInterruptions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SpotInterruptionRate"
  namespace           = "AWS/EKS"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.spot_interruption_threshold
  alarm_description   = "This metric monitors spot instance interruption rate"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.cluster_name
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-spot-interruption-alarm"
    }
  )
}

# Pod Disruption Budget for spot workloads
resource "kubernetes_pod_disruption_budget_v1" "spot_workload_pdb" {
  metadata {
    name = "spot-workload-pdb"
  }

  spec {
    min_available = 1
    selector {
      match_labels = {
        "workload-type" = "spot-tolerant"
      }
    }
  }

  depends_on = [
    aws_eks_node_group.spot_node_group,
    aws_eks_node_group.ondemand_node_group
  ]
}

# Example spot-tolerant application deployment
resource "kubernetes_deployment" "spot_demo_app" {
  metadata {
    name = "spot-demo-app"
    labels = {
      app = "spot-demo-app"
    }
  }

  spec {
    replicas = 6

    selector {
      match_labels = {
        app           = "spot-demo-app"
        workload-type = "spot-tolerant"
      }
    }

    template {
      metadata {
        labels = {
          app           = "spot-demo-app"
          workload-type = "spot-tolerant"
        }
      }

      spec {
        service_account_name = "default"

        # Toleration for spot instances
        toleration {
          key      = "node-type"
          operator = "Equal"
          value    = "spot"
          effect   = "NoSchedule"
        }

        # Node selector to prefer spot instances
        node_selector = {
          "node-type" = "spot"
        }

        container {
          image = "nginx:latest"
          name  = "nginx"

          resources {
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          port {
            container_port = 80
          }

          # Liveness and readiness probes
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        # Spread pods across nodes for better availability
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "DoNotSchedule"
          label_selector {
            match_labels = {
              app = "spot-demo-app"
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_eks_node_group.spot_node_group,
    aws_eks_node_group.ondemand_node_group
  ]
}

# Service for the demo application
resource "kubernetes_service" "spot_demo_service" {
  metadata {
    name = "spot-demo-service"
  }

  spec {
    selector = {
      app = "spot-demo-app"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }

  depends_on = [
    kubernetes_deployment.spot_demo_app
  ]
}