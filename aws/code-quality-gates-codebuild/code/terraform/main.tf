# Data sources for current AWS configuration
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate unique suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  project_name_with_suffix = "${var.project_name}-${random_string.suffix.result}"
  bucket_name              = "codebuild-quality-gates-${data.aws_caller_identity.current.account_id}-${random_string.suffix.result}"
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "code-quality-gates-codebuild"
  })
}

# ===== S3 BUCKET FOR ARTIFACTS AND CACHING =====

# S3 bucket for storing build artifacts, cache, and reports
resource "aws_s3_bucket" "artifacts" {
  bucket = local.bucket_name
  
  tags = local.common_tags
}

# Configure S3 bucket versioning
resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "cache_cleanup"
    status = "Enabled"

    filter {
      prefix = "cache/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "old_artifacts"
    status = "Enabled"

    filter {
      prefix = "artifacts/"
    }

    expiration {
      days = 90
    }
  }
}

# ===== SYSTEMS MANAGER PARAMETERS =====

# Store quality gate configuration in Parameter Store
resource "aws_ssm_parameter" "coverage_threshold" {
  name        = "/quality-gates/coverage-threshold"
  description = "Minimum code coverage percentage"
  type        = "String"
  value       = tostring(var.coverage_threshold)
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "sonar_quality_gate" {
  name        = "/quality-gates/sonar-quality-gate"
  description = "SonarQube quality gate status threshold"
  type        = "String"
  value       = var.sonar_quality_gate
  
  tags = local.common_tags
}

resource "aws_ssm_parameter" "security_threshold" {
  name        = "/quality-gates/security-threshold"
  description = "Maximum security vulnerability level"
  type        = "String"
  value       = var.security_threshold
  
  tags = local.common_tags
}

# ===== SNS TOPIC FOR NOTIFICATIONS =====

# SNS topic for quality gate notifications
resource "aws_sns_topic" "quality_gate_notifications" {
  count = var.enable_notifications ? 1 : 0
  
  name = "quality-gate-notifications-${random_string.suffix.result}"
  
  tags = local.common_tags
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count = var.enable_notifications ? 1 : 0
  
  topic_arn = aws_sns_topic.quality_gate_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===== IAM ROLES AND POLICIES =====

# IAM role for CodeBuild service
resource "aws_iam_role" "codebuild_service_role" {
  name = "${local.project_name_with_suffix}-service-role"

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

# IAM policy for CodeBuild service permissions
resource "aws_iam_role_policy" "codebuild_service_policy" {
  name = "${local.project_name_with_suffix}-service-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
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
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.coverage_threshold.arn,
          aws_ssm_parameter.sonar_quality_gate.arn,
          aws_ssm_parameter.security_threshold.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_notifications ? aws_sns_topic.quality_gate_notifications[0].arn : null
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:BatchGetBuilds"
        ]
        Resource = "*"
      }
    ]
  })
}

# ===== CODEBUILD PROJECT =====

# CloudWatch log group for CodeBuild
resource "aws_cloudwatch_log_group" "codebuild_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  
  name              = "/aws/codebuild/${local.project_name_with_suffix}"
  retention_in_days = 30
  
  tags = local.common_tags
}

# CodeBuild project for quality gates
resource "aws_codebuild_project" "quality_gates" {
  name         = local.project_name_with_suffix
  description  = "Quality Gates Demo with CodeBuild - Terraform managed"
  service_role = aws_iam_role.codebuild_service_role.arn

  artifacts {
    type     = "S3"
    location = "${aws_s3_bucket.artifacts.bucket}/artifacts"
  }

  cache {
    type     = var.enable_s3_caching ? "S3" : "NO_CACHE"
    location = var.enable_s3_caching ? "${aws_s3_bucket.artifacts.bucket}/cache" : null
  }

  environment {
    compute_type                = var.compute_type
    image                      = var.build_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "SNS_TOPIC_ARN"
      value = var.enable_notifications ? aws_sns_topic.quality_gate_notifications[0].arn : ""
    }
    
    environment_variable {
      name  = "AWS_REGION"
      value = data.aws_region.current.name
    }
    
    environment_variable {
      name  = "PROJECT_NAME"
      value = local.project_name_with_suffix
    }
  }

  logs_config {
    dynamic "cloudwatch_logs" {
      for_each = var.enable_cloudwatch_logs ? [1] : []
      content {
        status      = "ENABLED"
        group_name  = aws_cloudwatch_log_group.codebuild_logs[0].name
        stream_name = "${local.project_name_with_suffix}-build-logs"
      }
    }
  }

  source {
    type            = "GITHUB"
    location        = var.source_location
    git_clone_depth = 1
    
    git_submodules_config {
      fetch_submodules = true
    }
    
    buildspec = "buildspec.yml"
  }

  source_version = "main"

  tags = local.common_tags
}

# ===== CLOUDWATCH DASHBOARD =====

# CloudWatch dashboard for quality gate metrics
resource "aws_cloudwatch_dashboard" "quality_gates" {
  count = var.create_dashboard ? 1 : 0
  
  dashboard_name = "Quality-Gates-${local.project_name_with_suffix}"

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
            ["AWS/CodeBuild", "Builds", "ProjectName", local.project_name_with_suffix],
            [".", "Duration", ".", "."],
            [".", "FailedBuilds", ".", "."],
            [".", "SucceededBuilds", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "CodeBuild Quality Gate Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query = "SOURCE '/aws/codebuild/${local.project_name_with_suffix}' | fields @timestamp, @message\n| filter @message like /QUALITY GATE/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Quality Gate Events"
        }
      }
    ]
  })
}

# ===== SAMPLE BUILDSPEC CREATION =====

# Create a sample buildspec.yml file in the artifacts bucket
resource "aws_s3_object" "sample_buildspec" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "sample-buildspec.yml"
  
  content = templatefile("${path.module}/templates/buildspec.yml.tpl", {
    coverage_threshold_param = aws_ssm_parameter.coverage_threshold.name
    sonar_quality_gate_param = aws_ssm_parameter.sonar_quality_gate.name
    security_threshold_param = aws_ssm_parameter.security_threshold.name
    sns_topic_arn           = var.enable_notifications ? aws_sns_topic.quality_gate_notifications[0].arn : ""
  })
  
  tags = local.common_tags
}

# Create the buildspec template file
resource "local_file" "buildspec_template" {
  filename = "${path.module}/templates/buildspec.yml.tpl"
  content  = <<EOF
version: 0.2

env:
  parameter-store:
    COVERAGE_THRESHOLD: ${coverage_threshold_param}
    SONAR_QUALITY_GATE: ${sonar_quality_gate_param}
    SECURITY_THRESHOLD: ${security_threshold_param}
  variables:
    MAVEN_OPTS: "-Dmaven.repo.local=.m2/repository"

phases:
  install:
    runtime-versions:
      java: corretto21
    commands:
      - echo "Installing dependencies and tools..."
      - apt-get update && apt-get install -y curl unzip jq
      - curl -sSL https://github.com/SonarSource/sonar-scanner-cli/releases/download/4.8.0.2856/sonar-scanner-cli-4.8.0.2856-linux.zip -o sonar-scanner.zip
      - unzip sonar-scanner.zip
      - export PATH=$PATH:$PWD/sonar-scanner-4.8.0.2856-linux/bin
      - curl -sSL https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip -o dependency-check.zip
      - unzip dependency-check.zip
      - chmod +x dependency-check/bin/dependency-check.sh

  pre_build:
    commands:
      - echo "Validating build environment..."
      - java -version
      - mvn -version
      - echo "Build started on $(date)"

  build:
    commands:
      - echo "=== PHASE 1: Compile and Unit Tests ==="
      - mvn clean compile test
      - echo "✅ Unit tests completed"
      
      - echo "=== PHASE 2: Code Coverage Analysis ==="
      - mvn jacoco:report
      - COVERAGE=$$(grep -o 'Total[^%]*%' target/site/jacoco/index.html | grep -o '[0-9]*' | head -1)
      - echo "Code coverage: $${COVERAGE}%"
      - |
        if [ "$${COVERAGE:-0}" -lt "$${COVERAGE_THRESHOLD}" ]; then
          echo "❌ QUALITY GATE FAILED: Coverage $${COVERAGE}% below threshold $${COVERAGE_THRESHOLD}%"
          aws sns publish --topic-arn ${sns_topic_arn} --message "Quality Gate Failed: Coverage $${COVERAGE}% below threshold $${COVERAGE_THRESHOLD}%" --subject "Quality Gate Failure"
          exit 1
        fi
      - echo "✅ Code coverage check passed"
      
      - echo "=== PHASE 3: Static Code Analysis ==="
      - mvn sonar:sonar -Dsonar.projectKey=quality-gates-demo -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=$${SONAR_TOKEN}
      - echo "✅ SonarQube analysis completed"
      
      - echo "=== PHASE 4: Security Scanning ==="
      - ./dependency-check/bin/dependency-check.sh --project "Quality Gates Demo" --scan . --format JSON --out ./security-report.json
      - |
        HIGH_VULNS=$$(jq '.dependencies[]?.vulnerabilities[]? | select(.severity == "HIGH") | length' security-report.json 2>/dev/null | wc -l)
        if [ "$${HIGH_VULNS}" -gt 0 ]; then
          echo "❌ QUALITY GATE FAILED: Found $${HIGH_VULNS} HIGH severity vulnerabilities"
          aws sns publish --topic-arn ${sns_topic_arn} --message "Quality Gate Failed: $${HIGH_VULNS} HIGH severity vulnerabilities found" --subject "Security Gate Failure"
          exit 1
        fi
      - echo "✅ Security scan passed"
      
      - echo "=== PHASE 5: Integration Tests ==="
      - mvn verify
      - echo "✅ Integration tests completed"
      
      - echo "=== PHASE 6: Quality Gate Summary ==="
      - echo "All quality gates passed successfully!"
      - aws sns publish --topic-arn ${sns_topic_arn} --message "Quality Gate Success: All checks passed for build $${CODEBUILD_BUILD_ID}" --subject "Quality Gate Success"

  post_build:
    commands:
      - echo "=== Generating Quality Reports ==="
      - mkdir -p quality-reports
      - cp -r target/site/jacoco quality-reports/coverage-report || true
      - cp security-report.json quality-reports/ || true
      - echo "Build completed on $(date)"

artifacts:
  files:
    - target/*.jar
    - quality-reports/**/*
  name: quality-gates-artifacts

reports:
  jacoco-reports:
    files:
      - target/site/jacoco/jacoco.xml
    file-format: JACOCOXML
  junit-reports:
    files:
      - target/surefire-reports/*.xml
    file-format: JUNITXML

cache:
  paths:
    - .m2/repository/**/*
EOF
}