#!/bin/bash

# Video Content Protection with DRM and MediaPackage - Cleanup Script
# This script safely removes all DRM-protected video streaming infrastructure
# created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Function to load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [ ! -f "drm-deployment-config.json" ]; then
        error "Configuration file 'drm-deployment-config.json' not found. Cannot proceed with cleanup."
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        error "jq is required for parsing configuration. Please install it first."
    fi
    
    # Load configuration variables
    export AWS_REGION=$(jq -r '.aws_region // empty' drm-deployment-config.json)
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' drm-deployment-config.json)
    export RANDOM_SUFFIX=$(jq -r '.random_suffix // empty' drm-deployment-config.json)
    export CHANNEL_NAME=$(jq -r '.channel_name // empty' drm-deployment-config.json)
    export PACKAGE_CHANNEL=$(jq -r '.package_channel // empty' drm-deployment-config.json)
    export DRM_KEY_SECRET=$(jq -r '.drm_key_secret // empty' drm-deployment-config.json)
    export LAMBDA_FUNCTION=$(jq -r '.lambda_function // empty' drm-deployment-config.json)
    export OUTPUT_BUCKET=$(jq -r '.output_bucket // empty' drm-deployment-config.json)
    export DRM_KMS_KEY_ID=$(jq -r '.drm_kms_key_id // empty' drm-deployment-config.json)
    export DRM_SECRET_ARN=$(jq -r '.drm_secret_arn // empty' drm-deployment-config.json)
    export SPEKE_FUNCTION_URL=$(jq -r '.speke_function_url // empty' drm-deployment-config.json)
    export CHANNEL_ID=$(jq -r '.channel_id // empty' drm-deployment-config.json)
    export INPUT_ID=$(jq -r '.input_id // empty' drm-deployment-config.json)
    export SECURITY_GROUP_ID=$(jq -r '.security_group_id // empty' drm-deployment-config.json)
    export DRM_DISTRIBUTION_ID=$(jq -r '.drm_distribution_id // empty' drm-deployment-config.json)
    export MEDIALIVE_ROLE_ARN=$(jq -r '.medialive_role_arn // empty' drm-deployment-config.json)
    export SPEKE_LAMBDA_ROLE_ARN=$(jq -r '.speke_lambda_role_arn // empty' drm-deployment-config.json)
    
    # Verify essential configuration exists
    if [ -z "$AWS_REGION" ] || [ -z "$RANDOM_SUFFIX" ]; then
        error "Essential configuration missing from drm-deployment-config.json"
    fi
    
    log "Configuration loaded successfully"
    info "AWS Region: ${AWS_REGION}"
    info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "================================================================"
    echo "DRM-PROTECTED VIDEO STREAMING INFRASTRUCTURE CLEANUP"
    echo "================================================================"
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    echo "🎯 MediaLive Resources:"
    echo "  • Channel: ${CHANNEL_NAME:-'N/A'}"
    echo "  • Input: ${INPUT_ID:-'N/A'}"
    echo "  • Security Group: ${SECURITY_GROUP_ID:-'N/A'}"
    echo ""
    echo "📦 MediaPackage Resources:"
    echo "  • Channel: ${PACKAGE_CHANNEL:-'N/A'}"
    echo "  • HLS DRM Endpoint"
    echo "  • DASH DRM Endpoint"
    echo ""
    echo "⚡ Lambda Resources:"
    echo "  • SPEKE Function: ${LAMBDA_FUNCTION:-'N/A'}"
    echo "  • Function URL Configuration"
    echo "  • IAM Role and Policies"
    echo ""
    echo "🔐 Security Resources:"
    echo "  • KMS Key: ${DRM_KMS_KEY_ID:-'N/A'}"
    echo "  • Secrets Manager Secret: ${DRM_KEY_SECRET:-'N/A'}"
    echo "  • IAM Roles and Policies"
    echo ""
    echo "🌐 Distribution Resources:"
    echo "  • CloudFront Distribution: ${DRM_DISTRIBUTION_ID:-'N/A'}"
    echo "  • S3 Bucket: ${OUTPUT_BUCKET:-'N/A'}"
    echo ""
    echo "💰 COST IMPACT:"
    echo "  • Stops all hourly charges (MediaLive ~\$15-20/hour)"
    echo "  • Removes storage and data transfer costs"
    echo "  • KMS key will be scheduled for deletion (7-day grace period)"
    echo ""
    
    read -p "Are you sure you want to proceed with the cleanup? (type 'yes' to confirm): " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Starting resource destruction..."
}

# Function to stop and delete MediaLive channel
cleanup_medialive_channel() {
    if [ -n "${CHANNEL_ID:-}" ]; then
        log "Stopping and deleting MediaLive channel..."
        
        # Check channel state
        CHANNEL_STATE=$(aws medialive describe-channel \
            --region ${AWS_REGION} \
            --channel-id ${CHANNEL_ID} \
            --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$CHANNEL_STATE" != "NOT_FOUND" ]; then
            if [ "$CHANNEL_STATE" = "RUNNING" ]; then
                info "Stopping MediaLive channel..."
                aws medialive stop-channel \
                    --region ${AWS_REGION} \
                    --channel-id ${CHANNEL_ID} || warn "Failed to stop MediaLive channel"
                
                # Wait for channel to stop
                info "Waiting for channel to stop (this may take 2-3 minutes)..."
                aws medialive wait channel-stopped \
                    --region ${AWS_REGION} \
                    --channel-id ${CHANNEL_ID} || warn "Timeout waiting for channel to stop"
            fi
            
            # Delete channel
            info "Deleting MediaLive channel..."
            aws medialive delete-channel \
                --region ${AWS_REGION} \
                --channel-id ${CHANNEL_ID} || warn "Failed to delete MediaLive channel"
            
            log "✅ MediaLive channel deleted"
        else
            warn "MediaLive channel not found or already deleted"
        fi
    else
        warn "No MediaLive channel ID found in configuration"
    fi
}

# Function to delete MediaLive input and security group
cleanup_medialive_input() {
    if [ -n "${INPUT_ID:-}" ]; then
        log "Deleting MediaLive input..."
        
        aws medialive delete-input \
            --region ${AWS_REGION} \
            --input-id ${INPUT_ID} || warn "Failed to delete MediaLive input"
        
        log "✅ MediaLive input deleted"
    else
        warn "No MediaLive input ID found in configuration"
    fi
    
    if [ -n "${SECURITY_GROUP_ID:-}" ]; then
        log "Deleting MediaLive input security group..."
        
        aws medialive delete-input-security-group \
            --region ${AWS_REGION} \
            --input-security-group-id ${SECURITY_GROUP_ID} || warn "Failed to delete input security group"
        
        log "✅ MediaLive input security group deleted"
    else
        warn "No security group ID found in configuration"
    fi
}

# Function to delete MediaPackage resources
cleanup_mediapackage() {
    if [ -n "${PACKAGE_CHANNEL:-}" ]; then
        log "Deleting MediaPackage resources..."
        
        # Delete HLS DRM endpoint
        info "Deleting HLS DRM endpoint..."
        aws mediapackage delete-origin-endpoint \
            --region ${AWS_REGION} \
            --id "${PACKAGE_CHANNEL}-hls-drm" || warn "Failed to delete HLS DRM endpoint"
        
        # Delete DASH DRM endpoint
        info "Deleting DASH DRM endpoint..."
        aws mediapackage delete-origin-endpoint \
            --region ${AWS_REGION} \
            --id "${PACKAGE_CHANNEL}-dash-drm" || warn "Failed to delete DASH DRM endpoint"
        
        # Delete MediaPackage channel
        info "Deleting MediaPackage channel..."
        aws mediapackage delete-channel \
            --region ${AWS_REGION} \
            --id ${PACKAGE_CHANNEL} || warn "Failed to delete MediaPackage channel"
        
        log "✅ MediaPackage resources deleted"
    else
        warn "No MediaPackage channel found in configuration"
    fi
}

# Function to delete SPEKE Lambda function and related resources
cleanup_speke_lambda() {
    if [ -n "${LAMBDA_FUNCTION:-}" ]; then
        log "Deleting SPEKE Lambda function and related resources..."
        
        # Delete function URL configuration
        info "Deleting Lambda function URL configuration..."
        aws lambda delete-function-url-config \
            --function-name ${LAMBDA_FUNCTION} || warn "Failed to delete function URL configuration"
        
        # Delete Lambda function
        info "Deleting Lambda function..."
        aws lambda delete-function \
            --function-name ${LAMBDA_FUNCTION} || warn "Failed to delete Lambda function"
        
        # Delete Lambda role policies
        info "Deleting Lambda role policies..."
        aws iam delete-role-policy \
            --role-name ${LAMBDA_FUNCTION}-role \
            --policy-name SecretsManagerAccessPolicy || warn "Failed to delete Lambda role policy"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name ${LAMBDA_FUNCTION}-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || warn "Failed to detach managed policy"
        
        # Delete Lambda role
        info "Deleting Lambda IAM role..."
        aws iam delete-role \
            --role-name ${LAMBDA_FUNCTION}-role || warn "Failed to delete Lambda role"
        
        log "✅ SPEKE Lambda function and related resources deleted"
    else
        warn "No Lambda function found in configuration"
    fi
}

# Function to delete MediaLive IAM role
cleanup_medialive_role() {
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        log "Deleting MediaLive IAM role..."
        
        # Delete role policy
        info "Deleting MediaLive role policy..."
        aws iam delete-role-policy \
            --role-name MediaLiveDRMRole-${RANDOM_SUFFIX} \
            --policy-name MediaLiveDRMPolicy || warn "Failed to delete MediaLive role policy"
        
        # Delete role
        info "Deleting MediaLive IAM role..."
        aws iam delete-role \
            --role-name MediaLiveDRMRole-${RANDOM_SUFFIX} || warn "Failed to delete MediaLive role"
        
        log "✅ MediaLive IAM role deleted"
    else
        warn "Cannot delete MediaLive role - no random suffix found"
    fi
}

# Function to delete Secrets Manager resources
cleanup_secrets() {
    if [ -n "${DRM_KEY_SECRET:-}" ]; then
        log "Deleting Secrets Manager secret..."
        
        aws secretsmanager delete-secret \
            --secret-id ${DRM_KEY_SECRET} \
            --force-delete-without-recovery || warn "Failed to delete secret"
        
        log "✅ Secrets Manager secret deleted"
    else
        warn "No secret name found in configuration"
    fi
}

# Function to delete KMS resources
cleanup_kms() {
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        log "Deleting KMS resources..."
        
        # Delete KMS key alias
        info "Deleting KMS key alias..."
        aws kms delete-alias \
            --alias-name "alias/drm-content-${RANDOM_SUFFIX}" || warn "Failed to delete KMS alias"
        
        if [ -n "${DRM_KMS_KEY_ID:-}" ]; then
            # Schedule KMS key for deletion
            info "Scheduling KMS key for deletion (7-day waiting period)..."
            aws kms schedule-key-deletion \
                --key-id ${DRM_KMS_KEY_ID} \
                --pending-window-in-days 7 || warn "Failed to schedule KMS key deletion"
            
            log "✅ KMS key scheduled for deletion in 7 days"
        else
            warn "No KMS key ID found in configuration"
        fi
    else
        warn "Cannot delete KMS resources - no random suffix found"
    fi
}

# Function to disable and prepare CloudFront distribution for deletion
cleanup_cloudfront() {
    if [ -n "${DRM_DISTRIBUTION_ID:-}" ]; then
        log "Disabling CloudFront distribution..."
        
        # Get current distribution configuration
        info "Getting current CloudFront distribution configuration..."
        aws cloudfront get-distribution-config \
            --id ${DRM_DISTRIBUTION_ID} \
            --query 'DistributionConfig' > temp-drm-dist-config.json || {
                warn "Failed to get CloudFront distribution configuration"
                return
            }
        
        # Disable distribution
        info "Disabling CloudFront distribution..."
        cat temp-drm-dist-config.json | jq '.Enabled = false' > disabled-drm-dist-config.json
        
        # Get ETag for update
        ETAG=$(aws cloudfront get-distribution-config \
            --id ${DRM_DISTRIBUTION_ID} \
            --query 'ETag' --output text) || {
                warn "Failed to get CloudFront ETag"
                rm -f temp-drm-dist-config.json disabled-drm-dist-config.json
                return
            }
        
        # Update distribution to disable
        aws cloudfront update-distribution \
            --id ${DRM_DISTRIBUTION_ID} \
            --distribution-config file://disabled-drm-dist-config.json \
            --if-match ${ETAG} || warn "Failed to disable CloudFront distribution"
        
        # Clean up temporary files
        rm -f temp-drm-dist-config.json disabled-drm-dist-config.json
        
        warn "CloudFront distribution has been disabled but not deleted."
        warn "After propagation completes (~15 minutes), manually delete it using:"
        warn "aws cloudfront delete-distribution --id ${DRM_DISTRIBUTION_ID} --if-match <new-etag>"
        
        log "✅ CloudFront distribution disabled"
    else
        warn "No CloudFront distribution ID found in configuration"
    fi
}

# Function to delete S3 bucket and contents
cleanup_s3() {
    if [ -n "${OUTPUT_BUCKET:-}" ]; then
        log "Deleting S3 bucket and contents..."
        
        # Check if bucket exists
        if aws s3 ls s3://${OUTPUT_BUCKET} &> /dev/null; then
            # Remove all objects from bucket
            info "Removing all objects from S3 bucket..."
            aws s3 rm s3://${OUTPUT_BUCKET} --recursive || warn "Failed to remove bucket contents"
            
            # Delete bucket
            info "Deleting S3 bucket..."
            aws s3 rb s3://${OUTPUT_BUCKET} || warn "Failed to delete S3 bucket"
            
            log "✅ S3 bucket and contents deleted"
        else
            warn "S3 bucket not found or already deleted"
        fi
    else
        warn "No S3 bucket name found in configuration"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might have been created
    local files_to_remove=(
        "drm-config.json"
        "speke_provider.py"
        "speke-provider.zip"
        "speke-lambda-trust-policy.json"
        "speke-secrets-policy.json"
        "medialive-drm-trust-policy.json"
        "medialive-drm-policy.json"
        "medialive-drm-channel.json"
        "cloudfront-drm-distribution.json"
        "drm-test-player.html"
        "temp-drm-dist-config.json"
        "disabled-drm-dist-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done
    
    log "✅ Local temporary files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo ""
    echo "================================================================"
    echo "DRM-PROTECTED VIDEO STREAMING CLEANUP SUMMARY"
    echo "================================================================"
    echo ""
    echo "✅ RESOURCES DELETED:"
    echo "• MediaLive channel and input"
    echo "• MediaPackage channel and endpoints"
    echo "• SPEKE Lambda function and IAM role"
    echo "• MediaLive IAM role"
    echo "• Secrets Manager secret"
    echo "• S3 bucket and contents"
    echo "• Local temporary files"
    echo ""
    echo "⏳ PENDING DELETIONS:"
    echo "• KMS key (scheduled for deletion in 7 days)"
    echo "• CloudFront distribution (requires manual deletion after propagation)"
    echo ""
    echo "💰 COST IMPACT:"
    echo "• All hourly charges stopped immediately"
    echo "• No more data transfer or storage costs"
    echo "• KMS key charges stop after 7-day deletion period"
    echo ""
    echo "📋 MANUAL ACTIONS REQUIRED:"
    if [ -n "${DRM_DISTRIBUTION_ID:-}" ]; then
        echo "1. Wait 15 minutes for CloudFront distribution to disable"
        echo "2. Delete CloudFront distribution manually:"
        echo "   aws cloudfront delete-distribution --id ${DRM_DISTRIBUTION_ID} --if-match <etag>"
        echo ""
    fi
    echo "⚠️  IMPORTANT:"
    echo "• Keep drm-deployment-config.json for reference if needed"
    echo "• Monitor AWS billing to confirm cost reduction"
    echo "• Check CloudWatch logs for any remaining activity"
    echo ""
    echo "================================================================"
}

# Function to handle cleanup errors gracefully
handle_cleanup_errors() {
    warn "Some resources may not have been deleted due to errors."
    warn "This is often normal due to:"
    warn "• Resources already deleted manually"
    warn "• Dependencies still in use"
    warn "• Timing issues with AWS services"
    warn ""
    warn "Please check the AWS console to verify cleanup completion."
}

# Main cleanup function
main() {
    log "Starting DRM-protected video streaming infrastructure cleanup..."
    
    # Load configuration
    load_configuration
    
    # Confirm destruction
    confirm_destruction
    
    # Execute cleanup in proper order (reverse of creation)
    # Note: We use || true to continue on errors for non-critical failures
    
    cleanup_medialive_channel
    cleanup_medialive_input
    cleanup_medialive_role
    cleanup_mediapackage
    cleanup_speke_lambda
    cleanup_secrets
    cleanup_kms
    cleanup_cloudfront
    cleanup_s3
    cleanup_local_files
    
    # Display summary
    display_cleanup_summary
}

# Error handling
trap 'handle_cleanup_errors' ERR

# Check prerequisites
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
fi

# Execute main function
main "$@"

log "Cleanup script completed successfully!"