# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC and subnets if using default VPC
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
  vpc_id      = var.use_default_vpc ? data.aws_vpc.default[0].id : var.vpc_id
  subnet_ids  = var.use_default_vpc ? data.aws_subnets.default[0].ids : var.subnet_ids
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# KMS Key for encryption (if enabled)
resource "aws_kms_key" "hpc_key" {
  count                   = var.enable_encryption ? 1 : 0
  description             = "KMS key for HPC Batch infrastructure encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "hpc_key_alias" {
  count         = var.enable_encryption ? 1 : 0
  name          = "alias/${local.name_prefix}-hpc-key"
  target_key_id = aws_kms_key.hpc_key[0].key_id
}

# S3 Bucket for HPC data storage
resource "aws_s3_bucket" "hpc_data" {
  bucket = "${local.name_prefix}-${var.s3_bucket_name}"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.s3_bucket_name}"
  })
}

resource "aws_s3_bucket_versioning" "hpc_data_versioning" {
  bucket = aws_s3_bucket.hpc_data.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_public_access_block" "hpc_data_pab" {
  bucket = aws_s3_bucket.hpc_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hpc_data_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.hpc_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.hpc_key[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "hpc_data_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.hpc_data.id

  rule {
    id     = "hpc_data_lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    transition {
      days          = 180
      storage_class = "DEEP_ARCHIVE"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# EFS File System for shared storage (if enabled)
resource "aws_efs_file_system" "hpc_shared_storage" {
  count           = var.enable_efs ? 1 : 0
  performance_mode = var.efs_performance_mode
  throughput_mode = var.efs_throughput_mode
  
  dynamic "provisioned_throughput_in_mibps" {
    for_each = var.efs_throughput_mode == "provisioned" ? [var.efs_provisioned_throughput_mibps] : []
    content {
      provisioned_throughput_in_mibps = provisioned_throughput_in_mibps.value
    }
  }

  encrypted  = var.enable_encryption
  kms_key_id = var.enable_encryption ? aws_kms_key.hpc_key[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-shared-storage"
  })
}

# Security Group for EFS
resource "aws_security_group" "efs_sg" {
  count       = var.enable_efs ? 1 : 0
  name        = "${local.name_prefix}-efs-sg"
  description = "Security group for EFS file system access"
  vpc_id      = local.vpc_id

  ingress {
    from_port = 2049
    to_port   = 2049
    protocol  = "tcp"
    self      = true
    description = "NFS traffic from compute instances"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs-sg"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "hpc_shared_storage_mt" {
  count           = var.enable_efs ? length(local.subnet_ids) : 0
  file_system_id  = aws_efs_file_system.hpc_shared_storage[0].id
  subnet_id       = local.subnet_ids[count.index]
  security_groups = [aws_security_group.efs_sg[0].id]
}

# Security Group for Batch Compute Environment
resource "aws_security_group" "batch_compute_sg" {
  name        = "${local.name_prefix}-batch-compute-sg"
  description = "Security group for AWS Batch compute environment"
  vpc_id      = local.vpc_id

  # Allow access to EFS if enabled
  dynamic "egress" {
    for_each = var.enable_efs ? [1] : []
    content {
      from_port       = 2049
      to_port         = 2049
      protocol        = "tcp"
      security_groups = [aws_security_group.efs_sg[0].id]
      description     = "NFS traffic to EFS"
    }
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic for AWS API calls"
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP traffic for package downloads"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-compute-sg"
  })
}

# IAM Role for Batch Service
resource "aws_iam_role" "batch_service_role" {
  name = "${local.name_prefix}-batch-service-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-service-role"
  })
}

resource "aws_iam_role_policy_attachment" "batch_service_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "${local.name_prefix}-ecs-instance-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-instance-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Additional policy for S3 access
resource "aws_iam_role_policy" "s3_access_policy" {
  name = "${local.name_prefix}-s3-access-policy"
  role = aws_iam_role.ecs_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.hpc_data.arn,
          "${aws_s3_bucket.hpc_data.arn}/*"
        ]
      }
    ]
  })
}

# Instance Profile for EC2 Instances
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${local.name_prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-instance-profile"
  })
}

# AWS Batch Compute Environment
resource "aws_batch_compute_environment" "hpc_spot_compute" {
  compute_environment_name = "${local.name_prefix}-spot-compute"
  type                     = "MANAGED"
  state                    = "ENABLED"
  service_role             = aws_iam_role.batch_service_role.arn

  compute_resources {
    type                = "EC2"
    allocation_strategy = var.allocation_strategy
    min_vcpus          = 0
    max_vcpus          = var.max_vcpus
    desired_vcpus      = var.desired_vcpus
    instance_types     = var.instance_types
    bid_percentage     = var.spot_bid_percentage

    ec2_configuration {
      image_type = "ECS_AL2"
    }

    subnets            = local.subnet_ids
    security_group_ids = [aws_security_group.batch_compute_sg.id]
    instance_role      = aws_iam_instance_profile.ecs_instance_profile.arn

    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-batch-compute"
    })
  }

  depends_on = [aws_iam_role_policy_attachment.batch_service_policy]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-spot-compute"
  })
}

# AWS Batch Job Queue
resource "aws_batch_job_queue" "hpc_job_queue" {
  name     = "${local.name_prefix}-job-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.hpc_spot_compute.arn
  }

  depends_on = [aws_batch_compute_environment.hpc_spot_compute]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-job-queue"
  })
}

# IAM Role for Batch Job Execution
resource "aws_iam_role" "batch_execution_role" {
  name = "${local.name_prefix}-batch-execution-role"

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
    Name = "${local.name_prefix}-batch-execution-role"
  })
}

resource "aws_iam_role_policy_attachment" "batch_execution_policy" {
  role       = aws_iam_role.batch_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# AWS Batch Job Definition
resource "aws_batch_job_definition" "hpc_simulation" {
  name = "${local.name_prefix}-simulation"
  type = "container"

  container_properties = jsonencode({
    image  = var.container_image
    vcpus  = var.job_vcpus
    memory = var.job_memory_mb
    
    jobRoleArn       = aws_iam_role.ecs_instance_role.arn
    executionRoleArn = aws_iam_role.batch_execution_role.arn

    command = [
      "sh", "-c",
      "echo Starting HPC simulation at $(date); sleep 300; echo Simulation completed at $(date)"
    ]

    environment = [
      {
        name  = "S3_BUCKET"
        value = aws_s3_bucket.hpc_data.bucket
      },
      {
        name  = "AWS_DEFAULT_REGION"
        value = data.aws_region.current.name
      }
    ]

    mountPoints = var.enable_efs ? [
      {
        sourceVolume  = "efs-storage"
        containerPath = "/shared"
        readOnly      = false
      }
    ] : []

    volumes = var.enable_efs ? [
      {
        name = "efs-storage"
        efsVolumeConfiguration = {
          fileSystemId = aws_efs_file_system.hpc_shared_storage[0].id
        }
      }
    ] : []

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.batch_logs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "batch"
      }
    }
  })

  retry_strategy {
    attempts = var.job_retry_attempts
  }

  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-simulation"
  })
}

# CloudWatch Log Group for Batch Jobs
resource "aws_cloudwatch_log_group" "batch_logs" {
  name              = "/aws/batch/job"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.hpc_key[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-logs"
  })
}

# CloudWatch Metric Filter for Cost Tracking
resource "aws_logs_metric_filter" "spot_savings_filter" {
  count          = var.enable_detailed_monitoring ? 1 : 0
  name           = "${local.name_prefix}-spot-savings"
  log_group_name = aws_cloudwatch_log_group.batch_logs.name
  pattern        = "[timestamp, level=\"INFO\", message=\"*SPOT_SAVINGS*\"]"

  metric_transformation {
    name      = "SpotSavings"
    namespace = "HPC/Batch"
    value     = "1"
  }
}

# CloudWatch Alarm for Failed Jobs
resource "aws_cloudwatch_metric_alarm" "failed_jobs_alarm" {
  count               = var.enable_detailed_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-failed-jobs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedJobs"
  namespace           = "AWS/Batch"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.failed_jobs_alarm_threshold
  alarm_description   = "This metric monitors failed Batch jobs"
  alarm_actions       = []

  dimensions = {
    JobQueue = aws_batch_job_queue.hpc_job_queue.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-failed-jobs-alarm"
  })
}

# CloudWatch Dashboard for HPC Monitoring
resource "aws_cloudwatch_dashboard" "hpc_dashboard" {
  count          = var.enable_detailed_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-hpc-dashboard"

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
            ["AWS/Batch", "SubmittedJobs", "JobQueue", aws_batch_job_queue.hpc_job_queue.name],
            [".", "RunnableJobs", ".", "."],
            [".", "RunningJobs", ".", "."],
            [".", "FailedJobs", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Batch Job Status"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceType", "c5.large"],
            [".", ".", ".", "c5.xlarge"],
            [".", ".", ".", "m5.large"],
            [".", ".", ".", "m5.xlarge"]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Instance CPU Utilization"
          period  = 300
        }
      }
    ]
  })
}