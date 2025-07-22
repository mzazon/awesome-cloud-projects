# Generate random string for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if vpc_id is not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnets if subnet_ids are not provided
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Local values for computed resources
locals {
  # Use provided VPC ID or default VPC
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  
  # Use provided subnet IDs or default subnets
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Resource naming with random suffix
  cluster_name     = "${var.project_name}-${random_password.suffix.result}"
  repository_name  = "${var.project_name}-app-${random_password.suffix.result}"
  service_name     = "${var.project_name}-service"
  task_family      = "${var.project_name}-task"
  execution_role_name = "ecsTaskExecutionRole-${random_password.suffix.result}"
}

# ===============================================================================
# ECR Repository for Container Images
# ===============================================================================

# ECR repository for storing container images
resource "aws_ecr_repository" "app_repository" {
  name                 = local.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_scan
  }

  tags = {
    Name = local.repository_name
  }
}

# ECR repository lifecycle policy to manage image versions
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

# ===============================================================================
# IAM Roles and Policies
# ===============================================================================

# IAM role for ECS task execution
resource "aws_iam_role" "ecs_execution_role" {
  name = local.execution_role_name

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

  tags = {
    Name = local.execution_role_name
  }
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Optional: Create a task role for application-specific permissions
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-task-role-${random_password.suffix.result}"

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

  tags = {
    Name = "${var.project_name}-task-role-${random_password.suffix.result}"
  }
}

# ===============================================================================
# CloudWatch Log Group
# ===============================================================================

# CloudWatch log group for ECS task logs
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${local.task_family}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "/ecs/${local.task_family}"
  }
}

# ===============================================================================
# Security Groups
# ===============================================================================

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-${random_password.suffix.result}"
  description = "Security group for ECS Fargate tasks"
  vpc_id      = local.vpc_id

  # Inbound rule for application port
  ingress {
    description = "Application port"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Outbound rules for internet access (required for Fargate)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-tasks-${random_password.suffix.result}"
  }
}

# ===============================================================================
# ECS Cluster
# ===============================================================================

# ECS cluster with Fargate capacity providers
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = local.cluster_name
  }
}

# ECS cluster capacity providers configuration
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name
  
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ===============================================================================
# ECS Task Definition
# ===============================================================================

# ECS task definition for the containerized application
resource "aws_ecs_task_definition" "app" {
  family                   = local.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-container"
      image = var.container_image != "nginx:latest" ? var.container_image : "${aws_ecr_repository.app_repository.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      
      essential = true
      
      # Health check configuration
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      # Log configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      # Environment variables
      environment = [
        {
          name  = "PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "NODE_ENV"
          value = var.environment
        }
      ]
    }
  ])

  tags = {
    Name = local.task_family
  }
}

# ===============================================================================
# ECS Service
# ===============================================================================

# ECS service to manage the running tasks
resource "aws_ecs_service" "app" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  
  # Enable command execution for debugging
  enable_execute_command = true

  # Network configuration for Fargate
  network_configuration {
    subnets         = local.subnet_ids
    security_groups = [aws_security_group.ecs_tasks.id]
    # Enable public IP assignment for tasks (required if using public subnets)
    assign_public_ip = true
  }

  # Deployment configuration
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 50
  }

  # Wait for the service to reach a steady state during deployment
  wait_for_steady_state = true

  # Ensure cluster capacity providers are configured before service creation
  depends_on = [aws_ecs_cluster_capacity_providers.main]

  tags = {
    Name = local.service_name
  }
}

# ===============================================================================
# Auto Scaling Configuration
# ===============================================================================

# Application Auto Scaling target for the ECS service
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = {
    Name = "${local.service_name}-autoscaling-target"
  }
}

# Auto Scaling policy based on CPU utilization
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "${local.service_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    
    target_value       = var.cpu_target_value
    scale_out_cooldown = 300
    scale_in_cooldown  = 300
  }

  depends_on = [aws_appautoscaling_target.ecs_target]
}