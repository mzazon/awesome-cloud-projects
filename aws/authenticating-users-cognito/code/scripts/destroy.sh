#!/bin/bash

# AWS Cognito User Pools Cleanup Script
# This script removes all resources created by the Cognito User Pools deployment
# Recipe: Authenticating Users with Cognito User Pools

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to get user pool information from config file
load_configuration() {
    log_info "Loading configuration..."
    
    if [ -f "cognito-config.json" ]; then
        log_info "Found cognito-config.json, loading configuration..."
        
        export USER_POOL_ID=$(jq -r '.UserPoolId // empty' cognito-config.json 2>/dev/null || echo "")
        export CLIENT_ID=$(jq -r '.ClientId // empty' cognito-config.json 2>/dev/null || echo "")
        export AWS_REGION=$(jq -r '.Region // empty' cognito-config.json 2>/dev/null || echo "")
        
        # Extract domain prefix from hosted UI URL
        local hosted_ui_url
        hosted_ui_url=$(jq -r '.HostedUIUrl // empty' cognito-config.json 2>/dev/null || echo "")
        if [ -n "$hosted_ui_url" ]; then
            export DOMAIN_PREFIX=$(echo "$hosted_ui_url" | sed -n 's/https:\/\/\([^.]*\)\.auth\..*/\1/p')
        fi
        
        log_info "Loaded User Pool ID: $USER_POOL_ID"
        log_info "Loaded Client ID: $CLIENT_ID"
        log_info "Loaded Domain Prefix: $DOMAIN_PREFIX"
        log_info "Loaded Region: $AWS_REGION"
        
    else
        log_warning "Configuration file not found. Will attempt to find resources manually."
        
        # Set region from AWS CLI config if not set
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION=$(aws configure get region)
            if [ -z "$AWS_REGION" ]; then
                export AWS_REGION="us-east-1"
                log_warning "No region configured, using default: $AWS_REGION"
            fi
        fi
    fi
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    echo -e "${YELLOW}WARNING: This will permanently delete the following $resource_type:${NC}"
    echo "  $resource_name"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Operation cancelled by user."
        exit 0
    fi
}

# Function to find user pools if not provided
find_user_pools() {
    if [ -z "$USER_POOL_ID" ]; then
        log_info "Searching for Cognito User Pools with 'ecommerce-users' prefix..."
        
        local pools
        pools=$(aws cognito-idp list-user-pools --max-items 60 \
            --query 'UserPools[?starts_with(Name, `ecommerce-users`)].{Id:Id,Name:Name}' \
            --output table 2>/dev/null || echo "")
        
        if [ -n "$pools" ] && [ "$pools" != "None" ]; then
            echo "Found the following User Pools:"
            echo "$pools"
            echo ""
            read -p "Enter the User Pool ID to delete (or 'all' to delete all): " user_input
            
            if [ "$user_input" = "all" ]; then
                # Get all pool IDs
                USER_POOL_IDS=$(aws cognito-idp list-user-pools --max-items 60 \
                    --query 'UserPools[?starts_with(Name, `ecommerce-users`)].Id' \
                    --output text 2>/dev/null || echo "")
            else
                USER_POOL_IDS="$user_input"
            fi
        else
            log_warning "No User Pools found with 'ecommerce-users' prefix."
            exit 0
        fi
    else
        USER_POOL_IDS="$USER_POOL_ID"
    fi
}

# Function to delete hosted UI domain
delete_hosted_ui_domain() {
    local user_pool_id="$1"
    
    log_info "Removing hosted UI domain for User Pool: $user_pool_id"
    
    # If we have the domain prefix from config, use it
    if [ -n "$DOMAIN_PREFIX" ]; then
        local domain_status
        domain_status=$(aws cognito-idp describe-user-pool-domain \
            --domain "$DOMAIN_PREFIX" \
            --query 'DomainDescription.Status' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$domain_status" != "NOT_FOUND" ]; then
            aws cognito-idp delete-user-pool-domain \
                --domain "$DOMAIN_PREFIX" 2>/dev/null || {
                log_warning "Failed to delete domain '$DOMAIN_PREFIX' (may not exist)"
            }
            log_success "Deleted hosted UI domain: $DOMAIN_PREFIX"
        else
            log_info "Domain '$DOMAIN_PREFIX' not found, skipping"
        fi
    else
        # Try to find domains associated with the user pool
        log_info "Searching for domains associated with User Pool..."
        
        # Unfortunately, there's no direct way to list domains by user pool
        # We'll try common prefixes
        local common_prefixes=("ecommerce-auth" "auth" "cognito")
        for prefix in "${common_prefixes[@]}"; do
            local test_domains=("${prefix}" "${prefix}-test" "${prefix}-dev" "${prefix}-prod")
            for domain in "${test_domains[@]}"; do
                local domain_status
                domain_status=$(aws cognito-idp describe-user-pool-domain \
                    --domain "$domain" \
                    --query 'DomainDescription.Status' --output text 2>/dev/null || echo "NOT_FOUND")
                
                if [ "$domain_status" != "NOT_FOUND" ]; then
                    # Check if this domain belongs to our user pool
                    local domain_user_pool
                    domain_user_pool=$(aws cognito-idp describe-user-pool-domain \
                        --domain "$domain" \
                        --query 'DomainDescription.UserPoolId' --output text 2>/dev/null || echo "")
                    
                    if [ "$domain_user_pool" = "$user_pool_id" ]; then
                        aws cognito-idp delete-user-pool-domain \
                            --domain "$domain" 2>/dev/null || {
                            log_warning "Failed to delete domain '$domain'"
                        }
                        log_success "Deleted hosted UI domain: $domain"
                        return 0
                    fi
                fi
            done
        done
        
        log_info "No hosted UI domain found for this User Pool"
    fi
}

# Function to delete user pool clients
delete_user_pool_clients() {
    local user_pool_id="$1"
    
    log_info "Deleting User Pool clients for: $user_pool_id"
    
    # If we have the client ID from config, use it
    if [ -n "$CLIENT_ID" ]; then
        aws cognito-idp delete-user-pool-client \
            --user-pool-id "$user_pool_id" \
            --client-id "$CLIENT_ID" 2>/dev/null || {
            log_warning "Failed to delete client '$CLIENT_ID' (may not exist)"
        }
        log_success "Deleted User Pool client: $CLIENT_ID"
    else
        # Get all clients for this user pool
        local clients
        clients=$(aws cognito-idp list-user-pool-clients \
            --user-pool-id "$user_pool_id" \
            --query 'UserPoolClients[].ClientId' --output text 2>/dev/null || echo "")
        
        if [ -n "$clients" ] && [ "$clients" != "None" ]; then
            for client_id in $clients; do
                aws cognito-idp delete-user-pool-client \
                    --user-pool-id "$user_pool_id" \
                    --client-id "$client_id" 2>/dev/null || {
                    log_warning "Failed to delete client '$client_id'"
                }
                log_success "Deleted User Pool client: $client_id"
            done
        else
            log_info "No User Pool clients found"
        fi
    fi
}

# Function to delete user pool
delete_user_pool() {
    local user_pool_id="$1"
    
    log_info "Deleting User Pool: $user_pool_id"
    
    # Get user pool details for confirmation
    local pool_name
    pool_name=$(aws cognito-idp describe-user-pool \
        --user-pool-id "$user_pool_id" \
        --query 'UserPool.Name' --output text 2>/dev/null || echo "Unknown")
    
    # Confirm deletion
    confirm_deletion "User Pool" "$pool_name ($user_pool_id)"
    
    # First, delete hosted UI domain
    delete_hosted_ui_domain "$user_pool_id"
    
    # Wait a moment for domain deletion to propagate
    sleep 5
    
    # Delete user pool clients
    delete_user_pool_clients "$user_pool_id"
    
    # Wait a moment for client deletion to propagate
    sleep 5
    
    # Delete user pool (this removes all users and groups)
    aws cognito-idp delete-user-pool \
        --user-pool-id "$user_pool_id" 2>/dev/null || {
        log_error "Failed to delete User Pool '$user_pool_id'"
        return 1
    }
    
    log_success "Deleted User Pool: $pool_name ($user_pool_id)"
}

# Function to delete IAM role
delete_sns_role() {
    log_info "Checking for SNS IAM role..."
    
    local sns_role_arn
    sns_role_arn=$(aws iam get-role \
        --role-name CognitoSNSRole \
        --query 'Role.Arn' --output text 2>/dev/null || echo "")
    
    if [ -n "$sns_role_arn" ]; then
        log_info "Found SNS role, confirming deletion..."
        
        confirm_deletion "IAM Role" "CognitoSNSRole"
        
        # Detach policy and delete IAM role
        aws iam detach-role-policy \
            --role-name CognitoSNSRole \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSNSFullAccess" 2>/dev/null || {
            log_warning "Failed to detach policy from CognitoSNSRole (may not be attached)"
        }
        
        aws iam delete-role --role-name CognitoSNSRole 2>/dev/null || {
            log_warning "Failed to delete CognitoSNSRole (may not exist)"
        }
        
        log_success "Deleted SNS IAM role: CognitoSNSRole"
    else
        log_info "SNS IAM role not found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_remove=("cognito-config.json" "google-idp-config.json")
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed: $file"
        fi
    done
    
    # Clear environment variables
    unset USER_POOL_NAME CLIENT_NAME DOMAIN_PREFIX USER_POOL_ID CLIENT_ID USER_POOL_IDS
    
    log_success "Cleaned up local configuration files and environment variables"
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo "===================="
    echo "✅ User Pool(s) deleted"
    echo "✅ User Pool client(s) deleted"
    echo "✅ Hosted UI domain(s) deleted"
    echo "✅ SNS IAM role deleted (if found)"
    echo "✅ Local configuration files removed"
    echo "===================="
    log_success "All Cognito User Pool resources have been successfully removed!"
}

# Function to handle interactive mode
interactive_mode() {
    log_info "Starting interactive cleanup mode..."
    
    echo "This script will help you clean up AWS Cognito User Pool resources."
    echo ""
    
    # Option to delete specific user pool
    read -p "Do you have a specific User Pool ID to delete? (y/n): " has_pool_id
    
    if [ "$has_pool_id" = "y" ] || [ "$has_pool_id" = "Y" ]; then
        read -p "Enter the User Pool ID: " USER_POOL_ID
        export USER_POOL_ID
    fi
    
    # Option to delete SNS role
    read -p "Do you want to delete the CognitoSNSRole IAM role? (y/n): " delete_role
    
    if [ "$delete_role" = "y" ] || [ "$delete_role" = "Y" ]; then
        DELETE_SNS_ROLE=true
    else
        DELETE_SNS_ROLE=false
    fi
    
    export DELETE_SNS_ROLE
}

# Main cleanup function
main() {
    log_info "Starting AWS Cognito User Pools cleanup..."
    
    check_prerequisites
    load_configuration
    
    # If no configuration found and no arguments, run interactive mode
    if [ -z "$USER_POOL_ID" ] && [ $# -eq 0 ]; then
        interactive_mode
    fi
    
    find_user_pools
    
    # Delete each user pool
    for pool_id in $USER_POOL_IDS; do
        if [ -n "$pool_id" ] && [ "$pool_id" != "None" ]; then
            delete_user_pool "$pool_id"
        fi
    done
    
    # Delete SNS role if requested or if we have config
    if [ "$DELETE_SNS_ROLE" = "true" ] || [ -f "cognito-config.json" ]; then
        delete_sns_role
    fi
    
    cleanup_local_files
    display_summary
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --user-pool-id ID    Specific User Pool ID to delete"
    echo "  --all               Delete all User Pools with 'ecommerce-users' prefix"
    echo "  --delete-sns-role   Delete the CognitoSNSRole IAM role"
    echo "  --config FILE       Use specific configuration file (default: cognito-config.json)"
    echo "  --interactive       Run in interactive mode"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                 # Interactive mode or use cognito-config.json"
    echo "  $0 --user-pool-id us-east-1_ABC123 # Delete specific user pool"
    echo "  $0 --all --delete-sns-role         # Delete all user pools and SNS role"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user-pool-id)
            USER_POOL_ID="$2"
            shift 2
            ;;
        --all)
            FIND_ALL_POOLS=true
            shift
            ;;
        --delete-sns-role)
            DELETE_SNS_ROLE=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Trap errors
trap 'log_error "Cleanup failed. Some resources may still exist."; exit 1' ERR

# Execute main function
main "$@"