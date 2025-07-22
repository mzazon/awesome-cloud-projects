# Data Sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  project_name = "${var.project_name}-${random_id.suffix.hex}"
  
  common_tags = {
    Project     = local.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "cicd-pipelines-container-applications"
  }
}

# ================================
# VPC and Networking Resources
# ================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = length(aws_subnet.public)

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = length(aws_subnet.public)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-public-rt"
  })
}

# Route Tables for Private Subnets
resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-private-rt-${count.index + 1}"
  })
}

# Route Table Associations for Public Subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Table Associations for Private Subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ================================
# Security Groups
# ================================

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${local.project_name}-alb-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for Application Load Balancer"

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
    Name = "${local.project_name}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ECS Tasks Security Group
resource "aws_security_group" "ecs" {
  name_prefix = "${local.project_name}-ecs-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for ECS tasks"

  ingress {
    description     = "HTTP from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "X-Ray daemon"
    from_port       = 2000
    to_port         = 2000
    protocol        = "udp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-ecs-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ================================
# ECR Repository
# ================================

# ECR Repository for Container Images
resource "aws_ecr_repository" "main" {
  name                 = local.project_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-repository"
  })
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "main" {
  count = var.enable_lifecycle_policies ? 1 : 0

  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_prod_images} production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_prod_images
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_dev_images} development images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_dev_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ================================
# Application Load Balancers
# ================================

# Development Application Load Balancer
resource "aws_lb" "dev" {
  name               = "${local.project_name}-dev-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout               = var.alb_idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-alb"
    Environment = "development"
  })
}

# Production Application Load Balancer
resource "aws_lb" "prod" {
  name               = "${local.project_name}-prod-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  idle_timeout               = var.alb_idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-alb"
    Environment = "production"
  })
}

# ================================
# Target Groups
# ================================

# Development Target Group
resource "aws_lb_target_group" "dev" {
  name        = "${local.project_name}-dev-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-tg"
    Environment = "development"
  })
}

# Production Blue Target Group
resource "aws_lb_target_group" "prod_blue" {
  name        = "${local.project_name}-prod-blue"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = 15
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-blue"
    Environment = "production"
    Color       = "blue"
  })
}

# Production Green Target Group
resource "aws_lb_target_group" "prod_green" {
  name        = "${local.project_name}-prod-green"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = 15
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-green"
    Environment = "production"
    Color       = "green"
  })
}

# ================================
# Load Balancer Listeners
# ================================

# Development ALB Listener
resource "aws_lb_listener" "dev" {
  load_balancer_arn = aws_lb.dev.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dev.arn
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-listener"
    Environment = "development"
  })
}

# Production ALB Listener
resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.prod.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_blue.arn
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-listener"
    Environment = "production"
  })
}

# ================================
# CloudWatch Log Groups
# ================================

# Development Log Group
resource "aws_cloudwatch_log_group" "dev" {
  name              = "/aws/ecs/${local.project_name}/dev"
  retention_in_days = var.dev_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-logs"
    Environment = "development"
  })
}

# Production Log Group
resource "aws_cloudwatch_log_group" "prod" {
  name              = "/aws/ecs/${local.project_name}/prod"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-logs"
    Environment = "production"
  })
}

# ================================
# IAM Roles and Policies
# ================================

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution" {
  name = "${local.project_name}-ecs-task-execution-role"

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
    Name = "${local.project_name}-ecs-task-execution-role"
  })
}

# Attach managed policy to ECS Task Execution Role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role
resource "aws_iam_role" "ecs_task" {
  name = "${local.project_name}-ecs-task-role"

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
    Name = "${local.project_name}-ecs-task-role"
  })
}

# ECS Task Role Policy
resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.project_name}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "secretsmanager:GetSecretValue",
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodeBuild Service Role
resource "aws_iam_role" "codebuild" {
  name = "${local.project_name}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-codebuild-role"
  })
}

# CodeBuild Role Policy
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${local.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "s3:GetObject",
          "s3:PutObject",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "secretsmanager:GetSecretValue",
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodePipeline Service Role
resource "aws_iam_role" "codepipeline" {
  name = "${local.project_name}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-codepipeline-role"
  })
}

# CodePipeline Role Policy
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${local.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild",
          "codedeploy:CreateDeployment",
          "codedeploy:GetApplication",
          "codedeploy:GetApplicationRevision",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
          "iam:PassRole",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodeDeploy Service Role
resource "aws_iam_role" "codedeploy" {
  name = "${local.project_name}-codedeploy-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-codedeploy-role"
  })
}

# Attach managed policy to CodeDeploy Role
resource "aws_iam_role_policy_attachment" "codedeploy_policy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# ================================
# ECS Clusters
# ================================

# Development ECS Cluster
resource "aws_ecs_cluster" "dev" {
  name = "${local.project_name}-dev-cluster"

  capacity_providers = var.enable_fargate_spot ? var.dev_cluster_capacity_providers : ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = var.enable_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 0
  }

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-cluster"
    Environment = "development"
  })
}

# Production ECS Cluster
resource "aws_ecs_cluster" "prod" {
  name = "${local.project_name}-prod-cluster"

  capacity_providers = var.prod_cluster_capacity_providers

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-cluster"
    Environment = "production"
  })
}

# ================================
# Parameter Store Parameters
# ================================

# Application Version Parameter
resource "aws_ssm_parameter" "app_version" {
  name        = "/${local.project_name}/app/version"
  description = "Application version"
  type        = "String"
  value       = "1.0.0"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-app-version"
  })
}

# Application Environment Parameter
resource "aws_ssm_parameter" "app_environment" {
  name        = "/${local.project_name}/app/environment"
  description = "Application environment"
  type        = "String"
  value       = var.environment

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-app-environment"
  })
}

# ================================
# ECS Task Definitions
# ================================

# Development Task Definition
resource "aws_ecs_task_definition" "dev" {
  family                   = "${local.project_name}-dev-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.dev_task_cpu
  memory                   = var.dev_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "nginx:latest"
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "ENV"
          value = "development"
        },
        {
          name  = "AWS_XRAY_TRACING_NAME"
          value = "${local.project_name}-dev"
        }
      ]
      secrets = [
        {
          name      = "APP_VERSION"
          valueFrom = aws_ssm_parameter.app_version.name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dev.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ] + (var.enable_xray ? [
    {
      name      = "xray-daemon"
      image     = "amazon/aws-xray-daemon:latest"
      essential = false
      portMappings = [
        {
          containerPort = 2000
          protocol      = "udp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dev.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "xray"
        }
      }
    }
  ] : []))

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-task"
    Environment = "development"
  })
}

# Production Task Definition
resource "aws_ecs_task_definition" "prod" {
  family                   = "${local.project_name}-prod-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.prod_task_cpu
  memory                   = var.prod_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.main.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "ENV"
          value = "production"
        },
        {
          name  = "AWS_XRAY_TRACING_NAME"
          value = "${local.project_name}-prod"
        }
      ]
      secrets = [
        {
          name      = "APP_VERSION"
          valueFrom = aws_ssm_parameter.app_version.name
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prod.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ] + (var.enable_xray ? [
    {
      name      = "xray-daemon"
      image     = "amazon/aws-xray-daemon:latest"
      essential = false
      portMappings = [
        {
          containerPort = 2000
          protocol      = "udp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prod.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "xray"
        }
      }
    }
  ] : []))

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-task"
    Environment = "production"
  })
}

# ================================
# ECS Services
# ================================

# Development ECS Service
resource "aws_ecs_service" "dev" {
  name            = "${local.project_name}-dev-service"
  cluster         = aws_ecs_cluster.dev.id
  task_definition = aws_ecs_task_definition.dev.arn
  desired_count   = var.dev_service_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dev.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.dev]

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-dev-service"
    Environment = "development"
  })
}

# Production ECS Service
resource "aws_ecs_service" "prod" {
  name            = "${local.project_name}-prod-service"
  cluster         = aws_ecs_cluster.prod.id
  task_definition = aws_ecs_task_definition.prod.arn
  desired_count   = var.prod_service_desired_count
  launch_type     = "FARGATE"

  deployment_controller {
    type = var.enable_blue_green_deployment ? "CODE_DEPLOY" : "ECS"
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.prod_blue.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.prod]

  tags = merge(local.common_tags, {
    Name        = "${local.project_name}-prod-service"
    Environment = "production"
  })

  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
}

# ================================
# S3 Bucket for CodePipeline Artifacts
# ================================

# S3 Bucket for CodePipeline Artifacts
resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "${local.project_name}-codepipeline-artifacts"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-codepipeline-artifacts"
  })
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "codepipeline_artifacts" {
  bucket = aws_s3_bucket.codepipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ================================
# CodeBuild Project
# ================================

# CodeBuild Project
resource "aws_codebuild_project" "main" {
  name         = "${local.project_name}-build"
  description  = "Build project for ${local.project_name}"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.build_compute_type
    image                      = var.build_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.main.name
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-build"
  })
}

# ================================
# SNS Topic for Notifications
# ================================

# SNS Topic for Notifications
resource "aws_sns_topic" "notifications" {
  name = "${local.project_name}-notifications"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-notifications"
  })
}

# SNS Topic Subscription (if email provided)
resource "aws_sns_topic_subscription" "email_notifications" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ================================
# CloudWatch Alarms
# ================================

# High Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${local.project_name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.high_error_rate_threshold
  alarm_description   = "This metric monitors high error rate"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    LoadBalancer = aws_lb.prod.arn_suffix
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-high-error-rate"
  })
}

# High Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "${local.project_name}-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.high_response_time_threshold
  alarm_description   = "This metric monitors high response time"
  alarm_actions       = [aws_sns_topic.notifications.arn]

  dimensions = {
    LoadBalancer = aws_lb.prod.arn_suffix
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-high-response-time"
  })
}

# ================================
# CodeDeploy Application
# ================================

# CodeDeploy Application
resource "aws_codedeploy_app" "main" {
  compute_platform = "ECS"
  name             = "${local.project_name}-app"

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-app"
  })
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "prod" {
  count = var.enable_blue_green_deployment ? 1 : 0

  app_name              = aws_codedeploy_app.main.name
  deployment_group_name = "${local.project_name}-prod-deployment-group"
  service_role_arn      = aws_iam_role.codedeploy.arn
  deployment_config_name = var.deployment_config_name

  auto_rollback_configuration {
    enabled = var.auto_rollback_enabled
    events  = var.auto_rollback_events
  }

  blue_green_deployment_config {
    terminate_blue_instances_on_deployment_success {
      action                         = "TERMINATE"
      termination_wait_time_in_minutes = var.blue_green_termination_wait_time
    }

    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
  }

  ecs_service {
    cluster_name = aws_ecs_cluster.prod.name
    service_name = aws_ecs_service.prod.name
  }

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.prod_blue.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-prod-deployment-group"
  })
}

# ================================
# CodePipeline
# ================================

# CodePipeline
resource "aws_codepipeline" "main" {
  name     = "${local.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        S3Bucket    = aws_s3_bucket.codepipeline_artifacts.bucket
        S3ObjectKey = "source.zip"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Deploy-Dev"

    action {
      name            = "Deploy-Dev"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ClusterName = aws_ecs_cluster.dev.name
        ServiceName = aws_ecs_service.dev.name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  dynamic "stage" {
    for_each = var.enable_manual_approval ? [1] : []

    content {
      name = "Approval"

      action {
        name     = "ManualApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          NotificationArn = aws_sns_topic.notifications.arn
          CustomData      = "Please review the development deployment and approve for production deployment."
        }
      }
    }
  }

  stage {
    name = "Deploy-Production"

    action {
      name            = var.enable_blue_green_deployment ? "Deploy-Production" : "Deploy-Production-Rolling"
      category        = "Deploy"
      owner           = "AWS"
      provider        = var.enable_blue_green_deployment ? "CodeDeployToECS" : "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = var.enable_blue_green_deployment ? {
        ApplicationName                = aws_codedeploy_app.main.name
        DeploymentGroupName            = aws_codedeploy_deployment_group.prod[0].deployment_group_name
        TaskDefinitionTemplateArtifact = "build_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "build_output"
        AppSpecTemplatePath            = "appspec.yaml"
        } : {
        ClusterName = aws_ecs_cluster.prod.name
        ServiceName = aws_ecs_service.prod.name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-pipeline"
  })
}