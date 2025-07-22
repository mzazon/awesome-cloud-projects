#!/bin/bash

# Event-Driven Incident Response with Eventarc and Cloud Operations Suite - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Event-Driven Incident Response system resources

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: $DEFAULT_REGION)
    -z, --zone ZONE               GCP Zone (default: $DEFAULT_ZONE)
    -s, --suffix SUFFIX           Resource suffix (if known)
    -d, --dry-run                 Show what would be deleted without making changes
    -y, --yes                     Skip confirmation prompts
    -f, --force                   Force deletion of resources without confirmation
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --suffix abc123
    $0 --project-id my-project-123 --dry-run
    $0 --project-id my-project-123 --force --yes

NOTES:
    - This script will attempt to find and delete all resources created by the deploy script
    - If suffix is not provided, it will search for resources with common patterns
    - Use --dry-run to see what would be deleted before actually deleting
    - Use --force to skip individual resource confirmation prompts

EOF
}

# Parse command line arguments
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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -s|--suffix)
            RESOURCE_SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID:-}" ]]; then
    error "Project ID is required. Use --project-id or -p option."
    usage
    exit 1
fi

# Set defaults for optional parameters
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-$DEFAULT_ZONE}"
SERVICE_ACCOUNT="incident-response-sa"

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    exit 1
fi

# Check if project exists and is accessible
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    error "Project '$PROJECT_ID' does not exist or is not accessible."
    exit 1
fi

log "Prerequisites check completed successfully."

# Set project configuration
log "Setting project configuration..."
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# Function to confirm deletion
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "$FORCE_DELETE" == "true" || "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    read -p "Delete $resource_type '$resource_name'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to safely delete resource
safe_delete() {
    local delete_command="$1"
    local resource_type="$2"
    local resource_name="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete $resource_type: $resource_name"
        info "DRY RUN: Command: $delete_command"
        return 0
    fi
    
    if confirm_deletion "$resource_type" "$resource_name"; then
        log "Deleting $resource_type: $resource_name"
        if eval "$delete_command" &>/dev/null; then
            log "Successfully deleted $resource_type: $resource_name"
        else
            warn "Failed to delete $resource_type: $resource_name (may not exist)"
        fi
    else
        info "Skipping deletion of $resource_type: $resource_name"
    fi
}

# Find resources by pattern if suffix not provided
if [[ -z "${RESOURCE_SUFFIX:-}" ]]; then
    log "Discovering resources created by the incident response system..."
    
    # Try to find Cloud Functions with incident response patterns
    FUNCTIONS=$(gcloud functions list --regions="$REGION" --format="value(name)" 2>/dev/null | grep -E "(incident-triage|incident-notify)" | head -10)
    
    # Try to find Cloud Run services with incident response patterns
    SERVICES=$(gcloud run services list --regions="$REGION" --format="value(metadata.name)" 2>/dev/null | grep -E "(incident-remediate|incident-escalate)" | head -10)
    
    # Try to find Pub/Sub topics with incident response patterns
    TOPICS=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(incident-alerts|remediation-topic|escalation-topic|notification-topic)" | head -20)
    
    if [[ -n "$FUNCTIONS" || -n "$SERVICES" || -n "$TOPICS" ]]; then
        log "Found incident response resources:"
        [[ -n "$FUNCTIONS" ]] && echo "  Functions: $(echo "$FUNCTIONS" | tr '\n' ' ')"
        [[ -n "$SERVICES" ]] && echo "  Services: $(echo "$SERVICES" | tr '\n' ' ')"
        [[ -n "$TOPICS" ]] && echo "  Topics: $(echo "$TOPICS" | tr '\n' ' ' | sed 's|projects/[^/]*/topics/||g')"
    else
        warn "No incident response resources found. This may mean:"
        warn "  - Resources were already deleted"
        warn "  - Resources were created with different names"
        warn "  - Resources exist in different regions"
    fi
else
    log "Using provided suffix: $RESOURCE_SUFFIX"
fi

# Display cleanup configuration
log "Event-Driven Incident Response Cleanup Configuration"
echo "=================================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo "Resource Suffix: ${RESOURCE_SUFFIX:-'Auto-discovery mode'}"
echo "Dry Run: $DRY_RUN"
echo "Skip Confirmation: $SKIP_CONFIRMATION"
echo "Force Delete: $FORCE_DELETE"
echo "=================================================="

# Global confirmation prompt
if [[ "$SKIP_CONFIRMATION" == "false" && "$DRY_RUN" == "false" ]]; then
    echo ""
    warn "This will delete incident response resources in project: $PROJECT_ID"
    warn "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be deleted"
fi

# Start cleanup process
log "Starting cleanup of Event-Driven Incident Response resources..."

# 1. Delete Eventarc Triggers
log "Cleaning up Eventarc triggers..."
TRIGGERS=$(gcloud eventarc triggers list --locations="$REGION" --format="value(name)" 2>/dev/null | grep -E "(monitoring-alert-trigger|remediation-trigger|escalation-trigger)" || true)

if [[ -n "$TRIGGERS" ]]; then
    for trigger in $TRIGGERS; do
        safe_delete "gcloud eventarc triggers delete $trigger --location=$REGION --quiet" "Eventarc Trigger" "$trigger"
    done
else
    info "No Eventarc triggers found to delete."
fi

# 2. Delete Cloud Run Services
log "Cleaning up Cloud Run services..."
if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
    # If suffix is known, delete specific services
    for service in "incident-remediate-${RESOURCE_SUFFIX}" "incident-escalate-${RESOURCE_SUFFIX}"; do
        if gcloud run services describe "$service" --region="$REGION" &>/dev/null; then
            safe_delete "gcloud run services delete $service --region=$REGION --quiet" "Cloud Run Service" "$service"
        fi
    done
else
    # Auto-discovery mode
    SERVICES=$(gcloud run services list --regions="$REGION" --format="value(metadata.name)" 2>/dev/null | grep -E "(incident-remediate|incident-escalate)" || true)
    if [[ -n "$SERVICES" ]]; then
        for service in $SERVICES; do
            safe_delete "gcloud run services delete $service --region=$REGION --quiet" "Cloud Run Service" "$service"
        done
    else
        info "No Cloud Run services found to delete."
    fi
fi

# 3. Delete Cloud Functions
log "Cleaning up Cloud Functions..."
if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
    # If suffix is known, delete specific functions
    for function in "incident-triage-${RESOURCE_SUFFIX}" "incident-notify-${RESOURCE_SUFFIX}"; do
        if gcloud functions describe "$function" --region="$REGION" &>/dev/null; then
            safe_delete "gcloud functions delete $function --region=$REGION --quiet" "Cloud Function" "$function"
        fi
    done
else
    # Auto-discovery mode
    FUNCTIONS=$(gcloud functions list --regions="$REGION" --format="value(name)" 2>/dev/null | grep -E "(incident-triage|incident-notify)" || true)
    if [[ -n "$FUNCTIONS" ]]; then
        for function in $FUNCTIONS; do
            safe_delete "gcloud functions delete $function --region=$REGION --quiet" "Cloud Function" "$function"
        done
    else
        info "No Cloud Functions found to delete."
    fi
fi

# 4. Delete Monitoring Alert Policies
log "Cleaning up monitoring alert policies..."
if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
    # If suffix is known, delete specific policies
    POLICIES=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null | grep -E "(High CPU Utilization Alert - ${RESOURCE_SUFFIX}|High Error Rate Alert - ${RESOURCE_SUFFIX})" || true)
else
    # Auto-discovery mode - find policies with incident response patterns
    POLICIES=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null | grep -E "(High CPU Utilization Alert|High Error Rate Alert)" || true)
fi

if [[ -n "$POLICIES" ]]; then
    for policy in $POLICIES; do
        policy_name=$(gcloud alpha monitoring policies describe "$policy" --format="value(displayName)" 2>/dev/null || echo "$policy")
        safe_delete "gcloud alpha monitoring policies delete $policy --quiet" "Monitoring Policy" "$policy_name"
    done
else
    info "No monitoring alert policies found to delete."
fi

# 5. Delete Pub/Sub Topics
log "Cleaning up Pub/Sub topics..."
if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
    # If suffix is known, delete specific topics
    TOPICS_TO_DELETE=("incident-alerts-${RESOURCE_SUFFIX}" "remediation-topic" "escalation-topic" "notification-topic")
else
    # Auto-discovery mode
    TOPICS_TO_DELETE=($(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(incident-alerts|remediation-topic|escalation-topic|notification-topic)" | sed 's|projects/[^/]*/topics/||g' || true))
fi

if [[ ${#TOPICS_TO_DELETE[@]} -gt 0 ]]; then
    for topic in "${TOPICS_TO_DELETE[@]}"; do
        if [[ -n "$topic" ]] && gcloud pubsub topics describe "$topic" &>/dev/null; then
            safe_delete "gcloud pubsub topics delete $topic --quiet" "Pub/Sub Topic" "$topic"
        fi
    done
else
    info "No Pub/Sub topics found to delete."
fi

# 6. Remove IAM policy bindings and delete service account
log "Cleaning up service account and IAM bindings..."
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
    # Remove IAM policy bindings
    ROLES=("roles/monitoring.viewer" "roles/compute.instanceAdmin" "roles/pubsub.publisher" "roles/pubsub.subscriber" "roles/eventarc.eventReceiver")
    
    for role in "${ROLES[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY RUN: Would remove IAM binding for $role"
        else
            log "Removing IAM binding for $role"
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
                --role="$role" \
                --quiet &>/dev/null || warn "Failed to remove IAM binding for $role"
        fi
    done
    
    # Delete service account
    safe_delete "gcloud iam service-accounts delete ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com --quiet" "Service Account" "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
else
    info "Service account not found or already deleted."
fi

# 7. Check for any remaining resources
log "Checking for any remaining incident response resources..."

# Check for any Cloud Functions with incident patterns
REMAINING_FUNCTIONS=$(gcloud functions list --regions="$REGION" --format="value(name)" 2>/dev/null | grep -E "(incident|triage|notify)" || true)

# Check for any Cloud Run services with incident patterns
REMAINING_SERVICES=$(gcloud run services list --regions="$REGION" --format="value(metadata.name)" 2>/dev/null | grep -E "(incident|remediate|escalate)" || true)

# Check for any Pub/Sub topics with incident patterns
REMAINING_TOPICS=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(incident|remediation|escalation|notification)" || true)

# Check for any Eventarc triggers with incident patterns
REMAINING_TRIGGERS=$(gcloud eventarc triggers list --locations="$REGION" --format="value(name)" 2>/dev/null | grep -E "(incident|monitoring|remediation|escalation)" || true)

if [[ -n "$REMAINING_FUNCTIONS" || -n "$REMAINING_SERVICES" || -n "$REMAINING_TOPICS" || -n "$REMAINING_TRIGGERS" ]]; then
    warn "Some incident response resources may still exist:"
    [[ -n "$REMAINING_FUNCTIONS" ]] && echo "  Functions: $(echo "$REMAINING_FUNCTIONS" | tr '\n' ' ')"
    [[ -n "$REMAINING_SERVICES" ]] && echo "  Services: $(echo "$REMAINING_SERVICES" | tr '\n' ' ')"
    [[ -n "$REMAINING_TOPICS" ]] && echo "  Topics: $(echo "$REMAINING_TOPICS" | tr '\n' ' ' | sed 's|projects/[^/]*/topics/||g')"
    [[ -n "$REMAINING_TRIGGERS" ]] && echo "  Triggers: $(echo "$REMAINING_TRIGGERS" | tr '\n' ' ')"
    echo ""
    warn "You may need to delete these manually or run the script again with the correct suffix."
else
    log "No remaining incident response resources found."
fi

# Cleanup completion
if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN completed successfully!"
    log "Run without --dry-run to actually delete the resources."
else
    log "Event-Driven Incident Response system cleanup completed successfully!"
fi

echo ""
echo "=================================================="
echo "CLEANUP SUMMARY"
echo "=================================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo "Dry Run: $DRY_RUN"
echo ""
echo "Cleanup Actions Performed:"
echo "  ✅ Eventarc Triggers: Deleted all incident response triggers"
echo "  ✅ Cloud Run Services: Deleted remediation and escalation services"
echo "  ✅ Cloud Functions: Deleted triage and notification functions"
echo "  ✅ Monitoring Policies: Deleted alert policies"
echo "  ✅ Pub/Sub Topics: Deleted all incident response topics"
echo "  ✅ Service Account: Deleted incident response service account"
echo "  ✅ IAM Bindings: Removed all associated IAM policy bindings"
echo ""
if [[ "$DRY_RUN" == "false" ]]; then
    echo "All Event-Driven Incident Response resources have been successfully removed."
    echo "Your GCP project is now clean of incident response infrastructure."
else
    echo "This was a dry run - no actual resources were deleted."
    echo "Run the script without --dry-run to actually delete the resources."
fi
echo ""
echo "Note: Some resources may take a few minutes to be fully deleted."
echo "Check the Google Cloud Console to verify all resources are removed."
echo "=================================================="