# ECS Service Discovery with Route 53 and Application Load Balancer
# This Terraform configuration creates a complete microservices architecture with:
# - ECS Fargate cluster
# - AWS Cloud Map service discovery
# - Application Load Balancer with path-based routing
# - Security groups and IAM roles
# - CloudWatch logging

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "selected" {
  id      = var.vpc_id != "" ? var.vpc_id : null
  default = var.vpc_id == "" ? true : null
}

# Get subnets from the VPC
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  random_suffix     = random_id.suffix.hex
  cluster_name      = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-cluster-${local.random_suffix}"
  alb_name          = var.alb_name != "" ? var.alb_name : "${var.project_name}-alb-${local.random_suffix}"
  public_subnet_ids = length(var.public_subnet_ids) > 0 ? var.public_subnet_ids : data.aws_subnets.public.ids
  private_subnet_ids = length(var.private_subnet_ids) > 0 ? var.private_subnet_ids : (
    length(data.aws_subnets.private.ids) > 0 ? data.aws_subnets.private.ids : data.aws_subnets.public.ids
  )
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
  })
}

# CloudWatch Log Groups for ECS services
resource "aws_cloudwatch_log_group" "web_service" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/ecs/web-service"
  retention_in_days = var.log_retention_in_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_service" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/ecs/api-service"
  retention_in_days = var.log_retention_in_days
  tags              = local.common_tags
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# AWS Cloud Map Private DNS Namespace
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = var.namespace_name
  description = "Private DNS namespace for microservices service discovery"
  vpc         = data.aws_vpc.selected.id
  tags        = local.common_tags
}

# Cloud Map Services for service discovery
resource "aws_service_discovery_service" "web" {
  name = "web"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 300
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_service_discovery_service" "api" {
  name = "api"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 300
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_service_discovery_service" "database" {
  name = "database"

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 300
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 3
  }

  tags = local.common_tags
}

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "alb-sg-"
  description = "Security group for Application Load Balancer"
  vpc_id      = data.aws_vpc.selected.id

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
    Name = "alb-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "ecs-tasks-sg-"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description     = "Web service port from ALB"
    from_port       = var.web_service_port
    to_port         = var.web_service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "API service port from ALB"
    from_port       = var.api_service_port
    to_port         = var.api_service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Internal communication between services"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "ecs-tasks-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name = local.alb_name
  })
}

# Target Groups for ALB
resource "aws_lb_target_group" "web" {
  name_prefix  = "web-"
  port         = 80
  protocol     = "HTTP"
  target_type  = "ip"
  vpc_id       = data.aws_vpc.selected.id

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold_count
    unhealthy_threshold = var.unhealthy_threshold_count
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = merge(local.common_tags, {
    Name = "web-target-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "api" {
  name_prefix  = "api-"
  port         = 80
  protocol     = "HTTP"
  target_type  = "ip"
  vpc_id       = data.aws_vpc.selected.id

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold_count
    unhealthy_threshold = var.unhealthy_threshold_count
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = merge(local.common_tags, {
    Name = "api-target-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ALB Listener
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = local.common_tags
}

# ALB Listener Rule for API service
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.web.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  tags = local.common_tags
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name_prefix = "ecsTaskExecutionRole-"

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

# Attach the managed policy to the execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definition for Web Service
resource "aws_ecs_task_definition" "web" {
  family                   = "web-service-${local.random_suffix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.web_service_cpu
  memory                   = var.web_service_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "web-container"
      image = var.web_service_image

      portMappings = [
        {
          containerPort = 80
          hostPort      = var.web_service_port
          protocol      = "tcp"
        }
      ]

      essential = true

      logConfiguration = var.enable_cloudwatch_logs ? {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web_service[0].name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      } : null
    }
  ])

  tags = local.common_tags
}

# ECS Task Definition for API Service
resource "aws_ecs_task_definition" "api" {
  family                   = "api-service-${local.random_suffix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.api_service_cpu
  memory                   = var.api_service_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "api-container"
      image = var.api_service_image

      portMappings = [
        {
          containerPort = 80
          hostPort      = var.api_service_port
          protocol      = "tcp"
        }
      ]

      essential = true

      logConfiguration = var.enable_cloudwatch_logs ? {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.api_service[0].name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      } : null
    }
  ])

  tags = local.common_tags
}

# ECS Service for Web Application
resource "aws_ecs_service" "web" {
  name            = "web-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = var.web_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = length(data.aws_subnets.private.ids) == 0 ? true : false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web-container"
    container_port   = 80
  }

  service_registries {
    registry_arn = aws_service_discovery_service.web.arn
  }

  depends_on = [
    aws_lb_listener.web,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = local.common_tags
}

# ECS Service for API
resource "aws_ecs_service" "api" {
  name            = "api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.api_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = length(data.aws_subnets.private.ids) == 0 ? true : false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "api-container"
    container_port   = 80
  }

  service_registries {
    registry_arn = aws_service_discovery_service.api.arn
  }

  depends_on = [
    aws_lb_listener_rule.api,
    aws_iam_role_policy_attachment.ecs_task_execution_role_policy
  ]

  tags = local.common_tags
}