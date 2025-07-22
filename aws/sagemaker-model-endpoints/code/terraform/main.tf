# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  unique_suffix = random_id.suffix.hex
  
  # S3 bucket name (must be globally unique)
  bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-models-${local.unique_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# KMS key for encryption (optional)
resource "aws_kms_key" "sagemaker_key" {
  count = var.enable_encryption && var.kms_key_id == "" ? 1 : 0
  
  description             = "KMS key for SageMaker endpoint encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SageMaker Service"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sagemaker-key"
  })
}

resource "aws_kms_alias" "sagemaker_key_alias" {
  count = var.enable_encryption && var.kms_key_id == "" ? 1 : 0
  
  name          = "alias/${local.name_prefix}-sagemaker-key"
  target_key_id = aws_kms_key.sagemaker_key[0].key_id
}

# ECR Repository for inference container
resource "aws_ecr_repository" "inference_repository" {
  name                 = var.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability
  force_delete         = true
  
  image_scanning_configuration {
    scan_on_push = var.ecr_image_scan_on_push
  }
  
  encryption_configuration {
    encryption_type = var.enable_encryption ? "KMS" : "AES256"
    kms_key         = var.enable_encryption && var.kms_key_id == "" ? aws_kms_key.sagemaker_key[0].arn : var.kms_key_id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-inference-repository"
  })
}

# ECR Repository Policy
resource "aws_ecr_repository_policy" "inference_repository_policy" {
  repository = aws_ecr_repository.inference_repository.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSageMakerAccess"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "inference_repository_lifecycle" {
  repository = aws_ecr_repository.inference_repository.name
  
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

# S3 Bucket for model artifacts
resource "aws_s3_bucket" "model_artifacts" {
  bucket        = local.bucket_name
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-model-artifacts"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "model_artifacts_versioning" {
  bucket = aws_s3_bucket.model_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts_encryption" {
  bucket = aws_s3_bucket.model_artifacts.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_encryption && var.kms_key_id == "" ? aws_kms_key.sagemaker_key[0].arn : var.kms_key_id
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "model_artifacts_pab" {
  bucket = aws_s3_bucket.model_artifacts.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "model_artifacts_lifecycle" {
  bucket = aws_s3_bucket.model_artifacts.id
  
  rule {
    id     = "model_artifacts_lifecycle"
    status = "Enabled"
    
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# IAM Role for SageMaker Execution
resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${local.name_prefix}-sagemaker-execution-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sagemaker-execution-role"
  })
}

# IAM Policy for SageMaker Execution Role
resource "aws_iam_policy" "sagemaker_execution_policy" {
  name        = "${local.name_prefix}-sagemaker-execution-policy"
  description = "Policy for SageMaker execution role"
  
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
          aws_s3_bucket.model_artifacts.arn,
          "${aws_s3_bucket.model_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Additional KMS permissions for the execution role if encryption is enabled
resource "aws_iam_policy" "sagemaker_kms_policy" {
  count = var.enable_encryption ? 1 : 0
  
  name        = "${local.name_prefix}-sagemaker-kms-policy"
  description = "KMS permissions for SageMaker execution role"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = var.kms_key_id != "" ? var.kms_key_id : aws_kms_key.sagemaker_key[0].arn
      }
    ]
  })
}

# Attach policies to the SageMaker execution role
resource "aws_iam_role_policy_attachment" "sagemaker_execution_policy_attachment" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_execution_policy.arn
}

resource "aws_iam_role_policy_attachment" "sagemaker_kms_policy_attachment" {
  count = var.enable_encryption ? 1 : 0
  
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = aws_iam_policy.sagemaker_kms_policy[0].arn
}

# CloudWatch Log Group for SageMaker Endpoint
resource "aws_cloudwatch_log_group" "sagemaker_endpoint_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/sagemaker/Endpoints/${local.name_prefix}-${var.model_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.enable_encryption && var.kms_key_id == "" ? aws_kms_key.sagemaker_key[0].arn : var.kms_key_id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-logs"
  })
}

# SageMaker Model
resource "aws_sagemaker_model" "ml_model" {
  name               = "${local.name_prefix}-${var.model_name}"
  execution_role_arn = aws_iam_role.sagemaker_execution_role.arn
  
  primary_container {
    image          = var.container_image_uri != "" ? var.container_image_uri : "${aws_ecr_repository.inference_repository.repository_url}:latest"
    model_data_url = var.model_data_url != "" ? var.model_data_url : "s3://${aws_s3_bucket.model_artifacts.bucket}/model.tar.gz"
    
    environment = {
      SAGEMAKER_PROGRAM         = "predictor.py"
      SAGEMAKER_SUBMIT_DIRECTORY = "/opt/ml/code"
    }
  }
  
  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = var.enable_vpc_config ? [1] : []
    content {
      security_group_ids = var.security_group_ids
      subnets           = var.subnet_ids
    }
  }
  
  # Enable network isolation for enhanced security
  enable_network_isolation = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.model_name}"
  })
}

# SageMaker Endpoint Configuration
resource "aws_sagemaker_endpoint_configuration" "ml_endpoint_config" {
  name = "${local.name_prefix}-${var.model_name}-config"
  
  production_variants {
    variant_name           = "primary"
    model_name            = aws_sagemaker_model.ml_model.name
    initial_instance_count = var.endpoint_initial_instance_count
    instance_type         = var.endpoint_instance_type
    initial_variant_weight = var.endpoint_initial_variant_weight
  }
  
  # Data capture configuration for model monitoring
  data_capture_config {
    enable_capture                = true
    initial_sampling_percentage   = 100
    destination_s3_uri           = "s3://${aws_s3_bucket.model_artifacts.bucket}/data-capture"
    
    capture_options {
      capture_mode = "Input"
    }
    
    capture_options {
      capture_mode = "Output"
    }
    
    capture_content_type_header {
      json_content_types = ["application/json"]
    }
  }
  
  # KMS encryption for endpoint
  dynamic "kms_key_id" {
    for_each = var.enable_encryption ? [1] : []
    content {
      kms_key_id = var.kms_key_id != "" ? var.kms_key_id : aws_kms_key.sagemaker_key[0].arn
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.model_name}-config"
  })
}

# SageMaker Endpoint
resource "aws_sagemaker_endpoint" "ml_endpoint" {
  name                 = "${local.name_prefix}-${var.model_name}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.ml_endpoint_config.name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.model_name}-endpoint"
  })
}

# Auto Scaling Target for the SageMaker Endpoint
resource "aws_appautoscaling_target" "sagemaker_target" {
  count = var.enable_auto_scaling ? 1 : 0
  
  max_capacity       = var.auto_scaling_max_capacity
  min_capacity       = var.auto_scaling_min_capacity
  resource_id        = "endpoint/${aws_sagemaker_endpoint.ml_endpoint.name}/variant/primary"
  scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
  service_namespace  = "sagemaker"
  
  tags = local.common_tags
}

# Auto Scaling Policy
resource "aws_appautoscaling_policy" "sagemaker_scaling_policy" {
  count = var.enable_auto_scaling ? 1 : 0
  
  name               = "${local.name_prefix}-sagemaker-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.sagemaker_target[0].resource_id
  scalable_dimension = aws_appautoscaling_target.sagemaker_target[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.sagemaker_target[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
    }
    target_value = var.auto_scaling_target_value
  }
}

# SNS Topic for alerts (optional)
resource "aws_sns_topic" "sagemaker_alerts" {
  count = var.enable_sns_notifications ? 1 : 0
  
  name         = "${local.name_prefix}-sagemaker-alerts"
  display_name = "SageMaker Endpoint Alerts"
  
  kms_master_key_id = var.enable_encryption && var.kms_key_id == "" ? aws_kms_key.sagemaker_key[0].arn : var.kms_key_id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sagemaker-alerts"
  })
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.enable_sns_notifications && var.sns_email_endpoint != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.sagemaker_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# CloudWatch Alarms for Endpoint Monitoring
resource "aws_cloudwatch_metric_alarm" "endpoint_invocation_errors" {
  count = var.enable_endpoint_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-endpoint-invocation-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Invocation4XXErrors"
  namespace           = "AWS/SageMaker"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors SageMaker endpoint 4XX errors"
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  
  dimensions = {
    EndpointName = aws_sagemaker_endpoint.ml_endpoint.name
    VariantName  = "primary"
  }
  
  alarm_actions = var.enable_sns_notifications ? [aws_sns_topic.sagemaker_alerts[0].arn] : []
  ok_actions    = var.enable_sns_notifications ? [aws_sns_topic.sagemaker_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-invocation-errors"
  })
}

resource "aws_cloudwatch_metric_alarm" "endpoint_model_errors" {
  count = var.enable_endpoint_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-endpoint-model-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Invocation5XXErrors"
  namespace           = "AWS/SageMaker"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors SageMaker endpoint 5XX errors"
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  
  dimensions = {
    EndpointName = aws_sagemaker_endpoint.ml_endpoint.name
    VariantName  = "primary"
  }
  
  alarm_actions = var.enable_sns_notifications ? [aws_sns_topic.sagemaker_alerts[0].arn] : []
  ok_actions    = var.enable_sns_notifications ? [aws_sns_topic.sagemaker_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-model-errors"
  })
}

resource "aws_cloudwatch_metric_alarm" "endpoint_latency" {
  count = var.enable_endpoint_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-endpoint-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "ModelLatency"
  namespace           = "AWS/SageMaker"
  period              = "300"
  statistic           = "Average"
  threshold           = "10000"  # 10 seconds in milliseconds
  alarm_description   = "This metric monitors SageMaker endpoint latency"
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  
  dimensions = {
    EndpointName = aws_sagemaker_endpoint.ml_endpoint.name
    VariantName  = "primary"
  }
  
  alarm_actions = var.enable_sns_notifications ? [aws_sns_topic.sagemaker_alerts[0].arn] : []
  ok_actions    = var.enable_sns_notifications ? [aws_sns_topic.sagemaker_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-endpoint-high-latency"
  })
}

# CloudWatch Dashboard for SageMaker Endpoint Monitoring
resource "aws_cloudwatch_dashboard" "sagemaker_dashboard" {
  count = var.enable_endpoint_monitoring ? 1 : 0
  
  dashboard_name = "${local.name_prefix}-sagemaker-dashboard"
  
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
            ["AWS/SageMaker", "Invocations", "EndpointName", aws_sagemaker_endpoint.ml_endpoint.name, "VariantName", "primary"],
            [".", "Invocation4XXErrors", ".", ".", ".", "."],
            [".", "Invocation5XXErrors", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "SageMaker Endpoint Invocations and Errors"
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
            ["AWS/SageMaker", "ModelLatency", "EndpointName", aws_sagemaker_endpoint.ml_endpoint.name, "VariantName", "primary"],
            [".", "OverheadLatency", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "SageMaker Endpoint Latency"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/SageMaker", "CPUUtilization", "EndpointName", aws_sagemaker_endpoint.ml_endpoint.name, "VariantName", "primary"],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "SageMaker Endpoint Resource Utilization"
          period  = 300
        }
      }
    ]
  })
}