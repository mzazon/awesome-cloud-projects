#!/bin/bash

# Destroy script for AWS CodeArtifact Artifact Management
# This script safely removes all CodeArtifact resources created by the deploy script

set -e
set -o pipefail

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

# Function to check if AWS CLI is installed and configured
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
    
    log_success "Prerequisites check completed"
}

# Function to load deployment environment
load_deployment_environment() {
    log_info "Loading deployment environment..."
    
    # Try to load from deployment file
    if [[ -f "codeartifact-deployment.env" ]]; then
        source codeartifact-deployment.env
        log_success "Loaded deployment environment from codeartifact-deployment.env"
    else
        log_warning "Deployment environment file not found. Please provide resource details manually."
        
        # Prompt for required information
        read -p "Enter domain name: " DOMAIN_NAME
        read -p "Enter AWS region [$(aws configure get region)]: " AWS_REGION
        AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        
        if [[ -z "$DOMAIN_NAME" || -z "$AWS_REGION" ]]; then
            log_error "Domain name and region are required"
            exit 1
        fi
        
        # Set other variables
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export NPM_STORE_REPO="npm-store"
        export PYPI_STORE_REPO="pypi-store"
        export TEAM_REPO="team-dev"
        export PROD_REPO="production"
        export DOMAIN_OWNER=${AWS_ACCOUNT_ID}
    fi
    
    log_info "Using domain: ${DOMAIN_NAME}"
    log_info "Using region: ${AWS_REGION}"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    echo "  - Domain: ${DOMAIN_NAME}"
    echo "  - Repositories: ${NPM_STORE_REPO}, ${PYPI_STORE_REPO}, ${TEAM_REPO}, ${PROD_REPO}"
    echo "  - All packages and versions stored in these repositories"
    echo "  - Repository policies and configurations"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to reset package manager configurations
reset_package_managers() {
    log_info "Resetting package manager configurations..."
    
    # Reset npm configuration if npm is available
    if command -v npm &> /dev/null; then
        npm config delete registry 2>/dev/null || true
        npm config delete @mycompany:registry 2>/dev/null || true
        log_success "Reset npm configuration"
    fi
    
    # Reset pip configuration if pip is available
    if command -v pip &> /dev/null; then
        pip config unset global.index-url 2>/dev/null || true
        pip config unset global.trusted-host 2>/dev/null || true
        log_success "Reset pip configuration"
    fi
    
    log_success "Package manager configurations reset"
}

# Function to check if repository exists
check_repository_exists() {
    local repo_name=$1
    aws codeartifact describe-repository \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --repository ${repo_name} \
        --region ${AWS_REGION} &> /dev/null
}

# Function to delete repository policies
delete_repository_policies() {
    log_info "Deleting repository policies..."
    
    # Delete team repository permissions policy
    if check_repository_exists ${TEAM_REPO}; then
        aws codeartifact delete-repository-permissions-policy \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --region ${AWS_REGION} 2>/dev/null || true
        log_success "Deleted repository permissions policy for ${TEAM_REPO}"
    fi
    
    log_success "Repository policies deleted"
}

# Function to delete repositories
delete_repositories() {
    log_info "Deleting repositories in dependency order..."
    
    # Delete production repository first (no dependencies)
    if check_repository_exists ${PROD_REPO}; then
        log_info "Deleting production repository..."
        aws codeartifact delete-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${PROD_REPO} \
            --region ${AWS_REGION}
        log_success "Deleted production repository"
        
        # Wait for deletion to complete
        sleep 5
    else
        log_warning "Production repository does not exist or already deleted"
    fi
    
    # Delete team repository (depends on npm-store and pypi-store)
    if check_repository_exists ${TEAM_REPO}; then
        log_info "Deleting team development repository..."
        aws codeartifact delete-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --region ${AWS_REGION}
        log_success "Deleted team development repository"
        
        # Wait for deletion to complete
        sleep 5
    else
        log_warning "Team development repository does not exist or already deleted"
    fi
    
    # Delete npm store repository
    if check_repository_exists ${NPM_STORE_REPO}; then
        log_info "Deleting npm store repository..."
        aws codeartifact delete-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${NPM_STORE_REPO} \
            --region ${AWS_REGION}
        log_success "Deleted npm store repository"
        
        # Wait for deletion to complete
        sleep 5
    else
        log_warning "npm store repository does not exist or already deleted"
    fi
    
    # Delete pypi store repository
    if check_repository_exists ${PYPI_STORE_REPO}; then
        log_info "Deleting pypi store repository..."
        aws codeartifact delete-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${PYPI_STORE_REPO} \
            --region ${AWS_REGION}
        log_success "Deleted pypi store repository"
        
        # Wait for deletion to complete
        sleep 5
    else
        log_warning "pypi store repository does not exist or already deleted"
    fi
    
    log_success "All repositories deleted"
}

# Function to check if domain exists
check_domain_exists() {
    aws codeartifact describe-domain \
        --domain ${DOMAIN_NAME} \
        --region ${AWS_REGION} &> /dev/null
}

# Function to delete domain
delete_domain() {
    log_info "Deleting CodeArtifact domain..."
    
    if check_domain_exists; then
        aws codeartifact delete-domain \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --region ${AWS_REGION}
        log_success "Deleted CodeArtifact domain: ${DOMAIN_NAME}"
    else
        log_warning "Domain does not exist or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    # Remove policy files
    rm -f /tmp/codeartifact-policies/dev-policy.json 2>/dev/null || true
    rm -f /tmp/codeartifact-policies/prod-policy.json 2>/dev/null || true
    rm -f /tmp/codeartifact-policies/team-repo-policy.json 2>/dev/null || true
    rmdir /tmp/codeartifact-policies 2>/dev/null || true
    
    # Remove test directories
    rm -rf /tmp/npm-test 2>/dev/null || true
    rm -rf /tmp/pip-test 2>/dev/null || true
    
    # Remove custom package directory if it exists
    rm -rf my-custom-package 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Function to clean environment variables
cleanup_environment_variables() {
    log_info "Cleaning up environment variables..."
    
    unset DOMAIN_NAME NPM_STORE_REPO PYPI_STORE_REPO TEAM_REPO PROD_REPO
    unset DOMAIN_OWNER AWS_ACCOUNT_ID CODEARTIFACT_AUTH_TOKEN
    
    log_success "Environment variables cleaned up"
}

# Function to remove deployment info file
remove_deployment_file() {
    log_info "Removing deployment information file..."
    
    if [[ -f "codeartifact-deployment.env" ]]; then
        rm -f codeartifact-deployment.env
        log_success "Removed deployment information file"
    else
        log_info "Deployment information file not found"
    fi
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Check if domain still exists
    if check_domain_exists; then
        log_warning "Domain ${DOMAIN_NAME} still exists - deletion may be in progress"
    else
        log_success "Domain deletion confirmed"
    fi
    
    # Check for any remaining repositories
    local remaining_repos=$(aws codeartifact list-domains \
        --region ${AWS_REGION} \
        --query "domains[?name=='${DOMAIN_NAME}']" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$remaining_repos" ]]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may still be in deletion process"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "CodeArtifact cleanup completed!"
    echo ""
    log_info "Cleanup summary:"
    echo "  ✅ Package manager configurations reset"
    echo "  ✅ Repository policies deleted"
    echo "  ✅ All repositories deleted"
    echo "  ✅ Domain deleted"
    echo "  ✅ Local files and directories cleaned up"
    echo "  ✅ Environment variables cleared"
    echo ""
    log_info "All CodeArtifact resources have been removed."
    log_info "IAM policies in /tmp/codeartifact-policies/ were removed (if they existed)."
    echo ""
    log_warning "Note: If you attached IAM policies to users or roles, you may want to detach them manually."
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Some resources may not have been deleted."
    log_info "You can re-run this script to continue cleanup."
    exit 1
}

# Main destruction function
main() {
    # Set up interrupt handler
    trap cleanup_on_interrupt INT TERM
    
    log_info "Starting CodeArtifact cleanup..."
    
    check_prerequisites
    load_deployment_environment
    confirm_deletion
    reset_package_managers
    delete_repository_policies
    delete_repositories
    delete_domain
    cleanup_local_files
    cleanup_environment_variables
    remove_deployment_file
    verify_deletion
    display_cleanup_summary
}

# Function to handle dry run mode
dry_run() {
    log_info "DRY RUN MODE - No resources will be deleted"
    
    check_prerequisites
    load_deployment_environment
    
    log_info "Resources that would be deleted:"
    echo "  - Domain: ${DOMAIN_NAME}"
    
    # Check which repositories exist
    if check_repository_exists ${PROD_REPO}; then
        echo "  - Repository: ${PROD_REPO} (exists)"
    fi
    if check_repository_exists ${TEAM_REPO}; then
        echo "  - Repository: ${TEAM_REPO} (exists)"
    fi
    if check_repository_exists ${NPM_STORE_REPO}; then
        echo "  - Repository: ${NPM_STORE_REPO} (exists)"
    fi
    if check_repository_exists ${PYPI_STORE_REPO}; then
        echo "  - Repository: ${PYPI_STORE_REPO} (exists)"
    fi
    
    echo "  - Local files: policy files, test directories, deployment info"
    echo "  - Package manager configurations"
    echo ""
    log_info "Run without --dry-run to perform actual deletion"
}

# Check for dry run flag
if [[ "$1" == "--dry-run" ]]; then
    dry_run
else
    main "$@"
fi