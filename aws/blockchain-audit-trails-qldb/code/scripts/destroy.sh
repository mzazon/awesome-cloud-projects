#!/bin/bash

# AWS Blockchain Audit Trails Compliance - Cleanup Script
# This script safely removes all infrastructure resources created for the compliance audit trails solution
# Resources are deleted in reverse order of dependencies to avoid conflicts

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/compliance-audit-destroy-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed on line $1"
    log_error "Some resources may still exist. Check AWS console and log file: ${LOG_FILE}"
    log_error "You may need to manually clean up remaining resources."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
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
    
    # Check required permissions
    log "Checking AWS permissions..."
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    log "Cleaning up as: $(echo "${caller_identity}" | jq -r '.Arn // .UserId' 2>/dev/null || echo "Unknown")"
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved environment file
    if [[ -f "/tmp/compliance-audit-env.sh" ]]; then
        source /tmp/compliance-audit-env.sh
        log "Loaded environment variables from /tmp/compliance-audit-env.sh"
    else
        log_warning "Environment file not found. You may need to provide resource names manually."
        
        # Try to detect current region
        export AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            export AWS_REGION="us-east-1"
            log_warning "No default region found, using us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log "Using AWS Region: ${AWS_REGION}"
    log "Using Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo "=================================================================================="
    echo "                             ⚠️  WARNING ⚠️"
    echo "=================================================================================="
    echo ""
    echo "This script will permanently delete ALL compliance audit infrastructure including:"
    echo ""
    echo "🗑️  Resources to be deleted:"
    echo "   • QLDB Ledger and all immutable audit data"
    echo "   • Lambda functions and IAM roles"
    echo "   • CloudTrail logs and configuration"
    echo "   • S3 bucket and all stored audit reports"
    echo "   • EventBridge rules and targets"
    echo "   • CloudWatch dashboards and alarms"
    echo "   • SNS topics and subscriptions"
    echo "   • Kinesis Data Firehose delivery streams"
    echo "   • Athena workgroups and databases"
    echo ""
    echo "💾 Data Loss Warning:"
    echo "   • All audit records in QLDB will be permanently lost"
    echo "   • CloudTrail logs will be deleted from S3"
    echo "   • Compliance reports and analytics data will be removed"
    echo ""
    echo "🔐 Compliance Impact:"
    echo "   • This action may affect your regulatory compliance posture"
    echo "   • Ensure you have exported any required audit data first"
    echo "   • Consider regulatory retention requirements before proceeding"
    echo ""
    echo "=================================================================================="
    echo ""
    
    # Prompt for confirmation
    read -p "Are you absolutely sure you want to delete ALL compliance audit infrastructure? (type 'DELETE' to confirm): " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Double confirmation for production-like environments
    if [[ "${AWS_REGION}" == "us-east-1" || "${AWS_REGION}" == "us-west-2" || "${AWS_REGION}" == "eu-west-1" ]]; then
        read -p "This appears to be a production region (${AWS_REGION}). Type 'CONFIRM-DELETE' to proceed: " second_confirmation
        
        if [[ "${second_confirmation}" != "CONFIRM-DELETE" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log "User confirmed deletion. Proceeding with cleanup..."
}

# Function to find and delete resources by pattern
find_and_delete_resources() {
    local resource_type=$1
    local pattern=$2
    local delete_command=$3
    
    log "Finding ${resource_type} resources matching pattern: ${pattern}"
    
    case ${resource_type} in
        "lambda")
            aws lambda list-functions --query "Functions[?contains(FunctionName, '${pattern}')].FunctionName" --output text | tr '\t' '\n' | while read -r function_name; do
                if [[ -n "${function_name}" ]]; then
                    log "Deleting Lambda function: ${function_name}"
                    aws lambda delete-function --function-name "${function_name}" || log_warning "Failed to delete Lambda function: ${function_name}"
                fi
            done
            ;;
        "iam-role")
            aws iam list-roles --query "Roles[?contains(RoleName, '${pattern}')].RoleName" --output text | tr '\t' '\n' | while read -r role_name; do
                if [[ -n "${role_name}" ]]; then
                    log "Deleting IAM role: ${role_name}"
                    # Delete attached policies first
                    aws iam list-role-policies --role-name "${role_name}" --query 'PolicyNames' --output text | tr '\t' '\n' | while read -r policy_name; do
                        if [[ -n "${policy_name}" ]]; then
                            aws iam delete-role-policy --role-name "${role_name}" --policy-name "${policy_name}" || true
                        fi
                    done
                    # Detach managed policies
                    aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text | tr '\t' '\n' | while read -r policy_arn; do
                        if [[ -n "${policy_arn}" ]]; then
                            aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}" || true
                        fi
                    done
                    # Delete the role
                    aws iam delete-role --role-name "${role_name}" || log_warning "Failed to delete IAM role: ${role_name}"
                fi
            done
            ;;
        "cloudtrail")
            aws cloudtrail describe-trails --query "trailList[?contains(Name, '${pattern}')].Name" --output text | tr '\t' '\n' | while read -r trail_name; do
                if [[ -n "${trail_name}" ]]; then
                    log "Deleting CloudTrail: ${trail_name}"
                    aws cloudtrail stop-logging --name "${trail_name}" || true
                    aws cloudtrail delete-trail --name "${trail_name}" || log_warning "Failed to delete CloudTrail: ${trail_name}"
                fi
            done
            ;;
        "s3-bucket")
            aws s3api list-buckets --query "Buckets[?contains(Name, '${pattern}')].Name" --output text | tr '\t' '\n' | while read -r bucket_name; do
                if [[ -n "${bucket_name}" ]]; then
                    log "Emptying and deleting S3 bucket: ${bucket_name}"
                    aws s3 rm "s3://${bucket_name}" --recursive || true
                    aws s3api delete-bucket --bucket "${bucket_name}" || log_warning "Failed to delete S3 bucket: ${bucket_name}"
                fi
            done
            ;;
        "qldb")
            aws qldb list-ledgers --query "Ledgers[?contains(Name, '${pattern}')].Name" --output text | tr '\t' '\n' | while read -r ledger_name; do
                if [[ -n "${ledger_name}" ]]; then
                    log "Deleting QLDB ledger: ${ledger_name}"
                    # Disable deletion protection first
                    aws qldb update-ledger --name "${ledger_name}" --no-deletion-protection || true
                    # Wait a moment for the update to take effect
                    sleep 5
                    aws qldb delete-ledger --name "${ledger_name}" || log_warning "Failed to delete QLDB ledger: ${ledger_name}"
                fi
            done
            ;;
    esac
}

# Function to delete Lambda functions and IAM roles
delete_lambda_resources() {
    log "Deleting Lambda functions and IAM roles..."
    
    # Delete specific Lambda function if name is known
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found or already deleted"
        
        # Delete associated IAM role
        local role_name="${LAMBDA_FUNCTION_NAME}-role"
        log "Deleting IAM role: ${role_name}"
        
        # Delete inline policies
        aws iam list-role-policies --role-name "${role_name}" --query 'PolicyNames' --output text 2>/dev/null | tr '\t' '\n' | while read -r policy_name; do
            if [[ -n "${policy_name}" ]]; then
                aws iam delete-role-policy --role-name "${role_name}" --policy-name "${policy_name}" || true
            fi
        done
        
        # Detach managed policies
        aws iam list-attached-role-policies --role-name "${role_name}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n' | while read -r policy_arn; do
            if [[ -n "${policy_arn}" ]]; then
                aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${policy_arn}" || true
            fi
        done
        
        # Delete the role
        aws iam delete-role --role-name "${role_name}" 2>/dev/null || log_warning "IAM role ${role_name} not found or already deleted"
    else
        # Find and delete by pattern
        find_and_delete_resources "lambda" "audit-processor"
        find_and_delete_resources "iam-role" "audit-processor"
    fi
    
    log_success "Lambda and IAM resources cleanup completed"
}

# Function to delete EventBridge rules
delete_eventbridge_resources() {
    log "Deleting EventBridge rules and targets..."
    
    # Delete the specific compliance audit rule
    local rule_name="compliance-audit-rule"
    
    # Remove targets first
    aws events list-targets-by-rule --rule "${rule_name}" --query 'Targets[].Id' --output text 2>/dev/null | tr '\t' '\n' | while read -r target_id; do
        if [[ -n "${target_id}" ]]; then
            aws events remove-targets --rule "${rule_name}" --ids "${target_id}" || true
        fi
    done
    
    # Delete the rule
    aws events delete-rule --name "${rule_name}" 2>/dev/null || log_warning "EventBridge rule ${rule_name} not found or already deleted"
    
    log_success "EventBridge resources cleanup completed"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms --alarm-names "ComplianceAuditErrors" 2>/dev/null || log_warning "CloudWatch alarm ComplianceAuditErrors not found"
    
    # Delete CloudWatch dashboard
    aws cloudwatch delete-dashboards --dashboard-names "ComplianceAuditDashboard" 2>/dev/null || log_warning "CloudWatch dashboard ComplianceAuditDashboard not found"
    
    log_success "CloudWatch resources cleanup completed"
}

# Function to delete CloudTrail
delete_cloudtrail_resources() {
    log "Deleting CloudTrail resources..."
    
    if [[ -n "${CLOUDTRAIL_NAME:-}" ]]; then
        log "Stopping and deleting CloudTrail: ${CLOUDTRAIL_NAME}"
        aws cloudtrail stop-logging --name "${CLOUDTRAIL_NAME}" 2>/dev/null || true
        aws cloudtrail delete-trail --name "${CLOUDTRAIL_NAME}" 2>/dev/null || log_warning "CloudTrail ${CLOUDTRAIL_NAME} not found or already deleted"
    else
        # Find and delete by pattern
        find_and_delete_resources "cloudtrail" "compliance-audit-trail"
    fi
    
    log_success "CloudTrail resources cleanup completed"
}

# Function to delete SNS resources
delete_sns_resources() {
    log "Deleting SNS topics..."
    
    # Find and delete SNS topics related to compliance audit
    aws sns list-topics --query 'Topics[].TopicArn' --output text | tr '\t' '\n' | grep -i "compliance-audit-alerts" | while read -r topic_arn; do
        if [[ -n "${topic_arn}" ]]; then
            log "Deleting SNS topic: ${topic_arn}"
            aws sns delete-topic --topic-arn "${topic_arn}" || log_warning "Failed to delete SNS topic: ${topic_arn}"
        fi
    done
    
    log_success "SNS resources cleanup completed"
}

# Function to delete Kinesis Data Firehose
delete_kinesis_firehose_resources() {
    log "Deleting Kinesis Data Firehose resources..."
    
    # Delete Kinesis Data Firehose delivery stream
    aws firehose delete-delivery-stream --delivery-stream-name "compliance-audit-stream" 2>/dev/null || log_warning "Kinesis Data Firehose compliance-audit-stream not found"
    
    # Delete Firehose IAM role
    local firehose_role="compliance-firehose-role"
    
    # Delete inline policies
    aws iam list-role-policies --role-name "${firehose_role}" --query 'PolicyNames' --output text 2>/dev/null | tr '\t' '\n' | while read -r policy_name; do
        if [[ -n "${policy_name}" ]]; then
            aws iam delete-role-policy --role-name "${firehose_role}" --policy-name "${policy_name}" || true
        fi
    done
    
    # Delete the role
    aws iam delete-role --role-name "${firehose_role}" 2>/dev/null || log_warning "Firehose IAM role ${firehose_role} not found"
    
    log_success "Kinesis Data Firehose resources cleanup completed"
}

# Function to delete Athena resources
delete_athena_resources() {
    log "Deleting Athena resources..."
    
    # Delete Athena workgroup
    aws athena delete-work-group --work-group "compliance-audit-workgroup" --recursive-delete-option 2>/dev/null || log_warning "Athena workgroup compliance-audit-workgroup not found"
    
    log_success "Athena resources cleanup completed"
}

# Function to delete QLDB ledger
delete_qldb_resources() {
    log "Deleting QLDB ledger..."
    
    if [[ -n "${LEDGER_NAME:-}" ]]; then
        log "Disabling deletion protection and deleting QLDB ledger: ${LEDGER_NAME}"
        
        # Disable deletion protection first
        aws qldb update-ledger --name "${LEDGER_NAME}" --no-deletion-protection 2>/dev/null || log_warning "Could not disable deletion protection for ${LEDGER_NAME}"
        
        # Wait for the update to take effect
        sleep 10
        
        # Delete QLDB ledger
        aws qldb delete-ledger --name "${LEDGER_NAME}" 2>/dev/null || log_warning "QLDB ledger ${LEDGER_NAME} not found or already deleted"
    else
        # Find and delete by pattern
        find_and_delete_resources "qldb" "compliance-audit-ledger"
    fi
    
    log_success "QLDB resources cleanup completed"
}

# Function to delete S3 bucket
delete_s3_resources() {
    log "Deleting S3 bucket and contents..."
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        log "Emptying and deleting S3 bucket: ${S3_BUCKET_NAME}"
        
        # Empty the bucket first
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || log_warning "Could not empty S3 bucket ${S3_BUCKET_NAME}"
        
        # Delete object versions if versioning is enabled
        aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" --output json 2>/dev/null | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | select(.Key != null) | "--key \"\(.Key)\" --version-id \"\(.VersionId)\""' 2>/dev/null | \
        while read -r delete_args; do
            if [[ -n "${delete_args}" ]]; then
                eval "aws s3api delete-object --bucket ${S3_BUCKET_NAME} ${delete_args}" || true
            fi
        done
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null || log_warning "S3 bucket ${S3_BUCKET_NAME} not found or already deleted"
    else
        # Find and delete by pattern
        find_and_delete_resources "s3-bucket" "compliance-audit-bucket"
    fi
    
    log_success "S3 resources cleanup completed"
}

# Function to remove temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-custom-policy.json
    rm -f /tmp/firehose-trust-policy.json
    rm -f /tmp/firehose-policy.json
    rm -f /tmp/audit_processor.py
    rm -f /tmp/audit_processor.zip
    rm -f /tmp/setup_qldb_tables.py
    rm -f /tmp/generate_compliance_report.py
    
    # Optionally remove environment file
    read -p "Remove environment file /tmp/compliance-audit-env.sh? (y/N): " remove_env
    if [[ "${remove_env}" =~ ^[Yy]$ ]]; then
        rm -f /tmp/compliance-audit-env.sh
        log "Environment file removed"
    else
        log "Environment file preserved at /tmp/compliance-audit-env.sh"
    fi
    
    log_success "Temporary files cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "🎉 Compliance audit infrastructure cleanup completed!"
    
    echo ""
    echo "=================================================================================="
    echo "                          CLEANUP SUMMARY"
    echo "=================================================================================="
    echo ""
    echo "✅ Resources Deleted:"
    echo "   • Lambda functions and IAM roles"
    echo "   • EventBridge rules and targets"
    echo "   • CloudWatch dashboards and alarms"
    echo "   • CloudTrail logging configuration"
    echo "   • SNS topics and subscriptions"
    echo "   • Kinesis Data Firehose delivery streams"
    echo "   • Athena workgroups and databases"
    echo "   • QLDB ledger and all audit data"
    echo "   • S3 bucket and all contents"
    echo ""
    echo "📝 Important Notes:"
    echo "   • All audit records have been permanently deleted"
    echo "   • CloudTrail logs have been removed from S3"
    echo "   • Compliance reporting infrastructure is no longer available"
    echo "   • Any manual email subscriptions to SNS may need cleanup"
    echo ""
    echo "🔍 Manual Verification Recommended:"
    echo "   • Check AWS Console for any remaining resources"
    echo "   • Verify no unexpected charges in billing"
    echo "   • Review IAM roles for any orphaned policies"
    echo "   • Check CloudWatch logs for any remaining log groups"
    echo ""
    echo "📋 Cleanup Log: ${LOG_FILE}"
    echo "=================================================================================="
}

# Main cleanup function
main() {
    log "🗑️  Starting cleanup of Blockchain Audit Trails Compliance infrastructure..."
    log "Cleanup log: ${LOG_FILE}"
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Delete resources in reverse order of dependencies
    delete_lambda_resources
    delete_eventbridge_resources
    delete_cloudwatch_resources
    delete_cloudtrail_resources
    delete_sns_resources
    delete_kinesis_firehose_resources
    delete_athena_resources
    delete_qldb_resources
    delete_s3_resources
    cleanup_temp_files
    
    display_cleanup_summary
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi