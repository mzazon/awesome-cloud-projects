#!/bin/bash

# Destroy Advanced CodeBuild Pipelines with Multi-Stage Builds, Caching, and Artifacts Management
# This script safely removes all resources created by the deployment script

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

# Progress tracking
TOTAL_STEPS=9
CURRENT_STEP=0

update_progress() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo
    log_info "Step $CURRENT_STEP/$TOTAL_STEPS: $1"
    echo "Progress: [$(printf '%-50s' | tr ' ' '#' | head -c $((CURRENT_STEP * 50 / TOTAL_STEPS)))$(printf '%-50s' | head -c $((50 - CURRENT_STEP * 50 / TOTAL_STEPS)))] $(((CURRENT_STEP * 100) / TOTAL_STEPS))%"
    echo
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $description"
        log_info "[DRY-RUN] Command: $cmd"
        return 0
    else
        log_info "Executing: $description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed but continuing: $description"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check if resource exists
resource_exists() {
    local check_cmd="$1"
    local resource_type="$2"
    local resource_name="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would check if $resource_type '$resource_name' exists"
        return 0
    else
        if eval "$check_cmd" &>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
}

# Header
echo "================================================================================="
echo "      AWS Advanced CodeBuild Pipelines Cleanup Script"
echo "================================================================================="
echo
echo "This script will remove all resources created by the deployment script including:"
echo "  • CodeBuild projects (3 projects)"
echo "  • Lambda functions (3 functions)"
echo "  • EventBridge rules and targets"
echo "  • ECR repository and all images"
echo "  • S3 buckets and all contents"
echo "  • IAM roles and policies"
echo "  • CloudWatch dashboard"
echo
echo "⚠️  WARNING: This action is IRREVERSIBLE!"
echo "⚠️  All build history, artifacts, and cached data will be permanently deleted!"
echo

# Load configuration if available
if [[ -f ".deployment-config" && "$DRY_RUN" == "false" ]]; then
    log_info "Loading configuration from .deployment-config"
    source .deployment-config
    
    log_info "Configuration loaded:"
    log_info "  Project Name: ${PROJECT_NAME:-Not set}"
    log_info "  AWS Region: ${AWS_REGION:-Not set}"
    log_info "  Cache Bucket: ${CACHE_BUCKET:-Not set}"
    log_info "  Artifact Bucket: ${ARTIFACT_BUCKET:-Not set}"
    log_info "  ECR Repository: ${ECR_REPOSITORY:-Not set}"
else
    log_warning "Configuration file not found. You may need to provide resource names manually."
    
    # If no config file, try to detect current AWS region
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    
    log_info "Using detected AWS region: $AWS_REGION"
    log_info "Using detected AWS account: $AWS_ACCOUNT_ID"
    
    # Prompt for project name if not in config
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        if [[ "$FORCE_DELETE" == "false" ]]; then
            read -p "Enter the project name (or press Enter to scan for projects): " PROJECT_NAME
        fi
        
        if [[ -z "$PROJECT_NAME" ]]; then
            log_info "Scanning for advanced-build-* projects..."
            PROJECTS=$(aws codebuild list-projects --query 'projects[?starts_with(@, `advanced-build-`)]' --output text 2>/dev/null || echo "")
            if [[ -n "$PROJECTS" ]]; then
                log_info "Found projects: $PROJECTS"
                # Extract project base name from first project
                FIRST_PROJECT=$(echo "$PROJECTS" | head -n1 | tr '\t' '\n' | head -n1)
                PROJECT_NAME=$(echo "$FIRST_PROJECT" | sed 's/-dependencies$//' | sed 's/-main$//' | sed 's/-parallel$//')
            fi
        fi
    fi
    
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        # Derive other resource names from project name
        RANDOM_SUFFIX=$(echo "$PROJECT_NAME" | sed 's/advanced-build-//')
        export CACHE_BUCKET="codebuild-cache-${RANDOM_SUFFIX}"
        export ARTIFACT_BUCKET="build-artifacts-${RANDOM_SUFFIX}"
        export ECR_REPOSITORY="app-repository-${RANDOM_SUFFIX}"
        export BUILD_ROLE_NAME="CodeBuildAdvancedRole-${RANDOM_SUFFIX}"
        export DEPENDENCY_BUILD_PROJECT="${PROJECT_NAME}-dependencies"
        export MAIN_BUILD_PROJECT="${PROJECT_NAME}-main"
        export PARALLEL_BUILD_PROJECT="${PROJECT_NAME}-parallel"
    else
        log_error "Could not determine project name. Please ensure you run this script from the deployment directory or provide the project name."
        exit 1
    fi
fi

# Verify we have required information
if [[ -z "${PROJECT_NAME:-}" || -z "${AWS_REGION:-}" ]]; then
    log_error "Missing required configuration. Cannot proceed with cleanup."
    exit 1
fi

# Show what will be deleted
echo
log_info "The following resources will be deleted:"
echo "  📦 CodeBuild Projects:"
echo "    • ${DEPENDENCY_BUILD_PROJECT:-Unknown}"
echo "    • ${MAIN_BUILD_PROJECT:-Unknown}"
echo "    • ${PARALLEL_BUILD_PROJECT:-Unknown}"
echo "  🔧 Lambda Functions:"
echo "    • ${PROJECT_NAME}-orchestrator"
echo "    • ${PROJECT_NAME}-cache-manager"
echo "    • ${PROJECT_NAME}-analytics"
echo "  📅 EventBridge Rules:"
echo "    • cache-optimization-${RANDOM_SUFFIX:-unknown}"
echo "    • build-analytics-${RANDOM_SUFFIX:-unknown}"
echo "  🐳 ECR Repository:"
echo "    • ${ECR_REPOSITORY:-Unknown} (and all images)"
echo "  🗂️  S3 Buckets:"
echo "    • ${CACHE_BUCKET:-Unknown} (and all contents)"
echo "    • ${ARTIFACT_BUCKET:-Unknown} (and all contents)"
echo "  🔐 IAM Resources:"
echo "    • Role: ${BUILD_ROLE_NAME:-Unknown}"
echo "    • Policy: CodeBuildAdvancedPolicy-${RANDOM_SUFFIX:-unknown}"
echo "  📊 CloudWatch Dashboard:"
echo "    • Advanced-CodeBuild-${PROJECT_NAME}"
echo

# Confirm deletion
if [[ "$DRY_RUN" == "false" && "$FORCE_DELETE" == "false" ]]; then
    echo -e "${RED}⚠️  This action cannot be undone!${NC}"
    echo -e "${RED}⚠️  All build artifacts, cache data, and configuration will be permanently lost!${NC}"
    echo
    read -p "Are you absolutely sure you want to delete all these resources? (type 'yes' to confirm): " -r
    if [[ ! "$REPLY" == "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    echo
    log_warning "Starting cleanup in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
fi

# Prerequisites check
log_info "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

log_success "Prerequisites check completed"

# Step 1: Delete Lambda Functions and EventBridge Rules
update_progress "Deleting Lambda Functions and EventBridge Rules"

# Remove EventBridge targets first
if resource_exists "aws events list-targets-by-rule --rule cache-optimization-${RANDOM_SUFFIX}" "EventBridge rule" "cache-optimization-${RANDOM_SUFFIX}"; then
    execute_command "aws events remove-targets --rule cache-optimization-${RANDOM_SUFFIX} --ids 1" \
        "Removing targets from cache optimization rule" true
fi

if resource_exists "aws events list-targets-by-rule --rule build-analytics-${RANDOM_SUFFIX}" "EventBridge rule" "build-analytics-${RANDOM_SUFFIX}"; then
    execute_command "aws events remove-targets --rule build-analytics-${RANDOM_SUFFIX} --ids 1" \
        "Removing targets from build analytics rule" true
fi

# Delete EventBridge rules
execute_command "aws events delete-rule --name cache-optimization-${RANDOM_SUFFIX}" \
    "Deleting cache optimization EventBridge rule" true

execute_command "aws events delete-rule --name build-analytics-${RANDOM_SUFFIX}" \
    "Deleting build analytics EventBridge rule" true

# Delete Lambda functions
execute_command "aws lambda delete-function --function-name ${PROJECT_NAME}-orchestrator" \
    "Deleting build orchestrator Lambda function" true

execute_command "aws lambda delete-function --function-name ${PROJECT_NAME}-cache-manager" \
    "Deleting cache manager Lambda function" true

execute_command "aws lambda delete-function --function-name ${PROJECT_NAME}-analytics" \
    "Deleting build analytics Lambda function" true

log_success "Lambda functions and EventBridge rules cleanup completed"

# Step 2: Delete CodeBuild Projects
update_progress "Deleting CodeBuild Projects"

# Stop any running builds first
for project in "${DEPENDENCY_BUILD_PROJECT}" "${MAIN_BUILD_PROJECT}" "${PARALLEL_BUILD_PROJECT}"; do
    if resource_exists "aws codebuild describe-projects --names $project" "CodeBuild project" "$project"; then
        # Get running builds and stop them
        if [[ "$DRY_RUN" == "false" ]]; then
            RUNNING_BUILDS=$(aws codebuild list-builds-for-project --project-name "$project" --query 'ids' --output text 2>/dev/null || echo "")
            if [[ -n "$RUNNING_BUILDS" ]]; then
                for build_id in $RUNNING_BUILDS; do
                    # Check if build is still running
                    BUILD_STATUS=$(aws codebuild batch-get-builds --ids "$build_id" --query 'builds[0].buildStatus' --output text 2>/dev/null || echo "")
                    if [[ "$BUILD_STATUS" == "IN_PROGRESS" ]]; then
                        log_warning "Stopping running build: $build_id"
                        aws codebuild stop-build --id "$build_id" || log_warning "Failed to stop build $build_id"
                    fi
                done
            fi
        fi
        
        execute_command "aws codebuild delete-project --name $project" \
            "Deleting CodeBuild project: $project" true
    else
        log_warning "CodeBuild project $project not found, skipping"
    fi
done

log_success "CodeBuild projects cleanup completed"

# Step 3: Delete ECR Repository and Images
update_progress "Deleting ECR Repository and Images"

if resource_exists "aws ecr describe-repositories --repository-names ${ECR_REPOSITORY}" "ECR repository" "${ECR_REPOSITORY}"; then
    # Delete all images first
    if [[ "$DRY_RUN" == "false" ]]; then
        IMAGES=$(aws ecr list-images --repository-name "${ECR_REPOSITORY}" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
        if [[ "$IMAGES" != "[]" && "$IMAGES" != "" ]]; then
            echo "$IMAGES" > images.json
            execute_command "aws ecr batch-delete-image --repository-name ${ECR_REPOSITORY} --image-ids file://images.json" \
                "Deleting all images from ECR repository" true
            rm -f images.json
        fi
    fi
    
    execute_command "aws ecr delete-repository --repository-name ${ECR_REPOSITORY} --force" \
        "Deleting ECR repository" true
else
    log_warning "ECR repository ${ECR_REPOSITORY} not found, skipping"
fi

log_success "ECR repository cleanup completed"

# Step 4: Delete S3 Buckets and Contents
update_progress "Deleting S3 Buckets and Contents"

# Delete cache bucket
if resource_exists "aws s3api head-bucket --bucket ${CACHE_BUCKET}" "S3 bucket" "${CACHE_BUCKET}"; then
    execute_command "aws s3 rm s3://${CACHE_BUCKET} --recursive" \
        "Emptying cache bucket" true
    
    execute_command "aws s3 rb s3://${CACHE_BUCKET}" \
        "Deleting cache bucket" true
else
    log_warning "S3 cache bucket ${CACHE_BUCKET} not found, skipping"
fi

# Delete artifact bucket
if resource_exists "aws s3api head-bucket --bucket ${ARTIFACT_BUCKET}" "S3 bucket" "${ARTIFACT_BUCKET}"; then
    execute_command "aws s3 rm s3://${ARTIFACT_BUCKET} --recursive" \
        "Emptying artifact bucket" true
    
    execute_command "aws s3 rb s3://${ARTIFACT_BUCKET}" \
        "Deleting artifact bucket" true
else
    log_warning "S3 artifact bucket ${ARTIFACT_BUCKET} not found, skipping"
fi

log_success "S3 buckets cleanup completed"

# Step 5: Delete CloudWatch Dashboard
update_progress "Deleting CloudWatch Dashboard"

execute_command "aws cloudwatch delete-dashboards --dashboard-names Advanced-CodeBuild-${PROJECT_NAME}" \
    "Deleting CloudWatch dashboard" true

log_success "CloudWatch dashboard cleanup completed"

# Step 6: Delete IAM Role and Policy
update_progress "Deleting IAM Role and Policy"

# Detach policy from role first
if resource_exists "aws iam get-role --role-name ${BUILD_ROLE_NAME}" "IAM role" "${BUILD_ROLE_NAME}"; then
    execute_command "aws iam detach-role-policy --role-name ${BUILD_ROLE_NAME} --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CodeBuildAdvancedPolicy-${RANDOM_SUFFIX}" \
        "Detaching policy from IAM role" true
    
    execute_command "aws iam delete-role --role-name ${BUILD_ROLE_NAME}" \
        "Deleting IAM role" true
else
    log_warning "IAM role ${BUILD_ROLE_NAME} not found, skipping"
fi

# Delete policy
execute_command "aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/CodeBuildAdvancedPolicy-${RANDOM_SUFFIX}" \
    "Deleting IAM policy" true

log_success "IAM resources cleanup completed"

# Step 7: Clean Up CloudWatch Log Groups
update_progress "Cleaning Up CloudWatch Log Groups"

# Delete CodeBuild log groups
LOG_GROUPS=(
    "/aws/codebuild/${DEPENDENCY_BUILD_PROJECT}"
    "/aws/codebuild/${MAIN_BUILD_PROJECT}"
    "/aws/codebuild/${PARALLEL_BUILD_PROJECT}"
    "/aws/lambda/${PROJECT_NAME}-orchestrator"
    "/aws/lambda/${PROJECT_NAME}-cache-manager"
    "/aws/lambda/${PROJECT_NAME}-analytics"
)

for log_group in "${LOG_GROUPS[@]}"; do
    if resource_exists "aws logs describe-log-groups --log-group-name-prefix $log_group" "CloudWatch log group" "$log_group"; then
        execute_command "aws logs delete-log-group --log-group-name $log_group" \
            "Deleting CloudWatch log group: $log_group" true
    fi
done

log_success "CloudWatch log groups cleanup completed"

# Step 8: Verify Resource Deletion
update_progress "Verifying Resource Deletion"

if [[ "$DRY_RUN" == "false" ]]; then
    log_info "Verifying that resources have been deleted..."
    
    VERIFICATION_FAILED=false
    
    # Check CodeBuild projects
    for project in "${DEPENDENCY_BUILD_PROJECT}" "${MAIN_BUILD_PROJECT}" "${PARALLEL_BUILD_PROJECT}"; do
        if aws codebuild describe-projects --names "$project" &>/dev/null; then
            log_warning "CodeBuild project $project still exists"
            VERIFICATION_FAILED=true
        fi
    done
    
    # Check Lambda functions
    for func in "${PROJECT_NAME}-orchestrator" "${PROJECT_NAME}-cache-manager" "${PROJECT_NAME}-analytics"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            log_warning "Lambda function $func still exists"
            VERIFICATION_FAILED=true
        fi
    done
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "${CACHE_BUCKET}" &>/dev/null; then
        log_warning "S3 cache bucket ${CACHE_BUCKET} still exists"
        VERIFICATION_FAILED=true
    fi
    
    if aws s3api head-bucket --bucket "${ARTIFACT_BUCKET}" &>/dev/null; then
        log_warning "S3 artifact bucket ${ARTIFACT_BUCKET} still exists"
        VERIFICATION_FAILED=true
    fi
    
    # Check ECR repository
    if aws ecr describe-repositories --repository-names "${ECR_REPOSITORY}" &>/dev/null; then
        log_warning "ECR repository ${ECR_REPOSITORY} still exists"
        VERIFICATION_FAILED=true
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${BUILD_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role ${BUILD_ROLE_NAME} still exists"
        VERIFICATION_FAILED=true
    fi
    
    if [[ "$VERIFICATION_FAILED" == "true" ]]; then
        log_warning "Some resources may still exist. This could be due to:"
        log_warning "  • AWS eventual consistency delays"
        log_warning "  • Resource dependencies"
        log_warning "  • Insufficient permissions"
        log_warning "  • Resources in use by other services"
        log_warning "Please wait a few minutes and check manually if needed."
    else
        log_success "All resources appear to have been deleted successfully"
    fi
else
    log_info "[DRY-RUN] Verification skipped in dry-run mode"
fi

# Step 9: Clean Up Local Files
update_progress "Cleaning Up Local Files"

# Remove deployment configuration file
execute_command "rm -f .deployment-config" \
    "Removing deployment configuration file" true

# Remove any temporary files that might exist
TEMP_FILES=(
    "cache-lifecycle.json"
    "ecr-lifecycle-policy.json"
    "codebuild-trust-policy.json"
    "codebuild-advanced-policy.json"
    "build-monitoring-dashboard.json"
    "buildspec-dependencies.yml"
    "buildspec-main.yml"
    "buildspec-parallel.yml"
    "build-orchestrator.py"
    "cache-manager.py"
    "build-analytics.py"
    "build-orchestrator.zip"
    "cache-manager.zip"
    "build-analytics.zip"
    "sample-app-source.tar.gz"
    "images.json"
)

for file in "${TEMP_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        execute_command "rm -f $file" \
            "Removing temporary file: $file" true
    fi
done

log_success "Local files cleanup completed"

# Final summary
echo
echo "================================================================================="
echo "                         CLEANUP COMPLETED"
echo "================================================================================="
echo

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY-RUN COMPLETED"
    echo "No actual resources were deleted. This was a simulation of what would be deleted."
    echo "Run the script without --dry-run to perform the actual cleanup."
else
    log_success "CLEANUP COMPLETED SUCCESSFULLY"
    
    echo "📋 CLEANUP SUMMARY:"
    echo "   • All CodeBuild projects deleted"
    echo "   • All Lambda functions deleted"
    echo "   • All EventBridge rules deleted"
    echo "   • ECR repository and images deleted"
    echo "   • S3 buckets and contents deleted"
    echo "   • IAM role and policy deleted"
    echo "   • CloudWatch dashboard deleted"
    echo "   • CloudWatch log groups deleted"
    echo "   • Local configuration files deleted"
    echo
    
    echo "💰 COST IMPACT:"
    echo "   • All billable resources have been removed"
    echo "   • No ongoing charges should occur from this deployment"
    echo "   • Final costs will appear in your next AWS bill"
    echo
    
    echo "📝 NOTES:"
    echo "   • Some log entries may remain in CloudWatch (minimal cost)"
    echo "   • IAM activity may appear in CloudTrail logs"
    echo "   • DNS propagation may take time for S3 bucket names to become available"
    echo
    
    if [[ "$VERIFICATION_FAILED" == "true" ]]; then
        echo "⚠️  WARNING:"
        echo "   • Some resources may still exist due to AWS delays"
        echo "   • Please verify manually in the AWS Console"
        echo "   • Re-run this script if needed after a few minutes"
        echo
    fi
fi

echo "Thank you for using the Advanced CodeBuild Pipelines solution!"
log_success "Cleanup script completed successfully!"