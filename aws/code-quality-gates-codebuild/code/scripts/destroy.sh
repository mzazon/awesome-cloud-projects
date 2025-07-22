#!/bin/bash

# Quality Gates CodeBuild Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RECIPE_NAME="code-quality-gates-codebuild"

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Display banner
echo -e "${RED}"
echo "========================================"
echo "  CodeBuild Quality Gates Cleanup      "
echo "========================================"
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install it first."
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS CLI is not configured. Please run 'aws configure' first."
fi

# Load deployment information if available
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.env"
if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
    log "Loading deployment information from ${DEPLOYMENT_INFO_FILE}..."
    source "$DEPLOYMENT_INFO_FILE"
    log_success "Loaded deployment information"
else
    log_warning "No deployment information file found. Using manual input..."
    
    # Get AWS account information
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for resource names
    echo ""
    echo "Please provide the resource names to clean up:"
    read -p "CodeBuild Project Name: " PROJECT_NAME
    read -p "S3 Bucket Name: " BUCKET_NAME
    read -p "SNS Topic Name: " SNS_TOPIC_NAME
    
    if [[ -z "$PROJECT_NAME" || -z "$BUCKET_NAME" || -z "$SNS_TOPIC_NAME" ]]; then
        error_exit "All resource names are required for cleanup"
    fi
    
    export PROJECT_NAME
    export BUCKET_NAME
    export SNS_TOPIC_NAME
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    export DASHBOARD_NAME="Quality-Gates-${PROJECT_NAME}"
fi

log "AWS Account ID: ${AWS_ACCOUNT_ID}"
log "AWS Region: ${AWS_REGION}"
log "Project Name: ${PROJECT_NAME}"
log "S3 Bucket: ${BUCKET_NAME}"
log "SNS Topic: ${SNS_TOPIC_NAME}"

# Confirmation prompt
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}"
echo "   - CodeBuild Project: ${PROJECT_NAME}"
echo "   - S3 Bucket: ${BUCKET_NAME} (and all contents)"
echo "   - SNS Topic: ${SNS_TOPIC_NAME}"
echo "   - IAM Role: ${PROJECT_NAME}-service-role"
echo "   - IAM Policy: ${PROJECT_NAME}-quality-gate-policy"
echo "   - CloudWatch Dashboard: ${DASHBOARD_NAME}"
echo "   - Systems Manager Parameters: /quality-gates/*"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

# Start cleanup process
log "Starting cleanup process..."

# Stop any running builds
log "Checking for running builds..."
RUNNING_BUILDS=$(aws codebuild list-builds-for-project --project-name ${PROJECT_NAME} --query 'ids' --output text 2>/dev/null || echo "")
if [[ -n "$RUNNING_BUILDS" ]]; then
    log_warning "Found running builds. Stopping them..."
    for build_id in $RUNNING_BUILDS; do
        BUILD_STATUS=$(aws codebuild batch-get-builds --ids ${build_id} --query 'builds[0].buildStatus' --output text 2>/dev/null || echo "")
        if [[ "$BUILD_STATUS" == "IN_PROGRESS" ]]; then
            log "Stopping build: ${build_id}"
            aws codebuild stop-build --id ${build_id} >/dev/null 2>&1 || log_warning "Failed to stop build ${build_id}"
        fi
    done
    log "Waiting for builds to stop..."
    sleep 10
fi

# Delete CodeBuild project
log "Deleting CodeBuild project..."
if aws codebuild describe-projects --names ${PROJECT_NAME} >/dev/null 2>&1; then
    aws codebuild delete-project --name ${PROJECT_NAME}
    log_success "Deleted CodeBuild project: ${PROJECT_NAME}"
else
    log_warning "CodeBuild project ${PROJECT_NAME} not found"
fi

# Delete CloudWatch dashboard
log "Deleting CloudWatch dashboard..."
if aws cloudwatch describe-dashboards --dashboard-names ${DASHBOARD_NAME} >/dev/null 2>&1; then
    aws cloudwatch delete-dashboards --dashboard-names ${DASHBOARD_NAME}
    log_success "Deleted CloudWatch dashboard: ${DASHBOARD_NAME}"
else
    log_warning "CloudWatch dashboard ${DASHBOARD_NAME} not found"
fi

# Delete S3 bucket and contents
log "Deleting S3 bucket and contents..."
if aws s3 ls s3://${BUCKET_NAME} >/dev/null 2>&1; then
    log "Deleting all objects in bucket..."
    aws s3 rm s3://${BUCKET_NAME} --recursive --quiet
    
    # Delete versioned objects if versioning is enabled
    log "Deleting versioned objects..."
    aws s3api delete-objects --bucket ${BUCKET_NAME} --delete "$(aws s3api list-object-versions --bucket ${BUCKET_NAME} --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" --quiet 2>/dev/null || true
    
    # Delete delete markers
    aws s3api delete-objects --bucket ${BUCKET_NAME} --delete "$(aws s3api list-object-versions --bucket ${BUCKET_NAME} --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" --quiet 2>/dev/null || true
    
    log "Deleting bucket..."
    aws s3 rb s3://${BUCKET_NAME}
    log_success "Deleted S3 bucket: ${BUCKET_NAME}"
else
    log_warning "S3 bucket ${BUCKET_NAME} not found"
fi

# Delete SNS topic
log "Deleting SNS topic..."
if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} >/dev/null 2>&1; then
    aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}
    log_success "Deleted SNS topic: ${SNS_TOPIC_ARN}"
else
    log_warning "SNS topic ${SNS_TOPIC_ARN} not found"
fi

# Delete IAM role and policies
log "Deleting IAM role and policies..."

# Detach managed policies
log "Detaching managed policies..."
aws iam detach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess 2>/dev/null || log_warning "Failed to detach CloudWatchLogsFullAccess policy"
aws iam detach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || log_warning "Failed to detach AmazonS3FullAccess policy"

# Detach and delete custom policy
log "Detaching and deleting custom policy..."
aws iam detach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy 2>/dev/null || log_warning "Failed to detach custom policy"

if aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy >/dev/null 2>&1; then
    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy
    log_success "Deleted custom IAM policy"
else
    log_warning "Custom IAM policy not found"
fi

# Delete IAM role
log "Deleting IAM role..."
if aws iam get-role --role-name ${PROJECT_NAME}-service-role >/dev/null 2>&1; then
    aws iam delete-role --role-name ${PROJECT_NAME}-service-role
    log_success "Deleted IAM role: ${PROJECT_NAME}-service-role"
else
    log_warning "IAM role ${PROJECT_NAME}-service-role not found"
fi

# Delete Systems Manager parameters
log "Deleting Systems Manager parameters..."
PARAMETERS_TO_DELETE=(
    "/quality-gates/coverage-threshold"
    "/quality-gates/sonar-quality-gate"
    "/quality-gates/security-threshold"
)

for param in "${PARAMETERS_TO_DELETE[@]}"; do
    if aws ssm get-parameter --name "$param" >/dev/null 2>&1; then
        aws ssm delete-parameter --name "$param"
        log_success "Deleted parameter: $param"
    else
        log_warning "Parameter $param not found"
    fi
done

# Clean up local files
log "Cleaning up local files..."
LOCAL_FILES=(
    "trust-policy.json"
    "quality-gate-policy.json"
    "codebuild-project.json"
    "quality-dashboard.json"
    "buildspec.yml"
    "pom.xml"
    "source-code.zip"
    "deployment-info.env"
)

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_success "Removed local file: $file"
    fi
done

# Remove directories if empty
LOCAL_DIRS=(
    "src"
    "target"
    ".m2"
    "quality-reports"
)

for dir in "${LOCAL_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        log_success "Removed directory: $dir"
    fi
done

# Remove deployment info file
if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
    rm -f "$DEPLOYMENT_INFO_FILE"
    log_success "Removed deployment info file"
fi

# Final verification
log "Performing final verification..."

# Check if resources still exist
REMAINING_RESOURCES=()

if aws codebuild describe-projects --names ${PROJECT_NAME} >/dev/null 2>&1; then
    REMAINING_RESOURCES+=("CodeBuild Project: ${PROJECT_NAME}")
fi

if aws s3 ls s3://${BUCKET_NAME} >/dev/null 2>&1; then
    REMAINING_RESOURCES+=("S3 Bucket: ${BUCKET_NAME}")
fi

if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} >/dev/null 2>&1; then
    REMAINING_RESOURCES+=("SNS Topic: ${SNS_TOPIC_ARN}")
fi

if aws iam get-role --role-name ${PROJECT_NAME}-service-role >/dev/null 2>&1; then
    REMAINING_RESOURCES+=("IAM Role: ${PROJECT_NAME}-service-role")
fi

if aws cloudwatch describe-dashboards --dashboard-names ${DASHBOARD_NAME} >/dev/null 2>&1; then
    REMAINING_RESOURCES+=("CloudWatch Dashboard: ${DASHBOARD_NAME}")
fi

# Display cleanup summary
echo -e "${GREEN}"
echo "========================================"
echo "     Cleanup Summary"
echo "========================================"
echo -e "${NC}"

if [[ ${#REMAINING_RESOURCES[@]} -eq 0 ]]; then
    echo "✅ All resources have been successfully deleted"
    echo ""
    echo "🧹 Cleaned up resources:"
    echo "   - CodeBuild Project: ${PROJECT_NAME}"
    echo "   - S3 Bucket: ${BUCKET_NAME}"
    echo "   - SNS Topic: ${SNS_TOPIC_NAME}"
    echo "   - IAM Role: ${PROJECT_NAME}-service-role"
    echo "   - IAM Policy: ${PROJECT_NAME}-quality-gate-policy"
    echo "   - CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "   - Systems Manager Parameters: /quality-gates/*"
    echo "   - Local temporary files"
    echo ""
    log_success "Quality Gates CodeBuild cleanup completed successfully!"
else
    echo "⚠️  Some resources may still exist:"
    for resource in "${REMAINING_RESOURCES[@]}"; do
        echo "   - $resource"
    done
    echo ""
    echo "Please check the AWS console and manually delete any remaining resources if needed."
    log_warning "Cleanup completed with warnings"
fi

echo ""
echo "💡 Tips:"
echo "   - Check AWS billing for any unexpected charges"
echo "   - Verify in AWS console that all resources are deleted"
echo "   - Review CloudTrail logs for cleanup activities"
echo ""
echo "📞 If you need help:"
echo "   - Check the original recipe documentation"
echo "   - Review AWS documentation for manual cleanup procedures"
echo "   - Contact AWS support if needed"

# Create cleanup report
CLEANUP_REPORT="cleanup-report-$(date +%Y%m%d-%H%M%S).txt"
cat > "$CLEANUP_REPORT" << EOF
Quality Gates CodeBuild Cleanup Report
Generated: $(date)
Script: $0
User: $(whoami)
AWS Account: ${AWS_ACCOUNT_ID}
AWS Region: ${AWS_REGION}

Resources Cleaned Up:
- CodeBuild Project: ${PROJECT_NAME}
- S3 Bucket: ${BUCKET_NAME}
- SNS Topic: ${SNS_TOPIC_NAME}
- IAM Role: ${PROJECT_NAME}-service-role
- IAM Policy: ${PROJECT_NAME}-quality-gate-policy
- CloudWatch Dashboard: ${DASHBOARD_NAME}
- Systems Manager Parameters: /quality-gates/*

Remaining Resources:
$(printf '%s\n' "${REMAINING_RESOURCES[@]}")

Status: $(if [[ ${#REMAINING_RESOURCES[@]} -eq 0 ]]; then echo "SUCCESS"; else echo "COMPLETED WITH WARNINGS"; fi)
EOF

log_success "Cleanup report saved to: $CLEANUP_REPORT"