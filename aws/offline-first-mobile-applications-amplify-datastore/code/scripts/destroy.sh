#!/bin/bash

# AWS Amplify DataStore Offline-First Mobile Application Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="/tmp/amplify-datastore-destroy-$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_STATE_FILE="/tmp/amplify-datastore-state.json"

# Function to log messages
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log_error "$1"
    log_error "Check the log file for details: $LOG_FILE"
    exit 1
}

# Function to confirm destruction
confirm_destruction() {
    log_warn "This script will DELETE all AWS resources created by the deployment script."
    log_warn "This action CANNOT be undone!"
    echo ""
    
    # Check if running in automated mode
    if [[ "$1" == "--force" || "$1" == "-f" ]]; then
        log_warn "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding..."
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_info "Found deployment state file: $DEPLOYMENT_STATE_FILE"
        
        # Load variables from state file
        export APP_NAME=$(jq -r '.app_name' "$DEPLOYMENT_STATE_FILE")
        export PROJECT_DIR=$(jq -r '.project_dir' "$DEPLOYMENT_STATE_FILE")
        export AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_STATE_FILE")
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$DEPLOYMENT_STATE_FILE")
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$DEPLOYMENT_STATE_FILE")
        
        log_info "Loaded state - App: $APP_NAME, Project Dir: $PROJECT_DIR, Region: $AWS_REGION"
    else
        log_warn "Deployment state file not found. Will attempt to discover resources."
        
        # Try to discover from current directory or environment
        if [[ -d "$HOME/amplify-offline-app" ]]; then
            export PROJECT_DIR="$HOME/amplify-offline-app"
            log_info "Found project directory: $PROJECT_DIR"
        fi
        
        # Set default region if not set
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_REGION=${AWS_REGION:-"us-east-1"}
        
        # Get AWS Account ID
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
    fi
    
    log "✅ Deployment state loaded"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured. Please configure them first."
    fi
    
    # Check if jq is available (for state file parsing)
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed. State file parsing may be limited."
    fi
    
    # Check if Amplify CLI is installed
    if ! command -v amplify &> /dev/null; then
        log_warn "Amplify CLI is not installed. Manual resource cleanup may be required."
    fi
    
    log "✅ Prerequisites check completed"
}

# Function to delete Amplify backend resources
delete_amplify_backend() {
    log "Deleting Amplify backend resources..."
    
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        cd "$PROJECT_DIR"
        
        # Check if this is an Amplify project
        if [[ -f "amplify/.config/project-config.json" ]]; then
            log_info "Found Amplify project. Deleting backend resources..."
            
            # Delete the Amplify backend
            if command -v amplify &> /dev/null; then
                amplify delete --force >> "$LOG_FILE" 2>&1 || {
                    log_warn "Failed to delete Amplify backend using CLI. Will attempt manual cleanup."
                }
            else
                log_warn "Amplify CLI not available. Skipping Amplify delete command."
            fi
        else
            log_warn "No Amplify project found in: $PROJECT_DIR"
        fi
    else
        log_warn "Project directory not found: $PROJECT_DIR"
    fi
    
    log "✅ Amplify backend deletion completed"
}

# Function to manually clean up AWS resources
cleanup_aws_resources() {
    log "Performing manual AWS resource cleanup..."
    
    # Clean up AppSync APIs
    log_info "Cleaning up AppSync APIs..."
    if [[ -n "$APP_NAME" ]]; then
        APPSYNC_APIS=$(aws appsync list-graphql-apis --region "$AWS_REGION" --query 'graphqlApis[?contains(name, `'"$APP_NAME"'`)].apiId' --output text 2>/dev/null || echo "")
        if [[ -n "$APPSYNC_APIS" && "$APPSYNC_APIS" != "None" ]]; then
            for api_id in $APPSYNC_APIS; do
                log_info "Deleting AppSync API: $api_id"
                aws appsync delete-graphql-api --api-id "$api_id" --region "$AWS_REGION" >> "$LOG_FILE" 2>&1 || {
                    log_warn "Failed to delete AppSync API: $api_id"
                }
            done
        else
            log_info "No AppSync APIs found to delete"
        fi
    fi
    
    # Clean up DynamoDB tables
    log_info "Cleaning up DynamoDB tables..."
    DYNAMODB_TABLES=$(aws dynamodb list-tables --region "$AWS_REGION" --query 'TableNames[?contains(@, `Task`) || contains(@, `Project`)]' --output text 2>/dev/null || echo "")
    if [[ -n "$DYNAMODB_TABLES" && "$DYNAMODB_TABLES" != "None" ]]; then
        for table_name in $DYNAMODB_TABLES; do
            log_info "Deleting DynamoDB table: $table_name"
            aws dynamodb delete-table --table-name "$table_name" --region "$AWS_REGION" >> "$LOG_FILE" 2>&1 || {
                log_warn "Failed to delete DynamoDB table: $table_name"
            }
        done
    else
        log_info "No DynamoDB tables found to delete"
    fi
    
    # Clean up Cognito User Pools
    log_info "Cleaning up Cognito User Pools..."
    if [[ -n "$APP_NAME" ]]; then
        COGNITO_POOLS=$(aws cognito-idp list-user-pools --region "$AWS_REGION" --max-results 10 --query 'UserPools[?contains(Name, `'"$APP_NAME"'`)].Id' --output text 2>/dev/null || echo "")
        if [[ -n "$COGNITO_POOLS" && "$COGNITO_POOLS" != "None" ]]; then
            for pool_id in $COGNITO_POOLS; do
                log_info "Deleting Cognito User Pool: $pool_id"
                aws cognito-idp delete-user-pool --user-pool-id "$pool_id" --region "$AWS_REGION" >> "$LOG_FILE" 2>&1 || {
                    log_warn "Failed to delete Cognito User Pool: $pool_id"
                }
            done
        else
            log_info "No Cognito User Pools found to delete"
        fi
    fi
    
    # Clean up Cognito Identity Pools
    log_info "Cleaning up Cognito Identity Pools..."
    if [[ -n "$APP_NAME" ]]; then
        IDENTITY_POOLS=$(aws cognito-identity list-identity-pools --region "$AWS_REGION" --max-results 10 --query 'IdentityPools[?contains(IdentityPoolName, `'"$APP_NAME"'`)].IdentityPoolId' --output text 2>/dev/null || echo "")
        if [[ -n "$IDENTITY_POOLS" && "$IDENTITY_POOLS" != "None" ]]; then
            for pool_id in $IDENTITY_POOLS; do
                log_info "Deleting Cognito Identity Pool: $pool_id"
                aws cognito-identity delete-identity-pool --identity-pool-id "$pool_id" --region "$AWS_REGION" >> "$LOG_FILE" 2>&1 || {
                    log_warn "Failed to delete Cognito Identity Pool: $pool_id"
                }
            done
        else
            log_info "No Cognito Identity Pools found to delete"
        fi
    fi
    
    # Clean up IAM roles (be careful with this)
    log_info "Cleaning up IAM roles..."
    if [[ -n "$APP_NAME" ]]; then
        IAM_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `'"$APP_NAME"'`)].RoleName' --output text 2>/dev/null || echo "")
        if [[ -n "$IAM_ROLES" && "$IAM_ROLES" != "None" ]]; then
            for role_name in $IAM_ROLES; do
                log_info "Deleting IAM role: $role_name"
                
                # First, detach managed policies
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
                if [[ -n "$ATTACHED_POLICIES" && "$ATTACHED_POLICIES" != "None" ]]; then
                    for policy_arn in $ATTACHED_POLICIES; do
                        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" >> "$LOG_FILE" 2>&1 || {
                            log_warn "Failed to detach policy from role: $role_name"
                        }
                    done
                fi
                
                # Delete inline policies
                INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
                if [[ -n "$INLINE_POLICIES" && "$INLINE_POLICIES" != "None" ]]; then
                    for policy_name in $INLINE_POLICIES; do
                        aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" >> "$LOG_FILE" 2>&1 || {
                            log_warn "Failed to delete inline policy from role: $role_name"
                        }
                    done
                fi
                
                # Finally, delete the role
                aws iam delete-role --role-name "$role_name" >> "$LOG_FILE" 2>&1 || {
                    log_warn "Failed to delete IAM role: $role_name"
                }
            done
        else
            log_info "No IAM roles found to delete"
        fi
    fi
    
    log "✅ AWS resource cleanup completed"
}

# Function to clean up local project
cleanup_local_project() {
    log "Cleaning up local project..."
    
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        log_info "Removing project directory: $PROJECT_DIR"
        
        # Confirm before deleting
        if [[ "$1" != "--force" && "$1" != "-f" ]]; then
            read -p "Delete local project directory $PROJECT_DIR? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Keeping local project directory: $PROJECT_DIR"
                return 0
            fi
        fi
        
        rm -rf "$PROJECT_DIR" || {
            log_warn "Failed to remove project directory: $PROJECT_DIR"
        }
        
        log_info "Project directory removed successfully"
    else
        log_info "No project directory to remove"
    fi
    
    log "✅ Local project cleanup completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove deployment state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log_info "Removed deployment state file"
    fi
    
    # Clean up old log files (keep last 5)
    find /tmp -name "amplify-datastore-*.log" -type f -print0 | \
        sort -zr | \
        tail -zn +6 | \
        xargs -0 rm -f 2>/dev/null || true
    
    log "✅ Temporary files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check for remaining AppSync APIs
    if [[ -n "$APP_NAME" ]]; then
        REMAINING_APIS=$(aws appsync list-graphql-apis --region "$AWS_REGION" --query 'graphqlApis[?contains(name, `'"$APP_NAME"'`)].name' --output text 2>/dev/null || echo "")
        if [[ -n "$REMAINING_APIS" && "$REMAINING_APIS" != "None" ]]; then
            log_warn "Remaining AppSync APIs found: $REMAINING_APIS"
        else
            log_info "No remaining AppSync APIs found"
        fi
    fi
    
    # Check for remaining DynamoDB tables
    REMAINING_TABLES=$(aws dynamodb list-tables --region "$AWS_REGION" --query 'TableNames[?contains(@, `Task`) || contains(@, `Project`)]' --output text 2>/dev/null || echo "")
    if [[ -n "$REMAINING_TABLES" && "$REMAINING_TABLES" != "None" ]]; then
        log_warn "Remaining DynamoDB tables found: $REMAINING_TABLES"
    else
        log_info "No remaining DynamoDB tables found"
    fi
    
    # Check for remaining Cognito User Pools
    if [[ -n "$APP_NAME" ]]; then
        REMAINING_POOLS=$(aws cognito-idp list-user-pools --region "$AWS_REGION" --max-results 10 --query 'UserPools[?contains(Name, `'"$APP_NAME"'`)].Name' --output text 2>/dev/null || echo "")
        if [[ -n "$REMAINING_POOLS" && "$REMAINING_POOLS" != "None" ]]; then
            log_warn "Remaining Cognito User Pools found: $REMAINING_POOLS"
        else
            log_info "No remaining Cognito User Pools found"
        fi
    fi
    
    # Check if project directory still exists
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR" ]]; then
        log_info "Project directory still exists: $PROJECT_DIR"
    else
        log_info "Project directory successfully removed"
    fi
    
    log "✅ Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    log "==============="
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "App Name: ${APP_NAME:-'Not specified'}"
    log_info "Project Directory: ${PROJECT_DIR:-'Not specified'}"
    log_info "Log File: $LOG_FILE"
    log ""
    log "Resources cleaned up:"
    log "- Amplify backend resources"
    log "- AppSync GraphQL APIs"
    log "- DynamoDB tables"
    log "- Cognito User Pools and Identity Pools"
    log "- IAM roles and policies"
    log "- Local project directory (if confirmed)"
    log "- Temporary files"
    log ""
    log "✅ Cleanup completed successfully!"
}

# Function to wait for resource deletion
wait_for_deletion() {
    log "Waiting for resource deletion to complete..."
    
    # Wait for DynamoDB tables to be deleted
    if [[ -n "$DYNAMODB_TABLES" && "$DYNAMODB_TABLES" != "None" ]]; then
        for table_name in $DYNAMODB_TABLES; do
            log_info "Waiting for DynamoDB table deletion: $table_name"
            aws dynamodb wait table-not-exists --table-name "$table_name" --region "$AWS_REGION" >> "$LOG_FILE" 2>&1 || {
                log_warn "Timeout waiting for table deletion: $table_name"
            }
        done
    fi
    
    # Give other resources time to clean up
    sleep 10
    
    log "✅ Resource deletion wait completed"
}

# Main execution function
main() {
    log "Starting AWS Amplify DataStore Offline-First Mobile Application cleanup..."
    log "Log file: $LOG_FILE"
    
    # Parse command line arguments
    FORCE_FLAG=""
    for arg in "$@"; do
        case $arg in
            --force|-f)
                FORCE_FLAG="--force"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--force|-f] [--help|-h]"
                echo "  --force, -f    Skip confirmation prompts"
                echo "  --help, -h     Show this help message"
                exit 0
                ;;
        esac
    done
    
    # Execute cleanup steps
    confirm_destruction "$FORCE_FLAG"
    check_prerequisites
    load_deployment_state
    delete_amplify_backend
    cleanup_aws_resources
    wait_for_deletion
    cleanup_local_project "$FORCE_FLAG"
    cleanup_temp_files
    verify_cleanup
    display_summary
    
    log "Cleanup completed successfully!"
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi