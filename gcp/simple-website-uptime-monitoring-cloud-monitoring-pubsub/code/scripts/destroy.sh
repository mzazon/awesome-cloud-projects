#!/bin/bash
set -euo pipefail

# Simple Website Uptime Monitoring with Cloud Monitoring and Pub/Sub - Cleanup Script
# This script removes all resources created by the deployment script

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to load deployment state
load_deployment_state() {
    if [ -f "deployment-state.env" ]; then
        log "Loading deployment state from deployment-state.env..."
        source deployment-state.env
        success "Deployment state loaded"
    else
        warning "deployment-state.env not found, will prompt for values"
        return 1
    fi
}

# Function to prompt for missing values
prompt_for_values() {
    if [ -z "${PROJECT_ID:-}" ]; then
        read -p "Enter Google Cloud Project ID: " PROJECT_ID
    fi
    
    if [ -z "${REGION:-}" ]; then
        REGION="${REGION:-us-central1}"
    fi
    
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        read -p "Enter resource suffix (from deployment): " RANDOM_SUFFIX
    fi
    
    # Reconstruct resource names
    TOPIC_NAME="${TOPIC_NAME:-uptime-alerts-${RANDOM_SUFFIX}}"
    FUNCTION_NAME="${FUNCTION_NAME:-uptime-processor-${RANDOM_SUFFIX}}"
}

# Function to confirm destructive action
confirm_destruction() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [ "${FORCE:-}" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  About to delete $resource_type: $resource_name${NC}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping deletion of $resource_type: $resource_name"
        return 1
    fi
    return 0
}

# Function to delete resource with retry
delete_with_retry() {
    local delete_command="$1"
    local resource_description="$2"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Deleting $resource_description (attempt $attempt/$max_attempts)..."
        
        if eval "$delete_command" 2>/dev/null; then
            success "Deleted $resource_description"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            warning "Failed to delete $resource_description after $max_attempts attempts"
            return 1
        fi
        
        warning "Failed to delete $resource_description, retrying in 5 seconds..."
        sleep 5
        ((attempt++))
    done
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    eval "$check_command" >/dev/null 2>&1
}

# Main cleanup function
main() {
    log "Starting cleanup of Simple Website Uptime Monitoring solution..."
    
    # Check prerequisites
    log "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK first."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Load deployment state or prompt for values
    if ! load_deployment_state; then
        log "Prompting for deployment values..."
        prompt_for_values
    fi
    
    # Validate required variables
    if [ -z "${PROJECT_ID:-}" ] || [ -z "${RANDOM_SUFFIX:-}" ]; then
        error "Missing required variables: PROJECT_ID and RANDOM_SUFFIX"
        exit 1
    fi
    
    # Set gcloud configuration
    log "Setting gcloud configuration..."
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "${REGION:-us-central1}"
    
    log "Configuration:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: ${REGION:-us-central1}"
    log "  Resource Suffix: $RANDOM_SUFFIX"
    log "  Topic Name: $TOPIC_NAME"
    log "  Function Name: $FUNCTION_NAME"
    
    # Show final confirmation
    if [ "${FORCE:-}" != "true" ]; then
        echo
        echo -e "${RED}⚠️  WARNING: This will permanently delete all monitoring resources!${NC}"
        echo -e "${RED}⚠️  This action cannot be undone!${NC}"
        echo
        read -p "Type 'DELETE' to confirm permanent resource deletion: " confirmation
        if [ "$confirmation" != "DELETE" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Step 1: Delete alerting policy
    log "Deleting alerting policy..."
    if [ -n "${POLICY_ID:-}" ]; then
        if confirm_destruction "alerting policy" "$POLICY_ID"; then
            delete_with_retry \
                "gcloud alpha monitoring policies delete '$POLICY_ID' --project='$PROJECT_ID' --quiet" \
                "alerting policy"
        fi
    else
        # Find and delete alerting policies
        POLICIES=$(gcloud alpha monitoring policies list \
            --project="$PROJECT_ID" \
            --filter="displayName:'Website Uptime Alert Policy'" \
            --format="value(name)" 2>/dev/null || true)
        
        for policy in $POLICIES; do
            if confirm_destruction "alerting policy" "$policy"; then
                delete_with_retry \
                    "gcloud alpha monitoring policies delete '$policy' --project='$PROJECT_ID' --quiet" \
                    "alerting policy $policy"
            fi
        done
    fi
    
    # Step 2: Delete notification channels
    log "Deleting notification channels..."
    if [ -n "${CHANNEL_ID:-}" ]; then
        if confirm_destruction "notification channel" "$CHANNEL_ID"; then
            delete_with_retry \
                "gcloud alpha monitoring channels delete '$CHANNEL_ID' --project='$PROJECT_ID' --quiet" \
                "notification channel"
        fi
    else
        # Find and delete Pub/Sub notification channels
        CHANNELS=$(gcloud alpha monitoring channels list \
            --project="$PROJECT_ID" \
            --filter="type=pubsub AND displayName:'Uptime Alerts Pub/Sub Channel'" \
            --format="value(name)" 2>/dev/null || true)
        
        for channel in $CHANNELS; do
            if confirm_destruction "notification channel" "$channel"; then
                delete_with_retry \
                    "gcloud alpha monitoring channels delete '$channel' --project='$PROJECT_ID' --quiet" \
                    "notification channel $channel"
            fi
        done
    fi
    
    # Step 3: Delete uptime checks
    log "Deleting uptime checks..."
    UPTIME_CHECKS=$(gcloud monitoring uptime list \
        --project="$PROJECT_ID" \
        --filter="displayName:uptime-check-*-${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -z "$UPTIME_CHECKS" ]; then
        # Fallback: delete all uptime checks with pattern
        UPTIME_CHECKS=$(gcloud monitoring uptime list \
            --project="$PROJECT_ID" \
            --filter="displayName:uptime-check-*" \
            --format="value(name)" 2>/dev/null || true)
    fi
    
    for check in $UPTIME_CHECKS; do
        CHECK_DISPLAY_NAME=$(gcloud monitoring uptime describe "$check" \
            --project="$PROJECT_ID" \
            --format="value(displayName)" 2>/dev/null || echo "$check")
        
        if confirm_destruction "uptime check" "$CHECK_DISPLAY_NAME"; then
            delete_with_retry \
                "gcloud monitoring uptime delete '$check' --project='$PROJECT_ID' --quiet" \
                "uptime check $CHECK_DISPLAY_NAME"
        fi
    done
    
    # Step 4: Delete Cloud Function
    log "Deleting Cloud Function..."
    if resource_exists "gcloud functions describe '$FUNCTION_NAME' --region='${REGION:-us-central1}' --project='$PROJECT_ID'"; then
        if confirm_destruction "Cloud Function" "$FUNCTION_NAME"; then
            delete_with_retry \
                "gcloud functions delete '$FUNCTION_NAME' --region='${REGION:-us-central1}' --project='$PROJECT_ID' --quiet" \
                "Cloud Function $FUNCTION_NAME"
        fi
    else
        warning "Cloud Function $FUNCTION_NAME not found or already deleted"
    fi
    
    # Step 5: Delete Pub/Sub topic
    log "Deleting Pub/Sub topic..."
    if resource_exists "gcloud pubsub topics describe '$TOPIC_NAME' --project='$PROJECT_ID'"; then
        if confirm_destruction "Pub/Sub topic" "$TOPIC_NAME"; then
            delete_with_retry \
                "gcloud pubsub topics delete '$TOPIC_NAME' --project='$PROJECT_ID' --quiet" \
                "Pub/Sub topic $TOPIC_NAME"
        fi
    else
        warning "Pub/Sub topic $TOPIC_NAME not found or already deleted"
    fi
    
    # Step 6: Clean up local files
    log "Cleaning up local files..."
    local files_to_remove=(
        "uptime-function/"
        "notification-channel.json"
        "alerting-policy.json"
        "deployment-state.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            if confirm_destruction "local file/directory" "$file"; then
                rm -rf "$file"
                success "Removed local file/directory: $file"
            fi
        fi
    done
    
    # Step 7: Final validation
    log "Performing final validation..."
    
    # Check if resources are actually deleted
    local remaining_resources=0
    
    if resource_exists "gcloud pubsub topics describe '$TOPIC_NAME' --project='$PROJECT_ID'"; then
        warning "Pub/Sub topic still exists: $TOPIC_NAME"
        ((remaining_resources++))
    fi
    
    if resource_exists "gcloud functions describe '$FUNCTION_NAME' --region='${REGION:-us-central1}' --project='$PROJECT_ID'"; then
        warning "Cloud Function still exists: $FUNCTION_NAME"
        ((remaining_resources++))
    fi
    
    REMAINING_UPTIME_CHECKS=$(gcloud monitoring uptime list \
        --project="$PROJECT_ID" \
        --filter="displayName:uptime-check-*-${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [ "$REMAINING_UPTIME_CHECKS" -gt 0 ]; then
        warning "$REMAINING_UPTIME_CHECKS uptime checks still exist"
        ((remaining_resources++))
    fi
    
    # Clean up environment variables
    log "Cleaning up environment variables..."
    unset PROJECT_ID REGION ZONE NOTIFICATION_EMAIL RANDOM_SUFFIX
    unset TOPIC_NAME FUNCTION_NAME CHANNEL_ID POLICY_ID
    success "Environment variables cleaned up"
    
    log ""
    if [ $remaining_resources -eq 0 ]; then
        success "🎉 Cleanup completed successfully!"
        log "All monitoring resources have been removed."
    else
        warning "⚠️  Cleanup completed with $remaining_resources remaining resources"
        log "Please check the Google Cloud Console to verify resource deletion."
        log "Some resources may take additional time to be fully removed."
    fi
    
    log ""
    log "Summary of cleanup actions:"
    log "  • Deleted alerting policy and notification channels"
    log "  • Removed all uptime checks"
    log "  • Deleted Cloud Function: $FUNCTION_NAME"
    log "  • Removed Pub/Sub topic: $TOPIC_NAME"
    log "  • Cleaned up local files and environment variables"
    log ""
    log "Note: Billing stops immediately after resource deletion."
    log "Check Cloud Monitoring console to verify all resources are removed."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE=true
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force          Skip confirmation prompts"
            echo "  --project ID     Specify project ID"
            echo "  --suffix SUFFIX  Specify resource suffix"
            echo "  --region REGION  Specify region (default: us-central1)"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "This script will delete all resources created by the deployment script."
            echo "Use with caution as this action cannot be undone."
            exit 0
            ;;
        *)
            warning "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"