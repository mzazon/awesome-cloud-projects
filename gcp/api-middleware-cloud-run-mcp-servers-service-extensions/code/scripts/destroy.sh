#!/bin/bash

# Destroy script for API Middleware with Cloud Run MCP Servers and Service Extensions
# This script safely removes all resources created by the deploy.sh script
# Includes confirmation prompts and handles resource dependencies properly

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

# Configuration and defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_INFO_FILE="$SCRIPT_DIR/deployment-info.env"
FORCE_DELETE=false
DELETE_PROJECT=false
DRY_RUN=false
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --force           Skip confirmation prompts"
            echo "  --delete-project  Also delete the Google Cloud project"
            echo "  --dry-run        Show what would be deleted without executing"
            echo "  --quiet          Minimal output"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_warning "No deployment info file found at: $DEPLOYMENT_INFO_FILE"
        log_warning "Attempting to discover resources automatically..."
        return 1
    fi
    
    # Source the deployment info
    source "$DEPLOYMENT_INFO_FILE"
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in deployment info"
        return 1
    fi
    
    log_success "Loaded deployment info for project: $PROJECT_ID"
    return 0
}

# Discover resources automatically if deployment info is missing
discover_resources() {
    log_info "Attempting to discover MCP middleware resources..."
    
    # Get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No current project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    log_info "Discovering resources in project: $PROJECT_ID"
    log_info "Using region: $REGION"
    
    # Try to find MCP services by common naming patterns
    MCP_SERVICE_PREFIX=""
    MIDDLEWARE_SERVICE=""
    ENDPOINTS_CONFIG=""
    
    # Find Cloud Run services with MCP pattern
    local mcp_services
    mcp_services=$(gcloud run services list --region="$REGION" --format="value(metadata.name)" --filter="metadata.name~'mcp-server-'" 2>/dev/null || echo "")
    
    if [[ -n "$mcp_services" ]]; then
        # Extract prefix from first service
        local first_service
        first_service=$(echo "$mcp_services" | head -n1)
        MCP_SERVICE_PREFIX=$(echo "$first_service" | sed 's/-content-analyzer$//' | sed 's/-request-router$//' | sed 's/-response-enhancer$//')
        log_info "Discovered MCP service prefix: $MCP_SERVICE_PREFIX"
    fi
    
    # Find middleware service
    local middleware_services
    middleware_services=$(gcloud run services list --region="$REGION" --format="value(metadata.name)" --filter="metadata.name~'api-middleware-'" 2>/dev/null || echo "")
    
    if [[ -n "$middleware_services" ]]; then
        MIDDLEWARE_SERVICE=$(echo "$middleware_services" | head -n1)
        log_info "Discovered middleware service: $MIDDLEWARE_SERVICE"
    fi
    
    # Find endpoints configuration
    local endpoints_services
    endpoints_services=$(gcloud endpoints services list --format="value(serviceName)" --filter="serviceName~'endpoints-config-.*\.endpoints\.'" 2>/dev/null || echo "")
    
    if [[ -n "$endpoints_services" ]]; then
        local full_endpoint
        full_endpoint=$(echo "$endpoints_services" | head -n1)
        ENDPOINTS_CONFIG=$(echo "$full_endpoint" | sed "s/\.endpoints\.${PROJECT_ID}\.cloud\.goog$//" )
        log_info "Discovered endpoints config: $ENDPOINTS_CONFIG"
    fi
}

# Display resources to be deleted
display_resources() {
    echo
    log_info "=== Resources to be deleted ==="
    echo "Project ID: ${PROJECT_ID:-'Not set'}"
    echo "Region: ${REGION:-'Not set'}"
    
    if [[ -n "${MCP_SERVICE_PREFIX:-}" ]]; then
        echo "MCP Services:"
        echo "  - ${MCP_SERVICE_PREFIX}-content-analyzer"
        echo "  - ${MCP_SERVICE_PREFIX}-request-router"
        echo "  - ${MCP_SERVICE_PREFIX}-response-enhancer"
    else
        echo "MCP Services: None discovered"
    fi
    
    if [[ -n "${MIDDLEWARE_SERVICE:-}" ]]; then
        echo "Middleware Service: ${MIDDLEWARE_SERVICE}"
    else
        echo "Middleware Service: None discovered"
    fi
    
    if [[ -n "${ENDPOINTS_CONFIG:-}" ]]; then
        echo "Cloud Endpoints: ${ENDPOINTS_CONFIG}.endpoints.${PROJECT_ID}.cloud.goog"
    else
        echo "Cloud Endpoints: None discovered"
    fi
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "⚠️  PROJECT DELETION: The entire project will be deleted!"
    fi
    echo
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will permanently delete the above resources.${NC}"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo -e "${RED}⚠️  PROJECT DELETION WARNING: This will delete the ENTIRE project and ALL its resources!${NC}"
        echo -e "${RED}⚠️  This action is IRREVERSIBLE!${NC}"
    fi
    
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo
        echo -e "${RED}FINAL WARNING: About to delete project ${PROJECT_ID}${NC}"
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Deletion cancelled."
            exit 1
        fi
    fi
}

# Delete Cloud Endpoints service
delete_endpoints() {
    if [[ -z "${ENDPOINTS_CONFIG:-}" ]]; then
        log_info "No endpoints configuration to delete"
        return 0
    fi
    
    local endpoint_service="${ENDPOINTS_CONFIG}.endpoints.${PROJECT_ID}.cloud.goog"
    
    log_info "Deleting Cloud Endpoints service: $endpoint_service"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete: $endpoint_service"
        return 0
    fi
    
    if gcloud endpoints services describe "$endpoint_service" &>/dev/null; then
        if gcloud endpoints services delete "$endpoint_service" --quiet; then
            log_success "Deleted Cloud Endpoints service: $endpoint_service"
        else
            log_warning "Failed to delete Cloud Endpoints service: $endpoint_service"
        fi
    else
        log_info "Cloud Endpoints service not found: $endpoint_service"
    fi
}

# Delete Cloud Run services
delete_cloud_run_services() {
    log_info "Deleting Cloud Run services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Run services"
        return 0
    fi
    
    local services_to_delete=()
    
    # Add MCP services if prefix is known
    if [[ -n "${MCP_SERVICE_PREFIX:-}" ]]; then
        services_to_delete+=(
            "${MCP_SERVICE_PREFIX}-content-analyzer"
            "${MCP_SERVICE_PREFIX}-request-router"
            "${MCP_SERVICE_PREFIX}-response-enhancer"
        )
    fi
    
    # Add middleware service if known
    if [[ -n "${MIDDLEWARE_SERVICE:-}" ]]; then
        services_to_delete+=("$MIDDLEWARE_SERVICE")
    fi
    
    # If no specific services found, try to find all MCP-related services
    if [[ ${#services_to_delete[@]} -eq 0 ]]; then
        log_info "No specific services configured, searching for MCP-related services..."
        
        local discovered_services
        discovered_services=$(gcloud run services list --region="$REGION" --format="value(metadata.name)" \
            --filter="metadata.name~'mcp-server-' OR metadata.name~'api-middleware-'" 2>/dev/null || echo "")
        
        if [[ -n "$discovered_services" ]]; then
            while IFS= read -r service; do
                services_to_delete+=("$service")
            done <<< "$discovered_services"
        fi
    fi
    
    # Delete each service
    for service in "${services_to_delete[@]}"; do
        if [[ -n "$service" ]]; then
            log_info "Deleting Cloud Run service: $service"
            
            if gcloud run services describe "$service" --region="$REGION" &>/dev/null; then
                if gcloud run services delete "$service" --region="$REGION" --quiet; then
                    log_success "Deleted Cloud Run service: $service"
                else
                    log_warning "Failed to delete Cloud Run service: $service"
                fi
            else
                log_info "Cloud Run service not found: $service"
            fi
        fi
    done
    
    if [[ ${#services_to_delete[@]} -eq 0 ]]; then
        log_info "No Cloud Run services found to delete"
    fi
}

# Delete container images from Artifact Registry
delete_container_images() {
    log_info "Checking for container images in Artifact Registry..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would check and delete container images"
        return 0
    fi
    
    # List all repositories in the region
    local repositories
    repositories=$(gcloud artifacts repositories list --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$repositories" ]]; then
        log_info "No Artifact Registry repositories found"
        return 0
    fi
    
    # Check each repository for MCP-related images
    while IFS= read -r repo; do
        if [[ -n "$repo" ]]; then
            local repo_name
            repo_name=$(basename "$repo")
            
            log_info "Checking repository: $repo_name"
            
            # List images in the repository
            local images
            images=$(gcloud artifacts docker images list "$REGION-docker.pkg.dev/$PROJECT_ID/$repo_name" \
                --format="value(image)" --filter="image~'mcp-server-' OR image~'api-middleware-'" 2>/dev/null || echo "")
            
            if [[ -n "$images" ]]; then
                log_info "Found MCP-related images in repository: $repo_name"
                while IFS= read -r image; do
                    if [[ -n "$image" ]]; then
                        log_info "Deleting container image: $image"
                        if gcloud artifacts docker images delete "$image" --delete-tags --quiet; then
                            log_success "Deleted container image: $image"
                        else
                            log_warning "Failed to delete container image: $image"
                        fi
                    fi
                done <<< "$images"
            fi
        fi
    done <<< "$repositories"
}

# Clean up temporary files and local state
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove deployment info file
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Removed deployment info file"
    fi
    
    # Remove any temporary files that might exist
    rm -f /tmp/mcp-urls-* /tmp/openapi-*.yaml 2>/dev/null || true
    
    # Clean up any temporary directories
    rm -rf /tmp/mcp-middleware-* 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Delete the entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log_info "Deleting entire project: $PROJECT_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        return 0
    fi
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deleted: $PROJECT_ID"
        log_info "Note: Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project: $PROJECT_ID"
        exit 1
    fi
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DELETE_PROJECT" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    # Check for remaining Cloud Run services
    local remaining_services
    remaining_services=$(gcloud run services list --region="$REGION" --format="value(metadata.name)" \
        --filter="metadata.name~'mcp-server-' OR metadata.name~'api-middleware-'" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_services" ]]; then
        log_warning "Some Cloud Run services may still exist:"
        echo "$remaining_services"
    else
        log_success "No MCP-related Cloud Run services found"
    fi
    
    # Check for remaining endpoints
    local remaining_endpoints
    remaining_endpoints=$(gcloud endpoints services list --format="value(serviceName)" \
        --filter="serviceName~'endpoints-config-.*\.endpoints\.'" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_endpoints" ]]; then
        log_warning "Some endpoints services may still exist:"
        echo "$remaining_endpoints"
    else
        log_success "No MCP-related endpoints services found"
    fi
}

# Display cleanup summary
display_summary() {
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== Dry Run Summary ==="
        log_info "No resources were actually deleted (dry run mode)"
    elif [[ "$DELETE_PROJECT" == "true" ]]; then
        log_success "=== Cleanup Summary ==="
        log_success "Project $PROJECT_ID has been scheduled for deletion"
        log_info "All resources in the project will be permanently removed"
    else
        log_success "=== Cleanup Summary ==="
        log_success "API Middleware MCP resources have been removed"
        log_info "Project $PROJECT_ID has been preserved"
    fi
    
    if [[ "$QUIET" != "true" ]]; then
        echo
        log_info "Cleanup completed at: $(date)"
    fi
}

# Main cleanup function
main() {
    if [[ "$QUIET" != "true" ]]; then
        log_info "Starting API Middleware MCP cleanup..."
    fi
    
    # Load deployment info or discover resources
    if ! load_deployment_info; then
        discover_resources
    fi
    
    # Display resources and confirm deletion
    if [[ "$DRY_RUN" != "true" && "$QUIET" != "true" ]]; then
        display_resources
        confirm_deletion
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE ==="
        display_resources
    fi
    
    # Perform cleanup in the correct order
    delete_endpoints
    delete_cloud_run_services
    delete_container_images
    cleanup_local_files
    delete_project
    
    # Verify and summarize
    verify_cleanup
    display_summary
    
    if [[ "$QUIET" != "true" ]]; then
        log_success "API Middleware MCP cleanup completed!"
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi