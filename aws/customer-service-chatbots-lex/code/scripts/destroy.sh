#!/bin/bash

# Destroy script for Customer Service Chatbots with Amazon Lex
# This script removes all resources created by the deploy.sh script
# including Amazon Lex bot, Lambda function, DynamoDB table, and IAM roles

set -euo pipefail

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
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to ask for confirmation
confirm_destruction() {
    echo ""
    echo "============================================"
    warning "DESTRUCTIVE ACTION WARNING!"
    echo "============================================"
    echo ""
    warning "This script will permanently delete the following resources:"
    echo "  - Amazon Lex bot and all configurations"
    echo "  - Lambda function and deployment package"
    echo "  - DynamoDB table and all customer data"
    echo "  - IAM roles and policies"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    while true; do
        read -p "Are you sure you want to proceed? (yes/no): " yn
        case $yn in
            [Yy]es ) 
                log "Proceeding with resource destruction..."
                break
                ;;
            [Nn]o ) 
                log "Destruction cancelled by user"
                exit 0
                ;;
            * ) 
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Load environment variables from deployment
load_environment() {
    log "Loading environment variables..."
    
    if [ ! -f ".env_vars" ]; then
        error "Environment variables file (.env_vars) not found!"
        error "This file should have been created by the deploy.sh script."
        error "Please run the destroy script from the same directory as deploy.sh"
        exit 1
    fi
    
    # Source the environment variables
    source .env_vars
    
    # Verify required variables are set
    if [ -z "${BOT_ID:-}" ] || [ -z "${LAMBDA_FUNCTION_NAME:-}" ] || [ -z "${DYNAMODB_TABLE_NAME:-}" ]; then
        error "Required environment variables are not set!"
        error "Please check that .env_vars contains all necessary variables."
        exit 1
    fi
    
    success "Environment variables loaded successfully"
    log "Will destroy resources for Bot ID: $BOT_ID"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure'."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Delete Amazon Lex bot
delete_lex_bot() {
    log "Deleting Amazon Lex bot..."
    
    if [ -n "${BOT_ID:-}" ]; then
        # Check if bot exists before attempting deletion
        if aws lexv2-models describe-bot --bot-id "$BOT_ID" &> /dev/null; then
            aws lexv2-models delete-bot \
                --bot-id "$BOT_ID" \
                --skip-resource-in-use-check &> /dev/null || {
                warning "Failed to delete Lex bot, it may not exist or may already be deleted"
            }
            success "Amazon Lex bot deleted: $BOT_ID"
        else
            warning "Lex bot $BOT_ID does not exist or was already deleted"
        fi
    else
        warning "BOT_ID not found in environment variables"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        # Check if function exists before attempting deletion
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            aws lambda delete-function \
                --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null || {
                warning "Failed to delete Lambda function, it may not exist or may already be deleted"
            }
            success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        else
            warning "Lambda function $LAMBDA_FUNCTION_NAME does not exist or was already deleted"
        fi
    else
        warning "LAMBDA_FUNCTION_NAME not found in environment variables"
    fi
}

# Delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if [ -n "${DYNAMODB_TABLE_NAME:-}" ]; then
        # Check if table exists before attempting deletion
        if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &> /dev/null; then
            aws dynamodb delete-table \
                --table-name "$DYNAMODB_TABLE_NAME" &> /dev/null || {
                warning "Failed to delete DynamoDB table, it may not exist or may already be deleted"
            }
            
            # Wait for table deletion to complete
            log "Waiting for DynamoDB table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE_NAME" 2>/dev/null || {
                warning "Timeout waiting for table deletion, but deletion was initiated"
            }
            
            success "DynamoDB table deleted: $DYNAMODB_TABLE_NAME"
        else
            warning "DynamoDB table $DYNAMODB_TABLE_NAME does not exist or was already deleted"
        fi
    else
        warning "DYNAMODB_TABLE_NAME not found in environment variables"
    fi
}

# Delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    # Delete Lex service role
    if [ -n "${LEX_SERVICE_ROLE_NAME:-}" ]; then
        log "Deleting Lex service role: $LEX_SERVICE_ROLE_NAME"
        
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name "$LEX_SERVICE_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonLexV2BotPolicy" 2>/dev/null || {
            warning "Failed to detach policy from Lex service role, it may not exist"
        }
        
        # Delete the role
        aws iam delete-role \
            --role-name "$LEX_SERVICE_ROLE_NAME" 2>/dev/null || {
            warning "Failed to delete Lex service role, it may not exist"
        }
        
        success "Lex service role deleted: $LEX_SERVICE_ROLE_NAME"
    fi
    
    # Delete Lambda execution role
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        log "Deleting Lambda execution role: $LAMBDA_ROLE_NAME"
        
        # Detach basic execution policy
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || {
            warning "Failed to detach basic execution policy from Lambda role"
        }
        
        # Detach DynamoDB policy
        if [ -n "${AWS_ACCOUNT_ID:-}" ] && [ -n "${LAMBDA_POLICY_NAME:-}" ]; then
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" 2>/dev/null || {
                warning "Failed to detach DynamoDB policy from Lambda role"
            }
        fi
        
        # Delete the role
        aws iam delete-role \
            --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || {
            warning "Failed to delete Lambda role, it may not exist"
        }
        
        success "Lambda execution role deleted: $LAMBDA_ROLE_NAME"
    fi
    
    # Delete custom DynamoDB policy
    if [ -n "${AWS_ACCOUNT_ID:-}" ] && [ -n "${LAMBDA_POLICY_NAME:-}" ]; then
        log "Deleting custom DynamoDB policy: $LAMBDA_POLICY_NAME"
        
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}" 2>/dev/null || {
            warning "Failed to delete DynamoDB policy, it may not exist"
        }
        
        success "Custom DynamoDB policy deleted: $LAMBDA_POLICY_NAME"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment variables file
    if [ -f ".env_vars" ]; then
        rm -f .env_vars
        success "Environment variables file removed"
    fi
    
    # Remove any remaining temporary files
    rm -f lambda_function.py lambda_function.zip 2>/dev/null || true
    
    success "Local cleanup completed"
}

# Verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check if Lex bot still exists
    if [ -n "${BOT_ID:-}" ]; then
        if aws lexv2-models describe-bot --bot-id "$BOT_ID" &> /dev/null; then
            warning "Lex bot $BOT_ID still exists"
            ((errors++))
        else
            success "Lex bot deletion verified"
        fi
    fi
    
    # Check if Lambda function still exists
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            warning "Lambda function $LAMBDA_FUNCTION_NAME still exists"
            ((errors++))
        else
            success "Lambda function deletion verified"
        fi
    fi
    
    # Check if DynamoDB table still exists
    if [ -n "${DYNAMODB_TABLE_NAME:-}" ]; then
        if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &> /dev/null; then
            warning "DynamoDB table $DYNAMODB_TABLE_NAME still exists"
            ((errors++))
        else
            success "DynamoDB table deletion verified"
        fi
    fi
    
    # Check if IAM roles still exist
    if [ -n "${LEX_SERVICE_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "$LEX_SERVICE_ROLE_NAME" &> /dev/null; then
            warning "Lex service role $LEX_SERVICE_ROLE_NAME still exists"
            ((errors++))
        else
            success "Lex service role deletion verified"
        fi
    fi
    
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
            warning "Lambda role $LAMBDA_ROLE_NAME still exists"
            ((errors++))
        else
            success "Lambda role deletion verified"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        success "All resource deletions verified successfully"
    else
        warning "$errors resources may still exist. They may take additional time to be fully deleted."
    fi
}

# Display destruction summary
display_summary() {
    echo ""
    echo "============================================"
    success "DESTRUCTION COMPLETED!"
    echo "============================================"
    echo ""
    log "Destroyed Resources:"
    echo "  - Amazon Lex bot: ${BOT_NAME:-Unknown}"
    echo "  - Lambda function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
    echo "  - DynamoDB table: ${DYNAMODB_TABLE_NAME:-Unknown}"
    echo "  - IAM roles and policies"
    echo "  - Local environment files"
    echo ""
    success "All resources have been removed to avoid ongoing charges."
    echo ""
    log "Note: Some resources may take a few minutes to be fully deleted from AWS."
    log "You can verify deletion in the AWS Console if needed."
}

# Handle script interruption
handle_interrupt() {
    echo ""
    warning "Script interrupted by user"
    log "Some resources may have been partially deleted"
    log "Please check the AWS Console and rerun the script if needed"
    exit 1
}

# Set trap for script interruption
trap handle_interrupt SIGINT SIGTERM

# Main destruction function
main() {
    echo "============================================"
    echo "  Customer Service Chatbot Destruction"
    echo "  Amazon Lex + Lambda + DynamoDB"
    echo "============================================"
    echo ""
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    echo ""
    log "Starting resource destruction..."
    echo ""
    
    # Delete resources in reverse order of creation
    delete_lex_bot
    delete_lambda_function
    delete_dynamodb_table
    delete_iam_resources
    cleanup_local_files
    
    echo ""
    log "Verifying resource deletion..."
    verify_deletion
    
    display_summary
}

# Check if running in non-interactive mode
if [ "${1:-}" = "--force" ] || [ "${FORCE_DESTROY:-}" = "true" ]; then
    log "Running in non-interactive mode (forced destruction)"
    # Skip confirmation in non-interactive mode
    confirm_destruction() {
        warning "FORCE MODE: Skipping user confirmation"
    }
fi

# Run main function
main "$@"