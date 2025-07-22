#!/bin/bash

# Destroy script for Serverless Medical Image Processing with AWS HealthImaging and Step Functions
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to load deployment info
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "deployment-info.json" ]]; then
        log_error "deployment-info.json not found"
        log_info "This file is created during deployment and contains resource identifiers"
        log_info "Without it, you'll need to manually identify and delete resources"
        
        read -p "Continue with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        
        manual_cleanup
        return
    fi
    
    # Parse deployment info
    export AWS_REGION=$(jq -r '.awsRegion' deployment-info.json)
    export AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' deployment-info.json)
    export DATASTORE_ID=$(jq -r '.resources.healthImagingDataStore.id' deployment-info.json)
    export DATASTORE_NAME=$(jq -r '.resources.healthImagingDataStore.name' deployment-info.json)
    export INPUT_BUCKET=$(jq -r '.resources.s3Buckets.inputBucket' deployment-info.json)
    export OUTPUT_BUCKET=$(jq -r '.resources.s3Buckets.outputBucket' deployment-info.json)
    export STATE_MACHINE_NAME=$(jq -r '.resources.stepFunctions.stateMachine' deployment-info.json)
    export STATE_MACHINE_ARN=$(jq -r '.resources.stepFunctions.arn' deployment-info.json)
    export LAMBDA_ROLE_NAME=$(jq -r '.resources.iamRoles.lambdaRole' deployment-info.json)
    export STEPFUNCTIONS_ROLE_NAME=$(jq -r '.resources.iamRoles.stepFunctionsRole' deployment-info.json)
    export RANDOM_SUFFIX=$(jq -r '.resourceSuffix' deployment-info.json)
    export EVENTBRIDGE_RULE=$(jq -r '.resources.eventBridge.rule' deployment-info.json)
    
    # Set Lambda function names
    export START_IMPORT_FUNCTION="StartDicomImport-${RANDOM_SUFFIX}"
    export PROCESS_METADATA_FUNCTION="ProcessDicomMetadata-${RANDOM_SUFFIX}"
    export ANALYZE_IMAGE_FUNCTION="AnalyzeMedicalImage-${RANDOM_SUFFIX}"
    
    log_success "Deployment information loaded"
    log_info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function for manual cleanup when deployment-info.json is missing
manual_cleanup() {
    log_warning "Starting manual cleanup process..."
    log_info "You will need to manually identify resources created by the deployment"
    
    echo ""
    echo "Please manually delete the following types of resources:"
    echo "1. HealthImaging data stores (check AWS HealthImaging console)"
    echo "2. Lambda functions (names starting with StartDicomImport-, ProcessDicomMetadata-, AnalyzeMedicalImage-)"
    echo "3. Step Functions state machines (names starting with dicom-processor-)"
    echo "4. S3 buckets (names starting with dicom-input- and dicom-output-)"
    echo "5. IAM roles (names starting with lambda-medical-imaging- and StepFunctions-)"
    echo "6. EventBridge rules (names starting with DicomImportCompleted-)"
    echo "7. CloudWatch log groups (names starting with /aws/stepfunctions/dicom-processor-)"
    echo ""
    
    read -p "Press Enter to continue after manual cleanup..."
    exit 0
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will delete ALL resources created by the medical imaging pipeline deployment"
    echo ""
    echo "Resources to be deleted:"
    echo "• HealthImaging Data Store: ${DATASTORE_ID}"
    echo "• S3 Buckets: ${INPUT_BUCKET}, ${OUTPUT_BUCKET}"
    echo "• Lambda Functions: ${START_IMPORT_FUNCTION}, ${PROCESS_METADATA_FUNCTION}, ${ANALYZE_IMAGE_FUNCTION}"
    echo "• Step Functions State Machine: ${STATE_MACHINE_NAME}"
    echo "• IAM Roles: ${LAMBDA_ROLE_NAME}, ${STEPFUNCTIONS_ROLE_NAME}"
    echo "• EventBridge Rule: ${EVENTBRIDGE_RULE}"
    echo ""
    
    log_warning "This action cannot be undone!"
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    if [[ ! "$REPLY" == "yes" ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi
}

# Function to delete S3 bucket contents and buckets
delete_s3_resources() {
    log_info "Deleting S3 resources..."
    
    # Empty and delete input bucket
    if aws s3 ls "s3://${INPUT_BUCKET}" >/dev/null 2>&1; then
        log_info "Emptying input bucket: ${INPUT_BUCKET}"
        aws s3 rm "s3://${INPUT_BUCKET}" --recursive >/dev/null 2>&1 || true
        
        log_info "Deleting input bucket: ${INPUT_BUCKET}"
        aws s3 rb "s3://${INPUT_BUCKET}" >/dev/null 2>&1 || true
        log_success "Input bucket deleted"
    else
        log_warning "Input bucket ${INPUT_BUCKET} not found or already deleted"
    fi
    
    # Empty and delete output bucket
    if aws s3 ls "s3://${OUTPUT_BUCKET}" >/dev/null 2>&1; then
        log_info "Emptying output bucket: ${OUTPUT_BUCKET}"
        aws s3 rm "s3://${OUTPUT_BUCKET}" --recursive >/dev/null 2>&1 || true
        
        log_info "Deleting output bucket: ${OUTPUT_BUCKET}"
        aws s3 rb "s3://${OUTPUT_BUCKET}" >/dev/null 2>&1 || true
        log_success "Output bucket deleted"
    else
        log_warning "Output bucket ${OUTPUT_BUCKET} not found or already deleted"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    # Delete start import function
    if aws lambda get-function --function-name "${START_IMPORT_FUNCTION}" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "${START_IMPORT_FUNCTION}" >/dev/null 2>&1
        log_success "Deleted Lambda function: ${START_IMPORT_FUNCTION}"
    else
        log_warning "Lambda function ${START_IMPORT_FUNCTION} not found or already deleted"
    fi
    
    # Delete metadata processing function
    if aws lambda get-function --function-name "${PROCESS_METADATA_FUNCTION}" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "${PROCESS_METADATA_FUNCTION}" >/dev/null 2>&1
        log_success "Deleted Lambda function: ${PROCESS_METADATA_FUNCTION}"
    else
        log_warning "Lambda function ${PROCESS_METADATA_FUNCTION} not found or already deleted"
    fi
    
    # Delete image analysis function
    if aws lambda get-function --function-name "${ANALYZE_IMAGE_FUNCTION}" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "${ANALYZE_IMAGE_FUNCTION}" >/dev/null 2>&1
        log_success "Deleted Lambda function: ${ANALYZE_IMAGE_FUNCTION}"
    else
        log_warning "Lambda function ${ANALYZE_IMAGE_FUNCTION} not found or already deleted"
    fi
}

# Function to delete EventBridge resources
delete_eventbridge_resources() {
    log_info "Deleting EventBridge resources..."
    
    # Remove targets from the rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE}" >/dev/null 2>&1; then
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE}" \
            --ids "1" >/dev/null 2>&1 || true
        
        # Delete the rule
        aws events delete-rule --name "${EVENTBRIDGE_RULE}" >/dev/null 2>&1
        log_success "Deleted EventBridge rule: ${EVENTBRIDGE_RULE}"
    else
        log_warning "EventBridge rule ${EVENTBRIDGE_RULE} not found or already deleted"
    fi
}

# Function to delete Step Functions state machine
delete_step_functions() {
    log_info "Deleting Step Functions state machine..."
    
    if aws stepfunctions describe-state-machine --state-machine-arn "${STATE_MACHINE_ARN}" >/dev/null 2>&1; then
        aws stepfunctions delete-state-machine \
            --state-machine-arn "${STATE_MACHINE_ARN}" >/dev/null 2>&1
        log_success "Deleted Step Functions state machine: ${STATE_MACHINE_NAME}"
    else
        log_warning "Step Functions state machine ${STATE_MACHINE_NAME} not found or already deleted"
    fi
    
    # Delete CloudWatch log group
    LOG_GROUP_NAME="/aws/stepfunctions/${STATE_MACHINE_NAME}"
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[0]' >/dev/null 2>&1; then
        aws logs delete-log-group --log-group-name "${LOG_GROUP_NAME}" >/dev/null 2>&1 || true
        log_success "Deleted CloudWatch log group: ${LOG_GROUP_NAME}"
    fi
}

# Function to delete HealthImaging data store
delete_healthimaging_datastore() {
    log_info "Deleting HealthImaging data store..."
    
    if aws medical-imaging get-datastore --datastore-id "${DATASTORE_ID}" >/dev/null 2>&1; then
        log_info "Initiating data store deletion: ${DATASTORE_ID}"
        aws medical-imaging delete-datastore \
            --datastore-id "${DATASTORE_ID}" >/dev/null 2>&1
        
        log_warning "HealthImaging data store deletion initiated"
        log_info "Note: Data store deletion can take several minutes to complete"
        log_info "You can check status in the AWS HealthImaging console"
    else
        log_warning "HealthImaging data store ${DATASTORE_ID} not found or already deleted"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    # Delete Lambda execution role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            >/dev/null 2>&1 || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-name HealthImagingAccess \
            >/dev/null 2>&1 || true
        
        # Delete role
        aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1
        log_success "Deleted IAM role: ${LAMBDA_ROLE_NAME}"
    else
        log_warning "IAM role ${LAMBDA_ROLE_NAME} not found or already deleted"
    fi
    
    # Delete Step Functions execution role
    if aws iam get-role --role-name "${STEPFUNCTIONS_ROLE_NAME}" >/dev/null 2>&1; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${STEPFUNCTIONS_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaRole \
            >/dev/null 2>&1 || true
        
        # Delete role
        aws iam delete-role --role-name "${STEPFUNCTIONS_ROLE_NAME}" >/dev/null 2>&1
        log_success "Deleted IAM role: ${STEPFUNCTIONS_ROLE_NAME}"
    else
        log_warning "IAM role ${STEPFUNCTIONS_ROLE_NAME} not found or already deleted"
    fi
}

# Function to check for remaining resources
check_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    local remaining_resources=0
    
    # Check for Lambda functions
    if aws lambda list-functions --query "Functions[?contains(FunctionName, '${RANDOM_SUFFIX}')]" --output text | grep -q .; then
        log_warning "Some Lambda functions with suffix '${RANDOM_SUFFIX}' still exist"
        remaining_resources=1
    fi
    
    # Check for Step Functions
    if aws stepfunctions list-state-machines --query "stateMachines[?contains(name, '${RANDOM_SUFFIX}')]" --output text | grep -q .; then
        log_warning "Some Step Functions state machines with suffix '${RANDOM_SUFFIX}' still exist"
        remaining_resources=1
    fi
    
    # Check for IAM roles
    if aws iam list-roles --query "Roles[?contains(RoleName, '${RANDOM_SUFFIX}')]" --output text | grep -q .; then
        log_warning "Some IAM roles with suffix '${RANDOM_SUFFIX}' still exist"
        remaining_resources=1
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "No remaining resources detected"
    else
        log_warning "Some resources may still exist. Check the AWS console for manual cleanup"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "deployment-info.json" ]]; then
        rm -f deployment-info.json
        log_success "Removed deployment-info.json"
    fi
    
    # Remove any remaining temporary files
    rm -f lambda-trust-policy.json 2>/dev/null || true
    rm -f healthimaging-policy.json 2>/dev/null || true
    rm -f stepfunctions-trust-policy.json 2>/dev/null || true
    rm -f state-machine.json 2>/dev/null || true
    rm -f s3-notification.json 2>/dev/null || true
    rm -rf lambda-functions 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to display destruction summary
display_summary() {
    log_success "🧹 Cleanup completed!"
    echo ""
    echo "=== DESTRUCTION SUMMARY ==="
    echo "All medical imaging pipeline resources have been deleted or deletion initiated."
    echo ""
    echo "=== DELETED RESOURCES ==="
    echo "• S3 Buckets: ${INPUT_BUCKET}, ${OUTPUT_BUCKET}"
    echo "• Lambda Functions: 3 functions deleted"
    echo "• Step Functions State Machine: ${STATE_MACHINE_NAME}"
    echo "• EventBridge Rules: ${EVENTBRIDGE_RULE}"
    echo "• IAM Roles: ${LAMBDA_ROLE_NAME}, ${STEPFUNCTIONS_ROLE_NAME}"
    echo "• HealthImaging Data Store: ${DATASTORE_ID} (deletion initiated)"
    echo ""
    echo "=== IMPORTANT NOTES ==="
    echo "• HealthImaging data store deletion can take several minutes"
    echo "• Check the AWS HealthImaging console to confirm deletion completion"
    echo "• CloudWatch logs are retained with default retention policies"
    echo "• No additional charges will be incurred for deleted resources"
    echo ""
    log_info "Cleanup process completed successfully"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command_exists jq; then
        log_error "jq is not installed (required for JSON processing)"
        log_info "Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
        exit 1
    fi
    
    # Check AWS configuration
    check_aws_config
    
    log_success "Prerequisites check completed"
}

# Main destruction function
main() {
    echo "========================================"
    echo "   Medical Image Processing Cleanup"
    echo "========================================"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment information
    load_deployment_info
    
    # Confirm destruction
    confirm_destruction
    
    # Start destruction process
    log_info "Starting resource deletion..."
    echo ""
    
    # Delete resources in reverse order of creation
    delete_s3_resources
    delete_lambda_functions
    delete_eventbridge_resources
    delete_step_functions
    delete_healthimaging_datastore
    delete_iam_roles
    
    # Check for remaining resources
    check_remaining_resources
    
    # Clean up local files
    cleanup_local_files
    
    # Display summary
    display_summary
}

# Error handling
trap 'log_error "Cleanup failed. Some resources may still exist. Check AWS console for manual cleanup."; exit 1' ERR

# Run main function
main "$@"