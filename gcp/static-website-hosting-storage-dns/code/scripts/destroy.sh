#!/bin/bash

# Static Website Hosting with Cloud Storage and DNS - Cleanup Script
# This script removes all resources created by the deploy.sh script
# Based on recipe: Static Website Hosting with Cloud Storage and DNS

set -euo pipefail

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
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "You are not authenticated with gcloud. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [ -f ".deployment_state" ]; then
        # Source the deployment state file
        source .deployment_state
        
        log_success "Deployment state loaded:"
        log_info "  PROJECT_ID: ${PROJECT_ID}"
        log_info "  DOMAIN_NAME: ${DOMAIN_NAME}"
        log_info "  BUCKET_NAME: ${BUCKET_NAME}"
        log_info "  REGION: ${REGION}"
        log_info "  DNS_ZONE_NAME: ${DNS_ZONE_NAME}"
        log_info "  DEPLOYMENT_DATE: ${DEPLOYMENT_DATE}"
        
        return 0
    else
        log_warning "No deployment state file found (.deployment_state)"
        return 1
    fi
}

# Function to prompt for manual configuration
prompt_manual_configuration() {
    log_warning "Deployment state not found. Manual configuration required."
    echo
    
    # Prompt for required variables
    read -p "Enter GCP Project ID: " PROJECT_ID
    if [ -z "$PROJECT_ID" ]; then
        log_error "Project ID is required"
        exit 1
    fi
    
    read -p "Enter domain name (e.g., example.com): " DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        log_error "Domain name is required"
        exit 1
    fi
    
    read -p "Enter DNS zone name (e.g., website-zone-abc123): " DNS_ZONE_NAME
    if [ -z "$DNS_ZONE_NAME" ]; then
        log_error "DNS zone name is required"
        exit 1
    fi
    
    # Set derived variables
    export PROJECT_ID
    export DOMAIN_NAME
    export BUCKET_NAME="${DOMAIN_NAME}"
    export REGION="${REGION:-us-central1}"
    export DNS_ZONE_NAME
    
    log_success "Manual configuration completed"
}

# Function to get user confirmation
get_user_confirmation() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete the following resources:"
    log_warning "  • Cloud Storage bucket: gs://${BUCKET_NAME}"
    log_warning "  • All website content in the bucket"
    log_warning "  • Cloud DNS zone: ${DNS_ZONE_NAME}"
    log_warning "  • DNS records for domain: ${DOMAIN_NAME}"
    echo
    
    if [ "${SKIP_CONFIRMATION:-false}" = "true" ]; then
        log_info "Skipping confirmation due to --force flag"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion. Proceeding..."
}

# Function to set project context
set_project_context() {
    log_info "Setting project context..."
    
    # Set the project ID
    gcloud config set project ${PROJECT_ID}
    
    # Verify project access
    if ! gcloud projects describe ${PROJECT_ID} &>/dev/null; then
        log_error "Cannot access project ${PROJECT_ID}. Check project ID and permissions."
        exit 1
    fi
    
    log_success "Project context set to: ${PROJECT_ID}"
}

# Function to remove DNS records and zone
cleanup_dns_resources() {
    log_info "Cleaning up DNS resources..."
    
    # Check if DNS zone exists
    if ! gcloud dns managed-zones describe ${DNS_ZONE_NAME} &>/dev/null; then
        log_warning "DNS zone ${DNS_ZONE_NAME} not found. Skipping DNS cleanup."
        return 0
    fi
    
    # Remove CNAME record if it exists
    log_info "Removing CNAME record for ${DOMAIN_NAME}..."
    if gcloud dns record-sets describe ${DOMAIN_NAME}. --zone=${DNS_ZONE_NAME} --type=CNAME &>/dev/null; then
        gcloud dns record-sets delete ${DOMAIN_NAME}. \
            --zone=${DNS_ZONE_NAME} \
            --type=CNAME \
            --quiet
        
        log_success "✅ CNAME record deleted"
    else
        log_warning "CNAME record for ${DOMAIN_NAME} not found"
    fi
    
    # Wait for DNS propagation
    log_info "Waiting for DNS record deletion to propagate..."
    sleep 5
    
    # Remove DNS zone
    log_info "Removing DNS zone: ${DNS_ZONE_NAME}..."
    gcloud dns managed-zones delete ${DNS_ZONE_NAME} --quiet
    
    log_success "✅ DNS zone deleted"
}

# Function to remove storage bucket and content
cleanup_storage_resources() {
    log_info "Cleaning up Cloud Storage resources..."
    
    # Check if bucket exists
    if ! gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        log_warning "Storage bucket gs://${BUCKET_NAME} not found. Skipping storage cleanup."
        return 0
    fi
    
    # List bucket contents for confirmation
    log_info "Bucket contents to be deleted:"
    gsutil ls gs://${BUCKET_NAME}/ || log_warning "No objects found in bucket"
    
    # Remove all objects from bucket
    log_info "Removing all objects from bucket..."
    gsutil -m rm -r gs://${BUCKET_NAME}/* || log_warning "No objects to delete"
    
    # Remove the bucket itself
    log_info "Removing bucket: gs://${BUCKET_NAME}..."
    gsutil rb gs://${BUCKET_NAME}
    
    log_success "✅ Storage bucket and contents deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove local HTML files if they exist
    if [ -f "index.html" ]; then
        rm -f index.html
        log_success "Removed index.html"
    fi
    
    if [ -f "404.html" ]; then
        rm -f 404.html
        log_success "Removed 404.html"
    fi
    
    # Remove deployment state file
    if [ -f ".deployment_state" ]; then
        rm -f .deployment_state
        log_success "Removed .deployment_state"
    fi
    
    log_success "✅ Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Verify bucket deletion
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        log_error "❌ Storage bucket still exists: gs://${BUCKET_NAME}"
        return 1
    else
        log_success "✅ Storage bucket successfully deleted"
    fi
    
    # Verify DNS zone deletion
    if gcloud dns managed-zones describe ${DNS_ZONE_NAME} &>/dev/null; then
        log_error "❌ DNS zone still exists: ${DNS_ZONE_NAME}"
        return 1
    else
        log_success "✅ DNS zone successfully deleted"
    fi
    
    # Verify local files are cleaned up
    local files_remaining=false
    for file in index.html 404.html .deployment_state; do
        if [ -f "$file" ]; then
            log_error "❌ Local file still exists: $file"
            files_remaining=true
        fi
    done
    
    if [ "$files_remaining" = false ]; then
        log_success "✅ Local files successfully cleaned up"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "🎉 Cleanup completed successfully!"
    echo
    log_info "Cleanup Summary:"
    log_info "================"
    log_info "✅ Removed Cloud Storage bucket: gs://${BUCKET_NAME}"
    log_info "✅ Removed DNS zone: ${DNS_ZONE_NAME}"
    log_info "✅ Removed DNS records for: ${DOMAIN_NAME}"
    log_info "✅ Cleaned up local files"
    echo
    log_info "Additional Actions Required:"
    log_info "• Update your domain registrar to remove the Google Cloud name servers"
    log_info "• Consider disabling unused APIs to avoid potential charges:"
    log_info "  - Cloud Storage API"
    log_info "  - Cloud DNS API"
    echo
    log_success "All static website hosting resources have been removed!"
}

# Function to handle partial cleanup scenarios
handle_partial_cleanup() {
    log_warning "Some resources may not have been fully cleaned up"
    echo
    log_info "Manual cleanup commands:"
    log_info "========================"
    echo
    log_info "To manually remove the storage bucket:"
    log_info "  gsutil -m rm -r gs://${BUCKET_NAME}/*"
    log_info "  gsutil rb gs://${BUCKET_NAME}"
    echo
    log_info "To manually remove the DNS zone:"
    log_info "  gcloud dns record-sets delete ${DOMAIN_NAME}. --zone=${DNS_ZONE_NAME} --type=CNAME --quiet"
    log_info "  gcloud dns managed-zones delete ${DNS_ZONE_NAME} --quiet"
    echo
    log_info "To clean up local files:"
    log_info "  rm -f index.html 404.html .deployment_state"
}

# Main cleanup function
main() {
    log_info "🧹 Starting static website hosting cleanup..."
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state or prompt for manual configuration
    if ! load_deployment_state; then
        prompt_manual_configuration
    fi
    
    # Get user confirmation
    get_user_confirmation
    
    # Set project context
    set_project_context
    
    # Perform cleanup steps
    local cleanup_successful=true
    
    cleanup_dns_resources || cleanup_successful=false
    cleanup_storage_resources || cleanup_successful=false
    cleanup_local_files || cleanup_successful=false
    
    # Verify cleanup if all steps succeeded
    if [ "$cleanup_successful" = true ]; then
        verify_cleanup || cleanup_successful=false
    fi
    
    # Display results
    if [ "$cleanup_successful" = true ]; then
        display_cleanup_summary
    else
        log_warning "Cleanup completed with some issues"
        handle_partial_cleanup
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --force        Skip confirmation prompts (dangerous!)"
        echo "  --dry-run      Show what would be deleted without executing"
        echo ""
        echo "This script removes all resources created by deploy.sh:"
        echo "  • Cloud Storage bucket and all contents"
        echo "  • Cloud DNS zone and records"
        echo "  • Local HTML and state files"
        echo ""
        echo "The script will:"
        echo "  1. Load deployment state from .deployment_state file"
        echo "  2. Prompt for confirmation before deletion"
        echo "  3. Remove all cloud resources"
        echo "  4. Clean up local files"
        echo "  5. Verify cleanup completion"
        echo ""
        echo "Examples:"
        echo "  ./destroy.sh                    # Interactive cleanup"
        echo "  ./destroy.sh --force            # Skip confirmation"
        echo "  ./destroy.sh --dry-run          # Show what would be deleted"
        exit 0
        ;;
    --force)
        export SKIP_CONFIRMATION=true
        main
        ;;
    --dry-run)
        log_info "🔍 Dry run mode - showing what would be deleted..."
        echo
        
        # Try to load deployment state for dry run
        if load_deployment_state; then
            log_warning "The following resources would be PERMANENTLY DELETED:"
            log_warning "  • Cloud Storage bucket: gs://${BUCKET_NAME}"
            log_warning "  • All website content in the bucket"
            log_warning "  • Cloud DNS zone: ${DNS_ZONE_NAME}"
            log_warning "  • DNS records for domain: ${DOMAIN_NAME}"
            log_warning "  • Local files: index.html, 404.html, .deployment_state"
        else
            log_info "No deployment state found. Manual configuration would be required."
            log_info "Resources that would typically be deleted:"
            log_info "  • Cloud Storage bucket matching your domain name"
            log_info "  • Cloud DNS zone and CNAME records"
            log_info "  • Local website files and deployment state"
        fi
        
        echo
        log_info "To perform actual cleanup: ./destroy.sh"
        log_info "To skip confirmation: ./destroy.sh --force"
        exit 0
        ;;
    "")
        # No arguments, run main cleanup
        main
        ;;
    *)
        log_error "Unknown argument: $1"
        log_error "Use --help for usage information"
        exit 1
        ;;
esac