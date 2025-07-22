#!/bin/bash

# Destroy script for Website Uptime Monitoring with Route 53 Health Checks
# This script safely removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}⚠️  WARNING: This will destroy all monitoring resources!${NC}"
    echo "The following resources will be permanently deleted:"
    echo "  - Route 53 Health Check"
    echo "  - CloudWatch Alarm"
    echo "  - CloudWatch Dashboard"
    echo "  - SNS Topic and Subscriptions"
    echo "  - Configuration files"
    echo ""
    
    # Check if running in non-interactive mode
    if [ "${NON_INTERACTIVE:-false}" = "true" ]; then
        log "Running in non-interactive mode, proceeding with destruction..."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Load resource identifiers from state files
load_resource_ids() {
    log "Loading resource identifiers from state files..."
    
    # Load SNS Topic ARN
    if [ -f ".sns_topic_arn" ]; then
        SNS_TOPIC_ARN=$(cat .sns_topic_arn)
        log "Found SNS Topic ARN: $SNS_TOPIC_ARN"
    else
        warning "SNS Topic ARN state file not found"
        SNS_TOPIC_ARN=""
    fi
    
    # Load Health Check ID
    if [ -f ".health_check_id" ]; then
        HEALTH_CHECK_ID=$(cat .health_check_id)
        log "Found Health Check ID: $HEALTH_CHECK_ID"
    else
        warning "Health Check ID state file not found"
        HEALTH_CHECK_ID=""
    fi
    
    # Load Alarm Name
    if [ -f ".alarm_name" ]; then
        ALARM_NAME=$(cat .alarm_name)
        log "Found Alarm Name: $ALARM_NAME"
    else
        warning "Alarm Name state file not found"
        ALARM_NAME=""
    fi
    
    # Load Dashboard Name
    if [ -f ".dashboard_name" ]; then
        DASHBOARD_NAME=$(cat .dashboard_name)
        log "Found Dashboard Name: $DASHBOARD_NAME"
    else
        warning "Dashboard Name state file not found"
        DASHBOARD_NAME=""
    fi
    
    # Check if any resources were found
    if [ -z "$SNS_TOPIC_ARN" ] && [ -z "$HEALTH_CHECK_ID" ] && [ -z "$ALARM_NAME" ] && [ -z "$DASHBOARD_NAME" ]; then
        warning "No state files found. Resources may have already been deleted or were created manually."
        warning "You may need to delete resources manually through the AWS Console."
        return 1
    fi
    
    success "Resource identifiers loaded successfully"
}

# Delete CloudWatch Dashboard
delete_dashboard() {
    if [ -n "$DASHBOARD_NAME" ]; then
        log "Deleting CloudWatch dashboard: $DASHBOARD_NAME"
        
        if aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME" 2>/dev/null; then
            success "CloudWatch dashboard deleted successfully"
        else
            warning "Failed to delete CloudWatch dashboard (may not exist)"
        fi
    else
        log "No dashboard to delete"
    fi
}

# Delete CloudWatch Alarm
delete_alarm() {
    if [ -n "$ALARM_NAME" ]; then
        log "Deleting CloudWatch alarm: $ALARM_NAME"
        
        if aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME" 2>/dev/null; then
            success "CloudWatch alarm deleted successfully"
        else
            warning "Failed to delete CloudWatch alarm (may not exist)"
        fi
    else
        log "No alarm to delete"
    fi
}

# Delete SNS Topic and Subscriptions
delete_sns_resources() {
    if [ -n "$SNS_TOPIC_ARN" ]; then
        log "Deleting SNS topic and subscriptions: $SNS_TOPIC_ARN"
        
        # List and delete all subscriptions first (optional, as deleting topic removes them)
        log "Listing SNS subscriptions..."
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SUBSCRIPTIONS" ]; then
            log "Found subscriptions, they will be deleted with the topic"
        fi
        
        # Delete the topic (this automatically deletes all subscriptions)
        if aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null; then
            success "SNS topic and subscriptions deleted successfully"
        else
            warning "Failed to delete SNS topic (may not exist)"
        fi
    else
        log "No SNS topic to delete"
    fi
}

# Delete Route 53 Health Check
delete_health_check() {
    if [ -n "$HEALTH_CHECK_ID" ]; then
        log "Deleting Route 53 health check: $HEALTH_CHECK_ID"
        
        # First, check if health check exists
        if aws route53 get-health-check --health-check-id "$HEALTH_CHECK_ID" &>/dev/null; then
            # Delete the health check
            if aws route53 delete-health-check --health-check-id "$HEALTH_CHECK_ID" 2>/dev/null; then
                success "Route 53 health check deleted successfully"
            else
                error "Failed to delete Route 53 health check"
            fi
        else
            warning "Health check does not exist (may have been deleted already)"
        fi
    else
        log "No health check to delete"
    fi
}

# Clean up configuration files
cleanup_files() {
    log "Cleaning up configuration and state files..."
    
    # List of files to clean up
    FILES_TO_CLEAN=(
        "health-check-config.json"
        "dashboard-config.json"
        "deployment-summary.txt"
        ".sns_topic_arn"
        ".health_check_id"
        ".alarm_name"
        ".dashboard_name"
        ".sns_subscription_arn"
    )
    
    for file in "${FILES_TO_CLEAN[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed file: $file"
        fi
    done
    
    success "Configuration and state files cleaned up"
}

# Verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Verify health check deletion
    if [ -n "$HEALTH_CHECK_ID" ]; then
        if aws route53 get-health-check --health-check-id "$HEALTH_CHECK_ID" &>/dev/null; then
            error "Health check still exists: $HEALTH_CHECK_ID"
            verification_failed=true
        else
            success "Health check deletion verified"
        fi
    fi
    
    # Verify alarm deletion
    if [ -n "$ALARM_NAME" ]; then
        ALARM_EXISTS=$(aws cloudwatch describe-alarms \
            --alarm-names "$ALARM_NAME" \
            --query 'MetricAlarms[0].AlarmName' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$ALARM_EXISTS" != "None" ] && [ "$ALARM_EXISTS" != "" ]; then
            error "CloudWatch alarm still exists: $ALARM_NAME"
            verification_failed=true
        else
            success "CloudWatch alarm deletion verified"
        fi
    fi
    
    # Verify SNS topic deletion
    if [ -n "$SNS_TOPIC_ARN" ]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            error "SNS topic still exists: $SNS_TOPIC_ARN"
            verification_failed=true
        else
            success "SNS topic deletion verified"
        fi
    fi
    
    if [ "$verification_failed" = true ]; then
        error "Some resources were not deleted successfully. Please check the AWS Console."
    else
        success "All resource deletions verified successfully"
    fi
}

# Generate destruction summary
generate_destruction_summary() {
    log "Generating destruction summary..."
    
    cat > destruction-summary.txt << EOF
Website Uptime Monitoring Destruction Summary
=============================================

Destruction Date: $(date)

Resources Deleted:
- SNS Topic: ${SNS_TOPIC_ARN:-"Not found"}
- Health Check: ${HEALTH_CHECK_ID:-"Not found"}
- CloudWatch Alarm: ${ALARM_NAME:-"Not found"}
- CloudWatch Dashboard: ${DASHBOARD_NAME:-"Not found"}

Files Cleaned:
- health-check-config.json
- dashboard-config.json
- deployment-summary.txt
- State files (.sns_topic_arn, .health_check_id, etc.)

Notes:
- All monitoring resources have been removed
- No further charges will be incurred
- Email subscriptions have been cancelled
- Configuration files have been cleaned up

To redeploy the monitoring system, run: ./deploy.sh
EOF

    success "Destruction summary saved to destruction-summary.txt"
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Script interrupted or failed. Some resources may not have been deleted."
        warning "Please check the AWS Console to verify resource deletion."
        warning "You may need to manually delete remaining resources."
    fi
}

# Main destruction function
main() {
    # Set up exit handler
    trap cleanup_on_exit EXIT
    
    log "Starting Website Uptime Monitoring destruction..."
    
    confirm_destruction
    check_prerequisites
    
    # Try to load resource IDs, continue even if some are missing
    if ! load_resource_ids; then
        warning "Some state files are missing. Continuing with available information..."
    fi
    
    # Delete resources in reverse order of creation
    delete_dashboard
    delete_alarm
    delete_sns_resources
    delete_health_check
    cleanup_files
    verify_deletion
    generate_destruction_summary
    
    success "Destruction completed successfully!"
    success "All monitoring resources have been removed."
    success "No further charges will be incurred for the monitoring system."
    
    # Remove the exit handler since we completed successfully
    trap - EXIT
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--non-interactive] [--help]"
            echo ""
            echo "Options:"
            echo "  --non-interactive  Skip confirmation prompts"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "This script destroys all resources created by deploy.sh"
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Run main function
main "$@"