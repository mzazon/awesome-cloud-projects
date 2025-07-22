# Cost-Optimized Batch Processing with AWS Batch and Spot Instances
# This Terraform configuration creates a complete AWS Batch environment
# optimized for cost-effective batch processing using Spot instances

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if specified
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

# Get default VPC subnets if using default VPC
data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

# Local values for computed resource names
locals {
  random_suffix = random_string.suffix.result
  
  # Resource names with random suffix
  ecr_repository_name      = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.project_name}-${local.random_suffix}"
  compute_environment_name = var.compute_environment_name != "" ? var.compute_environment_name : "spot-compute-env-${local.random_suffix}"
  job_queue_name          = var.job_queue_name != "" ? var.job_queue_name : "spot-job-queue-${local.random_suffix}"
  job_definition_name     = var.job_definition_name != "" ? var.job_definition_name : "batch-job-def-${local.random_suffix}"
  
  # VPC and subnet configuration
  vpc_id     = var.use_default_vpc ? data.aws_vpc.default[0].id : var.vpc_id
  subnet_ids = var.use_default_vpc ? data.aws_subnets.default[0].ids : var.subnet_ids
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# AWS Batch Service Role
# This role allows AWS Batch to manage compute resources on your behalf
resource "aws_iam_role" "batch_service_role" {
  name = var.batch_service_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach the AWS managed policy for Batch service role
resource "aws_iam_role_policy_attachment" "batch_service_role_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# EC2 Instance Role for Batch Compute Environment
# This role allows EC2 instances to register with ECS and pull container images
resource "aws_iam_role" "instance_role" {
  name = var.instance_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach the AWS managed policy for ECS instance role
resource "aws_iam_role_policy_attachment" "instance_role_policy" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Create instance profile for EC2 instances
resource "aws_iam_instance_profile" "instance_profile" {
  name = var.instance_role_name
  role = aws_iam_role.instance_role.name
  tags = local.common_tags
}

# ECS Task Execution Role for Batch Jobs
# This role allows ECS tasks to pull container images and write logs
resource "aws_iam_role" "job_execution_role" {
  name = var.job_execution_role_name

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

# Attach the AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "job_execution_role_policy" {
  role       = aws_iam_role.job_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# =============================================================================
# NETWORKING
# =============================================================================

# Security Group for Batch Compute Environment
# Allows outbound traffic for container image pulls and logging
resource "aws_security_group" "batch_security_group" {
  name_prefix = "batch-sg-"
  description = "Security group for AWS Batch compute environment"
  vpc_id      = local.vpc_id

  # Allow all outbound traffic (required for ECR pulls and CloudWatch logs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic for container pulls and logging"
  }

  tags = merge(local.common_tags, {
    Name = "batch-security-group-${local.random_suffix}"
  })
}

# =============================================================================
# CONTAINER REGISTRY
# =============================================================================

# ECR Repository for Batch Container Images
resource "aws_ecr_repository" "batch_repository" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  # Enable image scanning for security
  image_scanning_configuration {
    scan_on_push = true
  }

  # Lifecycle policy to manage image costs
  lifecycle {
    ignore_changes = [image_scanning_configuration]
  }

  tags = local.common_tags
}

# ECR Lifecycle Policy to manage image retention and costs
resource "aws_ecr_lifecycle_policy" "batch_repository_policy" {
  repository = aws_ecr_repository.batch_repository.name

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

# =============================================================================
# AWS BATCH COMPUTE ENVIRONMENT
# =============================================================================

# AWS Batch Compute Environment with Spot Instances
# Optimized for cost-effective batch processing with fault tolerance
resource "aws_batch_compute_environment" "spot_compute_environment" {
  compute_environment_name = local.compute_environment_name
  type                    = "MANAGED"
  state                   = "ENABLED"
  service_role            = aws_iam_role.batch_service_role.arn

  compute_resources {
    type                = "EC2"
    allocation_strategy = "SPOT_CAPACITY_OPTIMIZED"
    min_vcpus          = var.min_vcpus
    max_vcpus          = var.max_vcpus
    desired_vcpus      = var.desired_vcpus
    instance_types     = var.instance_types
    
    # Spot instance configuration for cost optimization
    spot_iam_fleet_request_role = aws_iam_role.spot_fleet_role.arn
    bid_percentage             = var.spot_bid_percentage

    # Use ECS-optimized AMI
    ec2_configuration {
      image_type = "ECS_AL2"
    }

    # Network configuration
    subnets         = local.subnet_ids
    security_group_ids = [aws_security_group.batch_security_group.id]
    
    # Instance profile for EC2 instances
    instance_role = aws_iam_instance_profile.instance_profile.arn

    # Resource tags
    tags = merge(local.common_tags, {
      Name = "batch-compute-${local.random_suffix}"
    })
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role_policy,
    aws_iam_role_policy_attachment.spot_fleet_role_policy
  ]

  tags = local.common_tags
}

# IAM Role for Spot Fleet (required for Spot instances)
resource "aws_iam_role" "spot_fleet_role" {
  name = "aws-ec2-spot-fleet-role-${local.random_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Attach the AWS managed policy for Spot Fleet
resource "aws_iam_role_policy_attachment" "spot_fleet_role_policy" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# =============================================================================
# AWS BATCH JOB QUEUE
# =============================================================================

# AWS Batch Job Queue
# Manages job scheduling and prioritization
resource "aws_batch_job_queue" "job_queue" {
  name                 = local.job_queue_name
  state                = "ENABLED"
  priority             = 1
  compute_environments = [aws_batch_compute_environment.spot_compute_environment.arn]

  tags = local.common_tags
}

# =============================================================================
# AWS BATCH JOB DEFINITION
# =============================================================================

# AWS Batch Job Definition
# Defines container configuration and retry strategy for Spot instances
resource "aws_batch_job_definition" "job_definition" {
  name = local.job_definition_name
  type = "container"

  # Container properties
  container_properties = jsonencode({
    image  = "${aws_ecr_repository.batch_repository.repository_url}:latest"
    vcpus  = var.job_vcpus
    memory = var.job_memory
    
    # Job execution role for pulling images and logging
    jobRoleArn = aws_iam_role.job_execution_role.arn
    
    # Environment variables
    environment = [
      {
        name  = "AWS_DEFAULT_REGION"
        value = data.aws_region.current.name
      },
      {
        name  = "BATCH_JOB_QUEUE"
        value = local.job_queue_name
      }
    ]
    
    # Log configuration
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_logs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "batch-job"
      }
    }
  })

  # Retry strategy optimized for Spot instances
  retry_strategy {
    attempts = var.retry_attempts
    
    # Retry on Spot instance interruptions, but not on application failures
    evaluate_on_exit {
      action           = "RETRY"
      on_status_reason = "Host EC2*"
    }
    
    evaluate_on_exit {
      action    = "EXIT"
      on_reason = "*"
    }
  }

  # Job timeout configuration
  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }

  tags = local.common_tags
}

# =============================================================================
# CLOUDWATCH LOGS
# =============================================================================

# CloudWatch Log Group for Batch Jobs
resource "aws_cloudwatch_log_group" "batch_logs" {
  name              = "/aws/batch/job/${local.job_definition_name}"
  retention_in_days = 7

  tags = local.common_tags
}

# =============================================================================
# CLOUDWATCH ALARMS AND MONITORING
# =============================================================================

# CloudWatch Alarm for Failed Jobs
resource "aws_cloudwatch_metric_alarm" "failed_jobs_alarm" {
  alarm_name          = "batch-failed-jobs-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FailedJobs"
  namespace           = "AWS/Batch"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors failed batch jobs"
  alarm_actions       = []

  dimensions = {
    JobQueue = aws_batch_job_queue.job_queue.name
  }

  tags = local.common_tags
}

# CloudWatch Alarm for Spot Instance Interruptions
resource "aws_cloudwatch_metric_alarm" "spot_interruption_alarm" {
  alarm_name          = "batch-spot-interruptions-${local.random_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SpotInstanceTerminations"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "This metric monitors Spot instance interruptions"
  alarm_actions       = []

  tags = local.common_tags
}