# EKS CloudWatch Container Insights Infrastructure
# This configuration sets up comprehensive monitoring for an existing EKS cluster

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Get existing EKS cluster information
data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

# Get authentication token for EKS cluster
data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Local values for consistent resource naming and configuration
locals {
  cluster_name = var.cluster_name
  account_id   = data.aws_caller_identity.current.account_id
  
  # Common tags applied to all resources
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "EKS-CloudWatch-Monitoring"
      ManagedBy   = "Terraform"
      Cluster     = var.cluster_name
    },
    var.additional_tags
  )
}

# =====================================================
# SNS Topic and Subscription for Alert Notifications
# =====================================================

# SNS topic for CloudWatch alarm notifications
resource "aws_sns_topic" "eks_monitoring_alerts" {
  name = "eks-${local.cluster_name}-monitoring-alerts"

  tags = local.common_tags
}

# Email subscription for the SNS topic
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.eks_monitoring_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =====================================================
# EKS Control Plane Logging Configuration
# =====================================================

# Enable comprehensive EKS control plane logging
resource "aws_eks_cluster" "cluster_logging_update" {
  count = var.enable_control_plane_logging ? 1 : 0
  
  name     = var.cluster_name
  role_arn = data.aws_eks_cluster.cluster.role_arn
  version  = data.aws_eks_cluster.cluster.version

  # Enable all control plane log types for comprehensive monitoring
  enabled_cluster_log_types = [
    "api",
    "audit", 
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  vpc_config {
    subnet_ids              = data.aws_eks_cluster.cluster.vpc_config[0].subnet_ids
    endpoint_private_access = data.aws_eks_cluster.cluster.vpc_config[0].endpoint_private_access
    endpoint_public_access  = data.aws_eks_cluster.cluster.vpc_config[0].endpoint_public_access
    public_access_cidrs     = data.aws_eks_cluster.cluster.vpc_config[0].public_access_cidrs
    security_group_ids      = data.aws_eks_cluster.cluster.vpc_config[0].security_group_ids
  }

  tags = local.common_tags

  # Ensure this runs after the cluster is available
  depends_on = [data.aws_eks_cluster.cluster]
}

# =====================================================
# IAM Role for CloudWatch Agent (IRSA)
# =====================================================

# IAM role for CloudWatch agent service account
resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "eks-${local.cluster_name}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${local.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach CloudWatch Agent Server Policy to the role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.cloudwatch_agent_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# =====================================================
# Kubernetes Resources for CloudWatch Monitoring
# =====================================================

# Create the amazon-cloudwatch namespace
resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
    
    labels = {
      name = "amazon-cloudwatch"
    }
  }
}

# Service account for CloudWatch agent with IRSA annotation
resource "kubernetes_service_account" "cloudwatch_agent" {
  metadata {
    name      = "cloudwatch-agent"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
    
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cloudwatch_agent_role.arn
    }
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

# ConfigMap for CloudWatch agent configuration
resource "kubernetes_config_map" "cwagentconfig" {
  metadata {
    name      = "cwagentconfig"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
  }

  data = {
    "cwagentconfig.json" = jsonencode({
      logs = {
        metrics_collected = {
          kubernetes = {
            cluster_name = local.cluster_name
            metrics_collection_interval = 60
          }
        }
        force_flush_interval = 5
      }
      metrics = {
        namespace = "ContainerInsights"
        metrics_collected = {
          cpu = {
            measurement = ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
            metrics_collection_interval = 60
          }
          disk = {
            measurement = ["used_percent"]
            metrics_collection_interval = 60
            resources = ["*"]
          }
          diskio = {
            measurement = ["io_time", "read_bytes", "write_bytes", "reads", "writes"]
            metrics_collection_interval = 60
            resources = ["*"]
          }
          mem = {
            measurement = ["mem_used_percent"]
            metrics_collection_interval = 60
          }
          netstat = {
            measurement = ["tcp_established", "tcp_time_wait"]
            metrics_collection_interval = 60
          }
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

# DaemonSet for CloudWatch agent
resource "kubernetes_daemonset" "cloudwatch_agent" {
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
          image = var.cloudwatch_agent_image

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
            name = "HOST_PATH"
            value = "/rootfs"
          }

          env {
            name = "K8S_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name = "CI_VERSION"
            value = "k8s/1.3.9"
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

        volume {
          name = "cwagentconfig"
          config_map {
            name = kubernetes_config_map.cwagentconfig.metadata[0].name
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
            path = "/dev/disk/"
          }
        }

        termination_grace_period_seconds = 60
      }
    }
  }

  depends_on = [
    kubernetes_service_account.cloudwatch_agent,
    kubernetes_config_map.cwagentconfig
  ]
}

# ConfigMap for Fluent Bit configuration
resource "kubernetes_config_map" "fluent_bit_config" {
  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
    
    labels = {
      k8s-app = "fluent-bit"
    }
  }

  data = {
    "fluent-bit.conf" = <<-EOF
      [SERVICE]
          Flush                     5
          Grace                     30
          Log_Level                 info
          Daemon                    off
          Parsers_File              parsers.conf
          HTTP_Server               On
          HTTP_Listen               0.0.0.0
          HTTP_Port                 2020
          storage.path              /var/fluent-bit/state/flb-storage/
          storage.sync              normal
          storage.checksum          off
          storage.backlog.mem_limit 5M

      [INPUT]
          Name                tail
          Path                /var/log/containers/*.log
          multiline.parser    docker, cri
          Tag                 kube.*
          Mem_Buf_Limit       50MB
          Skip_Long_Lines     On

      [INPUT]
          Name                tail
          Path                /var/log/aws-routed-eni/ipamd.log
          Parser              aws_vpc_log
          Tag                 aws.vpc.log
          Mem_Buf_Limit       5MB
          Skip_Long_Lines     On

      [FILTER]
          Name                kubernetes
          Match               kube.*
          Kube_URL            https://kubernetes.default.svc:443
          Kube_Tag_Prefix     kube.var.log.containers.
          Merge_Log           On
          Merge_Log_Key       log_processed
          K8S-Logging.Parser  On
          K8S-Logging.Exclude Off
          Annotations         Off
          Labels              On

      [OUTPUT]
          Name                cloudwatch_logs
          Match               kube.*
          region              ${var.aws_region}
          log_group_name      /aws/containerinsights/${local.cluster_name}/application
          log_stream_prefix   $${kubernetes['namespace_name']}-
          auto_create_group   On
          extra_user_agent    container-insights

      [OUTPUT]
          Name                cloudwatch_logs
          Match               aws.vpc.log
          region              ${var.aws_region}
          log_group_name      /aws/containerinsights/${local.cluster_name}/dataplane
          log_stream_name     $${hostname}
          auto_create_group   On
          extra_user_agent    container-insights
    EOF

    "parsers.conf" = <<-EOF
      [PARSER]
          Name                aws_vpc_log
          Format              regex
          Regex               ^(?<time>[^ ]*) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
          Time_Key            time
          Time_Format         %Y-%m-%dT%H:%M:%S.%L%z
    EOF
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

# DaemonSet for Fluent Bit
resource "kubernetes_daemonset" "fluent_bit" {
  metadata {
    name      = "fluent-bit"
    namespace = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
    
    labels = {
      k8s-app                         = "fluent-bit"
      version                         = "v1"
      "kubernetes.io/cluster-service" = "true"
    }
  }

  spec {
    selector {
      match_labels = {
        k8s-app = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          k8s-app                         = "fluent-bit"
          version                         = "v1"
          "kubernetes.io/cluster-service" = "true"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.cloudwatch_agent.metadata[0].name

        container {
          name  = "fluent-bit"
          image = var.fluent_bit_image

          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }

          env {
            name  = "CLUSTER_NAME"
            value = local.cluster_name
          }

          env {
            name = "HTTP_SERVER"
            value = "On"
          }

          env {
            name = "HTTP_PORT"
            value = "2020"
          }

          env {
            name = "READ_FROM_HEAD"
            value = "Off"
          }

          env {
            name = "READ_FROM_TAIL"
            value = "On"
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
            name = "HOSTNAME"
            value_from {
              field_ref {
                api_version = "v1"
                field_path  = "metadata.name"
              }
            }
          }

          env {
            name = "CI_VERSION"
            value = "k8s/1.3.9"
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
            name       = "fluentbitstate"
            mount_path = "/var/fluent-bit/state"
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
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
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
          name = "fluentbitstate"
          host_path {
            path = "/var/fluent-bit/state"
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
          name = "fluent-bit-config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config.metadata[0].name
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

  depends_on = [
    kubernetes_service_account.cloudwatch_agent,
    kubernetes_config_map.fluent_bit_config
  ]
}

# =====================================================
# CloudWatch Alarms for EKS Monitoring
# =====================================================

# CloudWatch alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "EKS-${local.cluster_name}-HighCPU"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors EKS cluster CPU utilization"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  alarm_actions = [aws_sns_topic.eks_monitoring_alerts.arn]
  ok_actions    = [aws_sns_topic.eks_monitoring_alerts.arn]

  tags = local.common_tags
}

# CloudWatch alarm for high memory utilization
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "EKS-${local.cluster_name}-HighMemory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  alarm_description   = "This metric monitors EKS cluster memory utilization"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  alarm_actions = [aws_sns_topic.eks_monitoring_alerts.arn]
  ok_actions    = [aws_sns_topic.eks_monitoring_alerts.arn]

  tags = local.common_tags
}

# CloudWatch alarm for failed pods
resource "aws_cloudwatch_metric_alarm" "failed_pods" {
  alarm_name          = "EKS-${local.cluster_name}-FailedPods"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "cluster_failed_node_count"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "This metric monitors failed pods in the EKS cluster"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  alarm_actions = [aws_sns_topic.eks_monitoring_alerts.arn]
  ok_actions    = [aws_sns_topic.eks_monitoring_alerts.arn]

  tags = local.common_tags
}

# CloudWatch Log Groups with retention policy
resource "aws_cloudwatch_log_group" "container_insights_application" {
  name              = "/aws/containerinsights/${local.cluster_name}/application"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "container_insights_dataplane" {
  name              = "/aws/containerinsights/${local.cluster_name}/dataplane"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "container_insights_host" {
  name              = "/aws/containerinsights/${local.cluster_name}/host"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "container_insights_performance" {
  name              = "/aws/containerinsights/${local.cluster_name}/performance"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}