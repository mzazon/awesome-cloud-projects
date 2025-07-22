#!/bin/bash

# Destroy script for Load Balancer Traffic Routing with Service Extensions and BigQuery Data Canvas
# Recipe: load-balancer-traffic-routing-service-extensions-bigquery-data-canvas
# Provider: GCP

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log_info "Starting cleanup at $(date)"
log_info "Log file: $LOG_FILE"

# Function to prompt for confirmation
confirm_destruction() {
    local resource_type="$1"
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        echo -e "${YELLOW}WARNING:${NC} This will permanently delete ${resource_type}!"
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled by user"
            exit 0
        fi
    fi
}

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    # Try to load from deployment-info.txt
    if [[ -f "${SCRIPT_DIR}/deployment-info.txt" ]]; then
        log_info "Loading configuration from deployment-info.txt..."
        
        # Extract values from deployment file
        export PROJECT_ID=$(grep "Project ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f3)
        export REGION=$(grep "Region:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f2)
        RANDOM_SUFFIX=$(grep "Random Suffix:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f3)
        
        if [[ -n "$PROJECT_ID" && -n "$REGION" && -n "$RANDOM_SUFFIX" ]]; then
            export DATASET_NAME="traffic_analytics_${RANDOM_SUFFIX}"
            export EXTENSION_NAME="intelligent-router-${RANDOM_SUFFIX}"
            
            log_success "Configuration loaded from deployment file"
            log_info "  Project ID: ${PROJECT_ID}"
            log_info "  Region: ${REGION}"
            log_info "  Random Suffix: ${RANDOM_SUFFIX}"
        else
            log_warning "Failed to parse deployment-info.txt completely"
        fi
    fi
    
    # Fallback to environment variables or prompts
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
        if [[ -z "$PROJECT_ID" ]]; then
            read -p "Enter Project ID: " PROJECT_ID
        fi
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo 'us-central1')}"
        export REGION
    fi
    
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_warning "Random suffix not found. Will attempt to find resources by pattern."
        RANDOM_SUFFIX="*"
    fi
    
    export DATASET_NAME="${DATASET_NAME:-traffic_analytics_${RANDOM_SUFFIX}}"
    export EXTENSION_NAME="${EXTENSION_NAME:-intelligent-router-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    
    log_info "Using configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Dataset: ${DATASET_NAME}"
}

# Find resources by pattern if exact names are unknown
find_resources_by_pattern() {
    log_info "Discovering resources..."
    
    # Find Cloud Run services
    CLOUD_RUN_SERVICES=($(gcloud run services list --region="${REGION}" --format="value(metadata.name)" --filter="metadata.name~service-[abc]-.*" 2>/dev/null || echo ""))
    
    # Find load balancer components
    FORWARDING_RULES=($(gcloud compute forwarding-rules list --global --format="value(name)" --filter="name~intelligent-lb-rule-.*" 2>/dev/null || echo ""))
    HTTP_PROXIES=($(gcloud compute target-http-proxies list --format="value(name)" --filter="name~intelligent-proxy-.*" 2>/dev/null || echo ""))
    URL_MAPS=($(gcloud compute url-maps list --format="value(name)" --filter="name~intelligent-lb-.*" 2>/dev/null || echo ""))
    
    # Find backend services
    BACKEND_SERVICES=($(gcloud compute backend-services list --global --format="value(name)" --filter="name~service-[abc]-backend-.*" 2>/dev/null || echo ""))
    
    # Find health checks
    HEALTH_CHECKS=($(gcloud compute health-checks list --format="value(name)" --filter="name~cr-health-check-.*" 2>/dev/null || echo ""))
    
    # Find Network Endpoint Groups
    NEGS=($(gcloud compute network-endpoint-groups list --format="value(name)" --filter="name~service-[abc]-neg-.*" 2>/dev/null || echo ""))
    
    # Find Cloud Functions
    CLOUD_FUNCTIONS=($(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name~traffic-router-.*" 2>/dev/null || echo ""))
    
    # Find Service Extensions
    SERVICE_EXTENSIONS=($(gcloud service-extensions extensions list --location="${REGION}" --format="value(name)" --filter="name~intelligent-router-.*" 2>/dev/null || echo ""))
    
    # Find Workflows
    WORKFLOWS=($(gcloud workflows list --location="${REGION}" --format="value(name)" --filter="name~analytics-processor-.*" 2>/dev/null || echo ""))
    
    # Find BigQuery datasets
    BQ_DATASETS=($(bq ls --format=csv --max_results=1000 | grep "traffic_analytics_" | cut -d',' -f1 | tr -d '"' 2>/dev/null || echo ""))
    
    # Find logging sinks
    LOGGING_SINKS=($(gcloud logging sinks list --format="value(name)" --filter="name~traffic-analytics-sink-.*" 2>/dev/null || echo ""))
    
    log_info "Found resources to clean up:"
    [[ ${#CLOUD_RUN_SERVICES[@]} -gt 0 && -n "${CLOUD_RUN_SERVICES[0]}" ]] && log_info "  Cloud Run Services: ${#CLOUD_RUN_SERVICES[@]}"
    [[ ${#FORWARDING_RULES[@]} -gt 0 && -n "${FORWARDING_RULES[0]}" ]] && log_info "  Forwarding Rules: ${#FORWARDING_RULES[@]}"
    [[ ${#BACKEND_SERVICES[@]} -gt 0 && -n "${BACKEND_SERVICES[0]}" ]] && log_info "  Backend Services: ${#BACKEND_SERVICES[@]}"
    [[ ${#CLOUD_FUNCTIONS[@]} -gt 0 && -n "${CLOUD_FUNCTIONS[0]}" ]] && log_info "  Cloud Functions: ${#CLOUD_FUNCTIONS[@]}"
    [[ ${#BQ_DATASETS[@]} -gt 0 && -n "${BQ_DATASETS[0]}" ]] && log_info "  BigQuery Datasets: ${#BQ_DATASETS[@]}"
}

# Stop any running traffic generation
stop_traffic_generation() {
    log_info "Stopping any running traffic generation..."
    
    # Kill any running generate_traffic.sh processes
    pkill -f "generate_traffic.sh" 2>/dev/null || true
    
    log_success "Traffic generation stopped"
}

# Remove load balancer components
remove_load_balancer() {
    log_info "Removing load balancer components..."
    
    # Delete forwarding rules
    for rule in "${FORWARDING_RULES[@]}"; do
        if [[ -n "$rule" ]]; then
            log_info "Deleting forwarding rule: $rule"
            gcloud compute forwarding-rules delete "$rule" --global --quiet 2>/dev/null || log_warning "Failed to delete forwarding rule: $rule"
        fi
    done
    
    # Delete HTTP proxies
    for proxy in "${HTTP_PROXIES[@]}"; do
        if [[ -n "$proxy" ]]; then
            log_info "Deleting HTTP proxy: $proxy"
            gcloud compute target-http-proxies delete "$proxy" --quiet 2>/dev/null || log_warning "Failed to delete HTTP proxy: $proxy"
        fi
    done
    
    # Delete URL maps
    for urlmap in "${URL_MAPS[@]}"; do
        if [[ -n "$urlmap" ]]; then
            log_info "Deleting URL map: $urlmap"
            gcloud compute url-maps delete "$urlmap" --quiet 2>/dev/null || log_warning "Failed to delete URL map: $urlmap"
        fi
    done
    
    log_success "Load balancer components removed"
}

# Remove Service Extensions
remove_service_extensions() {
    log_info "Removing Service Extensions..."
    
    for extension in "${SERVICE_EXTENSIONS[@]}"; do
        if [[ -n "$extension" ]]; then
            log_info "Deleting Service Extension: $extension"
            gcloud service-extensions extensions delete "$extension" --location="${REGION}" --quiet 2>/dev/null || log_warning "Failed to delete Service Extension: $extension"
        fi
    done
    
    log_success "Service Extensions removed"
}

# Remove backend services and health checks
remove_backend_services() {
    log_info "Removing backend services and health checks..."
    
    # Delete backend services
    for backend in "${BACKEND_SERVICES[@]}"; do
        if [[ -n "$backend" ]]; then
            log_info "Deleting backend service: $backend"
            gcloud compute backend-services delete "$backend" --global --quiet 2>/dev/null || log_warning "Failed to delete backend service: $backend"
        fi
    done
    
    # Delete health checks
    for healthcheck in "${HEALTH_CHECKS[@]}"; do
        if [[ -n "$healthcheck" ]]; then
            log_info "Deleting health check: $healthcheck"
            gcloud compute health-checks delete "$healthcheck" --quiet 2>/dev/null || log_warning "Failed to delete health check: $healthcheck"
        fi
    done
    
    log_success "Backend services and health checks removed"
}

# Remove Network Endpoint Groups
remove_network_endpoint_groups() {
    log_info "Removing Network Endpoint Groups..."
    
    for neg in "${NEGS[@]}"; do
        if [[ -n "$neg" ]]; then
            log_info "Deleting NEG: $neg"
            gcloud compute network-endpoint-groups delete "$neg" --region="${REGION}" --quiet 2>/dev/null || log_warning "Failed to delete NEG: $neg"
        fi
    done
    
    log_success "Network Endpoint Groups removed"
}

# Remove Cloud Functions
remove_cloud_functions() {
    log_info "Removing Cloud Functions..."
    
    for function in "${CLOUD_FUNCTIONS[@]}"; do
        if [[ -n "$function" ]]; then
            log_info "Deleting Cloud Function: $function"
            gcloud functions delete "$function" --region="${REGION}" --quiet 2>/dev/null || log_warning "Failed to delete Cloud Function: $function"
        fi
    done
    
    log_success "Cloud Functions removed"
}

# Remove Workflows
remove_workflows() {
    log_info "Removing Workflows..."
    
    for workflow in "${WORKFLOWS[@]}"; do
        if [[ -n "$workflow" ]]; then
            log_info "Deleting Workflow: $workflow"
            gcloud workflows delete "$workflow" --location="${REGION}" --quiet 2>/dev/null || log_warning "Failed to delete Workflow: $workflow"
        fi
    done
    
    log_success "Workflows removed"
}

# Remove Cloud Run services
remove_cloud_run_services() {
    log_info "Removing Cloud Run services..."
    
    for service in "${CLOUD_RUN_SERVICES[@]}"; do
        if [[ -n "$service" ]]; then
            log_info "Deleting Cloud Run service: $service"
            gcloud run services delete "$service" --region="${REGION}" --quiet 2>/dev/null || log_warning "Failed to delete Cloud Run service: $service"
        fi
    done
    
    log_success "Cloud Run services removed"
}

# Remove logging sinks
remove_logging_sinks() {
    log_info "Removing logging sinks..."
    
    for sink in "${LOGGING_SINKS[@]}"; do
        if [[ -n "$sink" ]]; then
            log_info "Deleting logging sink: $sink"
            gcloud logging sinks delete "$sink" --quiet 2>/dev/null || log_warning "Failed to delete logging sink: $sink"
        fi
    done
    
    log_success "Logging sinks removed"
}

# Remove BigQuery resources
remove_bigquery_resources() {
    log_info "Removing BigQuery resources..."
    
    for dataset in "${BQ_DATASETS[@]}"; do
        if [[ -n "$dataset" ]]; then
            log_info "Deleting BigQuery dataset: $dataset"
            bq rm -rf --dataset "${PROJECT_ID}:${dataset}" 2>/dev/null || log_warning "Failed to delete BigQuery dataset: $dataset"
        fi
    done
    
    log_success "BigQuery resources removed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/deployment-info.txt"
        "${SCRIPT_DIR}/generate_traffic.sh"
        "${SCRIPT_DIR}/traffic-router-function.py"
        "${SCRIPT_DIR}/requirements.txt"
        "${SCRIPT_DIR}/analytics-workflow.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $(basename "$file")"
            rm -f "$file"
        fi
    done
    
    # Clean up environment variables
    unset PROJECT_ID REGION RANDOM_SUFFIX DATASET_NAME EXTENSION_NAME
    unset CLOUD_RUN_SERVICES FORWARDING_RULES HTTP_PROXIES URL_MAPS
    unset BACKEND_SERVICES HEALTH_CHECKS NEGS CLOUD_FUNCTIONS
    unset SERVICE_EXTENSIONS WORKFLOWS BQ_DATASETS LOGGING_SINKS
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining Cloud Run services
    local remaining_services=$(gcloud run services list --region="${REGION}" --format="value(metadata.name)" --filter="metadata.name~service-[abc]-.*" 2>/dev/null | wc -l)
    if [[ $remaining_services -gt 0 ]]; then
        log_warning "Found $remaining_services remaining Cloud Run services"
        remaining_resources=$((remaining_resources + remaining_services))
    fi
    
    # Check for remaining load balancer components
    local remaining_lb=$(gcloud compute forwarding-rules list --global --format="value(name)" --filter="name~intelligent-lb-rule-.*" 2>/dev/null | wc -l)
    if [[ $remaining_lb -gt 0 ]]; then
        log_warning "Found $remaining_lb remaining load balancer components"
        remaining_resources=$((remaining_resources + remaining_lb))
    fi
    
    # Check for remaining BigQuery datasets
    local remaining_bq=$(bq ls --format=csv --max_results=1000 2>/dev/null | grep "traffic_analytics_" | wc -l || echo 0)
    if [[ $remaining_bq -gt 0 ]]; then
        log_warning "Found $remaining_bq remaining BigQuery datasets"
        remaining_resources=$((remaining_resources + remaining_bq))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Some resources may still exist. Check Google Cloud Console for manual cleanup."
        log_info "You can also run this script again to attempt cleanup of remaining resources."
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log_info "=== Cleanup Summary ==="
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Cleanup completed at: $(date)"
    
    if [[ -f "${SCRIPT_DIR}/destroy.log" ]]; then
        log_info "Detailed logs available in: ${SCRIPT_DIR}/destroy.log"
    fi
    
    log_info "=== Recommended Next Steps ==="
    log_info "1. Check Google Cloud Console for any remaining resources"
    log_info "2. Review billing to ensure all resources are stopped"
    log_info "3. Clean up any custom IAM roles if created manually"
    log_info "4. Remove project if it was created specifically for this recipe"
}

# Main cleanup function
main() {
    log_info "=== Starting GCP Load Balancer Traffic Routing Cleanup ==="
    
    # Confirm destruction
    confirm_destruction "all recipe resources (Load Balancer, Cloud Run, BigQuery, etc.)"
    
    # Load configuration and discover resources
    load_deployment_config
    find_resources_by_pattern
    
    # Perform cleanup in reverse dependency order
    stop_traffic_generation
    remove_load_balancer
    remove_service_extensions
    remove_backend_services
    remove_network_endpoint_groups
    remove_cloud_functions
    remove_workflows
    remove_cloud_run_services
    remove_logging_sinks
    remove_bigquery_resources
    cleanup_local_files
    
    # Verify and summarize
    verify_cleanup
    display_cleanup_summary
    
    log_success "=== Cleanup completed! ==="
}

# Handle script arguments
case "${1:-}" in
    --force)
        export FORCE_DESTROY=true
        log_info "Force mode enabled - skipping confirmation prompts"
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --help     Show this help message"
        echo ""
        echo "This script will remove all resources created by the deploy.sh script."
        echo "Make sure you have the correct project configured in gcloud."
        exit 0
        ;;
esac

# Run main function
main "$@"