#!/bin/bash

# Enterprise Video Streaming Platform Cleanup Script
# AWS Elemental MediaLive, MediaPackage, and CloudFront
# Recipe: Live Video Streaming Platform with MediaLive

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.streaming-platform-state"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"

# Redirect all output to log file and console
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

# Check if deployment exists
check_deployment_exists() {
    if [[ ! -f "$STATE_FILE" ]]; then
        warn "No existing deployment found. Nothing to clean up."
        exit 0
    fi
    
    # Load deployment state
    source "$STATE_FILE"
    
    log "Found existing deployment: $PLATFORM_NAME"
    info "AWS Region: $AWS_REGION"
    info "Platform Name: $PLATFORM_NAME"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo "========================================================"
    echo "STREAMING PLATFORM DESTRUCTION CONFIRMATION"
    echo "========================================================"
    echo ""
    echo "⚠️  WARNING: This will permanently delete all resources!"
    echo ""
    echo "Platform: $PLATFORM_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Resources to be deleted:"
    echo "• MediaLive Channel (ID: ${CHANNEL_ID:-N/A})"
    echo "• MediaLive Inputs (RTMP, HLS, RTP)"
    echo "• MediaPackage Channel and Endpoints"
    echo "• CloudFront Distribution (ID: ${DISTRIBUTION_ID:-N/A})"
    echo "• S3 Bucket and all contents (${BUCKET_NAME:-N/A})"
    echo "• IAM Roles and Policies"
    echo "• CloudWatch Alarms"
    echo "• DRM Keys in Secrets Manager"
    echo ""
    echo "💰 This will stop all streaming charges immediately."
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warn "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to destroy this streaming platform? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Destruction confirmed. Starting cleanup process..."
}

# Stop and delete MediaLive channel
destroy_medialive_channel() {
    log "Stopping and deleting MediaLive channel..."
    
    if [[ -n "${CHANNEL_ID:-}" ]]; then
        # Get current channel state
        local channel_state
        channel_state=$(aws medialive describe-channel \
            --region "$AWS_REGION" \
            --channel-id "$CHANNEL_ID" \
            --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$channel_state" == "NOT_FOUND" ]]; then
            warn "MediaLive channel not found, may have been deleted already"
            return 0
        fi
        
        # Stop channel if running
        if [[ "$channel_state" == "RUNNING" ]]; then
            info "Stopping MediaLive channel..."
            aws medialive stop-channel \
                --region "$AWS_REGION" \
                --channel-id "$CHANNEL_ID"
            
            # Wait for channel to stop
            local timeout=300  # 5 minutes
            local elapsed=0
            
            while [[ $elapsed -lt $timeout ]]; do
                channel_state=$(aws medialive describe-channel \
                    --region "$AWS_REGION" \
                    --channel-id "$CHANNEL_ID" \
                    --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
                
                if [[ "$channel_state" == "IDLE" ]]; then
                    log "MediaLive channel stopped successfully"
                    break
                elif [[ "$channel_state" == "NOT_FOUND" ]]; then
                    warn "Channel disappeared during stop operation"
                    break
                fi
                
                sleep 10
                elapsed=$((elapsed + 10))
                info "Channel state: $channel_state (${elapsed}s elapsed)"
            done
            
            if [[ $elapsed -ge $timeout ]]; then
                warn "Timeout waiting for channel to stop. Attempting deletion anyway..."
            fi
        fi
        
        # Delete channel
        info "Deleting MediaLive channel..."
        aws medialive delete-channel \
            --region "$AWS_REGION" \
            --channel-id "$CHANNEL_ID" 2>/dev/null || warn "Failed to delete channel"
        
        log "MediaLive channel deletion initiated"
    else
        warn "No MediaLive channel ID found in state"
    fi
}

# Delete MediaLive inputs
destroy_medialive_inputs() {
    log "Deleting MediaLive inputs..."
    
    for input_name in "RTMP_INPUT_ID" "HLS_INPUT_ID" "RTP_INPUT_ID"; do
        local input_id="${!input_name:-}"
        
        if [[ -n "$input_id" ]]; then
            info "Deleting MediaLive input: $input_id"
            aws medialive delete-input \
                --region "$AWS_REGION" \
                --input-id "$input_id" 2>/dev/null || warn "Failed to delete input $input_id"
        fi
    done
    
    log "MediaLive inputs deletion completed"
}

# Delete MediaPackage endpoints and channel
destroy_mediapackage() {
    log "Deleting MediaPackage resources..."
    
    if [[ -n "${PACKAGE_CHANNEL_NAME:-}" ]]; then
        # Delete origin endpoints
        for endpoint_type in "hls-advanced" "dash-drm" "cmaf-ll"; do
            local endpoint_id="$PACKAGE_CHANNEL_NAME-$endpoint_type"
            info "Deleting MediaPackage endpoint: $endpoint_id"
            
            aws mediapackage delete-origin-endpoint \
                --region "$AWS_REGION" \
                --id "$endpoint_id" 2>/dev/null || warn "Failed to delete endpoint $endpoint_id"
        done
        
        # Wait a moment for endpoints to be deleted
        sleep 10
        
        # Delete MediaPackage channel
        info "Deleting MediaPackage channel: $PACKAGE_CHANNEL_NAME"
        aws mediapackage delete-channel \
            --region "$AWS_REGION" \
            --id "$PACKAGE_CHANNEL_NAME" 2>/dev/null || warn "Failed to delete MediaPackage channel"
        
        log "MediaPackage resources deletion completed"
    else
        warn "No MediaPackage channel name found in state"
    fi
}

# Delete CloudFront distribution
destroy_cloudfront() {
    log "Deleting CloudFront distribution..."
    
    if [[ -n "${DISTRIBUTION_ID:-}" ]]; then
        # Check if distribution exists
        local distribution_status
        distribution_status=$(aws cloudfront get-distribution \
            --id "$DISTRIBUTION_ID" \
            --query 'Distribution.Status' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$distribution_status" == "NOT_FOUND" ]]; then
            warn "CloudFront distribution not found, may have been deleted already"
            return 0
        fi
        
        # Get current distribution config
        info "Getting CloudFront distribution configuration..."
        aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query 'DistributionConfig' > temp-distribution-config.json 2>/dev/null || {
            warn "Failed to get distribution config"
            return 0
        }
        
        # Disable distribution if enabled
        local enabled=$(jq -r '.Enabled' temp-distribution-config.json)
        if [[ "$enabled" == "true" ]]; then
            info "Disabling CloudFront distribution..."
            
            # Update configuration to disable
            jq '.Enabled = false' temp-distribution-config.json > disabled-distribution-config.json
            
            # Get ETag for update
            local etag
            etag=$(aws cloudfront get-distribution-config \
                --id "$DISTRIBUTION_ID" \
                --query 'ETag' --output text 2>/dev/null || echo "")
            
            if [[ -n "$etag" ]]; then
                # Update distribution to disable it
                aws cloudfront update-distribution \
                    --id "$DISTRIBUTION_ID" \
                    --distribution-config file://disabled-distribution-config.json \
                    --if-match "$etag" > /dev/null 2>&1 || warn "Failed to disable distribution"
                
                # Wait for distribution to be disabled and deployed
                info "Waiting for CloudFront distribution to be disabled and deployed..."
                local timeout=600  # 10 minutes
                local elapsed=0
                
                while [[ $elapsed -lt $timeout ]]; do
                    distribution_status=$(aws cloudfront get-distribution \
                        --id "$DISTRIBUTION_ID" \
                        --query 'Distribution.Status' --output text 2>/dev/null || echo "NOT_FOUND")
                    
                    local enabled_status=$(aws cloudfront get-distribution \
                        --id "$DISTRIBUTION_ID" \
                        --query 'Distribution.DistributionConfig.Enabled' --output text 2>/dev/null || echo "true")
                    
                    if [[ "$distribution_status" == "Deployed" && "$enabled_status" == "false" ]]; then
                        log "CloudFront distribution disabled and deployed"
                        break
                    fi
                    
                    sleep 30
                    elapsed=$((elapsed + 30))
                    info "Distribution status: $distribution_status, enabled: $enabled_status (${elapsed}s elapsed)"
                done
                
                if [[ $elapsed -ge $timeout ]]; then
                    warn "Timeout waiting for distribution to be disabled. Manual deletion may be required."
                fi
            fi
        fi
        
        # Attempt to delete the distribution
        info "Attempting to delete CloudFront distribution..."
        local final_etag
        final_etag=$(aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query 'ETag' --output text 2>/dev/null || echo "")
        
        if [[ -n "$final_etag" ]]; then
            aws cloudfront delete-distribution \
                --id "$DISTRIBUTION_ID" \
                --if-match "$final_etag" 2>/dev/null || {
                warn "Failed to delete CloudFront distribution automatically"
                warn "Please delete distribution $DISTRIBUTION_ID manually in AWS Console"
                warn "Wait for distribution to be fully disabled before deletion"
            }
        fi
        
        # Clean up temporary files
        rm -f temp-distribution-config.json disabled-distribution-config.json
        
        log "CloudFront distribution deletion initiated"
    else
        warn "No CloudFront distribution ID found in state"
    fi
}

# Delete S3 bucket and contents
destroy_s3_storage() {
    log "Deleting S3 storage..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
            info "Deleting all objects in S3 bucket: $BUCKET_NAME"
            
            # Delete all object versions (including delete markers)
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text | while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" >/dev/null 2>&1 || true
                fi
            done
            
            # Delete all delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text | while read -r key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" >/dev/null 2>&1 || true
                fi
            done
            
            # Remove all objects (fallback)
            aws s3 rm "s3://$BUCKET_NAME" --recursive 2>/dev/null || true
            
            # Delete the bucket
            info "Deleting S3 bucket: $BUCKET_NAME"
            aws s3 rb "s3://$BUCKET_NAME" 2>/dev/null || warn "Failed to delete S3 bucket"
            
            log "S3 storage deletion completed"
        else
            warn "S3 bucket $BUCKET_NAME not found"
        fi
    else
        warn "No S3 bucket name found in state"
    fi
}

# Delete IAM roles and policies
destroy_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local role_name="MediaLivePlatformRole-$RANDOM_SUFFIX"
        
        # Delete role policy
        info "Deleting IAM role policy: MediaLivePlatformPolicy"
        aws iam delete-role-policy \
            --role-name "$role_name" \
            --policy-name "MediaLivePlatformPolicy" 2>/dev/null || warn "Failed to delete role policy"
        
        # Delete role
        info "Deleting IAM role: $role_name"
        aws iam delete-role \
            --role-name "$role_name" 2>/dev/null || warn "Failed to delete IAM role"
        
        log "IAM resources deletion completed"
    else
        warn "No random suffix found in state - cannot determine role names"
    fi
}

# Delete input security groups
destroy_security_groups() {
    log "Deleting MediaLive input security groups..."
    
    for sg_name in "SECURITY_GROUP_ID" "INTERNAL_SG_ID"; do
        local sg_id="${!sg_name:-}"
        
        if [[ -n "$sg_id" ]]; then
            info "Deleting input security group: $sg_id"
            aws medialive delete-input-security-group \
                --region "$AWS_REGION" \
                --input-security-group-id "$sg_id" 2>/dev/null || warn "Failed to delete security group $sg_id"
        fi
    done
    
    log "Security groups deletion completed"
}

# Delete CloudWatch alarms
destroy_monitoring() {
    log "Deleting CloudWatch alarms..."
    
    local alarm_names=()
    
    if [[ -n "${LIVE_CHANNEL_NAME:-}" ]]; then
        alarm_names+=("MediaLive-$LIVE_CHANNEL_NAME-InputLoss")
    fi
    
    if [[ -n "${PACKAGE_CHANNEL_NAME:-}" ]]; then
        alarm_names+=("MediaPackage-$PACKAGE_CHANNEL_NAME-EgressErrors")
    fi
    
    if [[ -n "${DISTRIBUTION_ID:-}" ]]; then
        alarm_names+=("CloudFront-$DISTRIBUTION_ID-ErrorRate")
    fi
    
    if [[ ${#alarm_names[@]} -gt 0 ]]; then
        info "Deleting CloudWatch alarms: ${alarm_names[*]}"
        aws cloudwatch delete-alarms \
            --alarm-names "${alarm_names[@]}" 2>/dev/null || warn "Failed to delete some CloudWatch alarms"
    fi
    
    log "Monitoring resources deletion completed"
}

# Delete DRM keys from Secrets Manager
destroy_secrets() {
    log "Deleting secrets from Secrets Manager..."
    
    if [[ -n "${DRM_KEY_ID:-}" ]]; then
        info "Deleting DRM key secret: $DRM_KEY_ID"
        aws secretsmanager delete-secret \
            --secret-id "$DRM_KEY_ID" \
            --force-delete-without-recovery 2>/dev/null || warn "Failed to delete DRM key secret"
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        info "Deleting DRM key secret by name: medialive-drm-key-$RANDOM_SUFFIX"
        aws secretsmanager delete-secret \
            --secret-id "medialive-drm-key-$RANDOM_SUFFIX" \
            --force-delete-without-recovery 2>/dev/null || warn "Failed to delete DRM key secret by name"
    fi
    
    log "Secrets deletion completed"
}

# Clean up state and temporary files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove state file
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        info "Removed state file: $STATE_FILE"
    fi
    
    # Remove temporary files that might exist
    local temp_files=(
        "lifecycle-policy.json"
        "medialive-trust-policy.json"
        "medialive-platform-policy.json"
        "platform-channel-config.json"
        "cloudfront-distribution-config.json"
        "streaming-platform-player.html"
        "temp-distribution-config.json"
        "disabled-distribution-config.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed temporary file: $file"
        fi
    done
    
    log "Local cleanup completed"
}

# Display final summary
display_cleanup_summary() {
    echo ""
    echo "========================================================"
    echo "STREAMING PLATFORM DESTRUCTION COMPLETED"
    echo "========================================================"
    echo ""
    echo "✅ Resources deleted:"
    echo "• MediaLive Channel and Inputs"
    echo "• MediaPackage Channel and Endpoints"
    echo "• CloudFront Distribution (deletion initiated)"
    echo "• S3 Bucket and all contents"
    echo "• IAM Roles and Policies"
    echo "• Input Security Groups"
    echo "• CloudWatch Alarms"
    echo "• DRM Keys and Secrets"
    echo "• Local state and temporary files"
    echo ""
    echo "⚠️  Important notes:"
    echo "• CloudFront distribution deletion may take 15-20 minutes to complete"
    echo "• Check AWS Console to verify all resources are deleted"
    echo "• Any remaining resources will continue to incur charges"
    echo "• Streaming charges have been stopped immediately"
    echo ""
    echo "📊 Cost impact:"
    echo "• MediaLive charges stopped (channel no longer running)"
    echo "• MediaPackage charges stopped (no more requests)"
    echo "• CloudFront charges will stop when deletion completes"
    echo "• S3 charges stopped (bucket and contents deleted)"
    echo ""
    echo "🔧 Cleanup log saved to: $LOG_FILE"
    echo "========================================================"
    echo ""
    log "Enterprise streaming platform destroyed successfully!"
}

# Main destruction function
main() {
    log "Starting enterprise video streaming platform destruction..."
    
    # Check deployment exists and load state
    check_deployment_exists
    
    # Confirm destruction
    confirm_destruction
    
    # Execute destruction steps in reverse order
    destroy_medialive_channel
    destroy_medialive_inputs
    destroy_mediapackage
    destroy_cloudfront
    destroy_s3_storage
    destroy_iam_resources
    destroy_security_groups
    destroy_monitoring
    destroy_secrets
    cleanup_local_files
    display_cleanup_summary
}

# Handle command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            export FORCE_DESTROY="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force|-f] [--help|-h]"
            echo ""
            echo "Options:"
            echo "  --force, -f    Skip confirmation prompt"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "This script will destroy the entire streaming platform and all associated resources."
            echo "Use with caution as this action cannot be undone."
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Execute main function
main "$@"