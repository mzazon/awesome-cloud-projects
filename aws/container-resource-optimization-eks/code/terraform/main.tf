# Main Terraform configuration for EKS Container Resource Optimization
# This file creates the infrastructure needed for automated container right-sizing using VPA

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = "EKS-Cost-Optimization"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "container-resource-optimization-right-sizing"
    },
    var.tags
  )
  
  # Unique suffix for resource names
  suffix = random_id.suffix.hex
}

# Data sources for existing EKS cluster
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# Create namespace for cost optimization workloads
resource "kubernetes_namespace" "cost_optimization" {
  metadata {
    name = var.namespace_name
    
    labels = {
      name        = var.namespace_name
      environment = var.environment
      purpose     = "cost-optimization"
    }
    
    annotations = {
      "cost-optimization/managed-by" = "terraform"
      "cost-optimization/created"    = timestamp()
    }
  }
}

# Deploy Kubernetes Metrics Server using Helm
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.11.0"

  set {
    name  = "replicas"
    value = var.metrics_server_replicas
  }

  set {
    name  = "args"
    value = "{--cert-dir=/tmp,--secure-port=4443,--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname,--kubelet-use-node-status-port,--metric-resolution=15s}"
  }

  # Resource requests and limits for cost optimization
  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "200Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "resources.limits.memory"
    value = "2000Mi"
  }

  depends_on = [kubernetes_namespace.cost_optimization]
}

# Deploy Vertical Pod Autoscaler using Helm
resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  namespace  = "kube-system"
  version    = "4.5.0"

  # Enable all VPA components
  set {
    name  = "recommender.enabled"
    value = "true"
  }

  set {
    name  = "updater.enabled"
    value = "true"
  }

  set {
    name  = "admissionController.enabled"
    value = "true"
  }

  # Configure resource settings for VPA components
  set {
    name  = "recommender.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "recommender.resources.requests.memory"
    value = "500Mi"
  }

  set {
    name  = "recommender.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "recommender.resources.limits.memory"
    value = "1000Mi"
  }

  set {
    name  = "updater.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "updater.resources.requests.memory"
    value = "500Mi"
  }

  set {
    name  = "updater.resources.limits.cpu"
    value = "1000m"
  }

  set {
    name  = "updater.resources.limits.memory"
    value = "1000Mi"
  }

  set {
    name  = "admissionController.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "admissionController.resources.requests.memory"
    value = "200Mi"
  }

  set {
    name  = "admissionController.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "admissionController.resources.limits.memory"
    value = "500Mi"
  }

  depends_on = [helm_release.metrics_server]
}

# Create test application deployment (conditionally)
resource "kubernetes_deployment" "test_app" {
  count = var.create_test_application ? 1 : 0

  metadata {
    name      = "resource-test-app"
    namespace = kubernetes_namespace.cost_optimization.metadata[0].name
    
    labels = {
      app         = "resource-test-app"
      environment = var.environment
      purpose     = "cost-optimization-testing"
    }
  }

  spec {
    replicas = var.test_app_replicas

    selector {
      match_labels = {
        app = "resource-test-app"
      }
    }

    template {
      metadata {
        labels = {
          app         = "resource-test-app"
          environment = var.environment
          purpose     = "cost-optimization-testing"
        }
      }

      spec {
        container {
          name  = "app"
          image = "nginx:1.20"

          port {
            container_port = 80
          }

          # Intentionally overprovisioned resources for demonstration
          resources {
            requests = {
              cpu    = var.test_app_cpu_request
              memory = var.test_app_memory_request
            }
            limits = {
              cpu    = var.test_app_cpu_limit
              memory = var.test_app_memory_limit
            }
          }

          # Add some load generation for realistic testing
          command = ["/bin/sh"]
          args    = ["-c", "while true; do echo 'Load test'; sleep 30; done & nginx -g 'daemon off;'"]

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
      }
    }
  }

  depends_on = [kubernetes_namespace.cost_optimization]
}

# Create service for test application
resource "kubernetes_service" "test_app" {
  count = var.create_test_application ? 1 : 0

  metadata {
    name      = "resource-test-app"
    namespace = kubernetes_namespace.cost_optimization.metadata[0].name
    
    labels = {
      app = "resource-test-app"
    }
  }

  spec {
    selector = {
      app = "resource-test-app"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment.test_app]
}

# Create VPA policy for test application (recommendation mode)
resource "kubectl_manifest" "vpa_policy_recommendation" {
  count = var.create_test_application ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      name      = "resource-test-app-vpa"
      namespace = kubernetes_namespace.cost_optimization.metadata[0].name
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = "resource-test-app"
      }
      updatePolicy = {
        updateMode = var.vpa_update_mode
      }
      resourcePolicy = {
        containerPolicies = [
          {
            containerName = "app"
            minAllowed = {
              cpu    = var.vpa_min_cpu
              memory = var.vpa_min_memory
            }
            maxAllowed = {
              cpu    = var.vpa_max_cpu
              memory = var.vpa_max_memory
            }
            controlledResources = ["cpu", "memory"]
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.vpa,
    kubernetes_deployment.test_app
  ]
}

# Create VPA policy for automated updates (if enabled)
resource "kubectl_manifest" "vpa_policy_auto" {
  count = var.create_test_application && var.enable_vpa_auto_mode ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      name      = "resource-test-app-vpa-auto"
      namespace = kubernetes_namespace.cost_optimization.metadata[0].name
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = "resource-test-app"
      }
      updatePolicy = {
        updateMode = "Auto"
      }
      resourcePolicy = {
        containerPolicies = [
          {
            containerName = "app"
            minAllowed = {
              cpu    = var.vpa_min_cpu
              memory = var.vpa_min_memory
            }
            maxAllowed = {
              cpu    = "500m"   # More conservative limits for auto mode
              memory = "512Mi"
            }
            controlledResources = ["cpu", "memory"]
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.vpa,
    kubernetes_deployment.test_app
  ]
}

# Enable CloudWatch Container Insights (conditionally)
resource "aws_eks_addon" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  
  # Use latest available version
  resolve_conflicts = "OVERWRITE"
  
  tags = local.common_tags
}

# CloudWatch namespace for Container Insights
resource "kubernetes_namespace" "amazon_cloudwatch" {
  count = var.enable_container_insights ? 1 : 0

  metadata {
    name = "amazon-cloudwatch"
    
    labels = {
      name = "amazon-cloudwatch"
    }
  }
}

# Deploy CloudWatch agent using Helm
resource "helm_release" "cloudwatch_agent" {
  count = var.enable_container_insights ? 1 : 0

  name       = "cloudwatch-agent"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-cloudwatch-metrics"
  namespace  = kubernetes_namespace.amazon_cloudwatch[0].metadata[0].name

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

# SNS topic for cost optimization alerts
resource "aws_sns_topic" "cost_alerts" {
  count = var.enable_cost_alerts ? 1 : 0

  name = "eks-cost-optimization-alerts-${local.suffix}"
  
  tags = local.common_tags
}

# SNS topic subscription (if email provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.enable_cost_alerts && var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.cost_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch dashboard for cost optimization monitoring
resource "aws_cloudwatch_dashboard" "cost_optimization" {
  count = var.enable_cost_dashboard ? 1 : 0

  dashboard_name = "EKS-Cost-Optimization-${local.suffix}"

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
            ["ContainerInsights", "pod_cpu_utilization", "Namespace", var.namespace_name],
            [".", "pod_memory_utilization", ".", "."],
            [".", "pod_cpu_reserved_capacity", ".", "."],
            [".", "pod_memory_reserved_capacity", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Resource Utilization vs Reserved Capacity"
          period  = 300
          stat    = "Average"
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
            ["ContainerInsights", "cluster_node_cpu_utilization", "ClusterName", var.cluster_name],
            [".", "cluster_node_memory_utilization", ".", "."],
            [".", "cluster_node_running_pod_count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Cluster Resource Utilization"
          period  = 300
          stat    = "Average"
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
            ["ContainerInsights", "pod_cpu_request", "Namespace", var.namespace_name],
            [".", "pod_memory_request", ".", "."],
            [".", "pod_cpu_usage", ".", "."],
            [".", "pod_memory_usage", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Resource Requests vs Actual Usage"
          period  = 300
          stat    = "Average"
        }
      }
    ]
  })

  tags = local.common_tags
}

# CloudWatch alarm for high resource waste
resource "aws_cloudwatch_metric_alarm" "high_resource_waste" {
  count = var.enable_cost_alerts ? 1 : 0

  alarm_name          = "EKS-High-Resource-Waste-${local.suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "pod_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cost_alert_threshold
  alarm_description   = "This metric monitors container resource utilization for cost optimization opportunities"
  alarm_actions       = var.enable_cost_alerts ? [aws_sns_topic.cost_alerts[0].arn] : []

  dimensions = {
    Namespace = var.namespace_name
  }

  tags = local.common_tags
}

# IAM role for Lambda cost optimization function
resource "aws_iam_role" "lambda_cost_optimization" {
  name = "eks-cost-optimization-lambda-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_cost_optimization" {
  name = "eks-cost-optimization-lambda-policy"
  role = aws_iam_role.lambda_cost_optimization.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_cost_alerts ? aws_sns_topic.cost_alerts[0].arn : "*"
      }
    ]
  })
}

# Lambda function for cost optimization automation
resource "aws_lambda_function" "cost_optimization" {
  filename      = "cost_optimization_lambda.zip"
  function_name = "eks-cost-optimization-${local.suffix}"
  role          = aws_iam_role.lambda_cost_optimization.arn
  handler       = "index.handler"
  runtime       = "python3.9"
  timeout       = 300

  environment {
    variables = {
      CLUSTER_NAME = var.cluster_name
      NAMESPACE    = var.namespace_name
      TOPIC_ARN    = var.enable_cost_alerts ? aws_sns_topic.cost_alerts[0].arn : ""
      THRESHOLD    = var.cost_alert_threshold
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.lambda_cost_optimization,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/eks-cost-optimization-${local.suffix}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# EventBridge rule to trigger Lambda function periodically
resource "aws_cloudwatch_event_rule" "cost_optimization_schedule" {
  name                = "eks-cost-optimization-schedule-${local.suffix}"
  description         = "Trigger cost optimization Lambda function every hour"
  schedule_expression = "rate(1 hour)"

  tags = local.common_tags
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.cost_optimization_schedule.name
  target_id = "CostOptimizationLambdaTarget"
  arn       = aws_lambda_function.cost_optimization.arn
}

# Permission for EventBridge to invoke Lambda function
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_optimization.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_optimization_schedule.arn
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "cost_optimization_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      topic_arn = var.enable_cost_alerts ? aws_sns_topic.cost_alerts[0].arn : ""
    })
    filename = "index.py"
  }
}

# ConfigMap for VPA recommendations script
resource "kubernetes_config_map" "vpa_scripts" {
  metadata {
    name      = "vpa-scripts"
    namespace = kubernetes_namespace.cost_optimization.metadata[0].name
  }

  data = {
    "generate-vpa-recommendations.sh" = templatefile("${path.module}/generate_vpa_recommendations.sh", {
      namespace = var.namespace_name
    })
  }

  depends_on = [kubernetes_namespace.cost_optimization]
}