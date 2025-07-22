# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
  random_suffix = random_id.suffix.hex
  
  # Resource names with random suffix
  cache_bucket_name    = var.cache_bucket_name != "" ? var.cache_bucket_name : "codebuild-cache-${var.project_name}-${local.random_suffix}"
  artifact_bucket_name = var.artifact_bucket_name != "" ? var.artifact_bucket_name : "build-artifacts-${var.project_name}-${local.random_suffix}"
  ecr_repository_name  = var.ecr_repository_name != "" ? var.ecr_repository_name : "app-repository-${var.project_name}-${local.random_suffix}"
  
  # CodeBuild project names
  dependency_build_project = "${var.project_name}-dependencies-${local.random_suffix}"
  main_build_project      = "${var.project_name}-main-${local.random_suffix}"
  parallel_build_project  = "${var.project_name}-parallel-${local.random_suffix}"
  
  # IAM role name
  build_role_name = "CodeBuildAdvancedRole-${var.project_name}-${local.random_suffix}"
  
  # Lambda function names
  orchestrator_function_name  = "${var.project_name}-orchestrator-${local.random_suffix}"
  cache_manager_function_name = "${var.project_name}-cache-manager-${local.random_suffix}"
  analytics_function_name     = "${var.project_name}-analytics-${local.random_suffix}"
  
  # Common tags
  common_tags = merge(
    var.additional_tags,
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "advanced-codebuild-pipelines-multi-stage-caching-artifacts"
    }
  )
}

# =============================================================================
# S3 BUCKETS FOR CACHING AND ARTIFACTS
# =============================================================================

# S3 bucket for build caching
resource "aws_s3_bucket" "cache_bucket" {
  bucket = local.cache_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning for cache bucket
resource "aws_s3_bucket_versioning" "cache_bucket_versioning" {
  bucket = aws_s3_bucket.cache_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption for cache bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "cache_bucket_encryption" {
  bucket = aws_s3_bucket.cache_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for cache bucket
resource "aws_s3_bucket_public_access_block" "cache_bucket_pab" {
  bucket = aws_s3_bucket.cache_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cache management
resource "aws_s3_bucket_lifecycle_configuration" "cache_bucket_lifecycle" {
  bucket = aws_s3_bucket.cache_bucket.id

  rule {
    id     = "CacheCleanup"
    status = "Enabled"

    filter {
      prefix = "cache/"
    }

    expiration {
      days = var.cache_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  rule {
    id     = "DependencyCache"
    status = "Enabled"

    filter {
      prefix = "deps/"
    }

    expiration {
      days = var.dependency_cache_days
    }
  }
}

# S3 bucket for build artifacts
resource "aws_s3_bucket" "artifact_bucket" {
  bucket = local.artifact_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning for artifact bucket
resource "aws_s3_bucket_versioning" "artifact_bucket_versioning" {
  bucket = aws_s3_bucket.artifact_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption for artifact bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "artifact_bucket_encryption" {
  bucket = aws_s3_bucket.artifact_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for artifact bucket
resource "aws_s3_bucket_public_access_block" "artifact_bucket_pab" {
  bucket = aws_s3_bucket.artifact_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# ECR REPOSITORY FOR CONTAINER IMAGES
# =============================================================================

# ECR repository for container images
resource "aws_ecr_repository" "app_repository" {
  name                 = local.ecr_repository_name
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.enable_ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

# ECR lifecycle policy for image management
resource "aws_ecr_lifecycle_policy" "app_repository_lifecycle" {
  repository = aws_ecr_repository.app_repository.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_lifecycle_count_number} tagged images"
        selection = {
          tagStatus     = "tagged"
          countType     = "imageCountMoreThan"
          countNumber   = var.ecr_lifecycle_count_number
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep untagged images for 1 day"
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

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM trust policy for CodeBuild
data "aws_iam_policy_document" "codebuild_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy for CodeBuild advanced operations
data "aws_iam_policy_document" "codebuild_advanced_policy" {
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  # S3 permissions for cache and artifacts
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.cache_bucket.arn,
      "${aws_s3_bucket.cache_bucket.arn}/*",
      aws_s3_bucket.artifact_bucket.arn,
      "${aws_s3_bucket.artifact_bucket.arn}/*"
    ]
  }

  # ECR permissions
  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:GetAuthorizationToken",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = ["*"]
  }

  # CodeBuild reports permissions
  statement {
    effect = "Allow"
    actions = [
      "codebuild:CreateReportGroup",
      "codebuild:CreateReport",
      "codebuild:UpdateReport",
      "codebuild:BatchPutTestCases",
      "codebuild:BatchPutCodeCoverages"
    ]
    resources = ["*"]
  }

  # CloudWatch metrics permissions
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }

  # CodeBuild project control permissions
  statement {
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds"
    ]
    resources = [
      "arn:aws:codebuild:${local.region}:${local.account_id}:project/${var.project_name}-*"
    ]
  }

  # VPC permissions (if VPC is enabled)
  dynamic "statement" {
    for_each = var.enable_vpc ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeDhcpOptions",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs"
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_vpc ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "ec2:CreateNetworkInterfacePermission"
      ]
      resources = ["arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*"]
      condition {
        test     = "StringEquals"
        variable = "ec2:Subnet"
        values   = [for subnet_id in var.subnet_ids : "arn:aws:ec2:${local.region}:${local.account_id}:subnet/${subnet_id}"]
      }
      condition {
        test     = "StringEquals"
        variable = "ec2:AuthorizedService"
        values   = ["codebuild.amazonaws.com"]
      }
    }
  }
}

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name               = local.build_role_name
  assume_role_policy = data.aws_iam_policy_document.codebuild_trust_policy.json
  tags               = local.common_tags
}

# IAM policy for CodeBuild advanced operations
resource "aws_iam_policy" "codebuild_advanced_policy" {
  name        = "CodeBuildAdvancedPolicy-${var.project_name}-${local.random_suffix}"
  description = "Comprehensive policy for advanced CodeBuild operations"
  policy      = data.aws_iam_policy_document.codebuild_advanced_policy.json
  tags        = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "codebuild_role_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_advanced_policy.arn
}

# =============================================================================
# SECURITY GROUP FOR VPC (if enabled)
# =============================================================================

resource "aws_security_group" "codebuild_sg" {
  count = var.enable_vpc ? 1 : 0
  
  name_prefix = "${var.project_name}-codebuild-"
  vpc_id      = var.vpc_id
  description = "Security group for CodeBuild projects"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-codebuild-sg"
  })
}

# =============================================================================
# CODEBUILD PROJECTS
# =============================================================================

# CodeBuild project for dependency management
resource "aws_codebuild_project" "dependency_build" {
  name         = local.dependency_build_project
  description  = "Dependency installation and caching stage"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type     = "S3"
    location = "${aws_s3_bucket.artifact_bucket.id}/dependencies"
  }

  environment {
    compute_type                = var.codebuild_compute_types.dependency
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = false

    environment_variable {
      name  = "CACHE_BUCKET"
      value = aws_s3_bucket.cache_bucket.id
    }

    environment_variable {
      name  = "ARTIFACT_BUCKET"
      value = aws_s3_bucket.artifact_bucket.id
    }
  }

  source {
    type = "S3"
    location = var.source_bucket != "" ? "${var.source_bucket}/${var.source_key}" : "${aws_s3_bucket.artifact_bucket.id}/${var.source_key}"
    buildspec = "buildspec-dependencies.yml"
  }

  cache {
    type     = "S3"
    location = "${aws_s3_bucket.cache_bucket.id}/dependency-cache"
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      vpc_id = var.vpc_id
      subnets = var.subnet_ids
      security_group_ids = concat(
        [aws_security_group.codebuild_sg[0].id],
        var.additional_security_group_ids
      )
    }
  }

  timeout_in_minutes = var.codebuild_timeout_minutes.dependency
  tags               = local.common_tags
}

# CodeBuild project for main build
resource "aws_codebuild_project" "main_build" {
  name         = local.main_build_project
  description  = "Main build stage with testing and quality checks"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type     = "S3"
    location = "${aws_s3_bucket.artifact_bucket.id}/main-build"
  }

  environment {
    compute_type                = var.codebuild_compute_types.main
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = true

    environment_variable {
      name  = "CACHE_BUCKET"
      value = aws_s3_bucket.cache_bucket.id
    }

    environment_variable {
      name  = "ARTIFACT_BUCKET"
      value = aws_s3_bucket.artifact_bucket.id
    }

    environment_variable {
      name  = "ECR_URI"
      value = aws_ecr_repository.app_repository.repository_url
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }

    environment_variable {
      name  = "DOCKER_BUILDKIT"
      value = "1"
    }
  }

  source {
    type = "S3"
    location = var.source_bucket != "" ? "${var.source_bucket}/${var.source_key}" : "${aws_s3_bucket.artifact_bucket.id}/${var.source_key}"
    buildspec = "buildspec-main.yml"
  }

  cache {
    type     = "S3"
    location = "${aws_s3_bucket.cache_bucket.id}/main-cache"
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      vpc_id = var.vpc_id
      subnets = var.subnet_ids
      security_group_ids = concat(
        [aws_security_group.codebuild_sg[0].id],
        var.additional_security_group_ids
      )
    }
  }

  timeout_in_minutes = var.codebuild_timeout_minutes.main
  tags               = local.common_tags
}

# CodeBuild project for parallel builds
resource "aws_codebuild_project" "parallel_build" {
  name         = local.parallel_build_project
  description  = "Parallel build for multiple architectures"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type     = "S3"
    location = "${aws_s3_bucket.artifact_bucket.id}/parallel-build"
  }

  environment {
    compute_type                = var.codebuild_compute_types.parallel
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = true

    environment_variable {
      name  = "CACHE_BUCKET"
      value = aws_s3_bucket.cache_bucket.id
    }

    environment_variable {
      name  = "ECR_URI"
      value = aws_ecr_repository.app_repository.repository_url
    }

    environment_variable {
      name  = "TARGET_ARCH"
      value = "amd64"
    }
  }

  source {
    type = "S3"
    location = var.source_bucket != "" ? "${var.source_bucket}/${var.source_key}" : "${aws_s3_bucket.artifact_bucket.id}/${var.source_key}"
    buildspec = "buildspec-parallel.yml"
  }

  cache {
    type     = "S3"
    location = "${aws_s3_bucket.cache_bucket.id}/parallel-cache"
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      vpc_id = var.vpc_id
      subnets = var.subnet_ids
      security_group_ids = concat(
        [aws_security_group.codebuild_sg[0].id],
        var.additional_security_group_ids
      )
    }
  }

  timeout_in_minutes = var.codebuild_timeout_minutes.parallel
  tags               = local.common_tags
}

# =============================================================================
# LAMBDA FUNCTIONS FOR ORCHESTRATION AND MANAGEMENT
# =============================================================================

# IAM trust policy for Lambda
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy for Lambda functions
data "aws_iam_policy_document" "lambda_policy" {
  # Basic Lambda execution permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:*"]
  }

  # CodeBuild permissions
  statement {
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
      "codebuild:BatchGetBuilds",
      "codebuild:ListBuildsForProject"
    ]
    resources = [
      aws_codebuild_project.dependency_build.arn,
      aws_codebuild_project.main_build.arn,
      aws_codebuild_project.parallel_build.arn
    ]
  }

  # S3 permissions
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.cache_bucket.arn,
      "${aws_s3_bucket.cache_bucket.arn}/*",
      aws_s3_bucket.artifact_bucket.arn,
      "${aws_s3_bucket.artifact_bucket.arn}/*"
    ]
  }

  # CloudWatch metrics permissions
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData"
    ]
    resources = ["*"]
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name               = "LambdaCodeBuildRole-${var.project_name}-${local.random_suffix}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json
  tags               = local.common_tags
}

# IAM policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "LambdaCodeBuildPolicy-${var.project_name}-${local.random_suffix}"
  description = "Policy for Lambda functions managing CodeBuild"
  policy      = data.aws_iam_policy_document.lambda_policy.json
  tags        = local.common_tags
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_role_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function for build orchestration
resource "aws_lambda_function" "build_orchestrator" {
  filename         = "${path.module}/lambda/build-orchestrator.zip"
  function_name    = local.orchestrator_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "build-orchestrator.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/build-orchestrator.zip")
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout_seconds.orchestrator
  memory_size     = var.lambda_memory_size.orchestrator
  description     = "Orchestrate multi-stage CodeBuild pipeline"

  environment {
    variables = {
      DEPENDENCY_BUILD_PROJECT = aws_codebuild_project.dependency_build.name
      MAIN_BUILD_PROJECT      = aws_codebuild_project.main_build.name
      PARALLEL_BUILD_PROJECT  = aws_codebuild_project.parallel_build.name
      CACHE_BUCKET           = aws_s3_bucket.cache_bucket.id
      ARTIFACT_BUCKET        = aws_s3_bucket.artifact_bucket.id
      ECR_URI                = aws_ecr_repository.app_repository.repository_url
    }
  }

  tags = local.common_tags
}

# Lambda function for cache management
resource "aws_lambda_function" "cache_manager" {
  filename         = "${path.module}/lambda/cache-manager.zip"
  function_name    = local.cache_manager_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "cache-manager.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/cache-manager.zip")
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout_seconds.cache_manager
  memory_size     = var.lambda_memory_size.cache_manager
  description     = "Manage and optimize CodeBuild caches"

  environment {
    variables = {
      CACHE_BUCKET = aws_s3_bucket.cache_bucket.id
    }
  }

  tags = local.common_tags
}

# Lambda function for build analytics
resource "aws_lambda_function" "build_analytics" {
  filename         = "${path.module}/lambda/build-analytics.zip"
  function_name    = local.analytics_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "build-analytics.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/build-analytics.zip")
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout_seconds.analytics
  memory_size     = var.lambda_memory_size.analytics
  description     = "Generate build analytics and performance reports"

  environment {
    variables = {
      DEPENDENCY_BUILD_PROJECT = aws_codebuild_project.dependency_build.name
      MAIN_BUILD_PROJECT      = aws_codebuild_project.main_build.name
      PARALLEL_BUILD_PROJECT  = aws_codebuild_project.parallel_build.name
      ARTIFACT_BUCKET         = aws_s3_bucket.artifact_bucket.id
    }
  }

  tags = local.common_tags
}

# =============================================================================
# CLOUDWATCH LOG GROUPS
# =============================================================================

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "orchestrator_logs" {
  name              = "/aws/lambda/${local.orchestrator_function_name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "cache_manager_logs" {
  name              = "/aws/lambda/${local.cache_manager_function_name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "analytics_logs" {
  name              = "/aws/lambda/${local.analytics_function_name}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# CloudWatch log groups for CodeBuild projects
resource "aws_cloudwatch_log_group" "dependency_build_logs" {
  name              = "/aws/codebuild/${local.dependency_build_project}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "main_build_logs" {
  name              = "/aws/codebuild/${local.main_build_project}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "parallel_build_logs" {
  name              = "/aws/codebuild/${local.parallel_build_project}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# =============================================================================
# EVENTBRIDGE RULES FOR AUTOMATED SCHEDULING
# =============================================================================

# EventBridge rule for cache optimization
resource "aws_cloudwatch_event_rule" "cache_optimization" {
  count = var.enable_eventbridge_rules ? 1 : 0
  
  name                = "cache-optimization-${var.project_name}-${local.random_suffix}"
  description         = "Daily cache optimization"
  schedule_expression = var.cache_optimization_schedule
  tags                = local.common_tags
}

# EventBridge target for cache optimization
resource "aws_cloudwatch_event_target" "cache_optimization_target" {
  count = var.enable_eventbridge_rules ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.cache_optimization[0].name
  target_id = "CacheOptimizationLambdaTarget"
  arn       = aws_lambda_function.cache_manager.arn
}

# Lambda permission for EventBridge to invoke cache manager
resource "aws_lambda_permission" "cache_optimization_invoke" {
  count = var.enable_eventbridge_rules ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cache_manager.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cache_optimization[0].arn
}

# EventBridge rule for analytics
resource "aws_cloudwatch_event_rule" "build_analytics" {
  count = var.enable_eventbridge_rules ? 1 : 0
  
  name                = "build-analytics-${var.project_name}-${local.random_suffix}"
  description         = "Weekly build analytics report"
  schedule_expression = var.analytics_schedule
  tags                = local.common_tags
}

# EventBridge target for analytics
resource "aws_cloudwatch_event_target" "analytics_target" {
  count = var.enable_eventbridge_rules ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.build_analytics[0].name
  target_id = "AnalyticsLambdaTarget"
  arn       = aws_lambda_function.build_analytics.arn
}

# Lambda permission for EventBridge to invoke analytics
resource "aws_lambda_permission" "analytics_invoke" {
  count = var.enable_eventbridge_rules ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.build_analytics.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.build_analytics[0].arn
}

# =============================================================================
# CLOUDWATCH DASHBOARD (optional)
# =============================================================================

resource "aws_cloudwatch_dashboard" "build_monitoring" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "Advanced-CodeBuild-${var.project_name}-${local.random_suffix}"

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
            ["CodeBuild/AdvancedPipeline", "PipelineExecutions", "Status", "SUCCEEDED"],
            [".", ".", ".", "FAILED"]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Pipeline Execution Results"
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
            ["CodeBuild/AdvancedPipeline", "BuildDuration", "Stage", "dependencies"],
            [".", ".", ".", "main"],
            [".", ".", ".", "parallel"]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Average Build Duration by Stage"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/CodeBuild", "Duration", "ProjectName", local.dependency_build_project],
            [".", ".", ".", local.main_build_project],
            [".", ".", ".", local.parallel_build_project]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "CodeBuild Project Durations"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/CodeBuild", "Builds", "ProjectName", local.dependency_build_project],
            [".", ".", ".", local.main_build_project],
            [".", ".", ".", local.parallel_build_project]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Build Count by Project"
        }
      },
      {
        type   = "log"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          query  = "SOURCE '/aws/codebuild/${local.main_build_project}' | fields @timestamp, @message | filter @message like /ERROR/ or @message like /FAILED/ | sort @timestamp desc | limit 20"
          region = local.region
          title  = "Recent Build Errors"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", local.cache_bucket_name, "StorageType", "StandardStorage"],
            [".", ".", local.artifact_bucket_name, ".", "."]
          ]
          period = 86400
          stat   = "Average"
          region = local.region
          title  = "Storage Usage (Cache and Artifacts)"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.orchestrator_function_name],
            [".", "Invocations", ".", "."],
            [".", "Errors", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Build Orchestrator Performance"
        }
      }
    ]
  })
}