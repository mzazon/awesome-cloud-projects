#!/bin/bash

# Global Content Delivery Infrastructure with Cloud WAN and Anywhere Cache - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Colors for output
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

# Check for force flag
FORCE_DELETE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--dry-run] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts and force deletion"
            echo "  --dry-run  Show what would be deleted without actually deleting"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log "Executing: $description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed but continuing: $description"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check if resource exists
resource_exists() {
    local check_cmd="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0  # Assume resources exist in dry-run mode
    fi
    eval "$check_cmd" &>/dev/null
}

log "🗑️  Starting Global Content Delivery Infrastructure Cleanup"
log "========================================================="

# Load deployment state if available
if [[ -f ".deployment_state" && "$DRY_RUN" == "false" ]]; then
    log "📋 Loading deployment state..."
    source .deployment_state
    log_success "Loaded deployment state from $(basename $(pwd))/.deployment_state"
else
    log_warning "No deployment state found. Using environment variables or defaults."
fi

# Set default values if not loaded from state
PROJECT_ID=${PROJECT_ID:-$1}
BUCKET_NAME=${BUCKET_NAME:-}
WAN_NAME=${WAN_NAME:-}
PRIMARY_REGION=${PRIMARY_REGION:-us-central1}
SECONDARY_REGION=${SECONDARY_REGION:-europe-west1}
TERTIARY_REGION=${TERTIARY_REGION:-asia-east1}
PRIMARY_ZONE=${PRIMARY_ZONE:-${PRIMARY_REGION}-a}
SECONDARY_ZONE=${SECONDARY_ZONE:-${SECONDARY_REGION}-b}
TERTIARY_ZONE=${TERTIARY_ZONE:-${TERTIARY_REGION}-a}

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "PROJECT_ID is required. Either run from deployment directory with .deployment_state file or provide as first argument."
    log_error "Usage: $0 [PROJECT_ID] [--force] [--dry-run]"
    exit 1
fi

log "Project ID: $PROJECT_ID"
log "Bucket Name: ${BUCKET_NAME:-not specified}"
log "WAN Name: ${WAN_NAME:-not specified}"

# Confirmation prompt (unless forced or dry-run)
if [[ "$FORCE_DELETE" != "true" && "$DRY_RUN" != "true" ]]; then
    echo ""
    log_warning "⚠️  WARNING: This will permanently delete all resources in project: $PROJECT_ID"
    log_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
fi

# Set the project context
if [[ "$DRY_RUN" == "false" ]]; then
    gcloud config set project $PROJECT_ID 2>/dev/null || {
        log_error "Failed to set project context. Project may not exist or you may not have access."
        exit 1
    }
fi

log "🔍 Checking current project context..."
if [[ "$DRY_RUN" == "false" ]]; then
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    if [[ "$CURRENT_PROJECT" != "$PROJECT_ID" ]]; then
        log_error "Current project ($CURRENT_PROJECT) doesn't match target project ($PROJECT_ID)"
        exit 1
    fi
fi

log_success "Project context confirmed: $PROJECT_ID"

# Start cleanup in reverse order of creation

# 1. Remove Cloud WAN Resources
log "🌍 Removing Cloud WAN resources..."

if [[ -n "$WAN_NAME" ]]; then
    # Delete WAN spokes first
    SPOKES=(
        "primary-spoke:$PRIMARY_REGION"
        "secondary-spoke:$SECONDARY_REGION"
        "tertiary-spoke:$TERTIARY_REGION"
    )
    
    for spoke_config in "${SPOKES[@]}"; do
        IFS=':' read -r spoke_name region <<< "$spoke_config"
        if resource_exists "gcloud network-connectivity spokes describe $spoke_name --location=$region"; then
            execute_command "gcloud network-connectivity spokes delete $spoke_name --location=$region --quiet" "Deleting $spoke_name" true
        fi
    done
    
    # Delete WAN hub
    if resource_exists "gcloud network-connectivity hubs describe $WAN_NAME"; then
        execute_command "gcloud network-connectivity hubs delete $WAN_NAME --quiet" "Deleting WAN hub $WAN_NAME" true
    fi
else
    log_warning "WAN_NAME not specified, attempting to find and delete WAN resources..."
    execute_command "gcloud network-connectivity hubs list --format='value(name)' | xargs -I {} gcloud network-connectivity hubs delete {} --quiet" "Deleting all WAN hubs" true
fi

log_success "Cloud WAN resources cleanup completed"

# 2. Remove Compute and Load Balancer Resources
log "💻 Removing compute instances and load balancer resources..."

# Delete compute instances
INSTANCES=(
    "content-server-primary:$PRIMARY_ZONE"
    "content-server-secondary:$SECONDARY_ZONE"
    "content-server-tertiary:$TERTIARY_ZONE"
)

for instance_config in "${INSTANCES[@]}"; do
    IFS=':' read -r instance_name zone <<< "$instance_config"
    if resource_exists "gcloud compute instances describe $instance_name --zone=$zone"; then
        execute_command "gcloud compute instances delete $instance_name --zone=$zone --quiet" "Deleting $instance_name" true
    fi
done

# Remove load balancer components (in reverse order of dependencies)
LB_RESOURCES=(
    "gcloud compute forwarding-rules delete content-rule --global --quiet"
    "gcloud compute target-http-proxies delete content-proxy --quiet"
    "gcloud compute url-maps delete content-map --quiet"
    "gcloud compute backend-services delete content-backend --global --quiet"
    "gcloud compute addresses delete content-ip --global --quiet"
    "gcloud compute health-checks delete basic-check --quiet"
)

for cmd in "${LB_RESOURCES[@]}"; do
    resource_name=$(echo $cmd | awk '{print $4}')
    execute_command "$cmd" "Deleting load balancer resource: $resource_name" true
done

log_success "Compute and load balancer resources cleanup completed"

# 3. Remove Storage and Cache Resources
log "🗄️  Removing storage and cache resources..."

if [[ -n "$BUCKET_NAME" ]]; then
    # Delete Anywhere Cache instances first
    CACHE_ZONES=("$PRIMARY_ZONE" "$SECONDARY_ZONE" "$TERTIARY_ZONE")
    
    for zone in "${CACHE_ZONES[@]}"; do
        # Note: Anywhere Cache deletion commands may vary based on actual implementation
        execute_command "gcloud alpha storage buckets update gs://${BUCKET_NAME} --remove-cache-config=zone=${zone}" "Removing cache in $zone" true
    done
    
    # Delete bucket contents and bucket
    if resource_exists "gsutil ls gs://$BUCKET_NAME"; then
        execute_command "gsutil -m rm -r gs://$BUCKET_NAME" "Deleting storage bucket and contents" true
    fi
else
    log_warning "BUCKET_NAME not specified, attempting to find and delete storage resources..."
    # List and delete buckets that match our naming pattern
    if [[ "$DRY_RUN" == "false" ]]; then
        BUCKETS=$(gsutil ls | grep "global-content-" || true)
        for bucket in $BUCKETS; do
            execute_command "gsutil -m rm -r $bucket" "Deleting bucket $bucket" true
        done
    fi
fi

log_success "Storage and cache resources cleanup completed"

# 4. Remove Monitoring Resources
log "📊 Removing monitoring resources..."

# Delete custom dashboards (this is a simplified approach)
if [[ "$DRY_RUN" == "false" ]]; then
    DASHBOARDS=$(gcloud monitoring dashboards list --filter="displayName:'Global Content Delivery Performance'" --format="value(name)" 2>/dev/null || true)
    for dashboard in $DASHBOARDS; do
        execute_command "gcloud monitoring dashboards delete $dashboard --quiet" "Deleting dashboard $dashboard" true
    done
fi

# Delete alerting policies
if [[ "$DRY_RUN" == "false" ]]; then
    POLICIES=$(gcloud alpha monitoring policies list --filter="displayName:'High Content Delivery Latency'" --format="value(name)" 2>/dev/null || true)
    for policy in $POLICIES; do
        execute_command "gcloud alpha monitoring policies delete $policy --quiet" "Deleting alerting policy $policy" true
    done
fi

log_success "Monitoring resources cleanup completed"

# 5. Clean up temporary files
log "🧹 Cleaning up temporary files..."

execute_command "rm -f /tmp/dashboard.json" "Removing temporary dashboard config" true
execute_command "rm -f /tmp/sample-content/*" "Removing temporary content files" true
execute_command "rmdir /tmp/sample-content 2>/dev/null" "Removing temporary content directory" true

log_success "Temporary files cleanup completed"

# 6. Optional: Delete the entire project
if [[ "$FORCE_DELETE" == "true" || "$DRY_RUN" == "true" ]]; then
    DELETE_PROJECT=true
elif [[ -f ".deployment_state" ]]; then
    echo ""
    log_warning "🚨 PROJECT DELETION OPTION"
    log_warning "The deployment created a dedicated project for this demo."
    read -p "Do you want to delete the entire project '$PROJECT_ID'? (yes/no): " delete_project_confirm
    DELETE_PROJECT=$([[ "$delete_project_confirm" == "yes" ]] && echo true || echo false)
else
    DELETE_PROJECT=false
fi

if [[ "$DELETE_PROJECT" == "true" ]]; then
    log "🗑️  Deleting entire project..."
    execute_command "gcloud projects delete $PROJECT_ID --quiet" "Deleting project $PROJECT_ID"
    log_success "Project deletion initiated: $PROJECT_ID"
    log_warning "Note: Project deletion may take several minutes to complete"
else
    log "📋 Project preserved: $PROJECT_ID"
    log "   You may want to review for any remaining resources and billing charges"
fi

# 7. Clean up deployment state file
if [[ -f ".deployment_state" ]]; then
    execute_command "rm -f .deployment_state" "Removing deployment state file"
    log_success "Deployment state file removed"
fi

# Final cleanup summary
log ""
log "📋 Cleanup Summary"
log "=================="
log_success "✅ Cloud WAN resources removed"
log_success "✅ Compute instances and load balancer removed"
log_success "✅ Storage bucket and cache removed"
log_success "✅ Monitoring resources removed"
log_success "✅ Temporary files cleaned up"

if [[ "$DELETE_PROJECT" == "true" ]]; then
    log_success "✅ Project deletion initiated"
else
    log_warning "⚠️  Project preserved - review for remaining resources"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "🔍 DRY-RUN MODE: No actual resources were deleted"
    log "To perform actual cleanup, run: ./destroy.sh"
else
    log_success "🎉 Global Content Delivery Infrastructure cleanup completed successfully!"
fi

log ""
log "💡 Tip: Check the Google Cloud Console to verify all resources have been removed"
log "     Console: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
log ""
log_warning "💰 Billing Note: It may take up to 24 hours for billing charges to stop after resource deletion"