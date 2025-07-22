#!/bin/bash

# Enterprise Knowledge Discovery with Google Agentspace and Vertex AI Search
# Cleanup/Destroy Script
# 
# This script safely removes all resources created by the deployment script:
# - Google Agentspace agents and workflows
# - Vertex AI Search engines and data stores
# - BigQuery datasets and tables
# - Cloud Storage buckets and contents
# - IAM roles and service accounts
# - Cloud Monitoring dashboards

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    error "Cleanup failed with exit code ${exit_code}"
    error "Check ${LOG_FILE} for detailed error information"
    warning "Some resources may not have been cleaned up properly"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Enterprise Knowledge Discovery Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -h, --help                    Show this help message
    --dry-run                     Show what would be deleted without executing
    --force                       Skip all confirmation prompts
    --keep-iam                    Keep IAM roles and service accounts
    --prefix PREFIX               Resource prefix to target for deletion

Environment Variables:
    PROJECT_ID                    Google Cloud Project ID
    REGION                       Deployment region

Examples:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --prefix enterprise-docs-abc123
    PROJECT_ID=my-project-123 $0 --force

EOF
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
KEEP_IAM=false
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
PREFIX=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep-iam)
            KEEP_IAM=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID}" ]]; then
    error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
    show_help
    exit 1
fi

# Initialize log file
echo "=== Enterprise Knowledge Discovery Cleanup ===" > "${LOG_FILE}"
log "Starting cleanup at $(date)"
log "Project ID: ${PROJECT_ID}"
log "Region: ${REGION}"
log "Dry Run: ${DRY_RUN}"
log "Force: ${FORCE}"
log "Keep IAM: ${KEEP_IAM}"

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} not found or not accessible."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set up environment
setup_environment() {
    info "Setting up environment..."
    
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION}"
    export ZONE="${REGION}-a"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Environment configured"
}

# Find resources with pattern matching
find_resources() {
    info "Discovering resources to clean up..."
    
    # Find storage buckets
    BUCKETS=()
    if [[ -n "${PREFIX}" ]]; then
        while IFS= read -r bucket; do
            [[ -n "${bucket}" ]] && BUCKETS+=("${bucket}")
        done < <(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "${PREFIX}" | sed 's|gs://||' | sed 's|/||' || true)
    else
        while IFS= read -r bucket; do
            [[ -n "${bucket}" ]] && BUCKETS+=("${bucket}")
        done < <(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(enterprise-docs|knowledge)" | sed 's|gs://||' | sed 's|/||' || true)
    fi
    
    # Find BigQuery datasets
    DATASETS=()
    if [[ -n "${PREFIX}" ]]; then
        while IFS= read -r dataset; do
            [[ -n "${dataset}" ]] && DATASETS+=("${dataset}")
        done < <(bq ls --project_id="${PROJECT_ID}" --max_results=1000 --format=csv 2>/dev/null | tail -n +2 | grep "${PREFIX}" | cut -d, -f1 || true)
    else
        while IFS= read -r dataset; do
            [[ -n "${dataset}" ]] && DATASETS+=("${dataset}")
        done < <(bq ls --project_id="${PROJECT_ID}" --max_results=1000 --format=csv 2>/dev/null | tail -n +2 | grep -E "(knowledge_analytics|enterprise)" | cut -d, -f1 || true)
    fi
    
    # Find Vertex AI Search engines and data stores
    SEARCH_ENGINES=()
    DATA_STORES=()
    if [[ -n "${PREFIX}" ]]; then
        while IFS= read -r engine; do
            [[ -n "${engine}" ]] && SEARCH_ENGINES+=("${engine}")
        done < <(gcloud alpha discovery-engine engines list --location=global --format="value(name)" 2>/dev/null | grep "${PREFIX}" | xargs -I {} basename {} || true)
        
        while IFS= read -r store; do
            [[ -n "${store}" ]] && DATA_STORES+=("${store}")
        done < <(gcloud alpha discovery-engine data-stores list --location=global --format="value(name)" 2>/dev/null | grep "${PREFIX}" | xargs -I {} basename {} || true)
    else
        while IFS= read -r engine; do
            [[ -n "${engine}" ]] && SEARCH_ENGINES+=("${engine}")
        done < <(gcloud alpha discovery-engine engines list --location=global --format="value(name)" 2>/dev/null | grep -E "(enterprise|knowledge)" | xargs -I {} basename {} || true)
        
        while IFS= read -r store; do
            [[ -n "${store}" ]] && DATA_STORES+=("${store}")
        done < <(gcloud alpha discovery-engine data-stores list --location=global --format="value(name)" 2>/dev/null | grep -E "(enterprise|knowledge)" | xargs -I {} basename {} || true)
    fi
    
    # Find Agentspace resources
    AGENTS=()
    WORKFLOWS=()
    while IFS= read -r agent; do
        [[ -n "${agent}" ]] && AGENTS+=("${agent}")
    done < <(gcloud alpha agentspace agents list --location=global --format="value(name)" 2>/dev/null | grep -E "(enterprise|knowledge)" | xargs -I {} basename {} || true)
    
    while IFS= read -r workflow; do
        [[ -n "${workflow}" ]] && WORKFLOWS+=("${workflow}")
    done < <(gcloud alpha agentspace workflows list --location=global --format="value(name)" 2>/dev/null | grep -E "(enterprise|knowledge)" | xargs -I {} basename {} || true)
    
    # Display found resources
    echo ""
    info "Found resources to clean up:"
    echo "  Storage Buckets: ${#BUCKETS[@]}"
    for bucket in "${BUCKETS[@]}"; do
        echo "    - gs://${bucket}"
    done
    echo "  BigQuery Datasets: ${#DATASETS[@]}"
    for dataset in "${DATASETS[@]}"; do
        echo "    - ${dataset}"
    done
    echo "  Search Engines: ${#SEARCH_ENGINES[@]}"
    for engine in "${SEARCH_ENGINES[@]}"; do
        echo "    - ${engine}"
    done
    echo "  Data Stores: ${#DATA_STORES[@]}"
    for store in "${DATA_STORES[@]}"; do
        echo "    - ${store}"
    done
    echo "  Agentspace Agents: ${#AGENTS[@]}"
    for agent in "${AGENTS[@]}"; do
        echo "    - ${agent}"
    done
    echo "  Agentspace Workflows: ${#WORKFLOWS[@]}"
    for workflow in "${WORKFLOWS[@]}"; do
        echo "    - ${workflow}"
    done
    echo ""
}

# Remove Agentspace resources
remove_agentspace_resources() {
    info "Removing Google Agentspace resources..."
    
    # Remove workflows first (they may depend on agents)
    for workflow in "${WORKFLOWS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete Agentspace workflow: ${workflow}"
        else
            info "Deleting Agentspace workflow: ${workflow}"
            if gcloud alpha agentspace workflows delete "${workflow}" \
                --location=global \
                --quiet 2>/dev/null; then
                success "Deleted workflow: ${workflow}"
            else
                warning "Failed to delete workflow: ${workflow} (may not exist or may have dependencies)"
            fi
        fi
    done
    
    # Remove agents
    for agent in "${AGENTS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete Agentspace agent: ${agent}"
        else
            info "Deleting Agentspace agent: ${agent}"
            if gcloud alpha agentspace agents delete "${agent}" \
                --location=global \
                --quiet 2>/dev/null; then
                success "Deleted agent: ${agent}"
            else
                warning "Failed to delete agent: ${agent} (may not exist)"
            fi
        fi
    done
    
    if [[ "${#AGENTS[@]}" -eq 0 && "${#WORKFLOWS[@]}" -eq 0 ]]; then
        info "No Agentspace resources found to remove"
    else
        success "Agentspace cleanup completed"
    fi
}

# Remove Vertex AI Search resources
remove_vertex_ai_search() {
    info "Removing Vertex AI Search resources..."
    
    # Remove search engines first (they depend on data stores)
    for engine in "${SEARCH_ENGINES[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete search engine: ${engine}"
        else
            info "Deleting search engine: ${engine}"
            if gcloud alpha discovery-engine engines delete "${engine}" \
                --location=global \
                --quiet 2>/dev/null; then
                success "Deleted search engine: ${engine}"
            else
                warning "Failed to delete search engine: ${engine} (may not exist or may have dependencies)"
            fi
        fi
    done
    
    # Wait a bit for engines to be deleted before removing data stores
    if [[ "${#SEARCH_ENGINES[@]}" -gt 0 && "${DRY_RUN}" == "false" ]]; then
        info "Waiting for search engines to be fully deleted..."
        sleep 30
    fi
    
    # Remove data stores
    for store in "${DATA_STORES[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete data store: ${store}"
        else
            info "Deleting data store: ${store}"
            if gcloud alpha discovery-engine data-stores delete "${store}" \
                --location=global \
                --quiet 2>/dev/null; then
                success "Deleted data store: ${store}"
            else
                warning "Failed to delete data store: ${store} (may not exist or may have dependencies)"
            fi
        fi
    done
    
    if [[ "${#SEARCH_ENGINES[@]}" -eq 0 && "${#DATA_STORES[@]}" -eq 0 ]]; then
        info "No Vertex AI Search resources found to remove"
    else
        success "Vertex AI Search cleanup completed"
    fi
}

# Remove BigQuery resources
remove_bigquery_resources() {
    info "Removing BigQuery resources..."
    
    for dataset in "${DATASETS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete BigQuery dataset: ${dataset}"
        else
            info "Deleting BigQuery dataset: ${dataset}"
            if bq rm -r -f "${PROJECT_ID}:${dataset}" 2>/dev/null; then
                success "Deleted BigQuery dataset: ${dataset}"
            else
                warning "Failed to delete BigQuery dataset: ${dataset} (may not exist)"
            fi
        fi
    done
    
    if [[ "${#DATASETS[@]}" -eq 0 ]]; then
        info "No BigQuery datasets found to remove"
    else
        success "BigQuery cleanup completed"
    fi
}

# Remove Cloud Storage resources
remove_storage_resources() {
    info "Removing Cloud Storage resources..."
    
    for bucket in "${BUCKETS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete storage bucket and contents: gs://${bucket}"
        else
            info "Deleting storage bucket and contents: gs://${bucket}"
            
            # First, try to delete all objects in the bucket
            if gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true; then
                info "Deleted contents of bucket: ${bucket}"
            fi
            
            # Then delete the bucket itself
            if gsutil rb "gs://${bucket}" 2>/dev/null; then
                success "Deleted storage bucket: ${bucket}"
            else
                warning "Failed to delete storage bucket: ${bucket} (may not exist or may not be empty)"
            fi
        fi
    done
    
    if [[ "${#BUCKETS[@]}" -eq 0 ]]; then
        info "No storage buckets found to remove"
    else
        success "Storage cleanup completed"
    fi
}

# Remove IAM resources
remove_iam_resources() {
    if [[ "${KEEP_IAM}" == "true" ]]; then
        info "Skipping IAM cleanup (--keep-iam specified)"
        return 0
    fi
    
    info "Removing IAM resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove IAM resources:"
        info "[DRY RUN]   - Service account: knowledge-discovery-sa"
        info "[DRY RUN]   - Custom role: knowledgeDiscoveryReader"
        info "[DRY RUN]   - Custom role: knowledgeDiscoveryAdmin"
        return 0
    fi
    
    # Remove service account
    info "Deleting service account: knowledge-discovery-sa"
    if gcloud iam service-accounts delete \
        "knowledge-discovery-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet 2>/dev/null; then
        success "Deleted service account: knowledge-discovery-sa"
    else
        warning "Failed to delete service account (may not exist)"
    fi
    
    # Remove custom IAM roles
    info "Deleting custom IAM role: knowledgeDiscoveryReader"
    if gcloud iam roles delete knowledgeDiscoveryReader \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null; then
        success "Deleted custom role: knowledgeDiscoveryReader"
    else
        warning "Failed to delete custom role: knowledgeDiscoveryReader (may not exist)"
    fi
    
    info "Deleting custom IAM role: knowledgeDiscoveryAdmin"
    if gcloud iam roles delete knowledgeDiscoveryAdmin \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null; then
        success "Deleted custom role: knowledgeDiscoveryAdmin"
    else
        warning "Failed to delete custom role: knowledgeDiscoveryAdmin (may not exist)"
    fi
    
    success "IAM cleanup completed"
}

# Remove monitoring resources
remove_monitoring_resources() {
    info "Removing monitoring resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would remove monitoring dashboards"
        return 0
    fi
    
    # Find and remove monitoring dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:'Enterprise Knowledge Discovery Dashboard'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${dashboards}" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "${dashboard}" ]]; then
                info "Deleting monitoring dashboard: ${dashboard}"
                if gcloud monitoring dashboards delete "${dashboard}" --quiet 2>/dev/null; then
                    success "Deleted monitoring dashboard"
                else
                    warning "Failed to delete monitoring dashboard (may not exist)"
                fi
            fi
        done <<< "${dashboards}"
    else
        info "No monitoring dashboards found to remove"
    fi
    
    success "Monitoring cleanup completed"
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/lifecycle.json"
        "${SCRIPT_DIR}/search_config.json"
        "${SCRIPT_DIR}/agentspace_config.yaml"
        "${SCRIPT_DIR}/knowledge_workflow.yaml"
        "${SCRIPT_DIR}/knowledge_reader_role.yaml"
        "${SCRIPT_DIR}/knowledge_admin_role.yaml"
        "${SCRIPT_DIR}/monitoring_config.json"
        "${SCRIPT_DIR}/sample_docs"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            if [[ -e "${file}" ]]; then
                info "[DRY RUN] Would remove temporary file/directory: ${file}"
            fi
        else
            if [[ -e "${file}" ]]; then
                info "Removing temporary file/directory: ${file}"
                rm -rf "${file}"
                success "Removed: ${file}"
            fi
        fi
    done
    
    success "Temporary files cleanup completed"
}

# Display cleanup summary
show_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    echo ""
    echo "=========================================="
    if [[ "${DRY_RUN}" == "true" ]]; then
        success "Enterprise Knowledge Discovery Cleanup Preview Complete!"
    else
        success "Enterprise Knowledge Discovery Cleanup Complete!"
    fi
    echo "=========================================="
    echo ""
    echo "Cleanup Details:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Duration: ${duration} seconds"
    echo "  Dry Run: ${DRY_RUN}"
    echo ""
    if [[ "${DRY_RUN}" == "false" ]]; then
        echo "Removed Resources:"
        echo "  ✅ Storage Buckets: ${#BUCKETS[@]}"
        echo "  ✅ BigQuery Datasets: ${#DATASETS[@]}"
        echo "  ✅ Vertex AI Search Engines: ${#SEARCH_ENGINES[@]}"
        echo "  ✅ Vertex AI Data Stores: ${#DATA_STORES[@]}"
        echo "  ✅ Agentspace Agents: ${#AGENTS[@]}"
        echo "  ✅ Agentspace Workflows: ${#WORKFLOWS[@]}"
        if [[ "${KEEP_IAM}" == "false" ]]; then
            echo "  ✅ IAM Roles and Service Accounts"
        else
            echo "  ⏭️  IAM Resources (kept as requested)"
        fi
        echo "  ✅ Monitoring Dashboards"
        echo "  ✅ Temporary Files"
        echo ""
        echo "All enterprise knowledge discovery resources have been removed."
        if [[ "${KEEP_IAM}" == "true" ]]; then
            warning "IAM roles and service accounts were preserved (--keep-iam specified)"
        fi
    else
        echo "This was a dry run. No resources were actually deleted."
        echo "Run without --dry-run to perform the actual cleanup."
    fi
    echo ""
    echo "Log file: ${LOG_FILE}"
    echo "=========================================="
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=========================================="
    error "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "=========================================="
    echo ""
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo "  • ${#BUCKETS[@]} Storage bucket(s) and ALL their contents"
    echo "  • ${#DATASETS[@]} BigQuery dataset(s) and ALL their data"
    echo "  • ${#SEARCH_ENGINES[@]} Vertex AI Search engine(s)"
    echo "  • ${#DATA_STORES[@]} Vertex AI data store(s)"
    echo "  • ${#AGENTS[@]} Agentspace agent(s)"
    echo "  • ${#WORKFLOWS[@]} Agentspace workflow(s)"
    if [[ "${KEEP_IAM}" == "false" ]]; then
        echo "  • IAM roles and service accounts"
    fi
    echo "  • Monitoring dashboards"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    error "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "Are you ABSOLUTELY SURE you want to delete these resources? (type 'DELETE' to confirm): " -r
    echo
    
    if [[ "${REPLY}" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    warning "Proceeding with resource deletion in 5 seconds..."
    warning "Press Ctrl+C to abort!"
    sleep 5
}

# Main cleanup function
main() {
    info "Starting Enterprise Knowledge Discovery cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    find_resources
    confirm_cleanup
    
    remove_agentspace_resources
    remove_vertex_ai_search
    remove_bigquery_resources
    remove_storage_resources
    remove_iam_resources
    remove_monitoring_resources
    cleanup_temp_files
    
    show_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi