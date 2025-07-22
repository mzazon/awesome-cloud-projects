# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = "${var.project_name}-sagemaker-mlops-${data.aws_region.current.name}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      CreatedBy   = "Terraform"
      Recipe      = "machine-learning-model-deployment-pipelines-sagemaker-codepipeline"
    },
    var.additional_tags
  )
}

# KMS Key for encryption
resource "aws_kms_key" "mlops_key" {
  count = var.enable_encryption ? 1 : 0
  
  description              = "KMS key for MLOps pipeline encryption"
  deletion_window_in_days  = var.kms_key_deletion_window
  enable_key_rotation      = true
  
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
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CodePipeline Service"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_kms_alias" "mlops_key_alias" {
  count = var.enable_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-mlops-key"
  target_key_id = aws_kms_key.mlops_key[0].key_id
}

# S3 bucket for storing artifacts, training data, and pipeline outputs
resource "aws_s3_bucket" "mlops_artifacts" {
  bucket = local.bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "mlops_artifacts_versioning" {
  bucket = aws_s3_bucket.mlops_artifacts.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlops_artifacts_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.mlops_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.mlops_key[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "mlops_artifacts_lifecycle" {
  bucket = aws_s3_bucket.mlops_artifacts.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_days * 2
      storage_class = "GLACIER"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mlops_artifacts_pab" {
  bucket = aws_s3_bucket.mlops_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample training data and source code
resource "aws_s3_object" "training_script" {
  bucket = aws_s3_bucket.mlops_artifacts.id
  key    = "code/train.py"
  content = file("${path.module}/assets/train.py")
  etag   = filemd5("${path.module}/assets/train.py")
  tags   = local.common_tags
}

resource "aws_s3_object" "buildspec_train" {
  bucket = aws_s3_bucket.mlops_artifacts.id
  key    = "buildspecs/buildspec-train.yml"
  content = templatefile("${path.module}/assets/buildspec-train.yml", {
    bucket_name                = aws_s3_bucket.mlops_artifacts.id
    model_package_group_name   = var.model_package_group_name
    sagemaker_role_arn        = aws_iam_role.sagemaker_execution_role.arn
  })
  tags = local.common_tags
}

resource "aws_s3_object" "buildspec_test" {
  bucket = aws_s3_bucket.mlops_artifacts.id
  key    = "buildspecs/buildspec-test.yml"
  content = file("${path.module}/assets/buildspec-test.yml")
  tags   = local.common_tags
}

# SageMaker Model Package Group for version management
resource "aws_sagemaker_model_package_group" "fraud_detection" {
  model_package_group_name        = var.model_package_group_name
  model_package_group_description = "Fraud detection model packages for ${var.project_name}"
  
  tags = local.common_tags
}

# IAM Role for SageMaker execution
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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_execution_policy" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy" "sagemaker_s3_access" {
  name = "${local.name_prefix}-sagemaker-s3-access"
  role = aws_iam_role.sagemaker_execution_role.id

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
          aws_s3_bucket.mlops_artifacts.arn,
          "${aws_s3_bucket.mlops_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_service_role" {
  name = "${local.name_prefix}-codebuild-service-role"

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

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${local.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild_service_role.id

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
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mlops_artifacts.arn,
          "${aws_s3_bucket.mlops_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:CreateTrainingJob",
          "sagemaker:DescribeTrainingJob",
          "sagemaker:CreateModel",
          "sagemaker:CreateModelPackage",
          "sagemaker:DescribeModelPackage",
          "sagemaker:UpdateModelPackage",
          "sagemaker:CreateEndpoint",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:DescribeEndpoint",
          "sagemaker:DeleteEndpoint",
          "sagemaker:DeleteEndpointConfig",
          "sagemaker:InvokeEndpoint"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.sagemaker_execution_role.arn
      }
    ]
  })
}

# CodeBuild project for model training
resource "aws_codebuild_project" "model_training" {
  name          = "${local.name_prefix}-train"
  description   = "ML model training project for ${var.project_name}"
  service_role  = aws_iam_role.codebuild_service_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "SAGEMAKER_ROLE_ARN"
      value = aws_iam_role.sagemaker_execution_role.arn
    }

    environment_variable {
      name  = "BUCKET_NAME"
      value = aws_s3_bucket.mlops_artifacts.id
    }

    environment_variable {
      name  = "MODEL_PACKAGE_GROUP_NAME"
      value = var.model_package_group_name
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-train.yml"
  }

  tags = local.common_tags
}

# CodeBuild project for model testing
resource "aws_codebuild_project" "model_testing" {
  name          = "${local.name_prefix}-test"
  description   = "ML model testing project for ${var.project_name}"
  service_role  = aws_iam_role.codebuild_service_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspecs/buildspec-test.yml"
  }

  tags = local.common_tags
}

# Lambda function for model deployment
data "archive_file" "lambda_deployment_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_deployment.zip"
  
  source {
    content = templatefile("${path.module}/assets/deploy_function.py", {
      project_name = var.project_name
      environment  = var.environment
    })
    filename = "deploy_function.py"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "${local.name_prefix}-lambda-execution-role"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_sagemaker_access" {
  name = "${local.name_prefix}-lambda-sagemaker-access"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:CreateModel",
          "sagemaker:CreateEndpointConfig",
          "sagemaker:CreateEndpoint",
          "sagemaker:DescribeEndpoint",
          "sagemaker:UpdateEndpoint",
          "sagemaker:DeleteEndpoint",
          "sagemaker:DeleteEndpointConfig",
          "sagemaker:DescribeModelPackage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "codepipeline:PutJobSuccessResult",
          "codepipeline:PutJobFailureResult"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.sagemaker_execution_role.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.mlops_artifacts.arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "model_deployment" {
  filename         = data.archive_file.lambda_deployment_zip.output_path
  function_name    = "${local.name_prefix}-deploy"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "deploy_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_deployment_zip.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME         = var.project_name
      ENVIRONMENT         = var.environment
      SAGEMAKER_ROLE_ARN  = aws_iam_role.sagemaker_execution_role.arn
      INSTANCE_TYPE       = var.sagemaker_endpoint_instance_type
    }
  }

  tags = local.common_tags
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_service_role" {
  name = "${local.name_prefix}-codepipeline-service-role"

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

resource "aws_iam_role_policy" "codepipeline_service_policy" {
  name = "${local.name_prefix}-codepipeline-service-policy"
  role = aws_iam_role.codepipeline_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.mlops_artifacts.arn,
          "${aws_s3_bucket.mlops_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Resource = [
          aws_codebuild_project.model_training.arn,
          aws_codebuild_project.model_testing.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.model_deployment.arn
      }
    ]
  })
}

# Create source code structure in S3
resource "aws_s3_object" "source_code_structure" {
  for_each = {
    "source/README.md" = templatefile("${path.module}/assets/source_readme.md", {
      project_name = var.project_name
    })
    "source/requirements.txt" = file("${path.module}/assets/requirements.txt")
  }
  
  bucket = aws_s3_bucket.mlops_artifacts.id
  key    = each.key
  content = each.value
  tags   = local.common_tags
}

# Upload sample training data
resource "aws_s3_object" "sample_training_data" {
  bucket = aws_s3_bucket.mlops_artifacts.id
  key    = "${var.training_data_prefix}/sample_data.csv"
  content = file("${path.module}/assets/sample_training_data.csv")
  tags   = local.common_tags
}

# CodePipeline for ML model deployment
resource "aws_codepipeline" "ml_deployment_pipeline" {
  name     = "${local.name_prefix}-pipeline"
  role_arn = aws_iam_role.codepipeline_service_role.arn

  artifact_store {
    location = aws_s3_bucket.mlops_artifacts.bucket
    type     = "S3"

    dynamic "encryption_key" {
      for_each = var.enable_encryption ? [1] : []
      content {
        id   = aws_kms_key.mlops_key[0].arn
        type = "KMS"
      }
    }
  }

  stage {
    name = "Source"

    action {
      name             = "SourceAction"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        S3Bucket    = aws_s3_bucket.mlops_artifacts.bucket
        S3ObjectKey = "source/ml-source-code.zip"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "TrainModel"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.model_training.name
      }
    }
  }

  stage {
    name = "Test"

    action {
      name             = "TestModel"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["BuildOutput"]
      output_artifacts = ["TestOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.model_testing.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "DeployModel"
      category        = "Invoke"
      owner           = "AWS"
      provider        = "Lambda"
      version         = "1"
      input_artifacts = ["TestOutput"]

      configuration = {
        FunctionName = aws_lambda_function.model_deployment.function_name
      }
    }
  }

  tags = local.common_tags
}

# CloudWatch Log Groups for better logging
resource "aws_cloudwatch_log_group" "codebuild_training_logs" {
  name              = "/aws/codebuild/${aws_codebuild_project.model_training.name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "codebuild_testing_logs" {
  name              = "/aws/codebuild/${aws_codebuild_project.model_testing.name}"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_deployment_logs" {
  name              = "/aws/lambda/${aws_lambda_function.model_deployment.function_name}"
  retention_in_days = 14
  tags              = local.common_tags
}

# SNS Topic for notifications (optional)
resource "aws_sns_topic" "pipeline_notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${local.name_prefix}-pipeline-notifications"
  tags  = local.common_tags
}

resource "aws_sns_topic_subscription" "email_notifications" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.pipeline_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge rule for pipeline state changes
resource "aws_cloudwatch_event_rule" "pipeline_state_change" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${local.name_prefix}-pipeline-state-change"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.ml_deployment_pipeline.name]
      state    = ["FAILED", "SUCCEEDED"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "sns_target" {
  count = var.notification_email != "" ? 1 : 0
  rule  = aws_cloudwatch_event_rule.pipeline_state_change[0].name
  arn   = aws_sns_topic.pipeline_notifications[0].arn
}