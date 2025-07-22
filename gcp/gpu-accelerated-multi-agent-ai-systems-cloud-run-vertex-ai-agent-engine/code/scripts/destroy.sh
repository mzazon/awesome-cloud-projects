#!/bin/bash

# Multi-Agent AI Systems Cleanup Script for GCP
# Destroys all resources created by the multi-agent AI deployment
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID    Specify GCP project ID (optional)
#   --region REGION           Specify GCP region (optional)
#   --force                   Skip confirmation prompts
#   --keep-images            Keep container images in Artifact Registry
#   --dry-run                Show what would be deleted without executing
#   --help                   Show this help message

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_REGION="us-central1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/multi-agent-destroy-$(date +%Y%m%d-%H%M%S).log"

# Flags
FORCE=false
KEEP_IMAGES=false
DRY_RUN=false
PROJECT_ID=""
REGION=""

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check log file: $LOG_FILE"
    log_error "Some resources may still exist and incur charges."
    log_error "Please review the Google Cloud Console to verify cleanup."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Multi-Agent AI Systems Cleanup Script

USAGE:
    ./destroy.sh [OPTIONS]

OPTIONS:
    --project-id PROJECT_ID    Specify GCP project ID (optional)
    --region REGION           Specify GCP region (default: $DEFAULT_REGION)
    --force                   Skip confirmation prompts
    --keep-images            Keep container images in Artifact Registry
    --dry-run                Show what would be deleted without executing
    --help                   Show this help message

EXAMPLES:
    ./destroy.sh
    ./destroy.sh --project-id my-project --region us-west1
    ./destroy.sh --force
    ./destroy.sh --dry-run
    ./destroy.sh --keep-images

SAFETY:
    - By default, prompts for confirmation before deleting resources
    - Use --dry-run to see what would be deleted
    - Use --force to skip confirmations (use with caution)
    - Some resources may take time to fully delete

EOF
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
            FORCE=true
            shift
            ;;
        --keep-images)
            KEEP_IMAGES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
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

# Set defaults
if [[ -z "$REGION" ]]; then
    REGION="$DEFAULT_REGION"
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be deleted"
    gcloud() { printf "DRY RUN: gcloud %s\n" "$*"; }
    FORCE=true  # Skip prompts in dry run
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "Not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Get or validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID specified and no default project set."
            log_error "Use: ./destroy.sh --project-id YOUR_PROJECT_ID"
            exit 1
        fi
        log "Using current project: $PROJECT_ID"
    else
        # Validate project exists
        if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
            log_error "Project $PROJECT_ID does not exist or you don't have access."
            exit 1
        fi
    fi
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    echo -e "${RED}WARNING: This will delete ALL multi-agent AI system resources!${NC}"
    echo "This includes:"
    echo "  - All Cloud Run services with GPU instances"
    echo "  - Redis instance and stored data"
    echo "  - Pub/Sub topics and subscriptions"
    echo "  - Container images (unless --keep-images is used)"
    echo "  - Monitoring configuration"
    echo
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Find and delete Cloud Run services
delete_cloud_run_services() {
    log "Deleting Cloud Run services..."
    
    # Find all agent-related services
    local services=$(gcloud run services list \
        --platform=managed \
        --region="$REGION" \
        --format="value(metadata.name)" \
        --filter="metadata.name~agent" 2>/dev/null || echo "")
    
    if [[ -z "$services" ]]; then
        log_warning "No Cloud Run agent services found"
        return
    fi
    
    for service in $services; do
        log "Deleting Cloud Run service: $service"
        gcloud run services delete "$service" \
            --platform=managed \
            --region="$REGION" \
            --quiet || log_warning "Failed to delete service: $service"
    done
    
    log_success "Cloud Run services deleted"
}

# Delete Redis instances
delete_redis_instances() {
    log "Deleting Redis instances..."
    
    # Find all agent-related Redis instances
    local instances=$(gcloud redis instances list \
        --region="$REGION" \
        --format="value(name)" \
        --filter="name~agent-cache" 2>/dev/null || echo "")
    
    if [[ -z "$instances" ]]; then
        log_warning "No Redis instances found"
        return
    fi
    
    for instance in $instances; do
        log "Deleting Redis instance: $instance"
        gcloud redis instances delete "$instance" \
            --region="$REGION" \
            --quiet || log_warning "Failed to delete Redis instance: $instance"
    done
    
    # Wait for deletion to complete
    log "Waiting for Redis instances to be fully deleted..."
    sleep 30
    
    log_success "Redis instances deleted"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Find and delete subscriptions first
    local subscriptions=$(gcloud pubsub subscriptions list \
        --format="value(name)" \
        --filter="name~agent-tasks" 2>/dev/null || echo "")
    
    for subscription in $subscriptions; do
        local sub_name=$(basename "$subscription")
        log "Deleting Pub/Sub subscription: $sub_name"
        gcloud pubsub subscriptions delete "$sub_name" \
            --quiet || log_warning "Failed to delete subscription: $sub_name"
    done
    
    # Find and delete topics
    local topics=$(gcloud pubsub topics list \
        --format="value(name)" \
        --filter="name~agent-tasks" 2>/dev/null || echo "")
    
    for topic in $topics; do
        local topic_name=$(basename "$topic")
        log "Deleting Pub/Sub topic: $topic_name"
        gcloud pubsub topics delete "$topic_name" \
            --quiet || log_warning "Failed to delete topic: $topic_name"
    done
    
    log_success "Pub/Sub resources deleted"
}

# Delete container images
delete_container_images() {
    if [[ "$KEEP_IMAGES" == "true" ]]; then
        log_warning "Keeping container images as requested"
        return
    fi
    
    log "Deleting container images..."
    
    # Check if repository exists
    if ! gcloud artifacts repositories describe agent-images --location="$REGION" &>/dev/null; then
        log_warning "Artifact Registry repository 'agent-images' not found"
        return
    fi
    
    # Delete all images in the repository
    local images=$(gcloud artifacts docker images list \
        "${REGION}-docker.pkg.dev/${PROJECT_ID}/agent-images" \
        --format="value(IMAGE)" 2>/dev/null || echo "")
    
    if [[ -n "$images" ]]; then
        for image in $images; do
            log "Deleting container image: $image"
            gcloud artifacts docker images delete "$image" \
                --quiet || log_warning "Failed to delete image: $image"
        done
    fi
    
    # Delete the repository
    log "Deleting Artifact Registry repository..."
    gcloud artifacts repositories delete agent-images \
        --location="$REGION" \
        --quiet || log_warning "Failed to delete Artifact Registry repository"
    
    log_success "Container images and repository deleted"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete log-based metrics
    if gcloud logging metrics describe agent_response_time &>/dev/null; then
        log "Deleting log-based metric: agent_response_time"
        gcloud logging metrics delete agent_response_time \
            --quiet || log_warning "Failed to delete log-based metric"
    fi
    
    # Delete alerting policies
    local policies=$(gcloud alpha monitoring policies list \
        --format="value(name)" \
        --filter="displayName~'High GPU Cost Alert'" 2>/dev/null || echo "")
    
    for policy in $policies; do
        log "Deleting monitoring policy: $policy"
        gcloud alpha monitoring policies delete "$policy" \
            --quiet || log_warning "Failed to delete monitoring policy: $policy"
    done
    
    log_success "Monitoring resources deleted"
}

# Delete Vertex AI resources
delete_vertex_ai_resources() {
    log "Checking for Vertex AI Agent Engine resources..."
    
    # List and delete reasoning engines
    local engines=$(gcloud ai reasoning-engines list \
        --region="$REGION" \
        --format="value(name)" \
        --filter="displayName~'multi-agent'" 2>/dev/null || echo "")
    
    for engine in $engines; do
        local engine_id=$(basename "$engine")
        log "Deleting Vertex AI Reasoning Engine: $engine_id"
        gcloud ai reasoning-engines delete "$engine_id" \
            --region="$REGION" \
            --quiet || log_warning "Failed to delete reasoning engine: $engine_id"
    done
    
    if [[ -z "$engines" ]]; then
        log_warning "No Vertex AI Agent Engine resources found"
    else
        log_success "Vertex AI resources deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove any temporary build directories
    if [[ -d "/tmp" ]]; then
        find /tmp -name "multi-agent-build-*" -type d -exec rm -rf {} + 2>/dev/null || true
        find /tmp -name "multi-agent-deploy-*.log" -mtime +7 -delete 2>/dev/null || true
        find /tmp -name "multi-agent-destroy-*.log" -mtime +7 -delete 2>/dev/null || true
    fi
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues=0
    
    # Check Cloud Run services
    local remaining_services=$(gcloud run services list \
        --platform=managed \
        --region="$REGION" \
        --format="value(metadata.name)" \
        --filter="metadata.name~agent" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_services" ]]; then
        log_warning "Remaining Cloud Run services: $remaining_services"
        issues=$((issues + 1))
    fi
    
    # Check Redis instances
    local remaining_redis=$(gcloud redis instances list \
        --region="$REGION" \
        --format="value(name)" \
        --filter="name~agent-cache" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_redis" ]]; then
        log_warning "Remaining Redis instances: $remaining_redis"
        issues=$((issues + 1))
    fi
    
    # Check Pub/Sub topics
    local remaining_topics=$(gcloud pubsub topics list \
        --format="value(name)" \
        --filter="name~agent-tasks" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_topics" ]]; then
        log_warning "Remaining Pub/Sub topics: $remaining_topics"
        issues=$((issues + 1))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Cleanup verification completed - no issues found"
    else
        log_warning "Cleanup verification found $issues potential issues"
        log_warning "Please check the Google Cloud Console to verify all resources are deleted"
    fi
}

# Print cleanup summary
print_summary() {
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Keep Images: $KEEP_IMAGES"
    echo
    echo "=== DELETED RESOURCES ==="
    echo "✅ Cloud Run services (agent-*)"
    echo "✅ Redis instances (agent-cache-*)"
    echo "✅ Pub/Sub topics and subscriptions (agent-tasks-*)"
    if [[ "$KEEP_IMAGES" == "false" ]]; then
        echo "✅ Container images and Artifact Registry repository"
    else
        echo "⚠️  Container images kept (--keep-images flag used)"
    fi
    echo "✅ Monitoring resources (log-based metrics, alerting policies)"
    echo "✅ Vertex AI Agent Engine resources"
    echo "✅ Local temporary files"
    echo
    echo "=== COST IMPACT ==="
    echo "💰 All GPU-enabled Cloud Run instances stopped (no more GPU charges)"
    echo "💰 Redis instances deleted (no more memory charges)"
    echo "💰 Only remaining charges should be for:"
    if [[ "$KEEP_IMAGES" == "true" ]]; then
        echo "   - Container image storage in Artifact Registry"
    fi
    echo "   - Cloud Logging retention (if configured)"
    echo "   - Historical monitoring data"
    echo
    echo "=== RECOMMENDATIONS ==="
    echo "1. Check the Google Cloud Console to verify all resources are deleted"
    echo "2. Review the billing dashboard to confirm cost reduction"
    echo "3. Check Cloud Logging for any remaining logs if storage costs are a concern"
    echo
    echo "Cleanup log saved to: $LOG_FILE"
}

# Main cleanup flow
main() {
    log "Starting Multi-Agent AI System cleanup..."
    log "Log file: $LOG_FILE"
    
    check_prerequisites
    confirm_deletion
    
    log "Beginning resource deletion..."
    
    delete_cloud_run_services
    delete_redis_instances
    delete_pubsub_resources
    delete_container_images
    delete_monitoring_resources
    delete_vertex_ai_resources
    cleanup_local_files
    verify_cleanup
    print_summary
    
    log_success "Cleanup completed successfully!"
    log_warning "Please verify in Google Cloud Console that all resources are deleted"
}

# Run main function
main "$@"