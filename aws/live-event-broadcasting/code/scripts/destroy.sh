#!/bin/bash

# Destroy script for AWS Elemental MediaConnect Live Event Broadcasting
# This script safely removes all resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
FORCE_CLEANUP=false
ENVIRONMENT_FILE="/tmp/live-broadcast-env.txt"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force                 Skip confirmation prompts"
    echo "  --env-file FILE         Use custom environment file (default: /tmp/live-broadcast-env.txt)"
    echo "  --help                  Show this help message"
    echo
    echo "Examples:"
    echo "  $0                      Interactive cleanup with confirmations"
    echo "  $0 --force              Automatic cleanup without prompts"
    echo "  $0 --env-file /path/to/env.txt"
    echo
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --env-file)
                ENVIRONMENT_FILE="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if environment file exists
    if [[ ! -f "$ENVIRONMENT_FILE" ]]; then
        error "Environment file not found: $ENVIRONMENT_FILE"
        error "This file is created by the deploy script and contains resource identifiers."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables from: $ENVIRONMENT_FILE"
    
    # Source the environment file
    source "$ENVIRONMENT_FILE"
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION"
        "FLOW_NAME_PRIMARY"
        "FLOW_NAME_BACKUP"
        "MEDIALIVE_CHANNEL_NAME"
        "MEDIAPACKAGE_CHANNEL_ID"
        "IAM_ROLE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    success "Environment variables loaded"
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "============================================"
    echo "        RESOURCE CLEANUP CONFIRMATION"
    echo "============================================"
    echo
    echo "This will delete the following resources:"
    echo "  • MediaConnect Flows: ${FLOW_NAME_PRIMARY}, ${FLOW_NAME_BACKUP}"
    echo "  • MediaLive Channel: ${MEDIALIVE_CHANNEL_NAME}"
    echo "  • MediaPackage Channel: ${MEDIAPACKAGE_CHANNEL_ID}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo "  • CloudWatch Alarms and Log Groups"
    echo
    echo "⚠️  This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to stop broadcasting pipeline
stop_pipeline() {
    log "Stopping broadcasting pipeline..."
    
    # Stop MediaLive channel if it exists and is running
    if [[ -n "${MEDIALIVE_CHANNEL_ID:-}" ]]; then
        local channel_state=$(aws medialive describe-channel \
            --channel-id "${MEDIALIVE_CHANNEL_ID}" \
            --query 'State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$channel_state" == "RUNNING" ]]; then
            log "Stopping MediaLive channel..."
            aws medialive stop-channel --channel-id "${MEDIALIVE_CHANNEL_ID}" > /dev/null
            
            # Wait for channel to stop
            log "Waiting for MediaLive channel to stop..."
            aws medialive wait channel-stopped --channel-id "${MEDIALIVE_CHANNEL_ID}"
            success "MediaLive channel stopped"
        elif [[ "$channel_state" != "NOT_FOUND" ]]; then
            log "MediaLive channel is already stopped (state: $channel_state)"
        fi
    fi
    
    # Stop MediaConnect flows
    if [[ -n "${PRIMARY_FLOW_ARN:-}" ]]; then
        local flow_status=$(aws mediaconnect describe-flow \
            --flow-arn "${PRIMARY_FLOW_ARN}" \
            --query 'Flow.Status' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$flow_status" == "ACTIVE" ]]; then
            log "Stopping primary MediaConnect flow..."
            aws mediaconnect stop-flow --flow-arn "${PRIMARY_FLOW_ARN}" > /dev/null
            success "Primary MediaConnect flow stopped"
        elif [[ "$flow_status" != "NOT_FOUND" ]]; then
            log "Primary MediaConnect flow is already stopped (status: $flow_status)"
        fi
    fi
    
    if [[ -n "${BACKUP_FLOW_ARN:-}" ]]; then
        local flow_status=$(aws mediaconnect describe-flow \
            --flow-arn "${BACKUP_FLOW_ARN}" \
            --query 'Flow.Status' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$flow_status" == "ACTIVE" ]]; then
            log "Stopping backup MediaConnect flow..."
            aws mediaconnect stop-flow --flow-arn "${BACKUP_FLOW_ARN}" > /dev/null
            success "Backup MediaConnect flow stopped"
        elif [[ "$flow_status" != "NOT_FOUND" ]]; then
            log "Backup MediaConnect flow is already stopped (status: $flow_status)"
        fi
    fi
    
    success "Broadcasting pipeline stopped"
}

# Function to delete MediaPackage resources
delete_mediapackage_resources() {
    log "Deleting MediaPackage resources..."
    
    # Delete MediaPackage origin endpoint
    if aws mediapackage describe-origin-endpoint --id "${MEDIAPACKAGE_CHANNEL_ID}-hls" &> /dev/null; then
        log "Deleting MediaPackage origin endpoint..."
        aws mediapackage delete-origin-endpoint --id "${MEDIAPACKAGE_CHANNEL_ID}-hls" > /dev/null
        success "MediaPackage origin endpoint deleted"
    else
        log "MediaPackage origin endpoint not found or already deleted"
    fi
    
    # Delete MediaPackage channel
    if aws mediapackage describe-channel --id "${MEDIAPACKAGE_CHANNEL_ID}" &> /dev/null; then
        log "Deleting MediaPackage channel..."
        aws mediapackage delete-channel --id "${MEDIAPACKAGE_CHANNEL_ID}" > /dev/null
        success "MediaPackage channel deleted"
    else
        log "MediaPackage channel not found or already deleted"
    fi
}

# Function to delete MediaLive resources
delete_medialive_resources() {
    log "Deleting MediaLive resources..."
    
    # Delete MediaLive channel
    if [[ -n "${MEDIALIVE_CHANNEL_ID:-}" ]]; then
        if aws medialive describe-channel --channel-id "${MEDIALIVE_CHANNEL_ID}" &> /dev/null; then
            log "Deleting MediaLive channel..."
            aws medialive delete-channel --channel-id "${MEDIALIVE_CHANNEL_ID}" > /dev/null
            success "MediaLive channel deleted"
        else
            log "MediaLive channel not found or already deleted"
        fi
    fi
    
    # Delete MediaLive inputs
    if [[ -n "${PRIMARY_INPUT_ID:-}" ]]; then
        if aws medialive describe-input --input-id "${PRIMARY_INPUT_ID}" &> /dev/null; then
            log "Deleting primary MediaLive input..."
            aws medialive delete-input --input-id "${PRIMARY_INPUT_ID}" > /dev/null
            success "Primary MediaLive input deleted"
        else
            log "Primary MediaLive input not found or already deleted"
        fi
    fi
    
    if [[ -n "${BACKUP_INPUT_ID:-}" ]]; then
        if aws medialive describe-input --input-id "${BACKUP_INPUT_ID}" &> /dev/null; then
            log "Deleting backup MediaLive input..."
            aws medialive delete-input --input-id "${BACKUP_INPUT_ID}" > /dev/null
            success "Backup MediaLive input deleted"
        else
            log "Backup MediaLive input not found or already deleted"
        fi
    fi
}

# Function to delete MediaConnect flows
delete_mediaconnect_flows() {
    log "Deleting MediaConnect flows..."
    
    # Delete primary flow
    if [[ -n "${PRIMARY_FLOW_ARN:-}" ]]; then
        if aws mediaconnect describe-flow --flow-arn "${PRIMARY_FLOW_ARN}" &> /dev/null; then
            log "Deleting primary MediaConnect flow..."
            aws mediaconnect delete-flow --flow-arn "${PRIMARY_FLOW_ARN}" > /dev/null
            success "Primary MediaConnect flow deleted"
        else
            log "Primary MediaConnect flow not found or already deleted"
        fi
    fi
    
    # Delete backup flow
    if [[ -n "${BACKUP_FLOW_ARN:-}" ]]; then
        if aws mediaconnect describe-flow --flow-arn "${BACKUP_FLOW_ARN}" &> /dev/null; then
            log "Deleting backup MediaConnect flow..."
            aws mediaconnect delete-flow --flow-arn "${BACKUP_FLOW_ARN}" > /dev/null
            success "Backup MediaConnect flow deleted"
        else
            log "Backup MediaConnect flow not found or already deleted"
        fi
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarms_to_delete=(
        "${FLOW_NAME_PRIMARY}-source-errors"
        "${MEDIALIVE_CHANNEL_NAME}-input-errors"
    )
    
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm"; then
            log "Deleting CloudWatch alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm" > /dev/null
            success "CloudWatch alarm deleted: $alarm"
        else
            log "CloudWatch alarm not found: $alarm"
        fi
    done
    
    # Delete log groups
    local log_groups=(
        "/aws/mediaconnect/${FLOW_NAME_PRIMARY}"
        "/aws/mediaconnect/${FLOW_NAME_BACKUP}"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            log "Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" > /dev/null
            success "Log group deleted: $log_group"
        else
            log "Log group not found: $log_group"
        fi
    done
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Check if IAM role exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log "Detaching policies from IAM role..."
        
        # Detach managed policies
        local policies=(
            "arn:aws:iam::aws:policy/MediaLiveFullAccess"
            "arn:aws:iam::aws:policy/MediaConnectFullAccess"
            "arn:aws:iam::aws:policy/MediaPackageFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            if aws iam list-attached-role-policies --role-name "${IAM_ROLE_NAME}" --query 'AttachedPolicies[?PolicyArn==`'$policy'`]' --output text | grep -q "$policy"; then
                log "Detaching policy: $policy"
                aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn "$policy"
                success "Policy detached: $policy"
            else
                log "Policy not attached: $policy"
            fi
        done
        
        # Delete IAM role
        log "Deleting IAM role..."
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" > /dev/null
        success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        log "IAM role not found or already deleted: ${IAM_ROLE_NAME}"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/medialive-channel-config.json"
        "/tmp/monitor-flows.sh"
        "$ENVIRONMENT_FILE"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed temporary file: $file"
        fi
    done
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check MediaConnect flows
    if [[ -n "${PRIMARY_FLOW_ARN:-}" ]] && aws mediaconnect describe-flow --flow-arn "${PRIMARY_FLOW_ARN}" &> /dev/null; then
        error "Primary MediaConnect flow still exists"
        ((cleanup_errors++))
    fi
    
    if [[ -n "${BACKUP_FLOW_ARN:-}" ]] && aws mediaconnect describe-flow --flow-arn "${BACKUP_FLOW_ARN}" &> /dev/null; then
        error "Backup MediaConnect flow still exists"
        ((cleanup_errors++))
    fi
    
    # Check MediaLive channel
    if [[ -n "${MEDIALIVE_CHANNEL_ID:-}" ]] && aws medialive describe-channel --channel-id "${MEDIALIVE_CHANNEL_ID}" &> /dev/null; then
        error "MediaLive channel still exists"
        ((cleanup_errors++))
    fi
    
    # Check MediaPackage channel
    if aws mediapackage describe-channel --id "${MEDIAPACKAGE_CHANNEL_ID}" &> /dev/null; then
        error "MediaPackage channel still exists"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        error "IAM role still exists"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        success "All resources successfully cleaned up"
        return 0
    else
        error "Some resources may not have been cleaned up completely"
        return 1
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo
    echo "================================================="
    echo "           CLEANUP SUMMARY"
    echo "================================================="
    echo
    echo "The following resources have been deleted:"
    echo "  ✅ MediaConnect Flows: ${FLOW_NAME_PRIMARY}, ${FLOW_NAME_BACKUP}"
    echo "  ✅ MediaLive Channel: ${MEDIALIVE_CHANNEL_NAME}"
    echo "  ✅ MediaPackage Channel: ${MEDIAPACKAGE_CHANNEL_ID}"
    echo "  ✅ IAM Role: ${IAM_ROLE_NAME}"
    echo "  ✅ CloudWatch Alarms and Log Groups"
    echo "  ✅ Temporary Files"
    echo
    echo "⚠️  Please verify in the AWS Console that all resources"
    echo "   have been properly deleted to avoid unexpected charges."
    echo
    echo "================================================="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    error "Cleanup process encountered an error."
    error "Some resources may not have been fully cleaned up."
    error "Please check the AWS Console and manually remove any remaining resources."
    exit 1
}

# Main cleanup function
main() {
    echo "============================================"
    echo "AWS Live Event Broadcasting Cleanup"
    echo "============================================"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    confirm_cleanup
    
    log "Starting resource cleanup..."
    
    stop_pipeline
    delete_mediapackage_resources
    delete_medialive_resources
    delete_mediaconnect_flows
    delete_cloudwatch_resources
    delete_iam_resources
    cleanup_temp_files
    
    # Verify cleanup was successful
    if verify_cleanup; then
        show_cleanup_summary
        success "Cleanup completed successfully!"
    else
        warn "Cleanup completed with some warnings. Please verify manually."
    fi
}

# Run main function with all arguments
main "$@"