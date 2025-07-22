# Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy
# This file contains the main infrastructure resources for implementing
# sophisticated blue-green deployment patterns with automated rollback capabilities

# ====================================
# Data Sources and Random Resources
# ====================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get subnets from VPC
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Local values for consistent naming and configuration
locals {
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Resource naming with random suffix
  project_name_with_suffix = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "advanced-blue-green-deployments"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# ====================================
# ECR Repository for Container Images
# ====================================

resource "aws_ecr_repository" "app_repository" {
  name                 = "${local.project_name_with_suffix}-web-app"
  image_tag_mutability = var.image_mutability

  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }

  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "app_repository_policy" {
  repository = aws_ecr_repository.app_repository.name

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
        description  = "Keep last 5 untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ====================================
# IAM Roles and Policies
# ====================================

# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.project_name_with_suffix}-ecs-execution-role"

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

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.project_name_with_suffix}-ecs-task-role"

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

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.project_name_with_suffix}-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodeDeploy Service Role
resource "aws_iam_role" "codedeploy_role" {
  name = "${local.project_name_with_suffix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "codedeploy_ecs_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

resource "aws_iam_role_policy_attachment" "codedeploy_lambda_policy" {
  role       = aws_iam_role.codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda"
}

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name = "${local.project_name_with_suffix}-lambda-role"

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
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Enhanced Lambda role for deployment hooks
resource "aws_iam_role_policy" "lambda_deployment_policy" {
  name = "${local.project_name_with_suffix}-lambda-deployment-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codedeploy:PutLifecycleEventHookExecutionStatus",
          "cloudwatch:PutMetricData",
          "ecs:DescribeServices",
          "ecs:DescribeTasks",
          "lambda:InvokeFunction",
          "elasticloadbalancing:DescribeTargetHealth"
        ]
        Resource = "*"
      }
    ]
  })
}

# ====================================
# Security Groups
# ====================================

# Security Group for Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name_prefix = "${local.project_name_with_suffix}-alb-"
  vpc_id      = local.vpc_id
  description = "Security group for Application Load Balancer"

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name_with_suffix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name_prefix = "${local.project_name_with_suffix}-ecs-"
  vpc_id      = local.vpc_id
  description = "Security group for ECS tasks"

  ingress {
    description     = "Traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name_with_suffix}-ecs-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ====================================
# Application Load Balancer
# ====================================

resource "aws_lb" "main" {
  name               = "${local.project_name_with_suffix}-alb"
  internal           = !var.enable_public_access
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = local.subnet_ids

  enable_deletion_protection = false
  idle_timeout              = var.alb_idle_timeout

  tags = local.common_tags
}

# Target Groups for Blue-Green Deployment
resource "aws_lb_target_group" "blue" {
  name        = "${local.project_name_with_suffix}-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold_count
    unhealthy_threshold = var.unhealthy_threshold_count
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name_with_suffix}-blue-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${local.project_name_with_suffix}-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold_count
    unhealthy_threshold = var.unhealthy_threshold_count
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name_with_suffix}-green-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [default_action]
  }
}

# ====================================
# ECS Cluster and Service
# ====================================

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.project_name_with_suffix}"
  retention_in_days = var.log_retention_in_days

  tags = local.common_tags
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.project_name_with_suffix}-cluster"

  capacity_providers = var.ecs_cluster_capacity_providers

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }

  setting {
    name  = "containerInsights"
    value = var.enable_detailed_monitoring ? "enabled" : "disabled"
  }

  tags = local.common_tags
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "${local.project_name_with_suffix}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "web-app"
      image = "${aws_ecr_repository.app_repository.repository_url}:${var.container_image_tag}"
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "APP_VERSION"
          value = var.initial_app_version
        },
        {
          name  = "ENVIRONMENT"
          value = "blue"
        },
        {
          name  = "PORT"
          value = tostring(var.container_port)
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${var.container_port}/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      essential = true
    }
  ])

  tags = local.common_tags
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "${local.project_name_with_suffix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = var.enable_public_access
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = "web-app"
    container_port   = var.container_port
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 50
  }

  enable_execute_command = true

  depends_on = [aws_lb_listener.main]

  tags = local.common_tags

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

# ====================================
# Lambda Function and Dependencies
# ====================================

# Create Lambda function package
data "archive_file" "lambda_function" {
  type        = "zip"
  output_path = "${path.module}/lambda-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda-function.py.tpl", {
      project_name = local.project_name_with_suffix
    })
    filename = "lambda-function.py"
  }
}

# Lambda Function
resource "aws_lambda_function" "api_function" {
  filename         = data.archive_file.lambda_function.output_path
  function_name    = "${local.project_name_with_suffix}-api-function"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda-function.lambda_handler"
  source_code_hash = data.archive_file.lambda_function.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      VERSION     = var.initial_app_version
      ENVIRONMENT = "blue"
    }
  }

  tags = local.common_tags
}

# Lambda Alias for Production
resource "aws_lambda_alias" "prod" {
  name             = "PROD"
  description      = "Production alias for blue-green deployments"
  function_name    = aws_lambda_function.api_function.function_name
  function_version = "$LATEST"

  depends_on = [aws_lambda_function.api_function]
}

# ====================================
# Lambda Deployment Hooks
# ====================================

# Pre-deployment validation hook
data "archive_file" "pre_deployment_hook" {
  type        = "zip"
  output_path = "${path.module}/pre-deployment-hook.zip"
  
  source {
    content = templatefile("${path.module}/pre-deployment-hook.py.tpl", {
      project_name = local.project_name_with_suffix
    })
    filename = "pre-deployment-hook.py"
  }
}

resource "aws_lambda_function" "pre_deployment_hook" {
  filename         = data.archive_file.pre_deployment_hook.output_path
  function_name    = "${local.project_name_with_suffix}-pre-deployment-hook"
  role            = aws_iam_role.lambda_role.arn
  handler         = "pre-deployment-hook.lambda_handler"
  source_code_hash = data.archive_file.pre_deployment_hook.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = 300
  memory_size     = 256

  description = "Pre-deployment validation hook for blue-green deployments"

  tags = local.common_tags
}

# Post-deployment validation hook
data "archive_file" "post_deployment_hook" {
  type        = "zip"
  output_path = "${path.module}/post-deployment-hook.zip"
  
  source {
    content = templatefile("${path.module}/post-deployment-hook.py.tpl", {
      project_name     = local.project_name_with_suffix
      alb_dns_name     = aws_lb.main.dns_name
      lambda_function_name = aws_lambda_function.api_function.function_name
    })
    filename = "post-deployment-hook.py"
  }
}

resource "aws_lambda_function" "post_deployment_hook" {
  filename         = data.archive_file.post_deployment_hook.output_path
  function_name    = "${local.project_name_with_suffix}-post-deployment-hook"
  role            = aws_iam_role.lambda_role.arn
  handler         = "post-deployment-hook.lambda_handler"
  source_code_hash = data.archive_file.post_deployment_hook.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      ALB_DNS_NAME         = aws_lb.main.dns_name
      LAMBDA_FUNCTION_NAME = aws_lambda_function.api_function.function_name
    }
  }

  description = "Post-deployment validation hook for blue-green deployments"

  tags = local.common_tags
}

# ====================================
# SNS Topic for Notifications
# ====================================

resource "aws_sns_topic" "deployment_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${local.project_name_with_suffix}-deployment-notifications"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.deployment_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ====================================
# CloudWatch Alarms
# ====================================

# ALB Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "alb_error_rate" {
  alarm_name          = "${local.project_name_with_suffix}-alb-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "High error rate detected in ALB"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.deployment_notifications[0].arn] : []

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.green.arn_suffix
  }

  tags = local.common_tags
}

# ALB Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${local.project_name_with_suffix}-alb-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.response_time_threshold
  alarm_description   = "High response time detected in ALB"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.deployment_notifications[0].arn] : []

  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.green.arn_suffix
  }

  tags = local.common_tags
}

# Lambda Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  alarm_name          = "${local.project_name_with_suffix}-lambda-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "High error rate detected in Lambda function"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.deployment_notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.api_function.function_name
  }

  tags = local.common_tags
}

# Lambda Duration Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${local.project_name_with_suffix}-lambda-high-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.lambda_duration_threshold
  alarm_description   = "High duration detected in Lambda function"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.deployment_notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.api_function.function_name
  }

  tags = local.common_tags
}

# ====================================
# CodeDeploy Applications
# ====================================

# CodeDeploy Application for ECS
resource "aws_codedeploy_app" "ecs_app" {
  compute_platform = "ECS"
  name             = "${local.project_name_with_suffix}-ecs-app"

  tags = local.common_tags
}

# CodeDeploy Deployment Group for ECS
resource "aws_codedeploy_deployment_group" "ecs_deployment_group" {
  app_name               = aws_codedeploy_app.ecs_app.name
  deployment_group_name  = "${local.project_name_with_suffix}-ecs-deployment-group"
  service_role_arn       = aws_iam_role.codedeploy_role.arn
  deployment_config_name = var.ecs_deployment_config

  auto_rollback_configuration {
    enabled = var.auto_rollback_enabled
    events  = var.auto_rollback_events
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                         = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_time_in_minutes
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    green_fleet_provisioning_option {
      action = "COPY_AUTO_SCALING_GROUP"
    }
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.main.name
    service_name = aws_ecs_service.app.name
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.blue.name
    }
    target_group_info {
      name = aws_lb_target_group.green.name
    }
  }

  tags = local.common_tags
}

# CodeDeploy Application for Lambda
resource "aws_codedeploy_app" "lambda_app" {
  compute_platform = "Lambda"
  name             = "${local.project_name_with_suffix}-lambda-app"

  tags = local.common_tags
}

# CodeDeploy Deployment Group for Lambda
resource "aws_codedeploy_deployment_group" "lambda_deployment_group" {
  app_name               = aws_codedeploy_app.lambda_app.name
  deployment_group_name  = "${local.project_name_with_suffix}-lambda-deployment-group"
  service_role_arn       = aws_iam_role.codedeploy_role.arn
  deployment_config_name = var.lambda_deployment_config

  auto_rollback_configuration {
    enabled = var.auto_rollback_enabled
    events  = var.auto_rollback_events
  }

  tags = local.common_tags
}

# ====================================
# CloudWatch Dashboard
# ====================================

resource "aws_cloudwatch_dashboard" "deployment_dashboard" {
  dashboard_name = "${local.project_name_with_suffix}-blue-green-deployments"

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
            ["AWS/CodeDeploy", "Deployments", "ApplicationName", aws_codedeploy_app.ecs_app.name],
            [".", ".", ".", aws_codedeploy_app.lambda_app.name]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "CodeDeploy Deployments"
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
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ALB Performance Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ServiceName", aws_ecs_service.app.name, "ClusterName", aws_ecs_cluster.main.name],
            [".", "PendingTaskCount", ".", ".", ".", "."],
            [".", "DesiredCount", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ECS Service Metrics"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.api_function.function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."],
            [".", "Throttles", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Lambda Function Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${aws_cloudwatch_log_group.ecs_logs.name}'\n| fields @timestamp, @message\n| filter @message like /ERROR/ or @message like /WARN/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Recent ECS Application Logs"
        }
      }
    ]
  })
}