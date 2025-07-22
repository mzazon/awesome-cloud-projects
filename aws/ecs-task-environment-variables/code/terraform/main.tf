# Terraform configuration for ECS Task Definitions with Environment Variable Management
# This configuration demonstrates comprehensive environment variable management strategies
# including Systems Manager Parameter Store, S3 environment files, and direct variables

# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Cluster and service names with fallbacks
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${local.name_prefix}-cluster"
  service_name = var.service_name != "" ? var.service_name : "${local.name_prefix}-service"
  
  # VPC and networking configuration
  vpc_id = var.use_existing_vpc ? (var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id) : aws_vpc.main[0].id
  subnet_ids = var.use_existing_vpc ? (length(var.subnet_ids) > 0 ? var.subnet_ids : [data.aws_subnet.default[0].id]) : aws_subnet.main[*].id
  security_group_id = var.use_existing_vpc ? data.aws_security_group.default[0].id : aws_security_group.ecs_tasks[0].id
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# Data sources for existing VPC resources (when using existing VPC)
data "aws_vpc" "default" {
  count   = var.use_existing_vpc && var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.use_existing_vpc && length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

data "aws_subnet" "default" {
  count = var.use_existing_vpc && length(var.subnet_ids) == 0 ? 1 : 0
  id    = data.aws_subnets.default[0].ids[0]
}

data "aws_security_group" "default" {
  count = var.use_existing_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  filter {
    name   = "group-name"
    values = ["default"]
  }
}

# VPC resources (only created if not using existing VPC)
resource "aws_vpc" "main" {
  count                = var.use_existing_vpc ? 0 : 1
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.main[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnets
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "main" {
  count                   = var.use_existing_vpc ? 0 : 2
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Route table
resource "aws_route_table" "main" {
  count  = var.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt"
  })
}

# Route table associations
resource "aws_route_table_association" "main" {
  count          = var.use_existing_vpc ? 0 : 2
  subnet_id      = aws_subnet.main[count.index].id
  route_table_id = aws_route_table.main[0].id
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  count       = var.use_existing_vpc ? 0 : 1
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main[0].id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow inbound traffic on container port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-tasks-sg"
  })
}

# S3 bucket for environment files
resource "aws_s3_bucket" "env_configs" {
  bucket = "${local.name_prefix}-env-configs"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-env-configs"
    Purpose     = "ECS Environment Files"
    Description = "Stores environment configuration files for ECS tasks"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "env_configs" {
  bucket = aws_s3_bucket.env_configs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "env_configs" {
  bucket = aws_s3_bucket.env_configs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "env_configs" {
  bucket = aws_s3_bucket.env_configs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Create environment files and upload to S3
resource "aws_s3_object" "env_files" {
  for_each = var.environment_files

  bucket = aws_s3_bucket.env_configs.bucket
  key    = "configs/${each.key}"
  content = join("\n", [
    for k, v in each.value.content : "${k}=${v}"
  ])
  content_type = "text/plain"

  tags = merge(local.common_tags, {
    Name        = each.key
    Purpose     = "Environment Configuration"
    Description = "Environment variables file for ECS tasks"
  })
}

# Systems Manager parameters for application configuration
resource "aws_ssm_parameter" "app_parameters" {
  for_each = var.app_parameters

  name        = "/myapp/${var.environment}/${each.key}"
  type        = each.value.type
  value       = each.value.value
  description = each.value.description

  tags = merge(local.common_tags, {
    Name        = "/myapp/${var.environment}/${each.key}"
    Purpose     = "Application Configuration"
    Description = each.value.description
  })
}

# Systems Manager secure parameters for secrets
resource "aws_ssm_parameter" "app_secrets" {
  for_each = var.app_secrets

  name        = "/myapp/${var.environment}/${each.key}"
  type        = "SecureString"
  value       = each.value.value
  description = each.value.description

  tags = merge(local.common_tags, {
    Name        = "/myapp/${var.environment}/${each.key}"
    Purpose     = "Application Secret"
    Description = each.value.description
  })
}

# Shared parameters across environments
resource "aws_ssm_parameter" "shared_region" {
  name        = "/myapp/shared/region"
  type        = "String"
  value       = data.aws_region.current.name
  description = "Shared region parameter"

  tags = merge(local.common_tags, {
    Name        = "/myapp/shared/region"
    Purpose     = "Shared Configuration"
    Description = "AWS region for shared resources"
  })
}

resource "aws_ssm_parameter" "shared_account_id" {
  name        = "/myapp/shared/account-id"
  type        = "String"
  value       = data.aws_caller_identity.current.account_id
  description = "Shared account ID parameter"

  tags = merge(local.common_tags, {
    Name        = "/myapp/shared/account-id"
    Purpose     = "Shared Configuration"
    Description = "AWS account ID for shared resources"
  })
}

# IAM role for ECS task execution
resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-task-execution-role"

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
    Name        = "${local.name_prefix}-task-execution-role"
    Purpose     = "ECS Task Execution"
    Description = "IAM role for ECS task execution with environment variable access"
  })
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution_policy" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Custom policy for Systems Manager Parameter Store and S3 access
resource "aws_iam_policy" "parameter_store_access" {
  name        = "${local.name_prefix}-parameter-store-access"
  description = "Policy for accessing Systems Manager Parameter Store and S3 environment files"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter",
          "ssm:GetParametersByPath"
        ]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/myapp/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.env_configs.arn}/configs/*"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-parameter-store-access"
    Purpose     = "Parameter Store Access"
    Description = "Allows access to Systems Manager parameters and S3 environment files"
  })
}

# Attach custom policy to task execution role
resource "aws_iam_role_policy_attachment" "parameter_store_access" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.parameter_store_access.arn
}

# IAM role for ECS tasks (runtime permissions)
resource "aws_iam_role" "task_role" {
  name = "${local.name_prefix}-task-role"

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
    Name        = "${local.name_prefix}-task-role"
    Purpose     = "ECS Task Runtime"
    Description = "IAM role for ECS task runtime permissions"
  })
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${var.task_family}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name        = "/ecs/${var.task_family}"
    Purpose     = "ECS Task Logs"
    Description = "CloudWatch log group for main ECS task definition"
  })
}

resource "aws_cloudwatch_log_group" "envfiles" {
  name              = "/ecs/${var.task_family}-envfiles"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name        = "/ecs/${var.task_family}-envfiles"
    Purpose     = "ECS Task Logs"
    Description = "CloudWatch log group for environment files ECS task definition"
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, {
    Name        = local.cluster_name
    Purpose     = "ECS Cluster"
    Description = "ECS cluster for environment variable management demonstration"
  })
}

# ECS Task Definition with comprehensive environment variable management
resource "aws_ecs_task_definition" "main" {
  family                   = var.task_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn           = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "app-container"
      image     = var.container_image
      essential = true
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Direct environment variables
      environment = [
        {
          name  = "NODE_ENV"
          value = var.environment
        },
        {
          name  = "SERVICE_NAME"
          value = local.service_name
        },
        {
          name  = "CLUSTER_NAME"
          value = local.cluster_name
        },
        {
          name  = "DEPLOYMENT_TYPE"
          value = "comprehensive-env-management"
        }
      ]

      # Systems Manager Parameter Store secrets
      secrets = [
        {
          name      = "DATABASE_HOST"
          valueFrom = aws_ssm_parameter.app_parameters["database/host"].name
        },
        {
          name      = "DATABASE_PORT"
          valueFrom = aws_ssm_parameter.app_parameters["database/port"].name
        },
        {
          name      = "API_DEBUG"
          valueFrom = aws_ssm_parameter.app_parameters["api/debug"].name
        },
        {
          name      = "DATABASE_PASSWORD"
          valueFrom = aws_ssm_parameter.app_secrets["database/password"].name
        },
        {
          name      = "API_SECRET_KEY"
          valueFrom = aws_ssm_parameter.app_secrets["api/secret-key"].name
        }
      ]

      # Environment files from S3
      environmentFiles = [
        {
          value = "arn:aws:s3:::${aws_s3_bucket.env_configs.bucket}/${aws_s3_object.env_files["app-config.env"].key}"
          type  = "s3"
        }
      ]

      # CloudWatch logging configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name        = var.task_family
    Purpose     = "ECS Task Definition"
    Description = "Task definition with comprehensive environment variable management"
  })
}

# Alternative task definition focused on environment files
resource "aws_ecs_task_definition" "envfiles" {
  family                   = "${var.task_family}-envfiles"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn           = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "app-container"
      image     = var.container_image
      essential = true
      
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      # Minimal direct environment variables
      environment = [
        {
          name  = "DEPLOYMENT_TYPE"
          value = "environment-files-focused"
        }
      ]

      # Multiple environment files for layered configuration
      environmentFiles = [
        {
          value = "arn:aws:s3:::${aws_s3_bucket.env_configs.bucket}/${aws_s3_object.env_files["app-config.env"].key}"
          type  = "s3"
        },
        {
          value = "arn:aws:s3:::${aws_s3_bucket.env_configs.bucket}/${aws_s3_object.env_files["prod-config.env"].key}"
          type  = "s3"
        }
      ]

      # CloudWatch logging configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.envfiles.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name        = "${var.task_family}-envfiles"
    Purpose     = "ECS Task Definition"
    Description = "Task definition focused on environment files configuration management"
  })
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = [local.security_group_id]
    assign_public_ip = true
  }

  enable_execute_command = var.enable_execute_command

  # Ensure service waits for task definition and other dependencies
  depends_on = [
    aws_ecs_task_definition.main,
    aws_iam_role_policy_attachment.task_execution_policy,
    aws_iam_role_policy_attachment.parameter_store_access
  ]

  tags = merge(local.common_tags, {
    Name        = local.service_name
    Purpose     = "ECS Service"
    Description = "ECS service running tasks with environment variable management"
  })
}