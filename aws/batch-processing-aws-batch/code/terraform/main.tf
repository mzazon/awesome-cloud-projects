# ======================================================================
# AWS Batch Processing Workloads Infrastructure
# 
# This Terraform configuration creates a complete AWS Batch processing
# environment based on the recipe "Batch Processing Workloads with AWS Batch"
#
# Components created:
# - AWS Batch Compute Environment with EC2 instances (including Spot support)
# - Job Queue for managing job submissions  
# - Job Definition with containerized workload configuration
# - ECR Repository for container image storage
# - IAM Roles and Policies for secure access
# - Security Groups for network isolation
# - CloudWatch Log Group for centralized logging
# - CloudWatch Alarms for monitoring and alerting
# - SNS Topic for notifications (optional)
# ======================================================================

# Data sources for existing infrastructure
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get default VPC if none specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get all subnets in the VPC if none specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Local values for computed configurations
locals {
  vpc_id                    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids               = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  compute_environment_name = var.compute_environment_name != "" ? var.compute_environment_name : "${var.project_name}-compute-env-${random_string.suffix.result}"
  job_queue_name          = var.job_queue_name != "" ? var.job_queue_name : "${var.project_name}-job-queue-${random_string.suffix.result}"
  job_definition_name     = var.job_definition_name != "" ? var.job_definition_name : "${var.project_name}-job-def-${random_string.suffix.result}"
  ecr_repository_name     = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.project_name}-${random_string.suffix.result}"
  
  common_tags = merge(
    {
      Name        = var.project_name
      Environment = var.environment
      Project     = "AWS Batch Processing Workloads"
      ManagedBy   = "Terraform"
      Recipe      = "batch-processing-workloads-aws-batch"
    },
    var.additional_tags
  )
}

# ======================================================================
# SECURITY GROUPS
# ======================================================================

# Security Group for Batch Compute Environment
resource "aws_security_group" "batch_compute" {
  name_prefix = "${var.project_name}-batch-sg-"
  description = "Security group for AWS Batch compute environment"
  vpc_id      = local.vpc_id

  # Allow all outbound traffic for downloading packages and accessing AWS services
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-batch-security-group"
    Type = "SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ======================================================================
# IAM ROLES AND POLICIES
# ======================================================================

# IAM Policy Document for AWS Batch Service Role
data "aws_iam_policy_document" "batch_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# IAM Role for AWS Batch Service
resource "aws_iam_role" "batch_service_role" {
  name_prefix        = "${var.project_name}-batch-service-"
  assume_role_policy = data.aws_iam_policy_document.batch_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-batch-service-role"
    Type = "IAMRole"
  })
}

# Attach AWS managed policy for Batch service
resource "aws_iam_role_policy_attachment" "batch_service_role_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# IAM Policy Document for ECS Instance Role
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM Role for ECS Instance Profile
resource "aws_iam_role" "ecs_instance_role" {
  name_prefix        = "${var.project_name}-ecs-instance-"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-instance-role"
    Type = "IAMRole"
  })
}

# Attach AWS managed policy for ECS instance
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Additional policy for enhanced logging and monitoring
resource "aws_iam_role_policy" "ecs_instance_additional" {
  name_prefix = "${var.project_name}-ecs-additional-"
  role        = aws_iam_role.ecs_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.batch_jobs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile for ECS instances
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name_prefix = "${var.project_name}-ecs-instance-profile-"
  role        = aws_iam_role.ecs_instance_role.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-instance-profile"
    Type = "IAMInstanceProfile"
  })
}

# ======================================================================
# ECR REPOSITORY
# ======================================================================

# ECR Repository for storing container images
resource "aws_ecr_repository" "batch_repo" {
  count = var.create_ecr_repository ? 1 : 0
  
  name                 = local.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_image_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecr-repository"
    Type = "ECRRepository"
  })
}

# ECR Repository Policy for secure access
resource "aws_ecr_repository_policy" "batch_repo_policy" {
  count      = var.create_ecr_repository ? 1 : 0
  repository = aws_ecr_repository.batch_repo[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
            aws_iam_role.ecs_instance_role.arn
          ]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}

# ECR Lifecycle Policy to manage image retention
resource "aws_ecr_lifecycle_policy" "batch_repo_lifecycle" {
  count      = var.create_ecr_repository ? 1 : 0
  repository = aws_ecr_repository.batch_repo[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_image_retention_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_image_retention_count
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

# ======================================================================
# CLOUDWATCH LOGGING
# ======================================================================

# CloudWatch Log Group for Batch jobs
resource "aws_cloudwatch_log_group" "batch_jobs" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_log_encryption ? aws_kms_key.batch_logs[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-batch-log-group"
    Type = "CloudWatchLogGroup"
  })
}

# KMS Key for CloudWatch Logs encryption (optional)
resource "aws_kms_key" "batch_logs" {
  count = var.enable_log_encryption ? 1 : 0
  
  description = "KMS key for AWS Batch CloudWatch logs encryption"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-batch-logs-key"
    Type = "KMSKey"
  })
}

# KMS Key Alias for easier identification
resource "aws_kms_alias" "batch_logs" {
  count         = var.enable_log_encryption ? 1 : 0
  name          = "alias/${var.project_name}-batch-logs-${random_string.suffix.result}"
  target_key_id = aws_kms_key.batch_logs[0].key_id
}

# ======================================================================
# AWS BATCH INFRASTRUCTURE
# ======================================================================

# AWS Batch Compute Environment
resource "aws_batch_compute_environment" "main" {
  compute_environment_name_prefix = "${var.project_name}-compute-env-"
  type                           = "MANAGED"
  state                          = "ENABLED"
  service_role                   = aws_iam_role.batch_service_role.arn

  compute_resources {
    type               = var.compute_environment_type
    allocation_strategy = var.allocation_strategy
    min_vcpus          = var.min_vcpus
    max_vcpus          = var.max_vcpus
    desired_vcpus      = var.desired_vcpus
    instance_types     = var.instance_types
    
    # Configure EC2 instances with Amazon Linux 2 ECS-optimized AMI
    ec2_configuration {
      image_type = var.ec2_image_type
    }
    
    # Spot instance configuration
    bid_percentage = var.compute_environment_type == "SPOT" ? var.spot_instance_percentage : null
    
    # Launch template configuration (optional)
    dynamic "launch_template" {
      for_each = var.launch_template_id != "" || var.launch_template_name != "" ? [1] : []
      content {
        launch_template_id   = var.launch_template_id != "" ? var.launch_template_id : null
        launch_template_name = var.launch_template_name != "" ? var.launch_template_name : null
        version             = var.launch_template_version
      }
    }
    
    subnets            = local.subnet_ids
    security_group_ids = [aws_security_group.batch_compute.id]
    instance_role      = aws_iam_instance_profile.ecs_instance_profile.arn

    # EC2 key pair for SSH access (optional)
    ec2_key_pair = var.ec2_key_pair_name != "" ? var.ec2_key_pair_name : null

    tags = merge(local.common_tags, {
      Name = "${var.project_name}-batch-compute-instance"
      Type = "BatchComputeInstance"
    })
  }

  # Update policy for managing infrastructure updates
  dynamic "update_policy" {
    for_each = var.enable_update_policy ? [1] : []
    content {
      job_execution_timeout_minutes = var.job_execution_timeout_minutes
      terminate_jobs_on_update      = var.terminate_jobs_on_update
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role_policy
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-compute-environment"
    Type = "BatchComputeEnvironment"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# AWS Batch Job Queue
resource "aws_batch_job_queue" "main" {
  name     = local.job_queue_name
  state    = "ENABLED"
  priority = var.job_queue_priority

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.main.arn
  }

  # Support for scheduling policy (if provided)
  dynamic "scheduling_policy_arn" {
    for_each = var.scheduling_policy_arn != "" ? [1] : []
    content {
      scheduling_policy_arn = var.scheduling_policy_arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-job-queue"
    Type = "BatchJobQueue"
  })
}

# AWS Batch Job Definition
resource "aws_batch_job_definition" "main" {
  name = local.job_definition_name
  type = "container"

  # Container properties with comprehensive configuration
  container_properties = jsonencode({
    image     = var.container_image
    vcpus     = var.job_vcpus
    memory    = var.job_memory
    jobRoleArn = var.job_role_arn != "" ? var.job_role_arn : null

    # Environment variables for job configuration
    environment = [
      for key, value in var.job_environment_variables : {
        name  = key
        value = tostring(value)
      }
    ]

    # Mount points for EFS or other file systems (if configured)
    mountPoints = var.enable_efs ? [
      {
        sourceVolume  = "efs-volume"
        containerPath = "/shared"
        readOnly      = false
      }
    ] : []

    # Volumes configuration for EFS
    volumes = var.enable_efs ? [
      {
        name = "efs-volume"
        efsVolumeConfiguration = {
          fileSystemId = var.efs_file_system_id
          rootDirectory = "/"
          transitEncryption = "ENABLED"
          authorizationConfig = {
            accessPointId = var.efs_access_point_id
            iam = "ENABLED"
          }
        }
      }
    ] : []

    # Logging configuration
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_jobs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "batch"
      }
    }

    # Resource requirements for advanced configurations
    resourceRequirements = concat(
      var.job_vcpus > 0 ? [{ type = "VCPU", value = tostring(var.job_vcpus) }] : [],
      var.job_memory > 0 ? [{ type = "MEMORY", value = tostring(var.job_memory) }] : [],
      var.job_gpu_count > 0 ? [{ type = "GPU", value = tostring(var.job_gpu_count) }] : []
    )

    # Fargate platform configuration (if using Fargate)
    fargatePlatformConfiguration = var.fargate_platform_version != "" ? {
      platformVersion = var.fargate_platform_version
    } : null

    # Ulimits for resource constraints
    ulimits = var.enable_ulimits ? [
      {
        name      = "nofile"
        softLimit = 65536
        hardLimit = 65536
      }
    ] : []
  })

  # Retry strategy for failed jobs
  retry_strategy {
    attempts = var.job_retry_attempts
  }

  # Timeout configuration
  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }

  # Parameters for job parameterization
  dynamic "parameters" {
    for_each = var.job_parameters
    content {
      parameters = var.job_parameters
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-job-definition"
    Type = "BatchJobDefinition"
  })
}

# ======================================================================
# MONITORING AND ALERTING
# ======================================================================

# SNS Topic for CloudWatch Alarms (optional)
resource "aws_sns_topic" "batch_alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? 1 : 0
  
  name              = "${var.project_name}-batch-alerts-${random_string.suffix.result}"
  kms_master_key_id = var.enable_sns_encryption ? "alias/aws/sns" : null

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-batch-alerts"
    Type = "SNSTopic"
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "batch_email_alerts" {
  count = var.enable_cloudwatch_alarms && var.alarm_email_endpoint != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.batch_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoint
}

# CloudWatch Alarm for Failed Jobs
resource "aws_cloudwatch_metric_alarm" "failed_jobs" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-batch-failed-jobs-${random_string.suffix.result}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.failed_jobs_evaluation_periods
  metric_name         = "FailedJobs"
  namespace           = "AWS/Batch"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.failed_jobs_threshold
  alarm_description   = "This metric monitors failed batch jobs in queue ${aws_batch_job_queue.main.name}"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.batch_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobQueue = aws_batch_job_queue.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-failed-jobs-alarm"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch Alarm for High Queue Utilization
resource "aws_cloudwatch_metric_alarm" "queue_utilization" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-batch-queue-utilization-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.queue_utilization_evaluation_periods
  metric_name         = "SubmittedJobs"
  namespace           = "AWS/Batch"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.queue_utilization_threshold
  alarm_description   = "This metric monitors batch job queue utilization for ${aws_batch_job_queue.main.name}"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.batch_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobQueue = aws_batch_job_queue.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-queue-utilization-alarm"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch Alarm for Compute Environment Issues
resource "aws_cloudwatch_metric_alarm" "compute_environment_issues" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${var.project_name}-batch-compute-env-issues-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "RunnableJobs"
  namespace           = "AWS/Batch"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "This metric monitors if jobs are stuck in runnable state indicating compute environment issues"
  alarm_actions       = var.alarm_email_endpoint != "" ? [aws_sns_topic.batch_alerts[0].arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobQueue = aws_batch_job_queue.main.name
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-compute-env-issues-alarm"
    Type = "CloudWatchAlarm"
  })
}

# CloudWatch Dashboard for Batch monitoring (optional)
resource "aws_cloudwatch_dashboard" "batch_dashboard" {
  count = var.create_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "${var.project_name}-batch-dashboard-${random_string.suffix.result}"

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
            ["AWS/Batch", "SubmittedJobs", "JobQueue", aws_batch_job_queue.main.name],
            [".", "RunnableJobs", ".", "."],
            [".", "RunningJobs", ".", "."],
            [".", "FailedJobs", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Batch Job Metrics"
          period  = 300
        }
      }
    ]
  })
}