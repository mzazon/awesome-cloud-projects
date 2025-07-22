#!/bin/bash

# Destroy script for Microservices Orchestration with AWS Step Functions
# This script safely removes all deployed resources

set -e  # Exit on any error

# Colors for output
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
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region set. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment setup complete"
}

# Discover deployed resources
discover_resources() {
    log "Discovering deployed resources..."
    
    # Find Step Functions state machines
    STATE_MACHINES=$(aws stepfunctions list-state-machines \
        --query 'stateMachines[?contains(name, `microservices-stepfn`)].{name:name,arn:stateMachineArn}' \
        --output text)
    
    # Find Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `microservices-stepfn`)].FunctionName' \
        --output text)
    
    # Find EventBridge rules
    EVENTBRIDGE_RULES=$(aws events list-rules \
        --query 'Rules[?contains(Name, `microservices-stepfn`)].Name' \
        --output text)
    
    # Find IAM roles
    IAM_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `microservices-stepfn`)].RoleName' \
        --output text)
    
    # Display discovered resources
    echo ""
    info "📋 Discovered Resources:"
    if [ ! -z "$STATE_MACHINES" ]; then
        echo "   • Step Functions State Machines:"
        echo "$STATE_MACHINES" | while read name arn; do
            echo "     - $name"
        done
    fi
    
    if [ ! -z "$LAMBDA_FUNCTIONS" ]; then
        echo "   • Lambda Functions:"
        echo "$LAMBDA_FUNCTIONS" | tr '\t' '\n' | while read func; do
            echo "     - $func"
        done
    fi
    
    if [ ! -z "$EVENTBRIDGE_RULES" ]; then
        echo "   • EventBridge Rules:"
        echo "$EVENTBRIDGE_RULES" | tr '\t' '\n' | while read rule; do
            echo "     - $rule"
        done
    fi
    
    if [ ! -z "$IAM_ROLES" ]; then
        echo "   • IAM Roles:"
        echo "$IAM_ROLES" | tr '\t' '\n' | while read role; do
            echo "     - $role"
        done
    fi
    
    if [ -z "$STATE_MACHINES" ] && [ -z "$LAMBDA_FUNCTIONS" ] && [ -z "$EVENTBRIDGE_RULES" ] && [ -z "$IAM_ROLES" ]; then
        warning "No microservices-stepfn resources found to delete"
        return 1
    fi
    
    echo ""
    success "Resource discovery complete"
}

# Confirm destruction
confirm_destruction() {
    echo ""
    warning "⚠️  DANGER ZONE ⚠️"
    echo "This will permanently delete ALL discovered microservices Step Functions resources!"
    echo "This action cannot be undone."
    echo ""
    
    if [ "$1" != "--force" ]; then
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        if [ "$confirmation" != "yes" ]; then
            info "Destruction cancelled by user"
            exit 0
        fi
        
        echo ""
        read -p "Are you ABSOLUTELY sure? This will delete everything! (type 'DELETE' to confirm): " final_confirmation
        if [ "$final_confirmation" != "DELETE" ]; then
            info "Destruction cancelled by user"
            exit 0
        fi
    else
        warning "Force mode enabled - skipping confirmation prompts"
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Delete Step Functions state machines
delete_step_functions() {
    if [ -z "$STATE_MACHINES" ]; then
        return 0
    fi
    
    log "Deleting Step Functions state machines..."
    
    echo "$STATE_MACHINES" | while read name arn; do
        if [ ! -z "$name" ]; then
            log "Deleting state machine: $name"
            
            # Stop any running executions
            RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
                --state-machine-arn "$arn" \
                --status-filter RUNNING \
                --query 'executions[].executionArn' \
                --output text 2>/dev/null || echo "")
            
            if [ ! -z "$RUNNING_EXECUTIONS" ]; then
                warning "Stopping running executions for $name..."
                echo "$RUNNING_EXECUTIONS" | tr '\t' '\n' | while read exec_arn; do
                    if [ ! -z "$exec_arn" ]; then
                        aws stepfunctions stop-execution --execution-arn "$exec_arn" &> /dev/null || true
                    fi
                done
                # Wait for executions to stop
                sleep 5
            fi
            
            # Delete state machine
            aws stepfunctions delete-state-machine --state-machine-arn "$arn" || warning "Failed to delete state machine $name"
            success "Deleted state machine: $name"
        fi
    done
}

# Delete EventBridge rules and targets
delete_eventbridge() {
    if [ -z "$EVENTBRIDGE_RULES" ]; then
        return 0
    fi
    
    log "Deleting EventBridge rules..."
    
    echo "$EVENTBRIDGE_RULES" | tr '\t' '\n' | while read rule; do
        if [ ! -z "$rule" ]; then
            log "Deleting EventBridge rule: $rule"
            
            # Remove targets first
            TARGETS=$(aws events list-targets-by-rule --rule "$rule" \
                --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [ ! -z "$TARGETS" ]; then
                aws events remove-targets --rule "$rule" --ids $TARGETS &> /dev/null || true
            fi
            
            # Delete rule
            aws events delete-rule --name "$rule" || warning "Failed to delete EventBridge rule $rule"
            success "Deleted EventBridge rule: $rule"
        fi
    done
}

# Delete Lambda functions
delete_lambda_functions() {
    if [ -z "$LAMBDA_FUNCTIONS" ]; then
        return 0
    fi
    
    log "Deleting Lambda functions..."
    
    echo "$LAMBDA_FUNCTIONS" | tr '\t' '\n' | while read func; do
        if [ ! -z "$func" ]; then
            log "Deleting Lambda function: $func"
            aws lambda delete-function --function-name "$func" || warning "Failed to delete Lambda function $func"
            success "Deleted Lambda function: $func"
        fi
    done
}

# Delete IAM roles
delete_iam_roles() {
    if [ -z "$IAM_ROLES" ]; then
        return 0
    fi
    
    log "Deleting IAM roles..."
    
    echo "$IAM_ROLES" | tr '\t' '\n' | while read role; do
        if [ ! -z "$role" ]; then
            log "Deleting IAM role: $role"
            
            # Detach all policies first
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" \
                --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            if [ ! -z "$ATTACHED_POLICIES" ]; then
                echo "$ATTACHED_POLICIES" | tr '\t' '\n' | while read policy_arn; do
                    if [ ! -z "$policy_arn" ]; then
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" &> /dev/null || true
                    fi
                done
            fi
            
            # Delete inline policies
            INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" \
                --query 'PolicyNames' --output text 2>/dev/null || echo "")
            
            if [ ! -z "$INLINE_POLICIES" ]; then
                echo "$INLINE_POLICIES" | tr '\t' '\n' | while read policy_name; do
                    if [ ! -z "$policy_name" ]; then
                        aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" &> /dev/null || true
                    fi
                done
            fi
            
            # Delete role
            aws iam delete-role --role-name "$role" || warning "Failed to delete IAM role $role"
            success "Deleted IAM role: $role"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might be left over
    rm -f *.py *.zip *.json user-response.json stepfunctions-definition.json &> /dev/null || true
    
    success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check for remaining resources
    REMAINING_STATE_MACHINES=$(aws stepfunctions list-state-machines \
        --query 'stateMachines[?contains(name, `microservices-stepfn`)].name' \
        --output text)
    
    REMAINING_LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `microservices-stepfn`)].FunctionName' \
        --output text)
    
    REMAINING_EVENTBRIDGE_RULES=$(aws events list-rules \
        --query 'Rules[?contains(Name, `microservices-stepfn`)].Name' \
        --output text)
    
    REMAINING_IAM_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `microservices-stepfn`)].RoleName' \
        --output text)
    
    if [ ! -z "$REMAINING_STATE_MACHINES" ] || [ ! -z "$REMAINING_LAMBDA_FUNCTIONS" ] || 
       [ ! -z "$REMAINING_EVENTBRIDGE_RULES" ] || [ ! -z "$REMAINING_IAM_ROLES" ]; then
        warning "Some resources may still exist:"
        [ ! -z "$REMAINING_STATE_MACHINES" ] && echo "   • State Machines: $REMAINING_STATE_MACHINES"
        [ ! -z "$REMAINING_LAMBDA_FUNCTIONS" ] && echo "   • Lambda Functions: $REMAINING_LAMBDA_FUNCTIONS"
        [ ! -z "$REMAINING_EVENTBRIDGE_RULES" ] && echo "   • EventBridge Rules: $REMAINING_EVENTBRIDGE_RULES"
        [ ! -z "$REMAINING_IAM_ROLES" ] && echo "   • IAM Roles: $REMAINING_IAM_ROLES"
        echo ""
        warning "You may need to manually delete these resources or run the script again"
    else
        success "All microservices-stepfn resources have been successfully deleted"
    fi
}

# Display cleanup summary
display_summary() {
    echo ""
    echo "=============================================="
    success "🧹 Cleanup completed!"
    echo "=============================================="
    echo ""
    echo "📋 Cleanup Summary:"
    echo "   • Step Functions State Machines: Deleted"
    echo "   • EventBridge Rules: Deleted"
    echo "   • Lambda Functions: Deleted"
    echo "   • IAM Roles: Deleted"
    echo "   • Local Files: Cleaned up"
    echo ""
    success "💰 All AWS resources have been removed to prevent ongoing charges"
    echo ""
    info "If you deployed multiple times, you may need to run this script again"
    info "to clean up additional resources with different suffixes."
    echo ""
}

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Safely destroy all microservices Step Functions resources."
    echo ""
    echo "Options:"
    echo "  --force     Skip confirmation prompts (use with caution)"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive mode with confirmations"
    echo "  $0 --force           # Force mode (no confirmations)"
    echo ""
}

# Main execution
main() {
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --force)
            log "🧹 Starting FORCED microservices Step Functions cleanup..."
            ;;
        "")
            log "🧹 Starting microservices Step Functions cleanup..."
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
    
    check_prerequisites
    setup_environment
    
    if ! discover_resources; then
        info "Nothing to clean up. Exiting."
        exit 0
    fi
    
    confirm_destruction "$1"
    
    # Delete resources in reverse dependency order
    delete_step_functions
    delete_eventbridge
    delete_lambda_functions
    delete_iam_roles
    cleanup_local_files
    
    # Wait a moment for eventual consistency
    log "Waiting for eventual consistency..."
    sleep 5
    
    verify_cleanup
    display_summary
}

# Handle script interruption
trap 'error "❌ Cleanup interrupted! Some resources may still exist. Run the script again to continue cleanup."' INT TERM

# Run main function
main "$@"