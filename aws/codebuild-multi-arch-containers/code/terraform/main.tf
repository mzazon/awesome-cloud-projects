# Main Terraform configuration for multi-architecture container images with CodeBuild
# This file creates all the necessary infrastructure components

# Data sources for current AWS account and region
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
  # Unique resource names
  project_name_full = "${var.project_name}-${random_string.suffix.result}"
  ecr_repo_name     = "${var.ecr_repository_name}-${random_string.suffix.result}"
  codebuild_project = "${var.project_name}-${random_string.suffix.result}"
  s3_bucket_name    = "${var.project_name}-source-${random_string.suffix.result}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })
  
  # ECR repository URI
  ecr_repository_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.ecr_repo_name}"
}

# S3 bucket for storing source code
resource "aws_s3_bucket" "source_bucket" {
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "CodeBuild Source Bucket"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source_bucket_encryption" {
  bucket = aws_s3_bucket.source_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "source_bucket_pab" {
  bucket = aws_s3_bucket.source_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECR repository for storing multi-architecture container images
resource "aws_ecr_repository" "container_repo" {
  name                 = local.ecr_repo_name
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, {
    Name = "Multi-Architecture Container Repository"
  })
}

# ECR lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "container_repo_lifecycle" {
  count      = var.ecr_lifecycle_policy ? 1 : 0
  repository = aws_ecr_repository.container_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["latest"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
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

# IAM role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "${local.project_name_full}-codebuild-role"

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
  })
}

# IAM policy for CodeBuild CloudWatch Logs access
resource "aws_iam_role_policy" "codebuild_logs_policy" {
  name = "${local.project_name_full}-codebuild-logs-policy"
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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${local.codebuild_project}*"
      }
    ]
  })
}

# IAM policy for CodeBuild ECR access
resource "aws_iam_role_policy" "codebuild_ecr_policy" {
  name = "${local.project_name_full}-codebuild-ecr-policy"
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
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for CodeBuild S3 access
resource "aws_iam_role_policy" "codebuild_s3_policy" {
  name = "${local.project_name_full}-codebuild-s3-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.source_bucket.arn,
          "${aws_s3_bucket.source_bucket.arn}/*"
        ]
      }
    ]
  })
}

# CodeBuild project for multi-architecture container builds
resource "aws_codebuild_project" "multi_arch_build" {
  name         = local.codebuild_project
  description  = "Multi-architecture container image build project for ${var.project_name}"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  # Cache configuration for optimized builds
  cache {
    type  = var.cache_type
    modes = var.cache_type == "LOCAL" ? var.cache_modes : []
  }

  environment {
    compute_type                = var.codebuild_compute_type
    image                      = var.codebuild_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = var.codebuild_privileged_mode

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = local.ecr_repo_name
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }

    environment_variable {
      name  = "TARGET_PLATFORMS"
      value = join(",", var.target_platforms)
    }
  }

  source {
    type     = var.source_type
    location = var.source_location != "" ? var.source_location : "${aws_s3_bucket.source_bucket.bucket}/source.zip"
    
    buildspec = var.buildspec_file
  }

  # VPC configuration if enabled
  dynamic "vpc_config" {
    for_each = var.enable_vpc_config ? [1] : []
    content {
      vpc_id = var.vpc_id
      subnets = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  tags = merge(local.common_tags, {
    Name = "Multi-Architecture Build Project"
  })
}

# CloudWatch Log Group for CodeBuild
resource "aws_cloudwatch_log_group" "codebuild_logs" {
  name              = "/aws/codebuild/${local.codebuild_project}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "CodeBuild Logs"
  })
}

# Create sample application files for demonstration
resource "local_file" "sample_app_js" {
  content = <<-EOF
const express = require('express');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    message: 'Hello from multi-architecture container!',
    architecture: os.arch(),
    platform: os.platform(),
    hostname: os.hostname(),
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port $${PORT}`);
  console.log(`Architecture: $${os.arch()}`);
  console.log(`Platform: $${os.platform()}`);
});
EOF

  filename = "${path.module}/sample-app/app.js"
}

resource "local_file" "sample_package_json" {
  content = <<-EOF
{
  "name": "multi-arch-sample",
  "version": "1.0.0",
  "description": "Sample application for multi-architecture builds",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

  filename = "${path.module}/sample-app/package.json"
}

resource "local_file" "sample_dockerfile" {
  content = <<-EOF
# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM node:18-alpine AS build

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Multi-stage build for final image
FROM node:18-alpine AS runtime

# Install security updates
RUN apk update && apk upgrade && apk add --no-cache dumb-init

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy dependencies from build stage
COPY --from=build /app/node_modules ./node_modules

# Copy application code
COPY --chown=nodejs:nodejs . .

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "app.js"]
EOF

  filename = "${path.module}/sample-app/Dockerfile"
}

resource "local_file" "sample_buildspec" {
  content = <<-EOF
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
      - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=$${COMMIT_HASH:=latest}
      - echo Repository URI is $REPOSITORY_URI
      - echo Image tag is $IMAGE_TAG
      
  build:
    commands:
      - echo Build started on $(date)
      - echo Building multi-architecture Docker image...
      
      # Create and use buildx builder
      - docker buildx create --name multiarch-builder --use --bootstrap
      - docker buildx inspect --bootstrap
      
      # Build and push multi-architecture image
      - |
        docker buildx build \
          --platform $TARGET_PLATFORMS \
          --tag $REPOSITORY_URI:latest \
          --tag $REPOSITORY_URI:$IMAGE_TAG \
          --push \
          --cache-from type=local,src=/tmp/.buildx-cache \
          --cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max \
          .
      
      # Move cache to prevent unbounded growth
      - rm -rf /tmp/.buildx-cache
      - mv /tmp/.buildx-cache-new /tmp/.buildx-cache
      
  post_build:
    commands:
      - echo Build completed on $(date)
      - echo Pushing the Docker images...
      - docker buildx imagetools inspect $REPOSITORY_URI:latest
      - printf '{"ImageURI":"%s"}' $REPOSITORY_URI:latest > imageDetail.json
      
artifacts:
  files:
    - imageDetail.json

cache:
  paths:
    - '/tmp/.buildx-cache/**/*'
EOF

  filename = "${path.module}/sample-app/buildspec.yml"
}

# Create ZIP archive of sample application
data "archive_file" "source_zip" {
  type        = "zip"
  source_dir  = "${path.module}/sample-app"
  output_path = "${path.module}/source.zip"
  
  depends_on = [
    local_file.sample_app_js,
    local_file.sample_package_json,
    local_file.sample_dockerfile,
    local_file.sample_buildspec
  ]
}

# Upload source ZIP to S3
resource "aws_s3_object" "source_zip" {
  bucket = aws_s3_bucket.source_bucket.id
  key    = "source.zip"
  source = data.archive_file.source_zip.output_path
  etag   = data.archive_file.source_zip.output_md5

  depends_on = [data.archive_file.source_zip]
}