#!/bin/bash

# ML Pipeline Governance with Hyperdisk ML and Vertex AI Model Registry - Cleanup Script
# This script safely removes all resources created by the deployment script

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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Some resources may need to be deleted manually."
    exit 1
}

# Continue on errors but log them
continue_on_error() {
    log_warning "$1"
    return 0
}

# Script header
echo "=============================================="
echo "ML Pipeline Governance Cleanup Script"
echo "=============================================="
echo ""

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error_exit "No active gcloud authentication found. Please run 'gcloud auth login' first."
fi

log_success "Prerequisites check completed"

# Load configuration from deployment
if [[ -f "deployment-config.env" ]]; then
    log "Loading deployment configuration..."
    source deployment-config.env
    log_success "Configuration loaded from deployment-config.env"
else
    log_warning "No deployment-config.env found. Using environment variables or defaults."
    
    # Try to get current project
    PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
    REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")}"
    ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter the project ID to clean up: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            error_exit "Project ID is required for cleanup"
        fi
    fi
    
    # Try to detect resources by pattern
    log "Attempting to detect resources in project $PROJECT_ID..."
    RANDOM_SUFFIX=""
    
    # Try to find resources with common patterns
    BUCKET_CANDIDATES=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "ml-training-data-" | head -1 || echo "")
    if [[ -n "$BUCKET_CANDIDATES" ]]; then
        BUCKET_NAME=$(basename "$BUCKET_CANDIDATES")
        RANDOM_SUFFIX=$(echo "$BUCKET_NAME" | sed 's/ml-training-data-//')
        log "Detected resources with suffix: $RANDOM_SUFFIX"
    fi
fi

echo ""
log "Cleanup Configuration:"
log "  Project ID: ${PROJECT_ID:-Not set}"
log "  Region: ${REGION:-Not set}"
log "  Zone: ${ZONE:-Not set}"
log "  Random Suffix: ${RANDOM_SUFFIX:-Not detected}"
echo ""

# Validate we have required information
if [[ -z "$PROJECT_ID" ]]; then
    error_exit "Project ID is required for cleanup. Set PROJECT_ID environment variable or ensure deployment-config.env exists."
fi

# Set the project context
log "Setting project context..."
gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project context"

# Confirmation prompt
echo ""
log_warning "This will delete ALL ML Pipeline Governance resources in project: $PROJECT_ID"
echo ""
echo "This includes:"
echo "- Compute instances and Hyperdisk ML volumes"
echo "- Vertex AI models and model registry entries"
echo "- Cloud Workflows"
echo "- Monitoring dashboards"
echo "- Cloud Storage buckets and data"
echo "- Service accounts"
echo "- Local configuration files"
echo ""
read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
if [[ ! "$REPLY" == "yes" ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo ""
log "Starting cleanup process..."

# Function to safely delete resources
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="$3"
    
    log "Deleting $resource_type: $resource_name"
    if eval "$delete_command" &>/dev/null; then
        log_success "Deleted $resource_type: $resource_name"
    else
        continue_on_error "Failed to delete $resource_type: $resource_name (may not exist)"
    fi
}

# Function to wait for operation completion
wait_for_operation() {
    local operation_type="$1"
    local check_command="$2"
    local max_wait="${3:-300}"  # Default 5 minutes
    local wait_time=0
    
    log "Waiting for $operation_type to complete..."
    while eval "$check_command" &>/dev/null && [[ $wait_time -lt $max_wait ]]; do
        sleep 10
        wait_time=$((wait_time + 10))
        log "Still waiting for $operation_type... (${wait_time}s/${max_wait}s)"
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log_warning "$operation_type did not complete within $max_wait seconds"
    else
        log_success "$operation_type completed"
    fi
}

# 1. Delete Cloud Workflows
log "Step 1: Removing Cloud Workflows..."
if [[ -n "${WORKFLOW_NAME:-}" ]]; then
    safe_delete "workflow" \
        "gcloud workflows delete '$WORKFLOW_NAME' --location='$REGION' --quiet" \
        "$WORKFLOW_NAME"
else
    # Try to find workflows by pattern
    WORKFLOW_LIST=$(gcloud workflows list --location="$REGION" --filter="name:ml-governance-workflow-" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$WORKFLOW_LIST" ]]; then
        while IFS= read -r workflow; do
            if [[ -n "$workflow" ]]; then
                WORKFLOW_NAME=$(basename "$workflow")
                safe_delete "workflow" \
                    "gcloud workflows delete '$WORKFLOW_NAME' --location='$REGION' --quiet" \
                    "$WORKFLOW_NAME"
            fi
        done <<< "$WORKFLOW_LIST"
    else
        log_warning "No workflows found to delete"
    fi
fi

# 2. Delete Vertex AI Models
log "Step 2: Removing Vertex AI models..."
if [[ -n "${MODEL_ID:-}" ]]; then
    safe_delete "Vertex AI model" \
        "gcloud ai models delete '$MODEL_ID' --region='$REGION' --quiet" \
        "$MODEL_ID"
else
    # Try to find models by pattern
    MODEL_LIST=$(gcloud ai models list --region="$REGION" --filter="displayName:governance-demo-model-" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$MODEL_LIST" ]]; then
        while IFS= read -r model; do
            if [[ -n "$model" ]]; then
                MODEL_ID=$(echo "$model" | cut -d'/' -f6)
                safe_delete "Vertex AI model" \
                    "gcloud ai models delete '$MODEL_ID' --region='$REGION' --quiet" \
                    "$MODEL_ID"
            fi
        done <<< "$MODEL_LIST"
    else
        log_warning "No Vertex AI models found to delete"
    fi
fi

# 3. Delete Compute Instances
log "Step 3: Removing compute instances..."
if [[ -n "${INSTANCE_NAME:-}" ]]; then
    safe_delete "compute instance" \
        "gcloud compute instances delete '$INSTANCE_NAME' --zone='$ZONE' --quiet" \
        "$INSTANCE_NAME"
    
    # Wait for instance deletion
    wait_for_operation "instance deletion" \
        "gcloud compute instances describe '$INSTANCE_NAME' --zone='$ZONE'" \
        120
else
    # Try to find instances by pattern or labels
    INSTANCE_LIST=$(gcloud compute instances list --filter="labels.purpose=ml-governance" --format="value(name,zone)" 2>/dev/null || echo "")
    if [[ -n "$INSTANCE_LIST" ]]; then
        while IFS= read -r instance_info; do
            if [[ -n "$instance_info" ]]; then
                INSTANCE_NAME=$(echo "$instance_info" | cut -d' ' -f1)
                INSTANCE_ZONE=$(echo "$instance_info" | cut -d' ' -f2)
                safe_delete "compute instance" \
                    "gcloud compute instances delete '$INSTANCE_NAME' --zone='$INSTANCE_ZONE' --quiet" \
                    "$INSTANCE_NAME"
            fi
        done <<< "$INSTANCE_LIST"
    else
        log_warning "No compute instances found to delete"
    fi
fi

# 4. Delete Hyperdisk ML Volumes
log "Step 4: Removing Hyperdisk ML volumes..."
if [[ -n "${HYPERDISK_NAME:-}" ]]; then
    safe_delete "Hyperdisk ML volume" \
        "gcloud compute disks delete '$HYPERDISK_NAME' --region='$REGION' --quiet" \
        "$HYPERDISK_NAME"
else
    # Try to find disks by pattern
    DISK_LIST=$(gcloud compute disks list --filter="name:ml-training-hyperdisk- AND type:hyperdisk-ml" --format="value(name,region)" 2>/dev/null || echo "")
    if [[ -n "$DISK_LIST" ]]; then
        while IFS= read -r disk_info; do
            if [[ -n "$disk_info" ]]; then
                DISK_NAME=$(echo "$disk_info" | cut -d' ' -f1)
                DISK_REGION=$(echo "$disk_info" | cut -d' ' -f2)
                safe_delete "Hyperdisk ML volume" \
                    "gcloud compute disks delete '$DISK_NAME' --region='$DISK_REGION' --quiet" \
                    "$DISK_NAME"
            fi
        done <<< "$DISK_LIST"
    else
        log_warning "No Hyperdisk ML volumes found to delete"
    fi
fi

# 5. Delete Monitoring Dashboards
log "Step 5: Removing monitoring dashboards..."
DASHBOARD_LIST=$(gcloud monitoring dashboards list --filter="displayName:'ML Governance Metrics Dashboard'" --format="value(name)" 2>/dev/null || echo "")
if [[ -n "$DASHBOARD_LIST" ]]; then
    while IFS= read -r dashboard; do
        if [[ -n "$dashboard" ]]; then
            safe_delete "monitoring dashboard" \
                "gcloud monitoring dashboards delete '$dashboard' --quiet" \
                "$dashboard"
        fi
    done <<< "$DASHBOARD_LIST"
else
    log_warning "No monitoring dashboards found to delete"
fi

# 6. Delete Cloud Storage Buckets
log "Step 6: Removing Cloud Storage buckets..."
if [[ -n "${BUCKET_NAME:-}" ]]; then
    log "Removing all objects from bucket: gs://$BUCKET_NAME"
    if gsutil -m rm -r "gs://$BUCKET_NAME" &>/dev/null; then
        log_success "Deleted bucket and contents: gs://$BUCKET_NAME"
    else
        continue_on_error "Failed to delete bucket: gs://$BUCKET_NAME (may not exist)"
    fi
else
    # Try to find buckets by pattern
    BUCKET_LIST=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "ml-training-data-" || echo "")
    if [[ -n "$BUCKET_LIST" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "$bucket" ]]; then
                log "Removing all objects from bucket: $bucket"
                if gsutil -m rm -r "$bucket" &>/dev/null; then
                    log_success "Deleted bucket and contents: $bucket"
                else
                    continue_on_error "Failed to delete bucket: $bucket"
                fi
            fi
        done <<< "$BUCKET_LIST"
    else
        log_warning "No training data buckets found to delete"
    fi
fi

# 7. Delete Service Accounts
log "Step 7: Removing service accounts..."
if [[ -n "${SERVICE_ACCOUNT_EMAIL:-}" ]]; then
    safe_delete "service account" \
        "gcloud iam service-accounts delete '$SERVICE_ACCOUNT_EMAIL' --quiet" \
        "$SERVICE_ACCOUNT_EMAIL"
else
    # Try to find service account by name pattern
    SA_LIST=$(gcloud iam service-accounts list --filter="displayName:'ML Governance Service Account'" --format="value(email)" 2>/dev/null || echo "")
    if [[ -n "$SA_LIST" ]]; then
        while IFS= read -r sa_email; do
            if [[ -n "$sa_email" ]]; then
                safe_delete "service account" \
                    "gcloud iam service-accounts delete '$sa_email' --quiet" \
                    "$sa_email"
            fi
        done <<< "$SA_LIST"
    else
        log_warning "No ML governance service accounts found to delete"
    fi
fi

# 8. Clean up local files
log "Step 8: Cleaning up local files..."
LOCAL_FILES=(
    "deployment-config.env"
    ".env"
    "governance-metrics.yaml"
    "ml-governance-workflow.yaml"
    "governance-policies.py"
    "model-lineage.py"
    "model-lineage-audit.json"
)

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        rm -f "$file"
        log_success "Removed local file: $file"
    fi
done

# 9. Optional: Disable APIs (commented out to avoid affecting other resources)
log "Step 9: API cleanup (optional)..."
log_warning "Skipping API disabling to avoid affecting other resources in the project"
log "If this was a dedicated project, you can manually disable the following APIs:"
echo "  - compute.googleapis.com"
echo "  - aiplatform.googleapis.com"
echo "  - workflows.googleapis.com"
echo "  - monitoring.googleapis.com"
echo "  - logging.googleapis.com"
echo "  - storage.googleapis.com"

# 10. Final verification
log "Step 10: Final verification..."

REMAINING_RESOURCES=()

# Check for remaining instances
if gcloud compute instances list --filter="labels.purpose=ml-governance" --format="value(name)" 2>/dev/null | grep -q .; then
    REMAINING_RESOURCES+=("Compute instances with ml-governance labels")
fi

# Check for remaining disks
if gcloud compute disks list --filter="type:hyperdisk-ml" --format="value(name)" 2>/dev/null | grep -q .; then
    REMAINING_RESOURCES+=("Hyperdisk ML volumes")
fi

# Check for remaining models
if gcloud ai models list --region="$REGION" --filter="displayName:governance-demo-model-" --format="value(name)" 2>/dev/null | grep -q .; then
    REMAINING_RESOURCES+=("Vertex AI models")
fi

# Check for remaining buckets
if gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -q "ml-training-data-"; then
    REMAINING_RESOURCES+=("ML training data buckets")
fi

# Check for remaining workflows
if gcloud workflows list --location="$REGION" --filter="name:ml-governance-workflow-" --format="value(name)" 2>/dev/null | grep -q .; then
    REMAINING_RESOURCES+=("ML governance workflows")
fi

if [[ ${#REMAINING_RESOURCES[@]} -eq 0 ]]; then
    log_success "All ML Pipeline Governance resources have been successfully cleaned up!"
else
    log_warning "Some resources may still remain:"
    for resource in "${REMAINING_RESOURCES[@]}"; do
        echo "  - $resource"
    done
    echo ""
    log_warning "You may need to delete these manually or run the script again"
fi

echo ""
echo "=============================================="
echo "Cleanup Summary"
echo "=============================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo ""

if [[ ${#REMAINING_RESOURCES[@]} -eq 0 ]]; then
    log_success "✅ Cleanup completed successfully!"
    echo ""
    log "All resources have been removed. The project $PROJECT_ID is now clean."
    
    if [[ "$PROJECT_ID" =~ ^ml-governance-[0-9]+$ ]]; then
        echo ""
        log_warning "This appears to be a dedicated project created for this recipe."
        log "Consider deleting the entire project if no longer needed:"
        echo "  gcloud projects delete $PROJECT_ID"
    fi
else
    log_warning "⚠️  Cleanup completed with warnings"
    echo ""
    log "Some resources may still exist and should be reviewed manually."
    log "Check the Google Cloud Console to verify all resources are deleted."
fi

echo ""
log "Cleanup process completed at $(date)"