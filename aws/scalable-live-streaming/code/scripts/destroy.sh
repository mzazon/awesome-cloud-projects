#!/bin/bash

# AWS Elemental MediaLive Live Streaming Solution Cleanup Script
# This script safely removes all resources created by the deployment script
# to avoid ongoing charges and cleanup the environment.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
    
    success "AWS credentials validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    
    if [ "$major_version" -lt 2 ]; then
        error "AWS CLI version 2 or higher is required. Current version: $aws_version"
        exit 1
    fi
    
    success "All prerequisites satisfied"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f .env ]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Attempting to load from individual files..."
        
        # Try to load from individual files
        [ -f .aws_region ] && export AWS_REGION=$(cat .aws_region)
        [ -f .aws_account_id ] && export AWS_ACCOUNT_ID=$(cat .aws_account_id)
        [ -f .stream_name ] && export STREAM_NAME=$(cat .stream_name)
        [ -f .channel_name ] && export CHANNEL_NAME=$(cat .channel_name)
        [ -f .package_channel_name ] && export PACKAGE_CHANNEL_NAME=$(cat .package_channel_name)
        [ -f .distribution_name ] && export DISTRIBUTION_NAME=$(cat .distribution_name)
        [ -f .bucket_name ] && export BUCKET_NAME=$(cat .bucket_name)
        [ -f .iam_role_name ] && export IAM_ROLE_NAME=$(cat .iam_role_name)
        
        # Load resource IDs
        [ -f .channel_id ] && export CHANNEL_ID=$(cat .channel_id)
        [ -f .input_id ] && export INPUT_ID=$(cat .input_id)
        [ -f .security_group_id ] && export SECURITY_GROUP_ID=$(cat .security_group_id)
        [ -f .distribution_id ] && export DISTRIBUTION_ID=$(cat .distribution_id)
        
        # Set AWS region if not set
        if [ -z "${AWS_REGION:-}" ]; then
            export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        fi
        
        if [ -z "${AWS_REGION:-}" ]; then
            error "AWS region not found. Please set AWS_REGION environment variable."
            exit 1
        fi
    fi
    
    log "Using AWS region: ${AWS_REGION}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "This will permanently delete all resources created by the deployment script."
    echo "The following resources will be removed:"
    echo ""
    
    if [ -n "${CHANNEL_ID:-}" ]; then
        echo "- MediaLive Channel: $CHANNEL_ID"
    fi
    
    if [ -n "${PACKAGE_CHANNEL_NAME:-}" ]; then
        echo "- MediaPackage Channel: $PACKAGE_CHANNEL_NAME"
        echo "- MediaPackage Endpoints: ${PACKAGE_CHANNEL_NAME}-hls, ${PACKAGE_CHANNEL_NAME}-dash"
    fi
    
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        echo "- CloudFront Distribution: $DISTRIBUTION_ID"
    fi
    
    if [ -n "${INPUT_ID:-}" ]; then
        echo "- MediaLive Input: $INPUT_ID"
    fi
    
    if [ -n "${SECURITY_GROUP_ID:-}" ]; then
        echo "- MediaLive Security Group: $SECURITY_GROUP_ID"
    fi
    
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        echo "- IAM Role: $IAM_ROLE_NAME"
    fi
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        echo "- S3 Bucket: $BUCKET_NAME (and all contents)"
    fi
    
    echo "- CloudWatch Alarms"
    echo "- SNS Topic: medialive-alerts (if created)"
    echo ""
    
    # Check if running in interactive mode
    if [ -t 0 ]; then
        echo -n "Are you sure you want to proceed? (yes/no): "
        read -r response
        
        if [ "$response" != "yes" ]; then
            log "Destruction cancelled by user."
            exit 0
        fi
    else
        warning "Running in non-interactive mode. Proceeding with destruction..."
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Function to stop and delete MediaLive channel
stop_medialive_channel() {
    if [ -z "${CHANNEL_ID:-}" ]; then
        warning "MediaLive channel ID not found. Skipping channel cleanup."
        return 0
    fi
    
    log "Stopping MediaLive channel: $CHANNEL_ID"
    
    # Check if channel exists and get its state
    local channel_state=""
    if channel_state=$(aws medialive describe-channel \
        --region "$AWS_REGION" \
        --channel-id "$CHANNEL_ID" \
        --query 'State' --output text 2>/dev/null); then
        
        log "Channel state: $channel_state"
        
        if [ "$channel_state" = "RUNNING" ]; then
            log "Stopping MediaLive channel..."
            aws medialive stop-channel \
                --region "$AWS_REGION" \
                --channel-id "$CHANNEL_ID"
            
            # Wait for channel to stop
            log "Waiting for channel to stop..."
            local max_attempts=30
            local attempt=0
            
            while [ $attempt -lt $max_attempts ]; do
                local current_state=$(aws medialive describe-channel \
                    --region "$AWS_REGION" \
                    --channel-id "$CHANNEL_ID" \
                    --query 'State' --output text 2>/dev/null)
                
                if [ "$current_state" = "IDLE" ]; then
                    break
                fi
                
                sleep 10
                attempt=$((attempt + 1))
                log "Waiting for channel to stop... (attempt $attempt/$max_attempts)"
            done
            
            if [ $attempt -eq $max_attempts ]; then
                warning "Channel did not stop within expected time. Proceeding with deletion anyway."
            fi
        fi
        
        # Delete the channel
        log "Deleting MediaLive channel..."
        aws medialive delete-channel \
            --region "$AWS_REGION" \
            --channel-id "$CHANNEL_ID"
        
        success "MediaLive channel deleted"
    else
        warning "MediaLive channel not found or already deleted"
    fi
}

# Function to delete MediaPackage resources
delete_mediapackage_resources() {
    if [ -z "${PACKAGE_CHANNEL_NAME:-}" ]; then
        warning "MediaPackage channel name not found. Skipping MediaPackage cleanup."
        return 0
    fi
    
    log "Deleting MediaPackage resources..."
    
    # Delete MediaPackage origin endpoints
    local endpoints=("${PACKAGE_CHANNEL_NAME}-hls" "${PACKAGE_CHANNEL_NAME}-dash")
    
    for endpoint in "${endpoints[@]}"; do
        if aws mediapackage describe-origin-endpoint \
            --region "$AWS_REGION" \
            --id "$endpoint" >/dev/null 2>&1; then
            
            log "Deleting MediaPackage endpoint: $endpoint"
            aws mediapackage delete-origin-endpoint \
                --region "$AWS_REGION" \
                --id "$endpoint"
            success "Deleted MediaPackage endpoint: $endpoint"
        else
            warning "MediaPackage endpoint $endpoint not found"
        fi
    done
    
    # Delete MediaPackage channel
    if aws mediapackage describe-channel \
        --region "$AWS_REGION" \
        --id "$PACKAGE_CHANNEL_NAME" >/dev/null 2>&1; then
        
        log "Deleting MediaPackage channel: $PACKAGE_CHANNEL_NAME"
        aws mediapackage delete-channel \
            --region "$AWS_REGION" \
            --id "$PACKAGE_CHANNEL_NAME"
        success "Deleted MediaPackage channel: $PACKAGE_CHANNEL_NAME"
    else
        warning "MediaPackage channel $PACKAGE_CHANNEL_NAME not found"
    fi
}

# Function to delete CloudFront distribution
delete_cloudfront_distribution() {
    if [ -z "${DISTRIBUTION_ID:-}" ]; then
        warning "CloudFront distribution ID not found. Skipping CloudFront cleanup."
        return 0
    fi
    
    log "Deleting CloudFront distribution: $DISTRIBUTION_ID"
    
    # Check if distribution exists
    if aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
        
        # Get current distribution config
        local config_file="temp-distribution-config.json"
        local etag=$(aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query 'ETag' --output text)
        
        aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query 'DistributionConfig' > "$config_file"
        
        # Disable distribution first
        log "Disabling CloudFront distribution..."
        local disabled_config=$(cat "$config_file" | jq '.Enabled = false')
        echo "$disabled_config" > "${config_file}.disabled"
        
        aws cloudfront update-distribution \
            --id "$DISTRIBUTION_ID" \
            --distribution-config "file://${config_file}.disabled" \
            --if-match "$etag" >/dev/null
        
        log "Waiting for distribution to be disabled..."
        local max_attempts=60  # CloudFront operations can take time
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            local status=$(aws cloudfront get-distribution \
                --id "$DISTRIBUTION_ID" \
                --query 'Distribution.Status' --output text 2>/dev/null)
            
            if [ "$status" = "Deployed" ]; then
                break
            fi
            
            sleep 30
            attempt=$((attempt + 1))
            log "Waiting for distribution to be disabled... (attempt $attempt/$max_attempts)"
        done
        
        if [ $attempt -eq $max_attempts ]; then
            warning "Distribution did not reach Deployed state within expected time"
            warning "You may need to manually delete the distribution later"
        else
            # Delete the distribution
            log "Deleting CloudFront distribution..."
            local final_etag=$(aws cloudfront get-distribution \
                --id "$DISTRIBUTION_ID" \
                --query 'ETag' --output text)
            
            aws cloudfront delete-distribution \
                --id "$DISTRIBUTION_ID" \
                --if-match "$final_etag"
            
            success "CloudFront distribution deletion initiated"
        fi
        
        # Clean up temporary files
        rm -f "$config_file" "${config_file}.disabled"
    else
        warning "CloudFront distribution $DISTRIBUTION_ID not found"
    fi
}

# Function to delete MediaLive input
delete_medialive_input() {
    if [ -z "${INPUT_ID:-}" ]; then
        warning "MediaLive input ID not found. Skipping input cleanup."
        return 0
    fi
    
    log "Deleting MediaLive input: $INPUT_ID"
    
    if aws medialive describe-input \
        --region "$AWS_REGION" \
        --input-id "$INPUT_ID" >/dev/null 2>&1; then
        
        aws medialive delete-input \
            --region "$AWS_REGION" \
            --input-id "$INPUT_ID"
        success "Deleted MediaLive input: $INPUT_ID"
    else
        warning "MediaLive input $INPUT_ID not found"
    fi
}

# Function to delete input security group
delete_input_security_group() {
    if [ -z "${SECURITY_GROUP_ID:-}" ]; then
        warning "MediaLive security group ID not found. Skipping security group cleanup."
        return 0
    fi
    
    log "Deleting MediaLive input security group: $SECURITY_GROUP_ID"
    
    if aws medialive describe-input-security-group \
        --region "$AWS_REGION" \
        --input-security-group-id "$SECURITY_GROUP_ID" >/dev/null 2>&1; then
        
        aws medialive delete-input-security-group \
            --region "$AWS_REGION" \
            --input-security-group-id "$SECURITY_GROUP_ID"
        success "Deleted MediaLive input security group: $SECURITY_GROUP_ID"
    else
        warning "MediaLive input security group $SECURITY_GROUP_ID not found"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    if [ -z "${IAM_ROLE_NAME:-}" ]; then
        warning "IAM role name not found. Skipping IAM role cleanup."
        return 0
    fi
    
    log "Deleting IAM role: $IAM_ROLE_NAME"
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        
        # Detach policies first
        log "Detaching policies from IAM role..."
        aws iam detach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/MediaLiveFullAccess || true
        
        # Delete the role
        aws iam delete-role --role-name "$IAM_ROLE_NAME"
        success "Deleted IAM role: $IAM_ROLE_NAME"
    else
        warning "IAM role $IAM_ROLE_NAME not found"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "S3 bucket name not found. Skipping S3 cleanup."
        return 0
    fi
    
    log "Deleting S3 bucket: $BUCKET_NAME"
    
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        
        # Delete all objects in the bucket
        log "Deleting all objects in S3 bucket..."
        aws s3 rm "s3://$BUCKET_NAME" --recursive
        
        # Delete all versions if versioning is enabled
        local versions=$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --query 'Versions[*].[Key,VersionId]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$versions" ]; then
            log "Deleting versioned objects..."
            while IFS=$'\t' read -r key version_id; do
                aws s3api delete-object \
                    --bucket "$BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            done <<< "$versions"
        fi
        
        # Delete delete markers
        local delete_markers=$(aws s3api list-object-versions \
            --bucket "$BUCKET_NAME" \
            --query 'DeleteMarkers[*].[Key,VersionId]' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$delete_markers" ]; then
            log "Deleting delete markers..."
            while IFS=$'\t' read -r key version_id; do
                aws s3api delete-object \
                    --bucket "$BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            done <<< "$delete_markers"
        fi
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$BUCKET_NAME"
        success "Deleted S3 bucket: $BUCKET_NAME"
    else
        warning "S3 bucket $BUCKET_NAME not found"
    fi
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    if [ -n "${CHANNEL_NAME:-}" ]; then
        local alarms=("MediaLive-${CHANNEL_NAME}-Errors" "MediaLive-${CHANNEL_NAME}-InputVideoFreeze")
        
        for alarm in "${alarms[@]}"; do
            if aws cloudwatch describe-alarms \
                --alarm-names "$alarm" \
                --region "$AWS_REGION" \
                --query 'MetricAlarms[0].AlarmName' \
                --output text 2>/dev/null | grep -q "$alarm"; then
                
                log "Deleting CloudWatch alarm: $alarm"
                aws cloudwatch delete-alarms \
                    --alarm-names "$alarm" \
                    --region "$AWS_REGION"
                success "Deleted CloudWatch alarm: $alarm"
            else
                warning "CloudWatch alarm $alarm not found"
            fi
        done
    else
        warning "Channel name not found. Skipping CloudWatch alarm cleanup."
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID:-}:medialive-alerts"
    
    if [ -n "${AWS_ACCOUNT_ID:-}" ] && aws sns get-topic-attributes \
        --topic-arn "$topic_arn" >/dev/null 2>&1; then
        
        log "Deleting SNS topic: $topic_arn"
        aws sns delete-topic --topic-arn "$topic_arn"
        success "Deleted SNS topic: $topic_arn"
    else
        warning "SNS topic not found or account ID not available"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # List of files to remove
    local files_to_remove=(
        ".env"
        ".aws_region"
        ".aws_account_id"
        ".stream_name"
        ".channel_name"
        ".package_channel_name"
        ".distribution_name"
        ".bucket_name"
        ".iam_role_name"
        ".channel_id"
        ".input_id"
        ".security_group_id"
        ".distribution_id"
        ".input_url"
        ".package_url"
        ".package_username"
        ".hls_endpoint"
        ".dash_endpoint"
        ".role_arn"
        ".distribution_domain"
        "medialive-trust-policy.json"
        "channel-config.json"
        "distribution-config.json"
        "test-player.html"
        "temp-distribution-config.json"
        "temp-distribution-config.json.disabled"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    success "Temporary files cleaned up"
}

# Function to display final summary
display_summary() {
    echo ""
    success "Resource cleanup completed!"
    echo ""
    echo "All AWS resources have been removed to avoid ongoing charges."
    echo ""
    echo "Resources that were cleaned up:"
    echo "- MediaLive Channel and Input"
    echo "- MediaPackage Channel and Endpoints"
    echo "- CloudFront Distribution"
    echo "- IAM Role and Policies"
    echo "- S3 Bucket and Contents"
    echo "- CloudWatch Alarms"
    echo "- SNS Topic"
    echo "- Temporary Files"
    echo ""
    echo "Note: CloudFront distribution deletion may take additional time to complete."
    echo "Check the AWS Console if you need to verify complete removal."
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    local exit_code=$?
    warning "An error occurred during cleanup. Exit code: $exit_code"
    warning "Some resources may not have been fully cleaned up."
    warning "Please check the AWS Console and manually remove any remaining resources."
    exit $exit_code
}

# Main destruction function
main() {
    log "Starting AWS Elemental MediaLive Live Streaming Solution cleanup..."
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Allow errors during cleanup - we want to continue even if some resources are missing
    set +e
    
    # Run cleanup steps
    check_prerequisites
    validate_aws_credentials
    load_environment
    confirm_destruction
    
    # Clean up resources in reverse order of creation
    stop_medialive_channel
    delete_cloudfront_distribution
    delete_mediapackage_resources
    delete_medialive_input
    delete_input_security_group
    delete_iam_role
    delete_s3_bucket
    delete_cloudwatch_alarms
    delete_sns_topic
    cleanup_temp_files
    
    display_summary
    
    success "Cleanup completed successfully!"
}

# Run main function
main "$@"