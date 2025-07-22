# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_id.suffix.hex
  
  # Generate unique resource names
  repo_name     = var.repository_name != "" ? var.repository_name : "${var.project_name}-${local.suffix}"
  pipeline_name = "${var.pipeline_name}-${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "infrastructure-deployment-pipelines-cdk-codepipeline"
    },
    var.additional_tags
  )
}

# =====================================
# IAM ROLES AND POLICIES
# =====================================

# CodePipeline service role
resource "aws_iam_role" "codepipeline_role" {
  name = "${var.project_name}-codepipeline-role-${local.suffix}"

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

# CodePipeline service role policy
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${var.project_name}-codepipeline-policy-${local.suffix}"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
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
        Resource = aws_codecommit_repository.repo.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = [
          aws_codebuild_project.build.arn,
          aws_codebuild_project.deploy_dev.arn,
          aws_codebuild_project.deploy_prod.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:CreateStack",
          "cloudformation:DescribeStacks",
          "cloudformation:UpdateStack",
          "cloudformation:DeleteStack",
          "cloudformation:DescribeStackEvents",
          "cloudformation:DescribeStackResources",
          "cloudformation:GetTemplate"
        ]
        Resource = "*"
      }
    ]
  })
}

# CodeBuild service role
resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-codebuild-role-${local.suffix}"

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

# CodeBuild service role policy
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy-${local.suffix}"
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
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${var.project_name}*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:*",
          "iam:*",
          "s3:*",
          "lambda:*",
          "ec2:*",
          "rds:*",
          "elasticloadbalancing:*",
          "autoscaling:*",
          "route53:*",
          "cloudfront:*",
          "sns:*",
          "sqs:*",
          "dynamodb:*",
          "ssm:*",
          "secretsmanager:*",
          "kms:*",
          "logs:*",
          "events:*",
          "application-autoscaling:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# =====================================
# CODECOMMIT REPOSITORY
# =====================================

# CodeCommit repository for source code
resource "aws_codecommit_repository" "repo" {
  repository_name   = local.repo_name
  repository_description = var.repository_description
  
  tags = local.common_tags
}

# =====================================
# S3 BUCKET FOR ARTIFACTS
# =====================================

# S3 bucket for storing build artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.project_name}-artifacts-${local.suffix}"
  
  tags = local.common_tags
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle policy
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "artifact_cleanup"
    status = "Enabled"

    expiration {
      days = var.artifact_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# =====================================
# CLOUDWATCH LOG GROUPS
# =====================================

# CloudWatch log group for CodeBuild builds
resource "aws_cloudwatch_log_group" "codebuild" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/codebuild/${var.project_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# =====================================
# CODEBUILD PROJECTS
# =====================================

# CodeBuild project for building and synthesizing CDK
resource "aws_codebuild_project" "build" {
  name         = "${var.project_name}-build-${local.suffix}"
  description  = "Build and synthesize CDK application"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = local.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = local.account_id
    }

    environment_variable {
      name  = "NODE_VERSION"
      value = var.nodejs_version
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = local.common_tags
}

# CodeBuild project for deploying to development environment
resource "aws_codebuild_project" "deploy_dev" {
  name         = "${var.project_name}-deploy-dev-${local.suffix}"
  description  = "Deploy CDK application to development environment"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = local.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = local.account_id
    }

    environment_variable {
      name  = "ENVIRONMENT"
      value = "dev"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec-deploy.yml"
  }

  tags = local.common_tags
}

# CodeBuild project for deploying to production environment
resource "aws_codebuild_project" "deploy_prod" {
  name         = "${var.project_name}-deploy-prod-${local.suffix}"
  description  = "Deploy CDK application to production environment"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = local.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = local.account_id
    }

    environment_variable {
      name  = "ENVIRONMENT"
      value = "prod"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec-deploy.yml"
  }

  tags = local.common_tags
}

# =====================================
# SNS TOPIC FOR NOTIFICATIONS
# =====================================

# SNS topic for pipeline notifications
resource "aws_sns_topic" "notifications" {
  count = var.enable_notifications ? 1 : 0
  name  = "${var.project_name}-pipeline-notifications-${local.suffix}"

  tags = local.common_tags
}

# SNS topic encryption
resource "aws_sns_topic_subscription" "email" {
  count     = var.enable_notifications && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =====================================
# CODEPIPELINE
# =====================================

# CodePipeline for CI/CD
resource "aws_codepipeline" "pipeline" {
  name     = local.pipeline_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
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
        RepositoryName = aws_codecommit_repository.repo.repository_name
        BranchName     = var.branch_name
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy-Dev"

    action {
      name            = "Deploy-Dev"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.deploy_dev.name
      }
    }
  }

  dynamic "stage" {
    for_each = var.enable_manual_approval ? [1] : []

    content {
      name = "Manual-Approval"

      action {
        name     = "Manual-Approval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          NotificationArn = var.enable_notifications ? aws_sns_topic.notifications[0].arn : null
          CustomData      = "Please review the development deployment and approve for production deployment"
        }
      }
    }
  }

  stage {
    name = "Deploy-Prod"

    action {
      name            = "Deploy-Prod"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ProjectName = aws_codebuild_project.deploy_prod.name
      }
    }
  }

  tags = local.common_tags
}

# =====================================
# CLOUDWATCH EVENTS FOR PIPELINE
# =====================================

# CloudWatch event rule for pipeline state changes
resource "aws_cloudwatch_event_rule" "pipeline_event" {
  count = var.enable_notifications ? 1 : 0
  name  = "${var.project_name}-pipeline-event-${local.suffix}"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.pipeline.name]
    }
  })

  tags = local.common_tags
}

# CloudWatch event target for SNS
resource "aws_cloudwatch_event_target" "sns" {
  count     = var.enable_notifications ? 1 : 0
  rule      = aws_cloudwatch_event_rule.pipeline_event[0].name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.notifications[0].arn
}

# SNS topic policy for CloudWatch events
resource "aws_sns_topic_policy" "pipeline_notifications" {
  count = var.enable_notifications ? 1 : 0
  arn   = aws_sns_topic.notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.notifications[0].arn
      }
    ]
  })
}

# =====================================
# CLOUDTRAIL FOR AUDIT LOGGING
# =====================================

# CloudTrail for API audit logging
resource "aws_cloudtrail" "pipeline_audit" {
  name           = "${var.project_name}-pipeline-audit-${local.suffix}"
  s3_bucket_name = aws_s3_bucket.audit_logs.id

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.artifacts.arn}/*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.audit_logs]

  tags = local.common_tags
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "audit_logs" {
  bucket = "${var.project_name}-audit-logs-${local.suffix}"
  
  tags = local.common_tags
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.audit_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.audit_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# S3 bucket public access block for audit logs
resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}