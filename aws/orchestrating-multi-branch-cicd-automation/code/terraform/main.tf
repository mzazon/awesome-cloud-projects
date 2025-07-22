# Main Terraform configuration for multi-branch CI/CD pipeline
# This file creates the complete infrastructure for automated multi-branch pipeline management

# Get current AWS account ID and region
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
  name_prefix      = "${var.project_name}-${var.environment}"
  repository_name  = var.repository_name != null ? var.repository_name : "${local.name_prefix}-${random_string.suffix.result}"
  artifact_bucket  = var.artifact_bucket_name != null ? var.artifact_bucket_name : "${local.name_prefix}-artifacts-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      CreatedBy   = "terraform"
      Owner       = var.owner
    },
    var.additional_tags
  )
}

# =============================================================================
# S3 BUCKET FOR PIPELINE ARTIFACTS
# =============================================================================

# S3 bucket for storing pipeline artifacts
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = local.artifact_bucket
  
  tags = merge(local.common_tags, {
    Name = "Pipeline Artifacts Bucket"
    Type = "Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  count  = var.enable_artifact_encryption ? 1 : 0
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    id     = "pipeline_artifacts_lifecycle"
    status = "Enabled"

    # Delete old versions after 30 days
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# =============================================================================
# CODECOMMIT REPOSITORY
# =============================================================================

# CodeCommit repository for the application source code
resource "aws_codecommit_repository" "app_repository" {
  repository_name        = local.repository_name
  repository_description = var.repository_description
  
  tags = merge(local.common_tags, {
    Name = "Application Repository"
    Type = "Source Control"
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM role for CodePipeline service
resource "aws_iam_role" "codepipeline_role" {
  name = "${local.name_prefix}-codepipeline-role-${random_string.suffix.result}"

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

  tags = merge(local.common_tags, {
    Name = "CodePipeline Service Role"
    Type = "IAM"
  })
}

# IAM policy for CodePipeline role
resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "${local.name_prefix}-codepipeline-policy"
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
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:CancelUploadArchive",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          "codecommit:ListBranches",
          "codecommit:ListRepositories",
          "codecommit:PutRepository",
          "codecommit:UploadArchive"
        ]
        Resource = aws_codecommit_repository.app_repository.arn
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = aws_codebuild_project.app_build.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for CodeBuild service
resource "aws_iam_role" "codebuild_role" {
  name = "${local.name_prefix}-codebuild-role-${random_string.suffix.result}"

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

  tags = merge(local.common_tags, {
    Name = "CodeBuild Service Role"
    Type = "IAM"
  })
}

# IAM policy for CodeBuild role
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${local.name_prefix}-codebuild-policy"
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
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
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
      }
    ]
  })
}

# Attach additional VPC policy if VPC configuration is enabled
resource "aws_iam_role_policy" "codebuild_vpc_policy" {
  count = var.enable_vpc_configuration ? 1 : 0
  name  = "${local.name_prefix}-codebuild-vpc-policy"
  role  = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Subnet" = var.subnet_ids
          }
        }
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${local.name_prefix}-lambda-role-${random_string.suffix.result}"

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
    Name = "Lambda Pipeline Manager Role"
    Type = "IAM"
  })
}

# IAM policy for Lambda role
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda_role.id

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
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codepipeline:CreatePipeline",
          "codepipeline:DeletePipeline",
          "codepipeline:GetPipeline",
          "codepipeline:GetPipelineState",
          "codepipeline:ListPipelines",
          "codepipeline:UpdatePipeline"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codecommit:GetBranch",
          "codecommit:GetRepository",
          "codecommit:ListBranches"
        ]
        Resource = aws_codecommit_repository.app_repository.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.codepipeline_role.arn,
          aws_iam_role.codebuild_role.arn
        ]
      }
    ]
  })
}

# Attach basic execution role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# =============================================================================
# CODEBUILD PROJECT
# =============================================================================

# CloudWatch Log Group for CodeBuild
resource "aws_cloudwatch_log_group" "codebuild_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/codebuild/${local.name_prefix}-build-${random_string.suffix.result}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name = "CodeBuild Log Group"
    Type = "Monitoring"
  })
}

# CodeBuild project for building applications
resource "aws_codebuild_project" "app_build" {
  name         = "${local.name_prefix}-build-${random_string.suffix.result}"
  description  = "Build project for multi-branch CI/CD pipeline"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "ARTIFACT_BUCKET"
      value = aws_s3_bucket.pipeline_artifacts.bucket
    }

    dynamic "environment_variable" {
      for_each = var.enable_code_coverage ? [1] : []
      content {
        name  = "ENABLE_CODE_COVERAGE"
        value = "true"
      }
    }

    dynamic "environment_variable" {
      for_each = var.enable_security_scanning ? [1] : []
      content {
        name  = "ENABLE_SECURITY_SCANNING"
        value = "true"
      }
    }
  }

  source {
    type            = "CODEPIPELINE"
    buildspec       = var.buildspec_file
    git_clone_depth = 1
  }

  # VPC configuration if enabled
  dynamic "vpc_config" {
    for_each = var.enable_vpc_configuration ? [1] : []
    content {
      vpc_id             = var.vpc_id
      subnets            = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  # CloudWatch logs configuration
  dynamic "logs_config" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    content {
      cloudwatch_logs {
        group_name  = aws_cloudwatch_log_group.codebuild_logs[0].name
        stream_name = "build-log"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "Multi-Branch Build Project"
    Type = "Build"
  })
}

# =============================================================================
# LAMBDA FUNCTION FOR PIPELINE MANAGEMENT
# =============================================================================

# Create Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/pipeline-manager.zip"
  
  source {
    content = <<EOF
import json
import boto3
import os
import logging
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codepipeline = boto3.client('codepipeline')
codecommit = boto3.client('codecommit')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to manage multi-branch CI/CD pipelines
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        repository_name = detail.get('requestParameters', {}).get('repositoryName', '')
        
        logger.info(f"Processing event: {event_name} for repository: {repository_name}")
        
        if event_name == 'CreateBranch':
            return handle_branch_creation(detail, repository_name)
        elif event_name == 'DeleteBranch':
            return handle_branch_deletion(detail, repository_name)
        elif event_name == 'GitPush':
            return handle_git_push(detail, repository_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Event processed but no action taken')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def handle_branch_creation(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle branch creation events"""
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if not branch_name:
        return {'statusCode': 400, 'body': 'Branch name not found'}
    
    # Only create pipelines for feature branches
    if branch_name.startswith(os.environ.get('FEATURE_BRANCH_PREFIX', 'feature/')):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            create_branch_pipeline(repository_name, branch_name, pipeline_name)
            logger.info(f"Created pipeline {pipeline_name} for branch {branch_name}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Pipeline {pipeline_name} created successfully')
            }
        except Exception as e:
            logger.error(f"Failed to create pipeline: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Pipeline creation failed: {str(e)}')
            }
    
    return {'statusCode': 200, 'body': 'No pipeline created for this branch type'}

def handle_branch_deletion(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle branch deletion events"""
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if branch_name.startswith(os.environ.get('FEATURE_BRANCH_PREFIX', 'feature/')):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            # Delete the pipeline
            codepipeline.delete_pipeline(name=pipeline_name)
            logger.info(f"Deleted pipeline {pipeline_name}")
            
            return {
                'statusCode': 200,
                'body': json.dumps(f'Pipeline {pipeline_name} deleted successfully')
            }
        except codepipeline.exceptions.PipelineNotFoundException:
            return {
                'statusCode': 404,
                'body': json.dumps(f'Pipeline {pipeline_name} not found')
            }
        except Exception as e:
            logger.error(f"Failed to delete pipeline: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Pipeline deletion failed: {str(e)}')
            }
    
    return {'statusCode': 200, 'body': 'No pipeline deleted for this branch type'}

def handle_git_push(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    """Handle git push events"""
    # For push events, we just log and let the pipeline trigger naturally
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    logger.info(f"Git push detected on branch {branch_name} in repository {repository_name}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Git push event processed')
    }

def create_branch_pipeline(repository_name: str, branch_name: str, pipeline_name: str) -> None:
    """Create a new pipeline for the specified branch"""
    
    pipeline_definition = {
        "pipeline": {
            "name": pipeline_name,
            "roleArn": os.environ['PIPELINE_ROLE_ARN'],
            "artifactStore": {
                "type": "S3",
                "location": os.environ['ARTIFACT_BUCKET']
            },
            "stages": [
                {
                    "name": "Source",
                    "actions": [
                        {
                            "name": "SourceAction",
                            "actionTypeId": {
                                "category": "Source",
                                "owner": "AWS",
                                "provider": "CodeCommit",
                                "version": "1"
                            },
                            "configuration": {
                                "RepositoryName": repository_name,
                                "BranchName": branch_name
                            },
                            "outputArtifacts": [
                                {
                                    "name": "SourceOutput"
                                }
                            ]
                        }
                    ]
                },
                {
                    "name": "Build",
                    "actions": [
                        {
                            "name": "BuildAction",
                            "actionTypeId": {
                                "category": "Build",
                                "owner": "AWS",
                                "provider": "CodeBuild",
                                "version": "1"
                            },
                            "configuration": {
                                "ProjectName": os.environ['CODEBUILD_PROJECT_NAME']
                            },
                            "inputArtifacts": [
                                {
                                    "name": "SourceOutput"
                                }
                            ],
                            "outputArtifacts": [
                                {
                                    "name": "BuildOutput"
                                }
                            ]
                        }
                    ]
                }
            ]
        }
    }
    
    # Create the pipeline
    codepipeline.create_pipeline(**pipeline_definition)
EOF
    filename = "pipeline-manager.py"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-pipeline-manager-${random_string.suffix.result}"
  retention_in_days = var.log_retention_in_days

  tags = merge(local.common_tags, {
    Name = "Lambda Pipeline Manager Logs"
    Type = "Monitoring"
  })
}

# Lambda function for pipeline management
resource "aws_lambda_function" "pipeline_manager" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-pipeline-manager-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "pipeline-manager.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      AWS_ACCOUNT_ID          = data.aws_caller_identity.current.account_id
      PIPELINE_ROLE_ARN       = aws_iam_role.codepipeline_role.arn
      CODEBUILD_PROJECT_NAME  = aws_codebuild_project.app_build.name
      ARTIFACT_BUCKET         = aws_s3_bucket.pipeline_artifacts.bucket
      FEATURE_BRANCH_PREFIX   = var.feature_branch_prefix
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_logs
  ]

  tags = merge(local.common_tags, {
    Name = "Pipeline Manager Function"
    Type = "Compute"
  })
}

# =============================================================================
# EVENTBRIDGE RULES FOR BRANCH MANAGEMENT
# =============================================================================

# EventBridge rule for CodeCommit events
resource "aws_cloudwatch_event_rule" "codecommit_events" {
  name        = "${local.name_prefix}-codecommit-events-${random_string.suffix.result}"
  description = "Trigger pipeline management for CodeCommit branch events"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    detail = {
      repositoryName = [aws_codecommit_repository.app_repository.repository_name]
      eventName      = ["CreateBranch", "DeleteBranch", "GitPush"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "CodeCommit Branch Events Rule"
    Type = "Event"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.codecommit_events.name
  target_id = "PipelineManagerTarget"
  arn       = aws_lambda_function.pipeline_manager.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.codecommit_events.arn
}

# =============================================================================
# PERMANENT PIPELINES FOR MAIN BRANCHES
# =============================================================================

# Create permanent pipelines for main branches
resource "aws_codepipeline" "permanent_pipelines" {
  for_each = toset(var.permanent_branches)
  
  name     = "${local.repository_name}-${each.value}"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        RepositoryName = aws_codecommit_repository.app_repository.repository_name
        BranchName     = each.value
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.app_build.name
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "Permanent Pipeline - ${each.value}"
    Type = "Pipeline"
    Branch = each.value
  })
}

# =============================================================================
# SNS NOTIFICATIONS (OPTIONAL)
# =============================================================================

# SNS topic for pipeline notifications
resource "aws_sns_topic" "pipeline_notifications" {
  count = var.enable_pipeline_notifications ? 1 : 0
  name  = "${local.name_prefix}-pipeline-notifications-${random_string.suffix.result}"

  tags = merge(local.common_tags, {
    Name = "Pipeline Notifications"
    Type = "Notification"
  })
}

# SNS subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.enable_pipeline_notifications && var.notification_email != null ? 1 : 0
  topic_arn = aws_sns_topic.pipeline_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for pipeline failures
resource "aws_cloudwatch_metric_alarm" "pipeline_failure_alarm" {
  for_each = var.enable_pipeline_notifications ? toset(var.permanent_branches) : []
  
  alarm_name          = "${local.name_prefix}-pipeline-failure-${each.value}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "PipelineExecutionFailure"
  namespace           = "AWS/CodePipeline"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors pipeline failures for ${each.value} branch"
  alarm_actions       = var.enable_pipeline_notifications ? [aws_sns_topic.pipeline_notifications[0].arn] : []

  dimensions = {
    PipelineName = aws_codepipeline.permanent_pipelines[each.value].name
  }

  tags = merge(local.common_tags, {
    Name = "Pipeline Failure Alarm - ${each.value}"
    Type = "Monitoring"
  })
}

# =============================================================================
# CLOUDWATCH DASHBOARD FOR MONITORING
# =============================================================================

# CloudWatch dashboard for pipeline monitoring
resource "aws_cloudwatch_dashboard" "pipeline_dashboard" {
  dashboard_name = "${local.name_prefix}-pipeline-dashboard"

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
            for branch in var.permanent_branches : [
              "AWS/CodePipeline",
              "PipelineExecutionSuccess",
              "PipelineName",
              aws_codepipeline.permanent_pipelines[branch].name
            ]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Pipeline Success Rate"
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
            [
              "AWS/CodeBuild",
              "Duration",
              "ProjectName",
              aws_codebuild_project.app_build.name
            ],
            [
              ".",
              "SucceededBuilds",
              ".",
              "."
            ],
            [
              ".",
              "FailedBuilds",
              ".",
              "."
            ]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Build Performance"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6

        properties = {
          query = "SOURCE '/aws/lambda/${aws_lambda_function.pipeline_manager.function_name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 100"
          region = data.aws_region.current.name
          title  = "Lambda Function Errors"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Pipeline Dashboard"
    Type = "Monitoring"
  })
}