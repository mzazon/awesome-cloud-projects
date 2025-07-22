#!/bin/bash

# AWS IoT SiteWise Industrial Data Collection - Cleanup Script
# This script safely removes all resources created by the deployment script
# to avoid ongoing charges and clean up the AWS environment

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to find and load state file
load_state_file() {
    # Check if state file is provided as argument
    if [ $# -eq 1 ] && [ -f "$1" ]; then
        STATE_FILE="$1"
        info "Using provided state file: $STATE_FILE"
    else
        # Try to find state file in /tmp
        STATE_FILES=$(find /tmp -name "sitewise-deployment-*.state" 2>/dev/null || true)
        
        if [ -z "$STATE_FILES" ]; then
            error "No state file found. Please provide the state file path as argument."
            error "Usage: $0 [state-file-path]"
            exit 1
        fi
        
        # If multiple state files exist, let user choose
        STATE_FILE_COUNT=$(echo "$STATE_FILES" | wc -l)
        if [ $STATE_FILE_COUNT -gt 1 ]; then
            info "Multiple state files found:"
            echo "$STATE_FILES" | nl
            read -p "Select state file number: " SELECTION
            STATE_FILE=$(echo "$STATE_FILES" | sed -n "${SELECTION}p")
        else
            STATE_FILE="$STATE_FILES"
        fi
        
        if [ ! -f "$STATE_FILE" ]; then
            error "Selected state file does not exist: $STATE_FILE"
            exit 1
        fi
        
        info "Using state file: $STATE_FILE"
    fi
    
    # Load environment variables from state file
    source "$STATE_FILE"
    
    # Verify required variables are loaded
    if [ -z "$AWS_REGION" ] || [ -z "$RANDOM_SUFFIX" ]; then
        error "State file is missing required variables"
        exit 1
    fi
    
    log "State file loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or you don't have valid credentials."
        exit 1
    fi
    
    # Verify region matches
    CURRENT_REGION=$(aws configure get region)
    if [ "$AWS_REGION" != "$CURRENT_REGION" ]; then
        warn "State file region ($AWS_REGION) differs from current AWS CLI region ($CURRENT_REGION)"
        warn "Using state file region: $AWS_REGION"
    fi
    
    log "Prerequisites check completed"
}

# Display resources to be deleted
display_resources() {
    log "Resources to be deleted:"
    info "========================"
    info "AWS Region: ${AWS_REGION}"
    info "Project Name: ${SITEWISE_PROJECT_NAME:-Unknown}"
    info "Asset Model ID: ${ASSET_MODEL_ID:-Not found}"
    info "Asset ID: ${ASSET_ID:-Not found}"
    info "Timestream Database: ${TIMESTREAM_DB_NAME:-Not found}"
    info "CloudWatch Alarm: ${ALARM_NAME:-Not found}"
    info "========================"
    
    # Confirmation prompt
    read -p "Are you sure you want to delete these resources? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Remove CloudWatch resources
cleanup_cloudwatch() {
    log "Cleaning up CloudWatch resources..."
    
    if [ -n "$ALARM_NAME" ]; then
        # Check if alarm exists
        if aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --region "$AWS_REGION" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$ALARM_NAME"; then
            # Delete CloudWatch alarm
            aws cloudwatch delete-alarms \
                --region "$AWS_REGION" \
                --alarm-names "$ALARM_NAME"
            
            if [ $? -eq 0 ]; then
                log "✅ CloudWatch alarm deleted: $ALARM_NAME"
            else
                warn "Failed to delete CloudWatch alarm: $ALARM_NAME"
            fi
        else
            info "CloudWatch alarm not found or already deleted: $ALARM_NAME"
        fi
    else
        info "No CloudWatch alarm to delete"
    fi
    
    # Note: Custom metrics data will expire naturally, no need to delete
    log "CloudWatch cleanup completed"
}

# Remove IoT SiteWise resources
cleanup_sitewise() {
    log "Cleaning up IoT SiteWise resources..."
    
    # Delete asset instance first (if exists)
    if [ -n "$ASSET_ID" ]; then
        # Check if asset exists
        if aws iotsitewise describe-asset --asset-id "$ASSET_ID" --region "$AWS_REGION" &> /dev/null; then
            log "Deleting asset instance: $ASSET_ID"
            aws iotsitewise delete-asset \
                --region "$AWS_REGION" \
                --asset-id "$ASSET_ID"
            
            if [ $? -eq 0 ]; then
                log "Asset deletion initiated: $ASSET_ID"
                
                # Wait for asset to be deleted (with timeout)
                info "Waiting for asset to be deleted..."
                WAIT_COUNT=0
                MAX_WAIT=30
                while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
                    if ! aws iotsitewise describe-asset --asset-id "$ASSET_ID" --region "$AWS_REGION" &> /dev/null; then
                        log "✅ Asset successfully deleted: $ASSET_ID"
                        break
                    fi
                    sleep 10
                    WAIT_COUNT=$((WAIT_COUNT + 1))
                    info "Waiting for asset deletion... ($WAIT_COUNT/$MAX_WAIT)"
                done
                
                if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                    warn "Asset deletion timeout. Asset may still be deleting: $ASSET_ID"
                fi
            else
                warn "Failed to delete asset: $ASSET_ID"
            fi
        else
            info "Asset not found or already deleted: $ASSET_ID"
        fi
    else
        info "No asset to delete"
    fi
    
    # Delete asset model (if exists and no assets are using it)
    if [ -n "$ASSET_MODEL_ID" ]; then
        # Check if asset model exists
        if aws iotsitewise describe-asset-model --asset-model-id "$ASSET_MODEL_ID" --region "$AWS_REGION" &> /dev/null; then
            log "Deleting asset model: $ASSET_MODEL_ID"
            aws iotsitewise delete-asset-model \
                --region "$AWS_REGION" \
                --asset-model-id "$ASSET_MODEL_ID"
            
            if [ $? -eq 0 ]; then
                log "Asset model deletion initiated: $ASSET_MODEL_ID"
                
                # Wait for asset model to be deleted (with timeout)
                info "Waiting for asset model to be deleted..."
                WAIT_COUNT=0
                MAX_WAIT=30
                while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
                    if ! aws iotsitewise describe-asset-model --asset-model-id "$ASSET_MODEL_ID" --region "$AWS_REGION" &> /dev/null; then
                        log "✅ Asset model successfully deleted: $ASSET_MODEL_ID"
                        break
                    fi
                    sleep 10
                    WAIT_COUNT=$((WAIT_COUNT + 1))
                    info "Waiting for asset model deletion... ($WAIT_COUNT/$MAX_WAIT)"
                done
                
                if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
                    warn "Asset model deletion timeout. Asset model may still be deleting: $ASSET_MODEL_ID"
                fi
            else
                warn "Failed to delete asset model: $ASSET_MODEL_ID"
            fi
        else
            info "Asset model not found or already deleted: $ASSET_MODEL_ID"
        fi
    else
        info "No asset model to delete"
    fi
    
    log "IoT SiteWise cleanup completed"
}

# Remove Timestream resources
cleanup_timestream() {
    log "Cleaning up Timestream resources..."
    
    if [ -n "$TIMESTREAM_DB_NAME" ]; then
        # Check if table exists and delete it first
        if aws timestream-write describe-table --database-name "$TIMESTREAM_DB_NAME" --table-name "equipment-metrics" --region "$AWS_REGION" &> /dev/null; then
            log "Deleting Timestream table: equipment-metrics"
            aws timestream-write delete-table \
                --region "$AWS_REGION" \
                --database-name "$TIMESTREAM_DB_NAME" \
                --table-name "equipment-metrics"
            
            if [ $? -eq 0 ]; then
                log "✅ Timestream table deleted: equipment-metrics"
                
                # Wait a moment for table deletion to complete
                sleep 5
            else
                warn "Failed to delete Timestream table: equipment-metrics"
            fi
        else
            info "Timestream table not found or already deleted: equipment-metrics"
        fi
        
        # Check if database exists and delete it
        if aws timestream-write describe-database --database-name "$TIMESTREAM_DB_NAME" --region "$AWS_REGION" &> /dev/null; then
            log "Deleting Timestream database: $TIMESTREAM_DB_NAME"
            aws timestream-write delete-database \
                --region "$AWS_REGION" \
                --database-name "$TIMESTREAM_DB_NAME"
            
            if [ $? -eq 0 ]; then
                log "✅ Timestream database deleted: $TIMESTREAM_DB_NAME"
            else
                warn "Failed to delete Timestream database: $TIMESTREAM_DB_NAME"
            fi
        else
            info "Timestream database not found or already deleted: $TIMESTREAM_DB_NAME"
        fi
    else
        info "No Timestream resources to delete"
    fi
    
    log "Timestream cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    if [ -n "$RANDOM_SUFFIX" ]; then
        rm -f "/tmp/asset-model-${RANDOM_SUFFIX}.id"
        rm -f "/tmp/asset-${RANDOM_SUFFIX}.id"
        
        info "Temporary files removed"
    fi
    
    # Ask user if they want to remove state file
    read -p "Do you want to remove the state file? (yes/no): " REMOVE_STATE
    if [ "$REMOVE_STATE" = "yes" ]; then
        rm -f "$STATE_FILE"
        log "✅ State file removed: $STATE_FILE"
    else
        info "State file preserved: $STATE_FILE"
    fi
    
    log "Local file cleanup completed"
}

# Validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local VALIDATION_ERRORS=0
    
    # Check asset model
    if [ -n "$ASSET_MODEL_ID" ]; then
        if aws iotsitewise describe-asset-model --asset-model-id "$ASSET_MODEL_ID" --region "$AWS_REGION" &> /dev/null; then
            warn "Asset model still exists: $ASSET_MODEL_ID"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        else
            log "✅ Asset model successfully removed"
        fi
    fi
    
    # Check asset instance
    if [ -n "$ASSET_ID" ]; then
        if aws iotsitewise describe-asset --asset-id "$ASSET_ID" --region "$AWS_REGION" &> /dev/null; then
            warn "Asset instance still exists: $ASSET_ID"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        else
            log "✅ Asset instance successfully removed"
        fi
    fi
    
    # Check Timestream database
    if [ -n "$TIMESTREAM_DB_NAME" ]; then
        if aws timestream-write describe-database --database-name "$TIMESTREAM_DB_NAME" --region "$AWS_REGION" &> /dev/null; then
            warn "Timestream database still exists: $TIMESTREAM_DB_NAME"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        else
            log "✅ Timestream database successfully removed"
        fi
    fi
    
    # Check CloudWatch alarm
    if [ -n "$ALARM_NAME" ]; then
        if aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --region "$AWS_REGION" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$ALARM_NAME"; then
            warn "CloudWatch alarm still exists: $ALARM_NAME"
            VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        else
            log "✅ CloudWatch alarm successfully removed"
        fi
    fi
    
    if [ $VALIDATION_ERRORS -eq 0 ]; then
        log "✅ All resources successfully cleaned up"
    else
        warn "$VALIDATION_ERRORS resources may still exist - check manually"
    fi
    
    log "Cleanup validation completed"
}

# Print cleanup summary
print_summary() {
    log "Cleanup Summary:"
    info "=================="
    info "AWS Region: ${AWS_REGION}"
    info "Project Name: ${SITEWISE_PROJECT_NAME:-Unknown}"
    info "=================="
    info ""
    info "Cleanup completed for:"
    info "✅ IoT SiteWise Asset Model and Instance"
    info "✅ Amazon Timestream Database and Table"
    info "✅ CloudWatch Alarms and Metrics"
    info "✅ Local temporary files"
    info ""
    info "Note: Some resources may have data retention periods."
    info "Check your AWS console to verify all resources are removed."
    info ""
    info "If you encounter any issues, check the AWS console manually:"
    info "- IoT SiteWise: https://console.aws.amazon.com/iotsitewise/"
    info "- Timestream: https://console.aws.amazon.com/timestream/"
    info "- CloudWatch: https://console.aws.amazon.com/cloudwatch/"
}

# Main execution
main() {
    log "Starting AWS IoT SiteWise Industrial Data Collection cleanup..."
    
    load_state_file "$@"
    check_prerequisites
    display_resources
    
    # Cleanup in reverse order of creation
    cleanup_cloudwatch
    cleanup_sitewise
    cleanup_timestream
    cleanup_local_files
    
    validate_cleanup
    print_summary
    
    log "Cleanup completed successfully! 🎉"
}

# Handle script interruption
cleanup_on_exit() {
    warn "Script interrupted. Some resources may not have been cleaned up."
    warn "Please run the script again or check AWS console manually."
    exit 1
}

trap cleanup_on_exit INT TERM

# Run main function
main "$@"