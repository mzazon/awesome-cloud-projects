# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  random_suffix         = random_id.suffix.hex
  repository_name       = var.repository_name != null ? var.repository_name : "${var.project_name}-${local.random_suffix}"
  build_project_name    = var.build_project_name != null ? var.build_project_name : "${var.project_name}-build-${local.random_suffix}"
  ecr_repository_name   = var.ecr_repository_name != null ? var.ecr_repository_name : "${var.project_name}-${local.random_suffix}"
  ecs_cluster_name      = var.ecs_cluster_name != null ? var.ecs_cluster_name : "${var.project_name}-cluster-${local.random_suffix}"
  pipeline_name         = var.pipeline_name != null ? var.pipeline_name : "${var.project_name}-pipeline-${local.random_suffix}"
  
  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "gitops-workflows-aws-codecommit-codebuild"
    },
    var.additional_tags
  )
}

#------------------------------------------------------------------------------
# CodeCommit Repository for GitOps Source Control
#------------------------------------------------------------------------------

resource "aws_codecommit_repository" "gitops_repo" {
  repository_name = local.repository_name
  description     = "GitOps workflow demonstration repository for ${var.project_name}"
  
  tags = merge(local.common_tags, {
    Name = local.repository_name
    Type = "GitOps Repository"
  })
}

#------------------------------------------------------------------------------
# ECR Repository for Container Images
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "app_repo" {
  name                 = local.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability
  
  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }
  
  tags = merge(local.common_tags, {
    Name = local.ecr_repository_name
    Type = "Container Registry"
  })
}

# ECR lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "app_repo_lifecycle" {
  repository = aws_ecr_repository.app_repo.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# CloudWatch Log Group for ECS Tasks
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.project_name}-app"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "/ecs/${var.project_name}-app"
    Type = "ECS Application Logs"
  })
}

#------------------------------------------------------------------------------
# IAM Role for CodeBuild Service
#------------------------------------------------------------------------------

# Trust policy allowing CodeBuild to assume this role
data "aws_iam_policy_document" "codebuild_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for CodeBuild with GitOps permissions
resource "aws_iam_role" "codebuild_role" {
  name               = "CodeBuildGitOpsRole-${local.random_suffix}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name = "CodeBuildGitOpsRole-${local.random_suffix}"
    Type = "CodeBuild Service Role"
  })
}

# Custom IAM policy for CodeBuild GitOps operations
data "aws_iam_policy_document" "codebuild_policy" {
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
    ]
  }
  
  # ECR permissions for container operations
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = [
      "*"
    ]
  }
  
  # ECS permissions for deployment
  statement {
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:ListTasks",
      "ecs:DescribeTasks"
    ]
    resources = [
      "*"
    ]
  }
  
  # IAM permissions for ECS task execution
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"
    ]
  }
  
  # CodeCommit permissions
  statement {
    effect = "Allow"
    actions = [
      "codecommit:GitPull"
    ]
    resources = [
      aws_codecommit_repository.gitops_repo.arn
    ]
  }
}

# Attach custom policy to CodeBuild role
resource "aws_iam_role_policy" "codebuild_policy" {
  name   = "CodeBuildGitOpsPolicy"
  role   = aws_iam_role.codebuild_role.id
  policy = data.aws_iam_policy_document.codebuild_policy.json
}

#------------------------------------------------------------------------------
# CodeBuild Project for GitOps Pipeline
#------------------------------------------------------------------------------

resource "aws_codebuild_project" "gitops_build" {
  name         = local.build_project_name
  description  = "GitOps build project for automated deployments"
  service_role = aws_iam_role.codebuild_role.arn
  
  artifacts {
    type = "NO_ARTIFACTS"
  }
  
  environment {
    compute_type                = var.build_environment_compute_type
    image                      = var.build_environment_image
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
      value = aws_ecr_repository.app_repo.name
    }
    
    environment_variable {
      name  = "IMAGE_URI"
      value = aws_ecr_repository.app_repo.repository_url
    }
    
    environment_variable {
      name  = "ECS_CLUSTER_NAME"
      value = local.ecs_cluster_name
    }
  }
  
  source {
    type            = "CODECOMMIT"
    location        = aws_codecommit_repository.gitops_repo.clone_url_http
    git_clone_depth = 1
    buildspec       = "config/buildspecs/buildspec.yml"
  }
  
  tags = merge(local.common_tags, {
    Name = local.build_project_name
    Type = "GitOps Build Project"
  })
}

#------------------------------------------------------------------------------
# CloudWatch Events Rule for GitOps Automation
#------------------------------------------------------------------------------

# EventBridge rule to trigger CodeBuild on repository changes
resource "aws_cloudwatch_event_rule" "codecommit_trigger" {
  count = var.enable_codecommit_trigger ? 1 : 0
  
  name        = "${var.project_name}-codecommit-trigger-${local.random_suffix}"
  description = "Trigger CodeBuild on CodeCommit repository changes"
  
  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [aws_codecommit_repository.gitops_repo.arn]
    detail = {
      event = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = ["main"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-codecommit-trigger-${local.random_suffix}"
    Type = "GitOps Automation Trigger"
  })
}

# CloudWatch Events target for CodeBuild
resource "aws_cloudwatch_event_target" "codebuild_target" {
  count = var.enable_codecommit_trigger ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.codecommit_trigger[0].name
  target_id = "CodeBuildTarget"
  arn       = aws_codebuild_project.gitops_build.arn
  
  role_arn = aws_iam_role.events_role[0].arn
}

# IAM role for CloudWatch Events
resource "aws_iam_role" "events_role" {
  count = var.enable_codecommit_trigger ? 1 : 0
  
  name = "EventsGitOpsRole-${local.random_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "EventsGitOpsRole-${local.random_suffix}"
    Type = "CloudWatch Events Role"
  })
}

# IAM policy for CloudWatch Events to trigger CodeBuild
resource "aws_iam_role_policy" "events_policy" {
  count = var.enable_codecommit_trigger ? 1 : 0
  
  name = "EventsGitOpsPolicy"
  role = aws_iam_role.events_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.gitops_build.arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# ECS Cluster for Container Orchestration
#------------------------------------------------------------------------------

resource "aws_ecs_cluster" "gitops_cluster" {
  name = local.ecs_cluster_name
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  
  tags = merge(local.common_tags, {
    Name = local.ecs_cluster_name
    Type = "ECS Cluster"
  })
}

resource "aws_ecs_cluster_capacity_providers" "gitops_cluster_capacity" {
  cluster_name = aws_ecs_cluster.gitops_cluster.name
  
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

#------------------------------------------------------------------------------
# ECS Task Definition for GitOps Application
#------------------------------------------------------------------------------

# Data source for ECS task execution role
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_ecs_task_definition" "gitops_app" {
  family                   = "${var.project_name}-app-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn
  
  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-app"
      image = "${aws_ecr_repository.app_repo.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "APP_VERSION"
          value = "1.0.0"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
      
      essential = true
    }
  ])
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-task"
    Type = "ECS Task Definition"
  })
}

#------------------------------------------------------------------------------
# VPC and Networking Resources (using default VPC for simplicity)
#------------------------------------------------------------------------------

# Data source for default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source for default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for ECS service
resource "aws_security_group" "ecs_service" {
  name        = "${var.project_name}-ecs-service-${local.random_suffix}"
  description = "Security group for ECS service"
  vpc_id      = data.aws_vpc.default.id
  
  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound traffic on application port"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-service-${local.random_suffix}"
    Type = "ECS Service Security Group"
  })
}

#------------------------------------------------------------------------------
# ECS Service for GitOps Application
#------------------------------------------------------------------------------

resource "aws_ecs_service" "gitops_app_service" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.gitops_cluster.id
  task_definition = aws_ecs_task_definition.gitops_app.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_service.id]
    assign_public_ip = true
  }
  
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-service"
    Type = "ECS Service"
  })
  
  depends_on = [
    aws_ecs_task_definition.gitops_app
  ]
}