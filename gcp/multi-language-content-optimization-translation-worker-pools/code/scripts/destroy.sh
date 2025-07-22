#!/bin/bash

#####################################################################
# Destroy Script for Multi-Language Content Optimization
# GCP Recipe: Cloud Translation Advanced + Cloud Run Worker Pools
#####################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#####################################################################
# Logging Functions
#####################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#####################################################################
# Error Handling
#####################################################################

handle_error() {
    local exit_code=$?
    log ERROR "Cleanup failed with exit code $exit_code"
    log INFO "Check $ERROR_LOG for detailed error information"
    log WARN "Some resources may still exist and require manual cleanup"
    exit $exit_code
}

trap handle_error ERR

#####################################################################
# Environment Loading
#####################################################################

load_environment() {
    log INFO "Loading environment variables..."
    
    # Try to load from .env file if it exists
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log INFO "Loading environment from .env file..."
        source "${SCRIPT_DIR}/.env"
        log DEBUG "Loaded environment variables from .env"
    else
        log WARN ".env file not found, using command line arguments or defaults"
        
        # Set default values if not provided
        export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log ERROR "PROJECT_ID not set and could not be determined from gcloud config"
            log INFO "Please set PROJECT_ID environment variable or ensure gcloud is configured"
            return 1
        fi
        
        # Generate resource names based on project
        RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(echo $PROJECT_ID | tail -c 7)}"
        export SOURCE_BUCKET="${SOURCE_BUCKET:-content-source-${RANDOM_SUFFIX}}"
        export TRANSLATED_BUCKET="${TRANSLATED_BUCKET:-content-translated-${RANDOM_SUFFIX}}"
        export MODELS_BUCKET="${MODELS_BUCKET:-translation-models-${RANDOM_SUFFIX}}"
        export TOPIC_NAME="${TOPIC_NAME:-content-processing-${RANDOM_SUFFIX}}"
        export WORKER_POOL_NAME="${WORKER_POOL_NAME:-translation-workers-${RANDOM_SUFFIX}}"
        export DATASET_NAME="${DATASET_NAME:-content_analytics_${RANDOM_SUFFIX}}"
        export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-translation-worker-sa}"
    fi
    
    # Validate required variables
    local required_vars=("PROJECT_ID" "REGION" "SOURCE_BUCKET" "TRANSLATED_BUCKET" 
                         "MODELS_BUCKET" "TOPIC_NAME" "WORKER_POOL_NAME" 
                         "DATASET_NAME" "SERVICE_ACCOUNT_NAME")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log ERROR "Required variable $var is not set"
            return 1
        fi
    done
    
    log INFO "✅ Environment variables loaded"
    log DEBUG "PROJECT_ID: $PROJECT_ID"
    log DEBUG "WORKER_POOL_NAME: $WORKER_POOL_NAME"
    log DEBUG "SOURCE_BUCKET: $SOURCE_BUCKET"
}

#####################################################################
# Prerequisites Check
#####################################################################

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log ERROR "Google Cloud CLI (gcloud) is not installed"
        return 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log ERROR "gsutil is not available"
        return 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log ERROR "BigQuery CLI (bq) is not available"
        return 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log ERROR "Not authenticated with gcloud"
        log INFO "Run: gcloud auth login"
        return 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" || {
        log ERROR "Failed to set project context: $PROJECT_ID"
        return 1
    }
    
    log INFO "✅ Prerequisites check passed"
}

#####################################################################
# Confirmation Prompts
#####################################################################

confirm_destruction() {
    log WARN "⚠️  WARNING: This will permanently delete the following resources:"
    log WARN "    • Cloud Run Worker Pool: $WORKER_POOL_NAME"
    log WARN "    • Storage Buckets: $SOURCE_BUCKET, $TRANSLATED_BUCKET, $MODELS_BUCKET"
    log WARN "    • Pub/Sub Topics and Subscriptions: $TOPIC_NAME"
    log WARN "    • BigQuery Dataset: $DATASET_NAME"
    log WARN "    • Service Account: $SERVICE_ACCOUNT_NAME"
    log WARN "    • Container Images in gcr.io/$PROJECT_ID"
    log WARN ""
    
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        echo -n "Are you sure you want to proceed? (yes/no): "
        read -r confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log INFO "Destruction cancelled by user"
            exit 0
        fi
    else
        log INFO "Force destruction enabled, skipping confirmation"
    fi
    
    log INFO "Proceeding with resource destruction..."
}

#####################################################################
# Resource Deletion Functions
#####################################################################

delete_worker_pool() {
    log INFO "Deleting Cloud Run Worker Pool..."
    
    # Check if worker pool exists
    if gcloud run worker-pools describe "${WORKER_POOL_NAME}" \
        --region "${REGION}" &> /dev/null; then
        
        log INFO "Deleting worker pool: $WORKER_POOL_NAME"
        gcloud run worker-pools delete "${WORKER_POOL_NAME}" \
            --region "${REGION}" \
            --quiet || {
            log ERROR "Failed to delete worker pool"
            return 1
        }
        
        # Wait for deletion to complete
        log INFO "Waiting for worker pool deletion to complete..."
        local max_attempts=30
        local attempt=0
        
        while [[ $attempt -lt $max_attempts ]]; do
            if ! gcloud run worker-pools describe "${WORKER_POOL_NAME}" \
                --region "${REGION}" &> /dev/null; then
                break
            fi
            
            log INFO "Worker pool still exists, waiting... (attempt $((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -eq $max_attempts ]]; then
            log ERROR "Worker pool deletion timed out"
            return 1
        fi
        
        log INFO "✅ Worker pool deleted successfully"
    else
        log INFO "Worker pool $WORKER_POOL_NAME not found, skipping"
    fi
}

delete_pubsub_resources() {
    log INFO "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    local subscriptions=("${TOPIC_NAME}-sub" "${TOPIC_NAME}-dlq-sub")
    
    for subscription in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe "$subscription" &> /dev/null; then
            log INFO "Deleting subscription: $subscription"
            gcloud pubsub subscriptions delete "$subscription" --quiet || {
                log WARN "Failed to delete subscription: $subscription"
            }
        else
            log INFO "Subscription $subscription not found, skipping"
        fi
    done
    
    # Delete topics
    local topics=("${TOPIC_NAME}" "${TOPIC_NAME}-dlq")
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &> /dev/null; then
            log INFO "Deleting topic: $topic"
            gcloud pubsub topics delete "$topic" --quiet || {
                log WARN "Failed to delete topic: $topic"
            }
        else
            log INFO "Topic $topic not found, skipping"
        fi
    done
    
    log INFO "✅ Pub/Sub resources cleanup completed"
}

delete_storage_buckets() {
    log INFO "Deleting Cloud Storage buckets..."
    
    local buckets=("$SOURCE_BUCKET" "$TRANSLATED_BUCKET" "$MODELS_BUCKET")
    
    for bucket in "${buckets[@]}"; do
        if gsutil ls "gs://${bucket}" &> /dev/null; then
            log INFO "Deleting bucket contents: $bucket"
            gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true
            
            log INFO "Deleting bucket: $bucket"
            gsutil rb "gs://${bucket}" || {
                log WARN "Failed to delete bucket: $bucket"
            }
        else
            log INFO "Bucket $bucket not found, skipping"
        fi
    done
    
    log INFO "✅ Storage buckets cleanup completed"
}

delete_bigquery_resources() {
    log INFO "Deleting BigQuery resources..."
    
    # Check if dataset exists
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log INFO "Deleting BigQuery dataset: $DATASET_NAME"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || {
            log ERROR "Failed to delete BigQuery dataset"
            return 1
        }
        log INFO "✅ BigQuery dataset deleted successfully"
    else
        log INFO "BigQuery dataset $DATASET_NAME not found, skipping"
    fi
}

delete_service_account() {
    log INFO "Deleting IAM service account..."
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
        # Remove IAM policy bindings first
        local roles=(
            "roles/translate.editor"
            "roles/storage.objectAdmin"
            "roles/bigquery.dataEditor"
            "roles/pubsub.subscriber"
            "roles/logging.logWriter"
            "roles/monitoring.metricWriter"
        )
        
        for role in "${roles[@]}"; do
            log INFO "Removing role binding: $role"
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="$role" --quiet 2>/dev/null || {
                log WARN "Failed to remove role binding: $role (may not exist)"
            }
        done
        
        # Delete service account
        log INFO "Deleting service account: $SERVICE_ACCOUNT_NAME"
        gcloud iam service-accounts delete "$sa_email" --quiet || {
            log ERROR "Failed to delete service account"
            return 1
        }
        
        log INFO "✅ Service account deleted successfully"
    else
        log INFO "Service account $SERVICE_ACCOUNT_NAME not found, skipping"
    fi
}

delete_container_images() {
    log INFO "Deleting container images..."
    
    # List and delete container images
    local image_name="gcr.io/${PROJECT_ID}/translation-worker"
    
    if gcloud container images list --repository="gcr.io/${PROJECT_ID}" \
        --format="value(name)" | grep -q "translation-worker"; then
        
        log INFO "Deleting container image: $image_name"
        gcloud container images delete "$image_name" \
            --force-delete-tags --quiet || {
            log WARN "Failed to delete container image"
        }
        
        log INFO "✅ Container images deleted successfully"
    else
        log INFO "Container image not found, skipping"
    fi
}

cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    # Remove application directory
    local app_dir="${SCRIPT_DIR}/../translation-worker"
    if [[ -d "$app_dir" ]]; then
        log INFO "Removing application directory: $app_dir"
        rm -rf "$app_dir"
    fi
    
    # Remove sample content directory
    local content_dir="${SCRIPT_DIR}/../sample-content"
    if [[ -d "$content_dir" ]]; then
        log INFO "Removing sample content directory: $content_dir"
        rm -rf "$content_dir"
    fi
    
    # Remove environment file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log INFO "Removing environment file"
        rm -f "${SCRIPT_DIR}/.env"
    fi
    
    # Remove temporary files
    rm -f "${SCRIPT_DIR}/engagement_sample.json" 2>/dev/null || true
    
    log INFO "✅ Local files cleanup completed"
}

#####################################################################
# Validation
#####################################################################

validate_cleanup() {
    log INFO "Validating resource cleanup..."
    
    local cleanup_errors=0
    
    # Check worker pool
    if gcloud run worker-pools describe "${WORKER_POOL_NAME}" \
        --region "${REGION}" &> /dev/null; then
        log ERROR "Worker pool still exists: $WORKER_POOL_NAME"
        ((cleanup_errors++))
    fi
    
    # Check storage buckets
    local buckets=("$SOURCE_BUCKET" "$TRANSLATED_BUCKET" "$MODELS_BUCKET")
    for bucket in "${buckets[@]}"; do
        if gsutil ls "gs://${bucket}" &> /dev/null; then
            log ERROR "Bucket still exists: $bucket"
            ((cleanup_errors++))
        fi
    done
    
    # Check Pub/Sub topics
    local topics=("${TOPIC_NAME}" "${TOPIC_NAME}-dlq")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &> /dev/null; then
            log ERROR "Topic still exists: $topic"
            ((cleanup_errors++))
        fi
    done
    
    # Check BigQuery dataset
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log ERROR "BigQuery dataset still exists: $DATASET_NAME"
        ((cleanup_errors++))
    fi
    
    # Check service account
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$sa_email" &> /dev/null; then
        log ERROR "Service account still exists: $SERVICE_ACCOUNT_NAME"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log INFO "✅ All resources have been successfully cleaned up"
    else
        log ERROR "Cleanup validation failed with $cleanup_errors errors"
        log INFO "Manual cleanup may be required for remaining resources"
        return 1
    fi
}

#####################################################################
# Main Destruction Flow
#####################################################################

main() {
    log INFO "Starting destruction of Multi-Language Content Optimization system..."
    log INFO "Destruction logs: $LOG_FILE"
    
    # Initialize log files
    echo "Destruction started at $(date)" > "$LOG_FILE"
    echo "Error log for destruction at $(date)" > "$ERROR_LOG"
    
    # Execute destruction steps
    load_environment
    check_prerequisites
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_worker_pool
    delete_pubsub_resources
    delete_bigquery_resources
    delete_storage_buckets
    delete_service_account
    delete_container_images
    cleanup_local_files
    
    validate_cleanup
    
    log INFO "🎉 Resource destruction completed successfully!"
    log INFO ""
    log INFO "📋 Cleanup Summary:"
    log INFO "  Project ID: $PROJECT_ID"
    log INFO "  Region: $REGION"
    log INFO "  All resources have been removed"
    log INFO ""
    log INFO "🔍 Final verification:"
    log INFO "  Check the Google Cloud Console to confirm all resources are deleted"
    log INFO "  Review any remaining charges in the billing console"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force           Skip confirmation prompts"
            echo "  --project ID      Specify project ID"
            echo "  --region REGION   Specify region"
            echo "  --help            Show this help message"
            echo ""
            echo "Environment variables can also be used:"
            echo "  PROJECT_ID, REGION, FORCE_DESTROY"
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            log INFO "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi