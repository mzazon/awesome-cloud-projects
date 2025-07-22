#!/bin/bash

# AWS App2Container Application Modernization Deployment Script
# This script automates the deployment of a containerized application using AWS App2Container
# Based on the recipe: Application Modernization with App2Container

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "An error occurred on line $1. Exiting."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Display script header
echo "=================================================="
echo "  AWS App2Container Deployment Script"
echo "  Recipe: Building Application Modernization"
echo "=================================================="
echo ""

# Configuration variables with defaults
DRY_RUN=${DRY_RUN:-false}
SKIP_APP2CONTAINER_INSTALL=${SKIP_APP2CONTAINER_INSTALL:-false}
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
WORKSPACE_PATH=${WORKSPACE_PATH:-/opt/app2container}
ENABLE_MONITORING=${ENABLE_MONITORING:-true}
ENABLE_AUTOSCALING=${ENABLE_AUTOSCALING:-true}

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version (should be v2)
    AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
    if [ "$AWS_CLI_VERSION" -lt 2 ]; then
        log_warning "AWS CLI v2 is recommended. Current version: $(aws --version)"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker Engine 17.07 or later."
        exit 1
    fi
    
    # Check Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing jq for JSON parsing..."
        if command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        else
            log_error "Please install jq manually for JSON parsing."
            exit 1
        fi
    fi
    
    # Check available disk space (need at least 20GB)
    AVAILABLE_SPACE=$(df /opt 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    REQUIRED_SPACE=$((20 * 1024 * 1024)) # 20GB in KB
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_error "Insufficient disk space. Need at least 20GB free in /opt directory."
        exit 1
    fi
    
    # Check if running as root or with sudo privileges
    if [ "$EUID" -ne 0 ]; then
        log_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    export CLUSTER_NAME="app2container-cluster-${RANDOM_SUFFIX}"
    export ECR_REPO_NAME="modernized-app-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="app2container-artifacts-${RANDOM_SUFFIX}"
    export CODECOMMIT_REPO_NAME="app2container-pipeline-${RANDOM_SUFFIX}"
    
    # Create environment file for persistence
    cat > /tmp/app2container-env.sh << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export CLUSTER_NAME="${CLUSTER_NAME}"
export ECR_REPO_NAME="${ECR_REPO_NAME}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME}"
export CODECOMMIT_REPO_NAME="${CODECOMMIT_REPO_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    log_success "Environment variables configured"
    log "Cluster Name: ${CLUSTER_NAME}"
    log "ECR Repository: ${ECR_REPO_NAME}"
    log "S3 Bucket: ${S3_BUCKET_NAME}"
}

# Create foundational AWS resources
create_aws_resources() {
    log "Creating foundational AWS resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would create S3 bucket, ECR repository, and CodeCommit repository"
        return 0
    fi
    
    # Create S3 bucket for App2Container artifacts
    if aws s3 ls "s3://${S3_BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
        log_success "Created S3 bucket: ${S3_BUCKET_NAME}"
    fi
    
    # Create ECR repository
    if aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "ECR repository ${ECR_REPO_NAME} already exists"
    else
        aws ecr create-repository \
            --repository-name "${ECR_REPO_NAME}" \
            --region "${AWS_REGION}"
        log_success "Created ECR repository: ${ECR_REPO_NAME}"
    fi
    
    # Create CodeCommit repository
    if aws codecommit get-repository --repository-name "${CODECOMMIT_REPO_NAME}" &>/dev/null; then
        log_warning "CodeCommit repository ${CODECOMMIT_REPO_NAME} already exists"
    else
        aws codecommit create-repository \
            --repository-name "${CODECOMMIT_REPO_NAME}" \
            --repository-description "App2Container modernization pipeline"
        log_success "Created CodeCommit repository: ${CODECOMMIT_REPO_NAME}"
    fi
}

# Install and configure App2Container
install_app2container() {
    if [ "$SKIP_APP2CONTAINER_INSTALL" = "true" ]; then
        log_warning "Skipping App2Container installation"
        return 0
    fi
    
    log "Installing and configuring AWS App2Container..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would download and install App2Container"
        return 0
    fi
    
    # Check if App2Container is already installed
    if command -v app2container &> /dev/null; then
        log_warning "App2Container already installed"
        app2container --version
    else
        # Download App2Container installer
        cd /tmp
        curl -o AWSApp2Container-installer-linux.tar.gz \
            https://app2container-release-us-east-1.s3.us-east-1.amazonaws.com/latest/linux/AWSApp2Container-installer-linux.tar.gz
        
        tar xzf AWSApp2Container-installer-linux.tar.gz
        ./install.sh
        
        log_success "App2Container installed successfully"
        app2container --version
        
        # Cleanup installer files
        rm -f AWSApp2Container-installer-linux.tar.gz
        rm -f install.sh
    fi
    
    # Initialize App2Container
    log "Initializing App2Container configuration..."
    
    # Create App2Container configuration directory if it doesn't exist
    mkdir -p "${WORKSPACE_PATH}"
    
    # Check if already initialized
    if [ -f "${WORKSPACE_PATH}/.app2container/config.json" ]; then
        log_warning "App2Container already initialized"
    else
        # Initialize with non-interactive configuration
        cat > /tmp/a2c-init-config.json << EOF
{
    "workspace": "${WORKSPACE_PATH}",
    "awsProfile": "default",
    "s3Bucket": "${S3_BUCKET_NAME}",
    "dockerContentTrust": false,
    "reportUsage": true
}
EOF
        
        app2container init --config-file /tmp/a2c-init-config.json
        log_success "App2Container initialized"
        
        # Cleanup config file
        rm -f /tmp/a2c-init-config.json
    fi
}

# Discover and analyze applications
discover_applications() {
    log "Discovering applications for containerization..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would discover and analyze applications"
        return 0
    fi
    
    # Create application inventory
    app2container inventory
    
    export INVENTORY_FILE="${WORKSPACE_PATH}/inventory.json"
    
    if [ ! -f "${INVENTORY_FILE}" ]; then
        log_error "Application inventory not found. No applications discovered."
        exit 1
    fi
    
    # Display discovered applications
    log "Discovered applications:"
    cat "${INVENTORY_FILE}" | jq -r '.[] | "- Application ID: \(.applicationId) | Type: \(.applicationType) | Server: \(.serverName)"'
    
    # Extract first Java application ID
    export APP_ID=$(jq -r '.[] | select(.applicationType == "java") | .applicationId' "${INVENTORY_FILE}" | head -1)
    
    if [ -z "${APP_ID}" ] || [ "${APP_ID}" = "null" ]; then
        log_error "No Java applications found for containerization."
        exit 1
    fi
    
    log_success "Selected application for containerization: ${APP_ID}"
    
    # Add APP_ID to environment file
    echo "export APP_ID=\"${APP_ID}\"" >> /tmp/app2container-env.sh
}

# Analyze application dependencies
analyze_application() {
    log "Analyzing application dependencies for ${APP_ID}..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would analyze application ${APP_ID}"
        return 0
    fi
    
    # Analyze the application
    app2container analyze --application-id "${APP_ID}"
    
    export ANALYSIS_FILE="${WORKSPACE_PATH}/${APP_ID}/analysis.json"
    
    if [ ! -f "${ANALYSIS_FILE}" ]; then
        log_error "Application analysis failed. Analysis file not found."
        exit 1
    fi
    
    # Display analysis summary
    log "Application analysis summary:"
    echo "- Image Tag: $(jq -r '.containerParameters.imageTag' "${ANALYSIS_FILE}")"
    echo "- Base OS: $(jq -r '.containerParameters.imageBaseOS' "${ANALYSIS_FILE}")"
    echo "- Application Port: $(jq -r '.containerParameters.serverPort' "${ANALYSIS_FILE}")"
    
    log_success "Application analysis completed"
}

# Extract and containerize application
containerize_application() {
    log "Extracting and containerizing application..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would extract and containerize application ${APP_ID}"
        return 0
    fi
    
    # Extract application artifacts
    app2container extract --application-id "${APP_ID}"
    
    export EXTRACT_DIR="${WORKSPACE_PATH}/${APP_ID}/extract"
    
    if [ ! -d "${EXTRACT_DIR}" ]; then
        log_error "Application extraction failed. Extract directory not found."
        exit 1
    fi
    
    log_success "Application artifacts extracted"
    
    # Containerize the application
    app2container containerize --application-id "${APP_ID}"
    
    # Verify container image was created
    export CONTAINER_IMAGE=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep "${APP_ID}" | head -1)
    
    if [ -z "${CONTAINER_IMAGE}" ]; then
        log_error "Container image creation failed."
        exit 1
    fi
    
    log_success "Application containerized: ${CONTAINER_IMAGE}"
    
    # Test container locally
    log "Testing containerized application locally..."
    docker run -d -p 8080:8080 --name "test-${APP_ID}" "${CONTAINER_IMAGE}" || true
    
    # Wait for container to start
    sleep 10
    
    # Check if container is running
    if docker ps | grep "test-${APP_ID}" &>/dev/null; then
        log_success "Container is running successfully"
        docker stop "test-${APP_ID}" && docker rm "test-${APP_ID}"
    else
        log_warning "Container test completed (container may have exited)"
        docker rm "test-${APP_ID}" 2>/dev/null || true
    fi
    
    # Add CONTAINER_IMAGE to environment file
    echo "export CONTAINER_IMAGE=\"${CONTAINER_IMAGE}\"" >> /tmp/app2container-env.sh
}

# Create ECS cluster and deploy application
deploy_to_ecs() {
    log "Creating ECS cluster and deploying application..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would create ECS cluster and deploy application"
        return 0
    fi
    
    # Create ECS cluster
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        log_warning "ECS cluster ${CLUSTER_NAME} already exists"
    else
        aws ecs create-cluster \
            --cluster-name "${CLUSTER_NAME}" \
            --capacity-providers FARGATE \
            --default-capacity-provider-strategy \
            capacityProvider=FARGATE,weight=1 \
            --region "${AWS_REGION}"
        log_success "ECS cluster created: ${CLUSTER_NAME}"
    fi
    
    # Generate and deploy ECS artifacts
    app2container generate app-deployment \
        --application-id "${APP_ID}" \
        --deploy-target ecs \
        --deploy
    
    log_success "Application deployed to ECS"
    
    # Get service information
    export SERVICE_NAME=$(aws ecs list-services --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" \
        --query 'serviceArns[0]' --output text | cut -d'/' -f2 2>/dev/null || echo "")
    
    if [ -n "${SERVICE_NAME}" ]; then
        log_success "ECS service created: ${SERVICE_NAME}"
        echo "export SERVICE_NAME=\"${SERVICE_NAME}\"" >> /tmp/app2container-env.sh
    fi
}

# Set up CI/CD pipeline
setup_cicd_pipeline() {
    log "Setting up CI/CD pipeline..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would set up CI/CD pipeline"
        return 0
    fi
    
    # Generate CI/CD pipeline artifacts
    app2container generate pipeline \
        --application-id "${APP_ID}" \
        --pipeline-type codepipeline
    
    export PIPELINE_DIR="${WORKSPACE_PATH}/${APP_ID}/pipeline"
    
    if [ -f "${PIPELINE_DIR}/codepipeline.yml" ]; then
        # Deploy the CI/CD pipeline
        aws cloudformation create-stack \
            --stack-name "app2container-pipeline-${APP_ID}" \
            --template-body "file://${PIPELINE_DIR}/codepipeline.yml" \
            --capabilities CAPABILITY_IAM \
            --parameters "ParameterKey=RepositoryName,ParameterValue=${CODECOMMIT_REPO_NAME}" \
            --region "${AWS_REGION}"
        
        # Wait for pipeline creation (with timeout)
        log "Waiting for CI/CD pipeline creation (this may take a few minutes)..."
        aws cloudformation wait stack-create-complete \
            --stack-name "app2container-pipeline-${APP_ID}" \
            --region "${AWS_REGION}"
        
        log_success "CI/CD pipeline deployed successfully"
    else
        log_warning "Pipeline template not found, skipping CI/CD setup"
    fi
}

# Configure monitoring and auto scaling
configure_monitoring() {
    if [ "$ENABLE_MONITORING" != "true" ]; then
        log_warning "Monitoring disabled, skipping configuration"
        return 0
    fi
    
    log "Configuring monitoring and auto scaling..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would configure monitoring and auto scaling"
        return 0
    fi
    
    if [ -z "${SERVICE_NAME}" ]; then
        log_warning "Service name not available, skipping auto scaling configuration"
        return 0
    fi
    
    # Create Application Auto Scaling target
    aws application-autoscaling register-scalable-target \
        --service-namespace ecs \
        --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
        --scalable-dimension ecs:service:DesiredCount \
        --min-capacity 1 \
        --max-capacity 10 \
        --region "${AWS_REGION}" || log_warning "Auto scaling target already exists"
    
    # Create scaling policy
    aws application-autoscaling put-scaling-policy \
        --service-namespace ecs \
        --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
        --scalable-dimension ecs:service:DesiredCount \
        --policy-name cpu-scaling-policy \
        --policy-type TargetTrackingScaling \
        --target-tracking-scaling-policy-configuration '{
            "TargetValue": 70.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' \
        --region "${AWS_REGION}" || log_warning "Scaling policy already exists"
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "App2Container-${APP_ID}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/ECS", "CPUUtilization", "ServiceName", "'${SERVICE_NAME}'", "ClusterName", "'${CLUSTER_NAME}'"]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'${AWS_REGION}'",
                        "title": "ECS CPU Utilization"
                    }
                }
            ]
        }' \
        --region "${AWS_REGION}" || log_warning "Dashboard creation failed"
    
    log_success "Monitoring and auto scaling configured"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Check ECR repository
    if aws ecr describe-images --repository-name "${ECR_REPO_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        log_success "Container image available in ECR"
    else
        log_warning "Container image not found in ECR"
    fi
    
    # Check ECS cluster
    if aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" \
            --query 'clusters[0].status' --output text)
        log_success "ECS cluster status: ${CLUSTER_STATUS}"
    else
        log_warning "ECS cluster not found"
    fi
    
    # Check ECS service if available
    if [ -n "${SERVICE_NAME}" ]; then
        SERVICE_STATUS=$(aws ecs describe-services \
            --cluster "${CLUSTER_NAME}" \
            --services "${SERVICE_NAME}" \
            --region "${AWS_REGION}" \
            --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
            --output table 2>/dev/null || echo "Service status unavailable")
        log "ECS service status: ${SERVICE_STATUS}"
    fi
    
    log_success "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "=================================================="
    echo "  AWS App2Container Deployment Summary"
    echo "=================================================="
    echo ""
    echo "Resources Created:"
    echo "- S3 Bucket: ${S3_BUCKET_NAME}"
    echo "- ECR Repository: ${ECR_REPO_NAME}"
    echo "- CodeCommit Repository: ${CODECOMMIT_REPO_NAME}"
    echo "- ECS Cluster: ${CLUSTER_NAME}"
    if [ -n "${SERVICE_NAME}" ]; then
        echo "- ECS Service: ${SERVICE_NAME}"
    fi
    if [ -n "${APP_ID}" ]; then
        echo "- Application ID: ${APP_ID}"
    fi
    echo ""
    echo "Environment file saved to: /tmp/app2container-env.sh"
    echo "To reuse these variables in another session:"
    echo "source /tmp/app2container-env.sh"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor application in ECS console"
    echo "2. Test application functionality"
    echo "3. Configure additional monitoring as needed"
    echo "4. Use destroy.sh script to clean up resources"
    echo ""
    echo "=================================================="
}

# Main execution flow
main() {
    log "Starting AWS App2Container deployment..."
    
    # Check if dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "Running in DRY RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_aws_resources
    install_app2container
    discover_applications
    analyze_application
    containerize_application
    deploy_to_ecs
    setup_cicd_pipeline
    configure_monitoring
    validate_deployment
    display_summary
    
    log_success "AWS App2Container deployment completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi