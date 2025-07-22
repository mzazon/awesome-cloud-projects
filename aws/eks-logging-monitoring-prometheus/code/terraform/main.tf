# EKS Cluster Logging and Monitoring with CloudWatch and Prometheus
# This Terraform configuration creates a comprehensive observability stack for Amazon EKS

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for common configurations
locals {
  cluster_name_unique = "${var.cluster_name}-${random_string.suffix.result}"
  
  common_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Purpose     = "eks-observability"
    }
  )
}

# VPC Module for EKS cluster
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name_unique}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  enable_vpn_gateway = false
  enable_dns_hostnames = true
  enable_dns_support = true

  # Enable required tags for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name_unique}" = "shared"
    "kubernetes.io/role/elb"                            = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name_unique}" = "shared"
    "kubernetes.io/role/internal-elb"                   = "1"
  }

  tags = local.common_tags
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name_unique
  role_arn = aws_iam_role.cluster_service_role.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
    endpoint_private_access = var.endpoint_config.private_access
    endpoint_public_access  = var.endpoint_config.public_access
    public_access_cidrs     = var.endpoint_config.public_access_cidrs
  }

  # Enable comprehensive control plane logging
  enabled_cluster_log_types = var.control_plane_logging

  # Ensure cluster service role is created first
  depends_on = [
    aws_iam_role_policy_attachment.cluster_service_policy,
    aws_cloudwatch_log_group.cluster_logs
  ]

  tags = local.common_tags
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = module.vpc.private_subnet_ids

  scaling_config {
    desired_size = var.node_group_config.scaling_config.desired_size
    max_size     = var.node_group_config.scaling_config.max_size
    min_size     = var.node_group_config.scaling_config.min_size
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = var.node_group_config.instance_types
  ami_type       = var.node_group_config.ami_type
  disk_size      = var.node_group_config.disk_size

  # Ensure node group role is created first
  depends_on = [
    aws_iam_role_policy_attachment.node_group_worker_policy,
    aws_iam_role_policy_attachment.node_group_cni_policy,
    aws_iam_role_policy_attachment.node_group_registry_policy,
  ]

  tags = local.common_tags
}

# CloudWatch Log Group for EKS Control Plane
resource "aws_cloudwatch_log_group" "cluster_logs" {
  name              = "/aws/eks/${local.cluster_name_unique}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name_unique}-cluster-logs"
    }
  )
}

# CloudWatch Log Groups for Container Insights
resource "aws_cloudwatch_log_group" "container_insights_application" {
  name              = "/aws/containerinsights/${local.cluster_name_unique}/application"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name_unique}-application-logs"
    }
  )
}

resource "aws_cloudwatch_log_group" "container_insights_dataplane" {
  name              = "/aws/containerinsights/${local.cluster_name_unique}/dataplane"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name_unique}-dataplane-logs"
    }
  )
}

# OIDC Provider for IAM Roles for Service Accounts
resource "aws_iam_openid_connect_provider" "eks" {
  count = var.enable_irsa ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = local.common_tags
}

# Data source for OIDC thumbprint
data "tls_certificate" "eks_oidc" {
  count = var.enable_irsa ? 1 : 0
  url   = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# CloudWatch Agent Service Account and IAM Role
resource "kubernetes_namespace" "amazon_cloudwatch" {
  depends_on = [aws_eks_node_group.main]
  
  metadata {
    name = "amazon-cloudwatch"
  }
}

resource "kubernetes_service_account" "cloudwatch_agent" {
  depends_on = [aws_eks_node_group.main]
  
  metadata {
    name      = "cloudwatch-agent"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
    annotations = var.enable_irsa ? {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cloudwatch_agent_role[0].arn
    } : {}
  }
}

# Fluent Bit ConfigMap
resource "kubernetes_config_map" "fluent_bit_config" {
  depends_on = [aws_eks_node_group.main]
  
  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  }

  data = {
    "fluent-bit.conf" = templatefile("${path.module}/templates/fluent-bit.conf.tpl", {
      cluster_name = local.cluster_name_unique
      aws_region   = data.aws_region.current.name
      log_level    = var.fluent_bit_config.log_level
      mem_buf_limit = var.fluent_bit_config.mem_buf_limit
      read_from_head = var.fluent_bit_config.read_from_head
    })
    
    "parsers.conf" = file("${path.module}/templates/parsers.conf.tpl")
  }
}

# Fluent Bit DaemonSet
resource "kubernetes_daemonset" "fluent_bit" {
  depends_on = [
    aws_eks_node_group.main,
    kubernetes_config_map.fluent_bit_config
  ]
  
  metadata {
    name      = "fluent-bit"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        name = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          name = "fluent-bit"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cloudwatch_agent.metadata[0].name

        container {
          name  = "fluent-bit"
          image = "amazon/aws-for-fluent-bit:${var.fluent_bit_config.image_tag}"
          image_pull_policy = "Always"

          env {
            name  = "AWS_REGION"
            value = data.aws_region.current.name
          }

          env {
            name  = "CLUSTER_NAME"
            value = local.cluster_name_unique
          }

          env {
            name  = "HOST_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name  = "HOSTNAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          resources {
            limits = {
              memory = "200Mi"
            }
            requests = {
              cpu    = "500m"
              memory = "100Mi"
            }
          }

          volume_mount {
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          volume_mount {
            name       = "fluentbitstate"
            mount_path = "/var/fluent-bit/state"
          }

          volume_mount {
            name       = "runlogjournal"
            mount_path = "/run/log/journal"
            read_only  = true
          }

          volume_mount {
            name       = "dmesg"
            mount_path = "/var/log/dmesg"
            read_only  = true
          }
        }

        termination_grace_period_seconds = 10

        volume {
          name = "fluent-bit-config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config.metadata[0].name
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "fluentbitstate"
          host_path {
            path = "/var/fluent-bit/state"
          }
        }

        volume {
          name = "runlogjournal"
          host_path {
            path = "/run/log/journal"
          }
        }

        volume {
          name = "dmesg"
          host_path {
            path = "/var/log/dmesg"
          }
        }

        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }

        toleration {
          operator = "Exists"
          effect   = "NoExecute"
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }
}

# CloudWatch Agent ConfigMap
resource "kubernetes_config_map" "cloudwatch_agent_config" {
  depends_on = [aws_eks_node_group.main]
  
  metadata {
    name      = "cwagentconfig"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  }

  data = {
    "cwagentconfig.json" = jsonencode({
      metrics = {
        namespace = "ContainerInsights"
        metrics_collected = {
          cpu = {
            measurement = [
              "cpu_usage_idle",
              "cpu_usage_iowait",
              "cpu_usage_user",
              "cpu_usage_system"
            ]
            metrics_collection_interval = var.monitoring_config.metrics_collection_interval
            resources = ["*"]
            totalcpu = false
          }
          disk = {
            measurement = ["used_percent"]
            metrics_collection_interval = var.monitoring_config.metrics_collection_interval
            resources = ["*"]
          }
          diskio = {
            measurement = [
              "io_time",
              "read_bytes",
              "write_bytes",
              "reads",
              "writes"
            ]
            metrics_collection_interval = var.monitoring_config.metrics_collection_interval
            resources = ["*"]
          }
          mem = {
            measurement = ["mem_used_percent"]
            metrics_collection_interval = var.monitoring_config.metrics_collection_interval
          }
          netstat = {
            measurement = [
              "tcp_established",
              "tcp_time_wait"
            ]
            metrics_collection_interval = var.monitoring_config.metrics_collection_interval
          }
          swap = {
            measurement = ["swap_used_percent"]
            metrics_collection_interval = var.monitoring_config.metrics_collection_interval
          }
        }
      }
    })
  }
}

# CloudWatch Agent DaemonSet
resource "kubernetes_daemonset" "cloudwatch_agent" {
  depends_on = [
    aws_eks_node_group.main,
    kubernetes_config_map.cloudwatch_agent_config
  ]
  
  metadata {
    name      = "cloudwatch-agent"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        name = "cloudwatch-agent"
      }
    }

    template {
      metadata {
        labels = {
          name = "cloudwatch-agent"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cloudwatch_agent.metadata[0].name

        container {
          name  = "cloudwatch-agent"
          image = "amazon/cloudwatch-agent:1.300026.2b361"

          port {
            container_port = 8125
            host_port      = 8125
            protocol       = "UDP"
          }

          resources {
            limits = {
              cpu    = "200m"
              memory = "200Mi"
            }
            requests = {
              cpu    = "200m"
              memory = "200Mi"
            }
          }

          env {
            name = "HOST_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }

          env {
            name = "HOST_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name = "K8S_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          volume_mount {
            name       = "cwagentconfig"
            mount_path = "/etc/cwagentconfig"
          }

          volume_mount {
            name       = "rootfs"
            mount_path = "/rootfs"
            read_only  = true
          }

          volume_mount {
            name       = "dockersock"
            mount_path = "/var/run/docker.sock"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdocker"
            mount_path = "/var/lib/docker"
            read_only  = true
          }

          volume_mount {
            name       = "containerdsock"
            mount_path = "/run/containerd/containerd.sock"
            read_only  = true
          }

          volume_mount {
            name       = "sys"
            mount_path = "/sys"
            read_only  = true
          }

          volume_mount {
            name       = "devdisk"
            mount_path = "/dev/disk"
            read_only  = true
          }
        }

        termination_grace_period_seconds = 60

        volume {
          name = "cwagentconfig"
          config_map {
            name = kubernetes_config_map.cloudwatch_agent_config.metadata[0].name
          }
        }

        volume {
          name = "rootfs"
          host_path {
            path = "/"
          }
        }

        volume {
          name = "dockersock"
          host_path {
            path = "/var/run/docker.sock"
          }
        }

        volume {
          name = "varlibdocker"
          host_path {
            path = "/var/lib/docker"
          }
        }

        volume {
          name = "containerdsock"
          host_path {
            path = "/run/containerd/containerd.sock"
          }
        }

        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }

        volume {
          name = "devdisk"
          host_path {
            path = "/dev/disk"
          }
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }

        toleration {
          operator = "Exists"
          effect   = "NoExecute"
        }
      }
    }
  }
}

# Amazon Managed Service for Prometheus Workspace
resource "aws_prometheus_workspace" "main" {
  count = var.enable_prometheus ? 1 : 0

  alias = "${var.prometheus_workspace_name}-${random_string.suffix.result}"

  tags = merge(
    local.common_tags,
    {
      Name = "${var.prometheus_workspace_name}-${random_string.suffix.result}"
    }
  )
}

# Prometheus Scraper Configuration
resource "aws_prometheus_scraper" "main" {
  count = var.enable_prometheus ? 1 : 0

  source {
    eks {
      cluster_arn = aws_eks_cluster.main.arn
      subnet_ids  = module.vpc.private_subnet_ids
    }
  }

  destination {
    amp {
      workspace_arn = aws_prometheus_workspace.main[0].arn
    }
  }

  scrape_configuration = templatefile("${path.module}/templates/prometheus-scraper-config.yaml.tpl", {
    cluster_name = local.cluster_name_unique
  })

  depends_on = [
    aws_iam_role.prometheus_scraper_role
  ]

  tags = local.common_tags
}

# Sample Application with Prometheus Metrics
resource "kubernetes_deployment" "sample_app" {
  count = var.deploy_sample_app ? 1 : 0
  
  depends_on = [aws_eks_node_group.main]
  
  metadata {
    name      = "sample-app"
    namespace = "default"
  }

  spec {
    replicas = var.sample_app_config.replicas

    selector {
      match_labels = {
        app = "sample-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "sample-app"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8080"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        container {
          name  = "sample-app"
          image = "${var.sample_app_config.image}:${var.sample_app_config.tag}"

          port {
            container_port = 80
          }

          port {
            container_port = 8080
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
            name  = "PROMETHEUS_ENABLED"
            value = "true"
          }
        }
      }
    }
  }
}

# Sample Application Service
resource "kubernetes_service" "sample_app" {
  count = var.deploy_sample_app ? 1 : 0
  
  depends_on = [aws_eks_node_group.main]
  
  metadata {
    name      = "sample-app-service"
    namespace = "default"
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "8080"
    }
  }

  spec {
    selector = {
      app = "sample-app"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 80
    }

    port {
      name        = "metrics"
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}