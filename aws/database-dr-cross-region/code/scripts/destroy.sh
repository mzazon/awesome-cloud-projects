#!/bin/bash

#################################################################################
# Database Disaster Recovery with Read Replicas - Destroy Script
#
# This script safely removes all resources created by the disaster recovery
# deployment, including RDS instances, Lambda functions, SNS topics, and
# monitoring components.
#
# Author: AWS Recipe Generator
# Version: 1.0
# Last Updated: 2025-07-12
#################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'        # Secure Internal Field Separator

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="/tmp/dr-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_NAME="${0##*/}"

#################################################################################
# Logging Functions
#################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}"
}

#################################################################################
# Utility Functions
#################################################################################

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Confirmation prompt with safety check
confirm_destruction() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY enabled - skipping confirmation for $resource_type"
        return 0
    fi
    
    echo
    echo -e "${RED}⚠️  DESTRUCTIVE ACTION WARNING ⚠️${NC}"
    echo "You are about to delete: $resource_type"
    echo "Resource: $resource_name"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            log_info "User confirmed deletion of $resource_type: $resource_name"
            return 0
            ;;
        *)
            log_info "User cancelled deletion of $resource_type: $resource_name"
            return 1
            ;;
    esac
}

# Wait for resource deletion with timeout
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    local max_attempts="${4:-20}"
    local delay="${5:-30}"
    
    log_info "Waiting for $resource_type $resource_id to be deleted..."
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts - Checking $resource_type deletion status..."
        
        case "$resource_type" in
            "rds")
                if ! aws rds describe-db-instances \
                    --region "$region" \
                    --db-instance-identifier "$resource_id" >/dev/null 2>&1; then
                    log_success "$resource_type $resource_id has been deleted"
                    return 0
                fi
                ;;
            *)
                log_error "Unknown resource type for deletion check: $resource_type"
                return 1
                ;;
        esac
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Timeout waiting for $resource_type $resource_id to be deleted"
            return 1
        fi
        
        log_info "Resource still exists, waiting $delay seconds..."
        sleep "$delay"
        ((attempt++))
    done
}

# Safe resource deletion with error handling
safe_delete() {
    local command="$1"
    local resource_name="$2"
    local ignore_errors="${3:-false}"
    
    log_info "Executing: $command"
    
    if eval "$command" 2>/dev/null; then
        log_success "Successfully deleted: $resource_name"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "Failed to delete $resource_name (ignoring error)"
            return 0
        else
            log_error "Failed to delete: $resource_name"
            return 1
        fi
    fi
}

#################################################################################
# Validation Functions
#################################################################################

validate_prerequisites() {
    log_info "Validating prerequisites for destruction..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Run 'aws configure' or set environment variables."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from local file first
    if [[ -f "./dr-deployment-info.json" ]]; then
        log_info "Loading deployment info from local file"
        local deployment_file="./dr-deployment-info.json"
    elif [[ -n "${S3_BUCKET:-}" ]] && aws s3 ls "s3://$S3_BUCKET/deployment-info.json" >/dev/null 2>&1; then
        log_info "Loading deployment info from S3"
        aws s3 cp "s3://$S3_BUCKET/deployment-info.json" /tmp/deployment-info.json
        local deployment_file="/tmp/deployment-info.json"
    else
        log_warning "Deployment info file not found. Using environment variables or defaults."
        return 1
    fi
    
    # Extract resource information using jq if available, otherwise use basic parsing
    if command_exists jq; then
        export AWS_ACCOUNT_ID=$(jq -r '.deployment_info.aws_account_id' "$deployment_file" 2>/dev/null || echo "${AWS_ACCOUNT_ID:-}")
        export PRIMARY_REGION=$(jq -r '.deployment_info.primary_region' "$deployment_file" 2>/dev/null || echo "${PRIMARY_REGION:-us-east-1}")
        export DR_REGION=$(jq -r '.deployment_info.dr_region' "$deployment_file" 2>/dev/null || echo "${DR_REGION:-us-west-2}")
        export DB_INSTANCE_ID=$(jq -r '.deployment_info.resources.primary_db_instance_id' "$deployment_file" 2>/dev/null || echo "${DB_INSTANCE_ID:-}")
        export DB_REPLICA_ID=$(jq -r '.deployment_info.resources.dr_replica_instance_id' "$deployment_file" 2>/dev/null || echo "${DB_REPLICA_ID:-}")
        export S3_BUCKET=$(jq -r '.deployment_info.resources.s3_config_bucket' "$deployment_file" 2>/dev/null || echo "${S3_BUCKET:-}")
        export SNS_TOPIC_PRIMARY=$(jq -r '.deployment_info.resources.sns_primary_topic' "$deployment_file" 2>/dev/null || echo "${SNS_TOPIC_PRIMARY:-}")
        export SNS_TOPIC_DR=$(jq -r '.deployment_info.resources.sns_dr_topic' "$deployment_file" 2>/dev/null || echo "${SNS_TOPIC_DR:-}")
        export LAMBDA_FUNCTION_PRIMARY=$(jq -r '.deployment_info.resources.lambda_coordinator' "$deployment_file" 2>/dev/null || echo "${LAMBDA_FUNCTION_PRIMARY:-}")
        export LAMBDA_FUNCTION_DR=$(jq -r '.deployment_info.resources.lambda_promoter' "$deployment_file" 2>/dev/null || echo "${LAMBDA_FUNCTION_DR:-}")
        export RANDOM_SUFFIX=$(jq -r '.deployment_info.resources.random_suffix' "$deployment_file" 2>/dev/null || echo "${RANDOM_SUFFIX:-}")
    else
        log_warning "jq not available. Using environment variables for resource identification."
    fi
    
    log_success "Deployment information loaded"
    return 0
}

setup_environment() {
    log_info "Setting up environment for destruction..."
    
    # Get AWS account ID if not set
    if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
        export AWS_ACCOUNT_ID
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    # Set default regions if not provided
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export DR_REGION="${DR_REGION:-us-west-2}"
    
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Primary Region: $PRIMARY_REGION"
    log_info "DR Region: $DR_REGION"
    
    # If RANDOM_SUFFIX is not set, try to derive it from resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]] && [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        RANDOM_SUFFIX=$(echo "$DB_INSTANCE_ID" | grep -o '[^-]*$' || echo "")
        export RANDOM_SUFFIX
        log_info "Derived RANDOM_SUFFIX: $RANDOM_SUFFIX"
    fi
    
    # Set resource names if not already set
    export DB_INSTANCE_ID="${DB_INSTANCE_ID:-primary-db-${RANDOM_SUFFIX}}"
    export DB_REPLICA_ID="${DB_REPLICA_ID:-dr-replica-${RANDOM_SUFFIX}}"
    export S3_BUCKET="${S3_BUCKET:-dr-config-bucket-${RANDOM_SUFFIX}}"
    export SNS_TOPIC_PRIMARY="${SNS_TOPIC_PRIMARY:-dr-primary-alerts-${RANDOM_SUFFIX}}"
    export SNS_TOPIC_DR="${SNS_TOPIC_DR:-dr-failover-alerts-${RANDOM_SUFFIX}}"
    export LAMBDA_FUNCTION_PRIMARY="${LAMBDA_FUNCTION_PRIMARY:-dr-coordinator-${RANDOM_SUFFIX}}"
    export LAMBDA_FUNCTION_DR="${LAMBDA_FUNCTION_DR:-replica-promoter-${RANDOM_SUFFIX}}"
    
    log_success "Environment setup completed"
}

#################################################################################
# Resource Deletion Functions
#################################################################################

delete_route53_health_checks() {
    log_info "Deleting Route 53 health checks..."
    
    # List all health checks and filter by name patterns
    local health_checks
    health_checks=$(aws route53 list-health-checks \
        --query 'HealthChecks[?contains(CallerReference, `primary-db-health`) || contains(CallerReference, `dr-db-health`)].Id' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$health_checks" ]]; then
        for health_check_id in $health_checks; do
            if [[ -n "$health_check_id" ]] && [[ "$health_check_id" != "None" ]]; then
                if confirm_destruction "Route 53 Health Check" "$health_check_id"; then
                    safe_delete "aws route53 delete-health-check --health-check-id '$health_check_id'" \
                        "Route 53 health check $health_check_id" true
                fi
            fi
        done
    else
        log_info "No Route 53 health checks found to delete"
    fi
    
    log_success "Route 53 health check cleanup completed"
}

delete_eventbridge_rules() {
    log_info "Deleting EventBridge rules..."
    
    # Remove targets from EventBridge rule
    safe_delete "aws events remove-targets --region '$DR_REGION' --rule 'rds-promotion-events' --ids '1'" \
        "EventBridge rule targets" true
    
    # Delete EventBridge rule
    safe_delete "aws events delete-rule --region '$DR_REGION' --name 'rds-promotion-events'" \
        "EventBridge rule rds-promotion-events" true
    
    log_success "EventBridge cleanup completed"
}

delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    # Delete DR coordinator Lambda function
    if [[ -n "${LAMBDA_FUNCTION_PRIMARY:-}" ]]; then
        if confirm_destruction "Lambda Function" "$LAMBDA_FUNCTION_PRIMARY"; then
            safe_delete "aws lambda delete-function --region '$PRIMARY_REGION' --function-name '$LAMBDA_FUNCTION_PRIMARY'" \
                "Lambda function $LAMBDA_FUNCTION_PRIMARY" true
        fi
    fi
    
    # Delete replica promoter Lambda function
    if [[ -n "${LAMBDA_FUNCTION_DR:-}" ]]; then
        if confirm_destruction "Lambda Function" "$LAMBDA_FUNCTION_DR"; then
            safe_delete "aws lambda delete-function --region '$DR_REGION' --function-name '$LAMBDA_FUNCTION_DR'" \
                "Lambda function $LAMBDA_FUNCTION_DR" true
        fi
    fi
    
    log_success "Lambda function cleanup completed"
}

delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    # Delete alarms in primary region
    local primary_alarms=(
        "${DB_INSTANCE_ID}-database-connection-failure"
        "${DB_INSTANCE_ID}-cpu-utilization-high"
    )
    
    for alarm in "${primary_alarms[@]}"; do
        safe_delete "aws cloudwatch delete-alarms --region '$PRIMARY_REGION' --alarm-names '$alarm'" \
            "CloudWatch alarm $alarm" true
    done
    
    # Delete alarms in DR region
    local dr_alarms=(
        "${DB_REPLICA_ID}-replica-lag-high"
        "${DB_REPLICA_ID}-cpu-utilization-high"
    )
    
    for alarm in "${dr_alarms[@]}"; do
        safe_delete "aws cloudwatch delete-alarms --region '$DR_REGION' --alarm-names '$alarm'" \
            "CloudWatch alarm $alarm" true
    done
    
    log_success "CloudWatch alarm cleanup completed"
}

delete_sns_topics() {
    log_info "Deleting SNS topics..."
    
    # Get SNS topic ARNs
    local primary_sns_arn
    local dr_sns_arn
    
    if [[ -n "${SNS_TOPIC_PRIMARY:-}" ]]; then
        primary_sns_arn=$(aws sns list-topics --region "$PRIMARY_REGION" \
            --query "Topics[?contains(TopicArn, '$SNS_TOPIC_PRIMARY')].TopicArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "${SNS_TOPIC_DR:-}" ]]; then
        dr_sns_arn=$(aws sns list-topics --region "$DR_REGION" \
            --query "Topics[?contains(TopicArn, '$SNS_TOPIC_DR')].TopicArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Delete primary SNS topic
    if [[ -n "$primary_sns_arn" ]] && [[ "$primary_sns_arn" != "None" ]]; then
        if confirm_destruction "SNS Topic" "$primary_sns_arn"; then
            safe_delete "aws sns delete-topic --region '$PRIMARY_REGION' --topic-arn '$primary_sns_arn'" \
                "SNS topic $primary_sns_arn" true
        fi
    fi
    
    # Delete DR SNS topic
    if [[ -n "$dr_sns_arn" ]] && [[ "$dr_sns_arn" != "None" ]]; then
        if confirm_destruction "SNS Topic" "$dr_sns_arn"; then
            safe_delete "aws sns delete-topic --region '$DR_REGION' --topic-arn '$dr_sns_arn'" \
                "SNS topic $dr_sns_arn" true
        fi
    fi
    
    log_success "SNS topic cleanup completed"
}

delete_read_replica() {
    log_info "Deleting read replica database..."
    
    if [[ -z "${DB_REPLICA_ID:-}" ]]; then
        log_warning "DB_REPLICA_ID not set, skipping read replica deletion"
        return 0
    fi
    
    # Check if replica exists
    if ! aws rds describe-db-instances \
        --region "$DR_REGION" \
        --db-instance-identifier "$DB_REPLICA_ID" >/dev/null 2>&1; then
        log_info "Read replica $DB_REPLICA_ID does not exist"
        return 0
    fi
    
    if confirm_destruction "RDS Read Replica" "$DB_REPLICA_ID"; then
        # Delete read replica
        safe_delete "aws rds delete-db-instance --region '$DR_REGION' --db-instance-identifier '$DB_REPLICA_ID' --skip-final-snapshot" \
            "RDS read replica $DB_REPLICA_ID"
        
        # Wait for deletion to complete
        wait_for_deletion "rds" "$DB_REPLICA_ID" "$DR_REGION" 20 30
    fi
    
    log_success "Read replica deletion completed"
}

delete_primary_database() {
    log_info "Deleting primary database..."
    
    if [[ -z "${DB_INSTANCE_ID:-}" ]]; then
        log_warning "DB_INSTANCE_ID not set, skipping primary database deletion"
        return 0
    fi
    
    # Check if primary database exists
    if ! aws rds describe-db-instances \
        --region "$PRIMARY_REGION" \
        --db-instance-identifier "$DB_INSTANCE_ID" >/dev/null 2>&1; then
        log_info "Primary database $DB_INSTANCE_ID does not exist"
        return 0
    fi
    
    if confirm_destruction "RDS Primary Database" "$DB_INSTANCE_ID"; then
        # Remove deletion protection first
        log_info "Removing deletion protection from $DB_INSTANCE_ID..."
        safe_delete "aws rds modify-db-instance --region '$PRIMARY_REGION' --db-instance-identifier '$DB_INSTANCE_ID' --no-deletion-protection" \
            "deletion protection removal for $DB_INSTANCE_ID" true
        
        # Wait a moment for the modification to take effect
        sleep 30
        
        # Delete primary database
        safe_delete "aws rds delete-db-instance --region '$PRIMARY_REGION' --db-instance-identifier '$DB_INSTANCE_ID' --skip-final-snapshot" \
            "RDS primary database $DB_INSTANCE_ID"
        
        # Wait for deletion to complete
        wait_for_deletion "rds" "$DB_INSTANCE_ID" "$PRIMARY_REGION" 20 30
    fi
    
    log_success "Primary database deletion completed"
}

delete_parameter_groups() {
    log_info "Deleting custom parameter groups..."
    
    # Delete custom parameter group if it exists
    safe_delete "aws rds delete-db-parameter-group --region '$PRIMARY_REGION' --db-parameter-group-name 'mysql-replication-optimized'" \
        "Parameter group mysql-replication-optimized" true
    
    log_success "Parameter group cleanup completed"
}

delete_s3_bucket() {
    log_info "Deleting S3 configuration bucket..."
    
    if [[ -z "${S3_BUCKET:-}" ]]; then
        log_warning "S3_BUCKET not set, skipping S3 cleanup"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$S3_BUCKET" >/dev/null 2>&1; then
        log_info "S3 bucket $S3_BUCKET does not exist"
        return 0
    fi
    
    if confirm_destruction "S3 Bucket" "$S3_BUCKET"; then
        # Empty bucket first
        log_info "Emptying S3 bucket $S3_BUCKET..."
        safe_delete "aws s3 rm 's3://$S3_BUCKET' --recursive" \
            "S3 bucket contents" true
        
        # Delete bucket
        safe_delete "aws s3 rb 's3://$S3_BUCKET'" \
            "S3 bucket $S3_BUCKET" true
    fi
    
    log_success "S3 bucket cleanup completed"
}

clean_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove local deployment info file
    if [[ -f "./dr-deployment-info.json" ]]; then
        rm -f "./dr-deployment-info.json"
        log_success "Removed local deployment info file"
    fi
    
    # Remove temporary files
    rm -f /tmp/deployment-info.json /tmp/dr-runbook.json
    
    log_success "Local file cleanup completed"
}

#################################################################################
# Main Destruction Function
#################################################################################

main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "Starting Database Disaster Recovery resource destruction..."
    log_info "Log file: $LOG_FILE"
    
    # Show destruction warning
    echo
    echo -e "${RED}⚠️  DESTRUCTIVE OPERATION WARNING ⚠️${NC}"
    echo "This script will permanently delete ALL disaster recovery resources including:"
    echo "- RDS primary database and read replica"
    echo "- Lambda functions"
    echo "- SNS topics and subscriptions"
    echo "- CloudWatch alarms"
    echo "- Route 53 health checks"
    echo "- EventBridge rules"
    echo "- S3 configuration bucket and contents"
    echo
    
    if [[ "${FORCE_DESTROY:-}" != "true" ]]; then
        read -p "Do you want to continue with the destruction? (yes/no): " -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                log_info "User confirmed destruction process"
                ;;
            *)
                log_info "User cancelled destruction process"
                exit 0
                ;;
        esac
    else
        log_warning "FORCE_DESTROY enabled - proceeding without confirmation"
    fi
    
    # Validation and setup
    validate_prerequisites
    load_deployment_info || log_warning "Could not load deployment info, using environment variables"
    setup_environment
    
    # Resource deletion phase (in reverse order of creation)
    delete_route53_health_checks
    delete_eventbridge_rules
    delete_lambda_functions
    delete_cloudwatch_alarms
    delete_sns_topics
    delete_read_replica
    delete_primary_database
    delete_parameter_groups
    delete_s3_bucket
    clean_local_files
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Destruction completed successfully!"
    log_info "Total destruction time: ${duration} seconds"
    
    # Display summary
    echo
    echo "==================================="
    echo "DESTRUCTION SUMMARY"
    echo "==================================="
    echo "The following resources have been deleted:"
    echo "- Primary Database: ${DB_INSTANCE_ID:-N/A}"
    echo "- DR Replica: ${DB_REPLICA_ID:-N/A}"
    echo "- S3 Bucket: ${S3_BUCKET:-N/A}"
    echo "- SNS Topics: ${SNS_TOPIC_PRIMARY:-N/A}, ${SNS_TOPIC_DR:-N/A}"
    echo "- Lambda Functions: ${LAMBDA_FUNCTION_PRIMARY:-N/A}, ${LAMBDA_FUNCTION_DR:-N/A}"
    echo "- CloudWatch Alarms: Multiple alarms deleted"
    echo "- Route 53 Health Checks: Deleted"
    echo "- EventBridge Rules: Deleted"
    echo
    echo "Log file: $LOG_FILE"
    echo "==================================="
}

#################################################################################
# Error Handling and Usage
#################################################################################

trap 'log_error "Destruction failed on line $LINENO. Check log file: $LOG_FILE"' ERR

# Show usage if help requested
if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    cat << EOF
Database Disaster Recovery Destruction Script

USAGE:
    $0 [OPTIONS]

ENVIRONMENT VARIABLES:
    PRIMARY_REGION      Primary AWS region (default: us-east-1)
    DR_REGION          Disaster recovery AWS region (default: us-west-2)
    FORCE_DESTROY      Skip confirmation prompts (default: false)
    
    Resource identifiers (auto-detected from deployment-info.json if available):
    DB_INSTANCE_ID      Primary database instance ID
    DB_REPLICA_ID       Read replica instance ID
    S3_BUCKET          Configuration bucket name
    SNS_TOPIC_PRIMARY   Primary SNS topic name
    SNS_TOPIC_DR       DR SNS topic name
    LAMBDA_FUNCTION_PRIMARY  Coordinator Lambda function name
    LAMBDA_FUNCTION_DR      Promoter Lambda function name
    RANDOM_SUFFIX      Resource naming suffix

EXAMPLES:
    # Interactive destruction with confirmations
    $0

    # Force destruction without confirmations
    FORCE_DESTROY=true $0

    # Destroy with specific regions
    PRIMARY_REGION=us-west-1 DR_REGION=eu-west-1 $0

    # Destroy with manual resource specification
    DB_INSTANCE_ID=my-primary-db DB_REPLICA_ID=my-replica $0

SAFETY FEATURES:
    - Confirmation prompts for each destructive action
    - Automatic detection of resources from deployment info
    - Comprehensive logging of all operations
    - Graceful handling of missing resources
    - Proper error handling and rollback

FILES USED:
    - ./dr-deployment-info.json (deployment summary, if available)
    - $LOG_FILE (detailed destruction log)

REQUIREMENTS:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for resource deletion
EOF
    exit 0
fi

# Execute main function
main "$@"