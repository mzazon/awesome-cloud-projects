#!/bin/bash

# AWS DMS Database Migration Cleanup Script
# This script safely removes all DMS resources created by the deployment script
# Includes confirmation prompts and proper resource deletion order

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

# Configuration variables
PROJECT_NAME="${PROJECT_NAME:-dms-migration}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "./dms-deployment-info.txt" ]]; then
        log "Found deployment info file, extracting resource identifiers..."
        
        # Extract resource identifiers from deployment info file
        export DMS_REPLICATION_INSTANCE_ID=$(grep "DMS Replication Instance:" ./dms-deployment-info.txt | cut -d: -f2 | xargs)
        export DMS_SUBNET_GROUP_ID=$(grep "DMS Subnet Group:" ./dms-deployment-info.txt | cut -d: -f2 | xargs)
        export DMS_SOURCE_ENDPOINT_ID=$(grep "Source Endpoint:" ./dms-deployment-info.txt | cut -d: -f2 | xargs)
        export DMS_TARGET_ENDPOINT_ID=$(grep "Target Endpoint:" ./dms-deployment-info.txt | cut -d: -f2 | xargs)
        export DMS_TASK_ID=$(grep "Migration Task:" ./dms-deployment-info.txt | cut -d: -f2 | xargs)
        export SNS_TOPIC_ARN=$(grep "SNS Topic:" ./dms-deployment-info.txt | cut -d: -f2 | xargs)
        
        # Extract random suffix from resource names
        RANDOM_SUFFIX=$(echo "$DMS_REPLICATION_INSTANCE_ID" | sed "s/${PROJECT_NAME}-replication-//")
        
        log_success "Deployment information loaded from file"
    else
        log_warning "Deployment info file not found. Will attempt to discover resources..."
        discover_resources
    fi
}

# Function to discover existing resources
discover_resources() {
    log "Discovering existing DMS resources..."
    
    # Discover replication instances
    REPLICATION_INSTANCES=$(aws dms describe-replication-instances \
        --query "ReplicationInstances[?contains(ReplicationInstanceIdentifier, '${PROJECT_NAME}')].ReplicationInstanceIdentifier" \
        --output text)
    
    if [[ -n "$REPLICATION_INSTANCES" ]]; then
        export DMS_REPLICATION_INSTANCE_ID=$(echo "$REPLICATION_INSTANCES" | head -n1)
        log "Found replication instance: $DMS_REPLICATION_INSTANCE_ID"
        
        # Extract random suffix
        RANDOM_SUFFIX=$(echo "$DMS_REPLICATION_INSTANCE_ID" | sed "s/${PROJECT_NAME}-replication-//")
        
        # Set other resource identifiers based on pattern
        export DMS_SUBNET_GROUP_ID="${PROJECT_NAME}-subnet-group-${RANDOM_SUFFIX}"
        export DMS_SOURCE_ENDPOINT_ID="${PROJECT_NAME}-source-${RANDOM_SUFFIX}"
        export DMS_TARGET_ENDPOINT_ID="${PROJECT_NAME}-target-${RANDOM_SUFFIX}"
        export DMS_TASK_ID="${PROJECT_NAME}-migration-task-${RANDOM_SUFFIX}"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${PROJECT_NAME}-migration-alerts-${RANDOM_SUFFIX}"
    else
        log_error "No DMS resources found for project: $PROJECT_NAME"
        exit 1
    fi
    
    log_success "Resource discovery completed"
}

# Function to display resources to be deleted
display_resources() {
    log "The following resources will be deleted:"
    echo ""
    echo "  DMS Resources:"
    echo "    - Replication Instance: $DMS_REPLICATION_INSTANCE_ID"
    echo "    - Subnet Group: $DMS_SUBNET_GROUP_ID"
    echo "    - Source Endpoint: $DMS_SOURCE_ENDPOINT_ID"
    echo "    - Target Endpoint: $DMS_TARGET_ENDPOINT_ID"
    echo "    - Migration Task: $DMS_TASK_ID"
    echo ""
    echo "  Monitoring Resources:"
    echo "    - SNS Topic: $SNS_TOPIC_ARN"
    echo "    - CloudWatch Alarms: ${PROJECT_NAME}-DMS-Task-Failure-${RANDOM_SUFFIX}"
    echo "    - CloudWatch Alarms: ${PROJECT_NAME}-DMS-High-Latency-${RANDOM_SUFFIX}"
    echo "    - Event Subscription: ${PROJECT_NAME}-events-${RANDOM_SUFFIX}"
    echo ""
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping confirmation (SKIP_CONFIRMATION=true)"
        return 0
    fi
    
    display_resources
    
    log_warning "This action is irreversible and will permanently delete all listed resources."
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to stop and delete migration task
delete_migration_task() {
    log "Stopping and deleting migration task..."
    
    # Check if task exists
    if ! aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0]' --output text | grep -q "$DMS_TASK_ID" 2>/dev/null; then
        log_warning "Migration task not found, skipping deletion"
        return 0
    fi
    
    # Get task ARN and status
    TASK_INFO=$(aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0].{Arn:ReplicationTaskArn,Status:Status}' \
        --output text)
    
    MIGRATION_TASK_ARN=$(echo "$TASK_INFO" | cut -f1)
    TASK_STATUS=$(echo "$TASK_INFO" | cut -f2)
    
    # Stop task if running
    if [[ "$TASK_STATUS" == "running" || "$TASK_STATUS" == "starting" ]]; then
        log "Stopping migration task..."
        aws dms stop-replication-task \
            --replication-task-arn "$MIGRATION_TASK_ARN"
        
        # Wait for task to stop
        log "Waiting for task to stop..."
        timeout 300 bash -c "
            while true; do
                status=\$(aws dms describe-replication-tasks \
                    --filters \"Name=replication-task-id,Values=$DMS_TASK_ID\" \
                    --query 'ReplicationTasks[0].Status' --output text)
                if [[ \"\$status\" == \"stopped\" || \"\$status\" == \"failed\" ]]; then
                    break
                fi
                sleep 10
            done
        " || log_warning "Timeout waiting for task to stop, proceeding with deletion"
    fi
    
    # Delete migration task
    aws dms delete-replication-task \
        --replication-task-arn "$MIGRATION_TASK_ARN"
    
    log_success "Migration task deleted: $DMS_TASK_ID"
}

# Function to delete event subscription
delete_event_subscription() {
    log "Deleting event subscription..."
    
    SUBSCRIPTION_NAME="${PROJECT_NAME}-events-${RANDOM_SUFFIX}"
    
    # Check if event subscription exists
    if ! aws dms describe-event-subscriptions \
        --filters "Name=subscription-name,Values=$SUBSCRIPTION_NAME" \
        --query 'EventSubscriptionsList[0]' --output text | grep -q "$SUBSCRIPTION_NAME" 2>/dev/null; then
        log_warning "Event subscription not found, skipping deletion"
        return 0
    fi
    
    aws dms delete-event-subscription \
        --subscription-name "$SUBSCRIPTION_NAME"
    
    log_success "Event subscription deleted: $SUBSCRIPTION_NAME"
}

# Function to delete database endpoints
delete_endpoints() {
    log "Deleting database endpoints..."
    
    # Delete source endpoint
    if aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_SOURCE_ENDPOINT_ID" \
        --query 'Endpoints[0]' --output text | grep -q "$DMS_SOURCE_ENDPOINT_ID" 2>/dev/null; then
        
        SOURCE_ENDPOINT_ARN=$(aws dms describe-endpoints \
            --filters "Name=endpoint-id,Values=$DMS_SOURCE_ENDPOINT_ID" \
            --query 'Endpoints[0].EndpointArn' --output text)
        
        aws dms delete-endpoint \
            --endpoint-arn "$SOURCE_ENDPOINT_ARN"
        
        log_success "Source endpoint deleted: $DMS_SOURCE_ENDPOINT_ID"
    else
        log_warning "Source endpoint not found, skipping deletion"
    fi
    
    # Delete target endpoint
    if aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_TARGET_ENDPOINT_ID" \
        --query 'Endpoints[0]' --output text | grep -q "$DMS_TARGET_ENDPOINT_ID" 2>/dev/null; then
        
        TARGET_ENDPOINT_ARN=$(aws dms describe-endpoints \
            --filters "Name=endpoint-id,Values=$DMS_TARGET_ENDPOINT_ID" \
            --query 'Endpoints[0].EndpointArn' --output text)
        
        aws dms delete-endpoint \
            --endpoint-arn "$TARGET_ENDPOINT_ARN"
        
        log_success "Target endpoint deleted: $DMS_TARGET_ENDPOINT_ID"
    else
        log_warning "Target endpoint not found, skipping deletion"
    fi
}

# Function to delete replication instance
delete_replication_instance() {
    log "Deleting replication instance..."
    
    # Check if replication instance exists
    if ! aws dms describe-replication-instances \
        --filters "Name=replication-instance-id,Values=$DMS_REPLICATION_INSTANCE_ID" \
        --query 'ReplicationInstances[0]' --output text | grep -q "$DMS_REPLICATION_INSTANCE_ID" 2>/dev/null; then
        log_warning "Replication instance not found, skipping deletion"
        return 0
    fi
    
    # Get replication instance ARN
    REPLICATION_INSTANCE_ARN=$(aws dms describe-replication-instances \
        --filters "Name=replication-instance-id,Values=$DMS_REPLICATION_INSTANCE_ID" \
        --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)
    
    # Delete replication instance
    aws dms delete-replication-instance \
        --replication-instance-arn "$REPLICATION_INSTANCE_ARN"
    
    log "Replication instance deletion initiated (this may take several minutes)"
    
    # Wait for deletion if not forcing
    if [[ "$FORCE_DELETE" != "true" ]]; then
        log "Waiting for replication instance to be deleted..."
        timeout 600 bash -c "
            while true; do
                if ! aws dms describe-replication-instances \
                    --filters \"Name=replication-instance-id,Values=$DMS_REPLICATION_INSTANCE_ID\" \
                    --query 'ReplicationInstances[0]' --output text | grep -q \"$DMS_REPLICATION_INSTANCE_ID\" 2>/dev/null; then
                    break
                fi
                sleep 30
            done
        " && log_success "Replication instance deleted: $DMS_REPLICATION_INSTANCE_ID" || log_warning "Timeout waiting for replication instance deletion"
    else
        log_success "Replication instance deletion initiated: $DMS_REPLICATION_INSTANCE_ID"
    fi
}

# Function to delete subnet group
delete_subnet_group() {
    log "Deleting DMS subnet group..."
    
    # Check if subnet group exists
    if ! aws dms describe-replication-subnet-groups \
        --filters "Name=replication-subnet-group-id,Values=$DMS_SUBNET_GROUP_ID" \
        --query 'ReplicationSubnetGroups[0]' --output text | grep -q "$DMS_SUBNET_GROUP_ID" 2>/dev/null; then
        log_warning "Subnet group not found, skipping deletion"
        return 0
    fi
    
    aws dms delete-replication-subnet-group \
        --replication-subnet-group-identifier "$DMS_SUBNET_GROUP_ID"
    
    log_success "Subnet group deleted: $DMS_SUBNET_GROUP_ID"
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    ALARM_NAMES=(
        "${PROJECT_NAME}-DMS-Task-Failure-${RANDOM_SUFFIX}"
        "${PROJECT_NAME}-DMS-High-Latency-${RANDOM_SUFFIX}"
    )
    
    # Check which alarms exist
    EXISTING_ALARMS=()
    for alarm in "${ALARM_NAMES[@]}"; do
        if aws cloudwatch describe-alarms \
            --alarm-names "$alarm" \
            --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm" 2>/dev/null; then
            EXISTING_ALARMS+=("$alarm")
        fi
    done
    
    if [[ ${#EXISTING_ALARMS[@]} -eq 0 ]]; then
        log_warning "No CloudWatch alarms found, skipping deletion"
        return 0
    fi
    
    # Delete existing alarms
    aws cloudwatch delete-alarms \
        --alarm-names "${EXISTING_ALARMS[@]}"
    
    log_success "CloudWatch alarms deleted: ${EXISTING_ALARMS[*]}"
}

# Function to delete SNS topic and subscriptions
delete_sns_topic() {
    log "Deleting SNS topic and subscriptions..."
    
    # Check if SNS topic exists
    if ! aws sns get-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
        log_warning "SNS topic not found, skipping deletion"
        return 0
    fi
    
    # List and delete subscriptions first
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$SNS_TOPIC_ARN" \
        --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "$SUBSCRIPTIONS" ]]; then
        for subscription in $SUBSCRIPTIONS; do
            if [[ "$subscription" != "PendingConfirmation" ]]; then
                aws sns unsubscribe --subscription-arn "$subscription"
                log "Deleted subscription: $subscription"
            fi
        done
    fi
    
    # Delete SNS topic
    aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
    
    log_success "SNS topic deleted: $SNS_TOPIC_ARN"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "./dms-deployment-info.txt" ]]; then
        rm -f "./dms-deployment-info.txt"
        log "Deleted deployment info file"
    fi
    
    # Remove any temporary files
    rm -f /tmp/table-mappings.json 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    REMAINING_RESOURCES=()
    
    # Check for remaining DMS resources
    if aws dms describe-replication-instances \
        --filters "Name=replication-instance-id,Values=$DMS_REPLICATION_INSTANCE_ID" \
        --query 'ReplicationInstances[0]' --output text 2>/dev/null | grep -q "$DMS_REPLICATION_INSTANCE_ID" 2>/dev/null; then
        REMAINING_RESOURCES+=("Replication Instance: $DMS_REPLICATION_INSTANCE_ID")
    fi
    
    if aws dms describe-replication-tasks \
        --filters "Name=replication-task-id,Values=$DMS_TASK_ID" \
        --query 'ReplicationTasks[0]' --output text 2>/dev/null | grep -q "$DMS_TASK_ID" 2>/dev/null; then
        REMAINING_RESOURCES+=("Migration Task: $DMS_TASK_ID")
    fi
    
    if aws dms describe-endpoints \
        --filters "Name=endpoint-id,Values=$DMS_SOURCE_ENDPOINT_ID" \
        --query 'Endpoints[0]' --output text 2>/dev/null | grep -q "$DMS_SOURCE_ENDPOINT_ID" 2>/dev/null; then
        REMAINING_RESOURCES+=("Source Endpoint: $DMS_SOURCE_ENDPOINT_ID")
    fi
    
    if [[ ${#REMAINING_RESOURCES[@]} -eq 0 ]]; then
        log_success "All resources have been successfully deleted"
    else
        log_warning "Some resources may still be deleting:"
        for resource in "${REMAINING_RESOURCES[@]}"; do
            echo "  - $resource"
        done
        log "These resources may take additional time to complete deletion"
    fi
}

# Main cleanup function
main() {
    log "Starting AWS DMS Database Migration cleanup..."
    
    check_prerequisites
    setup_environment
    load_deployment_info
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_migration_task
    delete_event_subscription
    delete_endpoints
    delete_replication_instance
    delete_subnet_group
    delete_cloudwatch_alarms
    delete_sns_topic
    cleanup_local_files
    verify_cleanup
    
    log_success "AWS DMS Database Migration cleanup completed!"
    log ""
    log "All DMS resources have been cleaned up successfully."
    log "Please verify in the AWS console that all resources have been deleted."
    log ""
    log "Note: Some resources (like replication instances) may take additional time"
    log "to complete deletion even after the API confirms the deletion request."
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force              Skip waiting for resource deletion completion"
            echo "  --yes                Skip confirmation prompts"
            echo "  --project-name NAME  Override project name (default: dms-migration)"
            echo "  --environment ENV    Override environment (default: dev)"
            echo "  --help               Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_NAME         Project name for resource identification"
            echo "  ENVIRONMENT          Environment name for resource identification"
            echo "  FORCE_DELETE         Set to 'true' to skip deletion wait times"
            echo "  SKIP_CONFIRMATION    Set to 'true' to skip confirmation prompts"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"