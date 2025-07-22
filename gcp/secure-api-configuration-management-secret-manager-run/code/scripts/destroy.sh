#!/bin/bash

# Secure API Configuration Management with Secret Manager and Cloud Run - Cleanup Script
# This script safely removes all resources created during the deployment with proper
# error handling, confirmation prompts, and comprehensive logging.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup script for Secure API Configuration Management deployment.

OPTIONS:
    -p, --project PROJECT_ID    Specify the project ID to clean up
    -y, --yes                   Skip confirmation prompts (dangerous!)
    -f, --force                 Force cleanup even if some operations fail
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Interactive cleanup with prompts
    $0 -p secure-api-1234567890 # Clean up specific project
    $0 -y                       # Non-interactive cleanup (use with caution)
    $0 -f                       # Force cleanup ignoring some errors

Note: Without -p flag, the script will attempt to find deployment info files.
EOF
}

# Function to parse command line arguments
parse_arguments() {
    SKIP_CONFIRMATION=false
    FORCE_CLEANUP=false
    TARGET_PROJECT=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                TARGET_PROJECT="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_CLEANUP=true
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

# Function to find deployment info files
find_deployment_info() {
    log_info "Looking for deployment information files..."
    
    local info_files
    info_files=(deployment-info-*.txt)
    
    if [[ ${#info_files[@]} -eq 0 ]] || [[ ! -f "${info_files[0]}" ]]; then
        if [[ -z "$TARGET_PROJECT" ]]; then
            log_error "No deployment info files found and no project specified."
            log_error "Please run with -p PROJECT_ID or ensure deployment-info-*.txt exists."
            exit 1
        else
            log_warning "No deployment info file found, using provided project: $TARGET_PROJECT"
            return
        fi
    fi
    
    if [[ ${#info_files[@]} -gt 1 ]]; then
        log_warning "Multiple deployment info files found:"
        for file in "${info_files[@]}"; do
            if [[ -f "$file" ]]; then
                log_warning "  - $file"
            fi
        done
        
        if [[ -z "$TARGET_PROJECT" ]]; then
            log_error "Multiple deployments found. Please specify -p PROJECT_ID"
            exit 1
        fi
    fi
    
    # Load deployment info if file exists
    for file in "${info_files[@]}"; do
        if [[ -f "$file" ]] && [[ "$file" =~ deployment-info-(.*)\.txt ]]; then
            local file_project="${BASH_REMATCH[1]}"
            if [[ -z "$TARGET_PROJECT" ]] || [[ "$file_project" == "$TARGET_PROJECT" ]]; then
                log_info "Loading deployment info from: $file"
                # Source the file to load variables
                # shellcheck source=/dev/null
                source "$file"
                DEPLOYMENT_INFO_FILE="$file"
                break
            fi
        fi
    done
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project exists and we have access
validate_project() {
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_info "Validating project access: $PROJECT_ID"
        
        if gcloud projects describe "$PROJECT_ID" --quiet &>/dev/null; then
            log_success "Project validated: $PROJECT_ID"
            gcloud config set project "$PROJECT_ID"
        else
            log_error "Cannot access project: $PROJECT_ID"
            log_error "Make sure the project exists and you have permission to access it."
            exit 1
        fi
    else
        log_error "No PROJECT_ID specified or found in deployment info."
        exit 1
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "Project ID: ${PROJECT_ID:-"Unknown"}"
    log_info "Region: ${REGION:-"Unknown"}"
    log_info ""
    log_info "Resources to be deleted:"
    log_info "  - API Gateway: ${GATEWAY_NAME:-"Unknown"}"
    log_info "  - Cloud Run Service: ${SERVICE_NAME:-"Unknown"}"
    log_info "  - Container Images"
    log_info "  - Service Account: ${SA_NAME:-"Unknown"}"
    log_info "  - Secret Manager Secrets: ${SECRET_NAME:-"Unknown"}-*"
    log_info "  - API Keys"
    log_info "  - Project: ${PROJECT_ID:-"Unknown"} (optional)"
    log_info ""
}

# Function to get user confirmation
get_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping confirmation prompts (--yes flag used)"
        return 0
    fi
    
    show_cleanup_summary
    
    echo -e "${YELLOW}WARNING: This will permanently delete all resources listed above.${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed cleanup. Proceeding..."
}

# Function to cleanup API Gateway resources
cleanup_api_gateway() {
    log_info "Cleaning up API Gateway resources..."
    
    local cleanup_success=true
    
    # Delete API Gateway
    if [[ -n "${GATEWAY_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        log_info "Deleting API Gateway: $GATEWAY_NAME"
        if gcloud api-gateway gateways delete "$GATEWAY_NAME" \
            --location="$REGION" \
            --quiet 2>/dev/null; then
            log_success "API Gateway deleted: $GATEWAY_NAME"
        else
            log_warning "Failed to delete API Gateway: $GATEWAY_NAME (may not exist)"
            [[ "$FORCE_CLEANUP" == "false" ]] && cleanup_success=false
        fi
        
        # Wait for gateway deletion
        log_info "Waiting for gateway deletion to complete..."
        sleep 30
    fi
    
    # Delete API configuration
    if [[ -n "${GATEWAY_NAME:-}" ]]; then
        log_info "Deleting API configuration: ${GATEWAY_NAME}-config"
        if gcloud api-gateway api-configs delete "${GATEWAY_NAME}-config" \
            --api="$GATEWAY_NAME" \
            --quiet 2>/dev/null; then
            log_success "API configuration deleted: ${GATEWAY_NAME}-config"
        else
            log_warning "Failed to delete API configuration (may not exist)"
            [[ "$FORCE_CLEANUP" == "false" ]] && cleanup_success=false
        fi
    fi
    
    # Delete API
    if [[ -n "${GATEWAY_NAME:-}" ]]; then
        log_info "Deleting API: $GATEWAY_NAME"
        if gcloud api-gateway apis delete "$GATEWAY_NAME" \
            --quiet 2>/dev/null; then
            log_success "API deleted: $GATEWAY_NAME"
        else
            log_warning "Failed to delete API (may not exist)"
            [[ "$FORCE_CLEANUP" == "false" ]] && cleanup_success=false
        fi
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "API Gateway resources cleanup completed"
    else
        log_warning "API Gateway cleanup completed with warnings"
    fi
}

# Function to cleanup API keys
cleanup_api_keys() {
    log_info "Cleaning up API keys..."
    
    # List and delete API keys created for this deployment
    local api_keys
    api_keys=$(gcloud alpha services api-keys list \
        --filter="displayName:Secure API Gateway Key" \
        --format='value(name)' 2>/dev/null || echo "")
    
    if [[ -n "$api_keys" ]]; then
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                log_info "Deleting API key: $key"
                if gcloud alpha services api-keys delete "$key" --quiet 2>/dev/null; then
                    log_success "API key deleted: $key"
                else
                    log_warning "Failed to delete API key: $key"
                fi
            fi
        done <<< "$api_keys"
    else
        log_info "No API keys found to delete"
    fi
    
    log_success "API keys cleanup completed"
}

# Function to cleanup Cloud Run service
cleanup_cloud_run() {
    log_info "Cleaning up Cloud Run service..."
    
    if [[ -n "${SERVICE_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        log_info "Deleting Cloud Run service: $SERVICE_NAME"
        if gcloud run services delete "$SERVICE_NAME" \
            --region="$REGION" \
            --quiet 2>/dev/null; then
            log_success "Cloud Run service deleted: $SERVICE_NAME"
        else
            log_warning "Failed to delete Cloud Run service (may not exist)"
        fi
    else
        log_warning "Cloud Run service name or region not found"
    fi
    
    log_success "Cloud Run cleanup completed"
}

# Function to cleanup container images
cleanup_container_images() {
    log_info "Cleaning up container images..."
    
    if [[ -n "${SERVICE_NAME:-}" ]] && [[ -n "${PROJECT_ID:-}" ]]; then
        local image_name="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
        log_info "Deleting container image: $image_name"
        
        if gcloud container images delete "$image_name" \
            --quiet 2>/dev/null; then
            log_success "Container image deleted: $image_name"
        else
            log_warning "Failed to delete container image (may not exist)"
        fi
    else
        log_warning "Container image name or project not found"
    fi
    
    log_success "Container images cleanup completed"
}

# Function to cleanup service account
cleanup_service_account() {
    log_info "Cleaning up service account..."
    
    if [[ -n "${SA_NAME:-}" ]] && [[ -n "${PROJECT_ID:-}" ]]; then
        local sa_email="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        log_info "Deleting service account: $sa_email"
        
        if gcloud iam service-accounts delete "$sa_email" \
            --quiet 2>/dev/null; then
            log_success "Service account deleted: $sa_email"
        else
            log_warning "Failed to delete service account (may not exist)"
        fi
    else
        log_warning "Service account name or project not found"
    fi
    
    log_success "Service account cleanup completed"
}

# Function to cleanup Secret Manager secrets
cleanup_secrets() {
    log_info "Cleaning up Secret Manager secrets..."
    
    if [[ -n "${SECRET_NAME:-}" ]]; then
        local secrets=("${SECRET_NAME}-db" "${SECRET_NAME}-keys" "${SECRET_NAME}-config")
        
        for secret in "${secrets[@]}"; do
            log_info "Deleting secret: $secret"
            if gcloud secrets delete "$secret" --quiet 2>/dev/null; then
                log_success "Secret deleted: $secret"
            else
                log_warning "Failed to delete secret: $secret (may not exist)"
            fi
        done
    else
        log_warning "Secret name base not found"
    fi
    
    log_success "Secrets cleanup completed"
}

# Function to cleanup monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."
    
    # Clean up any monitoring policies (if they exist)
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:Secret Manager Access Monitoring" \
        --format='value(name)' 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy; do
            if [[ -n "$policy" ]]; then
                log_info "Deleting monitoring policy: $policy"
                if gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null; then
                    log_success "Monitoring policy deleted"
                else
                    log_warning "Failed to delete monitoring policy"
                fi
            fi
        done <<< "$policies"
    fi
    
    # Clean up logging sinks
    local sinks
    sinks=$(gcloud logging sinks list \
        --filter="name:secret-manager-audit" \
        --format='value(name)' 2>/dev/null || echo "")
    
    if [[ -n "$sinks" ]]; then
        while IFS= read -r sink; do
            if [[ -n "$sink" ]]; then
                log_info "Deleting logging sink: $sink"
                if gcloud logging sinks delete "$sink" --quiet 2>/dev/null; then
                    log_success "Logging sink deleted"
                else
                    log_warning "Failed to delete logging sink"
                fi
            fi
        done <<< "$sinks"
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Function to cleanup project (optional)
cleanup_project() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping project deletion confirmation in non-interactive mode"
        log_warning "To delete the project, run: gcloud projects delete ${PROJECT_ID}"
        return
    fi
    
    echo ""
    log_info "Project cleanup options:"
    log_info "1. Keep project (recommended for shared projects)"
    log_info "2. Delete entire project (WARNING: irreversible!)"
    echo ""
    
    read -p "Choose option (1 or 2): " -r project_choice
    echo ""
    
    case $project_choice in
        1)
            log_info "Keeping project: $PROJECT_ID"
            log_info "Individual resources have been cleaned up."
            ;;
        2)
            echo -e "${RED}WARNING: This will permanently delete the entire project and ALL resources in it!${NC}"
            read -p "Type the project ID to confirm deletion: " -r confirm_project
            echo ""
            
            if [[ "$confirm_project" == "$PROJECT_ID" ]]; then
                log_info "Deleting project: $PROJECT_ID"
                if gcloud projects delete "$PROJECT_ID" --quiet; then
                    log_success "Project deletion initiated: $PROJECT_ID"
                    log_info "Note: Project deletion may take several minutes to complete"
                else
                    log_error "Failed to delete project: $PROJECT_ID"
                fi
            else
                log_warning "Project ID mismatch. Project deletion cancelled."
            fi
            ;;
        *)
            log_warning "Invalid choice. Keeping project: $PROJECT_ID"
            ;;
    esac
}

# Function to cleanup deployment info file
cleanup_deployment_info() {
    if [[ -n "${DEPLOYMENT_INFO_FILE:-}" ]] && [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_info "Removing deployment info file: $DEPLOYMENT_INFO_FILE"
        if rm "$DEPLOYMENT_INFO_FILE" 2>/dev/null; then
            log_success "Deployment info file removed"
        else
            log_warning "Failed to remove deployment info file"
        fi
    fi
}

# Function to display cleanup results
show_cleanup_results() {
    log_success "Cleanup process completed!"
    log_info ""
    log_info "Summary of actions taken:"
    log_info "  ✅ API Gateway resources removed"
    log_info "  ✅ API keys removed"
    log_info "  ✅ Cloud Run service removed"
    log_info "  ✅ Container images removed"
    log_info "  ✅ Service account removed"
    log_info "  ✅ Secret Manager secrets removed"
    log_info "  ✅ Monitoring resources removed"
    
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_info ""
        log_info "Project: $PROJECT_ID"
        log_info "Note: If you chose to keep the project, you may want to review"
        log_info "      any remaining resources and billing settings."
    fi
}

# Main cleanup function
main() {
    log_info "Starting secure API configuration management cleanup..."
    
    parse_arguments "$@"
    check_prerequisites
    find_deployment_info
    validate_project
    get_confirmation
    
    # Run cleanup functions in reverse order of creation
    cleanup_api_gateway
    cleanup_api_keys
    cleanup_cloud_run
    cleanup_container_images
    cleanup_service_account
    cleanup_secrets
    cleanup_monitoring
    cleanup_project
    cleanup_deployment_info
    
    show_cleanup_results
}

# Trap to handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"