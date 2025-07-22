#!/bin/bash

# Destroy script for Dedicated Hosts License Compliance Recipe
# This script safely removes all resources created by the deploy.sh script
# ensuring proper cleanup order and cost optimization

set -e  # Exit on any error

# Color codes for output
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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log "Prerequisites check completed"
}

# Load deployment state or prompt for resource prefix
load_deployment_state() {
    log "Loading deployment state..."
    
    # Look for deployment state file
    STATE_FILE=$(ls *-deployment-state.json 2>/dev/null | head -1)
    
    if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
        log "Found deployment state file: $STATE_FILE"
        
        # Extract values from state file
        export LICENSE_COMPLIANCE_PREFIX=$(cat "$STATE_FILE" | grep -o '"resource_prefix": "[^"]*"' | cut -d'"' -f4)
        export AWS_REGION=$(cat "$STATE_FILE" | grep -o '"aws_region": "[^"]*"' | cut -d'"' -f4)
        export AWS_ACCOUNT_ID=$(cat "$STATE_FILE" | grep -o '"aws_account_id": "[^"]*"' | cut -d'"' -f4)
        export SNS_TOPIC_ARN=$(cat "$STATE_FILE" | grep -o '"sns_topic_arn": "[^"]*"' | cut -d'"' -f4)
        export WINDOWS_LICENSE_ARN=$(cat "$STATE_FILE" | grep -o '"windows_license_arn": "[^"]*"' | cut -d'"' -f4)
        export ORACLE_LICENSE_ARN=$(cat "$STATE_FILE" | grep -o '"oracle_license_arn": "[^"]*"' | cut -d'"' -f4)
        export WINDOWS_HOST_ID=$(cat "$STATE_FILE" | grep -o '"windows_host_id": "[^"]*"' | cut -d'"' -f4)
        export ORACLE_HOST_ID=$(cat "$STATE_FILE" | grep -o '"oracle_host_id": "[^"]*"' | cut -d'"' -f4)
        
        info "Loaded state from $STATE_FILE"
    else
        warn "No deployment state file found. Manual input required."
        
        # Prompt for resource prefix if not found
        if [[ -z "$LICENSE_COMPLIANCE_PREFIX" ]]; then
            echo -n "Enter the resource prefix used during deployment: "
            read LICENSE_COMPLIANCE_PREFIX
            
            if [[ -z "$LICENSE_COMPLIANCE_PREFIX" ]]; then
                error "Resource prefix is required for cleanup"
                exit 1
            fi
        fi
        
        # Set AWS region
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set. Please configure AWS CLI or set AWS_REGION environment variable."
            exit 1
        fi
        
        # Get AWS account ID
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    info "Cleanup configuration:"
    info "  Resource Prefix: $LICENSE_COMPLIANCE_PREFIX"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account ID: $AWS_ACCOUNT_ID"
}

# Confirmation prompt for destructive operations
confirm_destruction() {
    echo ""
    warn "This will permanently delete all resources with prefix: $LICENSE_COMPLIANCE_PREFIX"
    warn "This action cannot be undone!"
    echo ""
    echo -n "Are you sure you want to continue? (yes/no): "
    read confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warn "Starting cleanup in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

# Stop and terminate any running instances
terminate_instances() {
    log "Terminating BYOL instances..."
    
    # Find instances with BYOL compliance tag
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --filters "Name=tag:BYOLCompliance,Values=true" \
            "Name=instance-state-name,Values=running,stopped,stopping" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$INSTANCE_IDS" && "$INSTANCE_IDS" != "None" ]]; then
        info "Found instances to terminate: $INSTANCE_IDS"
        
        # Stop instances first
        aws ec2 stop-instances --instance-ids $INSTANCE_IDS > /dev/null 2>&1 || true
        
        # Wait for instances to stop (with timeout)
        info "Waiting for instances to stop..."
        timeout 300 aws ec2 wait instance-stopped --instance-ids $INSTANCE_IDS || warn "Timeout waiting for instances to stop"
        
        # Terminate instances
        aws ec2 terminate-instances --instance-ids $INSTANCE_IDS > /dev/null 2>&1 || true
        
        # Wait for termination (with timeout)
        info "Waiting for instances to terminate..."
        timeout 300 aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS || warn "Timeout waiting for instances to terminate"
        
        log "Instances terminated"
    else
        info "No BYOL instances found to terminate"
    fi
}

# Release Dedicated Hosts
release_dedicated_hosts() {
    log "Releasing Dedicated Hosts..."
    
    # Find hosts with our tags
    HOST_IDS=$(aws ec2 describe-hosts \
        --filters "Name=tag:${DEDICATED_HOST_TAG_KEY:-LicenseCompliance},Values=${DEDICATED_HOST_TAG_VALUE:-BYOL-Production}" \
        --query "Hosts[].HostId" \
        --output text 2>/dev/null || echo "")
    
    # Also try to release specific hosts if we have them
    if [[ -n "$WINDOWS_HOST_ID" ]]; then
        HOST_IDS="$HOST_IDS $WINDOWS_HOST_ID"
    fi
    if [[ -n "$ORACLE_HOST_ID" ]]; then
        HOST_IDS="$HOST_IDS $ORACLE_HOST_ID"
    fi
    
    # Remove duplicates and empty values
    HOST_IDS=$(echo $HOST_IDS | tr ' ' '\n' | sort -u | grep -v "^$" | grep -v "None" | tr '\n' ' ')
    
    if [[ -n "$HOST_IDS" ]]; then
        info "Found Dedicated Hosts to release: $HOST_IDS"
        
        for HOST_ID in $HOST_IDS; do
            aws ec2 release-hosts --host-ids "$HOST_ID" > /dev/null 2>&1 || warn "Failed to release host $HOST_ID"
        done
        
        log "Dedicated Hosts released"
    else
        info "No Dedicated Hosts found to release"
    fi
}

# Delete License Manager configurations
delete_license_configurations() {
    log "Deleting License Manager configurations..."
    
    # Find license configurations by prefix
    LICENSE_ARNS=$(aws license-manager list-license-configurations \
        --query "LicenseConfigurations[?starts_with(Name, '${LICENSE_COMPLIANCE_PREFIX}')].LicenseConfigurationArn" \
        --output text 2>/dev/null || echo "")
    
    # Also try specific ARNs if we have them
    if [[ -n "$WINDOWS_LICENSE_ARN" ]]; then
        LICENSE_ARNS="$LICENSE_ARNS $WINDOWS_LICENSE_ARN"
    fi
    if [[ -n "$ORACLE_LICENSE_ARN" ]]; then
        LICENSE_ARNS="$LICENSE_ARNS $ORACLE_LICENSE_ARN"
    fi
    
    # Remove duplicates and empty values
    LICENSE_ARNS=$(echo $LICENSE_ARNS | tr ' ' '\n' | sort -u | grep -v "^$" | tr '\n' ' ')
    
    if [[ -n "$LICENSE_ARNS" ]]; then
        info "Found license configurations to delete: $LICENSE_ARNS"
        
        for ARN in $LICENSE_ARNS; do
            aws license-manager delete-license-configuration \
                --license-configuration-arn "$ARN" > /dev/null 2>&1 || warn "Failed to delete license configuration $ARN"
        done
        
        log "License configurations deleted"
    else
        info "No license configurations found to delete"
    fi
}

# Delete License Manager report generators
delete_license_report_generators() {
    log "Deleting License Manager report generators..."
    
    # Find report generators by prefix
    REPORT_ARNS=$(aws license-manager list-license-manager-report-generators \
        --query "ReportGenerators[?starts_with(ReportGeneratorName, '${LICENSE_COMPLIANCE_PREFIX}')].LicenseManagerReportGeneratorArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$REPORT_ARNS" && "$REPORT_ARNS" != "None" ]]; then
        info "Found report generators to delete: $REPORT_ARNS"
        
        for ARN in $REPORT_ARNS; do
            aws license-manager delete-license-manager-report-generator \
                --license-manager-report-generator-arn "$ARN" > /dev/null 2>&1 || warn "Failed to delete report generator $ARN"
        done
        
        log "License Manager report generators deleted"
    else
        info "No License Manager report generators found to delete"
    fi
}

# Remove AWS Config resources
remove_config_resources() {
    log "Removing AWS Config resources..."
    
    # Stop configuration recorder
    aws configservice stop-configuration-recorder \
        --configuration-recorder-name "${LICENSE_COMPLIANCE_PREFIX}-recorder" \
        > /dev/null 2>&1 || info "Configuration recorder not found or already stopped"
    
    # Delete Config rules
    aws configservice delete-config-rule \
        --config-rule-name "${LICENSE_COMPLIANCE_PREFIX}-host-compliance" \
        > /dev/null 2>&1 || info "Config rule not found"
    
    # Delete delivery channel
    aws configservice delete-delivery-channel \
        --delivery-channel-name "${LICENSE_COMPLIANCE_PREFIX}-delivery-channel" \
        > /dev/null 2>&1 || info "Delivery channel not found"
    
    # Delete configuration recorder
    aws configservice delete-configuration-recorder \
        --configuration-recorder-name "${LICENSE_COMPLIANCE_PREFIX}-recorder" \
        > /dev/null 2>&1 || info "Configuration recorder not found"
    
    log "AWS Config resources removed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms \
        --alarm-names "${LICENSE_COMPLIANCE_PREFIX}-license-utilization" \
        > /dev/null 2>&1 || info "CloudWatch alarm not found"
    
    # Delete CloudWatch dashboard
    aws cloudwatch delete-dashboards \
        --dashboard-names "${LICENSE_COMPLIANCE_PREFIX}-compliance-dashboard" \
        > /dev/null 2>&1 || info "CloudWatch dashboard not found"
    
    log "CloudWatch resources deleted"
}

# Delete Systems Manager resources
delete_ssm_resources() {
    log "Deleting Systems Manager resources..."
    
    # Delete SSM document
    aws ssm delete-document \
        --name "${LICENSE_COMPLIANCE_PREFIX}-license-inventory" \
        > /dev/null 2>&1 || info "SSM document not found"
    
    # Delete SSM associations (if any)
    ASSOCIATION_IDS=$(aws ssm list-associations \
        --query "Associations[?starts_with(Name, '${LICENSE_COMPLIANCE_PREFIX}')].AssociationId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$ASSOCIATION_IDS" && "$ASSOCIATION_IDS" != "None" ]]; then
        for ASSOC_ID in $ASSOCIATION_IDS; do
            aws ssm delete-association \
                --association-id "$ASSOC_ID" > /dev/null 2>&1 || warn "Failed to delete association $ASSOC_ID"
        done
    fi
    
    log "Systems Manager resources deleted"
}

# Delete launch templates
delete_launch_templates() {
    log "Deleting launch templates..."
    
    # Delete launch templates by name
    aws ec2 delete-launch-template \
        --launch-template-name "${LICENSE_COMPLIANCE_PREFIX}-windows-sql" \
        > /dev/null 2>&1 || info "Windows SQL launch template not found"
    
    aws ec2 delete-launch-template \
        --launch-template-name "${LICENSE_COMPLIANCE_PREFIX}-oracle-db" \
        > /dev/null 2>&1 || info "Oracle DB launch template not found"
    
    log "Launch templates deleted"
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Detach policies from Config role
    aws iam detach-role-policy \
        --role-name "${LICENSE_COMPLIANCE_PREFIX}-config-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole \
        > /dev/null 2>&1 || info "Config role policy not attached"
    
    # Delete Config role
    aws iam delete-role \
        --role-name "${LICENSE_COMPLIANCE_PREFIX}-config-role" \
        > /dev/null 2>&1 || info "Config role not found"
    
    # Delete Lambda role (if exists)
    aws iam detach-role-policy \
        --role-name "${LICENSE_COMPLIANCE_PREFIX}-lambda-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        > /dev/null 2>&1 || info "Lambda role policy not attached"
    
    aws iam delete-role \
        --role-name "${LICENSE_COMPLIANCE_PREFIX}-lambda-role" \
        > /dev/null 2>&1 || info "Lambda role not found"
    
    log "IAM roles deleted"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete compliance report function
    aws lambda delete-function \
        --function-name "${LICENSE_COMPLIANCE_PREFIX}-compliance-report" \
        > /dev/null 2>&1 || info "Lambda function not found"
    
    log "Lambda functions deleted"
}

# Delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    # Delete reports bucket
    REPORTS_BUCKET="${LICENSE_COMPLIANCE_PREFIX}-reports-${AWS_ACCOUNT_ID}"
    if aws s3 ls "s3://$REPORTS_BUCKET" > /dev/null 2>&1; then
        aws s3 rb "s3://$REPORTS_BUCKET" --force > /dev/null 2>&1 || warn "Failed to delete reports bucket"
        log "Reports bucket deleted: $REPORTS_BUCKET"
    else
        info "Reports bucket not found: $REPORTS_BUCKET"
    fi
    
    # Delete Config bucket
    CONFIG_BUCKET="${LICENSE_COMPLIANCE_PREFIX}-config-${AWS_ACCOUNT_ID}"
    if aws s3 ls "s3://$CONFIG_BUCKET" > /dev/null 2>&1; then
        aws s3 rb "s3://$CONFIG_BUCKET" --force > /dev/null 2>&1 || warn "Failed to delete Config bucket"
        log "Config bucket deleted: $CONFIG_BUCKET"
    else
        info "Config bucket not found: $CONFIG_BUCKET"
    fi
}

# Delete SNS topics
delete_sns_topics() {
    log "Deleting SNS topics..."
    
    # Find and delete SNS topics by name
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" > /dev/null 2>&1 || info "SNS topic not found"
        log "SNS topic deleted: $SNS_TOPIC_ARN"
    else
        # Try to find by name
        TOPIC_ARN=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${LICENSE_COMPLIANCE_PREFIX}-compliance-alerts')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$TOPIC_ARN" && "$TOPIC_ARN" != "None" ]]; then
            aws sns delete-topic --topic-arn "$TOPIC_ARN" > /dev/null 2>&1 || warn "Failed to delete SNS topic"
            log "SNS topic deleted: $TOPIC_ARN"
        else
            info "SNS topic not found"
        fi
    fi
}

# Remove temporary files and deployment state
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    rm -f /tmp/license-manager-bucket-policy.json
    rm -f /tmp/license-compliance-dashboard.json
    rm -f /tmp/compliance-report-function.py
    rm -f /tmp/compliance-report.zip
    
    # Remove deployment state file
    rm -f *-deployment-state.json
    
    log "Local files cleaned up"
}

# Main cleanup function
main() {
    log "Starting Dedicated Hosts License Compliance cleanup..."
    
    check_prerequisites
    load_deployment_state
    confirm_destruction
    
    # Stop destructive operations first
    terminate_instances
    release_dedicated_hosts
    
    # Remove License Manager resources
    delete_license_configurations
    delete_license_report_generators
    
    # Remove monitoring and compliance resources
    remove_config_resources
    delete_cloudwatch_resources
    delete_ssm_resources
    
    # Remove compute resources
    delete_launch_templates
    delete_lambda_functions
    
    # Remove IAM and storage resources
    delete_iam_roles
    delete_s3_buckets
    delete_sns_topics
    
    # Cleanup local files
    cleanup_local_files
    
    log "Cleanup completed successfully!"
    echo ""
    info "All resources with prefix '$LICENSE_COMPLIANCE_PREFIX' have been removed"
    warn "Please verify in the AWS console that all resources are deleted"
    warn "Some resources may take additional time to fully terminate"
    echo ""
    log "Cleanup Summary:"
    info "  ✓ EC2 instances terminated"
    info "  ✓ Dedicated Hosts released"
    info "  ✓ License Manager configurations deleted"
    info "  ✓ AWS Config resources removed"
    info "  ✓ CloudWatch alarms and dashboards deleted"
    info "  ✓ Systems Manager documents deleted"
    info "  ✓ Launch templates deleted"
    info "  ✓ IAM roles deleted"
    info "  ✓ Lambda functions deleted"
    info "  ✓ S3 buckets deleted"
    info "  ✓ SNS topics deleted"
    info "  ✓ Local files cleaned up"
}

# Run main function
main "$@"