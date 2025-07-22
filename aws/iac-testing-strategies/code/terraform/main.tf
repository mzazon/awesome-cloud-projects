# Infrastructure as Code Testing Automation
# This Terraform configuration creates a comprehensive testing strategy for Infrastructure as Code
# using AWS CodeBuild, CodePipeline, and supporting services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique names with random suffix
  project_suffix    = "${var.project_name}-${random_id.suffix.hex}"
  repository_name   = var.repository_name != null ? var.repository_name : "iac-testing-repo-${random_id.suffix.hex}"
  bucket_name       = var.bucket_name != null ? var.bucket_name : "iac-testing-artifacts-${random_id.suffix.hex}"
  
  # Merge default and additional tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Infrastructure Testing Automation"
    },
    var.additional_tags
  )
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# S3 Bucket for storing build artifacts and pipeline artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = local.common_tags
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  count  = var.artifact_encryption ? 1 : 0
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block configuration
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CodeCommit repository for storing Infrastructure as Code
resource "aws_codecommit_repository" "iac_repo" {
  repository_name        = local.repository_name
  repository_description = "Infrastructure as Code repository for automated testing"

  tags = local.common_tags
}

# CloudWatch Log Group for CodeBuild
resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/${local.project_suffix}"
  retention_in_days = var.retention_days

  tags = local.common_tags
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${local.project_suffix}-codebuild-role"

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

# IAM Policy for CodeBuild - Basic permissions
resource "aws_iam_role_policy" "codebuild_basic_policy" {
  name = "${local.project_suffix}-codebuild-basic-policy"
  role = aws_iam_role.codebuild_role.id

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
        Resource = [
          aws_cloudwatch_log_group.codebuild_logs.arn,
          "${aws_cloudwatch_log_group.codebuild_logs.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GitPull"
        ]
        Resource = aws_codecommit_repository.iac_repo.arn
      }
    ]
  })
}

# IAM Policy for CodeBuild - Testing permissions (for integration tests)
resource "aws_iam_role_policy" "codebuild_testing_policy" {
  name = "${local.project_suffix}-codebuild-testing-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudformation:CreateStack",
          "cloudformation:UpdateStack",
          "cloudformation:DeleteStack",
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackEvents",
          "cloudformation:DescribeStackResources",
          "cloudformation:ValidateTemplate",
          "cloudformation:GetTemplate",
          "cloudformation:ListStacks"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "cloudformation:StackName" = "integration-test-*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketEncryption",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "s3:bucket" = "*integration-test-*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:RoleName" = "*integration-test-*"
          }
        }
      }
    ]
  })
}

# CodeBuild Project for Infrastructure Testing
resource "aws_codebuild_project" "iac_testing" {
  name          = local.project_suffix
  description   = "Automated testing for Infrastructure as Code"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "S3"
    location = "${aws_s3_bucket.artifacts.bucket}/artifacts"
    packaging = "ZIP"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }

    environment_variable {
      name  = "ARTIFACT_BUCKET"
      value = aws_s3_bucket.artifacts.bucket
    }

    # Add testing tools as environment variables
    dynamic "environment_variable" {
      for_each = var.testing_tools
      content {
        name  = "TESTING_TOOL_${upper(replace(environment_variable.value, "-", "_"))}"
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      status      = "ENABLED"
      group_name  = aws_cloudwatch_log_group.codebuild_logs.name
      stream_name = "build-log"
    }
  }

  source {
    type            = "CODECOMMIT"
    location        = aws_codecommit_repository.iac_repo.clone_url_http
    buildspec       = var.custom_buildspec_path
    git_clone_depth = 1

    git_submodules_config {
      fetch_submodules = false
    }
  }

  tags = local.common_tags
}

# IAM Role for CodePipeline (only created if pipeline is enabled)
resource "aws_iam_role" "codepipeline_role" {
  count = var.enable_pipeline ? 1 : 0
  name  = "${local.project_suffix}-pipeline-role"

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

  tags = local.common_tags
}

# IAM Policy for CodePipeline
resource "aws_iam_role_policy" "codepipeline_policy" {
  count = var.enable_pipeline ? 1 : 0
  name  = "${local.project_suffix}-pipeline-policy"
  role  = aws_iam_role.codepipeline_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          "codecommit:ListBranches",
          "codecommit:ListRepositories"
        ]
        Resource = aws_codecommit_repository.iac_repo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.iac_testing.arn
      }
    ]
  })
}

# CodePipeline for end-to-end automation (optional)
resource "aws_codepipeline" "iac_testing_pipeline" {
  count    = var.enable_pipeline ? 1 : 0
  name     = "${local.project_suffix}-pipeline"
  role_arn = aws_iam_role.codepipeline_role[0].arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"

    dynamic "encryption_key" {
      for_each = var.artifact_encryption ? [1] : []
      content {
        id   = "alias/aws/s3"
        type = "KMS"
      }
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = aws_codecommit_repository.iac_repo.repository_name
        BranchName     = var.pipeline_branch
      }
    }
  }

  stage {
    name = "Test"

    action {
      name             = "Test"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]

      configuration = {
        ProjectName = aws_codebuild_project.iac_testing.name
      }
    }
  }

  tags = local.common_tags
}

# SNS Topic for notifications (optional)
resource "aws_sns_topic" "build_notifications" {
  count = var.notification_email != null ? 1 : 0
  name  = "${local.project_suffix}-build-notifications"

  tags = local.common_tags
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != null ? 1 : 0
  topic_arn = aws_sns_topic.build_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Event Rule for CodeBuild state changes
resource "aws_cloudwatch_event_rule" "codebuild_state_change" {
  count       = var.notification_email != null ? 1 : 0
  name        = "${local.project_suffix}-codebuild-state-change"
  description = "Capture CodeBuild state changes"

  event_pattern = jsonencode({
    source      = ["aws.codebuild"]
    detail-type = ["CodeBuild Build State Change"]
    detail = {
      project-name = [aws_codebuild_project.iac_testing.name]
      build-status = ["FAILED", "SUCCEEDED", "STOPPED"]
    }
  })

  tags = local.common_tags
}

# CloudWatch Event Target for SNS
resource "aws_cloudwatch_event_target" "sns_target" {
  count     = var.notification_email != null ? 1 : 0
  rule      = aws_cloudwatch_event_rule.codebuild_state_change[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.build_notifications[0].arn
}

# IAM Role for CloudWatch Events
resource "aws_iam_role" "cloudwatch_events_role" {
  count = var.notification_email != null ? 1 : 0
  name  = "${local.project_suffix}-cloudwatch-events-role"

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

  tags = local.common_tags
}

# IAM Policy for CloudWatch Events to publish to SNS
resource "aws_iam_role_policy" "cloudwatch_events_policy" {
  count = var.notification_email != null ? 1 : 0
  name  = "${local.project_suffix}-cloudwatch-events-policy"
  role  = aws_iam_role.cloudwatch_events_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.build_notifications[0].arn
      }
    ]
  })
}

# SNS Topic Policy to allow CloudWatch Events to publish
resource "aws_sns_topic_policy" "build_notifications_policy" {
  count = var.notification_email != null ? 1 : 0
  arn   = aws_sns_topic.build_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchEventsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.build_notifications[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Sample buildspec file content (stored as local value for reference)
locals {
  sample_buildspec = yamlencode({
    version = "0.2"
    phases = {
      install = {
        runtime-versions = {
          python = "3.9"
        }
        commands = [
          "echo 'Installing dependencies...'",
          "pip install -r tests/requirements.txt",
          "pip install awscli"
        ]
      }
      pre_build = {
        commands = [
          "echo 'Pre-build phase started on `date`'",
          "echo 'Validating AWS credentials...'",
          "aws sts get-caller-identity"
        ]
      }
      build = {
        commands = [
          "echo 'Build phase started on `date`'",
          "echo 'Running unit tests...'",
          "cd tests && python -m pytest test_s3_bucket.py -v",
          "cd ..",
          "echo 'Running security tests...'",
          "python tests/security_test.py",
          "echo 'Running cost analysis...'",
          "python tests/cost_analysis.py",
          "echo 'Running integration tests...'",
          "python tests/integration_test.py"
        ]
      }
      post_build = {
        commands = [
          "echo 'Post-build phase started on `date`'",
          "echo 'All tests completed successfully!'"
        ]
      }
    }
    artifacts = {
      files = ["**/*"]
      base-directory = "."
    }
  })
}