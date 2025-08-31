#!/bin/bash

# Destroy script for Interactive Business Process Automation with Bedrock Agents and EventBridge
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"
DRY_RUN=false
FORCE_DESTROY=false
INTERACTIVE=true

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Interactive Business Process Automation with Bedrock Agents and EventBridge

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be destroyed without actually destroying
    -f, --force         Force destruction without confirmation prompts
    -y, --yes           Non-interactive mode (same as --force)
    -c, --config FILE   Use specific config file (default: .deploy-config)

EXAMPLES:
    $0                  # Destroy with confirmation prompts
    $0 --dry-run        # Preview what would be destroyed
    $0 --force          # Destroy without prompts
    $0 --config my-config  # Use custom config file

NOTES:
    - This script reads configuration from .deploy-config created during deployment
    - Resources are destroyed in reverse order of creation for safety
    - Some resources may take several minutes to fully delete

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force|-y|--yes)
            FORCE_DESTROY=true
            INTERACTIVE=false
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

log "Starting destruction of Interactive Business Process Automation resources"

# Load configuration
load_configuration() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file not found: $CONFIG_FILE"
        error "Make sure you run this script from the same location as deploy.sh"
        exit 1
    fi
    
    log "Loading configuration from: $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # Validate required variables
    required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "PROJECT_NAME" 
        "S3_BUCKET" "AGENT_NAME" "EVENT_BUS_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in configuration"
            exit 1
        fi
    done
    
    # Set derived variables
    export AGENT_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-agent-role"
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-execution-role"
    
    success "Configuration loaded: Project ${PROJECT_NAME} in ${AWS_REGION}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo ""
        warning "This will permanently destroy the following resources:"
        echo "  • Project: ${PROJECT_NAME}"
        echo "  • S3 Bucket: ${S3_BUCKET} (and all contents)"
        echo "  • Bedrock Agent: ${AGENT_NAME}"
        echo "  • EventBridge Bus: ${EVENT_BUS_NAME}"
        echo "  • Lambda Functions: ${PROJECT_NAME}-*"
        echo "  • IAM Roles and Policies"
        echo "  • EventBridge Rules and Targets"
        echo ""
        
        if [[ "$DRY_RUN" == "false" ]]; then
            echo -n "Are you sure you want to continue? (type 'DELETE' to confirm): "
            read -r confirmation
            
            if [[ "$confirmation" != "DELETE" ]]; then
                log "Destruction cancelled by user"
                exit 0
            fi
        fi
    fi
    
    log "Proceeding with resource destruction..."
}

# Remove Bedrock Agent and related resources
destroy_bedrock_agent() {
    log "Destroying Bedrock Agent and related resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would destroy Bedrock Agent: ${AGENT_NAME}"
        return 0
    fi
    
    # Get agent ID if available
    if [[ -n "${AGENT_ID:-}" ]]; then
        log "Using Agent ID from config: ${AGENT_ID}"
    else
        AGENT_ID=$(aws bedrock-agent list-agents \
            --query "agentSummaries[?agentName=='${AGENT_NAME}'].agentId" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$AGENT_ID" && "$AGENT_ID" != "None" ]]; then
        log "Destroying agent: ${AGENT_ID}"
        
        # Delete agent aliases first
        ALIASES=$(aws bedrock-agent list-agent-aliases \
            --agent-id "${AGENT_ID}" \
            --query "agentAliasSummaries[].agentAliasId" \
            --output text 2>/dev/null || echo "")
        
        for alias_id in $ALIASES; do
            if [[ "$alias_id" != "None" && -n "$alias_id" ]]; then
                log "Deleting agent alias: ${alias_id}"
                aws bedrock-agent delete-agent-alias \
                    --agent-id "${AGENT_ID}" \
                    --agent-alias-id "${alias_id}" || true
            fi
        done
        
        # Delete action groups
        ACTION_GROUPS=$(aws bedrock-agent list-agent-action-groups \
            --agent-id "${AGENT_ID}" \
            --agent-version "DRAFT" \
            --query "actionGroupSummaries[].actionGroupId" \
            --output text 2>/dev/null || echo "")
        
        for action_group_id in $ACTION_GROUPS; do
            if [[ "$action_group_id" != "None" && -n "$action_group_id" ]]; then
                log "Deleting action group: ${action_group_id}"
                aws bedrock-agent delete-agent-action-group \
                    --agent-id "${AGENT_ID}" \
                    --agent-version "DRAFT" \
                    --action-group-id "${action_group_id}" || true
            fi
        done
        
        # Delete the agent
        log "Deleting agent: ${AGENT_ID}"
        aws bedrock-agent delete-agent \
            --agent-id "${AGENT_ID}" \
            --skip-resource-in-use-check || true
        
        success "Bedrock Agent destroyed"
    else
        warning "Bedrock Agent not found or already deleted"
    fi
}

# Remove EventBridge resources
destroy_eventbridge_resources() {
    log "Destroying EventBridge resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would destroy EventBridge rules and event bus"
        return 0
    fi
    
    # Remove EventBridge rules and targets
    for rule_type in approval processing alert; do
        rule_name="${PROJECT_NAME}-${rule_type}-rule"
        
        log "Removing targets from rule: ${rule_name}"
        aws events remove-targets \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --rule "${rule_name}" \
            --ids "1" 2>/dev/null || true
        
        log "Deleting rule: ${rule_name}"
        aws events delete-rule \
            --event-bus-name "${EVENT_BUS_NAME}" \
            --name "${rule_name}" 2>/dev/null || true
    done
    
    # Delete custom event bus
    log "Deleting event bus: ${EVENT_BUS_NAME}"
    aws events delete-event-bus \
        --name "${EVENT_BUS_NAME}" 2>/dev/null || true
    
    success "EventBridge resources destroyed"
}

# Remove Lambda functions
destroy_lambda_functions() {
    log "Destroying Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would destroy Lambda functions: ${PROJECT_NAME}-*"
        return 0
    fi
    
    # Delete Lambda functions
    for function_type in approval processing notification agent-action; do
        function_name="${PROJECT_NAME}-${function_type}"
        
        log "Deleting Lambda function: ${function_name}"
        
        # Remove EventBridge permissions first
        aws lambda remove-permission \
            --function-name "${function_name}" \
            --statement-id "eventbridge-${function_type}-invoke" 2>/dev/null || true
        
        # Delete the function
        aws lambda delete-function \
            --function-name "${function_name}" 2>/dev/null || true
    done
    
    success "Lambda functions destroyed"
}

# Remove IAM resources
destroy_iam_resources() {
    log "Destroying IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would destroy IAM roles and policies"
        return 0
    fi
    
    # Detach and delete Lambda execution role
    log "Removing Lambda execution role..."
    aws iam detach-role-policy \
        --role-name "${PROJECT_NAME}-lambda-execution-role" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
    
    aws iam delete-role \
        --role-name "${PROJECT_NAME}-lambda-execution-role" 2>/dev/null || true
    
    # Detach and delete Bedrock agent policy and role
    log "Removing Bedrock agent IAM resources..."
    aws iam detach-role-policy \
        --role-name "${PROJECT_NAME}-agent-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-agent-policy" 2>/dev/null || true
    
    aws iam delete-policy \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-agent-policy" 2>/dev/null || true
    
    aws iam delete-role \
        --role-name "${PROJECT_NAME}-agent-role" 2>/dev/null || true
    
    success "IAM resources destroyed"
}

# Remove S3 resources
destroy_s3_bucket() {
    log "Destroying S3 bucket and contents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would destroy S3 bucket: ${S3_BUCKET}"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null; then
        log "Removing all objects from bucket..."
        
        # Delete all object versions and delete markers
        aws s3api list-object-versions \
            --bucket "${S3_BUCKET}" \
            --output json \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' | \
        jq -r '.[] | "--key \"\(.Key)\" --version-id \(.VersionId)"' | \
        while read -r line; do
            eval "aws s3api delete-object --bucket \"${S3_BUCKET}\" $line" 2>/dev/null || true
        done
        
        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "${S3_BUCKET}" \
            --output json \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' | \
        jq -r '.[] | "--key \"\(.Key)\" --version-id \(.VersionId)"' | \
        while read -r line; do
            eval "aws s3api delete-object --bucket \"${S3_BUCKET}\" $line" 2>/dev/null || true
        done
        
        # Remove remaining objects
        aws s3 rm "s3://${S3_BUCKET}" --recursive 2>/dev/null || true
        
        # Delete the bucket
        log "Deleting S3 bucket: ${S3_BUCKET}"
        aws s3 rb "s3://${S3_BUCKET}" --force 2>/dev/null || true
        
        success "S3 bucket destroyed"
    else
        warning "S3 bucket not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up temporary files"
        return 0
    fi
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "${SCRIPT_DIR}/agent-trust-policy.json"
        "${SCRIPT_DIR}/agent-permissions-policy.json"
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/action-schema.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing file: $(basename "$file")"
            rm -f "$file"
        fi
    done
    
    success "Local files cleaned up"
}

# Wait for resource deletion
wait_for_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Waiting for resources to be fully deleted..."
    
    # Wait for S3 bucket deletion
    local retries=0
    while aws s3api head-bucket --bucket "${S3_BUCKET}" 2>/dev/null && [ $retries -lt 30 ]; do
        log "Waiting for S3 bucket deletion..."
        sleep 10
        ((retries++))
    done
    
    success "Resource deletion completed"
}

# Generate destruction summary
generate_summary() {
    log "Destruction Summary:"
    echo "  Project Name: ${PROJECT_NAME}"
    echo "  Region: ${AWS_REGION}"
    echo "  Destruction Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Resources destroyed:"
        echo "  ✅ Bedrock Agent and aliases"
        echo "  ✅ EventBridge rules and event bus"
        echo "  ✅ Lambda functions"
        echo "  ✅ IAM roles and policies"
        echo "  ✅ S3 bucket and contents"
        echo "  ✅ Local temporary files"
        echo ""
        echo "Configuration file preserved: ${CONFIG_FILE}"
        echo "To remove configuration: rm ${CONFIG_FILE}"
    else
        echo "This was a dry run. No resources were actually destroyed."
        echo "Run without --dry-run to perform actual destruction."
    fi
}

# Main destruction workflow
destroy_solution() {
    load_configuration
    confirm_destruction
    
    # Destroy resources in reverse order of creation
    destroy_bedrock_agent
    destroy_eventbridge_resources
    destroy_lambda_functions
    destroy_iam_resources
    destroy_s3_bucket
    cleanup_local_files
    wait_for_deletion
    
    success "Destruction completed successfully!"
    generate_summary
}

# Error handling
handle_error() {
    error "Destruction failed at step: ${BASH_COMMAND}"
    error "Check the logs above for details"
    
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo ""
        echo "Some resources may have been partially destroyed."
        echo "You may need to clean up remaining resources manually."
        echo "Check the AWS Console for any remaining resources."
    fi
    
    exit 1
}

# Set error trap
trap handle_error ERR

# Main execution
destroy_solution

exit 0