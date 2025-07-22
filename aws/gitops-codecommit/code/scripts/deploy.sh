#!/bin/bash

# GitOps Workflows with AWS CodeCommit and CodeBuild - Deployment Script
# This script automates the deployment of the complete GitOps infrastructure
# including CodeCommit repository, CodeBuild project, ECR repository, and ECS resources

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/gitops-deploy-$(date +%Y%m%d-%H%M%S).log"
RANDOM_SUFFIX=""
REPO_NAME=""
PROJECT_NAME=""
PIPELINE_NAME=""
CLUSTER_NAME=""
ECR_URI=""
REPO_CLONE_URL=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    log "${RED}Check log file: ${LOG_FILE}${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Check if required tools are installed
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        error_exit "Git is not installed. Please install it first."
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured properly."
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "${AWS_REGION}" ]; then
        AWS_REGION="us-east-1"
        warning "No default region found, using us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Set resource names
    REPO_NAME="gitops-demo-${RANDOM_SUFFIX}"
    PROJECT_NAME="gitops-build-${RANDOM_SUFFIX}"
    PIPELINE_NAME="gitops-pipeline-${RANDOM_SUFFIX}"
    CLUSTER_NAME="gitops-cluster-${RANDOM_SUFFIX}"
    
    # Export for use in other functions
    export REPO_NAME PROJECT_NAME PIPELINE_NAME CLUSTER_NAME
    
    log "Environment variables initialized:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  REPO_NAME: ${REPO_NAME}"
    log "  PROJECT_NAME: ${PROJECT_NAME}"
    log "  CLUSTER_NAME: ${CLUSTER_NAME}"
    
    success "Environment initialization complete"
}

# Create CodeCommit repository
create_codecommit_repo() {
    info "Creating CodeCommit repository..."
    
    # Check if repository already exists
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &> /dev/null; then
        warning "Repository ${REPO_NAME} already exists, skipping creation"
        REPO_CLONE_URL=$(aws codecommit get-repository \
            --repository-name "${REPO_NAME}" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
    else
        # Create repository
        aws codecommit create-repository \
            --repository-name "${REPO_NAME}" \
            --repository-description "GitOps workflow demonstration repository" \
            >> "${LOG_FILE}" 2>&1
        
        REPO_CLONE_URL=$(aws codecommit get-repository \
            --repository-name "${REPO_NAME}" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
    fi
    
    success "CodeCommit repository ready: ${REPO_CLONE_URL}"
}

# Create ECR repository
create_ecr_repo() {
    info "Creating ECR repository..."
    
    # Check if repository already exists
    if aws ecr describe-repositories --repository-names "${REPO_NAME}" &> /dev/null; then
        warning "ECR repository ${REPO_NAME} already exists, skipping creation"
    else
        # Create repository
        aws ecr create-repository \
            --repository-name "${REPO_NAME}" \
            --region "${AWS_REGION}" \
            >> "${LOG_FILE}" 2>&1
    fi
    
    # Get repository URI
    ECR_URI=$(aws ecr describe-repositories \
        --repository-names "${REPO_NAME}" \
        --query 'repositories[0].repositoryUri' \
        --output text)
    
    success "ECR repository ready: ${ECR_URI}"
}

# Create IAM roles
create_iam_roles() {
    info "Creating IAM roles..."
    
    # Create CodeBuild service role
    local codebuild_role_name="CodeBuildGitOpsRole-${RANDOM_SUFFIX}"
    
    # Check if role already exists
    if aws iam get-role --role-name "${codebuild_role_name}" &> /dev/null; then
        warning "IAM role ${codebuild_role_name} already exists, skipping creation"
    else
        # Create trust policy
        cat > "/tmp/codebuild-trust-policy.json" << 'EOF'
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
        
        # Create role
        aws iam create-role \
            --role-name "${codebuild_role_name}" \
            --assume-role-policy-document file:///tmp/codebuild-trust-policy.json \
            >> "${LOG_FILE}" 2>&1
        
        # Attach policies
        aws iam attach-role-policy \
            --role-name "${codebuild_role_name}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
        
        aws iam attach-role-policy \
            --role-name "${codebuild_role_name}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
        
        aws iam attach-role-policy \
            --role-name "${codebuild_role_name}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess
        
        # Wait for role to be available
        sleep 10
    fi
    
    success "IAM roles configured"
}

# Create CodeBuild project
create_codebuild_project() {
    info "Creating CodeBuild project..."
    
    # Check if project already exists
    if aws codebuild batch-get-projects --names "${PROJECT_NAME}" &> /dev/null; then
        warning "CodeBuild project ${PROJECT_NAME} already exists, skipping creation"
    else
        # Get CodeBuild role ARN
        local codebuild_role_arn=$(aws iam get-role \
            --role-name "CodeBuildGitOpsRole-${RANDOM_SUFFIX}" \
            --query 'Role.Arn' \
            --output text)
        
        # Create project
        aws codebuild create-project \
            --name "${PROJECT_NAME}" \
            --description "GitOps build project for automated deployments" \
            --source "{
                \"type\": \"CODECOMMIT\",
                \"location\": \"${REPO_CLONE_URL}\",
                \"buildspec\": \"config/buildspecs/buildspec.yml\"
            }" \
            --artifacts "{
                \"type\": \"NO_ARTIFACTS\"
            }" \
            --environment "{
                \"type\": \"LINUX_CONTAINER\",
                \"image\": \"aws/codebuild/amazonlinux2-x86_64-standard:5.0\",
                \"computeType\": \"BUILD_GENERAL1_SMALL\",
                \"privilegedMode\": true
            }" \
            --service-role "${codebuild_role_arn}" \
            >> "${LOG_FILE}" 2>&1
    fi
    
    success "CodeBuild project ready"
}

# Create ECS cluster
create_ecs_cluster() {
    info "Creating ECS cluster..."
    
    # Check if cluster already exists
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q "${CLUSTER_NAME}"; then
        warning "ECS cluster ${CLUSTER_NAME} already exists, skipping creation"
    else
        # Create cluster
        aws ecs create-cluster --cluster-name "${CLUSTER_NAME}" >> "${LOG_FILE}" 2>&1
    fi
    
    # Create CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "/ecs/gitops-app" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "/ecs/gitops-app"; then
        warning "CloudWatch log group /ecs/gitops-app already exists, skipping creation"
    else
        aws logs create-log-group --log-group-name "/ecs/gitops-app" >> "${LOG_FILE}" 2>&1
    fi
    
    success "ECS cluster and logging configured"
}

# Setup Git repository with initial content
setup_git_repo() {
    info "Setting up Git repository with initial content..."
    
    local temp_dir="/tmp/gitops-${RANDOM_SUFFIX}"
    
    # Clean up any existing temp directory
    rm -rf "${temp_dir}"
    
    # Clone repository
    git clone "${REPO_CLONE_URL}" "${temp_dir}" >> "${LOG_FILE}" 2>&1
    cd "${temp_dir}"
    
    # Check if repository already has content
    if [ -f "README.md" ]; then
        warning "Repository already has content, skipping initial setup"
        cd - > /dev/null
        return 0
    fi
    
    # Create directory structure
    mkdir -p {app,infrastructure,config}
    mkdir -p infrastructure/{dev,staging,prod}
    mkdir -p config/{buildspecs,policies}
    
    # Create sample application
    cat > app/app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
    res.json({
        message: 'GitOps Demo Application',
        version: process.env.APP_VERSION || '1.0.0',
        environment: process.env.ENVIRONMENT || 'development'
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, () => {
    console.log(`App running on port ${port}`);
});
EOF
    
    # Create package.json
    cat > app/package.json << 'EOF'
{
  "name": "gitops-demo-app",
  "version": "1.0.0",
  "description": "Sample application for GitOps workflow demonstration",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF
    
    # Create Dockerfile
    cat > app/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .
EXPOSE 3000
CMD ["npm", "start"]
EOF
    
    # Create buildspec
    cat > config/buildspecs/buildspec.yml << EOF
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region \$AWS_DEFAULT_REGION | docker login --username AWS --password-stdin ${ECR_URI}
      - REPOSITORY_URI=${ECR_URI}
      - COMMIT_HASH=\$(echo \$CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=\$COMMIT_HASH
      - echo Build started on \$(date)
      
  build:
    commands:
      - echo Build started on \$(date)
      - echo Building the Docker image...
      - cd app
      - docker build -t \$REPOSITORY_URI:latest .
      - docker tag \$REPOSITORY_URI:latest \$REPOSITORY_URI:\$IMAGE_TAG
      
  post_build:
    commands:
      - echo Build completed on \$(date)
      - echo Pushing the Docker images...
      - docker push \$REPOSITORY_URI:latest
      - docker push \$REPOSITORY_URI:\$IMAGE_TAG
      - echo Writing image definitions file...
      - printf '[{"name":"gitops-app","imageUri":"%s"}]' \$REPOSITORY_URI:\$IMAGE_TAG > imagedefinitions.json
      
artifacts:
  files:
    - imagedefinitions.json
    - infrastructure/**/*
  name: GitOpsArtifacts
EOF
    
    # Create task definition
    cat > infrastructure/task-definition.json << EOF
{
  "family": "gitops-app-task",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "gitops-app",
      "image": "${ECR_URI}:latest",
      "portMappings": [
        {
          "containerPort": 3000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "ENVIRONMENT",
          "value": "development"
        },
        {
          "name": "APP_VERSION",
          "value": "1.0.0"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/gitops-app",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
EOF
    
    # Create README
    cat > README.md << 'EOF'
# GitOps Demo Application

This repository demonstrates GitOps workflows using AWS CodeCommit and CodeBuild.

## Structure

- `app/` - Sample Node.js application
- `infrastructure/` - Infrastructure definitions
- `config/` - Build and deployment configurations

## GitOps Workflow

1. Make changes to application code
2. Commit and push to main branch
3. CodeBuild automatically builds and deploys changes
4. Monitor deployment through AWS console

## Local Development

```bash
cd app
npm install
npm start
```

The application will be available at http://localhost:3000
EOF
    
    # Configure Git if not already configured
    if ! git config user.email &> /dev/null; then
        git config user.email "gitops-demo@example.com"
        git config user.name "GitOps Demo"
    fi
    
    # Commit and push
    git add .
    git commit -m "Initial GitOps configuration

- Add sample Node.js application with health endpoints
- Configure CodeBuild buildspec for automated CI/CD
- Define ECS task definition for container deployment
- Establish GitOps directory structure
- Configure IAM roles and ECR repository" >> "${LOG_FILE}" 2>&1
    
    git push origin main >> "${LOG_FILE}" 2>&1
    
    # Return to original directory
    cd - > /dev/null
    
    success "Git repository configured with initial content"
}

# Test the deployment
test_deployment() {
    info "Testing deployment..."
    
    # Start a test build
    local build_id=$(aws codebuild start-build \
        --project-name "${PROJECT_NAME}" \
        --query 'build.id' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${build_id}" ]; then
        info "Test build started: ${build_id}"
        
        # Wait for build to start
        sleep 10
        
        # Check build status
        local build_status=$(aws codebuild batch-get-builds \
            --ids "${build_id}" \
            --query 'builds[0].buildStatus' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        info "Build status: ${build_status}"
        
        if [ "${build_status}" == "IN_PROGRESS" ]; then
            info "Build is running. Check AWS Console for progress."
        elif [ "${build_status}" == "SUCCEEDED" ]; then
            success "Test build completed successfully"
        else
            warning "Build status: ${build_status}. Check AWS Console for details."
        fi
    else
        warning "Could not start test build. Check configuration manually."
    fi
}

# Generate deployment summary
generate_summary() {
    info "Generating deployment summary..."
    
    local summary_file="/tmp/gitops-deployment-summary.txt"
    
    cat > "${summary_file}" << EOF
GitOps Workflow Deployment Summary
==================================

Deployment completed at: $(date)

Resources Created:
- CodeCommit Repository: ${REPO_NAME}
- ECR Repository: ${ECR_URI}
- CodeBuild Project: ${PROJECT_NAME}
- ECS Cluster: ${CLUSTER_NAME}
- IAM Role: CodeBuildGitOpsRole-${RANDOM_SUFFIX}

Repository URL: ${REPO_CLONE_URL}

Next Steps:
1. Clone the repository locally: git clone ${REPO_CLONE_URL}
2. Make changes to the application code
3. Commit and push changes to trigger automated deployment
4. Monitor builds in the AWS CodeBuild console
5. View container logs in CloudWatch at log group: /ecs/gitops-app

Environment Variables (save these for cleanup):
export REPO_NAME="${REPO_NAME}"
export PROJECT_NAME="${PROJECT_NAME}"
export CLUSTER_NAME="${CLUSTER_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export AWS_REGION="${AWS_REGION}"

Log File: ${LOG_FILE}
EOF
    
    cat "${summary_file}"
    
    success "Deployment summary saved to: ${summary_file}"
}

# Main deployment function
main() {
    log "${GREEN}Starting GitOps Workflow Deployment${NC}"
    log "Log file: ${LOG_FILE}"
    
    # Check if running with proper permissions
    if [ "$EUID" -eq 0 ]; then
        warning "Running as root. This is not recommended for security reasons."
    fi
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    create_codecommit_repo
    create_ecr_repo
    create_iam_roles
    create_codebuild_project
    create_ecs_cluster
    setup_git_repo
    test_deployment
    generate_summary
    
    success "GitOps workflow deployment completed successfully!"
    log "Check the summary above for next steps and resource information."
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi