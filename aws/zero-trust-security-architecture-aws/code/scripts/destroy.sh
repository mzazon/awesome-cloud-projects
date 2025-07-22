#!/bin/bash

# Zero Trust Security Architecture Cleanup Script
# This script removes all resources created by the zero trust deployment
# Author: AWS Recipes Team
# Version: 1.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Zero Trust Security Architecture Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deleted without making changes
    -v, --verbose          Enable verbose logging
    -r, --region REGION    AWS region (default: from AWS CLI config)
    -p, --prefix PREFIX    Resource prefix used during deployment (required)
    -f, --force           Skip confirmation prompts (dangerous)
    --preserve-data       Keep S3 buckets and their data
    --preserve-logs       Keep CloudWatch logs and Config history

EXAMPLES:
    $0 --prefix zero-trust-a1b2c3
    $0 --dry-run --prefix zero-trust-a1b2c3
    $0 --force --prefix zero-trust-a1b2c3 --preserve-data

WARNINGS:
    - This script will DELETE all zero trust security resources
    - Data in S3 buckets will be permanently lost (unless --preserve-data)
    - CloudWatch logs will be deleted (unless --preserve-logs)
    - Security Hub findings history will be lost
    - This action cannot be undone

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Administrative permissions for all services used
    - Resource prefix from original deployment

EOF
}

# Default values
DRY_RUN=false
VERBOSE=false
FORCE=false
PRESERVE_DATA=false
PRESERVE_LOGS=false
PREFIX=""
CUSTOM_REGION=""

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            -r|--region)
                CUSTOM_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --preserve-data)
                PRESERVE_DATA=true
                shift
                ;;
            --preserve-logs)
                PRESERVE_LOGS=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ${AWS_CLI_VERSION:0:1} != "2" ]]; then
        error "AWS CLI v2 is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check prefix parameter
    if [[ -z "$PREFIX" ]]; then
        error "Resource prefix is required. Use --prefix option."
        error "This should be the same prefix used during deployment."
        exit 1
    fi
    
    success "Prerequisites validated"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region
    if [[ -n "$CUSTOM_REGION" ]]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set derived variables based on prefix
    export ZERO_TRUST_PREFIX="$PREFIX"
    export SECURITY_ROLE_NAME="${ZERO_TRUST_PREFIX}-security-role"
    export COMPLIANCE_ROLE_NAME="${ZERO_TRUST_PREFIX}-compliance-role"
    export MONITORING_ROLE_NAME="${ZERO_TRUST_PREFIX}-monitoring-role"
    export SECURITY_LOGS_BUCKET="${ZERO_TRUST_PREFIX}-security-logs-${AWS_ACCOUNT_ID}"
    export SECURE_DATA_BUCKET="${ZERO_TRUST_PREFIX}-secure-data-${AWS_ACCOUNT_ID}"
    
    # Try to load environment variables from deployment
    if [[ -f "/tmp/zero-trust-vars.env" ]]; then
        log "Loading environment variables from deployment..."
        source /tmp/zero-trust-vars.env
    fi
    
    log "Environment initialized:"
    log "  Region: $AWS_REGION"
    log "  Account: $AWS_ACCOUNT_ID"
    log "  Prefix: $ZERO_TRUST_PREFIX"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] $description"
        log "[DRY-RUN] Command: $cmd"
    else
        log "$description"
        if [[ "$VERBOSE" == "true" ]]; then
            log "Executing: $cmd"
        fi
        
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warning "Command failed but continuing: $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Confirm destructive operations
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    warning "=========================================="
    warning "DESTRUCTIVE OPERATION WARNING"
    warning "=========================================="
    warning "This will DELETE the following resources:"
    warning "- Security Hub configuration and findings"
    warning "- GuardDuty detector and findings"
    warning "- AWS Config recorder and rules"
    warning "- IAM roles and policies"
    warning "- VPC and network resources"
    warning "- KMS keys (scheduled for deletion)"
    if [[ "$PRESERVE_DATA" == "false" ]]; then
        warning "- S3 buckets and ALL DATA"
    fi
    if [[ "$PRESERVE_LOGS" == "false" ]]; then
        warning "- CloudWatch logs and monitoring data"
    fi
    warning "- SNS topics and subscriptions"
    warning ""
    warning "Prefix: $ZERO_TRUST_PREFIX"
    warning "Region: $AWS_REGION"
    warning "Account: $AWS_ACCOUNT_ID"
    warning "=========================================="
    echo
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Remove Lambda functions and local files
cleanup_lambda_functions() {
    log "Cleaning up Lambda functions and local files..."
    
    # Delete Lambda function (may not exist in all deployments)
    execute_command "aws lambda delete-function \
        --function-name \"${ZERO_TRUST_PREFIX}-session-verification\"" \
        "Deleting session verification Lambda function" true
    
    # Clean up local files
    execute_command "rm -f /tmp/session-verification.py /tmp/session-verification.zip" \
        "Removing local Lambda files" true
    
    execute_command "rm -f /tmp/zero-trust-policy.json /tmp/abac-policy.json" \
        "Removing policy files" true
    
    execute_command "rm -f /tmp/zero-trust-vars.env" \
        "Removing environment variables file" true
    
    success "Lambda functions and files cleaned up"
}

# Disable Security Hub and GuardDuty
cleanup_security_services() {
    log "Cleaning up Security Hub and GuardDuty..."
    
    # Get GuardDuty detector ID
    DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo "None")
    
    if [[ "$DETECTOR_ID" != "None" ]] && [[ -n "$DETECTOR_ID" ]]; then
        # Delete GuardDuty threat intel sets
        THREAT_INTEL_SETS=$(aws guardduty list-threat-intel-sets \
            --detector-id "$DETECTOR_ID" \
            --query 'ThreatIntelSetIds[]' --output text 2>/dev/null || echo "")
        
        for set_id in $THREAT_INTEL_SETS; do
            execute_command "aws guardduty delete-threat-intel-set \
                --detector-id \"$DETECTOR_ID\" \
                --threat-intel-set-id \"$set_id\"" \
                "Deleting threat intel set: $set_id" true
        done
        
        # Delete GuardDuty detector
        execute_command "aws guardduty delete-detector \
            --detector-id \"$DETECTOR_ID\"" \
            "Deleting GuardDuty detector" true
    fi
    
    # Disable Security Hub standards
    execute_command "aws securityhub batch-disable-standards \
        --standards-subscription-arns \
        \"arn:aws:securityhub:$AWS_REGION:$AWS_ACCOUNT_ID:subscription/aws-foundational-security/v/1.0.0\" \
        \"arn:aws:securityhub:$AWS_REGION:$AWS_ACCOUNT_ID:subscription/cis-aws-foundations-benchmark/v/1.2.0\"" \
        "Disabling Security Hub standards" true
    
    # Delete Security Hub insights
    INSIGHT_ARNS=$(aws securityhub get-insights \
        --query 'Insights[?contains(Name, `Zero Trust`)].InsightArn' \
        --output text 2>/dev/null || echo "")
    
    for insight_arn in $INSIGHT_ARNS; do
        execute_command "aws securityhub delete-insight \
            --insight-arn \"$insight_arn\"" \
            "Deleting Security Hub insight: $insight_arn" true
    done
    
    # Disable Security Hub
    execute_command "aws securityhub disable-security-hub" \
        "Disabling Security Hub" true
    
    success "Security services cleaned up"
}

# Remove AWS Config resources
cleanup_aws_config() {
    log "Cleaning up AWS Config resources..."
    
    # Stop Config recorder
    execute_command "aws configservice stop-configuration-recorder \
        --configuration-recorder-name zero-trust-config-recorder" \
        "Stopping Config recorder" true
    
    # Delete Config rules
    execute_command "aws configservice delete-config-rule \
        --config-rule-name zero-trust-mfa-enabled" \
        "Deleting MFA Config rule" true
    
    execute_command "aws configservice delete-config-rule \
        --config-rule-name zero-trust-s3-bucket-ssl-requests-only" \
        "Deleting SSL Config rule" true
    
    # Delete remediation configurations
    execute_command "aws configservice delete-remediation-configuration \
        --config-rule-name zero-trust-mfa-enabled" \
        "Deleting Config remediation" true
    
    # Delete Config recorder and delivery channel
    execute_command "aws configservice delete-configuration-recorder \
        --configuration-recorder-name zero-trust-config-recorder" \
        "Deleting Config recorder" true
    
    execute_command "aws configservice delete-delivery-channel \
        --delivery-channel-name zero-trust-config-channel" \
        "Deleting Config delivery channel" true
    
    success "AWS Config resources cleaned up"
}

# Remove network resources
cleanup_network_resources() {
    log "Cleaning up network resources..."
    
    # Get VPC ID if not already set
    if [[ -z "${VPC_ID:-}" ]]; then
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${ZERO_TRUST_PREFIX}-vpc" \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "None")
    fi
    
    if [[ "$VPC_ID" != "None" ]] && [[ -n "$VPC_ID" ]]; then
        # Delete VPC endpoints
        VPC_ENDPOINT_IDS=$(aws ec2 describe-vpc-endpoints \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'VpcEndpoints[*].VpcEndpointId' --output text 2>/dev/null || echo "")
        
        for endpoint_id in $VPC_ENDPOINT_IDS; do
            execute_command "aws ec2 delete-vpc-endpoint \
                --vpc-endpoint-ids \"$endpoint_id\"" \
                "Deleting VPC endpoint: $endpoint_id" true
        done
        
        # Get security group ID if not already set
        if [[ -z "${ZERO_TRUST_SG:-}" ]]; then
            ZERO_TRUST_SG=$(aws ec2 describe-security-groups \
                --filters "Name=group-name,Values=${ZERO_TRUST_PREFIX}-zero-trust-sg" \
                --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
        fi
        
        # Delete security group
        if [[ "$ZERO_TRUST_SG" != "None" ]] && [[ -n "$ZERO_TRUST_SG" ]]; then
            execute_command "aws ec2 delete-security-group \
                --group-id \"$ZERO_TRUST_SG\"" \
                "Deleting security group" true
        fi
        
        # Delete subnets
        SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[*].SubnetId' --output text 2>/dev/null || echo "")
        
        for subnet_id in $SUBNET_IDS; do
            execute_command "aws ec2 delete-subnet \
                --subnet-id \"$subnet_id\"" \
                "Deleting subnet: $subnet_id" true
        done
        
        # Delete VPC
        execute_command "aws ec2 delete-vpc \
            --vpc-id \"$VPC_ID\"" \
            "Deleting VPC" true
    fi
    
    success "Network resources cleaned up"
}

# Remove IAM roles and policies
cleanup_iam_resources() {
    log "Cleaning up IAM roles and policies..."
    
    # Get policy ARNs
    ZERO_TRUST_POLICY_ARN=$(aws iam list-policies \
        --scope Local \
        --query "Policies[?PolicyName=='${ZERO_TRUST_PREFIX}-boundary-policy'].Arn" \
        --output text 2>/dev/null || echo "")
    
    ABAC_POLICY_ARN=$(aws iam list-policies \
        --scope Local \
        --query "Policies[?PolicyName=='${ZERO_TRUST_PREFIX}-abac-policy'].Arn" \
        --output text 2>/dev/null || echo "")
    
    # Detach policies from roles before deletion
    ROLES_TO_CHECK=(
        "${ZERO_TRUST_PREFIX}-conditional-access-role"
        "${ZERO_TRUST_PREFIX}-config-role"
        "$SECURITY_ROLE_NAME"
    )
    
    for role_name in "${ROLES_TO_CHECK[@]}"; do
        # List and detach managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            execute_command "aws iam detach-role-policy \
                --role-name \"$role_name\" \
                --policy-arn \"$policy_arn\"" \
                "Detaching policy from role: $role_name" true
        done
        
        # Delete role
        execute_command "aws iam delete-role \
            --role-name \"$role_name\"" \
            "Deleting IAM role: $role_name" true
    done
    
    # Delete custom policies
    if [[ -n "$ZERO_TRUST_POLICY_ARN" ]]; then
        execute_command "aws iam delete-policy \
            --policy-arn \"$ZERO_TRUST_POLICY_ARN\"" \
            "Deleting zero trust boundary policy" true
    fi
    
    if [[ -n "$ABAC_POLICY_ARN" ]]; then
        execute_command "aws iam delete-policy \
            --policy-arn \"$ABAC_POLICY_ARN\"" \
            "Deleting ABAC policy" true
    fi
    
    success "IAM resources cleaned up"
}

# Remove S3 buckets and KMS resources
cleanup_data_resources() {
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        warning "Preserving S3 buckets and data as requested"
        return 0
    fi
    
    log "Cleaning up S3 buckets and KMS resources..."
    
    # Empty and delete S3 buckets
    BUCKETS_TO_DELETE=(
        "$SECURITY_LOGS_BUCKET"
        "$SECURE_DATA_BUCKET"
    )
    
    for bucket in "${BUCKETS_TO_DELETE[@]}"; do
        # Check if bucket exists
        if aws s3 ls "s3://$bucket" &>/dev/null; then
            # Empty bucket (including versioned objects)
            execute_command "aws s3api delete-objects \
                --bucket \"$bucket\" \
                --delete \"\$(aws s3api list-object-versions \
                    --bucket \"$bucket\" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')\"" \
                "Emptying versioned objects from bucket: $bucket" true
            
            execute_command "aws s3 rm \"s3://$bucket\" --recursive" \
                "Emptying bucket: $bucket" true
            
            # Delete bucket
            execute_command "aws s3api delete-bucket \
                --bucket \"$bucket\"" \
                "Deleting bucket: $bucket" true
        fi
    done
    
    # Get KMS key ID
    if [[ -z "${KMS_KEY_ID:-}" ]]; then
        KMS_KEY_ID=$(aws kms describe-key \
            --key-id "alias/${ZERO_TRUST_PREFIX}-key" \
            --query 'KeyMetadata.KeyId' --output text 2>/dev/null || echo "None")
    fi
    
    if [[ "$KMS_KEY_ID" != "None" ]] && [[ -n "$KMS_KEY_ID" ]]; then
        # Delete KMS key alias
        execute_command "aws kms delete-alias \
            --alias-name \"alias/${ZERO_TRUST_PREFIX}-key\"" \
            "Deleting KMS key alias" true
        
        # Schedule KMS key for deletion
        execute_command "aws kms schedule-key-deletion \
            --key-id \"$KMS_KEY_ID\" \
            --pending-window-in-days 7" \
            "Scheduling KMS key for deletion (7 days)" true
    fi
    
    success "Data resources cleaned up"
}

# Remove monitoring resources
cleanup_monitoring_resources() {
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        warning "Preserving CloudWatch logs as requested"
    else
        log "Cleaning up monitoring resources..."
        
        # Delete CloudWatch dashboard
        execute_command "aws cloudwatch delete-dashboards \
            --dashboard-names \"${ZERO_TRUST_PREFIX}-security-dashboard\"" \
            "Deleting CloudWatch dashboard" true
        
        # Delete CloudWatch alarms
        execute_command "aws cloudwatch delete-alarms \
            --alarm-names \"${ZERO_TRUST_PREFIX}-failed-logins\"" \
            "Deleting CloudWatch alarms" true
        
        # Delete CloudWatch log groups
        execute_command "aws logs delete-log-group \
            --log-group-name \"/aws/zero-trust/${ZERO_TRUST_PREFIX}\"" \
            "Deleting CloudWatch log group" true
        
        execute_command "aws logs delete-log-group \
            --log-group-name \"/aws/zero-trust/${ZERO_TRUST_PREFIX}/sessions\"" \
            "Deleting session log group" true
    fi
    
    # Delete SNS topic and subscriptions
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${ZERO_TRUST_PREFIX}-security-alerts"
    
    execute_command "aws sns delete-topic \
        --topic-arn \"$SNS_TOPIC_ARN\"" \
        "Deleting SNS topic" true
    
    # Delete SSM document
    execute_command "aws ssm delete-document \
        --name \"${ZERO_TRUST_PREFIX}-session-preferences\"" \
        "Deleting SSM document" true
    
    success "Monitoring resources cleaned up"
}

# Remove IAM Identity Center resources
cleanup_identity_center() {
    log "Cleaning up IAM Identity Center resources..."
    
    # Get Identity Center instance ARN
    INSTANCE_ARN=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "None")
    
    if [[ "$INSTANCE_ARN" != "None" ]] && [[ -n "$INSTANCE_ARN" ]]; then
        # Get permission set ARN
        PERMISSION_SET_ARN=$(aws sso-admin list-permission-sets \
            --instance-arn "$INSTANCE_ARN" \
            --query 'PermissionSets[0]' --output text 2>/dev/null || echo "None")
        
        if [[ "$PERMISSION_SET_ARN" != "None" ]] && [[ -n "$PERMISSION_SET_ARN" ]]; then
            # Get permission set details to verify it's ours
            PERMISSION_SET_NAME=$(aws sso-admin describe-permission-set \
                --instance-arn "$INSTANCE_ARN" \
                --permission-set-arn "$PERMISSION_SET_ARN" \
                --query 'PermissionSet.Name' --output text 2>/dev/null || echo "")
            
            if [[ "$PERMISSION_SET_NAME" == "ZeroTrustSecurityAdmin" ]]; then
                # Detach managed policies
                execute_command "aws sso-admin detach-managed-policy-from-permission-set \
                    --instance-arn \"$INSTANCE_ARN\" \
                    --permission-set-arn \"$PERMISSION_SET_ARN\" \
                    --managed-policy-arn arn:aws:iam::aws:policy/SecurityAudit" \
                    "Detaching SecurityAudit policy from permission set" true
                
                # Delete permission set
                execute_command "aws sso-admin delete-permission-set \
                    --instance-arn \"$INSTANCE_ARN\" \
                    --permission-set-arn \"$PERMISSION_SET_ARN\"" \
                    "Deleting zero trust permission set" true
            fi
        fi
    fi
    
    success "Identity Center resources cleaned up"
}

# Create cleanup summary
create_cleanup_summary() {
    log "Creating cleanup summary..."
    
    cat > /tmp/zero-trust-cleanup-summary.txt << EOF
Zero Trust Security Architecture Cleanup Summary
==============================================

Cleanup Date: $(date)
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID
Resource Prefix: $ZERO_TRUST_PREFIX

Resources Removed:
- Security Hub: Disabled with all standards and insights
- GuardDuty: Detector and threat intel sets deleted
- AWS Config: Recorder, rules, and delivery channel removed
- IAM Identity Center: Zero trust permission set deleted
- IAM Roles: All zero trust roles and policies removed
- Network Security: VPC, subnets, and security groups deleted
- KMS Keys: Scheduled for deletion (7-day window)
- Monitoring: CloudWatch dashboards, alarms, and logs removed
- SNS Topics: Security alert topics deleted

Data Preservation:
- S3 Data: $(if [[ "$PRESERVE_DATA" == "true" ]]; then echo "PRESERVED"; else echo "DELETED"; fi)
- CloudWatch Logs: $(if [[ "$PRESERVE_LOGS" == "true" ]]; then echo "PRESERVED"; else echo "DELETED"; fi)

Important Notes:
- KMS keys are scheduled for deletion in 7 days
- You can cancel KMS key deletion if needed
- Identity Center may still be enabled (requires manual disable)
- Some service-linked roles may remain (normal behavior)

$(if [[ "$PRESERVE_DATA" == "true" ]]; then
cat << EOF2

Preserved S3 Buckets:
- Security Logs: $SECURITY_LOGS_BUCKET
- Secure Data: $SECURE_DATA_BUCKET

To manually delete preserved buckets:
aws s3 rb s3://$SECURITY_LOGS_BUCKET --force
aws s3 rb s3://$SECURE_DATA_BUCKET --force
EOF2
fi)

$(if [[ "$PRESERVE_LOGS" == "true" ]]; then
cat << EOF3

Preserved Log Groups:
- /aws/zero-trust/${ZERO_TRUST_PREFIX}
- /aws/zero-trust/${ZERO_TRUST_PREFIX}/sessions

To manually delete preserved logs:
aws logs delete-log-group --log-group-name "/aws/zero-trust/${ZERO_TRUST_PREFIX}"
EOF3
fi)

Cleanup completed successfully.

EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp /tmp/zero-trust-cleanup-summary.txt ./zero-trust-cleanup-summary.txt
        success "Cleanup summary saved to: ./zero-trust-cleanup-summary.txt"
    else
        cat /tmp/zero-trust-cleanup-summary.txt
    fi
}

# Main cleanup function
main() {
    echo "=============================================="
    echo "Zero Trust Security Architecture Cleanup"
    echo "=============================================="
    echo
    
    parse_args "$@"
    validate_prerequisites
    initialize_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No resources will be deleted"
        echo
    else
        confirm_destruction
    fi
    
    # Execute cleanup steps in reverse order of creation
    cleanup_lambda_functions
    cleanup_monitoring_resources
    cleanup_data_resources
    cleanup_network_resources
    cleanup_iam_resources
    cleanup_identity_center
    cleanup_aws_config
    cleanup_security_services
    create_cleanup_summary
    
    echo
    echo "=============================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN COMPLETED - No resources were deleted"
        log "Run without --dry-run to perform actual cleanup"
    else
        success "ZERO TRUST SECURITY ARCHITECTURE CLEANUP COMPLETED"
        if [[ "$PRESERVE_DATA" == "true" ]] || [[ "$PRESERVE_LOGS" == "true" ]]; then
            warning "Some resources were preserved as requested"
        fi
        log "Review the cleanup summary for details"
        log "KMS keys are scheduled for deletion in 7 days"
    fi
    echo "=============================================="
}

# Run main function with all arguments
main "$@"