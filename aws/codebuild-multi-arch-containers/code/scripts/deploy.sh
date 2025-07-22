#!/bin/bash
# Deploy script for Multi-Architecture Container Images with CodeBuild
# This script creates the complete infrastructure for building ARM and x86 container images

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI not configured or authentication failed"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (minimum v2)
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI version 2 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check Docker
    if ! command_exists docker; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check zip
    if ! command_exists zip; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="multi-arch-build-${RANDOM_SUFFIX}"
    export ECR_REPO_NAME="sample-app-${RANDOM_SUFFIX}"
    export CODEBUILD_ROLE_NAME="CodeBuildMultiArchRole-${RANDOM_SUFFIX}"
    export ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"
    
    # Save environment variables to a file for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
PROJECT_NAME=${PROJECT_NAME}
ECR_REPO_NAME=${ECR_REPO_NAME}
CODEBUILD_ROLE_NAME=${CODEBUILD_ROLE_NAME}
ECR_REPO_URI=${ECR_REPO_URI}
EOF
    
    log_success "Environment variables configured"
    log_info "Project Name: ${PROJECT_NAME}"
    log_info "ECR Repository: ${ECR_REPO_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Function to create ECR repository
create_ecr_repository() {
    log_info "Creating ECR repository..."
    
    # Check if repository already exists
    if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_warning "ECR repository ${ECR_REPO_NAME} already exists"
        return 0
    fi
    
    # Create ECR repository
    aws ecr create-repository \
        --repository-name "${ECR_REPO_NAME}" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --region "${AWS_REGION}"
    
    log_success "Created ECR repository: ${ECR_REPO_URI}"
}

# Function to create IAM role for CodeBuild
create_iam_role() {
    log_info "Creating IAM role for CodeBuild..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${CODEBUILD_ROLE_NAME}" >/dev/null 2>&1; then
        log_warning "IAM role ${CODEBUILD_ROLE_NAME} already exists"
        return 0
    fi
    
    # Create trust policy
    cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${CODEBUILD_ROLE_NAME}" \
        --assume-role-policy-document file://trust-policy.json
    
    # Create policy for CodeBuild permissions
    cat > codebuild-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:GetAuthorizationToken",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${CODEBUILD_ROLE_NAME}" \
        --policy-name "CodeBuildMultiArchPolicy" \
        --policy-document file://codebuild-policy.json
    
    log_success "Created IAM role: ${CODEBUILD_ROLE_NAME}"
}

# Function to create sample application
create_sample_application() {
    log_info "Creating sample application..."
    
    # Create application directory
    mkdir -p sample-app
    cd sample-app
    
    # Create Node.js application
    cat > app.js << 'EOF'
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
  console.log(`Server running on port ${PORT}`);
  console.log(`Architecture: ${os.arch()}`);
  console.log(`Platform: ${os.platform()}`);
});
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
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
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
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
    
    # Create buildspec.yml
    cat > buildspec.yml << EOF
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region \$AWS_DEFAULT_REGION | docker login --username AWS --password-stdin \$AWS_ACCOUNT_ID.dkr.ecr.\$AWS_DEFAULT_REGION.amazonaws.com
      - REPOSITORY_URI=\$AWS_ACCOUNT_ID.dkr.ecr.\$AWS_DEFAULT_REGION.amazonaws.com/\$IMAGE_REPO_NAME
      - COMMIT_HASH=\$(echo \$CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=\${COMMIT_HASH:=latest}
      - echo Repository URI is \$REPOSITORY_URI
      - echo Image tag is \$IMAGE_TAG
      
  build:
    commands:
      - echo Build started on \$(date)
      - echo Building multi-architecture Docker image...
      
      # Create and use buildx builder
      - docker buildx create --name multiarch-builder --use --bootstrap
      - docker buildx inspect --bootstrap
      
      # Build and push multi-architecture image
      - |
        docker buildx build \
          --platform linux/amd64,linux/arm64 \
          --tag \$REPOSITORY_URI:latest \
          --tag \$REPOSITORY_URI:\$IMAGE_TAG \
          --push \
          --cache-from type=local,src=/tmp/.buildx-cache \
          --cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max \
          .
      
      # Move cache to prevent unbounded growth
      - rm -rf /tmp/.buildx-cache
      - mv /tmp/.buildx-cache-new /tmp/.buildx-cache
      
  post_build:
    commands:
      - echo Build completed on \$(date)
      - echo Pushing the Docker images...
      - docker buildx imagetools inspect \$REPOSITORY_URI:latest
      - printf '{"ImageURI":"%s"}' \$REPOSITORY_URI:latest > imageDetail.json
      
artifacts:
  files:
    - imageDetail.json

cache:
  paths:
    - '/tmp/.buildx-cache/**/*'
EOF
    
    cd ..
    log_success "Created sample Node.js application with multi-architecture support"
}

# Function to create CodeBuild project
create_codebuild_project() {
    log_info "Creating CodeBuild project..."
    
    # Check if project already exists
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_warning "CodeBuild project ${PROJECT_NAME} already exists"
        return 0
    fi
    
    # Create CodeBuild project configuration
    cat > codebuild-project.json << EOF
{
  "name": "${PROJECT_NAME}",
  "description": "Multi-architecture container image build project",
  "source": {
    "type": "S3",
    "location": "${PROJECT_NAME}-source/source.zip"
  },
  "artifacts": {
    "type": "NO_ARTIFACTS"
  },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_MEDIUM",
    "privilegedMode": true,
    "environmentVariables": [
      {
        "name": "AWS_DEFAULT_REGION",
        "value": "${AWS_REGION}"
      },
      {
        "name": "AWS_ACCOUNT_ID",
        "value": "${AWS_ACCOUNT_ID}"
      },
      {
        "name": "IMAGE_REPO_NAME",
        "value": "${ECR_REPO_NAME}"
      }
    ]
  },
  "serviceRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CODEBUILD_ROLE_NAME}",
  "timeoutInMinutes": 60,
  "cache": {
    "type": "LOCAL",
    "modes": ["LOCAL_DOCKER_LAYER_CACHE"]
  }
}
EOF
    
    # Create CodeBuild project
    aws codebuild create-project \
        --cli-input-json file://codebuild-project.json \
        --region "${AWS_REGION}"
    
    log_success "Created CodeBuild project: ${PROJECT_NAME}"
}

# Function to upload source code to S3
upload_source_code() {
    log_info "Uploading source code to S3..."
    
    # Create S3 bucket for source code
    if aws s3api head-bucket --bucket "${PROJECT_NAME}-source" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_warning "S3 bucket ${PROJECT_NAME}-source already exists"
    else
        aws s3 mb "s3://${PROJECT_NAME}-source" --region "${AWS_REGION}"
    fi
    
    # Create source archive
    cd sample-app
    zip -r ../source.zip . -x "*.git*" "*.DS_Store*"
    cd ..
    
    # Upload source to S3
    aws s3 cp source.zip "s3://${PROJECT_NAME}-source/source.zip" --region "${AWS_REGION}"
    
    log_success "Uploaded source code to S3"
}

# Function to start build
start_build() {
    log_info "Starting CodeBuild build..."
    
    # Start CodeBuild build
    BUILD_ID=$(aws codebuild start-build \
        --project-name "${PROJECT_NAME}" \
        --region "${AWS_REGION}" \
        --query 'build.id' --output text)
    
    echo "BUILD_ID=${BUILD_ID}" >> .env
    
    log_success "Started build with ID: ${BUILD_ID}"
    
    # Monitor build status
    log_info "Monitoring build progress..."
    while true; do
        BUILD_STATUS=$(aws codebuild batch-get-builds \
            --ids "${BUILD_ID}" \
            --region "${AWS_REGION}" \
            --query 'builds[0].buildStatus' --output text)
        
        log_info "Build status: ${BUILD_STATUS}"
        
        if [ "$BUILD_STATUS" = "SUCCEEDED" ]; then
            log_success "Build completed successfully!"
            break
        elif [ "$BUILD_STATUS" = "FAILED" ] || [ "$BUILD_STATUS" = "FAULT" ] || [ "$BUILD_STATUS" = "STOPPED" ] || [ "$BUILD_STATUS" = "TIMED_OUT" ]; then
            log_error "Build failed with status: ${BUILD_STATUS}"
            log_info "Check build logs at: https://console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT_NAME}/history"
            exit 1
        fi
        
        sleep 30
    done
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying multi-architecture image deployment..."
    
    # Check ECR images
    aws ecr describe-images \
        --repository-name "${ECR_REPO_NAME}" \
        --region "${AWS_REGION}" \
        --query 'imageDetails[0].{ImageTags:imageTags,ImagePushedAt:imagePushedAt,ImageSizeInBytes:imageSizeInBytes}'
    
    # Get ECR login token
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    # Inspect multi-architecture image
    docker buildx imagetools inspect "${ECR_REPO_URI}:latest"
    
    log_success "Multi-architecture image verification complete"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f trust-policy.json codebuild-policy.json codebuild-project.json source.zip
    
    log_success "Temporary files cleaned up"
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "=================================="
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "=================================="
    echo
    log_info "Resources Created:"
    echo "  - ECR Repository: ${ECR_REPO_URI}"
    echo "  - CodeBuild Project: ${PROJECT_NAME}"
    echo "  - IAM Role: ${CODEBUILD_ROLE_NAME}"
    echo "  - S3 Bucket: ${PROJECT_NAME}-source"
    echo
    log_info "Multi-architecture container image is now available at:"
    echo "  ${ECR_REPO_URI}:latest"
    echo
    log_info "To test the image on different architectures:"
    echo "  docker pull --platform linux/amd64 ${ECR_REPO_URI}:latest"
    echo "  docker pull --platform linux/arm64 ${ECR_REPO_URI}:latest"
    echo
    log_warning "Remember to run ./destroy.sh to clean up resources when done!"
}

# Main deployment function
main() {
    log_info "Starting multi-architecture container image deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_ecr_repository
    create_iam_role
    create_sample_application
    create_codebuild_project
    upload_source_code
    start_build
    verify_deployment
    cleanup_temp_files
    show_deployment_summary
}

# Run main function
main "$@"