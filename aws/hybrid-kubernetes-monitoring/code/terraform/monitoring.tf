# ==============================================================================
# CLOUDWATCH DASHBOARDS
# ==============================================================================

# Main CloudWatch dashboard for hybrid EKS monitoring
resource "aws_cloudwatch_dashboard" "hybrid_monitoring" {
  count = var.cloudwatch_dashboard_enabled ? 1 : 0

  dashboard_name = "EKS-Hybrid-Monitoring-${local.cluster_name}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EKS", "cluster_node_count", "ClusterName", local.cluster_name],
            [local.cloudwatch_namespace, "HybridNodeCount"],
            [".", "FargatePodCount"],
            [".", "TotalPodCount"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Hybrid Cluster Capacity"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "pod_cpu_utilization", "ClusterName", local.cluster_name],
            [".", "pod_memory_utilization", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Pod Resource Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "cluster_node_count", "ClusterName", local.cluster_name],
            [".", "cluster_failed_node_count", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Cluster Node Status"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "pod_running", "ClusterName", local.cluster_name],
            [".", "pod_pending", ".", "."],
            [".", "pod_failed", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Pod Status Distribution"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          query = join("\n", [
            "SOURCE '/aws/containerinsights/${local.cluster_name}/application'",
            "| fields @timestamp, kubernetes.pod_name, log",
            "| filter kubernetes.namespace_name = \"cloud-apps\"",
            "| sort @timestamp desc",
            "| limit 100"
          ])
          region = data.aws_region.current.name
          title  = "Application Logs from Cloud Apps"
          view   = "table"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "namespace_number_of_running_pods", "ClusterName", local.cluster_name, "Namespace", "cloud-apps"],
            [".", ".", ".", ".", ".", "kube-system"],
            [".", ".", ".", ".", ".", "amazon-cloudwatch"]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Pods by Namespace"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/ContainerInsights", "cluster_memory_utilization", "ClusterName", local.cluster_name],
            [".", "cluster_cpu_utilization", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Cluster Resource Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "EKS-Hybrid-Monitoring-Dashboard"
  })
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

# High CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "EKS-Hybrid-HighCPU-${local.cluster_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "pod_cpu_utilization"
  namespace           = "AWS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.high_cpu_threshold
  alarm_description   = "High CPU utilization detected in hybrid EKS cluster ${local.cluster_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions          = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = merge(local.common_tags, {
    Name = "EKS-Hybrid-HighCPU-Alarm"
  })
}

# High memory utilization alarm
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "EKS-Hybrid-HighMemory-${local.cluster_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "pod_memory_utilization"
  namespace           = "AWS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.high_memory_threshold
  alarm_description   = "High memory utilization detected in hybrid EKS cluster ${local.cluster_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions          = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = merge(local.common_tags, {
    Name = "EKS-Hybrid-HighMemory-Alarm"
  })
}

# Low hybrid node count alarm
resource "aws_cloudwatch_metric_alarm" "low_hybrid_nodes" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "EKS-Hybrid-LowNodeCount-${local.cluster_name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HybridNodeCount"
  namespace           = local.cloudwatch_namespace
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Low hybrid node count detected in EKS cluster ${local.cluster_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions          = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  treat_missing_data  = "breaching"

  tags = merge(local.common_tags, {
    Name = "EKS-Hybrid-LowNodeCount-Alarm"
  })
}

# Failed pods alarm
resource "aws_cloudwatch_metric_alarm" "failed_pods" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "EKS-Hybrid-FailedPods-${local.cluster_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "pod_failed"
  namespace           = "AWS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "Failed pods detected in hybrid EKS cluster ${local.cluster_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions          = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = merge(local.common_tags, {
    Name = "EKS-Hybrid-FailedPods-Alarm"
  })
}

# Cluster node count alarm
resource "aws_cloudwatch_metric_alarm" "cluster_node_count" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "EKS-Hybrid-ClusterNodeCount-${local.cluster_name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "cluster_node_count"
  namespace           = "AWS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Low cluster node count in hybrid EKS cluster ${local.cluster_name}"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  ok_actions          = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = local.cluster_name
  }

  tags = merge(local.common_tags, {
    Name = "EKS-Hybrid-ClusterNodeCount-Alarm"
  })
}

# ==============================================================================
# CUSTOM METRICS COLLECTION
# ==============================================================================

# IAM role for custom metrics collection
data "aws_iam_policy_document" "custom_metrics_assume_role" {
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
      values   = ["system:serviceaccount:cloud-apps:hybrid-metrics-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "custom_metrics" {
  name               = "${local.cluster_name}-custom-metrics-role"
  assume_role_policy = data.aws_iam_policy_document.custom_metrics_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-custom-metrics-role"
  })
}

# Custom policy for CloudWatch metrics publishing
resource "aws_iam_policy" "custom_metrics" {
  name        = "${local.cluster_name}-custom-metrics-policy"
  description = "Policy for publishing custom metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = local.cloudwatch_namespace
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-custom-metrics-policy"
  })
}

resource "aws_iam_role_policy_attachment" "custom_metrics" {
  policy_arn = aws_iam_policy.custom_metrics.arn
  role       = aws_iam_role.custom_metrics.name
}

# Service account for custom metrics collection
resource "kubernetes_service_account" "custom_metrics" {
  count = var.deploy_sample_applications ? 1 : 0

  metadata {
    name      = "hybrid-metrics-sa"
    namespace = kubernetes_namespace.cloud_apps[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.custom_metrics.arn
    }
  }

  depends_on = [
    aws_iam_role.custom_metrics,
    kubernetes_namespace.cloud_apps
  ]
}

# ConfigMap for custom metrics collection script
resource "kubernetes_config_map" "metrics_script" {
  count = var.deploy_sample_applications ? 1 : 0

  metadata {
    name      = "metrics-collection-script"
    namespace = kubernetes_namespace.cloud_apps[0].metadata[0].name
  }

  data = {
    "collect-metrics.sh" = <<-EOF
      #!/bin/bash
      set -e
      
      echo "Collecting hybrid cluster metrics..."
      
      # Get hybrid node count (simulated for demo - in real scenario would query actual hybrid nodes)
      HYBRID_NODES=0
      
      # Get Fargate pod count
      FARGATE_PODS=$(kubectl get pods -A -o jsonpath='{.items[?(@.spec.nodeName)].spec.nodeName}' | tr ' ' '\n' | grep -c fargate || echo 0)
      
      # Get total pod count
      TOTAL_PODS=$(kubectl get pods -A --no-headers | wc -l)
      
      # Get running pods per namespace
      CLOUD_APPS_PODS=$(kubectl get pods -n cloud-apps --no-headers 2>/dev/null | wc -l || echo 0)
      
      echo "Publishing metrics to CloudWatch..."
      
      # Publish metrics to CloudWatch
      aws cloudwatch put-metric-data \
        --region ${data.aws_region.current.name} \
        --namespace ${local.cloudwatch_namespace} \
        --metric-data \
          MetricName=HybridNodeCount,Value=$HYBRID_NODES,Unit=Count \
          MetricName=FargatePodCount,Value=$FARGATE_PODS,Unit=Count \
          MetricName=TotalPodCount,Value=$TOTAL_PODS,Unit=Count \
          MetricName=CloudAppsPodCount,Value=$CLOUD_APPS_PODS,Unit=Count
      
      echo "Metrics published successfully"
    EOF
  }

  depends_on = [kubernetes_namespace.cloud_apps]
}

# CronJob for custom metrics collection
resource "kubernetes_cron_job_v1" "custom_metrics_collector" {
  count = var.deploy_sample_applications ? 1 : 0

  metadata {
    name      = "hybrid-metrics-collector"
    namespace = kubernetes_namespace.cloud_apps[0].metadata[0].name
  }

  spec {
    schedule = "*/5 * * * *"

    job_template {
      metadata {
        labels = {
          app = "metrics-collector"
        }
      }

      spec {
        template {
          metadata {
            labels = {
              app = "metrics-collector"
            }
          }

          spec {
            service_account_name = kubernetes_service_account.custom_metrics[0].metadata[0].name
            restart_policy       = "OnFailure"

            container {
              name    = "metrics-collector"
              image   = "public.ecr.aws/aws-cli/aws-cli:latest"
              command = ["/bin/bash", "/scripts/collect-metrics.sh"]

              volume_mount {
                name       = "metrics-script"
                mount_path = "/scripts"
              }

              env {
                name  = "AWS_REGION"
                value = data.aws_region.current.name
              }

              env {
                name  = "CLUSTER_NAME"
                value = local.cluster_name
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
            }

            volume {
              name = "metrics-script"
              config_map {
                name         = kubernetes_config_map.metrics_script[0].metadata[0].name
                default_mode = "0755"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.custom_metrics,
    kubernetes_config_map.metrics_script
  ]
}

# ==============================================================================
# LOG INSIGHTS QUERIES
# ==============================================================================

# CloudWatch Logs Insights query for application errors
resource "aws_cloudwatch_query_definition" "application_errors" {
  count = var.cloudwatch_dashboard_enabled ? 1 : 0

  name = "EKS-Hybrid-Application-Errors-${local.cluster_name}"

  log_group_names = [
    "/aws/containerinsights/${local.cluster_name}/application"
  ]

  query_string = <<EOF
fields @timestamp, kubernetes.pod_name, kubernetes.namespace_name, log
| filter log like /ERROR/ or log like /FATAL/ or log like /Exception/
| sort @timestamp desc
| limit 100
EOF
}

# CloudWatch Logs Insights query for pod restarts
resource "aws_cloudwatch_query_definition" "pod_restarts" {
  count = var.cloudwatch_dashboard_enabled ? 1 : 0

  name = "EKS-Hybrid-Pod-Restarts-${local.cluster_name}"

  log_group_names = [
    "/aws/containerinsights/${local.cluster_name}/host"
  ]

  query_string = <<EOF
fields @timestamp, kubernetes.pod_name, kubernetes.namespace_name
| filter kubernetes.container_name = "POD"
| filter log like /Started container/ or log like /Stopped container/
| sort @timestamp desc
| limit 100
EOF
}