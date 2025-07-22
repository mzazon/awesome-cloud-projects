#!/bin/bash

# Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions
# Cleanup Script for GCP
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration variables
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Get current project if not specified
    if [[ -z "${PROJECT_ID}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No project ID specified and no default project configured."
            log_error "Please set PROJECT_ID environment variable or use --project-id flag."
            exit 1
        fi
    fi
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Prerequisites check completed"
    log "Using Project ID: ${PROJECT_ID}"
    log "Using Region: ${REGION}"
}

# Function to confirm destructive actions
confirm_deletion() {
    if [[ "${FORCE_DELETE}" != "true" ]]; then
        echo ""
        log_warning "This will permanently delete all Certificate Lifecycle Management resources in project: ${PROJECT_ID}"
        log_warning "This action cannot be undone!"
        echo ""
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log "Deletion cancelled by user"
            exit 0
        fi
    fi
}

# Function to get resource names from project
discover_resources() {
    log "Discovering Certificate Lifecycle Management resources..."
    
    # Discover Cloud Functions
    FUNCTIONS=($(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~cert-monitor OR name~cert-renew OR name~cert-revoke" 2>/dev/null || echo ""))
    
    # Discover Cloud Scheduler jobs
    SCHEDULER_JOBS=($(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name~cert-check" 2>/dev/null || echo ""))
    
    # Discover CA pools
    CA_POOLS=($(gcloud privateca pools list --location="${REGION}" --format="value(name)" --filter="name~ca-pool" 2>/dev/null || echo ""))
    
    # Discover certificate templates
    CERT_TEMPLATES=($(gcloud privateca templates list --location="${REGION}" --format="value(name)" --filter="name~web-server-template" 2>/dev/null || echo ""))
    
    # Discover secrets
    SECRETS=($(gcloud secrets list --format="value(name)" --filter="name~cert-" 2>/dev/null || echo ""))
    
    # Discover service accounts
    SERVICE_ACCOUNTS=($(gcloud iam service-accounts list --format="value(email)" --filter="email~cert-automation-sa" 2>/dev/null || echo ""))
    
    # Discover alerting policies
    ALERT_POLICIES=($(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName~Certificate" 2>/dev/null || echo ""))
    
    log_success "Resource discovery completed"
    
    # Display discovered resources
    echo ""
    echo "Discovered Resources:"
    echo "===================="
    echo "Functions: ${#FUNCTIONS[@]} found"
    echo "Scheduler Jobs: ${#SCHEDULER_JOBS[@]} found"
    echo "CA Pools: ${#CA_POOLS[@]} found"
    echo "Certificate Templates: ${#CERT_TEMPLATES[@]} found"
    echo "Secrets: ${#SECRETS[@]} found"
    echo "Service Accounts: ${#SERVICE_ACCOUNTS[@]} found"
    echo "Alert Policies: ${#ALERT_POLICIES[@]} found"
    echo ""
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    if [[ ${#SCHEDULER_JOBS[@]} -gt 0 ]]; then
        log "Deleting Cloud Scheduler jobs..."
        
        for job in "${SCHEDULER_JOBS[@]}"; do
            if [[ -n "${job}" ]]; then
                log "Deleting scheduler job: ${job}"
                if gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted scheduler job: ${job}"
                else
                    log_warning "Failed to delete scheduler job: ${job} (may not exist)"
                fi
            fi
        done
    else
        log "No Cloud Scheduler jobs found to delete"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
        log "Deleting Cloud Functions..."
        
        for function in "${FUNCTIONS[@]}"; do
            if [[ -n "${function}" ]]; then
                log "Deleting function: ${function}"
                if gcloud functions delete "${function}" --region="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted function: ${function}"
                else
                    log_warning "Failed to delete function: ${function} (may not exist)"
                fi
            fi
        done
        
        # Wait for functions to be fully deleted
        log "Waiting for functions to be fully deleted (15 seconds)..."
        sleep 15
    else
        log "No Cloud Functions found to delete"
    fi
}

# Function to delete certificate templates
delete_certificate_templates() {
    if [[ ${#CERT_TEMPLATES[@]} -gt 0 ]]; then
        log "Deleting certificate templates..."
        
        for template in "${CERT_TEMPLATES[@]}"; do
            if [[ -n "${template}" ]]; then
                # Extract template name from full path
                template_name=$(basename "${template}")
                log "Deleting certificate template: ${template_name}"
                if gcloud privateca templates delete "${template_name}" --location="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted certificate template: ${template_name}"
                else
                    log_warning "Failed to delete certificate template: ${template_name} (may not exist)"
                fi
            fi
        done
    else
        log "No certificate templates found to delete"
    fi
}

# Function to delete secrets
delete_secrets() {
    if [[ ${#SECRETS[@]} -gt 0 ]]; then
        log "Deleting secrets..."
        
        for secret in "${SECRETS[@]}"; do
            if [[ -n "${secret}" ]]; then
                # Extract secret name from full path
                secret_name=$(basename "${secret}")
                log "Deleting secret: ${secret_name}"
                if gcloud secrets delete "${secret_name}" --quiet 2>/dev/null; then
                    log_success "Deleted secret: ${secret_name}"
                else
                    log_warning "Failed to delete secret: ${secret_name} (may not exist)"
                fi
            fi
        done
    else
        log "No secrets found to delete"
    fi
}

# Function to delete certificate authorities
delete_certificate_authorities() {
    if [[ ${#CA_POOLS[@]} -gt 0 ]]; then
        log "Deleting Certificate Authorities..."
        
        for ca_pool_path in "${CA_POOLS[@]}"; do
            if [[ -n "${ca_pool_path}" ]]; then
                # Extract pool name from full path
                ca_pool_name=$(basename "${ca_pool_path}")
                
                log "Processing CA pool: ${ca_pool_name}"
                
                # List and disable subordinate CAs first
                local subordinates
                subordinates=($(gcloud privateca subordinates list --pool="${ca_pool_name}" --location="${REGION}" --format="value(name)" 2>/dev/null || echo ""))
                
                for sub_ca_path in "${subordinates[@]}"; do
                    if [[ -n "${sub_ca_path}" ]]; then
                        sub_ca_name=$(basename "${sub_ca_path}")
                        log "Disabling subordinate CA: ${sub_ca_name}"
                        gcloud privateca subordinates disable "${sub_ca_name}" \
                            --pool="${ca_pool_name}" \
                            --location="${REGION}" \
                            --ignore-active-certificates \
                            --quiet 2>/dev/null || log_warning "Failed to disable subordinate CA: ${sub_ca_name}"
                        
                        log "Deleting subordinate CA: ${sub_ca_name}"
                        gcloud privateca subordinates delete "${sub_ca_name}" \
                            --pool="${ca_pool_name}" \
                            --location="${REGION}" \
                            --ignore-active-certificates \
                            --quiet 2>/dev/null || log_warning "Failed to delete subordinate CA: ${sub_ca_name}"
                    fi
                done
                
                # List and disable root CAs
                local roots
                roots=($(gcloud privateca roots list --pool="${ca_pool_name}" --location="${REGION}" --format="value(name)" 2>/dev/null || echo ""))
                
                for root_ca_path in "${roots[@]}"; do
                    if [[ -n "${root_ca_path}" ]]; then
                        root_ca_name=$(basename "${root_ca_path}")
                        log "Disabling root CA: ${root_ca_name}"
                        gcloud privateca roots disable "${root_ca_name}" \
                            --pool="${ca_pool_name}" \
                            --location="${REGION}" \
                            --ignore-active-certificates \
                            --quiet 2>/dev/null || log_warning "Failed to disable root CA: ${root_ca_name}"
                        
                        log "Deleting root CA: ${root_ca_name}"
                        gcloud privateca roots delete "${root_ca_name}" \
                            --pool="${ca_pool_name}" \
                            --location="${REGION}" \
                            --ignore-active-certificates \
                            --quiet 2>/dev/null || log_warning "Failed to delete root CA: ${root_ca_name}"
                    fi
                done
                
                # Wait for CAs to be fully deleted before deleting the pool
                log "Waiting for CAs to be fully deleted (30 seconds)..."
                sleep 30
                
                # Delete the CA pool
                log "Deleting CA pool: ${ca_pool_name}"
                if gcloud privateca pools delete "${ca_pool_name}" \
                    --location="${REGION}" \
                    --quiet 2>/dev/null; then
                    log_success "Deleted CA pool: ${ca_pool_name}"
                else
                    log_warning "Failed to delete CA pool: ${ca_pool_name} (may not exist or still have active CAs)"
                fi
            fi
        done
    else
        log "No CA pools found to delete"
    fi
}

# Function to delete alerting policies
delete_alert_policies() {
    if [[ ${#ALERT_POLICIES[@]} -gt 0 ]]; then
        log "Deleting alerting policies..."
        
        for policy in "${ALERT_POLICIES[@]}"; do
            if [[ -n "${policy}" ]]; then
                log "Deleting alerting policy: ${policy}"
                if gcloud alpha monitoring policies delete "${policy}" --quiet 2>/dev/null; then
                    log_success "Deleted alerting policy: ${policy}"
                else
                    log_warning "Failed to delete alerting policy: ${policy} (may not exist)"
                fi
            fi
        done
    else
        log "No alerting policies found to delete"
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        log "Deleting service accounts..."
        
        for service_account in "${SERVICE_ACCOUNTS[@]}"; do
            if [[ -n "${service_account}" ]]; then
                log "Deleting service account: ${service_account}"
                if gcloud iam service-accounts delete "${service_account}" --quiet 2>/dev/null; then
                    log_success "Deleted service account: ${service_account}"
                else
                    log_warning "Failed to delete service account: ${service_account} (may not exist)"
                fi
            fi
        done
    else
        log "No service accounts found to delete"
    fi
}

# Function to delete project (if requested)
delete_project() {
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        log_warning "This will permanently delete ALL resources in the project!"
        
        if [[ "${FORCE_DELETE}" != "true" ]]; then
            echo ""
            read -p "Are you absolutely sure you want to delete the entire project? (type 'DELETE PROJECT' to confirm): " project_confirmation
            if [[ "${project_confirmation}" != "DELETE PROJECT" ]]; then
                log "Project deletion cancelled by user"
                return
            fi
        fi
        
        if gcloud projects delete "${PROJECT_ID}" --quiet; then
            log_success "Project deletion initiated: ${PROJECT_ID}"
            log "Note: Project deletion may take several minutes to complete"
        else
            log_error "Failed to delete project: ${PROJECT_ID}"
        fi
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~cert-monitor OR name~cert-renew OR name~cert-revoke" 2>/dev/null | wc -l)
    
    # Check remaining scheduler jobs
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name~cert-check" 2>/dev/null | wc -l)
    
    # Check remaining CA pools
    local remaining_pools
    remaining_pools=$(gcloud privateca pools list --location="${REGION}" --format="value(name)" --filter="name~ca-pool" 2>/dev/null | wc -l)
    
    # Check remaining secrets
    local remaining_secrets
    remaining_secrets=$(gcloud secrets list --format="value(name)" --filter="name~cert-" 2>/dev/null | wc -l)
    
    echo ""
    echo "Cleanup Verification:"
    echo "===================="
    echo "Remaining Functions: ${remaining_functions}"
    echo "Remaining Scheduler Jobs: ${remaining_jobs}"
    echo "Remaining CA Pools: ${remaining_pools}"
    echo "Remaining Secrets: ${remaining_secrets}"
    echo ""
    
    if [[ $((remaining_functions + remaining_jobs + remaining_pools + remaining_secrets)) -eq 0 ]]; then
        log_success "All Certificate Lifecycle Management resources have been successfully removed"
    else
        log_warning "Some resources may still exist. Check the Google Cloud Console for any remaining resources."
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    log "Cleanup Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources cleaned up:"
    echo "- Cloud Functions"
    echo "- Cloud Scheduler jobs"
    echo "- Certificate Authority infrastructure"
    echo "- Certificate templates"
    echo "- Secret Manager secrets"
    echo "- Service accounts"
    echo "- Monitoring alerting policies"
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "- Entire project (deletion initiated)"
    fi
    echo ""
    log_success "Certificate Lifecycle Management cleanup completed!"
    echo "===================="
}

# Main cleanup function
main() {
    log "Starting Certificate Lifecycle Management cleanup..."
    
    check_prerequisites
    discover_resources
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_scheduler_jobs
    delete_cloud_functions
    delete_certificate_templates
    delete_secrets
    delete_certificate_authorities
    delete_alert_policies
    delete_service_accounts
    
    # Optionally delete the entire project
    delete_project
    
    # Verify cleanup (unless deleting entire project)
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        verify_cleanup
    fi
    
    display_summary
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID          Set Google Cloud project ID"
            echo "  --region REGION                  Set region (default: us-central1)"
            echo "  --force                          Skip confirmation prompts"
            echo "  --delete-project                 Delete the entire project (DESTRUCTIVE!)"
            echo "  --help                           Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID                       Google Cloud project ID"
            echo "  REGION                           Region"
            echo "  FORCE_DELETE                     Skip confirmations (true/false)"
            echo "  DELETE_PROJECT                   Delete entire project (true/false)"
            echo ""
            echo "Examples:"
            echo "  $0                              # Interactive cleanup"
            echo "  $0 --force                      # Non-interactive cleanup"
            echo "  $0 --project-id my-project      # Cleanup specific project"
            echo "  $0 --delete-project --force     # Delete entire project without prompts"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main