#!/bin/bash

# Advanced IoT Device Shadow Synchronization - Cleanup Script
# This script safely removes all resources created by the deployment script
# including Lambda functions, DynamoDB tables, IoT resources, and monitoring

set -e  # Exit on any error

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Progress tracking
STEP_COUNT=0
TOTAL_STEPS=10

progress() {
    STEP_COUNT=$((STEP_COUNT + 1))
    echo -e "\n${BLUE}[STEP $STEP_COUNT/$TOTAL_STEPS]${NC} $1\n"
}

# Configuration variables
REGION=${AWS_REGION:-$(aws configure get region)}
ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

# Load deployment configuration
load_deployment_config() {
    if [[ ! -f .deployment-config ]]; then
        log_error "Deployment configuration file '.deployment-config' not found."
        echo "This script requires the configuration file created during deployment."
        echo "If you deployed manually, please set the following environment variables:"
        echo "  SHADOW_SYNC_LAMBDA, CONFLICT_RESOLVER_LAMBDA, SHADOW_HISTORY_TABLE,"
        echo "  DEVICE_CONFIG_TABLE, SYNC_METRICS_TABLE, EVENT_BUS_NAME, THING_NAME,"
        echo "  EXECUTION_ROLE_NAME, POLICY_NAME, and other resource names"
        exit 1
    fi
    
    log_info "Loading deployment configuration..."
    source .deployment-config
    
    # Validate required variables
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        log_error "Invalid deployment configuration. Missing RANDOM_SUFFIX."
        exit 1
    fi
    
    log_success "Configuration loaded for deployment: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "\n${YELLOW}WARNING: This will permanently delete the following resources:${NC}"
    echo -e "${RED}  ❌ Lambda Functions: ${CONFLICT_RESOLVER_LAMBDA}, ${SHADOW_SYNC_LAMBDA}${NC}"
    echo -e "${RED}  ❌ DynamoDB Tables: ${SHADOW_HISTORY_TABLE}, ${DEVICE_CONFIG_TABLE}, ${SYNC_METRICS_TABLE}${NC}"
    echo -e "${RED}  ❌ IoT Thing: ${THING_NAME}${NC}"
    echo -e "${RED}  ❌ EventBridge Bus: ${EVENT_BUS_NAME}${NC}"
    echo -e "${RED}  ❌ IAM Role and Policy: ${EXECUTION_ROLE_NAME}, ${POLICY_NAME}${NC}"
    echo -e "${RED}  ❌ CloudWatch Dashboard and Logs${NC}"
    echo -e "${RED}  ❌ IoT Rules and Certificates${NC}"
    
    echo -e "\n${BLUE}Estimated costs that will be eliminated:${NC}"
    echo "  • Lambda: ~\$0.20/1M invocations"
    echo "  • DynamoDB: ~\$1.25/month for 1GB + requests"
    echo "  • IoT Core: ~\$1.00/1M messages"
    echo "  • CloudWatch Logs: ~\$0.50/GB ingested"
    
    echo -e "\n${YELLOW}This action cannot be undone!${NC}"
    read -p "Are you sure you want to delete all resources? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_success "Destruction confirmed"
}

# Dry run mode
perform_dry_run() {
    echo -e "\n${BLUE}=== DRY RUN MODE ===${NC}"
    echo "The following resources would be deleted:"
    
    # Check which resources exist
    echo -e "\n${BLUE}Lambda Functions:${NC}"
    if aws lambda get-function --function-name "$CONFLICT_RESOLVER_LAMBDA" &>/dev/null; then
        echo "  ✓ $CONFLICT_RESOLVER_LAMBDA (exists)"
    else
        echo "  ✗ $CONFLICT_RESOLVER_LAMBDA (not found)"
    fi
    
    if aws lambda get-function --function-name "$SHADOW_SYNC_LAMBDA" &>/dev/null; then
        echo "  ✓ $SHADOW_SYNC_LAMBDA (exists)"
    else
        echo "  ✗ $SHADOW_SYNC_LAMBDA (not found)"
    fi
    
    echo -e "\n${BLUE}DynamoDB Tables:${NC}"
    for table in "$SHADOW_HISTORY_TABLE" "$DEVICE_CONFIG_TABLE" "$SYNC_METRICS_TABLE"; do
        if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
            echo "  ✓ $table (exists)"
        else
            echo "  ✗ $table (not found)"
        fi
    done
    
    echo -e "\n${BLUE}IoT Resources:${NC}"
    if aws iot describe-thing --thing-name "$THING_NAME" &>/dev/null; then
        echo "  ✓ Thing: $THING_NAME (exists)"
    else
        echo "  ✗ Thing: $THING_NAME (not found)"
    fi
    
    echo -e "\n${BLUE}EventBridge Bus:${NC}"
    if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
        echo "  ✓ $EVENT_BUS_NAME (exists)"
    else
        echo "  ✗ $EVENT_BUS_NAME (not found)"
    fi
    
    echo -e "\n${YELLOW}To perform actual cleanup, run: ./destroy.sh${NC}"
    echo -e "${YELLOW}To force cleanup without confirmation, run: FORCE_DELETE=true ./destroy.sh${NC}"
    exit 0
}

# Delete EventBridge rules and targets
delete_eventbridge_resources() {
    progress "Deleting EventBridge rules and targets"
    
    # Remove targets first, then delete rules
    if [[ -n "$HEALTH_CHECK_RULE" ]]; then
        log_info "Removing targets from health check rule: ${HEALTH_CHECK_RULE}"
        aws events remove-targets \
            --rule "$HEALTH_CHECK_RULE" \
            --ids "1" 2>/dev/null || log_warning "Failed to remove targets from $HEALTH_CHECK_RULE"
        
        log_info "Deleting health check rule: ${HEALTH_CHECK_RULE}"
        aws events delete-rule \
            --name "$HEALTH_CHECK_RULE" 2>/dev/null || log_warning "Failed to delete rule $HEALTH_CHECK_RULE"
    fi
    
    if [[ -n "$CONFLICT_NOTIFICATION_RULE" ]]; then
        log_info "Deleting conflict notification rule: ${CONFLICT_NOTIFICATION_RULE}"
        aws events delete-rule \
            --name "$CONFLICT_NOTIFICATION_RULE" 2>/dev/null || log_warning "Failed to delete rule $CONFLICT_NOTIFICATION_RULE"
    fi
    
    # Delete custom EventBridge bus
    if [[ -n "$EVENT_BUS_NAME" ]]; then
        log_info "Deleting EventBridge bus: ${EVENT_BUS_NAME}"
        aws events delete-event-bus \
            --name "$EVENT_BUS_NAME" 2>/dev/null || log_warning "Failed to delete EventBridge bus $EVENT_BUS_NAME"
        log_success "EventBridge bus deleted: ${EVENT_BUS_NAME}"
    fi
    
    log_success "EventBridge resources cleanup completed"
}

# Delete Lambda functions and permissions
delete_lambda_functions() {
    progress "Deleting Lambda functions and permissions"
    
    # Delete conflict resolver Lambda function
    if [[ -n "$CONFLICT_RESOLVER_LAMBDA" ]]; then
        log_info "Deleting conflict resolver Lambda: ${CONFLICT_RESOLVER_LAMBDA}"
        aws lambda delete-function \
            --function-name "$CONFLICT_RESOLVER_LAMBDA" 2>/dev/null || log_warning "Failed to delete Lambda function $CONFLICT_RESOLVER_LAMBDA"
        log_success "Lambda function deleted: ${CONFLICT_RESOLVER_LAMBDA}"
    fi
    
    # Delete sync manager Lambda function
    if [[ -n "$SHADOW_SYNC_LAMBDA" ]]; then
        log_info "Deleting sync manager Lambda: ${SHADOW_SYNC_LAMBDA}"
        aws lambda delete-function \
            --function-name "$SHADOW_SYNC_LAMBDA" 2>/dev/null || log_warning "Failed to delete Lambda function $SHADOW_SYNC_LAMBDA"
        log_success "Lambda function deleted: ${SHADOW_SYNC_LAMBDA}"
    fi
    
    log_success "Lambda functions cleanup completed"
}

# Delete IoT rules and resources
delete_iot_resources() {
    progress "Deleting IoT rules, things, and certificates"
    
    # Delete IoT rules
    if [[ -n "$DELTA_RULE_NAME" ]]; then
        log_info "Deleting shadow delta processing rule: ${DELTA_RULE_NAME}"
        aws iot delete-topic-rule \
            --rule-name "$DELTA_RULE_NAME" 2>/dev/null || log_warning "Failed to delete IoT rule $DELTA_RULE_NAME"
        log_success "IoT rule deleted: ${DELTA_RULE_NAME}"
    fi
    
    if [[ -n "$AUDIT_RULE_NAME" ]]; then
        log_info "Deleting shadow audit logging rule: ${AUDIT_RULE_NAME}"
        aws iot delete-topic-rule \
            --rule-name "$AUDIT_RULE_NAME" 2>/dev/null || log_warning "Failed to delete IoT rule $AUDIT_RULE_NAME"
        log_success "IoT rule deleted: ${AUDIT_RULE_NAME}"
    fi
    
    # Delete IoT thing and certificates
    if [[ -n "$THING_NAME" ]]; then
        log_info "Cleaning up IoT thing: ${THING_NAME}"
        
        # Detach and delete certificates
        if [[ -n "$DEMO_CERT_ARN" ]] && [[ -n "$DEMO_CERT_ID" ]]; then
            log_info "Detaching certificate from thing"
            aws iot detach-thing-principal \
                --thing-name "$THING_NAME" \
                --principal "$DEMO_CERT_ARN" 2>/dev/null || log_warning "Failed to detach certificate from thing"
            
            if [[ -n "$DEMO_POLICY_NAME" ]]; then
                log_info "Detaching policy from certificate"
                aws iot detach-policy \
                    --policy-name "$DEMO_POLICY_NAME" \
                    --target "$DEMO_CERT_ARN" 2>/dev/null || log_warning "Failed to detach policy from certificate"
                
                log_info "Deleting IoT policy: ${DEMO_POLICY_NAME}"
                aws iot delete-policy \
                    --policy-name "$DEMO_POLICY_NAME" 2>/dev/null || log_warning "Failed to delete IoT policy $DEMO_POLICY_NAME"
            fi
            
            log_info "Deactivating and deleting certificate: ${DEMO_CERT_ID}"
            aws iot update-certificate \
                --certificate-id "$DEMO_CERT_ID" \
                --new-status INACTIVE 2>/dev/null || log_warning "Failed to deactivate certificate"
            
            aws iot delete-certificate \
                --certificate-id "$DEMO_CERT_ID" 2>/dev/null || log_warning "Failed to delete certificate"
        fi
        
        # Delete IoT thing
        log_info "Deleting IoT thing: ${THING_NAME}"
        aws iot delete-thing \
            --thing-name "$THING_NAME" 2>/dev/null || log_warning "Failed to delete IoT thing $THING_NAME"
        
        log_success "IoT thing deleted: ${THING_NAME}"
    fi
    
    # Delete IoT thing type
    log_info "Deleting IoT thing type: SyncDemoDevice"
    aws iot delete-thing-type \
        --thing-type-name "SyncDemoDevice" 2>/dev/null || log_warning "Failed to delete IoT thing type"
    
    log_success "IoT resources cleanup completed"
}

# Delete DynamoDB tables
delete_dynamodb_tables() {
    progress "Deleting DynamoDB tables"
    
    # Delete tables
    for table in "$SHADOW_HISTORY_TABLE" "$DEVICE_CONFIG_TABLE" "$SYNC_METRICS_TABLE"; do
        if [[ -n "$table" ]]; then
            log_info "Deleting DynamoDB table: ${table}"
            aws dynamodb delete-table \
                --table-name "$table" 2>/dev/null || log_warning "Failed to delete DynamoDB table $table"
            log_success "DynamoDB table deletion initiated: ${table}"
        fi
    done
    
    # Wait for tables to be deleted
    log_info "Waiting for DynamoDB tables to be deleted..."
    for table in "$SHADOW_HISTORY_TABLE" "$DEVICE_CONFIG_TABLE" "$SYNC_METRICS_TABLE"; do
        if [[ -n "$table" ]]; then
            aws dynamodb wait table-not-exists --table-name "$table" 2>/dev/null || log_warning "Table $table may still exist"
            log_success "Table confirmed deleted: ${table}"
        fi
    done
    
    log_success "DynamoDB tables cleanup completed"
}

# Delete IAM resources
delete_iam_resources() {
    progress "Deleting IAM roles and policies"
    
    # Detach and delete IAM policy
    if [[ -n "$POLICY_NAME" ]] && [[ -n "$EXECUTION_ROLE_NAME" ]]; then
        log_info "Detaching IAM policy from role"
        aws iam detach-role-policy \
            --role-name "$EXECUTION_ROLE_NAME" \
            --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null || log_warning "Failed to detach policy from role"
        
        log_info "Deleting IAM policy: ${POLICY_NAME}"
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null || log_warning "Failed to delete IAM policy $POLICY_NAME"
        
        log_success "IAM policy deleted: ${POLICY_NAME}"
    fi
    
    # Delete IAM role
    if [[ -n "$EXECUTION_ROLE_NAME" ]]; then
        log_info "Deleting IAM role: ${EXECUTION_ROLE_NAME}"
        aws iam delete-role \
            --role-name "$EXECUTION_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete IAM role $EXECUTION_ROLE_NAME"
        
        log_success "IAM role deleted: ${EXECUTION_ROLE_NAME}"
    fi
    
    log_success "IAM resources cleanup completed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    progress "Deleting CloudWatch dashboards and log groups"
    
    # Delete CloudWatch dashboard
    if [[ -n "$DASHBOARD_NAME" ]]; then
        log_info "Deleting CloudWatch dashboard: ${DASHBOARD_NAME}"
        aws cloudwatch delete-dashboards \
            --dashboard-names "$DASHBOARD_NAME" 2>/dev/null || log_warning "Failed to delete dashboard $DASHBOARD_NAME"
        log_success "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
    fi
    
    # Delete CloudWatch log groups
    if [[ -n "$AUDIT_LOG_GROUP" ]]; then
        log_info "Deleting CloudWatch log group: ${AUDIT_LOG_GROUP}"
        aws logs delete-log-group \
            --log-group-name "$AUDIT_LOG_GROUP" 2>/dev/null || log_warning "Failed to delete log group $AUDIT_LOG_GROUP"
        log_success "CloudWatch log group deleted: ${AUDIT_LOG_GROUP}"
    fi
    
    # Delete Lambda function log groups
    for lambda_func in "$CONFLICT_RESOLVER_LAMBDA" "$SHADOW_SYNC_LAMBDA"; do
        if [[ -n "$lambda_func" ]]; then
            log_group="/aws/lambda/${lambda_func}"
            log_info "Deleting Lambda log group: ${log_group}"
            aws logs delete-log-group \
                --log-group-name "$log_group" 2>/dev/null || log_warning "Failed to delete log group $log_group"
        fi
    done
    
    log_success "CloudWatch resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    progress "Cleaning up local files and certificates"
    
    # Remove certificate files
    local cert_files=("demo-device-certificate.pem" "demo-device-public-key.pem" "demo-device-private-key.pem" "demo-cert-output.json")
    for file in "${cert_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing certificate file: ${file}"
            rm -f "$file"
        fi
    done
    
    # Remove shadow output files
    local shadow_files=("configuration-shadow-output.json" "telemetry-shadow-output.json" "maintenance-shadow-output.json")
    for file in "${shadow_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing shadow output file: ${file}"
            rm -f "$file"
        fi
    done
    
    # Remove temporary files
    rm -f /tmp/shadow-* /tmp/demo-* 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Remove deployment configuration
remove_deployment_config() {
    progress "Removing deployment configuration"
    
    if [[ -f ".deployment-config" ]]; then
        log_info "Removing deployment configuration file"
        rm -f ".deployment-config"
        log_success "Deployment configuration removed"
    fi
    
    log_success "Configuration cleanup completed"
}

# Validate cleanup completion
validate_cleanup() {
    progress "Validating cleanup completion"
    
    local cleanup_issues=()
    
    # Check Lambda functions
    for lambda_func in "$CONFLICT_RESOLVER_LAMBDA" "$SHADOW_SYNC_LAMBDA"; do
        if [[ -n "$lambda_func" ]] && aws lambda get-function --function-name "$lambda_func" &>/dev/null; then
            cleanup_issues+=("Lambda function still exists: $lambda_func")
        fi
    done
    
    # Check DynamoDB tables
    for table in "$SHADOW_HISTORY_TABLE" "$DEVICE_CONFIG_TABLE" "$SYNC_METRICS_TABLE"; do
        if [[ -n "$table" ]] && aws dynamodb describe-table --table-name "$table" &>/dev/null; then
            cleanup_issues+=("DynamoDB table still exists: $table")
        fi
    done
    
    # Check IoT thing
    if [[ -n "$THING_NAME" ]] && aws iot describe-thing --thing-name "$THING_NAME" &>/dev/null; then
        cleanup_issues+=("IoT thing still exists: $THING_NAME")
    fi
    
    # Check EventBridge bus
    if [[ -n "$EVENT_BUS_NAME" ]] && aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
        cleanup_issues+=("EventBridge bus still exists: $EVENT_BUS_NAME")
    fi
    
    # Check IAM role
    if [[ -n "$EXECUTION_ROLE_NAME" ]] && aws iam get-role --role-name "$EXECUTION_ROLE_NAME" &>/dev/null; then
        cleanup_issues+=("IAM role still exists: $EXECUTION_ROLE_NAME")
    fi
    
    # Report cleanup status
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "All resources successfully cleaned up!"
        
        echo -e "\n${GREEN}=== CLEANUP SUMMARY ===${NC}"
        echo -e "${GREEN}✅ All AWS resources have been deleted${NC}"
        echo -e "${GREEN}✅ All local files have been removed${NC}"
        echo -e "${GREEN}✅ All configuration files have been cleaned up${NC}"
        
        echo -e "\n${BLUE}Cost Impact:${NC}"
        echo "• All ongoing charges for this deployment have been eliminated"
        echo "• You will only be charged for usage up to the deletion time"
        echo "• DynamoDB and CloudWatch Logs charges may continue briefly as data is purged"
        
        echo -e "\n${BLUE}Next Steps:${NC}"
        echo "• Review your AWS bill to confirm charge elimination"
        echo "• If you plan to redeploy, run ./deploy.sh again"
        echo "• Consider implementing cost alerts for future deployments"
        
    else
        log_warning "Some resources may not have been fully cleaned up:"
        for issue in "${cleanup_issues[@]}"; do
            echo -e "  ${YELLOW}⚠️  $issue${NC}"
        done
        
        echo -e "\n${YELLOW}Manual cleanup may be required for remaining resources.${NC}"
        echo -e "${YELLOW}Check the AWS Console to verify complete resource removal.${NC}"
    fi
}

# Error handling
handle_cleanup_error() {
    log_error "An error occurred during cleanup. Some resources may not have been deleted."
    log_info "Please check the AWS Console and manually delete any remaining resources."
    log_info "Common resources to check:"
    echo "  • Lambda functions: $CONFLICT_RESOLVER_LAMBDA, $SHADOW_SYNC_LAMBDA"
    echo "  • DynamoDB tables: $SHADOW_HISTORY_TABLE, $DEVICE_CONFIG_TABLE, $SYNC_METRICS_TABLE"
    echo "  • IoT thing: $THING_NAME"
    echo "  • EventBridge bus: $EVENT_BUS_NAME"
    echo "  • IAM role: $EXECUTION_ROLE_NAME"
    echo "  • CloudWatch dashboard and log groups"
    exit 1
}

# Main execution
main() {
    echo -e "${RED}Starting Advanced IoT Device Shadow Synchronization Cleanup${NC}\n"
    
    # Check if dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        load_deployment_config
        perform_dry_run
        exit 0
    fi
    
    # Set error handler
    trap handle_cleanup_error ERR
    
    # Execute cleanup steps
    load_deployment_config
    confirm_destruction
    delete_eventbridge_resources
    delete_lambda_functions
    delete_iot_resources
    delete_dynamodb_tables
    delete_iam_resources
    delete_cloudwatch_resources
    cleanup_local_files
    remove_deployment_config
    validate_cleanup
    
    echo -e "\n${GREEN}✅ Cleanup completed successfully!${NC}"
    echo -e "${BLUE}Total cleanup time: $(($(date +%s) - START_TIME)) seconds${NC}\n"
}

# Record start time
START_TIME=$(date +%s)

# Help message
show_help() {
    echo "Advanced IoT Device Shadow Synchronization - Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run          Show what would be deleted without actually deleting"
    echo "  --force            Skip confirmation prompt and delete immediately"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DRY_RUN=true       Enable dry run mode"
    echo "  FORCE_DELETE=true  Skip confirmation prompt"
    echo "  AWS_REGION         Override AWS region"
    echo ""
    echo "Examples:"
    echo "  $0                 # Interactive cleanup with confirmation"
    echo "  $0 --dry-run       # Preview what would be deleted"
    echo "  $0 --force         # Delete without confirmation"
    echo "  DRY_RUN=true $0    # Dry run via environment variable"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi