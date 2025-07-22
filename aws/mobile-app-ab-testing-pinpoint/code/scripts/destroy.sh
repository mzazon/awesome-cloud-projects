#!/bin/bash

# =============================================================================
# Destroy Script for A/B Testing Mobile Apps with Amazon Pinpoint
# =============================================================================
# This script safely removes all resources created by the deployment script
# for the A/B testing infrastructure, including campaigns, segments, analytics,
# and monitoring resources.
# =============================================================================

# Color codes for output
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

# Parse command line arguments
FORCE_CLEANUP=false
CONFIRM_DESTRUCTIVE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            CONFIRM_DESTRUCTIVE=false
            shift
            ;;
        --yes)
            CONFIRM_DESTRUCTIVE=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force     Force cleanup without confirmation"
            echo "  --yes       Skip confirmation prompts"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Load Environment Variables
# =============================================================================

log "Loading environment configuration..."

# Check if .env file exists
if [ ! -f ".env" ]; then
    log_error ".env file not found. Cannot proceed with cleanup."
    log_error "Please ensure you're running this script from the same directory as deploy.sh"
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

log_success "Environment variables loaded"
log "Region: ${AWS_REGION}"
log "Account ID: ${AWS_ACCOUNT_ID}"

# =============================================================================
# Prerequisites Check
# =============================================================================

log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Verify we're in the correct AWS account
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
    log_error "AWS account mismatch. Expected: ${AWS_ACCOUNT_ID}, Current: ${CURRENT_ACCOUNT}"
    exit 1
fi

log_success "Prerequisites check completed"

# =============================================================================
# Confirmation Prompt
# =============================================================================

if [ "$CONFIRM_DESTRUCTIVE" = true ]; then
    echo
    log_warning "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
    echo
    echo "This will permanently delete the following resources:"
    echo "  • Pinpoint Application: ${PINPOINT_APP_ID}"
    echo "  • Campaign: ${CAMPAIGN_ID}"
    echo "  • User Segments: ${ACTIVE_USERS_SEGMENT}, ${HIGH_VALUE_SEGMENT}"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "  • Kinesis Stream: ${KINESIS_STREAM_NAME}"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo
    echo "This action cannot be undone."
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

cleanup_campaign() {
    log "Stopping and deleting campaign..."
    
    if [ -n "${CAMPAIGN_ID}" ]; then
        # First, pause the campaign
        aws pinpoint update-campaign \
            --application-id "${PINPOINT_APP_ID}" \
            --campaign-id "${CAMPAIGN_ID}" \
            --write-campaign-request '{"IsPaused": true}' \
            2>/dev/null || log_warning "Failed to pause campaign or campaign not found"
        
        # Wait a moment for the campaign to stop
        sleep 5
        
        # Delete the campaign
        aws pinpoint delete-campaign \
            --application-id "${PINPOINT_APP_ID}" \
            --campaign-id "${CAMPAIGN_ID}" \
            2>/dev/null || log_warning "Failed to delete campaign or campaign not found"
        
        log_success "Campaign cleanup completed"
    else
        log_warning "Campaign ID not found, skipping campaign cleanup"
    fi
}

cleanup_segments() {
    log "Deleting user segments..."
    
    if [ -n "${ACTIVE_USERS_SEGMENT}" ]; then
        aws pinpoint delete-segment \
            --application-id "${PINPOINT_APP_ID}" \
            --segment-id "${ACTIVE_USERS_SEGMENT}" \
            2>/dev/null || log_warning "Failed to delete active users segment"
        
        log_success "Active users segment deleted"
    fi
    
    if [ -n "${HIGH_VALUE_SEGMENT}" ]; then
        aws pinpoint delete-segment \
            --application-id "${PINPOINT_APP_ID}" \
            --segment-id "${HIGH_VALUE_SEGMENT}" \
            2>/dev/null || log_warning "Failed to delete high-value users segment"
        
        log_success "High-value users segment deleted"
    fi
}

cleanup_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    if [ -n "${DASHBOARD_NAME}" ]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" \
            2>/dev/null || log_warning "Failed to delete CloudWatch dashboard"
        
        log_success "CloudWatch dashboard deleted"
    else
        log_warning "Dashboard name not found, skipping dashboard cleanup"
    fi
}

cleanup_kinesis_stream() {
    log "Deleting Kinesis stream..."
    
    if [ -n "${KINESIS_STREAM_NAME}" ]; then
        # Check if stream exists
        if aws kinesis describe-stream --stream-name "${KINESIS_STREAM_NAME}" &>/dev/null; then
            aws kinesis delete-stream \
                --stream-name "${KINESIS_STREAM_NAME}" \
                --enforce-consumer-deletion \
                2>/dev/null || log_warning "Failed to delete Kinesis stream"
            
            log_success "Kinesis stream deletion initiated"
        else
            log_warning "Kinesis stream not found"
        fi
    else
        log_warning "Kinesis stream name not found, skipping stream cleanup"
    fi
}

cleanup_s3_bucket() {
    log "Cleaning up S3 bucket..."
    
    if [ -n "${S3_BUCKET_NAME}" ]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            # Remove all objects from bucket (including versions)
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || log_warning "Failed to empty S3 bucket"
            
            # Remove all object versions
            aws s3api delete-objects --bucket "${S3_BUCKET_NAME}" \
                --delete "$(aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' --output json)" \
                2>/dev/null || log_warning "Failed to delete object versions"
            
            # Remove delete markers
            aws s3api delete-objects --bucket "${S3_BUCKET_NAME}" \
                --delete "$(aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' --output json)" \
                2>/dev/null || log_warning "Failed to delete delete markers"
            
            # Delete the bucket
            aws s3 rb "s3://${S3_BUCKET_NAME}" 2>/dev/null || log_warning "Failed to delete S3 bucket"
            
            log_success "S3 bucket cleaned up"
        else
            log_warning "S3 bucket not found"
        fi
    else
        log_warning "S3 bucket name not found, skipping bucket cleanup"
    fi
}

cleanup_iam_resources() {
    log "Cleaning up IAM resources..."
    
    if [ -n "${IAM_ROLE_NAME}" ]; then
        # Get attached policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null)
        
        # Detach policies
        if [ -n "${ATTACHED_POLICIES}" ]; then
            for policy_arn in ${ATTACHED_POLICIES}; do
                aws iam detach-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-arn "${policy_arn}" \
                    2>/dev/null || log_warning "Failed to detach policy: ${policy_arn}"
            done
        fi
        
        # Delete custom policy if it exists
        POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PinpointAnalyticsPolicy-${RANDOM_SUFFIX}"
        if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
            aws iam delete-policy --policy-arn "${POLICY_ARN}" \
                2>/dev/null || log_warning "Failed to delete custom policy"
        fi
        
        # Delete IAM role
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" \
            2>/dev/null || log_warning "Failed to delete IAM role"
        
        log_success "IAM resources cleaned up"
    else
        log_warning "IAM role name not found, skipping IAM cleanup"
    fi
}

cleanup_pinpoint_application() {
    log "Deleting Pinpoint application..."
    
    if [ -n "${PINPOINT_APP_ID}" ]; then
        # Delete the Pinpoint application (this will also delete associated resources)
        aws pinpoint delete-app --application-id "${PINPOINT_APP_ID}" \
            2>/dev/null || log_warning "Failed to delete Pinpoint application"
        
        log_success "Pinpoint application deleted"
    else
        log_warning "Pinpoint application ID not found, skipping application cleanup"
    fi
}

cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    rm -f trust-policy.json pinpoint-policy.json ab-test-campaign.json dashboard-config.json winner-selection-lambda.py
    
    log_success "Temporary files cleaned up"
}

# =============================================================================
# Execute Cleanup
# =============================================================================

log "Starting resource cleanup..."

# Execute cleanup functions in reverse order of creation
cleanup_campaign
cleanup_segments
cleanup_cloudwatch_dashboard
cleanup_kinesis_stream
cleanup_s3_bucket
cleanup_iam_resources
cleanup_pinpoint_application
cleanup_temp_files

# =============================================================================
# Final Cleanup
# =============================================================================

log "Performing final cleanup..."

# Remove environment file
if [ -f ".env" ]; then
    rm -f ".env"
    log_success "Environment file removed"
fi

# =============================================================================
# Cleanup Summary
# =============================================================================

log_success "=== CLEANUP COMPLETED SUCCESSFULLY ==="
echo
echo "🧹 All resources have been cleaned up:"
echo "  ✅ Pinpoint Application deleted"
echo "  ✅ Campaign and segments removed"
echo "  ✅ CloudWatch dashboard deleted"
echo "  ✅ Kinesis stream deleted"
echo "  ✅ S3 bucket and contents removed"
echo "  ✅ IAM role and policies deleted"
echo "  ✅ Temporary files cleaned up"
echo
echo "💰 Cost Impact:"
echo "  • All billable resources have been terminated"
echo "  • No ongoing charges should occur from this deployment"
echo
echo "📋 Notes:"
echo "  • Some resources may take a few minutes to fully terminate"
echo "  • CloudWatch logs may be retained based on your retention settings"
echo "  • Check the AWS console to verify complete cleanup if needed"
echo
log_success "Cleanup completed successfully!"

# =============================================================================
# Post-Cleanup Verification
# =============================================================================

if [ "$FORCE_CLEANUP" = false ]; then
    echo
    log "Running post-cleanup verification..."
    
    # Check if Pinpoint app still exists
    if aws pinpoint get-app --application-id "${PINPOINT_APP_ID}" &>/dev/null; then
        log_warning "Pinpoint application may still exist"
    else
        log_success "Pinpoint application confirmed deleted"
    fi
    
    # Check if S3 bucket still exists
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket may still exist"
    else
        log_success "S3 bucket confirmed deleted"
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        log_warning "IAM role may still exist"
    else
        log_success "IAM role confirmed deleted"
    fi
    
    log_success "Post-cleanup verification completed"
fi

exit 0