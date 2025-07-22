# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique names using random suffix
  random_suffix = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  
  # Resource names
  eks_cluster_name     = var.eks_cluster_name != "" ? var.eks_cluster_name : "${var.project_name}-eks-${local.random_suffix}"
  ecs_cluster_name     = var.ecs_cluster_name != "" ? var.ecs_cluster_name : "${var.project_name}-ecs-${local.random_suffix}"
  opensearch_domain    = "${var.project_name}-logs-${local.random_suffix}"
  
  # Common tags
  common_tags = merge({
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }, var.additional_tags)
}

# =========================================
# VPC and Networking
# =========================================

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc-${local.random_suffix}"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Enable VPC Flow Logs for network monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_destination_type            = "cloud-watch-logs"

  # Tags for EKS cluster discovery
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                          = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"                 = "1"
  }

  tags = local.common_tags
}

# =========================================
# EKS Cluster with Enhanced Observability
# =========================================

module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.eks_cluster_name
  cluster_version = var.eks_cluster_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Enable cluster logging for all log types
  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Enable OIDC for service accounts
  enable_oidc_provider = true

  # EKS Managed Node Group
  eks_managed_node_groups = {
    observability_nodes = {
      name = "observability-nodes"

      instance_types = [var.eks_node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.eks_node_group_min_size
      max_size     = var.eks_node_group_max_size
      desired_size = var.eks_node_group_desired_size

      disk_size = var.eks_node_disk_size

      labels = {
        Environment = var.environment
        Role        = "observability"
      }

      tags = {
        Environment = var.environment
        Monitoring  = "enabled"
      }

      # Enable detailed monitoring
      enable_monitoring = true

      # IAM role for worker nodes with observability permissions
      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        XRayDaemonWriteAccess      = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
      }
    }
  }

  # EKS Addons
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

  tags = local.common_tags
}

# =========================================
# ECS Cluster with Container Insights
# =========================================

resource "aws_ecs_cluster" "main" {
  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_cluster.name
      }
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# =========================================
# CloudWatch Log Groups
# =========================================

resource "aws_cloudwatch_log_group" "eks_application" {
  name              = "/aws/eks/${local.eks_cluster_name}/application"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "ecs_application" {
  name              = "/aws/ecs/${local.ecs_cluster_name}/application"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "ecs_cluster" {
  name              = "/aws/ecs/${local.ecs_cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "container_insights" {
  name              = "/aws/containerinsights/${local.eks_cluster_name}/application"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# =========================================
# SNS Topic for Alerts
# =========================================

resource "aws_sns_topic" "container_alerts" {
  name = "container-observability-alerts-${local.random_suffix}"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.alert_email != "admin@example.com" ? 1 : 0

  topic_arn = aws_sns_topic.container_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# =========================================
# Service Accounts for Observability
# =========================================

module "aws_load_balancer_controller_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "aws-load-balancer-controller-${local.random_suffix}"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}

module "cloudwatch_observability_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "cloudwatch-observability-${local.random_suffix}"

  role_policy_arns = {
    CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:cloudwatch-agent"]
    }
  }

  tags = local.common_tags
}

module "adot_collector_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "adot-collector-${local.random_suffix}"

  role_policy_arns = {
    CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    XRayDaemonWriteAccess      = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.monitoring_namespace}:adot-collector"]
    }
  }

  tags = local.common_tags
}

# =========================================
# Kubernetes Namespaces
# =========================================

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
    labels = {
      name = var.monitoring_namespace
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
    labels = {
      name = "amazon-cloudwatch"
    }
  }

  depends_on = [module.eks]
}

# =========================================
# Container Insights with Enhanced Observability
# =========================================

resource "kubectl_manifest" "container_insights_configmap" {
  count = var.enable_container_insights ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/container-insights-config.yaml", {
    cluster_name = local.eks_cluster_name
    region       = var.aws_region
    log_group    = aws_cloudwatch_log_group.container_insights.name
  })

  depends_on = [kubernetes_namespace.amazon_cloudwatch]
}

resource "kubectl_manifest" "container_insights_daemonset" {
  count = var.enable_container_insights ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/container-insights-daemonset.yaml", {
    cluster_name = local.eks_cluster_name
    region       = var.aws_region
    role_arn     = module.cloudwatch_observability_irsa_role.iam_role_arn
  })

  depends_on = [
    kubernetes_namespace.amazon_cloudwatch,
    kubectl_manifest.container_insights_configmap[0]
  ]
}

# =========================================
# Prometheus and Grafana Stack
# =========================================

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = "23.4.0"
  namespace  = var.monitoring_namespace

  values = [
    templatefile("${path.module}/templates/prometheus-values.yaml", {
      cluster_name           = local.eks_cluster_name
      storage_size          = var.prometheus_storage_size
      retention_days        = "${var.log_retention_days}d"
      enable_persistence    = var.enable_prometheus_persistence
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "6.58.7"
  namespace  = var.monitoring_namespace

  values = [
    templatefile("${path.module}/templates/grafana-values.yaml", {
      admin_password     = var.grafana_admin_password
      storage_size       = var.grafana_storage_size
      region             = var.aws_region
      cluster_name       = local.eks_cluster_name
      ecs_cluster_name   = local.ecs_cluster_name
      enable_loadbalancer = var.enable_grafana_lb
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.prometheus
  ]
}

# =========================================
# AWS Distro for OpenTelemetry (ADOT)
# =========================================

resource "kubectl_manifest" "adot_operator" {
  count = var.enable_adot_collector ? 1 : 0

  yaml_body = data.http.adot_operator.response_body

  depends_on = [module.eks]
}

data "http" "adot_operator" {
  url = "https://github.com/aws-observability/aws-otel-operator/releases/latest/download/opentelemetry-operator.yaml"
}

resource "kubectl_manifest" "adot_collector" {
  count = var.enable_adot_collector ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/adot-collector.yaml", {
    cluster_name         = local.eks_cluster_name
    region               = var.aws_region
    namespace            = var.monitoring_namespace
    collection_interval  = var.adot_collection_interval
    role_arn            = module.adot_collector_irsa_role.iam_role_arn
  })

  depends_on = [
    kubernetes_namespace.monitoring,
    kubectl_manifest.adot_operator[0]
  ]
}

# =========================================
# ECS Task Definition and Service
# =========================================

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_cloudwatch_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
  role       = aws_iam_role.ecs_task_execution_role.name
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_xray_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# ECS Task Definition
resource "aws_ecs_task_definition" "observability_demo" {
  family                   = "observability-demo-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "app"
      image = "nginx:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          protocol     = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_application.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
      environment = [
        {
          name  = "AWS_XRAY_TRACING_NAME"
          value = "ecs-observability-demo"
        }
      ]
    },
    {
      name  = "aws-otel-collector"
      image = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
      essential = false
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_application.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "otel-collector"
        }
      }
      environment = [
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]
    }
  ])

  tags = local.common_tags
}

# ECS Service
resource "aws_ecs_service" "observability_demo" {
  name            = "observability-demo-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.observability_demo.arn
  desired_count   = var.ecs_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  tags = local.common_tags
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-${local.random_suffix}"
  description = "Security group for ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# =========================================
# CloudWatch Alarms and Anomaly Detection
# =========================================

# CPU Utilization Alarm for EKS
resource "aws_cloudwatch_metric_alarm" "eks_high_cpu" {
  alarm_name          = "EKS-High-CPU-Utilization-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "pod_cpu_utilization"
  namespace           = "AWS/ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors EKS pod CPU utilization"
  alarm_actions       = [aws_sns_topic.container_alerts.arn]
  ok_actions          = [aws_sns_topic.container_alerts.arn]

  dimensions = {
    ClusterName = local.eks_cluster_name
  }

  tags = local.common_tags
}

# Memory Utilization Alarm for EKS
resource "aws_cloudwatch_metric_alarm" "eks_high_memory" {
  alarm_name          = "EKS-High-Memory-Utilization-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "pod_memory_utilization"
  namespace           = "AWS/ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_threshold
  alarm_description   = "This metric monitors EKS pod memory utilization"
  alarm_actions       = [aws_sns_topic.container_alerts.arn]

  dimensions = {
    ClusterName = local.eks_cluster_name
  }

  tags = local.common_tags
}

# ECS Service Unhealthy Tasks Alarm
resource "aws_cloudwatch_metric_alarm" "ecs_unhealthy_tasks" {
  alarm_name          = "ECS-Service-Unhealthy-Tasks-${local.random_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors ECS running task count"
  alarm_actions       = [aws_sns_topic.container_alerts.arn]

  dimensions = {
    ServiceName = aws_ecs_service.observability_demo.name
    ClusterName = local.ecs_cluster_name
  }

  tags = local.common_tags
}

# Anomaly Detection for CPU
resource "aws_cloudwatch_anomaly_detector" "cpu_anomaly" {
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      return_data = true
      metric_stat {
        metric {
          metric_name = "pod_cpu_utilization"
          namespace   = "AWS/ContainerInsights"
          dimensions = {
            ClusterName = local.eks_cluster_name
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# Anomaly Detection for Memory
resource "aws_cloudwatch_anomaly_detector" "memory_anomaly" {
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      return_data = true
      metric_stat {
        metric {
          metric_name = "pod_memory_utilization"
          namespace   = "AWS/ContainerInsights"
          dimensions = {
            ClusterName = local.eks_cluster_name
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# CPU Anomaly Detection Alarm
resource "aws_cloudwatch_metric_alarm" "cpu_anomaly_alarm" {
  alarm_name          = "EKS-CPU-Anomaly-Detection-${local.random_suffix}"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = "2"
  threshold_metric_id = "ad1"
  alarm_description   = "This metric monitors CPU utilization anomalies"
  alarm_actions       = [aws_sns_topic.container_alerts.arn]

  metric_query {
    id          = "m1"
    return_data = true
    metric {
      metric_name = "pod_cpu_utilization"
      namespace   = "AWS/ContainerInsights"
      dimensions = {
        ClusterName = local.eks_cluster_name
      }
      period = 300
      stat   = "Average"
    }
  }

  metric_query {
    id          = "ad1"
    expression  = "ANOMALY_DETECTION_FUNCTION(m1, ${var.anomaly_threshold})"
    return_data = true
  }

  tags = local.common_tags
}

# =========================================
# CloudWatch Dashboard
# =========================================

resource "aws_cloudwatch_dashboard" "container_observability" {
  dashboard_name = "Container-Observability-${local.random_suffix}"

  dashboard_body = templatefile("${path.module}/templates/dashboard.json", {
    region           = var.aws_region
    eks_cluster_name = local.eks_cluster_name
    ecs_cluster_name = local.ecs_cluster_name
    ecs_service_name = aws_ecs_service.observability_demo.name
  })

  depends_on = [
    module.eks,
    aws_ecs_cluster.main
  ]
}

# =========================================
# OpenSearch Domain (Optional)
# =========================================

resource "aws_opensearch_domain" "container_logs" {
  count = var.enable_opensearch ? 1 : 0

  domain_name    = local.opensearch_domain
  engine_version = "OpenSearch_2.3"

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_volume_size
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https = true
  }

  advanced_security_options {
    enabled = true
    anonymous_auth_enabled = false
    internal_user_database_enabled = true
    master_user_options {
      master_user_name     = "admin"
      master_user_password = var.grafana_admin_password
    }
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "es:*"
        Principal = "*"
        Effect = "Allow"
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain}/*"
      }
    ]
  })

  tags = local.common_tags
}

# =========================================
# Performance Optimization Lambda
# =========================================

resource "aws_lambda_function" "performance_optimizer" {
  count = var.enable_automated_optimization ? 1 : 0

  filename         = data.archive_file.performance_optimizer[0].output_path
  function_name    = "container-performance-optimizer-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution_role[0].arn
  handler         = "performance_optimizer.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.optimization_lambda_timeout
  source_code_hash = data.archive_file.performance_optimizer[0].output_base64sha256

  environment {
    variables = {
      EKS_CLUSTER_NAME = local.eks_cluster_name
      ECS_CLUSTER_NAME = local.ecs_cluster_name
      SNS_TOPIC_ARN    = aws_sns_topic.container_alerts.arn
    }
  }

  tags = local.common_tags
}

# Lambda function code
data "archive_file" "performance_optimizer" {
  count = var.enable_automated_optimization ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/performance_optimizer.zip"
  source {
    content = templatefile("${path.module}/templates/performance_optimizer.py", {
      eks_cluster_name = local.eks_cluster_name
      ecs_cluster_name = local.ecs_cluster_name
    })
    filename = "performance_optimizer.py"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_execution_role" {
  count = var.enable_automated_optimization ? 1 : 0

  name = "PerformanceOptimizerRole-${local.random_suffix}"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count = var.enable_automated_optimization ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role[0].name
}

resource "aws_iam_role_policy_attachment" "lambda_cloudwatch_read" {
  count = var.enable_automated_optimization ? 1 : 0

  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
  role       = aws_iam_role.lambda_execution_role[0].name
}

# EventBridge rule for performance analysis
resource "aws_cloudwatch_event_rule" "performance_analysis" {
  count = var.enable_automated_optimization ? 1 : 0

  name                = "container-performance-analysis-${local.random_suffix}"
  description         = "Trigger container performance optimization analysis"
  schedule_expression = var.performance_analysis_schedule

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "performance_analysis" {
  count = var.enable_automated_optimization ? 1 : 0

  rule      = aws_cloudwatch_event_rule.performance_analysis[0].name
  target_id = "PerformanceOptimizationTarget"
  arn       = aws_lambda_function.performance_optimizer[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_automated_optimization ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.performance_optimizer[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.performance_analysis[0].arn
}