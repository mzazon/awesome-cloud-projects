# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get default VPC if not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnets if not provided
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get availability zones if not provided
data "aws_availability_zones" "available" {
  count = length(var.availability_zones) == 0 ? 1 : 0
  state = "available"
}

# Local values for resource naming and configuration
locals {
  # Resource names
  cluster_name            = var.cluster_name != "" ? var.cluster_name : "fargate-cluster-${random_string.suffix.result}"
  service_name            = var.service_name != "" ? var.service_name : "fargate-service-${random_string.suffix.result}"
  task_definition_family  = var.task_definition_family != "" ? var.task_definition_family : "fargate-task-${random_string.suffix.result}"
  alb_name                = var.alb_name != "" ? var.alb_name : "fargate-alb-${random_string.suffix.result}"
  ecr_repository_name     = var.ecr_repository_name != "" ? var.ecr_repository_name : "fargate-demo-${random_string.suffix.result}"
  
  # Network configuration
  vpc_id                  = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids              = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  availability_zones      = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available[0].names, 0, min(3, length(data.aws_availability_zones.available[0].names)))
  
  # Container configuration
  container_image         = var.container_image != "" ? var.container_image : "${aws_ecr_repository.fargate_demo.repository_url}:latest"
  
  # Common tags
  common_tags = merge(
    {
      Name        = "fargate-serverless-containers"
      Environment = var.environment
      Project     = "fargate-serverless-containers"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# ECR Repository for container images
resource "aws_ecr_repository" "fargate_demo" {
  name                 = local.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = var.ecr_encryption_type
  }

  tags = merge(local.common_tags, {
    Name = local.ecr_repository_name
  })
}

# ECR Repository Policy for cleanup
resource "aws_ecr_lifecycle_policy" "fargate_demo" {
  repository = aws_ecr_repository.fargate_demo.name

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

# CloudWatch Log Group for ECS tasks
resource "aws_cloudwatch_log_group" "fargate_logs" {
  name              = "/ecs/${local.task_definition_family}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "/ecs/${local.task_definition_family}"
  })
}

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "${local.alb_name}-sg"
  description = "Security group for Fargate ALB"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.alb_name}-sg"
  })
}

# Security Group for Fargate tasks
resource "aws_security_group" "fargate_tasks" {
  name        = "${local.service_name}-sg"
  description = "Security group for Fargate tasks"
  vpc_id      = local.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP outbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.service_name}-sg"
  })
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole-${random_string.suffix.result}"

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

  tags = merge(local.common_tags, {
    Name = "ecsTaskExecutionRole-${random_string.suffix.result}"
  })
}

# Attach the managed policy to the task execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_role" {
  name = "ecsTaskRole-${random_string.suffix.result}"

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

  tags = merge(local.common_tags, {
    Name = "ecsTaskRole-${random_string.suffix.result}"
  })
}

# IAM Policy for ECS Task Role
resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "ecsTaskRolePolicy-${random_string.suffix.result}"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "fargate_cluster" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "fargate_cluster" {
  cluster_name = aws_ecs_cluster.fargate_cluster.name

  capacity_providers = var.enable_fargate_spot ? ["FARGATE", "FARGATE_SPOT"] : ["FARGATE"]

  default_capacity_provider_strategy {
    base              = var.fargate_base
    weight            = var.fargate_weight
    capacity_provider = "FARGATE"
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = var.enable_fargate_spot ? [1] : []
    content {
      weight            = var.fargate_spot_weight
      capacity_provider = "FARGATE_SPOT"
    }
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "fargate_task" {
  family                   = local.task_definition_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "fargate-demo-container"
      image     = local.container_image
      essential = true
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        for key, value in var.container_environment_variables : {
          name  = key
          value = value
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fargate_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"
        ]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_unhealthy_threshold
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = local.task_definition_family
  })
}

# Application Load Balancer
resource "aws_lb" "fargate_alb" {
  name               = local.alb_name
  internal           = var.alb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  enable_deletion_protection = var.alb_deletion_protection

  tags = merge(local.common_tags, {
    Name = local.alb_name
  })
}

# Target Group for ALB
resource "aws_lb_target_group" "fargate_tg" {
  name        = "fargate-tg-${random_string.suffix.result}"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    interval            = var.health_check_interval
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
  }

  tags = merge(local.common_tags, {
    Name = "fargate-tg-${random_string.suffix.result}"
  })
}

# ALB Listener
resource "aws_lb_listener" "fargate_listener" {
  load_balancer_arn = aws_lb.fargate_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.fargate_tg.arn
  }

  tags = merge(local.common_tags, {
    Name = "fargate-listener-${random_string.suffix.result}"
  })
}

# ECS Service
resource "aws_ecs_service" "fargate_service" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.fargate_cluster.id
  task_definition = aws_ecs_task_definition.fargate_task.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  platform_version = var.platform_version

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [aws_security_group.fargate_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.fargate_tg.arn
    container_name   = "fargate-demo-container"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = var.health_check_grace_period

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 50
    
    deployment_circuit_breaker {
      enable   = true
      rollback = true
    }
  }

  enable_execute_command = var.enable_execute_command

  depends_on = [
    aws_lb_listener.fargate_listener
  ]

  tags = merge(local.common_tags, {
    Name = local.service_name
  })
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_target" {
  count = var.enable_auto_scaling ? 1 : 0

  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.fargate_cluster.name}/${aws_ecs_service.fargate_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(local.common_tags, {
    Name = "ecs-autoscaling-target-${random_string.suffix.result}"
  })
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  count = var.enable_auto_scaling ? 1 : 0

  name               = "${local.service_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Auto Scaling Policy - Memory
resource "aws_appautoscaling_policy" "ecs_memory_policy" {
  count = var.enable_auto_scaling ? 1 : 0

  name               = "${local.service_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}