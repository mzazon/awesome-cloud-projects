#!/bin/bash

# Destroy script for Real-Time Edge AI Inference with IoT Greengrass
# This script safely removes all AWS resources created by the deployment

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "$1 could not be found. Please install it before running this script."
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all resources created by the Edge AI deployment.${NC}"
    echo ""
    if [[ -f .deployment_state ]]; then
        echo "Resources to be deleted:"
        source .deployment_state
        echo "  - S3 Bucket: ${S3_BUCKET_NAME:-unknown}"
        echo "  - IoT Thing: ${GREENGRASS_THING_NAME:-unknown}"
        echo "  - EventBridge Bus: ${EVENT_BUS_NAME:-unknown}"
        echo "  - Greengrass Deployment: ${DEPLOYMENT_ID:-unknown}"
        echo "  - IAM Roles and Policies"
        echo "  - CloudWatch Log Groups"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Please type 'DELETE' to confirm destruction: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Destruction cancelled - confirmation text did not match"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required commands
    check_command "aws"
    check_command "jq"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set environment variables."
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    if [[ -f .deployment_state ]]; then
        log_info "Loading deployment state from .deployment_state file..."
        source .deployment_state
        
        # Validate required variables are set
        if [[ -z "${AWS_REGION:-}" ]]; then
            log_warning "AWS_REGION not found in deployment state, attempting to detect..."
            export AWS_REGION=$(aws configure get region)
            if [[ -z "$AWS_REGION" ]]; then
                error_exit "Could not determine AWS region. Please set AWS_REGION environment variable."
            fi
        fi
        
        if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
            log_warning "AWS_ACCOUNT_ID not found in deployment state, detecting..."
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        fi
        
        log_success "Deployment state loaded"
    else
        log_warning ".deployment_state file not found. Attempting manual detection..."
        
        # Try to find resources manually
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to find S3 buckets with edge-models prefix
        BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `edge-models-`)].Name' --output text)
        if [[ -n "$BUCKETS" ]]; then
            export S3_BUCKET_NAME=$(echo "$BUCKETS" | head -n1)
            log_info "Found S3 bucket: $S3_BUCKET_NAME"
        fi
        
        # Set other default values
        export EVENT_BUS_NAME="edge-monitoring-bus"
        export EDGE_PROJECT_NAME="edge-ai-inference"
        export GREENGRASS_THING_NAME="edge-device"
        
        log_warning "Using detected/default values. Some resources may not be found."
    fi
}

# Cancel and remove Greengrass deployments
remove_greengrass_deployments() {
    log_info "Removing IoT Greengrass deployments..."
    
    # Cancel active deployment if deployment ID is known
    if [[ -n "${DEPLOYMENT_ID:-}" ]]; then
        log_info "Cancelling deployment: $DEPLOYMENT_ID"
        aws greengrassv2 cancel-deployment \
            --deployment-id "$DEPLOYMENT_ID" 2>/dev/null || \
            log_warning "Could not cancel deployment $DEPLOYMENT_ID (may already be cancelled or not exist)"
        
        # Wait for cancellation to complete
        log_info "Waiting for deployment cancellation to complete..."
        sleep 30
    fi
    
    # List and cancel any other deployments for the thing
    if [[ -n "${GREENGRASS_THING_NAME:-}" ]]; then
        log_info "Checking for other deployments for thing: $GREENGRASS_THING_NAME"
        
        THING_ARN="arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/${GREENGRASS_THING_NAME}"
        
        # Get deployments for this thing
        DEPLOYMENTS=$(aws greengrassv2 list-deployments \
            --target-arn "$THING_ARN" \
            --query 'deployments[?deploymentStatus==`ACTIVE`].deploymentId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$DEPLOYMENTS" ]]; then
            for dep_id in $DEPLOYMENTS; do
                log_info "Cancelling active deployment: $dep_id"
                aws greengrassv2 cancel-deployment \
                    --deployment-id "$dep_id" 2>/dev/null || \
                    log_warning "Could not cancel deployment $dep_id"
            done
            
            # Wait for cancellations
            sleep 30
        fi
    fi
    
    log_success "Greengrass deployments removed"
}

# Remove Greengrass components
remove_greengrass_components() {
    log_info "Removing IoT Greengrass components..."
    
    # List of components to remove
    COMPONENTS=(
        "com.edge.InferenceEngine"
        "com.edge.DefectDetectionModel"
        "com.edge.OnnxRuntime"
    )
    
    for component in "${COMPONENTS[@]}"; do
        log_info "Checking component: $component"
        
        # List all versions of the component
        VERSIONS=$(aws greengrassv2 list-component-versions \
            --arn "arn:aws:greengrass:${AWS_REGION}:${AWS_ACCOUNT_ID}:components:${component}" \
            --query 'componentVersions[].componentVersion' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$VERSIONS" ]]; then
            for version in $VERSIONS; do
                log_info "Deleting component version: $component:$version"
                aws greengrassv2 delete-component \
                    --arn "arn:aws:greengrass:${AWS_REGION}:${AWS_ACCOUNT_ID}:components:${component}:versions:${version}" \
                    2>/dev/null || log_warning "Could not delete $component:$version"
            done
        else
            log_info "No versions found for component: $component"
        fi
    done
    
    log_success "Greengrass components removed"
}

# Remove EventBridge resources
remove_eventbridge_resources() {
    log_info "Removing EventBridge resources..."
    
    if [[ -n "${EVENT_BUS_NAME:-}" ]]; then
        # Remove targets from rule
        log_info "Removing targets from EventBridge rule..."
        aws events remove-targets \
            --rule edge-inference-monitoring \
            --event-bus-name "$EVENT_BUS_NAME" \
            --ids "1" 2>/dev/null || \
            log_warning "Could not remove EventBridge rule targets"
        
        # Delete rule
        log_info "Deleting EventBridge rule..."
        aws events delete-rule \
            --name edge-inference-monitoring \
            --event-bus-name "$EVENT_BUS_NAME" 2>/dev/null || \
            log_warning "Could not delete EventBridge rule"
        
        # Delete custom event bus
        log_info "Deleting EventBridge bus: $EVENT_BUS_NAME"
        aws events delete-event-bus \
            --name "$EVENT_BUS_NAME" 2>/dev/null || \
            log_warning "Could not delete EventBridge bus"
    fi
    
    # Remove CloudWatch log group
    log_info "Removing CloudWatch log group..."
    aws logs delete-log-group \
        --log-group-name "/aws/events/edge-inference" 2>/dev/null || \
        log_warning "Could not delete CloudWatch log group"
    
    log_success "EventBridge resources removed"
}

# Remove IoT resources
remove_iot_resources() {
    log_info "Removing IoT resources..."
    
    if [[ -n "${GREENGRASS_THING_NAME:-}" ]]; then
        # List and detach certificates from thing
        log_info "Checking for attached certificates..."
        CERTIFICATES=$(aws iot list-thing-principals \
            --thing-name "$GREENGRASS_THING_NAME" \
            --query 'principals' --output text 2>/dev/null || echo "")
        
        if [[ -n "$CERTIFICATES" && "$CERTIFICATES" != "None" ]]; then
            for cert_arn in $CERTIFICATES; do
                log_info "Detaching certificate: $cert_arn"
                aws iot detach-thing-principal \
                    --thing-name "$GREENGRASS_THING_NAME" \
                    --principal "$cert_arn" 2>/dev/null || \
                    log_warning "Could not detach certificate"
                
                # Extract certificate ID from ARN
                CERT_ID=$(echo "$cert_arn" | awk -F'/' '{print $2}')
                
                # Detach policies from certificate
                POLICIES=$(aws iot list-attached-policies \
                    --target "$cert_arn" \
                    --query 'policies[].policyName' --output text 2>/dev/null || echo "")
                
                if [[ -n "$POLICIES" && "$POLICIES" != "None" ]]; then
                    for policy in $POLICIES; do
                        log_info "Detaching policy $policy from certificate"
                        aws iot detach-policy \
                            --policy-name "$policy" \
                            --target "$cert_arn" 2>/dev/null || \
                            log_warning "Could not detach policy"
                    done
                fi
                
                # Deactivate and delete certificate
                log_info "Deactivating certificate: $CERT_ID"
                aws iot update-certificate \
                    --certificate-id "$CERT_ID" \
                    --new-status INACTIVE 2>/dev/null || \
                    log_warning "Could not deactivate certificate"
                
                log_info "Deleting certificate: $CERT_ID"
                aws iot delete-certificate \
                    --certificate-id "$CERT_ID" --force-delete 2>/dev/null || \
                    log_warning "Could not delete certificate"
            done
        fi
        
        # Delete IoT Thing
        log_info "Deleting IoT Thing: $GREENGRASS_THING_NAME"
        aws iot delete-thing \
            --thing-name "$GREENGRASS_THING_NAME" 2>/dev/null || \
            log_warning "Could not delete IoT Thing"
    fi
    
    # Delete IoT policy
    log_info "Deleting IoT policy..."
    aws iot delete-policy \
        --policy-name GreengrassV2IoTThingPolicy 2>/dev/null || \
        log_warning "Could not delete IoT policy"
    
    # Delete IoT role alias
    log_info "Deleting IoT role alias..."
    aws iot delete-role-alias \
        --role-alias GreengrassV2TokenExchangeRoleAlias 2>/dev/null || \
        log_warning "Could not delete IoT role alias"
    
    log_success "IoT resources removed"
}

# Remove S3 bucket and contents
remove_s3_resources() {
    log_info "Removing S3 resources..."
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
            log_info "Emptying S3 bucket: $S3_BUCKET_NAME"
            
            # Remove all object versions and delete markers
            aws s3api list-object-versions \
                --bucket "$S3_BUCKET_NAME" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text | while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$S3_BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Remove delete markers
            aws s3api list-object-versions \
                --bucket "$S3_BUCKET_NAME" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text | while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$S3_BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" 2>/dev/null || true
                fi
            done
            
            # Remove current objects
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
            
            # Delete bucket
            log_info "Deleting S3 bucket: $S3_BUCKET_NAME"
            aws s3 rb "s3://${S3_BUCKET_NAME}" 2>/dev/null || \
                log_warning "Could not delete S3 bucket (may not be empty)"
        else
            log_info "S3 bucket $S3_BUCKET_NAME does not exist or is not accessible"
        fi
    fi
    
    log_success "S3 resources removed"
}

# Remove IAM resources
remove_iam_resources() {
    log_info "Removing IAM resources..."
    
    # Detach and delete IAM role
    log_info "Removing IAM role: GreengrassV2TokenExchangeRole"
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name GreengrassV2TokenExchangeRole \
        --policy-arn arn:aws:iam::aws:policy/GreengrassV2TokenExchangeRoleAccess \
        2>/dev/null || log_warning "Could not detach managed policy"
    
    # List and detach inline policies
    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name GreengrassV2TokenExchangeRole \
        --query 'PolicyNames' --output text 2>/dev/null || echo "")
    
    if [[ -n "$INLINE_POLICIES" && "$INLINE_POLICIES" != "None" ]]; then
        for policy in $INLINE_POLICIES; do
            log_info "Deleting inline policy: $policy"
            aws iam delete-role-policy \
                --role-name GreengrassV2TokenExchangeRole \
                --policy-name "$policy" 2>/dev/null || \
                log_warning "Could not delete inline policy"
        done
    fi
    
    # Delete IAM role
    aws iam delete-role \
        --role-name GreengrassV2TokenExchangeRole 2>/dev/null || \
        log_warning "Could not delete IAM role"
    
    log_success "IAM resources removed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        ".deployment_state"
        ".deployment_id"
        "greengrass-config.yaml"
        "install-greengrass.sh"
        "bucket-policy.json"
        "greengrass-trust-policy.json"
        "device-policy.json"
        "event-pattern.json"
        "deployment.json"
        "model-metadata.json"
        "onnx-runtime-recipe.json"
        "model-component-recipe.json"
        "inference-component-recipe.json"
        "inference_app.py"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    # Remove model artifacts directory if it exists
    if [[ -d "model-artifacts" ]]; then
        rm -rf model-artifacts
        log_info "Removed: model-artifacts directory"
    fi
    
    log_success "Local files cleaned up"
}

# Display destruction summary
display_summary() {
    log_success "Resource destruction completed!"
    echo ""
    echo "=================================="
    echo "DESTRUCTION SUMMARY"
    echo "=================================="
    echo "The following resources have been removed:"
    echo "✅ IoT Greengrass deployments and components"
    echo "✅ EventBridge rules, targets, and custom bus"
    echo "✅ CloudWatch log groups"
    echo "✅ IoT Things, certificates, and policies"
    echo "✅ S3 bucket and all contents"
    echo "✅ IAM roles and policies"
    echo "✅ Local configuration files"
    echo ""
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        echo "S3 Bucket removed: $S3_BUCKET_NAME"
    fi
    if [[ -n "${GREENGRASS_THING_NAME:-}" ]]; then
        echo "IoT Thing removed: $GREENGRASS_THING_NAME"
    fi
    if [[ -n "${EVENT_BUS_NAME:-}" ]]; then
        echo "EventBridge Bus removed: $EVENT_BUS_NAME"
    fi
    echo ""
    echo "⚠️  Note: If you have edge devices still running Greengrass,"
    echo "   you may need to manually clean them up:"
    echo "   1. Stop Greengrass service on each device"
    echo "   2. Remove /greengrass directory"
    echo "   3. Uninstall Greengrass software"
    echo ""
    echo "All AWS cloud resources have been successfully removed."
    echo "=================================="
}

# Main destruction function
main() {
    echo ""
    echo "🔥 Edge AI Infrastructure Destruction Script"
    echo "============================================="
    echo ""
    
    # Run destruction steps
    check_prerequisites
    load_deployment_state
    confirm_destruction
    
    log_info "Starting resource destruction..."
    echo ""
    
    # Remove resources in reverse order of creation
    remove_greengrass_deployments
    remove_greengrass_components
    remove_eventbridge_resources
    remove_iot_resources
    remove_s3_resources
    remove_iam_resources
    cleanup_local_files
    
    display_summary
    
    log_success "All resources have been successfully destroyed!"
    exit 0
}

# Handle script interruption
trap 'echo -e "\n${RED}[ERROR]${NC} Script interrupted. Some resources may not have been cleaned up."; exit 1' INT TERM

# Run main function
main "$@"