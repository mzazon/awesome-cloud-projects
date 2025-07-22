#!/bin/bash

# Data Quality Pipelines with DataBrew
# Cleanup/Destroy Script
# 
# This script safely removes all AWS resources created by the deployment script.
# It handles dependencies and provides safeguards against accidental deletion.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY RUN mode - no resources will be deleted"
fi

# Force mode to skip confirmations
FORCE_MODE=${FORCE_MODE:-false}

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    info "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY RUN] Would execute: $cmd"
        return 0
    else
        if eval "$cmd" 2>/dev/null; then
            log "✅ $description completed successfully"
            return 0
        else
            if [ "$ignore_errors" = "true" ]; then
                warn "⚠️  $description failed (ignored)"
                return 0
            else
                error "❌ Failed to execute: $description"
                return 1
            fi
        fi
    fi
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Check if deployment-info.json exists
    if [ ! -f "deployment-info.json" ]; then
        warn "deployment-info.json not found. Manual resource specification required."
        
        # Prompt for manual input
        if [ "$FORCE_MODE" = "false" ]; then
            read -p "Enter resource suffix (from deployment): " RANDOM_SUFFIX
            
            if [ -z "$RANDOM_SUFFIX" ]; then
                error "Resource suffix is required for cleanup"
            fi
        else
            error "deployment-info.json not found and running in force mode. Cannot proceed."
        fi
    else
        # Load from deployment info file
        if command -v jq &> /dev/null; then
            RANDOM_SUFFIX=$(jq -r '.resourceSuffix' deployment-info.json)
            AWS_REGION=$(jq -r '.awsRegion' deployment-info.json)
            AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' deployment-info.json)
            BUCKET_NAME=$(jq -r '.resources.s3Bucket' deployment-info.json)
            DATASET_NAME=$(jq -r '.resources.datasetName' deployment-info.json)
            RULESET_NAME=$(jq -r '.resources.rulesetName' deployment-info.json)
            PROFILE_JOB_NAME=$(jq -r '.resources.profileJobName' deployment-info.json)
        else
            # Parse JSON without jq (basic parsing)
            RANDOM_SUFFIX=$(grep -o '"resourceSuffix": "[^"]*"' deployment-info.json | cut -d'"' -f4)
            AWS_REGION=$(grep -o '"awsRegion": "[^"]*"' deployment-info.json | cut -d'"' -f4)
            AWS_ACCOUNT_ID=$(grep -o '"awsAccountId": "[^"]*"' deployment-info.json | cut -d'"' -f4)
            BUCKET_NAME=$(grep -o '"s3Bucket": "[^"]*"' deployment-info.json | cut -d'"' -f4)
            DATASET_NAME=$(grep -o '"datasetName": "[^"]*"' deployment-info.json | cut -d'"' -f4)
            RULESET_NAME=$(grep -o '"rulesetName": "[^"]*"' deployment-info.json | cut -d'"' -f4)
            PROFILE_JOB_NAME=$(grep -o '"profileJobName": "[^"]*"' deployment-info.json | cut -d'"' -f4)
        fi
    fi
    
    # Set defaults if not loaded from file
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    export BUCKET_NAME=${BUCKET_NAME:-"data-quality-pipeline-${RANDOM_SUFFIX}"}
    export DATASET_NAME=${DATASET_NAME:-"customer-data-${RANDOM_SUFFIX}"}
    export RULESET_NAME=${RULESET_NAME:-"customer-quality-rules-${RANDOM_SUFFIX}"}
    export PROFILE_JOB_NAME=${PROFILE_JOB_NAME:-"quality-assessment-job-${RANDOM_SUFFIX}"}
    
    info "Resource suffix: $RANDOM_SUFFIX"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    
    log "✅ Deployment information loaded"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Verify we can access the expected region
    if [ -n "$AWS_REGION" ]; then
        info "Using AWS region: $AWS_REGION"
    else
        error "AWS region not configured"
    fi
    
    log "✅ Prerequisites check passed"
}

# Stop running DataBrew jobs
stop_databrew_jobs() {
    log "Stopping any running DataBrew jobs..."
    
    # Check if profile job exists and stop any running executions
    if [ "$DRY_RUN" = "false" ]; then
        # List running job runs
        RUNNING_JOBS=$(aws databrew list-job-runs \
            --name "${PROFILE_JOB_NAME}" \
            --query 'JobRuns[?State==`RUNNING`].RunId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$RUNNING_JOBS" ]; then
            warn "Found running job executions. Stopping them..."
            for RUN_ID in $RUNNING_JOBS; do
                execute_cmd "aws databrew stop-job-run --name ${PROFILE_JOB_NAME} --run-id ${RUN_ID}" \
                    "Stopping job run: $RUN_ID" true
            done
            
            # Wait for jobs to stop
            info "Waiting for jobs to stop..."
            sleep 30
        fi
    fi
    
    log "✅ DataBrew jobs stopped"
}

# Delete DataBrew resources
delete_databrew_resources() {
    log "Deleting DataBrew resources..."
    
    # Delete profile job
    execute_cmd "aws databrew delete-job --name ${PROFILE_JOB_NAME}" \
        "Deleting profile job: ${PROFILE_JOB_NAME}" true
    
    # Delete ruleset
    execute_cmd "aws databrew delete-ruleset --name ${RULESET_NAME}" \
        "Deleting ruleset: ${RULESET_NAME}" true
    
    # Delete dataset
    execute_cmd "aws databrew delete-dataset --name ${DATASET_NAME}" \
        "Deleting dataset: ${DATASET_NAME}" true
    
    log "✅ DataBrew resources deleted"
}

# Delete EventBridge resources
delete_eventbridge_resources() {
    log "Deleting EventBridge resources..."
    
    # Remove EventBridge rule targets
    execute_cmd "aws events remove-targets \
        --rule DataBrewValidationRule-${RANDOM_SUFFIX} \
        --ids \"1\"" \
        "Removing EventBridge rule targets" true
    
    # Delete EventBridge rule
    execute_cmd "aws events delete-rule \
        --name DataBrewValidationRule-${RANDOM_SUFFIX}" \
        "Deleting EventBridge rule: DataBrewValidationRule-${RANDOM_SUFFIX}" true
    
    log "✅ EventBridge resources deleted"
}

# Delete Lambda resources
delete_lambda_resources() {
    log "Deleting Lambda resources..."
    
    # Remove Lambda permission for EventBridge
    execute_cmd "aws lambda remove-permission \
        --function-name DataQualityProcessor-${RANDOM_SUFFIX} \
        --statement-id databrew-eventbridge-permission" \
        "Removing Lambda EventBridge permission" true
    
    # Delete Lambda function
    execute_cmd "aws lambda delete-function \
        --function-name DataQualityProcessor-${RANDOM_SUFFIX}" \
        "Deleting Lambda function: DataQualityProcessor-${RANDOM_SUFFIX}" true
    
    log "✅ Lambda resources deleted"
}

# Delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # DataBrew service role
    execute_cmd "aws iam detach-role-policy \
        --role-name DataBrewServiceRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueDataBrewServiceRole" \
        "Detaching DataBrew service policy" true
    
    execute_cmd "aws iam delete-role \
        --role-name DataBrewServiceRole-${RANDOM_SUFFIX}" \
        "Deleting DataBrew service role: DataBrewServiceRole-${RANDOM_SUFFIX}" true
    
    # Lambda execution role
    execute_cmd "aws iam delete-role-policy \
        --role-name DataQualityLambdaRole-${RANDOM_SUFFIX} \
        --policy-name DataQualityPermissions" \
        "Deleting Lambda inline policy" true
    
    execute_cmd "aws iam detach-role-policy \
        --role-name DataQualityLambdaRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Detaching Lambda basic execution policy" true
    
    execute_cmd "aws iam delete-role \
        --role-name DataQualityLambdaRole-${RANDOM_SUFFIX}" \
        "Deleting Lambda execution role: DataQualityLambdaRole-${RANDOM_SUFFIX}" true
    
    log "✅ IAM resources deleted"
}

# Delete S3 resources
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    # Check if bucket exists
    if [ "$DRY_RUN" = "false" ]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
            # Get bucket size for confirmation
            BUCKET_SIZE=$(aws s3 ls s3://${BUCKET_NAME} --recursive --summarize | grep "Total Size" | cut -d: -f2 | tr -d ' ' 2>/dev/null || echo "unknown")
            
            if [ "$FORCE_MODE" = "false" ]; then
                warn "S3 bucket '${BUCKET_NAME}' contains data (Size: ${BUCKET_SIZE})"
                read -p "Are you sure you want to delete all contents? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    info "Skipping S3 bucket deletion"
                    return 0
                fi
            fi
            
            # Empty bucket first
            execute_cmd "aws s3 rm s3://${BUCKET_NAME} --recursive" \
                "Emptying S3 bucket: ${BUCKET_NAME}" true
            
            # Delete bucket
            execute_cmd "aws s3 rb s3://${BUCKET_NAME}" \
                "Deleting S3 bucket: ${BUCKET_NAME}" true
        else
            info "S3 bucket '${BUCKET_NAME}' does not exist or already deleted"
        fi
    fi
    
    log "✅ S3 resources deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "deployment-info.json" ]; then
        if [ "$FORCE_MODE" = "false" ]; then
            read -p "Delete deployment-info.json? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f deployment-info.json
                info "Deleted deployment-info.json"
            fi
        else
            rm -f deployment-info.json
            info "Deleted deployment-info.json"
        fi
    fi
    
    # Remove any remaining temporary files
    if [ "$DRY_RUN" = "false" ]; then
        rm -f customer-data.csv
        rm -f lambda-function.zip
        rm -f lambda-function.py
        rm -f databrew-trust-policy.json
        rm -f lambda-trust-policy.json
        rm -f lambda-permissions-policy.json
        rm -f ruleset-rules.json
        rm -f bad-customer-data.csv
        rm -rf reports/
    fi
    
    log "✅ Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    if [ "$DRY_RUN" = "false" ]; then
        # Check DataBrew resources
        if aws databrew describe-job --name "${PROFILE_JOB_NAME}" &>/dev/null; then
            warn "DataBrew job still exists: ${PROFILE_JOB_NAME}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        if aws databrew describe-ruleset --name "${RULESET_NAME}" &>/dev/null; then
            warn "DataBrew ruleset still exists: ${RULESET_NAME}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        if aws databrew describe-dataset --name "${DATASET_NAME}" &>/dev/null; then
            warn "DataBrew dataset still exists: ${DATASET_NAME}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        # Check Lambda function
        if aws lambda get-function --function-name "DataQualityProcessor-${RANDOM_SUFFIX}" &>/dev/null; then
            warn "Lambda function still exists: DataQualityProcessor-${RANDOM_SUFFIX}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        # Check EventBridge rule
        if aws events describe-rule --name "DataBrewValidationRule-${RANDOM_SUFFIX}" &>/dev/null; then
            warn "EventBridge rule still exists: DataBrewValidationRule-${RANDOM_SUFFIX}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        # Check IAM roles
        if aws iam get-role --role-name "DataBrewServiceRole-${RANDOM_SUFFIX}" &>/dev/null; then
            warn "IAM role still exists: DataBrewServiceRole-${RANDOM_SUFFIX}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        if aws iam get-role --role-name "DataQualityLambdaRole-${RANDOM_SUFFIX}" &>/dev/null; then
            warn "IAM role still exists: DataQualityLambdaRole-${RANDOM_SUFFIX}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        # Check S3 bucket
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
            warn "S3 bucket still exists: ${BUCKET_NAME}"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log "✅ Cleanup verification passed - all resources removed"
    else
        warn "⚠️  Cleanup verification found ${cleanup_errors} remaining resources"
        info "You may need to manually delete these resources or run the script again"
    fi
}

# Main cleanup function
main() {
    log "Starting AWS Data Quality Pipeline cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force      Skip confirmation prompts"
                echo "  --dry-run    Show what would be deleted without actually deleting"
                echo "  --help       Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Load deployment information
    load_deployment_info
    
    # Check prerequisites
    check_prerequisites
    
    # Show warning and get confirmation
    if [ "$FORCE_MODE" = "false" ] && [ "$DRY_RUN" = "false" ]; then
        echo
        warn "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
        echo
        info "This script will permanently delete the following resources:"
        info "- S3 bucket: ${BUCKET_NAME} (and all contents)"
        info "- DataBrew dataset: ${DATASET_NAME}"
        info "- DataBrew ruleset: ${RULESET_NAME}"
        info "- DataBrew profile job: ${PROFILE_JOB_NAME}"
        info "- Lambda function: DataQualityProcessor-${RANDOM_SUFFIX}"
        info "- EventBridge rule: DataBrewValidationRule-${RANDOM_SUFFIX}"
        info "- IAM roles: DataBrewServiceRole-${RANDOM_SUFFIX}, DataQualityLambdaRole-${RANDOM_SUFFIX}"
        echo
        warn "This action cannot be undone!"
        echo
        
        read -p "Are you absolutely sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
        
        # Double confirmation for S3 bucket
        read -p "Confirm deletion of S3 bucket and all data? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Create cleanup log file
    CLEANUP_LOG="cleanup-$(date +%Y%m%d-%H%M%S).log"
    if [ "$DRY_RUN" = "false" ]; then
        exec > >(tee -a "$CLEANUP_LOG") 2>&1
        info "Cleanup log: $CLEANUP_LOG"
    fi
    
    # Execute cleanup steps in reverse order of creation
    stop_databrew_jobs
    delete_databrew_resources
    delete_eventbridge_resources
    delete_lambda_resources
    delete_iam_resources
    delete_s3_resources
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    log "🗑️  Cleanup completed!"
    
    if [ "$DRY_RUN" = "false" ]; then
        echo
        info "All AWS resources have been deleted"
        info "Cleanup log saved to: $CLEANUP_LOG"
        echo
        info "Cost note: You will no longer be charged for these resources"
        info "Check your AWS billing dashboard to confirm all resources are removed"
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist. Check AWS console and re-run script if needed."' INT TERM

# Run main function
main "$@"