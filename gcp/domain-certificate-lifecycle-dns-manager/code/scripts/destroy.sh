#!/bin/bash

# Domain and Certificate Lifecycle Management with Cloud DNS and Certificate Manager
# Cleanup/Destroy Script for GCP
# 
# This script safely removes all resources created by the deploy.sh script:
# - Cloud Scheduler jobs
# - Cloud Functions
# - Application Load Balancer components
# - Certificate Manager certificates and maps
# - Cloud DNS zones
# - Service accounts
# - IAM bindings

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm destructive operation
confirm_destruction() {
    echo "=================================================="
    echo "Domain and Certificate Lifecycle Management"
    echo "GCP Cleanup Script"
    echo "=================================================="
    echo
    
    log_warning "This script will permanently delete all resources created by the deployment."
    log_warning "This action cannot be undone!"
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_info "Force destroy mode enabled. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ -f "deployment_state.env" ]]; then
        source deployment_state.env
        log_success "Deployment state loaded from deployment_state.env"
    else
        log_warning "deployment_state.env not found. Using environment variables or defaults."
        
        # Set defaults if not already set
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export DNS_ZONE_NAME="${DNS_ZONE_NAME:-}"
        export DOMAIN_NAME="${DOMAIN_NAME:-}"
        export CERT_NAME="${CERT_NAME:-}"
        export FUNCTION_NAME="${FUNCTION_NAME:-}"
        export SCHEDULER_JOB="${SCHEDULER_JOB:-}"
        export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "PROJECT_ID not set. Please set environment variables or ensure deployment_state.env exists."
            exit 1
        fi
    fi
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
    gcloud config set compute/zone "${ZONE}" 2>/dev/null || true
    
    log_info "Using project: ${PROJECT_ID}"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible."
        exit 1
    fi
    
    log_success "Prerequisites validated successfully"
}

# Function to remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."
    
    # List and remove all scheduler jobs with our naming pattern
    local jobs_removed=0
    
    if [[ -n "${SCHEDULER_JOB:-}" ]]; then
        if gcloud scheduler jobs describe "${SCHEDULER_JOB}" >/dev/null 2>&1; then
            gcloud scheduler jobs delete "${SCHEDULER_JOB}" --quiet
            log_success "Deleted scheduler job: ${SCHEDULER_JOB}"
            ((jobs_removed++))
        fi
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local daily_job="daily-cert-audit-${RANDOM_SUFFIX}"
        if gcloud scheduler jobs describe "${daily_job}" >/dev/null 2>&1; then
            gcloud scheduler jobs delete "${daily_job}" --quiet
            log_success "Deleted scheduler job: ${daily_job}"
            ((jobs_removed++))
        fi
    fi
    
    # Fallback: find jobs by pattern
    local job_list
    job_list=$(gcloud scheduler jobs list --filter="name:cert-check OR name:daily-cert-audit" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$job_list" ]]; then
        while IFS= read -r job_name; do
            if [[ -n "$job_name" ]]; then
                gcloud scheduler jobs delete "$job_name" --quiet
                log_success "Deleted scheduler job: $job_name"
                ((jobs_removed++))
            fi
        done <<< "$job_list"
    fi
    
    if [[ $jobs_removed -eq 0 ]]; then
        log_info "No scheduler jobs found to remove"
    else
        log_success "Removed $jobs_removed scheduler job(s)"
    fi
}

# Function to remove Cloud Functions
remove_cloud_functions() {
    log_info "Removing Cloud Functions..."
    
    local functions_removed=0
    
    # Remove specific functions if names are known
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" >/dev/null 2>&1; then
            gcloud functions delete "${FUNCTION_NAME}" --quiet
            log_success "Deleted function: ${FUNCTION_NAME}"
            ((functions_removed++))
        fi
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local dns_function="dns-update-${RANDOM_SUFFIX}"
        if gcloud functions describe "${dns_function}" >/dev/null 2>&1; then
            gcloud functions delete "${dns_function}" --quiet
            log_success "Deleted function: ${dns_function}"
            ((functions_removed++))
        fi
    fi
    
    # Fallback: find functions by pattern
    local function_list
    function_list=$(gcloud functions list --filter="name:cert-automation OR name:dns-update" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$function_list" ]]; then
        while IFS= read -r func_name; do
            if [[ -n "$func_name" ]]; then
                gcloud functions delete "$func_name" --quiet
                log_success "Deleted function: $func_name"
                ((functions_removed++))
            fi
        done <<< "$function_list"
    fi
    
    if [[ $functions_removed -eq 0 ]]; then
        log_info "No Cloud Functions found to remove"
    else
        log_success "Removed $functions_removed Cloud Function(s)"
    fi
}

# Function to remove load balancer components
remove_load_balancer() {
    log_info "Removing Application Load Balancer components..."
    
    local lb_resources_removed=0
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        # Remove forwarding rule
        local forwarding_rule="demo-https-rule-${RANDOM_SUFFIX}"
        if gcloud compute forwarding-rules describe "$forwarding_rule" --global >/dev/null 2>&1; then
            gcloud compute forwarding-rules delete "$forwarding_rule" --global --quiet
            log_success "Deleted forwarding rule: $forwarding_rule"
            ((lb_resources_removed++))
        fi
        
        # Remove HTTPS proxy
        local https_proxy="demo-https-proxy-${RANDOM_SUFFIX}"
        if gcloud compute target-https-proxies describe "$https_proxy" --global >/dev/null 2>&1; then
            gcloud compute target-https-proxies delete "$https_proxy" --global --quiet
            log_success "Deleted HTTPS proxy: $https_proxy"
            ((lb_resources_removed++))
        fi
        
        # Remove URL map
        local url_map="demo-url-map-${RANDOM_SUFFIX}"
        if gcloud compute url-maps describe "$url_map" --global >/dev/null 2>&1; then
            gcloud compute url-maps delete "$url_map" --global --quiet
            log_success "Deleted URL map: $url_map"
            ((lb_resources_removed++))
        fi
        
        # Remove backend service
        local backend_service="demo-backend-${RANDOM_SUFFIX}"
        if gcloud compute backend-services describe "$backend_service" --global >/dev/null 2>&1; then
            gcloud compute backend-services delete "$backend_service" --global --quiet
            log_success "Deleted backend service: $backend_service"
            ((lb_resources_removed++))
        fi
    fi
    
    # Fallback: find resources by pattern
    local lb_patterns=("demo-https-rule" "demo-https-proxy" "demo-url-map" "demo-backend")
    for pattern in "${lb_patterns[@]}"; do
        case $pattern in
            "demo-https-rule")
                local rules
                rules=$(gcloud compute forwarding-rules list --global --filter="name:${pattern}" --format="value(name)" 2>/dev/null || true)
                if [[ -n "$rules" ]]; then
                    while IFS= read -r rule; do
                        if [[ -n "$rule" ]]; then
                            gcloud compute forwarding-rules delete "$rule" --global --quiet
                            log_success "Deleted forwarding rule: $rule"
                            ((lb_resources_removed++))
                        fi
                    done <<< "$rules"
                fi
                ;;
            "demo-https-proxy")
                local proxies
                proxies=$(gcloud compute target-https-proxies list --filter="name:${pattern}" --format="value(name)" 2>/dev/null || true)
                if [[ -n "$proxies" ]]; then
                    while IFS= read -r proxy; do
                        if [[ -n "$proxy" ]]; then
                            gcloud compute target-https-proxies delete "$proxy" --global --quiet
                            log_success "Deleted HTTPS proxy: $proxy"
                            ((lb_resources_removed++))
                        fi
                    done <<< "$proxies"
                fi
                ;;
            "demo-url-map")
                local maps
                maps=$(gcloud compute url-maps list --filter="name:${pattern}" --format="value(name)" 2>/dev/null || true)
                if [[ -n "$maps" ]]; then
                    while IFS= read -r map; do
                        if [[ -n "$map" ]]; then
                            gcloud compute url-maps delete "$map" --global --quiet
                            log_success "Deleted URL map: $map"
                            ((lb_resources_removed++))
                        fi
                    done <<< "$maps"
                fi
                ;;
            "demo-backend")
                local backends
                backends=$(gcloud compute backend-services list --global --filter="name:${pattern}" --format="value(name)" 2>/dev/null || true)
                if [[ -n "$backends" ]]; then
                    while IFS= read -r backend; do
                        if [[ -n "$backend" ]]; then
                            gcloud compute backend-services delete "$backend" --global --quiet
                            log_success "Deleted backend service: $backend"
                            ((lb_resources_removed++))
                        fi
                    done <<< "$backends"
                fi
                ;;
        esac
    done
    
    if [[ $lb_resources_removed -eq 0 ]]; then
        log_info "No load balancer components found to remove"
    else
        log_success "Removed $lb_resources_removed load balancer component(s)"
    fi
}

# Function to remove certificates and certificate maps
remove_certificates() {
    log_info "Removing certificates and certificate maps..."
    
    local cert_resources_removed=0
    
    if [[ -n "${RANDOM_SUFFIX:-}" && -n "${DOMAIN_NAME:-}" ]]; then
        # Remove certificate map entries
        local cert_map="cert-map-${RANDOM_SUFFIX}"
        if gcloud certificate-manager maps entries describe "${DOMAIN_NAME}" --map="$cert_map" --global >/dev/null 2>&1; then
            gcloud certificate-manager maps entries delete "${DOMAIN_NAME}" --map="$cert_map" --global --quiet
            log_success "Deleted certificate map entry: ${DOMAIN_NAME}"
            ((cert_resources_removed++))
        fi
        
        # Remove certificate map
        if gcloud certificate-manager maps describe "$cert_map" --global >/dev/null 2>&1; then
            gcloud certificate-manager maps delete "$cert_map" --global --quiet
            log_success "Deleted certificate map: $cert_map"
            ((cert_resources_removed++))
        fi
    fi
    
    # Remove certificate
    if [[ -n "${CERT_NAME:-}" ]]; then
        if gcloud certificate-manager certificates describe "${CERT_NAME}" --global >/dev/null 2>&1; then
            gcloud certificate-manager certificates delete "${CERT_NAME}" --global --quiet
            log_success "Deleted certificate: ${CERT_NAME}"
            ((cert_resources_removed++))
        fi
    fi
    
    # Fallback: find certificates by pattern
    local cert_list
    cert_list=$(gcloud certificate-manager certificates list --global --filter="name:ssl-cert" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$cert_list" ]]; then
        while IFS= read -r cert; do
            if [[ -n "$cert" ]]; then
                gcloud certificate-manager certificates delete "$cert" --global --quiet
                log_success "Deleted certificate: $cert"
                ((cert_resources_removed++))
            fi
        done <<< "$cert_list"
    fi
    
    # Remove certificate maps by pattern
    local map_list
    map_list=$(gcloud certificate-manager maps list --global --filter="name:cert-map" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$map_list" ]]; then
        while IFS= read -r map; do
            if [[ -n "$map" ]]; then
                # First remove entries
                local entries
                entries=$(gcloud certificate-manager maps entries list --map="$map" --global --format="value(hostname)" 2>/dev/null || true)
                if [[ -n "$entries" ]]; then
                    while IFS= read -r entry; do
                        if [[ -n "$entry" ]]; then
                            gcloud certificate-manager maps entries delete "$entry" --map="$map" --global --quiet 2>/dev/null || true
                        fi
                    done <<< "$entries"
                fi
                
                # Then remove the map
                gcloud certificate-manager maps delete "$map" --global --quiet
                log_success "Deleted certificate map: $map"
                ((cert_resources_removed++))
            fi
        done <<< "$map_list"
    fi
    
    if [[ $cert_resources_removed -eq 0 ]]; then
        log_info "No certificates or certificate maps found to remove"
    else
        log_success "Removed $cert_resources_removed certificate resource(s)"
    fi
}

# Function to remove DNS zone
remove_dns_zone() {
    log_info "Removing Cloud DNS zone..."
    
    if [[ -n "${DNS_ZONE_NAME:-}" ]]; then
        if gcloud dns managed-zones describe "${DNS_ZONE_NAME}" >/dev/null 2>&1; then
            gcloud dns managed-zones delete "${DNS_ZONE_NAME}" --quiet
            log_success "Deleted DNS zone: ${DNS_ZONE_NAME}"
        else
            log_info "DNS zone ${DNS_ZONE_NAME} not found"
        fi
    else
        # Fallback: find zones by pattern
        local zone_list
        zone_list=$(gcloud dns managed-zones list --filter="name:automation-zone" --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "$zone_list" ]]; then
            while IFS= read -r zone; do
                if [[ -n "$zone" ]]; then
                    gcloud dns managed-zones delete "$zone" --quiet
                    log_success "Deleted DNS zone: $zone"
                fi
            done <<< "$zone_list"
        else
            log_info "No DNS zones found to remove"
        fi
    fi
}

# Function to remove service account
remove_service_account() {
    log_info "Removing service account..."
    
    local sa_email="cert-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$sa_email" >/dev/null 2>&1; then
        # Remove IAM policy bindings first
        local roles=(
            "roles/dns.admin"
            "roles/certificatemanager.editor"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" \
                --quiet 2>/dev/null || true
        done
        
        # Delete service account
        gcloud iam service-accounts delete "$sa_email" --quiet
        log_success "Deleted service account: $sa_email"
    else
        log_info "Service account not found: $sa_email"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_removed=0
    local files_to_remove=("nameservers.txt" "deployment_state.env")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed local file: $file"
            ((files_removed++))
        fi
    done
    
    # Remove any leftover function directories
    if [[ -d "cert-automation-function" ]]; then
        rm -rf "cert-automation-function"
        log_success "Removed function directory: cert-automation-function"
        ((files_removed++))
    fi
    
    if [[ $files_removed -eq 0 ]]; then
        log_info "No local files found to remove"
    else
        log_success "Removed $files_removed local file(s)"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=0
    
    # Check for remaining resources
    local resource_checks=(
        "gcloud scheduler jobs list --filter='name:cert-check OR name:daily-cert-audit' --format='value(name)'"
        "gcloud functions list --filter='name:cert-automation OR name:dns-update' --format='value(name)'"
        "gcloud certificate-manager certificates list --global --filter='name:ssl-cert' --format='value(name)'"
        "gcloud certificate-manager maps list --global --filter='name:cert-map' --format='value(name)'"
        "gcloud dns managed-zones list --filter='name:automation-zone' --format='value(name)'"
    )
    
    for check in "${resource_checks[@]}"; do
        local result
        result=$(eval "$check" 2>/dev/null || true)
        if [[ -n "$result" ]]; then
            log_warning "Some resources may still exist:"
            echo "$result"
            ((issues_found++))
        fi
    done
    
    if [[ $issues_found -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_warning "Some resources may still exist. Manual cleanup may be required."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup completed!"
    echo
    log_info "Resources removed:"
    log_info "  ✓ Cloud Scheduler jobs"
    log_info "  ✓ Cloud Functions"
    log_info "  ✓ Load balancer components"
    log_info "  ✓ Certificates and certificate maps"
    log_info "  ✓ DNS zones"
    log_info "  ✓ Service accounts"
    log_info "  ✓ Local files"
    echo
    log_warning "Important reminders:"
    log_warning "1. Revert nameserver changes with your domain registrar if needed"
    log_warning "2. Check your GCP billing console to verify no unexpected charges"
    log_warning "3. Review any remaining resources in your project"
    echo
    log_info "If you created a new project specifically for this deployment,"
    log_info "you may want to delete the entire project:"
    log_info "  gcloud projects delete ${PROJECT_ID}"
}

# Main cleanup function
main() {
    confirm_destruction
    load_deployment_state
    validate_prerequisites
    
    log_info "Starting resource cleanup process..."
    echo
    
    # Remove resources in reverse order of creation
    remove_scheduler_jobs
    remove_cloud_functions
    remove_load_balancer
    remove_certificates
    remove_dns_zone
    remove_service_account
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"