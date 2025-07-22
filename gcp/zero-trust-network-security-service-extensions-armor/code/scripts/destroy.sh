#!/bin/bash

# destroy.sh - Clean up Zero-Trust Network Security with Service Extensions and Cloud Armor
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

# Colors for output
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Zero-Trust Network Security infrastructure

OPTIONS:
    -p, --project       Google Cloud Project ID (required)
    -r, --region        Deployment region (default: ${DEFAULT_REGION})
    -z, --zone          Deployment zone (default: ${DEFAULT_ZONE})
    -n, --name          Application name prefix (default: auto-detect)
    --force             Skip confirmation prompts
    --dry-run           Show what would be deleted without executing
    --keep-network      Keep VPC network and subnets (useful for shared networks)
    --keep-logs         Keep log sinks and monitoring configuration
    -h, --help          Show this help message

EXAMPLES:
    $0 --project my-gcp-project
    $0 --project my-gcp-project --force
    $0 --project my-gcp-project --dry-run
    $0 --project my-gcp-project --keep-network

SAFETY FEATURES:
    - Interactive confirmation by default
    - Dry-run mode to preview deletions
    - Option to preserve shared resources
    - Detailed logging of all operations

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -n|--name)
                APP_NAME_PREFIX="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --keep-network)
                KEEP_NETWORK=true
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Initialize variables
PROJECT_ID=""
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
APP_NAME_PREFIX=""
FORCE=false
DRY_RUN=false
KEEP_NETWORK=false
KEEP_LOGS=false

# Parse arguments
parse_args "$@"

# Validate required parameters
if [[ -z "${PROJECT_ID}" ]]; then
    log_error "Project ID is required. Use --project flag."
    show_help
    exit 1
fi

# Dry run function
execute_command() {
    local cmd="$1"
    local description="${2:-}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${cmd}"
        if [[ -n "${description}" ]]; then
            log_info "[DRY RUN] Purpose: ${description}"
        fi
        return 0
    else
        log_info "Executing: ${cmd}"
        if [[ -n "${description}" ]]; then
            log_info "Purpose: ${description}"
        fi
        eval "${cmd}" || log_warning "Command failed (continuing): ${cmd}"
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed."
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error_exit "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
    fi

    log_success "Prerequisites check completed"
}

# Auto-detect resources
auto_detect_resources() {
    log_info "Auto-detecting zero-trust resources in project ${PROJECT_ID}..."

    # Try to find resources with common patterns
    local detected_apps=()
    
    # Look for forwarding rules that might be from our deployment
    while IFS= read -r rule; do
        if [[ "${rule}" =~ zero-trust-app-[a-f0-9]{6}-forwarding-rule ]]; then
            local app_name="${rule%-forwarding-rule}"
            detected_apps+=("${app_name}")
        fi
    done < <(gcloud compute forwarding-rules list --global --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null || echo "")

    # Look for backend services
    while IFS= read -r service; do
        if [[ "${service}" =~ zero-trust-app-[a-f0-9]{6}-backend-service ]]; then
            local app_name="${service%-backend-service}"
            if [[ ! " ${detected_apps[*]} " =~ " ${app_name} " ]]; then
                detected_apps+=("${app_name}")
            fi
        fi
    done < <(gcloud compute backend-services list --global --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null || echo "")

    # Look for security policies
    while IFS= read -r policy; do
        if [[ "${policy}" == "zero-trust-armor-policy" ]]; then
            SECURITY_POLICY_NAME="${policy}"
        fi
    done < <(gcloud compute security-policies list --format="value(name)" --project="${PROJECT_ID}" 2>/dev/null || echo "")

    # Look for service extensions (Cloud Run services)
    while IFS= read -r service; do
        if [[ "${service}" == "zero-trust-extension" ]]; then
            SERVICE_EXTENSION_NAME="${service}"
        fi
    done < <(gcloud run services list --region="${REGION}" --format="value(metadata.name)" --project="${PROJECT_ID}" 2>/dev/null || echo "")

    if [[ ${#detected_apps[@]} -eq 0 ]]; then
        log_warning "No zero-trust applications detected. You may need to specify --name parameter."
        if [[ -z "${APP_NAME_PREFIX}" ]]; then
            log_error "No resources found and no app name specified. Use --name parameter."
            exit 1
        fi
        APP_NAME="${APP_NAME_PREFIX}"
    else
        if [[ ${#detected_apps[@]} -gt 1 ]]; then
            log_warning "Multiple zero-trust applications detected:"
            for app in "${detected_apps[@]}"; do
                log_warning "  - ${app}"
            done
            if [[ -z "${APP_NAME_PREFIX}" ]]; then
                log_error "Multiple apps found. Use --name to specify which one to delete."
                exit 1
            fi
            APP_NAME="${APP_NAME_PREFIX}"
        else
            APP_NAME="${detected_apps[0]}"
        fi
    fi

    # Set other resource names based on detected/specified app name
    NETWORK_NAME="zero-trust-vpc"
    SUBNET_NAME="zero-trust-subnet"
    SECURITY_POLICY_NAME="${SECURITY_POLICY_NAME:-zero-trust-armor-policy}"
    SERVICE_EXTENSION_NAME="${SERVICE_EXTENSION_NAME:-zero-trust-extension}"

    log_info "Target resources:"
    log_info "  App Name: ${APP_NAME}"
    log_info "  Network: ${NETWORK_NAME}"
    log_info "  Security Policy: ${SECURITY_POLICY_NAME}"
    log_info "  Service Extension: ${SERVICE_EXTENSION_NAME}"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - Load balancer and related components"
    echo "  - Backend services and instance groups"
    echo "  - Compute instances and service accounts"
    echo "  - Cloud Armor security policies"
    echo "  - Service Extension (Cloud Run service)"
    if [[ "${KEEP_NETWORK}" != "true" ]]; then
        echo "  - VPC network and subnets"
    fi
    if [[ "${KEEP_LOGS}" != "true" ]]; then
        echo "  - Log sinks and monitoring configuration"
    fi
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Delete load balancer components
delete_load_balancer() {
    log_info "Deleting load balancer components..."

    # Delete global forwarding rule
    execute_command "gcloud compute forwarding-rules delete ${APP_NAME}-forwarding-rule \
        --global \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove global forwarding rule"

    # Delete HTTPS proxy
    execute_command "gcloud compute target-https-proxies delete ${APP_NAME}-https-proxy \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove HTTPS proxy"

    # Delete URL map
    execute_command "gcloud compute url-maps delete ${APP_NAME}-url-map \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove URL map"

    # Delete SSL certificate
    execute_command "gcloud compute ssl-certificates delete ${APP_NAME}-ssl-cert \
        --global \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove SSL certificate"

    log_success "Load balancer components deleted"
}

# Delete backend services
delete_backend_services() {
    log_info "Deleting backend services and instance groups..."

    # Delete backend service
    execute_command "gcloud compute backend-services delete ${APP_NAME}-backend-service \
        --global \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove backend service"

    # Delete instance group
    execute_command "gcloud compute instance-groups unmanaged delete ${APP_NAME}-ig \
        --zone ${ZONE} \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove instance group"

    # Delete health check
    execute_command "gcloud compute health-checks delete ${APP_NAME}-health-check \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove health check"

    log_success "Backend services deleted"
}

# Delete compute instances
delete_compute_instances() {
    log_info "Deleting compute instances and service accounts..."

    # Delete compute instance
    execute_command "gcloud compute instances delete ${APP_NAME}-backend \
        --zone ${ZONE} \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove backend compute instance"

    # Delete service account
    execute_command "gcloud iam service-accounts delete \
        ${APP_NAME}-backend@${PROJECT_ID}.iam.gserviceaccount.com \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove backend service account"

    log_success "Compute instances and service accounts deleted"
}

# Delete security policies
delete_security_policies() {
    log_info "Deleting Cloud Armor security policies..."

    # Delete Cloud Armor security policy
    execute_command "gcloud compute security-policies delete ${SECURITY_POLICY_NAME} \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove Cloud Armor security policy"

    log_success "Security policies deleted"
}

# Delete service extensions
delete_service_extensions() {
    log_info "Deleting Service Extensions..."

    # Delete Cloud Run service
    execute_command "gcloud run services delete ${SERVICE_EXTENSION_NAME} \
        --region ${REGION} \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove Service Extension Cloud Run service"

    log_success "Service Extensions deleted"
}

# Delete network resources
delete_network_resources() {
    if [[ "${KEEP_NETWORK}" == "true" ]]; then
        log_info "Skipping network deletion (--keep-network flag)"
        return 0
    fi

    log_info "Deleting network resources..."

    # Delete firewall rules
    execute_command "gcloud compute firewall-rules delete ${APP_NAME}-allow-iap \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove IAP firewall rule"

    execute_command "gcloud compute firewall-rules delete ${APP_NAME}-allow-health-check \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove health check firewall rule"

    # Delete subnet
    execute_command "gcloud compute networks subnets delete ${SUBNET_NAME} \
        --region ${REGION} \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove subnet"

    # Delete VPC network
    execute_command "gcloud compute networks delete ${NETWORK_NAME} \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove VPC network"

    log_success "Network resources deleted"
}

# Delete monitoring and logging
delete_monitoring() {
    if [[ "${KEEP_LOGS}" == "true" ]]; then
        log_info "Skipping monitoring deletion (--keep-logs flag)"
        return 0
    fi

    log_info "Deleting monitoring and logging resources..."

    # Delete log sink
    execute_command "gcloud logging sinks delete zero-trust-security-sink \
        --quiet \
        --project=${PROJECT_ID}" \
        "Remove security log sink"

    # Delete storage bucket if it was created for logs
    execute_command "gsutil rm -r gs://${PROJECT_ID}-security-logs || true" \
        "Remove security logs storage bucket"

    log_success "Monitoring and logging resources deleted"
}

# Verify cleanup
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed. No resources were actually deleted."
        return 0
    fi

    log_info "Verifying cleanup completion..."

    local remaining_resources=()

    # Check for remaining forwarding rules
    if gcloud compute forwarding-rules describe "${APP_NAME}-forwarding-rule" --global --project="${PROJECT_ID}" &>/dev/null; then
        remaining_resources+=("Forwarding rule: ${APP_NAME}-forwarding-rule")
    fi

    # Check for remaining backend services
    if gcloud compute backend-services describe "${APP_NAME}-backend-service" --global --project="${PROJECT_ID}" &>/dev/null; then
        remaining_resources+=("Backend service: ${APP_NAME}-backend-service")
    fi

    # Check for remaining instances
    if gcloud compute instances describe "${APP_NAME}-backend" --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
        remaining_resources+=("Compute instance: ${APP_NAME}-backend")
    fi

    # Check for remaining security policies
    if gcloud compute security-policies describe "${SECURITY_POLICY_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
        remaining_resources+=("Security policy: ${SECURITY_POLICY_NAME}")
    fi

    # Check for remaining Cloud Run services
    if gcloud run services describe "${SERVICE_EXTENSION_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
        remaining_resources+=("Cloud Run service: ${SERVICE_EXTENSION_NAME}")
    fi

    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        log_warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            log_warning "  - ${resource}"
        done
        log_warning "You may need to delete these manually or run the script again."
    else
        log_success "All zero-trust resources have been successfully removed!"
    fi
}

# Display cleanup summary
cleanup_summary() {
    log_info "Cleanup operation completed"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "App Name: ${APP_NAME}"
    if [[ "${KEEP_NETWORK}" == "true" ]]; then
        echo "Network: Preserved (--keep-network)"
    else
        echo "Network: Deleted"
    fi
    if [[ "${KEEP_LOGS}" == "true" ]]; then
        echo "Monitoring: Preserved (--keep-logs)"
    else
        echo "Monitoring: Deleted"
    fi
    echo "Timestamp: $(date)"
    echo
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo "All specified zero-trust network security resources have been removed."
        echo "Verify in the Google Cloud Console that all resources are deleted."
    else
        echo "This was a dry run. No resources were actually deleted."
        echo "Remove --dry-run flag to perform actual deletion."
    fi
}

# Main execution
main() {
    log_info "Starting Zero-Trust Network Security cleanup..."
    log_info "Timestamp: $(date)"

    check_prerequisites
    auto_detect_resources
    confirm_deletion

    # Delete resources in reverse order of creation
    delete_load_balancer
    delete_backend_services
    delete_compute_instances
    delete_security_policies
    delete_service_extensions
    delete_network_resources
    delete_monitoring

    verify_cleanup
    cleanup_summary

    log_success "Cleanup completed successfully!"
}

# Execute main function
main "$@"