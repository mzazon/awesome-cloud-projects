# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local values
locals {
  name_suffix = random_id.suffix.hex
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
    },
    var.additional_tags
  )
}

# ===== ECR Repository =====
resource "aws_ecr_repository" "main" {
  name                 = "${var.ecr_repository_name}-${local.name_suffix}"
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# ECR repository policy to allow CodeBuild access
resource "aws_ecr_repository_policy" "main" {
  repository = aws_ecr_repository.main.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCodeBuildAccess"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:GetAuthorizationToken"
        ]
      }
    ]
  })
}

# ===== Enhanced Scanning Configuration =====
resource "aws_ecr_registry_scanning_configuration" "main" {
  count = var.enable_enhanced_scanning ? 1 : 0

  scan_type = "ENHANCED"

  rule {
    scan_frequency = var.scan_frequency
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}

# ===== SNS Topic for Security Alerts =====
resource "aws_sns_topic" "security_alerts" {
  name = "security-alerts-${local.name_suffix}"
  
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===== IAM Roles =====

# CodeBuild service role
resource "aws_iam_role" "codebuild_role" {
  name = "ECRSecurityScanningRole-${local.name_suffix}"

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

  tags = local.common_tags
}

# CodeBuild IAM policy
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "ECRSecurityScanningPolicy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
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
          "ecr:DescribeImageScanFindings"
        ]
        Resource = "*"
      },
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
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.snyk_token_secret_name}*",
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.prisma_credentials_secret_name}*"
        ]
      }
    ]
  })
}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "SecurityScanLambdaRole-${local.name_suffix}"

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

  tags = local.common_tags
}

# Lambda IAM policy
resource "aws_iam_role_policy" "lambda_policy" {
  name = "SecurityHubIntegrationPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "securityhub:BatchImportFindings",
          "securityhub:GetFindings",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ===== CodeBuild Project =====
resource "aws_codebuild_project" "security_scanning" {
  name          = "security-scan-${local.name_suffix}"
  description   = "Multi-stage container security scanning pipeline"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    privileged_mode            = true
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "ECR_REPO_NAME"
      value = aws_ecr_repository.main.name
    }

    environment_variable {
      name  = "ECR_URI"
      value = aws_ecr_repository.main.repository_url
    }

    environment_variable {
      name  = "SNYK_TOKEN_SECRET"
      value = var.snyk_token_secret_name
    }

    environment_variable {
      name  = "PRISMA_CREDENTIALS_SECRET"
      value = var.prisma_credentials_secret_name
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1

    buildspec = "buildspec.yml"
  }

  tags = local.common_tags
}

# ===== Lambda Function for Security Scan Processing =====
resource "aws_lambda_function" "security_scan_processor" {
  filename         = "scan_processor.zip"
  function_name    = "SecurityScanProcessor-${local.name_suffix}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "scan_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_alerts.arn
      AWS_REGION    = data.aws_region.current.name
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    }
  }

  tags = local.common_tags

  depends_on = [data.archive_file.lambda_zip]
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "scan_processor.zip"
  
  source {
    content = templatefile("${path.module}/lambda/scan_processor.py", {
      sns_topic_arn = aws_sns_topic.security_alerts.arn
      aws_region    = data.aws_region.current.name
      aws_account_id = data.aws_caller_identity.current.account_id
    })
    filename = "scan_processor.py"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/SecurityScanProcessor-${local.name_suffix}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

# ===== EventBridge Rules =====
resource "aws_cloudwatch_event_rule" "ecr_scan_completed" {
  name        = "ECRScanCompleted-${local.name_suffix}"
  description = "Trigger when ECR enhanced scan completes"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Scan"]
    detail = {
      scan-status = ["INITIAL_SCAN_COMPLETE"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.ecr_scan_completed.name
  target_id = "TriggerLambdaTarget"
  arn       = aws_lambda_function.security_scan_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_scan_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ecr_scan_completed.arn
}

# ===== AWS Config Rules =====
resource "aws_config_configuration_recorder" "recorder" {
  count    = var.enable_config_rules ? 1 : 0
  name     = "security-scanning-recorder-${local.name_suffix}"
  role_arn = aws_iam_role.config_role[0].arn

  recording_group {
    all_supported = true
  }
}

resource "aws_config_delivery_channel" "channel" {
  count          = var.enable_config_rules ? 1 : 0
  name           = "security-scanning-channel-${local.name_suffix}"
  s3_bucket_name = aws_s3_bucket.config_bucket[0].bucket
}

resource "aws_config_config_rule" "ecr_scan_enabled" {
  count = var.enable_config_rules ? 1 : 0
  name  = "ecr-repository-scan-enabled-${local.name_suffix}"

  source {
    owner             = "AWS"
    source_identifier = "ECR_PRIVATE_IMAGE_SCANNING_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = local.common_tags
}

# S3 bucket for Config
resource "aws_s3_bucket" "config_bucket" {
  count  = var.enable_config_rules ? 1 : 0
  bucket = "config-bucket-${local.name_suffix}"

  tags = local.common_tags
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  count  = var.enable_config_rules ? 1 : 0
  bucket = aws_s3_bucket.config_bucket[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket[0].arn
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# Config service role
resource "aws_iam_role" "config_role" {
  count = var.enable_config_rules ? 1 : 0
  name  = "ConfigRole-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_policy" {
  count      = var.enable_config_rules ? 1 : 0
  role       = aws_iam_role.config_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# ===== CloudWatch Dashboard =====
resource "aws_cloudwatch_dashboard" "security_dashboard" {
  dashboard_name = "ContainerSecurityDashboard-${local.name_suffix}"

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
            ["AWS/ECR", "RepositoryCount"],
            ["AWS/ECR", "ImageCount"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "ECR Repository Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query  = "SOURCE '/aws/lambda/SecurityScanProcessor-${local.name_suffix}' | fields @timestamp, @message | filter @message like /CRITICAL/ | sort @timestamp desc | limit 20"
          region = data.aws_region.current.name
          title  = "Critical Security Findings"
        }
      }
    ]
  })
}