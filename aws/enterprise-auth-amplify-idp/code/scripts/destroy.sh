#!/bin/bash

# destroy.sh - Clean up Enterprise Authentication with Amplify and External Identity Providers
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to confirm destructive action
confirm_destruction() {
    echo ""
    warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo "This script will permanently delete all resources created for enterprise authentication:"
    echo "- Amplify project and backend resources"
    echo "- Cognito User Pool and associated configurations"
    echo "- Cognito domain"
    echo "- Sample React application"
    echo "- All configuration files"
    echo ""
    
    # Check if running in CI/CD or force mode
    if [ "$FORCE_DESTROY" = "true" ] || [ "$CI" = "true" ]; then
        warning "Force mode or CI detected. Proceeding with destruction..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from .env file
    if [ -f ".env" ]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Attempting to discover resources..."
        
        # Try to discover resources if .env is missing
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
            error "Unable to determine AWS region or account. Please ensure AWS CLI is configured."
            exit 1
        fi
        
        # Try to find Amplify projects
        log "Searching for Amplify projects with 'enterprise-auth' prefix..."
        
        # List directories that match our pattern
        POSSIBLE_PROJECTS=$(ls -d enterprise-auth-* 2>/dev/null || true)
        if [ -n "$POSSIBLE_PROJECTS" ]; then
            warning "Found potential project directories: $POSSIBLE_PROJECTS"
            warning "Please specify APP_NAME manually or restore the .env file"
        fi
    fi
    
    # Verify required variables
    if [ -z "$APP_NAME" ]; then
        error "APP_NAME not set. Cannot proceed with cleanup."
        error "Please provide APP_NAME environment variable or restore .env file."
        exit 1
    fi
    
    log "Using configuration:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  App Name: ${APP_NAME}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS CLI authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or not authenticated."
        exit 1
    fi
    
    # Check Amplify CLI if project exists
    if [ -d "${APP_NAME}" ] && ! command -v amplify &> /dev/null; then
        warning "Amplify CLI not found but project directory exists."
        warning "Some cleanup operations may fail. Consider installing Amplify CLI."
    fi
    
    success "Prerequisites check completed"
}

# Function to delete SAML identity provider
delete_saml_provider() {
    log "Removing SAML identity provider..."
    
    if [ -n "$USER_POOL_ID" ]; then
        # Try to delete the SAML identity provider
        aws cognito-idp delete-identity-provider \
            --user-pool-id "${USER_POOL_ID}" \
            --provider-name "EnterpriseAD" 2>/dev/null || \
            warning "SAML identity provider may not exist or already deleted"
        
        success "SAML identity provider removal attempted"
    else
        warning "USER_POOL_ID not available. Skipping SAML provider deletion."
    fi
}

# Function to delete Cognito domain
delete_cognito_domain() {
    log "Removing Cognito domain..."
    
    if [ -n "$DOMAIN_PREFIX" ]; then
        # Delete domain
        aws cognito-idp delete-user-pool-domain \
            --domain "${DOMAIN_PREFIX}" 2>/dev/null || \
            warning "Cognito domain may not exist or already deleted"
        
        # Wait for domain deletion
        log "Waiting for domain deletion to complete..."
        max_attempts=10
        attempt=0
        while [ $attempt -lt $max_attempts ]; do
            domain_status=$(aws cognito-idp describe-user-pool-domain \
                --domain "${DOMAIN_PREFIX}" \
                --query 'DomainDescription.Status' --output text 2>/dev/null || echo "DELETED")
            
            if [ "$domain_status" = "DELETED" ] || [ "$domain_status" = "" ]; then
                break
            fi
            
            log "Domain status: ${domain_status}. Waiting for deletion..."
            sleep 10
            ((attempt++))
        done
        
        success "Cognito domain deletion completed"
    else
        warning "DOMAIN_PREFIX not available. Skipping domain deletion."
    fi
}

# Function to delete Amplify project
delete_amplify_project() {
    log "Removing Amplify project..."
    
    if [ -d "${APP_NAME}" ]; then
        cd "${APP_NAME}"
        
        # Check if this is an Amplify project
        if [ -f "amplify/.config/project-config.json" ]; then
            log "Found Amplify project. Attempting to delete backend..."
            
            # Delete Amplify backend
            amplify delete --yes 2>/dev/null || \
                warning "Amplify delete command failed. Some resources may remain."
            
            cd ..
        else
            warning "Directory exists but doesn't appear to be an Amplify project."
        fi
        
        success "Amplify project cleanup attempted"
    else
        warning "Amplify project directory '${APP_NAME}' not found."
    fi
}

# Function to force delete Cognito resources
force_delete_cognito() {
    log "Force deleting any remaining Cognito resources..."
    
    # Search for User Pools that match our naming pattern
    if [ -n "$USER_POOL_NAME" ]; then
        USER_POOLS=$(aws cognito-idp list-user-pools \
            --max-items 50 \
            --query "UserPools[?contains(Name, '${USER_POOL_NAME}')].Id" \
            --output text 2>/dev/null || true)
        
        if [ -n "$USER_POOLS" ]; then
            for pool_id in $USER_POOLS; do
                log "Found User Pool to delete: $pool_id"
                
                # Delete all users first
                log "Deleting users from User Pool: $pool_id"
                aws cognito-idp list-users --user-pool-id "$pool_id" \
                    --query 'Users[].Username' --output text | \
                while read username; do
                    if [ -n "$username" ]; then
                        aws cognito-idp admin-delete-user \
                            --user-pool-id "$pool_id" \
                            --username "$username" 2>/dev/null || true
                    fi
                done
                
                # Delete User Pool
                aws cognito-idp delete-user-pool \
                    --user-pool-id "$pool_id" 2>/dev/null || \
                    warning "Failed to delete User Pool: $pool_id"
            done
            
            success "Cognito User Pool cleanup completed"
        else
            log "No matching User Pools found for cleanup"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    # Remove project directory
    if [ -d "${APP_NAME}" ]; then
        log "Removing project directory: ${APP_NAME}"
        rm -rf "${APP_NAME}"
        success "Project directory removed"
    fi
    
    # Remove configuration files
    local files_to_remove=(".env" "saml-configuration.txt")
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log "Removing configuration file: $file"
            rm -f "$file"
        fi
    done
    
    success "Local file cleanup completed"
}

# Function to clean up environment variables
cleanup_environment_variables() {
    log "Cleaning up environment variables..."
    
    unset AWS_REGION AWS_ACCOUNT_ID APP_NAME USER_POOL_NAME USER_POOL_ID
    unset APP_CLIENT_ID COGNITO_DOMAIN DOMAIN_PREFIX RANDOM_SUFFIX
    
    success "Environment variables cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "==========================================="
    echo "✅ SAML identity provider removal attempted"
    echo "✅ Cognito domain deletion completed"
    echo "✅ Amplify project cleanup attempted"
    echo "✅ Cognito User Pool cleanup completed"
    echo "✅ Local files and directories removed"
    echo "✅ Environment variables cleaned up"
    echo ""
    echo "Cleanup completed!"
    echo ""
    warning "Note: Some AWS resources may take additional time to fully delete."
    warning "Check the AWS Console to verify all resources have been removed."
    echo "==========================================="
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if project directory still exists
    if [ -d "${APP_NAME}" ]; then
        warning "Project directory still exists: ${APP_NAME}"
    else
        success "Project directory successfully removed"
    fi
    
    # Check if configuration files still exist
    if [ -f ".env" ] || [ -f "saml-configuration.txt" ]; then
        warning "Some configuration files still exist"
    else
        success "Configuration files successfully removed"
    fi
    
    # Try to check Cognito resources
    if [ -n "$USER_POOL_ID" ]; then
        aws cognito-idp describe-user-pool \
            --user-pool-id "${USER_POOL_ID}" >/dev/null 2>&1 && \
            warning "User Pool may still exist: ${USER_POOL_ID}" || \
            success "User Pool successfully deleted"
    fi
    
    success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log "Starting Enterprise Authentication cleanup..."
    
    confirm_destruction
    load_environment
    check_prerequisites
    delete_saml_provider
    delete_cognito_domain
    delete_amplify_project
    force_delete_cognito
    cleanup_local_files
    verify_cleanup
    cleanup_environment_variables
    
    success "Cleanup completed successfully!"
    display_cleanup_summary
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompt"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  FORCE_DESTROY    Set to 'true' to skip confirmation"
            echo "  CI               Set to 'true' for CI/CD environments"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"