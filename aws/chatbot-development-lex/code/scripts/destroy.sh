#!/bin/bash

#===============================================================================
# AWS Amazon Lex Chatbot Cleanup Script
# 
# This script removes all resources created by the deploy.sh script including:
# - Amazon Lex bot and aliases
# - Lambda function
# - DynamoDB table
# - S3 bucket
# - IAM roles and policies
#
# WARNING: This script will permanently delete all resources and data.
#          Make sure to backup any important data before running.
#===============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
readonly DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.json"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS Amazon Lex chatbot infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: from deployment info)
    -p, --prefix PREFIX     Resource name prefix (default: from deployment info)
    -f, --force             Skip confirmation prompts
    -d, --dry-run           Show what would be deleted without executing
    -v, --verbose           Enable verbose logging
    --keep-data             Keep DynamoDB table and S3 bucket data

EXAMPLES:
    $0                      # Interactive cleanup using deployment info
    $0 -f                   # Force cleanup without prompts
    $0 -p my-bot            # Cleanup resources with specific prefix
    $0 -d                   # Dry run mode

SAFETY FEATURES:
    - Confirmation prompts for destructive operations
    - Dry run mode to preview deletions
    - Automatic backup of deployment info
    - Graceful handling of missing resources

EOF
}

# Parse command line arguments
parse_args() {
    REGION=""
    PREFIX=""
    FORCE=false
    DRY_RUN=false
    VERBOSE=false
    KEEP_DATA=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."

    if [[ -f "$DEPLOYMENT_INFO" ]]; then
        # Read deployment info from JSON file
        if command -v jq &> /dev/null; then
            AWS_REGION=$(jq -r '.aws_region // empty' "$DEPLOYMENT_INFO")
            AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // empty' "$DEPLOYMENT_INFO")
            RESOURCE_PREFIX=$(jq -r '.resource_prefix // empty' "$DEPLOYMENT_INFO")
            BOT_NAME=$(jq -r '.bot_name // empty' "$DEPLOYMENT_INFO")
            BOT_ID=$(jq -r '.bot_id // empty' "$DEPLOYMENT_INFO")
            BOT_ALIAS_ID=$(jq -r '.bot_alias_id // empty' "$DEPLOYMENT_INFO")
            LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name // empty' "$DEPLOYMENT_INFO")
            ORDERS_TABLE_NAME=$(jq -r '.orders_table_name // empty' "$DEPLOYMENT_INFO")
            PRODUCTS_BUCKET_NAME=$(jq -r '.products_bucket_name // empty' "$DEPLOYMENT_INFO")
            LEX_ROLE_NAME=$(jq -r '.lex_role_name // empty' "$DEPLOYMENT_INFO")
            LAMBDA_ROLE_NAME=$(jq -r '.lambda_role_name // empty' "$DEPLOYMENT_INFO")
        else
            # Fallback: parse JSON without jq
            AWS_REGION=$(grep '"aws_region"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            AWS_ACCOUNT_ID=$(grep '"aws_account_id"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            RESOURCE_PREFIX=$(grep '"resource_prefix"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            BOT_NAME=$(grep '"bot_name"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            BOT_ID=$(grep '"bot_id"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            LAMBDA_FUNCTION_NAME=$(grep '"lambda_function_name"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            ORDERS_TABLE_NAME=$(grep '"orders_table_name"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            PRODUCTS_BUCKET_NAME=$(grep '"products_bucket_name"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            LEX_ROLE_NAME=$(grep '"lex_role_name"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
            LAMBDA_ROLE_NAME=$(grep '"lambda_role_name"' "$DEPLOYMENT_INFO" | cut -d'"' -f4)
        fi

        log "Loaded deployment information from: $DEPLOYMENT_INFO"
    else
        warn "Deployment info file not found: $DEPLOYMENT_INFO"
        warn "Will attempt to discover resources based on provided parameters"
    fi

    # Override with command line arguments if provided
    if [[ -n "$REGION" ]]; then
        AWS_REGION="$REGION"
    fi
    if [[ -n "$PREFIX" ]]; then
        RESOURCE_PREFIX="$PREFIX"
    fi

    # Set defaults if still empty
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    fi
    if [[ -z "$RESOURCE_PREFIX" ]]; then
        RESOURCE_PREFIX="chatbot-demo"
    fi

    log "Using AWS Region: $AWS_REGION"
    log "Using Resource Prefix: $RESOURCE_PREFIX"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi

    # Get AWS account ID if not already set
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi

    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    log "Prerequisites check completed"
}

# Discover resources if not provided
discover_resources() {
    log "Discovering resources to cleanup..."

    # If we don't have specific resource names, try to discover them
    if [[ -z "$BOT_NAME" || -z "$LAMBDA_FUNCTION_NAME" ]]; then
        log "Searching for resources with prefix: $RESOURCE_PREFIX"

        # Find Lex bots
        if [[ -z "$BOT_NAME" ]]; then
            local bots
            bots=$(aws lexv2-models list-bots --query "botSummaries[?starts_with(botName, '$RESOURCE_PREFIX')].botName" --output text 2>/dev/null || echo "")
            if [[ -n "$bots" ]]; then
                BOT_NAME=$(echo "$bots" | head -n1)
                log "Found Lex bot: $BOT_NAME"
            fi
        fi

        # Find Lambda functions
        if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
            local functions
            functions=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '$RESOURCE_PREFIX')].FunctionName" --output text 2>/dev/null || echo "")
            if [[ -n "$functions" ]]; then
                LAMBDA_FUNCTION_NAME=$(echo "$functions" | head -n1)
                log "Found Lambda function: $LAMBDA_FUNCTION_NAME"
            fi
        fi

        # Find DynamoDB tables
        if [[ -z "$ORDERS_TABLE_NAME" ]]; then
            local tables
            tables=$(aws dynamodb list-tables --query "TableNames[?starts_with(@, '$RESOURCE_PREFIX')]" --output text 2>/dev/null || echo "")
            if [[ -n "$tables" ]]; then
                ORDERS_TABLE_NAME=$(echo "$tables" | head -n1)
                log "Found DynamoDB table: $ORDERS_TABLE_NAME"
            fi
        fi

        # Find S3 buckets
        if [[ -z "$PRODUCTS_BUCKET_NAME" ]]; then
            local buckets
            buckets=$(aws s3 ls | grep "$RESOURCE_PREFIX" | awk '{print $3}' | head -n1 2>/dev/null || echo "")
            if [[ -n "$buckets" ]]; then
                PRODUCTS_BUCKET_NAME="$buckets"
                log "Found S3 bucket: $PRODUCTS_BUCKET_NAME"
            fi
        fi

        # Find IAM roles
        if [[ -z "$LEX_ROLE_NAME" ]]; then
            local roles
            roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '$RESOURCE_PREFIX') && contains(RoleName, 'lex')].RoleName" --output text 2>/dev/null || echo "")
            if [[ -n "$roles" ]]; then
                LEX_ROLE_NAME=$(echo "$roles" | head -n1)
                log "Found Lex IAM role: $LEX_ROLE_NAME"
            fi
        fi

        if [[ -z "$LAMBDA_ROLE_NAME" ]]; then
            local roles
            roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '$RESOURCE_PREFIX') && contains(RoleName, 'lambda')].RoleName" --output text 2>/dev/null || echo "")
            if [[ -n "$roles" ]]; then
                LAMBDA_ROLE_NAME=$(echo "$roles" | head -n1)
                log "Found Lambda IAM role: $LAMBDA_ROLE_NAME"
            fi
        fi
    fi

    # Get additional resource information if available
    if [[ -n "$BOT_NAME" && -z "$BOT_ID" ]]; then
        BOT_ID=$(aws lexv2-models list-bots --query "botSummaries[?botName=='$BOT_NAME'].botId" --output text 2>/dev/null || echo "")
    fi

    if [[ -n "$BOT_ID" && -z "$BOT_ALIAS_ID" ]]; then
        BOT_ALIAS_ID=$(aws lexv2-models list-bot-aliases --bot-id "$BOT_ID" --query "botAliasSummaries[0].botAliasId" --output text 2>/dev/null || echo "")
    fi
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    local ignore_errors="${2:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            log "Executing: $cmd"
        fi
        
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warn "Command failed (ignored): $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure you want to continue? [y/N]: " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Delete Lex bot and aliases
delete_lex_bot() {
    if [[ -z "$BOT_NAME" && -z "$BOT_ID" ]]; then
        warn "No Lex bot information found, skipping"
        return 0
    fi

    log "Deleting Lex bot and associated resources..."

    # Delete bot alias first
    if [[ -n "$BOT_ID" && -n "$BOT_ALIAS_ID" ]]; then
        execute "aws lexv2-models delete-bot-alias \
            --bot-id '$BOT_ID' \
            --bot-alias-id '$BOT_ALIAS_ID'" true
        log "✅ Deleted bot alias: $BOT_ALIAS_ID"
    fi

    # Delete bot
    if [[ -n "$BOT_ID" ]]; then
        execute "aws lexv2-models delete-bot --bot-id '$BOT_ID'" true
        log "✅ Deleted Lex bot: $BOT_NAME ($BOT_ID)"
    elif [[ -n "$BOT_NAME" ]]; then
        # Try to find and delete by name
        local bot_id
        bot_id=$(aws lexv2-models list-bots --query "botSummaries[?botName=='$BOT_NAME'].botId" --output text 2>/dev/null || echo "")
        if [[ -n "$bot_id" ]]; then
            execute "aws lexv2-models delete-bot --bot-id '$bot_id'" true
            log "✅ Deleted Lex bot: $BOT_NAME ($bot_id)"
        else
            warn "Could not find Lex bot: $BOT_NAME"
        fi
    fi
}

# Delete Lambda function
delete_lambda_function() {
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
        warn "No Lambda function name found, skipping"
        return 0
    fi

    log "Deleting Lambda function..."

    # Remove Lambda permissions first
    execute "aws lambda remove-permission \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --statement-id lex-invoke" true

    # Delete Lambda function
    execute "aws lambda delete-function \
        --function-name '$LAMBDA_FUNCTION_NAME'" true

    log "✅ Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
}

# Delete DynamoDB table
delete_dynamodb_table() {
    if [[ -z "$ORDERS_TABLE_NAME" ]]; then
        warn "No DynamoDB table name found, skipping"
        return 0
    fi

    if [[ "$KEEP_DATA" == "true" ]]; then
        warn "Keeping DynamoDB table as requested: $ORDERS_TABLE_NAME"
        return 0
    fi

    log "Deleting DynamoDB table..."

    confirm_action "This will permanently delete the DynamoDB table '$ORDERS_TABLE_NAME' and all its data."

    execute "aws dynamodb delete-table --table-name '$ORDERS_TABLE_NAME'" true

    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "$ORDERS_TABLE_NAME" 2>/dev/null || true
    fi

    log "✅ Deleted DynamoDB table: $ORDERS_TABLE_NAME"
}

# Delete S3 bucket
delete_s3_bucket() {
    if [[ -z "$PRODUCTS_BUCKET_NAME" ]]; then
        warn "No S3 bucket name found, skipping"
        return 0
    fi

    if [[ "$KEEP_DATA" == "true" ]]; then
        warn "Keeping S3 bucket as requested: $PRODUCTS_BUCKET_NAME"
        return 0
    fi

    log "Deleting S3 bucket..."

    confirm_action "This will permanently delete the S3 bucket '$PRODUCTS_BUCKET_NAME' and all its contents."

    # Empty bucket first
    execute "aws s3 rm s3://'$PRODUCTS_BUCKET_NAME' --recursive" true

    # Delete bucket
    execute "aws s3 rb s3://'$PRODUCTS_BUCKET_NAME'" true

    log "✅ Deleted S3 bucket: $PRODUCTS_BUCKET_NAME"
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."

    # Delete Lambda IAM role
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        log "Deleting Lambda IAM role: $LAMBDA_ROLE_NAME"
        
        # Detach policies
        local lambda_policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
            "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
        )
        
        for policy in "${lambda_policies[@]}"; do
            execute "aws iam detach-role-policy \
                --role-name '$LAMBDA_ROLE_NAME' \
                --policy-arn '$policy'" true
        done
        
        execute "aws iam delete-role --role-name '$LAMBDA_ROLE_NAME'" true
        log "✅ Deleted Lambda IAM role: $LAMBDA_ROLE_NAME"
    fi

    # Delete Lex IAM role
    if [[ -n "$LEX_ROLE_NAME" ]]; then
        log "Deleting Lex IAM role: $LEX_ROLE_NAME"
        
        execute "aws iam detach-role-policy \
            --role-name '$LEX_ROLE_NAME' \
            --policy-arn arn:aws:iam::aws:policy/AmazonLexFullAccess" true
        
        execute "aws iam delete-role --role-name '$LEX_ROLE_NAME'" true
        log "✅ Deleted Lex IAM role: $LEX_ROLE_NAME"
    fi
}

# Clean up temporary files
cleanup_files() {
    log "Cleaning up temporary files..."

    local files_to_remove=(
        "/tmp/lex_fulfillment.py"
        "/tmp/lex_fulfillment.zip"
        "/tmp/product_intent.json"
        "/tmp/order_intent.json"
        "/tmp/support_intent.json"
    )

    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute "rm -f '$file'" true
        fi
    done

    # Remove Lambda code directories
    execute "rm -rf /tmp/lex-lambda-*" true

    log "✅ Temporary files cleaned up"
}

# Backup deployment info
backup_deployment_info() {
    if [[ -f "$DEPLOYMENT_INFO" && "$DRY_RUN" == "false" ]]; then
        local backup_file="${DEPLOYMENT_INFO}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$DEPLOYMENT_INFO" "$backup_file"
        log "Deployment info backed up to: $backup_file"
    fi
}

# Print cleanup summary
print_summary() {
    log "Cleanup completed!"
    
    echo ""
    echo "==============================================================================="
    echo "                          CLEANUP SUMMARY"
    echo "==============================================================================="
    echo "AWS Region:           $AWS_REGION"
    echo "AWS Account:          $AWS_ACCOUNT_ID"
    echo "Resource Prefix:      $RESOURCE_PREFIX"
    echo ""
    echo "RESOURCES DELETED:"
    if [[ -n "$BOT_NAME" ]]; then
        echo "  ✅ Lex Bot:            $BOT_NAME"
    fi
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        echo "  ✅ Lambda Function:    $LAMBDA_FUNCTION_NAME"
    fi
    if [[ -n "$ORDERS_TABLE_NAME" ]]; then
        if [[ "$KEEP_DATA" == "true" ]]; then
            echo "  ⚠️  DynamoDB Table:     $ORDERS_TABLE_NAME (KEPT)"
        else
            echo "  ✅ DynamoDB Table:     $ORDERS_TABLE_NAME"
        fi
    fi
    if [[ -n "$PRODUCTS_BUCKET_NAME" ]]; then
        if [[ "$KEEP_DATA" == "true" ]]; then
            echo "  ⚠️  S3 Bucket:          $PRODUCTS_BUCKET_NAME (KEPT)"
        else
            echo "  ✅ S3 Bucket:          $PRODUCTS_BUCKET_NAME"
        fi
    fi
    if [[ -n "$LEX_ROLE_NAME" ]]; then
        echo "  ✅ Lex IAM Role:       $LEX_ROLE_NAME"
    fi
    if [[ -n "$LAMBDA_ROLE_NAME" ]]; then
        echo "  ✅ Lambda IAM Role:    $LAMBDA_ROLE_NAME"
    fi
    echo "  ✅ Temporary Files:    Cleaned"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "NOTE: This was a dry run. No resources were actually deleted."
        echo "Run without -d/--dry-run flag to perform actual cleanup."
    else
        echo "All specified resources have been successfully removed."
        echo "You will no longer be charged for these resources."
    fi
    echo "==============================================================================="
}

# Main cleanup function
main() {
    # Initialize logging
    : > "$LOG_FILE"
    : > "$ERROR_LOG"

    log "Starting AWS Amazon Lex Chatbot cleanup..."
    log "Script started at: $(date)"

    # Parse arguments
    parse_args "$@"

    # Load deployment info and check prerequisites
    load_deployment_info
    check_prerequisites
    discover_resources

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be deleted"
    fi

    # Show what will be deleted
    echo ""
    echo "==============================================================================="
    echo "                     RESOURCES TO BE DELETED"
    echo "==============================================================================="
    [[ -n "$BOT_NAME" ]] && echo "Lex Bot:            $BOT_NAME"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "Lambda Function:    $LAMBDA_FUNCTION_NAME"
    [[ -n "$ORDERS_TABLE_NAME" ]] && echo "DynamoDB Table:     $ORDERS_TABLE_NAME"
    [[ -n "$PRODUCTS_BUCKET_NAME" ]] && echo "S3 Bucket:          $PRODUCTS_BUCKET_NAME"
    [[ -n "$LEX_ROLE_NAME" ]] && echo "Lex IAM Role:       $LEX_ROLE_NAME"
    [[ -n "$LAMBDA_ROLE_NAME" ]] && echo "Lambda IAM Role:    $LAMBDA_ROLE_NAME"
    echo "Temporary Files:    Various"
    echo "==============================================================================="

    # Final confirmation
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_action "WARNING: This operation will permanently delete all listed resources."
    fi

    # Backup deployment info
    backup_deployment_info

    # Perform cleanup
    delete_lex_bot
    delete_lambda_function
    delete_dynamodb_table
    delete_s3_bucket
    delete_iam_roles
    cleanup_files

    # Print summary
    print_summary

    log "Cleanup script completed successfully!"
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"; exit 1' ERR

# Run main function
main "$@"