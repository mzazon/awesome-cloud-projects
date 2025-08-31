#!/bin/bash

# Service Quota Monitoring with CloudWatch Alarms - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"
FORCE_DELETE=false

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS credentials."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    if [[ ! -f "$STATE_FILE" ]]; then
        log_error "Deployment state file not found: $STATE_FILE"
        log_error "Either the deployment was not completed or the state file was deleted."
        
        if [[ "$FORCE_DELETE" == "true" ]]; then
            log_warning "Force delete mode enabled. Will attempt to delete resources by name pattern."
            return 0
        else
            echo ""
            echo "To force cleanup without state file, run: $0 --force"
            echo "Warning: Force mode may not delete all resources if naming patterns changed."
            exit 1
        fi
    fi
    
    # Source the state file to load variables
    source "$STATE_FILE"
    
    if [[ "${DEPLOYMENT_COMPLETE:-false}" != "true" ]]; then
        log_warning "Deployment appears to be incomplete based on state file."
        echo "This may be due to a failed deployment. Continuing with cleanup..."
    fi
    
    log_success "Deployment state loaded from: $STATE_FILE"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete mode - skipping confirmation"
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - SNS Topic and all subscriptions"
    echo "  - All CloudWatch alarms for service quota monitoring"
    echo ""
    
    if [[ -f "$STATE_FILE" ]]; then
        echo "Resources to be deleted:"
        if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
            echo "  - SNS Topic: $SNS_TOPIC_ARN"
        fi
        
        local alarm_count=0
        if grep -q "EC2_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null; then
            echo "  - CloudWatch Alarm: EC2-Running-Instances-Quota-Alert"
            ((alarm_count++))
        fi
        if grep -q "VPC_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null; then
            echo "  - CloudWatch Alarm: VPC-Quota-Alert"
            ((alarm_count++))
        fi
        if grep -q "LAMBDA_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null; then
            echo "  - CloudWatch Alarm: Lambda-Concurrent-Executions-Quota-Alert"
            ((alarm_count++))
        fi
        
        echo "  - Total CloudWatch Alarms: $alarm_count"
    fi
    
    echo ""
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms_deleted=0
    local alarm_names=()
    
    # Collect alarm names from state file or use default names in force mode
    if [[ -f "$STATE_FILE" ]]; then
        grep -q "EC2_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null && alarm_names+=("EC2-Running-Instances-Quota-Alert")
        grep -q "VPC_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null && alarm_names+=("VPC-Quota-Alert")
        grep -q "LAMBDA_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null && alarm_names+=("Lambda-Concurrent-Executions-Quota-Alert")
    else
        # Force mode - try to delete all possible alarms
        alarm_names=("EC2-Running-Instances-Quota-Alert" "VPC-Quota-Alert" "Lambda-Concurrent-Executions-Quota-Alert")
    fi
    
    if [[ ${#alarm_names[@]} -eq 0 ]]; then
        log_warning "No CloudWatch alarms found to delete"
        return 0
    fi
    
    # Delete alarms individually to handle partial failures
    for alarm_name in "${alarm_names[@]}"; do
        log "Deleting alarm: $alarm_name"
        
        if aws cloudwatch delete-alarms --alarm-names "$alarm_name" &> /dev/null; then
            log_success "Deleted alarm: $alarm_name"
            ((alarms_deleted++))
        else
            # Check if alarm exists before reporting error
            if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
                log_error "Failed to delete alarm: $alarm_name"
            else
                log_warning "Alarm not found (may have been deleted already): $alarm_name"
            fi
        fi
    done
    
    if [[ $alarms_deleted -gt 0 ]]; then
        log_success "Deleted $alarms_deleted CloudWatch alarms"
    fi
}

# Function to delete SNS topic and subscriptions
delete_sns_resources() {
    log "Deleting SNS topic and subscriptions..."
    
    local sns_topic_arn="${SNS_TOPIC_ARN:-}"
    
    # In force mode, try to find SNS topics by name pattern
    if [[ -z "$sns_topic_arn" ]] && [[ "$FORCE_DELETE" == "true" ]]; then
        log "Searching for SNS topics with service-quota-alerts pattern..."
        
        local topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `service-quota-alerts`)].TopicArn' --output text)
        
        if [[ -n "$topics" ]]; then
            log_warning "Found SNS topics matching pattern. Using first match for cleanup."
            sns_topic_arn=$(echo "$topics" | head -n1)
        fi
    fi
    
    if [[ -z "$sns_topic_arn" ]]; then
        log_warning "No SNS topic ARN found to delete"
        return 0
    fi
    
    log "Deleting SNS topic: $sns_topic_arn"
    
    # List subscriptions before deletion for logging
    local subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$sns_topic_arn" \
        --query 'Subscriptions[*].SubscriptionArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$subscriptions" ]]; then
        local sub_count=$(echo "$subscriptions" | wc -w)
        log "Found $sub_count subscription(s) that will be deleted with the topic"
    fi
    
    # Delete the topic (this automatically deletes all subscriptions)
    if aws sns delete-topic --topic-arn "$sns_topic_arn" &> /dev/null; then
        log_success "SNS topic deleted: $sns_topic_arn"
    else
        # Check if topic exists before reporting error
        if aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &> /dev/null; then
            log_error "Failed to delete SNS topic: $sns_topic_arn"
        else
            log_warning "SNS topic not found (may have been deleted already): $sns_topic_arn"
        fi
    fi
}

# Function to verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Verify CloudWatch alarms deletion
    local remaining_alarms=()
    local alarm_names=("EC2-Running-Instances-Quota-Alert" "VPC-Quota-Alert" "Lambda-Concurrent-Executions-Quota-Alert")
    
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
            remaining_alarms+=("$alarm_name")
            cleanup_success=false
        fi
    done
    
    if [[ ${#remaining_alarms[@]} -gt 0 ]]; then
        log_error "The following CloudWatch alarms still exist:"
        printf '%s\n' "${remaining_alarms[@]}"
    else
        log_success "All CloudWatch alarms have been deleted"
    fi
    
    # Verify SNS topic deletion
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
            log_error "SNS topic still exists: $SNS_TOPIC_ARN"
            cleanup_success=false
        else
            log_success "SNS topic has been deleted"
        fi
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_error "Some resources may not have been deleted completely"
        log_error "Please check the AWS console and delete any remaining resources manually"
    fi
}

# Function to remove state file
cleanup_state_file() {
    if [[ -f "$STATE_FILE" ]]; then
        log "Removing deployment state file..."
        
        if rm -f "$STATE_FILE"; then
            log_success "State file removed: $STATE_FILE"
        else
            log_error "Failed to remove state file: $STATE_FILE"
            log_error "Please remove it manually to allow fresh deployments"
        fi
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    log "Cleanup Summary:"
    echo "================"
    echo "Operation: Service Quota Monitoring Cleanup"
    echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        echo "SNS Topic Deleted: $SNS_TOPIC_ARN"
    fi
    
    echo "CloudWatch Alarms: EC2, VPC, and Lambda quota monitoring alarms removed"
    echo "State File: $STATE_FILE (removed)"
    
    echo ""
    log_success "Service quota monitoring cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Service Quota Monitoring cleanup..."
    
    check_prerequisites
    load_deployment_state
    confirm_deletion
    delete_cloudwatch_alarms
    delete_sns_resources
    verify_cleanup
    cleanup_state_file
    display_summary
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Service Quota Monitoring Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force      Force cleanup without confirmation and state file"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Description:"
    echo "  This script removes all resources created by the deployment script:"
    echo "  - SNS topic and email subscriptions"
    echo "  - CloudWatch alarms for service quota monitoring"
    echo "  - Deployment state file"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmation"
    echo "  $0 --force           # Force cleanup without confirmation"
    echo "  $0 --dry-run         # Preview what would be deleted"
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            echo "DRY RUN MODE - No resources will be deleted"
            echo ""
            
            if [[ -f "$STATE_FILE" ]]; then
                source "$STATE_FILE"
                echo "Resources that would be deleted:"
                if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
                    echo "  - SNS Topic: $SNS_TOPIC_ARN"
                fi
                
                grep -q "EC2_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null && echo "  - CloudWatch Alarm: EC2-Running-Instances-Quota-Alert"
                grep -q "VPC_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null && echo "  - CloudWatch Alarm: VPC-Quota-Alert"
                grep -q "LAMBDA_ALARM_CREATED=true" "$STATE_FILE" 2>/dev/null && echo "  - CloudWatch Alarm: Lambda-Concurrent-Executions-Quota-Alert"
                
                echo "  - State file: $STATE_FILE"
            else
                echo "No state file found. In force mode, would attempt to delete:"
                echo "  - SNS topics matching pattern: service-quota-alerts-*"
                echo "  - CloudWatch alarms: EC2-Running-Instances-Quota-Alert, VPC-Quota-Alert, Lambda-Concurrent-Executions-Quota-Alert"
            fi
            
            echo ""
            echo "To perform actual cleanup, run: $0"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main