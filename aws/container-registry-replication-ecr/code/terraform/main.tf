# Main Terraform configuration for ECR Container Registry Replication Strategies
# Implements comprehensive multi-region container registry replication with monitoring

# Data sources for account information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Generate unique repository names with random suffix
  production_repo_name = "${var.repository_prefix}/production-${random_string.suffix.result}"
  testing_repo_name    = "${var.repository_prefix}/testing-${random_string.suffix.result}"
  
  # Common resource naming
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Account ID for replication configuration
  account_id = data.aws_caller_identity.current.account_id
  
  # Common tags for all resources
  common_tags = merge(var.default_tags, {
    Environment = var.environment
    Suffix      = random_string.suffix.result
  })
}

# ============================================================================
# ECR REPOSITORIES (SOURCE REGION)
# ============================================================================

# Production ECR Repository with immutable tags
resource "aws_ecr_repository" "production" {
  name                 = local.production_repo_name
  image_tag_mutability = "IMMUTABLE"
  
  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-production-repo"
    Repository  = "production"
    Purpose     = "Production container images"
  })
}

# Testing ECR Repository with mutable tags
resource "aws_ecr_repository" "testing" {
  name                 = local.testing_repo_name
  image_tag_mutability = "MUTABLE"
  
  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }
  
  encryption_configuration {
    encryption_type = "AES256"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.resource_prefix}-testing-repo"
    Repository  = "testing"
    Purpose     = "Testing and development container images"
  })
}

# ============================================================================
# ECR LIFECYCLE POLICIES
# ============================================================================

# Production Repository Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "production" {
  repository = aws_ecr_repository.production.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.production_image_retention_count} production images"
        selection = {
          tagStatus      = "tagged"
          tagPrefixList  = ["prod", "release"]
          countType      = "imageCountMoreThan"
          countNumber    = var.production_image_retention_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than ${var.untagged_image_retention_days} day(s)"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Testing Repository Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "testing" {
  repository = aws_ecr_repository.testing.name
  
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.testing_image_retention_count} testing images"
        selection = {
          tagStatus      = "tagged"
          tagPrefixList  = ["test", "dev", "staging"]
          countType      = "imageCountMoreThan"
          countNumber    = var.testing_image_retention_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete images older than ${var.testing_image_retention_days} days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.testing_image_retention_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# IAM ROLES FOR ECR ACCESS
# ============================================================================

# IAM Role for Production ECR Read Access
resource "aws_iam_role" "ecr_production_role" {
  count = var.create_iam_roles ? 1 : 0
  
  name = "${local.resource_prefix}-ecr-production-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "ecs-tasks.amazonaws.com", "lambda.amazonaws.com"]
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-production-role"
    Purpose = "Production ECR read access"
  })
}

# IAM Policy for Production ECR Read Access
resource "aws_iam_role_policy" "ecr_production_policy" {
  count = var.create_iam_roles ? 1 : 0
  
  name = "${local.resource_prefix}-ecr-production-policy"
  role = aws_iam_role.ecr_production_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = [
          aws_ecr_repository.production.arn,
          aws_ecr_repository.testing.arn
        ]
      }
    ]
  })
}

# IAM Role for CI/CD Pipeline ECR Push Access
resource "aws_iam_role" "ecr_ci_pipeline_role" {
  count = var.create_iam_roles ? 1 : 0
  
  name = "${local.resource_prefix}-ecr-ci-pipeline-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["codebuild.amazonaws.com", "codepipeline.amazonaws.com"]
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-ci-pipeline-role"
    Purpose = "CI/CD pipeline ECR push access"
  })
}

# IAM Policy for CI/CD Pipeline ECR Push Access
resource "aws_iam_role_policy" "ecr_ci_pipeline_policy" {
  count = var.create_iam_roles ? 1 : 0
  
  name = "${local.resource_prefix}-ecr-ci-pipeline-policy"
  role = aws_iam_role.ecr_ci_pipeline_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
        Resource = [
          aws_ecr_repository.production.arn,
          aws_ecr_repository.testing.arn
        ]
      }
    ]
  })
}

# ============================================================================
# ECR REPOSITORY POLICIES
# ============================================================================

# Production Repository Policy for Access Control
resource "aws_ecr_repository_policy" "production" {
  repository = aws_ecr_repository.production.name
  
  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid    = "ProdReadOnlyAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.create_iam_roles ? aws_iam_role.ecr_production_role[0].arn : var.existing_production_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories"
        ]
      },
      {
        Sid    = "ProdPushAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.create_iam_roles ? aws_iam_role.ecr_ci_pipeline_role[0].arn : var.existing_ci_pipeline_role_arn
        }
        Action = [
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}

# ============================================================================
# ECR REPLICATION CONFIGURATION
# ============================================================================

# ECR Replication Configuration for Cross-Region Distribution
resource "aws_ecr_replication_configuration" "main" {
  replication_configuration {
    rule {
      destination {
        region      = var.destination_region
        registry_id = local.account_id
      }
      
      destination {
        region      = var.secondary_region
        registry_id = local.account_id
      }
      
      repository_filter {
        filter      = var.repository_prefix
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}

# ============================================================================
# SNS TOPIC FOR MONITORING NOTIFICATIONS
# ============================================================================

# SNS Topic for ECR Replication Alerts
resource "aws_sns_topic" "ecr_alerts" {
  count = var.enable_sns_notifications ? 1 : 0
  
  name = "${local.resource_prefix}-ecr-replication-alerts"
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-replication-alerts"
    Purpose = "ECR replication monitoring alerts"
  })
}

# SNS Topic Policy for CloudWatch Alarms
resource "aws_sns_topic_policy" "ecr_alerts" {
  count = var.enable_sns_notifications ? 1 : 0
  
  arn = aws_sns_topic.ecr_alerts[0].arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.ecr_alerts[0].arn
      }
    ]
  })
}

# SNS Topic Subscription for Email Notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.enable_sns_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.ecr_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# CLOUDWATCH MONITORING AND ALARMS
# ============================================================================

# CloudWatch Dashboard for ECR Monitoring
resource "aws_cloudwatch_dashboard" "ecr_monitoring" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_name = "${local.resource_prefix}-ecr-replication-monitoring"
  
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
            ["AWS/ECR", "RepositoryPullCount", "RepositoryName", local.production_repo_name],
            ["AWS/ECR", "RepositoryPushCount", "RepositoryName", local.production_repo_name],
            ["AWS/ECR", "RepositoryPullCount", "RepositoryName", local.testing_repo_name],
            ["AWS/ECR", "RepositoryPushCount", "RepositoryName", local.testing_repo_name]
          ]
          period = 300
          stat   = "Sum"
          region = var.source_region
          title  = "ECR Repository Activity"
          view   = "timeSeries"
          stacked = false
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
            ["AWS/ECR", "RepositorySize", "RepositoryName", local.production_repo_name],
            ["AWS/ECR", "RepositorySize", "RepositoryName", local.testing_repo_name]
          ]
          period = 300
          stat   = "Average"
          region = var.source_region
          title  = "ECR Repository Size"
          view   = "timeSeries"
          stacked = false
        }
      }
    ]
  })
}

# CloudWatch Alarm for ECR Replication Failure Rate
resource "aws_cloudwatch_metric_alarm" "replication_failure_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-ecr-replication-failure-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationFailureRate"
  namespace           = "AWS/ECR"
  period              = "300"
  statistic           = "Average"
  threshold           = var.replication_failure_threshold
  alarm_description   = "This metric monitors ECR replication failure rate"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.ecr_alerts[0].arn] : []
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-replication-failure-rate"
    Purpose = "ECR replication failure monitoring"
  })
}

# CloudWatch Alarm for High Repository Pull Rate
resource "aws_cloudwatch_metric_alarm" "high_pull_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.resource_prefix}-ecr-high-pull-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RepositoryPullCount"
  namespace           = "AWS/ECR"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "This metric monitors ECR repository pull count"
  alarm_actions       = var.enable_sns_notifications ? [aws_sns_topic.ecr_alerts[0].arn] : []
  
  dimensions = {
    RepositoryName = local.production_repo_name
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-high-pull-rate"
    Purpose = "ECR high pull rate monitoring"
  })
}

# ============================================================================
# LAMBDA FUNCTION FOR AUTOMATED CLEANUP (OPTIONAL)
# ============================================================================

# IAM Role for Lambda Cleanup Function
resource "aws_iam_role" "lambda_cleanup_role" {
  name = "${local.resource_prefix}-lambda-cleanup-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-lambda-cleanup-role"
    Purpose = "Lambda function for ECR cleanup"
  })
}

# IAM Policy for Lambda Cleanup Function
resource "aws_iam_role_policy" "lambda_cleanup_policy" {
  name = "${local.resource_prefix}-lambda-cleanup-policy"
  role = aws_iam_role.lambda_cleanup_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:BatchDeleteImage",
          "ecr:ListImages"
        ]
        Resource = [
          aws_ecr_repository.production.arn,
          aws_ecr_repository.testing.arn
        ]
      }
    ]
  })
}

# Lambda Function for ECR Cleanup
resource "aws_lambda_function" "ecr_cleanup" {
  filename         = "ecr_cleanup_lambda.zip"
  function_name    = "${local.resource_prefix}-ecr-cleanup"
  role            = aws_iam_role.lambda_cleanup_role.arn
  handler         = "index.lambda_handler"
  runtime         = "python3.11"
  timeout         = 60
  
  environment {
    variables = {
      REPOSITORY_PREFIX = var.repository_prefix
      CLEANUP_DAYS     = "30"
    }
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-cleanup"
    Purpose = "Automated ECR cleanup function"
  })
  
  depends_on = [data.archive_file.lambda_zip]
}

# Archive Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "ecr_cleanup_lambda.zip"
  
  source {
    content = templatefile("${path.module}/lambda_cleanup.py.tpl", {
      repository_prefix = var.repository_prefix
    })
    filename = "index.py"
  }
}

# EventBridge Rule for scheduled Lambda execution
resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "${local.resource_prefix}-ecr-cleanup-schedule"
  description         = "Trigger ECR cleanup Lambda function"
  schedule_expression = "cron(0 2 * * ? *)"  # Daily at 2 AM
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-ecr-cleanup-schedule"
    Purpose = "Schedule for ECR cleanup function"
  })
}

# EventBridge Target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.lambda_schedule.name
  target_id = "ECRCleanupLambdaTarget"
  arn       = aws_lambda_function.ecr_cleanup.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecr_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}