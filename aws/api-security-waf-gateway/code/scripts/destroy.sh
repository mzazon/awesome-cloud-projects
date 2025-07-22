#!/bin/bash

# Destroy script for API Access WAF Gateway Recipe
# This script safely removes all AWS resources created by the deploy script

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Get caller identity
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    log "Authenticated as: $(echo $CALLER_IDENTITY | jq -r '.Arn' 2>/dev/null || echo "$(echo $CALLER_IDENTITY | grep -o '"Arn":"[^"]*"' | cut -d'"' -f4)")"
    
    success "Prerequisites check completed successfully"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check for deployment state file from command line argument
    if [ $# -gt 0 ] && [ -f "$1/deployment-state.txt" ]; then
        STATE_FILE="$1/deployment-state.txt"
        log "Loading state from provided path: $STATE_FILE"
    else
        # Try to find the most recent deployment state file
        STATE_FILES=$(find /tmp -name "deployment-state.txt" -path "*/waf-api-deployment-*" 2>/dev/null | sort -r)
        
        if [ -z "$STATE_FILES" ]; then
            warn "No deployment state file found. Will attempt manual cleanup."
            return 1
        fi
        
        # Use the most recent state file
        STATE_FILE=$(echo "$STATE_FILES" | head -1)
        log "Found deployment state file: $STATE_FILE"
    fi
    
    # Source the state file to load variables
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
        export WAF_WEB_ACL_NAME API_NAME LOG_GROUP_NAME WEB_ACL_ID API_ID WEB_ACL_ARN AWS_REGION AWS_ACCOUNT_ID TEMP_DIR
        
        log "Loaded deployment state:"
        log "  WAF Web ACL Name: $WAF_WEB_ACL_NAME"
        log "  API Name: $API_NAME"
        log "  AWS Region: $AWS_REGION"
        log "  Temp Directory: $TEMP_DIR"
        
        return 0
    else
        warn "Deployment state file not found or not readable"
        return 1
    fi
}

# Function to prompt for manual input if state is not available
prompt_manual_input() {
    log "Manual cleanup mode - please provide resource information"
    
    echo -n "Enter WAF Web ACL Name (or press Enter to skip): "
    read -r WAF_WEB_ACL_NAME
    
    echo -n "Enter API Gateway Name (or press Enter to skip): "
    read -r API_NAME
    
    echo -n "Enter CloudWatch Log Group Name (or press Enter to skip): "
    read -r LOG_GROUP_NAME
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region set, using us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Manual input completed"
}

# Function to find resources by tags or naming patterns
discover_resources() {
    log "Discovering resources to clean up..."
    
    # If we have resource names, try to find their IDs
    if [ -n "${WAF_WEB_ACL_NAME:-}" ]; then
        log "Looking for WAF Web ACL: $WAF_WEB_ACL_NAME"
        WEB_ACL_ID=$(aws wafv2 list-web-acls --scope REGIONAL \
            --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME'].Id" --output text 2>/dev/null || echo "")
        
        if [ -n "$WEB_ACL_ID" ] && [ "$WEB_ACL_ID" != "None" ]; then
            log "Found WAF Web ACL ID: $WEB_ACL_ID"
            
            # Get WAF ARN
            WEB_ACL_ARN=$(aws wafv2 get-web-acl \
                --id "$WEB_ACL_ID" \
                --name "$WAF_WEB_ACL_NAME" \
                --scope REGIONAL \
                --query 'WebACL.ARN' --output text 2>/dev/null || echo "")
        fi
    fi
    
    if [ -n "${API_NAME:-}" ]; then
        log "Looking for API Gateway: $API_NAME"
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='$API_NAME'].id" --output text 2>/dev/null || echo "")
        
        if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
            log "Found API Gateway ID: $API_ID"
        fi
    fi
    
    # List all resources with naming pattern for orphaned cleanup
    log "Scanning for resources with 'api-security-acl-' or 'protected-api-' naming pattern..."
    
    # Find WAF Web ACLs
    ORPHANED_WACLS=$(aws wafv2 list-web-acls --scope REGIONAL \
        --query "WebACLs[?starts_with(Name, 'api-security-acl-')].[Name,Id]" --output text 2>/dev/null || echo "")
    
    # Find API Gateways
    ORPHANED_APIS=$(aws apigateway get-rest-apis \
        --query "items[?starts_with(name, 'protected-api-')].[name,id]" --output text 2>/dev/null || echo "")
    
    # Find CloudWatch Log Groups
    ORPHANED_LOGS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/waf/api-security-acl-" \
        --query "logGroups[].logGroupName" --output text 2>/dev/null || echo "")
    
    if [ -n "$ORPHANED_WACLS" ]; then
        warn "Found orphaned WAF Web ACLs:"
        echo "$ORPHANED_WACLS"
    fi
    
    if [ -n "$ORPHANED_APIS" ]; then
        warn "Found orphaned API Gateways:"
        echo "$ORPHANED_APIS"
    fi
    
    if [ -n "$ORPHANED_LOGS" ]; then
        warn "Found orphaned CloudWatch Log Groups:"
        echo "$ORPHANED_LOGS"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "Resources to be destroyed:"
    echo "=========================="
    
    [ -n "${WAF_WEB_ACL_NAME:-}" ] && echo "- WAF Web ACL: $WAF_WEB_ACL_NAME (ID: ${WEB_ACL_ID:-unknown})"
    [ -n "${API_NAME:-}" ] && echo "- API Gateway: $API_NAME (ID: ${API_ID:-unknown})"
    [ -n "${LOG_GROUP_NAME:-}" ] && echo "- CloudWatch Log Group: $LOG_GROUP_NAME"
    
    if [ -n "$ORPHANED_WACLS" ]; then
        echo "- Orphaned WAF Web ACLs: $(echo "$ORPHANED_WACLS" | wc -l) found"
    fi
    
    if [ -n "$ORPHANED_APIS" ]; then
        echo "- Orphaned API Gateways: $(echo "$ORPHANED_APIS" | wc -l) found"
    fi
    
    if [ -n "$ORPHANED_LOGS" ]; then
        echo "- Orphaned Log Groups: $(echo "$ORPHANED_LOGS" | wc -l) found"
    fi
    
    echo ""
    warn "This action cannot be undone!"
    echo -n "Are you sure you want to destroy these resources? (yes/no): "
    read -r CONFIRMATION
    
    if [ "$CONFIRMATION" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    if [ -n "${WAF_WEB_ACL_NAME:-}" ]; then
        ALARM_NAME="${WAF_WEB_ACL_NAME}-HighBlockedRequests"
        
        if aws cloudwatch describe-alarms --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0]' --output text &> /dev/null; then
            aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME"
            success "Removed CloudWatch alarm: $ALARM_NAME"
        else
            warn "CloudWatch alarm not found: $ALARM_NAME"
        fi
    fi
}

# Function to disassociate WAF from API Gateway
disassociate_waf() {
    log "Disassociating WAF from API Gateway..."
    
    if [ -n "${API_ID:-}" ] && [ -n "${AWS_REGION:-}" ]; then
        RESOURCE_ARN="arn:aws:apigateway:${AWS_REGION}::/restapis/${API_ID}/stages/prod"
        
        # Check if association exists
        if aws wafv2 get-web-acl-for-resource --resource-arn "$RESOURCE_ARN" &> /dev/null; then
            aws wafv2 disassociate-web-acl --resource-arn "$RESOURCE_ARN"
            success "WAF disassociated from API Gateway stage"
            
            # Wait a moment for disassociation to complete
            sleep 5
        else
            warn "No WAF association found for API Gateway stage"
        fi
    else
        warn "API ID or region not available for WAF disassociation"
    fi
}

# Function to delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway..."
    
    if [ -n "${API_ID:-}" ]; then
        # Check if API exists
        if aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
            aws apigateway delete-rest-api --rest-api-id "$API_ID"
            success "API Gateway deleted: $API_ID"
        else
            warn "API Gateway not found: $API_ID"
        fi
    fi
    
    # Clean up orphaned APIs
    if [ -n "$ORPHANED_APIS" ]; then
        log "Cleaning up orphaned API Gateways..."
        echo "$ORPHANED_APIS" | while read -r API_NAME_ORPHAN API_ID_ORPHAN; do
            if [ -n "$API_ID_ORPHAN" ] && [ "$API_ID_ORPHAN" != "None" ]; then
                aws apigateway delete-rest-api --rest-api-id "$API_ID_ORPHAN" || warn "Failed to delete API: $API_ID_ORPHAN"
                success "Deleted orphaned API Gateway: $API_NAME_ORPHAN ($API_ID_ORPHAN)"
            fi
        done
    fi
}

# Function to disable WAF logging and delete Web ACL
delete_waf_web_acl() {
    log "Disabling WAF logging and deleting Web ACL..."
    
    if [ -n "${WEB_ACL_ARN:-}" ]; then
        # Remove WAF logging configuration
        if aws wafv2 get-logging-configuration --resource-arn "$WEB_ACL_ARN" &> /dev/null; then
            aws wafv2 delete-logging-configuration --resource-arn "$WEB_ACL_ARN" --region "$AWS_REGION"
            success "WAF logging configuration removed"
            
            # Wait for logging to be fully disabled
            sleep 5
        else
            warn "No WAF logging configuration found"
        fi
    fi
    
    if [ -n "${WEB_ACL_ID:-}" ] && [ -n "${WAF_WEB_ACL_NAME:-}" ]; then
        # Get current lock token
        LOCK_TOKEN=$(aws wafv2 get-web-acl \
            --id "$WEB_ACL_ID" \
            --name "$WAF_WEB_ACL_NAME" \
            --scope REGIONAL \
            --query 'LockToken' --output text 2>/dev/null || echo "")
        
        if [ -n "$LOCK_TOKEN" ] && [ "$LOCK_TOKEN" != "None" ]; then
            aws wafv2 delete-web-acl \
                --id "$WEB_ACL_ID" \
                --name "$WAF_WEB_ACL_NAME" \
                --scope REGIONAL \
                --lock-token "$LOCK_TOKEN"
            success "WAF Web ACL deleted: $WAF_WEB_ACL_NAME"
        else
            warn "Could not get lock token for WAF Web ACL: $WAF_WEB_ACL_NAME"
        fi
    fi
    
    # Clean up orphaned WAF Web ACLs
    if [ -n "$ORPHANED_WACLS" ]; then
        log "Cleaning up orphaned WAF Web ACLs..."
        echo "$ORPHANED_WACLS" | while read -r WACL_NAME_ORPHAN WACL_ID_ORPHAN; do
            if [ -n "$WACL_ID_ORPHAN" ] && [ "$WACL_ID_ORPHAN" != "None" ]; then
                # Try to get lock token and delete
                ORPHAN_LOCK_TOKEN=$(aws wafv2 get-web-acl \
                    --id "$WACL_ID_ORPHAN" \
                    --name "$WACL_NAME_ORPHAN" \
                    --scope REGIONAL \
                    --query 'LockToken' --output text 2>/dev/null || echo "")
                
                if [ -n "$ORPHAN_LOCK_TOKEN" ] && [ "$ORPHAN_LOCK_TOKEN" != "None" ]; then
                    # Try to disable logging first
                    ORPHAN_ARN=$(aws wafv2 get-web-acl \
                        --id "$WACL_ID_ORPHAN" \
                        --name "$WACL_NAME_ORPHAN" \
                        --scope REGIONAL \
                        --query 'WebACL.ARN' --output text 2>/dev/null || echo "")
                    
                    if [ -n "$ORPHAN_ARN" ]; then
                        aws wafv2 delete-logging-configuration --resource-arn "$ORPHAN_ARN" --region "$AWS_REGION" 2>/dev/null || true
                        sleep 2
                    fi
                    
                    aws wafv2 delete-web-acl \
                        --id "$WACL_ID_ORPHAN" \
                        --name "$WACL_NAME_ORPHAN" \
                        --scope REGIONAL \
                        --lock-token "$ORPHAN_LOCK_TOKEN" || warn "Failed to delete WAF Web ACL: $WACL_NAME_ORPHAN"
                    success "Deleted orphaned WAF Web ACL: $WACL_NAME_ORPHAN ($WACL_ID_ORPHAN)"
                fi
            fi
        done
    fi
}

# Function to delete CloudWatch log groups
delete_log_groups() {
    log "Deleting CloudWatch log groups..."
    
    if [ -n "${LOG_GROUP_NAME:-}" ]; then
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
            --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" --output text | grep -q "$LOG_GROUP_NAME"; then
            aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
            success "CloudWatch log group deleted: $LOG_GROUP_NAME"
        else
            warn "CloudWatch log group not found: $LOG_GROUP_NAME"
        fi
    fi
    
    # Clean up orphaned log groups
    if [ -n "$ORPHANED_LOGS" ]; then
        log "Cleaning up orphaned CloudWatch log groups..."
        echo "$ORPHANED_LOGS" | while read -r LOG_GROUP_ORPHAN; do
            if [ -n "$LOG_GROUP_ORPHAN" ]; then
                aws logs delete-log-group --log-group-name "$LOG_GROUP_ORPHAN" || warn "Failed to delete log group: $LOG_GROUP_ORPHAN"
                success "Deleted orphaned log group: $LOG_GROUP_ORPHAN"
            fi
        done
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        success "Temporary directory removed: $TEMP_DIR"
    fi
    
    # Clean up any other temporary files
    TEMP_FILES="/tmp/web-acl-id.txt /tmp/api-id.txt /tmp/root-resource-id.txt /tmp/test-resource-id.txt /tmp/web-acl-arn.txt /tmp/latest-stream.txt /tmp/api-endpoint.txt"
    for TEMP_FILE in $TEMP_FILES; do
        if [ -f "$TEMP_FILE" ]; then
            rm -f "$TEMP_FILE"
            log "Removed temporary file: $TEMP_FILE"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    REMAINING_RESOURCES=0
    
    # Check for remaining WAF Web ACLs
    if [ -n "${WAF_WEB_ACL_NAME:-}" ]; then
        REMAINING_WACL=$(aws wafv2 list-web-acls --scope REGIONAL \
            --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME'].Id" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_WACL" ] && [ "$REMAINING_WACL" != "None" ]; then
            warn "WAF Web ACL still exists: $WAF_WEB_ACL_NAME"
            REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
        fi
    fi
    
    # Check for remaining APIs
    if [ -n "${API_NAME:-}" ]; then
        REMAINING_API=$(aws apigateway get-rest-apis \
            --query "items[?name=='$API_NAME'].id" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_API" ] && [ "$REMAINING_API" != "None" ]; then
            warn "API Gateway still exists: $API_NAME"
            REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
        fi
    fi
    
    # Check for remaining log groups
    if [ -n "${LOG_GROUP_NAME:-}" ]; then
        REMAINING_LOG=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
            --query "logGroups[?logGroupName=='$LOG_GROUP_NAME'].logGroupName" --output text 2>/dev/null || echo "")
        if [ -n "$REMAINING_LOG" ]; then
            warn "CloudWatch log group still exists: $LOG_GROUP_NAME"
            REMAINING_RESOURCES=$((REMAINING_RESOURCES + 1))
        fi
    fi
    
    if [ $REMAINING_RESOURCES -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        warn "$REMAINING_RESOURCES resource(s) may still exist. Manual cleanup may be required."
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been removed:"
    echo "- WAF Web ACL and associated rules"
    echo "- API Gateway REST API and resources"
    echo "- CloudWatch log groups and alarms"
    echo "- WAF logging configurations"
    echo "- Temporary files and directories"
    echo ""
    success "Cleanup completed successfully!"
    echo ""
    log "Note: It may take a few minutes for all resources to be fully removed from the AWS console."
}

# Main execution
main() {
    log "Starting AWS WAF API Gateway cleanup..."
    
    check_prerequisites
    
    # Try to load deployment state, fall back to manual input if needed
    if ! load_deployment_state "$@"; then
        prompt_manual_input
    fi
    
    discover_resources
    confirm_destruction
    remove_cloudwatch_alarms
    disassociate_waf
    delete_api_gateway
    delete_waf_web_acl
    delete_log_groups
    cleanup_temp_files
    verify_cleanup
    display_summary
    
    success "Destruction completed successfully!"
}

# Trap cleanup on exit
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Cleanup failed. Check the logs above for details."
        warn "Some resources may still exist and require manual cleanup."
        warn "Check the AWS console for any remaining resources."
    fi
}

trap cleanup_on_exit EXIT

# Show usage if help is requested
if [ $# -gt 0 ] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [TEMP_DIR]"
    echo ""
    echo "Destroys AWS resources created by the WAF API Gateway recipe."
    echo ""
    echo "Arguments:"
    echo "  TEMP_DIR    Optional path to the deployment temporary directory"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Auto-discover resources"
    echo "  $0 /tmp/waf-api-deployment-abc123    # Use specific temp directory"
    echo ""
    echo "The script will attempt to find deployment state automatically."
    echo "If not found, it will prompt for manual input of resource names."
    exit 0
fi

# Run main function
main "$@"