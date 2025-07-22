#!/bin/bash

# Amazon QLDB Cleanup Script
# Building ACID-Compliant Distributed Databases with Amazon QLDB
# Author: DevOps Engineer
# Version: 1.0

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
        exit 1
    fi
    
    # Get and display current AWS identity
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
    AWS_USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS User/Role: $AWS_USER_ARN"
    
    log "Prerequisites check completed successfully."
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    STATE_FILE="deployment-state.json"
    
    if [ -f "$STATE_FILE" ]; then
        info "Found deployment state file: $STATE_FILE"
        
        # Load resource names from state file
        export LEDGER_NAME=$(jq -r '.ledger_name // empty' "$STATE_FILE")
        export IAM_ROLE_NAME=$(jq -r '.iam_role_name // empty' "$STATE_FILE")
        export S3_BUCKET_NAME=$(jq -r '.s3_bucket_name // empty' "$STATE_FILE")
        export KINESIS_STREAM_NAME=$(jq -r '.kinesis_stream_name // empty' "$STATE_FILE")
        export AWS_REGION=$(jq -r '.aws_region // empty' "$STATE_FILE")
        export STREAM_ID=$(jq -r '.stream_id // empty' "$STATE_FILE")
        export EXPORT_ID=$(jq -r '.export_id // empty' "$STATE_FILE")
        
        info "Loaded resource information:"
        [ -n "$LEDGER_NAME" ] && info "  Ledger: $LEDGER_NAME"
        [ -n "$IAM_ROLE_NAME" ] && info "  IAM Role: $IAM_ROLE_NAME"
        [ -n "$S3_BUCKET_NAME" ] && info "  S3 Bucket: $S3_BUCKET_NAME"
        [ -n "$KINESIS_STREAM_NAME" ] && info "  Kinesis Stream: $KINESIS_STREAM_NAME"
        [ -n "$AWS_REGION" ] && info "  AWS Region: $AWS_REGION"
        [ -n "$STREAM_ID" ] && info "  Stream ID: $STREAM_ID"
        [ -n "$EXPORT_ID" ] && info "  Export ID: $EXPORT_ID"
        
    else
        warn "No deployment state file found. You will need to provide resource names manually."
        echo ""
        prompt_for_manual_input
    fi
    
    # Set AWS region if not loaded from state
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warn "No region found, using us-east-1"
        fi
    fi
    
    log "Deployment state loaded successfully."
}

# Function to prompt for manual resource input
prompt_for_manual_input() {
    info "Please provide the resource names to clean up:"
    
    read -p "QLDB Ledger name (or press Enter to skip): " LEDGER_NAME
    export LEDGER_NAME
    
    read -p "IAM Role name (or press Enter to skip): " IAM_ROLE_NAME
    export IAM_ROLE_NAME
    
    read -p "S3 Bucket name (or press Enter to skip): " S3_BUCKET_NAME
    export S3_BUCKET_NAME
    
    read -p "Kinesis Stream name (or press Enter to skip): " KINESIS_STREAM_NAME
    export KINESIS_STREAM_NAME
    
    read -p "Journal Stream ID (or press Enter to skip): " STREAM_ID
    export STREAM_ID
    
    read -p "S3 Export ID (or press Enter to skip): " EXPORT_ID
    export EXPORT_ID
}

# Function to confirm cleanup with user
confirm_cleanup() {
    log "Cleanup Confirmation"
    echo "===================="
    echo ""
    warn "This will permanently delete the following resources:"
    
    [ -n "${LEDGER_NAME:-}" ] && echo "  ❌ QLDB Ledger: $LEDGER_NAME"
    [ -n "${IAM_ROLE_NAME:-}" ] && echo "  ❌ IAM Role: $IAM_ROLE_NAME"
    [ -n "${S3_BUCKET_NAME:-}" ] && echo "  ❌ S3 Bucket: $S3_BUCKET_NAME (and all contents)"
    [ -n "${KINESIS_STREAM_NAME:-}" ] && echo "  ❌ Kinesis Stream: $KINESIS_STREAM_NAME"
    [ -n "${STREAM_ID:-}" ] && echo "  ❌ Journal Stream: $STREAM_ID"
    
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    if [ "${FORCE_CLEANUP:-false}" = "true" ]; then
        warn "Force cleanup mode enabled, proceeding without confirmation..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed with cleanup? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        info "Cleanup cancelled by user."
        exit 0
    fi
    
    log "Cleanup confirmed by user."
}

# Function to cancel active journal streams
cancel_journal_streams() {
    if [ -n "${LEDGER_NAME:-}" ] && [ -n "${STREAM_ID:-}" ]; then
        log "Canceling journal streams..."
        
        info "Canceling journal stream: $STREAM_ID"
        if aws qldb cancel-journal-kinesis-stream \
            --ledger-name ${LEDGER_NAME} \
            --stream-id ${STREAM_ID} 2>/dev/null; then
            info "✅ Journal stream cancellation initiated"
            
            # Wait for stream to be canceled
            info "Waiting for stream to be canceled..."
            local max_attempts=30
            local attempt=1
            while [ $attempt -le $max_attempts ]; do
                STREAM_STATUS=$(aws qldb describe-journal-kinesis-stream \
                    --ledger-name ${LEDGER_NAME} \
                    --stream-id ${STREAM_ID} \
                    --query 'Stream.Status' --output text 2>/dev/null || echo "UNKNOWN")
                
                if [ "$STREAM_STATUS" = "CANCELED" ] || [ "$STREAM_STATUS" = "UNKNOWN" ]; then
                    info "✅ Journal stream canceled"
                    break
                elif [ "$STREAM_STATUS" = "CANCELING" ]; then
                    info "Stream is being canceled... (attempt $attempt/$max_attempts)"
                    sleep 10
                    ((attempt++))
                else
                    info "Stream status: $STREAM_STATUS (attempt $attempt/$max_attempts)"
                    sleep 10
                    ((attempt++))
                fi
            done
            
            if [ $attempt -gt $max_attempts ]; then
                warn "Stream did not cancel within expected time, proceeding anyway"
            fi
        else
            warn "Failed to cancel journal stream or stream not found"
        fi
    else
        info "No journal stream to cancel"
    fi
    
    log "Journal stream cancellation completed."
}

# Function to delete S3 export data and bucket
delete_s3_resources() {
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        log "Deleting S3 resources..."
        
        # Check if bucket exists
        if aws s3 ls s3://${S3_BUCKET_NAME} &> /dev/null; then
            info "Deleting all objects in S3 bucket: $S3_BUCKET_NAME"
            if aws s3 rm s3://${S3_BUCKET_NAME} --recursive 2>/dev/null; then
                info "✅ S3 objects deleted"
            else
                warn "Failed to delete some S3 objects"
            fi
            
            info "Deleting S3 bucket: $S3_BUCKET_NAME"
            if aws s3 rb s3://${S3_BUCKET_NAME} 2>/dev/null; then
                info "✅ S3 bucket deleted"
            else
                error "Failed to delete S3 bucket"
                warn "You may need to delete this manually from the AWS Console"
            fi
        else
            info "S3 bucket not found or already deleted"
        fi
    else
        info "No S3 bucket to delete"
    fi
    
    log "S3 cleanup completed."
}

# Function to delete Kinesis stream
delete_kinesis_stream() {
    if [ -n "${KINESIS_STREAM_NAME:-}" ]; then
        log "Deleting Kinesis stream..."
        
        info "Deleting Kinesis stream: $KINESIS_STREAM_NAME"
        if aws kinesis delete-stream \
            --stream-name ${KINESIS_STREAM_NAME} 2>/dev/null; then
            info "✅ Kinesis stream deletion initiated"
            
            # Wait for stream to be deleted
            info "Waiting for Kinesis stream to be deleted..."
            local max_attempts=30
            local attempt=1
            while [ $attempt -le $max_attempts ]; do
                if ! aws kinesis describe-stream \
                    --stream-name ${KINESIS_STREAM_NAME} &> /dev/null; then
                    info "✅ Kinesis stream deleted"
                    break
                else
                    info "Kinesis stream still exists... (attempt $attempt/$max_attempts)"
                    sleep 10
                    ((attempt++))
                fi
            done
            
            if [ $attempt -gt $max_attempts ]; then
                warn "Kinesis stream did not delete within expected time"
            fi
        else
            warn "Failed to delete Kinesis stream or stream not found"
        fi
    else
        info "No Kinesis stream to delete"
    fi
    
    log "Kinesis stream cleanup completed."
}

# Function to delete IAM role and policies
delete_iam_resources() {
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        log "Deleting IAM resources..."
        
        # Delete inline policies first
        info "Deleting IAM role policies"
        if aws iam delete-role-policy \
            --role-name ${IAM_ROLE_NAME} \
            --policy-name QLDBStreamPolicy 2>/dev/null; then
            info "✅ IAM role policy deleted"
        else
            warn "Failed to delete IAM role policy or policy not found"
        fi
        
        # Delete IAM role
        info "Deleting IAM role: $IAM_ROLE_NAME"
        if aws iam delete-role \
            --role-name ${IAM_ROLE_NAME} 2>/dev/null; then
            info "✅ IAM role deleted"
        else
            warn "Failed to delete IAM role or role not found"
        fi
    else
        info "No IAM role to delete"
    fi
    
    log "IAM resources cleanup completed."
}

# Function to delete QLDB ledger
delete_qldb_ledger() {
    if [ -n "${LEDGER_NAME:-}" ]; then
        log "Deleting QLDB ledger..."
        
        # Check if ledger exists
        if aws qldb describe-ledger --name ${LEDGER_NAME} &> /dev/null; then
            # Disable deletion protection first
            info "Disabling deletion protection for ledger: $LEDGER_NAME"
            if aws qldb update-ledger \
                --name ${LEDGER_NAME} \
                --no-deletion-protection 2>/dev/null; then
                info "✅ Deletion protection disabled"
            else
                warn "Failed to disable deletion protection"
            fi
            
            # Wait a moment for the update to take effect
            sleep 5
            
            # Delete the ledger
            info "Deleting QLDB ledger: $LEDGER_NAME"
            if aws qldb delete-ledger \
                --name ${LEDGER_NAME} 2>/dev/null; then
                info "✅ QLDB ledger deletion initiated"
                
                # Wait for ledger to be deleted
                info "Waiting for QLDB ledger to be deleted..."
                local max_attempts=30
                local attempt=1
                while [ $attempt -le $max_attempts ]; do
                    if ! aws qldb describe-ledger \
                        --name ${LEDGER_NAME} &> /dev/null; then
                        info "✅ QLDB ledger deleted"
                        break
                    else
                        info "QLDB ledger still exists... (attempt $attempt/$max_attempts)"
                        sleep 10
                        ((attempt++))
                    fi
                done
                
                if [ $attempt -gt $max_attempts ]; then
                    warn "QLDB ledger did not delete within expected time"
                fi
            else
                error "Failed to delete QLDB ledger"
                warn "You may need to delete this manually from the AWS Console"
            fi
        else
            info "QLDB ledger not found or already deleted"
        fi
    else
        info "No QLDB ledger to delete"
    fi
    
    log "QLDB ledger cleanup completed."
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "qldb-trust-policy.json"
        "qldb-permissions-policy.json"
        "create-tables.sql"
        "accounts.json"
        "transactions.json"
        "kinesis-config.json"
        "s3-export-config.json"
        "current-digest.json"
        "verify-transaction.py"
        "audit-queries.sql"
        "acid-patterns.md"
        "deployment-state.json"
    )
    
    local removed_count=0
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: $file"
            ((removed_count++))
        fi
    done
    
    if [ $removed_count -eq 0 ]; then
        info "No local files to clean up"
    else
        info "✅ Removed $removed_count local files"
    fi
    
    # Clear environment variables
    unset LEDGER_NAME IAM_ROLE_NAME S3_BUCKET_NAME KINESIS_STREAM_NAME STREAM_ID EXPORT_ID
    
    log "Local cleanup completed."
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check if QLDB ledger still exists
    if [ -n "${LEDGER_NAME:-}" ]; then
        if aws qldb describe-ledger --name ${LEDGER_NAME} &> /dev/null; then
            warn "❌ QLDB ledger still exists: $LEDGER_NAME"
            ((cleanup_issues++))
        else
            info "✅ QLDB ledger deleted successfully"
        fi
    fi
    
    # Check if IAM role still exists
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name ${IAM_ROLE_NAME} &> /dev/null; then
            warn "❌ IAM role still exists: $IAM_ROLE_NAME"
            ((cleanup_issues++))
        else
            info "✅ IAM role deleted successfully"
        fi
    fi
    
    # Check if S3 bucket still exists
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        if aws s3 ls s3://${S3_BUCKET_NAME} &> /dev/null; then
            warn "❌ S3 bucket still exists: $S3_BUCKET_NAME"
            ((cleanup_issues++))
        else
            info "✅ S3 bucket deleted successfully"
        fi
    fi
    
    # Check if Kinesis stream still exists
    if [ -n "${KINESIS_STREAM_NAME:-}" ]; then
        if aws kinesis describe-stream --stream-name ${KINESIS_STREAM_NAME} &> /dev/null; then
            warn "❌ Kinesis stream still exists: $KINESIS_STREAM_NAME"
            ((cleanup_issues++))
        else
            info "✅ Kinesis stream deleted successfully"
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "✅ All resources cleaned up successfully!"
    else
        warn "⚠️  $cleanup_issues cleanup issue(s) detected. You may need to manually delete remaining resources."
    fi
    
    log "Cleanup validation completed."
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo ""
    info "Cleanup operations completed for:"
    
    [ -n "${LEDGER_NAME:-}" ] && info "  ✅ QLDB Ledger: $LEDGER_NAME"
    [ -n "${IAM_ROLE_NAME:-}" ] && info "  ✅ IAM Role: $IAM_ROLE_NAME"
    [ -n "${S3_BUCKET_NAME:-}" ] && info "  ✅ S3 Bucket: $S3_BUCKET_NAME"
    [ -n "${KINESIS_STREAM_NAME:-}" ] && info "  ✅ Kinesis Stream: $KINESIS_STREAM_NAME"
    [ -n "${STREAM_ID:-}" ] && info "  ✅ Journal Stream: $STREAM_ID"
    
    echo ""
    info "Local files cleaned up"
    info "Environment variables cleared"
    echo ""
    info "Please verify in the AWS Console that all resources have been removed."
    warn "Check your AWS billing to ensure no unexpected charges are incurred."
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    warn "Some resources may not have been cleaned up completely."
    echo ""
    info "To manually clean up remaining resources:"
    echo ""
    
    [ -n "${LEDGER_NAME:-}" ] && echo "  aws qldb delete-ledger --name ${LEDGER_NAME}"
    [ -n "${IAM_ROLE_NAME:-}" ] && echo "  aws iam delete-role --role-name ${IAM_ROLE_NAME}"
    [ -n "${S3_BUCKET_NAME:-}" ] && echo "  aws s3 rb s3://${S3_BUCKET_NAME} --force"
    [ -n "${KINESIS_STREAM_NAME:-}" ] && echo "  aws kinesis delete-stream --stream-name ${KINESIS_STREAM_NAME}"
    
    echo ""
    info "Or use the AWS Console to delete resources manually."
}

# Main cleanup function
main() {
    log "Starting Amazon QLDB cleanup..."
    
    # Run cleanup steps in reverse order of creation
    check_prerequisites
    load_deployment_state
    confirm_cleanup
    cancel_journal_streams
    delete_s3_resources
    delete_kinesis_stream
    delete_iam_resources
    delete_qldb_ledger
    cleanup_local_files
    validate_cleanup
    display_cleanup_summary
    
    log "Amazon QLDB cleanup completed!"
}

# Cleanup function for script interruption
cleanup_on_error() {
    error "Cleanup interrupted. Some resources may still exist."
    handle_partial_cleanup
    exit 1
}

# Set trap for cleanup on script exit
trap cleanup_on_error ERR INT TERM

# Check for help flag
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Amazon QLDB Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force      Skip confirmation prompts (use with caution)"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "This script removes all Amazon QLDB resources including:"
    echo "  - QLDB Ledger and all data (irreversible)"
    echo "  - IAM roles and policies"
    echo "  - S3 bucket and all exported data"
    echo "  - Kinesis stream and journal streaming"
    echo "  - Local configuration and data files"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI v2 installed and configured"
    echo "  - jq installed for JSON processing"
    echo "  - Appropriate AWS permissions for resource deletion"
    echo ""
    echo "WARNING: This operation is irreversible!"
    echo ""
    exit 0
fi

# Check for force flag
if [ "${1:-}" = "--force" ]; then
    export FORCE_CLEANUP=true
    warn "Force cleanup mode enabled!"
fi

# Run main cleanup
main "$@"