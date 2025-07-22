# ==============================================================================
# RANDOM SUFFIX FOR UNIQUE RESOURCE NAMING
# ==============================================================================

resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get subnets from VPC if not specified
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

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  # Use provided VPC ID or default VPC
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id

  # Use provided subnet IDs or default subnets
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids

  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex

  # Container image URI - use ECR repo if created, otherwise use default Python image
  container_image_uri = var.container_image != "" ? var.container_image : (
    var.create_ecr_repository ? 
    "${aws_ecr_repository.batch_processing[0].repository_url}:latest" : 
    "public.ecr.aws/lambda/python:3.9"
  )

  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "batch-processing-workloads-aws-batch-fargate"
    },
    var.additional_tags
  )
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM role for ECS task execution (Fargate)
data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "batch_execution_role" {
  name               = "${local.name_prefix}-batch-execution-role-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-execution-role-${local.name_suffix}"
  })
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "batch_execution_role_policy" {
  role       = aws_iam_role.batch_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM role for AWS Batch service
data "aws_iam_policy_document" "batch_service_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "batch_service_role" {
  name               = "${local.name_prefix}-batch-service-role-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.batch_service_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-service-role-${local.name_suffix}"
  })
}

# Attach AWS managed policy for Batch service
resource "aws_iam_role_policy_attachment" "batch_service_role_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# ==============================================================================
# SECURITY GROUPS
# ==============================================================================

resource "aws_security_group" "batch_fargate" {
  count       = var.create_security_group ? 1 : 0
  name        = "${local.name_prefix}-batch-fargate-sg-${local.name_suffix}"
  description = "Security group for AWS Batch Fargate tasks"
  vpc_id      = local.vpc_id

  # Egress rules - allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.allowed_egress_cidr_blocks
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-fargate-sg-${local.name_suffix}"
  })
}

# ==============================================================================
# ECR REPOSITORY (OPTIONAL)
# ==============================================================================

resource "aws_ecr_repository" "batch_processing" {
  count                = var.create_ecr_repository ? 1 : 0
  name                 = "${local.name_prefix}-batch-processing-${local.name_suffix}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_image_scanning
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-processing-${local.name_suffix}"
  })
}

# ECR repository policy to allow access from the same account
resource "aws_ecr_repository_policy" "batch_processing" {
  count      = var.create_ecr_repository ? 1 : 0
  repository = aws_ecr_repository.batch_processing[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy"
        ]
      }
    ]
  })
}

# ==============================================================================
# CLOUDWATCH LOG GROUP
# ==============================================================================

resource "aws_cloudwatch_log_group" "batch_jobs" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = var.log_group_name
  })
}

# ==============================================================================
# AWS BATCH COMPUTE ENVIRONMENT
# ==============================================================================

resource "aws_batch_compute_environment" "fargate" {
  compute_environment_name = "${local.name_prefix}-fargate-compute-${local.name_suffix}"
  type                     = "MANAGED"
  state                    = var.compute_environment_state
  service_role            = aws_iam_role.batch_service_role.arn

  compute_resources {
    type               = "FARGATE"
    max_vcpus          = var.max_vcpus
    security_group_ids = var.create_security_group ? [aws_security_group.batch_fargate[0].id] : []
    subnets           = local.subnet_ids
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fargate-compute-${local.name_suffix}"
  })

  depends_on = [aws_iam_role_policy_attachment.batch_service_role_policy]
}

# ==============================================================================
# AWS BATCH JOB QUEUE
# ==============================================================================

resource "aws_batch_job_queue" "main" {
  name     = "${local.name_prefix}-job-queue-${local.name_suffix}"
  state    = var.job_queue_state
  priority = var.job_queue_priority

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.fargate.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-job-queue-${local.name_suffix}"
  })

  depends_on = [aws_batch_compute_environment.fargate]
}

# ==============================================================================
# AWS BATCH JOB DEFINITION
# ==============================================================================

resource "aws_batch_job_definition" "main" {
  name = "${local.name_prefix}-job-definition-${local.name_suffix}"
  type = "container"
  
  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = local.container_image_uri
    
    resourceRequirements = [
      {
        type  = "VCPU"
        value = var.job_vcpu
      },
      {
        type  = "MEMORY"
        value = var.job_memory
      }
    ]

    executionRoleArn = aws_iam_role.batch_execution_role.arn

    networkConfiguration = {
      assignPublicIp = var.assign_public_ip ? "ENABLED" : "DISABLED"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "batch-fargate"
      }
    }

    # Default command - can be overridden at job submission
    command = ["python3", "-c", "print('Hello from AWS Batch with Fargate!')"]

    # Environment variables
    environment = [
      {
        name  = "AWS_DEFAULT_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "BATCH_ENVIRONMENT"
        value = var.environment
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-job-definition-${local.name_suffix}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.batch_execution_role_policy,
    aws_cloudwatch_log_group.batch_jobs
  ]
}

# ==============================================================================
# SAMPLE BATCH JOB DEFINITION WITH CUSTOM CONTAINER (if ECR repo is created)
# ==============================================================================

resource "aws_batch_job_definition" "custom_container" {
  count = var.create_ecr_repository ? 1 : 0
  name  = "${local.name_prefix}-custom-job-definition-${local.name_suffix}"
  type  = "container"
  
  platform_capabilities = ["FARGATE"]

  container_properties = jsonencode({
    image = aws_ecr_repository.batch_processing[0].repository_url
    
    resourceRequirements = [
      {
        type  = "VCPU"
        value = var.job_vcpu
      },
      {
        type  = "MEMORY"
        value = var.job_memory
      }
    ]

    executionRoleArn = aws_iam_role.batch_execution_role.arn

    networkConfiguration = {
      assignPublicIp = var.assign_public_ip ? "ENABLED" : "DISABLED"
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "batch-fargate-custom"
      }
    }

    # Environment variables for custom container
    environment = [
      {
        name  = "AWS_DEFAULT_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "BATCH_ENVIRONMENT"
        value = var.environment
      },
      {
        name  = "JOB_TYPE"
        value = "custom-processing"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-custom-job-definition-${local.name_suffix}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.batch_execution_role_policy,
    aws_cloudwatch_log_group.batch_jobs,
    aws_ecr_repository.batch_processing
  ]
}