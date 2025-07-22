#!/bin/bash

# Centralized Logging with Amazon OpenSearch Service - Cleanup Script
# This script safely removes all resources created by the centralized logging deployment.
# It includes confirmation prompts and thorough verification of resource deletion.

set -euo pipefail

# Configuration and Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/centralized-logging-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly TIMEOUT_GENERAL=300      # 5 minutes for most operations
readonly TIMEOUT_OPENSEARCH=600   # 10 minutes for OpenSearch deletion

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup incomplete. Some resources may still exist."
    log_error "Please manually check and delete remaining resources to avoid charges."
    exit 1
}

# Resource discovery functions
discover_resources() {
    log "Discovering centralized logging resources..."
    
    # Try to load from environment file if available
    local env_files=(/tmp/centralized-logging-env-*.sh)
    if [[ ${#env_files[@]} -gt 0 && -f "${env_files[0]}" ]]; then
        log "Loading environment from ${env_files[0]}"
        # shellcheck source=/dev/null
        source "${env_files[0]}"
        export DISCOVERED_FROM_FILE=true
    else
        export DISCOVERED_FROM_FILE=false
    fi
    
    # Set AWS region and account if not already set
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error_exit "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        fi
    fi
    
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    export AWS_REGION AWS_ACCOUNT_ID
    
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    
    # Discover resources by pattern if not loaded from environment
    if [[ "$DISCOVERED_FROM_FILE" == "false" ]]; then
        discover_by_pattern
    fi
}

discover_by_pattern() {
    log "Searching for centralized logging resources by pattern..."
    
    # Discover OpenSearch domains
    local opensearch_domains
    opensearch_domains=$(aws opensearch list-domain-names \
        --query 'DomainNames[?starts_with(DomainName, `central-logging-`)].DomainName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$opensearch_domains" ]]; then
        export DISCOVERED_DOMAINS="$opensearch_domains"
        log "Found OpenSearch domains: $DISCOVERED_DOMAINS"
    else
        export DISCOVERED_DOMAINS=""
    fi
    
    # Discover Kinesis streams
    local kinesis_streams
    kinesis_streams=$(aws kinesis list-streams \
        --query 'StreamNames[?starts_with(@, `log-stream-`)]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$kinesis_streams" ]]; then
        export DISCOVERED_KINESIS_STREAMS="$kinesis_streams"
        log "Found Kinesis streams: $DISCOVERED_KINESIS_STREAMS"
    else
        export DISCOVERED_KINESIS_STREAMS=""
    fi
    
    # Discover Firehose delivery streams
    local firehose_streams
    firehose_streams=$(aws firehose list-delivery-streams \
        --query 'DeliveryStreamNames[?starts_with(@, `log-delivery-`)]' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$firehose_streams" ]]; then
        export DISCOVERED_FIREHOSE_STREAMS="$firehose_streams"
        log "Found Firehose streams: $DISCOVERED_FIREHOSE_STREAMS"
    else
        export DISCOVERED_FIREHOSE_STREAMS=""
    fi
    
    # Discover Lambda functions
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `LogProcessor-`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lambda_functions" ]]; then
        export DISCOVERED_LAMBDA_FUNCTIONS="$lambda_functions"
        log "Found Lambda functions: $DISCOVERED_LAMBDA_FUNCTIONS"
    else
        export DISCOVERED_LAMBDA_FUNCTIONS=""
    fi
    
    # Discover S3 buckets
    local s3_buckets
    s3_buckets=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `central-logging-backup-`)].Name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$s3_buckets" ]]; then
        export DISCOVERED_S3_BUCKETS="$s3_buckets"
        log "Found S3 buckets: $DISCOVERED_S3_BUCKETS"
    else
        export DISCOVERED_S3_BUCKETS=""
    fi
    
    # Discover IAM roles
    local iam_roles
    iam_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `OpenSearchServiceRole-`) || contains(RoleName, `LogProcessorLambdaRole-`) || contains(RoleName, `FirehoseDeliveryRole-`) || contains(RoleName, `CWLogsToKinesisRole-`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$iam_roles" ]]; then
        export DISCOVERED_IAM_ROLES="$iam_roles"
        log "Found IAM roles: $DISCOVERED_IAM_ROLES"
    else
        export DISCOVERED_IAM_ROLES=""
    fi
}

check_resources_exist() {
    log "Checking for existing centralized logging resources..."
    
    local resources_found=false
    
    # Check what resources exist
    if [[ -n "${DOMAIN_NAME:-}" ]] || [[ -n "${DISCOVERED_DOMAINS:-}" ]]; then
        log "OpenSearch domains to delete: ${DOMAIN_NAME:-$DISCOVERED_DOMAINS}"
        resources_found=true
    fi
    
    if [[ -n "${KINESIS_STREAM:-}" ]] || [[ -n "${DISCOVERED_KINESIS_STREAMS:-}" ]]; then
        log "Kinesis streams to delete: ${KINESIS_STREAM:-$DISCOVERED_KINESIS_STREAMS}"
        resources_found=true
    fi
    
    if [[ -n "${FIREHOSE_STREAM:-}" ]] || [[ -n "${DISCOVERED_FIREHOSE_STREAMS:-}" ]]; then
        log "Firehose streams to delete: ${FIREHOSE_STREAM:-$DISCOVERED_FIREHOSE_STREAMS}"
        resources_found=true
    fi
    
    if [[ -n "${DISCOVERED_LAMBDA_FUNCTIONS:-}" ]]; then
        log "Lambda functions to delete: $DISCOVERED_LAMBDA_FUNCTIONS"
        resources_found=true
    fi
    
    if [[ -n "${BACKUP_BUCKET:-}" ]] || [[ -n "${DISCOVERED_S3_BUCKETS:-}" ]]; then
        log "S3 buckets to delete: ${BACKUP_BUCKET:-$DISCOVERED_S3_BUCKETS}"
        resources_found=true
    fi
    
    if [[ -n "${DISCOVERED_IAM_ROLES:-}" ]]; then
        log "IAM roles to delete: $DISCOVERED_IAM_ROLES"
        resources_found=true
    fi
    
    if [[ "$resources_found" == "false" ]]; then
        log_warning "No centralized logging resources found to delete."
        exit 0
    fi
}

confirm_deletion() {
    log_warning "=========================================="
    log_warning "DESTRUCTIVE OPERATION WARNING"
    log_warning "=========================================="
    log_warning "This script will permanently delete ALL centralized logging resources."
    log_warning "This action CANNOT be undone."
    log_warning ""
    log_warning "Resources to be deleted:"
    
    # List all resources that will be deleted
    [[ -n "${DOMAIN_NAME:-}${DISCOVERED_DOMAINS:-}" ]] && log_warning "• OpenSearch domains: ${DOMAIN_NAME:-$DISCOVERED_DOMAINS}"
    [[ -n "${KINESIS_STREAM:-}${DISCOVERED_KINESIS_STREAMS:-}" ]] && log_warning "• Kinesis streams: ${KINESIS_STREAM:-$DISCOVERED_KINESIS_STREAMS}"
    [[ -n "${FIREHOSE_STREAM:-}${DISCOVERED_FIREHOSE_STREAMS:-}" ]] && log_warning "• Firehose streams: ${FIREHOSE_STREAM:-$DISCOVERED_FIREHOSE_STREAMS}"
    [[ -n "${DISCOVERED_LAMBDA_FUNCTIONS:-}" ]] && log_warning "• Lambda functions: $DISCOVERED_LAMBDA_FUNCTIONS"
    [[ -n "${BACKUP_BUCKET:-}${DISCOVERED_S3_BUCKETS:-}" ]] && log_warning "• S3 buckets: ${BACKUP_BUCKET:-$DISCOVERED_S3_BUCKETS}"
    [[ -n "${DISCOVERED_IAM_ROLES:-}" ]] && log_warning "• IAM roles: $DISCOVERED_IAM_ROLES"
    
    log_warning ""
    log_warning "⚠️  DATA LOSS WARNING: All log data stored in OpenSearch will be permanently deleted."
    log_warning "⚠️  BILLING WARNING: Ensure this is not a production environment."
    log_warning ""
    
    if [[ "${SKIP_CONFIRMATION:-}" != "true" ]]; then
        echo -n "Type 'DELETE' to confirm resource deletion: "
        read -r confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            log "Deletion cancelled by user."
            exit 0
        fi
        
        echo -n "Are you absolutely sure? Type 'yes' to proceed: "
        read -r final_confirmation
        if [[ "$final_confirmation" != "yes" ]]; then
            log "Deletion cancelled by user."
            exit 0
        fi
    fi
    
    log "User confirmed deletion. Proceeding with resource cleanup..."
}

# Resource deletion functions
delete_subscription_filters() {
    log "Removing CloudWatch Logs subscription filters..."
    
    # Get all log groups and try to remove our subscription filters
    local log_groups
    log_groups=$(aws logs describe-log-groups \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    local deleted_filters=0
    for log_group in $log_groups; do
        # Try to delete filters with our naming pattern
        for pattern in "CentralLoggingFilter-" "CentralLoggingTestFilter-" "TestFilter-"; do
            local filter_names
            filter_names=$(aws logs describe-subscription-filters \
                --log-group-name "$log_group" \
                --query "subscriptionFilters[?starts_with(filterName, \`$pattern\`)].filterName" \
                --output text 2>/dev/null || echo "")
            
            for filter_name in $filter_names; do
                if aws logs delete-subscription-filter \
                    --log-group-name "$log_group" \
                    --filter-name "$filter_name" > /dev/null 2>&1; then
                    log "Deleted filter $filter_name from $log_group"
                    ((deleted_filters++))
                fi
            done
        done
    done
    
    # Delete test log group if it exists
    if aws logs delete-log-group \
        --log-group-name "/aws/test/centralized-logging" > /dev/null 2>&1; then
        log "Deleted test log group"
        ((deleted_filters++))
    fi
    
    if [[ $deleted_filters -gt 0 ]]; then
        log_success "Removed $deleted_filters subscription filters and log groups"
    else
        log_warning "No subscription filters found to remove"
    fi
}

delete_lambda_functions() {
    log "Deleting Lambda functions and event source mappings..."
    
    # Use discovered functions or specific function name
    local functions_to_delete=""
    if [[ -n "${DISCOVERED_LAMBDA_FUNCTIONS:-}" ]]; then
        functions_to_delete="$DISCOVERED_LAMBDA_FUNCTIONS"
    elif [[ -n "${RANDOM_STRING:-}" ]]; then
        functions_to_delete="LogProcessor-${RANDOM_STRING}"
    fi
    
    if [[ -z "$functions_to_delete" ]]; then
        log_warning "No Lambda functions found to delete"
        return 0
    fi
    
    for function_name in $functions_to_delete; do
        log "Processing Lambda function: $function_name"
        
        # Delete event source mappings first
        local event_source_mappings
        event_source_mappings=$(aws lambda list-event-source-mappings \
            --function-name "$function_name" \
            --query 'EventSourceMappings[].UUID' \
            --output text 2>/dev/null || echo "")
        
        for uuid in $event_source_mappings; do
            if aws lambda delete-event-source-mapping \
                --uuid "$uuid" > /dev/null 2>&1; then
                log "Deleted event source mapping: $uuid"
            fi
        done
        
        # Delete the Lambda function
        if aws lambda delete-function \
            --function-name "$function_name" > /dev/null 2>&1; then
            log_success "Deleted Lambda function: $function_name"
        else
            log_warning "Failed to delete Lambda function: $function_name"
        fi
    done
}

delete_firehose_streams() {
    log "Deleting Kinesis Data Firehose delivery streams..."
    
    # Use discovered streams or specific stream name
    local streams_to_delete=""
    if [[ -n "${DISCOVERED_FIREHOSE_STREAMS:-}" ]]; then
        streams_to_delete="$DISCOVERED_FIREHOSE_STREAMS"
    elif [[ -n "${FIREHOSE_STREAM:-}" ]]; then
        streams_to_delete="$FIREHOSE_STREAM"
    fi
    
    if [[ -z "$streams_to_delete" ]]; then
        log_warning "No Firehose streams found to delete"
        return 0
    fi
    
    for stream_name in $streams_to_delete; do
        if aws firehose delete-delivery-stream \
            --delivery-stream-name "$stream_name" > /dev/null 2>&1; then
            log_success "Deleted Firehose stream: $stream_name"
        else
            log_warning "Failed to delete Firehose stream: $stream_name"
        fi
    done
}

delete_kinesis_streams() {
    log "Deleting Kinesis Data Streams..."
    
    # Use discovered streams or specific stream name
    local streams_to_delete=""
    if [[ -n "${DISCOVERED_KINESIS_STREAMS:-}" ]]; then
        streams_to_delete="$DISCOVERED_KINESIS_STREAMS"
    elif [[ -n "${KINESIS_STREAM:-}" ]]; then
        streams_to_delete="$KINESIS_STREAM"
    fi
    
    if [[ -z "$streams_to_delete" ]]; then
        log_warning "No Kinesis streams found to delete"
        return 0
    fi
    
    for stream_name in $streams_to_delete; do
        if aws kinesis delete-stream \
            --stream-name "$stream_name" > /dev/null 2>&1; then
            log_success "Deleted Kinesis stream: $stream_name"
        else
            log_warning "Failed to delete Kinesis stream: $stream_name"
        fi
    done
}

delete_opensearch_domains() {
    log "Deleting Amazon OpenSearch Service domains..."
    
    # Use discovered domains or specific domain name
    local domains_to_delete=""
    if [[ -n "${DISCOVERED_DOMAINS:-}" ]]; then
        domains_to_delete="$DISCOVERED_DOMAINS"
    elif [[ -n "${DOMAIN_NAME:-}" ]]; then
        domains_to_delete="$DOMAIN_NAME"
    fi
    
    if [[ -z "$domains_to_delete" ]]; then
        log_warning "No OpenSearch domains found to delete"
        return 0
    fi
    
    for domain_name in $domains_to_delete; do
        log "Deleting OpenSearch domain: $domain_name"
        
        if aws opensearch delete-domain \
            --domain-name "$domain_name" > /dev/null 2>&1; then
            log_success "OpenSearch domain deletion initiated: $domain_name"
            
            # Wait for deletion to complete
            log "Waiting for OpenSearch domain deletion to complete..."
            local attempts=0
            local max_attempts=60  # 10 minutes maximum
            
            while [ $attempts -lt $max_attempts ]; do
                if ! aws opensearch describe-domain \
                    --domain-name "$domain_name" > /dev/null 2>&1; then
                    log_success "OpenSearch domain deleted: $domain_name"
                    break
                fi
                
                log "Domain still deleting... (attempt $((attempts + 1))/$max_attempts)"
                sleep 10
                ((attempts++))
            done
            
            if [ $attempts -eq $max_attempts ]; then
                log_warning "OpenSearch domain deletion taking longer than expected: $domain_name"
            fi
        else
            log_warning "Failed to delete OpenSearch domain: $domain_name"
        fi
    done
}

delete_s3_buckets() {
    log "Deleting S3 backup buckets..."
    
    # Use discovered buckets or specific bucket name
    local buckets_to_delete=""
    if [[ -n "${DISCOVERED_S3_BUCKETS:-}" ]]; then
        buckets_to_delete="$DISCOVERED_S3_BUCKETS"
    elif [[ -n "${BACKUP_BUCKET:-}" ]]; then
        buckets_to_delete="$BACKUP_BUCKET"
    fi
    
    if [[ -z "$buckets_to_delete" ]]; then
        log_warning "No S3 buckets found to delete"
        return 0
    fi
    
    for bucket_name in $buckets_to_delete; do
        log "Processing S3 bucket: $bucket_name"
        
        # Empty the bucket first
        if aws s3 rm "s3://$bucket_name" --recursive > /dev/null 2>&1; then
            log "Emptied S3 bucket: $bucket_name"
        else
            log_warning "Failed to empty S3 bucket or bucket was already empty: $bucket_name"
        fi
        
        # Delete the bucket
        if aws s3api delete-bucket \
            --bucket "$bucket_name" > /dev/null 2>&1; then
            log_success "Deleted S3 bucket: $bucket_name"
        else
            log_warning "Failed to delete S3 bucket: $bucket_name"
        fi
    done
}

delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    # Use discovered roles or specific role names
    local roles_to_delete=""
    if [[ -n "${DISCOVERED_IAM_ROLES:-}" ]]; then
        roles_to_delete="$DISCOVERED_IAM_ROLES"
    elif [[ -n "${RANDOM_STRING:-}" ]]; then
        roles_to_delete="OpenSearchServiceRole-${RANDOM_STRING} LogProcessorLambdaRole-${RANDOM_STRING} FirehoseDeliveryRole-${RANDOM_STRING} CWLogsToKinesisRole-${RANDOM_STRING}"
    fi
    
    if [[ -z "$roles_to_delete" ]]; then
        log_warning "No IAM roles found to delete"
        return 0
    fi
    
    for role_name in $roles_to_delete; do
        log "Processing IAM role: $role_name"
        
        # Delete attached inline policies first
        local policy_names
        policy_names=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $policy_names; do
            if aws iam delete-role-policy \
                --role-name "$role_name" \
                --policy-name "$policy_name" > /dev/null 2>&1; then
                log "Deleted policy $policy_name from role $role_name"
            fi
        done
        
        # Delete the role
        if aws iam delete-role \
            --role-name "$role_name" > /dev/null 2>&1; then
            log_success "Deleted IAM role: $role_name"
        else
            log_warning "Failed to delete IAM role: $role_name"
        fi
    done
}

cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove temporary files created during deployment
    local temp_files=(
        "opensearch-trust-policy.json"
        "lambda-trust-policy.json"
        "firehose-trust-policy.json"
        "cwlogs-trust-policy.json"
        "opensearch-domain-config.json"
        "firehose-config.json"
        "lambda-execution-policy.json"
        "firehose-service-policy.json"
        "cwlogs-kinesis-policy.json"
        "log_processor.py"
        "log_processor.zip"
    )
    
    local cleaned_files=0
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            ((cleaned_files++))
        fi
    done
    
    # Remove environment files
    local env_files=(/tmp/centralized-logging-env-*.sh)
    if [[ ${#env_files[@]} -gt 0 ]]; then
        for env_file in "${env_files[@]}"; do
            if [[ -f "$env_file" ]]; then
                rm -f "$env_file"
                log "Removed environment file: $env_file"
                ((cleaned_files++))
            fi
        done
    fi
    
    if [[ $cleaned_files -gt 0 ]]; then
        log_success "Cleaned up $cleaned_files local files"
    else
        log "No local files to clean up"
    fi
}

verify_deletion() {
    log "Verifying resource deletion..."
    
    local remaining_resources=0
    
    # Check OpenSearch domains
    if [[ -n "${DOMAIN_NAME:-}${DISCOVERED_DOMAINS:-}" ]]; then
        local domains="${DOMAIN_NAME:-$DISCOVERED_DOMAINS}"
        for domain in $domains; do
            if aws opensearch describe-domain \
                --domain-name "$domain" > /dev/null 2>&1; then
                log_warning "OpenSearch domain still exists: $domain"
                ((remaining_resources++))
            fi
        done
    fi
    
    # Check Kinesis streams
    if [[ -n "${KINESIS_STREAM:-}${DISCOVERED_KINESIS_STREAMS:-}" ]]; then
        local streams="${KINESIS_STREAM:-$DISCOVERED_KINESIS_STREAMS}"
        for stream in $streams; do
            if aws kinesis describe-stream \
                --stream-name "$stream" > /dev/null 2>&1; then
                log_warning "Kinesis stream still exists: $stream"
                ((remaining_resources++))
            fi
        done
    fi
    
    # Check Firehose streams
    if [[ -n "${FIREHOSE_STREAM:-}${DISCOVERED_FIREHOSE_STREAMS:-}" ]]; then
        local streams="${FIREHOSE_STREAM:-$DISCOVERED_FIREHOSE_STREAMS}"
        for stream in $streams; do
            if aws firehose describe-delivery-stream \
                --delivery-stream-name "$stream" > /dev/null 2>&1; then
                log_warning "Firehose stream still exists: $stream"
                ((remaining_resources++))
            fi
        done
    fi
    
    # Check Lambda functions
    if [[ -n "${DISCOVERED_LAMBDA_FUNCTIONS:-}" ]]; then
        for function_name in $DISCOVERED_LAMBDA_FUNCTIONS; do
            if aws lambda get-function \
                --function-name "$function_name" > /dev/null 2>&1; then
                log_warning "Lambda function still exists: $function_name"
                ((remaining_resources++))
            fi
        done
    fi
    
    # Check S3 buckets
    if [[ -n "${BACKUP_BUCKET:-}${DISCOVERED_S3_BUCKETS:-}" ]]; then
        local buckets="${BACKUP_BUCKET:-$DISCOVERED_S3_BUCKETS}"
        for bucket in $buckets; do
            if aws s3api head-bucket \
                --bucket "$bucket" > /dev/null 2>&1; then
                log_warning "S3 bucket still exists: $bucket"
                ((remaining_resources++))
            fi
        done
    fi
    
    # Check IAM roles
    if [[ -n "${DISCOVERED_IAM_ROLES:-}" ]]; then
        for role in $DISCOVERED_IAM_ROLES; do
            if aws iam get-role \
                --role-name "$role" > /dev/null 2>&1; then
                log_warning "IAM role still exists: $role"
                ((remaining_resources++))
            fi
        done
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources successfully deleted"
    else
        log_warning "$remaining_resources resources still exist - they may be in the process of being deleted"
    fi
    
    return $remaining_resources
}

print_deletion_summary() {
    log_success "=========================================="
    log_success "CLEANUP COMPLETED"
    log_success "=========================================="
    log ""
    log "🗑️  Resource Deletion Summary:"
    log "   • CloudWatch Logs subscription filters removed"
    log "   • Lambda functions and event source mappings deleted"
    log "   • Kinesis Data Firehose streams deleted"
    log "   • Kinesis Data Streams deleted"
    log "   • OpenSearch Service domains deleted"
    log "   • S3 backup buckets deleted"
    log "   • IAM roles and policies deleted"
    log "   • Local temporary files cleaned up"
    log ""
    log "📋 Important Notes:"
    log "   • Some resources (like OpenSearch domains) may take additional time to fully delete"
    log "   • Check AWS console to verify all resources are removed"
    log "   • Monitor AWS billing to ensure no unexpected charges"
    log ""
    log "📁 Log Files:"
    log "   • Cleanup log: $LOG_FILE"
    log ""
    log "💰 Cost Impact:"
    log "   • All ongoing charges for centralized logging should stop"
    log "   • Final charges may appear on next billing cycle for partial usage"
    log ""
    
    if verify_deletion; then
        log_success "✅ All centralized logging resources have been successfully removed"
    else
        log_warning "⚠️  Some resources may still be deleting - please verify manually"
    fi
}

# Main cleanup workflow
main() {
    log "=========================================="
    log "Centralized Logging Cleanup Script"
    log "=========================================="
    log "Starting cleanup at $(date)"
    log "Log file: $LOG_FILE"
    
    # Discovery and confirmation
    discover_resources
    check_resources_exist
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_subscription_filters
    delete_lambda_functions
    delete_firehose_streams
    delete_kinesis_streams
    delete_opensearch_domains
    delete_s3_buckets
    delete_iam_roles
    cleanup_local_files
    
    # Summary and verification
    print_deletion_summary
    
    log_success "Cleanup completed successfully!"
    log "Total cleanup time: $SECONDS seconds"
}

# Run main function
main "$@"