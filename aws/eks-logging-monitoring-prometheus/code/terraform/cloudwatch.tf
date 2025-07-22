# CloudWatch resources for EKS cluster monitoring and alerting

# CloudWatch Dashboard for EKS cluster observability
resource "aws_cloudwatch_dashboard" "eks_observability" {
  dashboard_name = "${local.cluster_name_unique}-observability"

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
            ["ContainerInsights", "cluster_node_count", "ClusterName", local.cluster_name_unique],
            [".", "cluster_node_running_count", ".", "."],
            [".", "cluster_node_failed_count", ".", "."]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "EKS Cluster Node Status"
          period    = 300
          stat      = "Average"
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
            ["ContainerInsights", "cluster_running_count", "ClusterName", local.cluster_name_unique],
            [".", "cluster_pending_count", ".", "."],
            [".", "cluster_failed_count", ".", "."]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "EKS Cluster Pod Status"
          period    = 300
          stat      = "Average"
          yAxis = {
            left = {
              min = 0
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
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", local.cluster_name_unique],
            [".", "node_memory_utilization", ".", "."],
            [".", "node_filesystem_utilization", ".", "."]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "Node Resource Utilization"
          period    = 300
          stat      = "Average"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '/aws/eks/${local.cluster_name_unique}/cluster' | fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "EKS Control Plane Errors"
          view   = "table"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", local.cluster_name_unique],
            [".", "pod_memory_utilization", ".", "."]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = data.aws_region.current.name
          title     = "Pod Resource Utilization"
          period    = 300
          stat      = "Average"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '/aws/containerinsights/${local.cluster_name_unique}/application' | fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Application Pod Errors"
          view   = "table"
        }
      }
    ]
  })

  tags = local.common_tags
}

# CloudWatch Alarms for EKS cluster monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cluster_name_unique}-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_utilization_threshold
  alarm_description   = "This metric monitors CPU utilization in the EKS cluster"
  alarm_actions       = var.enable_sns_alerts ? [aws_sns_topic.cloudwatch_alarms[0].arn] : []

  dimensions = {
    ClusterName = local.cluster_name_unique
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_memory_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cluster_name_unique}-high-memory-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_utilization_threshold
  alarm_description   = "This metric monitors memory utilization in the EKS cluster"
  alarm_actions       = var.enable_sns_alerts ? [aws_sns_topic.cloudwatch_alarms[0].arn] : []

  dimensions = {
    ClusterName = local.cluster_name_unique
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "high_failed_pods" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cluster_name_unique}-high-failed-pods"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "cluster_failed_count"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.failed_pods_threshold
  alarm_description   = "This metric monitors the number of failed pods in the EKS cluster"
  alarm_actions       = var.enable_sns_alerts ? [aws_sns_topic.cloudwatch_alarms[0].arn] : []

  dimensions = {
    ClusterName = local.cluster_name_unique
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "node_not_ready" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${local.cluster_name_unique}-node-not-ready"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_node_running_count"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.node_group_config.scaling_config.min_size
  alarm_description   = "This metric monitors the number of ready nodes in the EKS cluster"
  alarm_actions       = var.enable_sns_alerts ? [aws_sns_topic.cloudwatch_alarms[0].arn] : []

  dimensions = {
    ClusterName = local.cluster_name_unique
  }

  tags = local.common_tags
}

# CloudWatch Composite Alarm for overall cluster health
resource "aws_cloudwatch_composite_alarm" "cluster_health" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name        = "${local.cluster_name_unique}-cluster-health"
  alarm_description = "Composite alarm for overall EKS cluster health"
  
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.high_cpu_utilization[0].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.high_memory_utilization[0].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.high_failed_pods[0].alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.node_not_ready[0].alarm_name})"
  ])

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.cloudwatch_alarms[0].arn] : []

  tags = local.common_tags
}

# CloudWatch Log Insights saved queries
resource "aws_cloudwatch_query_definition" "eks_control_plane_errors" {
  count = var.monitoring_config.enable_logs_insights_queries ? 1 : 0

  name = "${local.cluster_name_unique}-control-plane-errors"
  
  log_group_names = [
    aws_cloudwatch_log_group.cluster_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
EOF
}

resource "aws_cloudwatch_query_definition" "eks_authentication_failures" {
  count = var.monitoring_config.enable_logs_insights_queries ? 1 : 0

  name = "${local.cluster_name_unique}-authentication-failures"
  
  log_group_names = [
    aws_cloudwatch_log_group.cluster_logs.name
  ]

  query_string = <<EOF
fields @timestamp, @message
| filter @message like /authentication failed/
| sort @timestamp desc
| limit 50
EOF
}

resource "aws_cloudwatch_query_definition" "application_pod_errors" {
  count = var.monitoring_config.enable_logs_insights_queries ? 1 : 0

  name = "${local.cluster_name_unique}-application-errors"
  
  log_group_names = [
    aws_cloudwatch_log_group.container_insights_application.name
  ]

  query_string = <<EOF
fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50
EOF
}

resource "aws_cloudwatch_query_definition" "pod_restart_analysis" {
  count = var.monitoring_config.enable_logs_insights_queries ? 1 : 0

  name = "${local.cluster_name_unique}-pod-restarts"
  
  log_group_names = [
    aws_cloudwatch_log_group.container_insights_application.name
  ]

  query_string = <<EOF
fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, @message
| filter @message like /restart/
| stats count() by kubernetes.namespace_name, kubernetes.pod_name
| sort count desc
| limit 20
EOF
}

resource "aws_cloudwatch_query_definition" "resource_usage_analysis" {
  count = var.monitoring_config.enable_logs_insights_queries ? 1 : 0

  name = "${local.cluster_name_unique}-resource-usage"
  
  log_group_names = [
    aws_cloudwatch_log_group.container_insights_application.name
  ]

  query_string = <<EOF
fields @timestamp, kubernetes.namespace_name, kubernetes.pod_name, @message
| filter @message like /OOM/ or @message like /memory/
| sort @timestamp desc
| limit 50
EOF
}