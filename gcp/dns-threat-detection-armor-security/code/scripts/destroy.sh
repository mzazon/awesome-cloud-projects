#!/bin/bash

# DNS Threat Detection with Cloud Armor and Security Center - Cleanup Script
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
LOG_FILE="${SCRIPT_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output to both console and log file
exec > >(tee -a "$LOG_FILE")
exec 2>&1

log "Starting DNS Threat Detection cleanup"
log "Log file: $LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to get current project configuration
get_current_config() {
    log "Getting current Google Cloud configuration..."
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    ZONE=$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")
    
    if [ -z "$PROJECT_ID" ]; then
        error "No project configured. Please set a project with 'gcloud config set project PROJECT_ID'"
    fi
    
    log "Current configuration:"
    log "  PROJECT_ID: $PROJECT_ID"
    log "  REGION: $REGION"
    log "  ZONE: $ZONE"
    
    # Get organization ID if available
    ORG_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
    if [ -n "$ORG_ID" ]; then
        log "  ORG_ID: $ORG_ID"
    else
        warn "No organization found"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo
    warn "⚠️  DANGER ZONE ⚠️"
    warn "This script will DELETE the following resources:"
    echo "  • All Cloud Functions"
    echo "  • All Cloud Armor security policies (with 'dns-protection-policy' prefix)"
    echo "  • All DNS policies and managed zones (with 'dns-security-policy' and 'security-zone' prefix)"
    echo "  • All Pub/Sub topics and subscriptions (with 'dns-security-alerts' prefix)"
    echo "  • All Security Command Center notifications (with 'dns-threat-export' prefix)"
    echo "  • All custom log metrics (dns_malware_queries)"
    echo "  • All monitoring alert policies (DNS Threat Detection)"
    echo "  • Optionally: The entire project"
    echo
    warn "Project: $PROJECT_ID"
    echo

    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Do you want to delete the entire project '$PROJECT_ID'? (type 'yes' to delete project, 'no' to keep project): " delete_project
    if [ "$delete_project" = "yes" ]; then
        DELETE_PROJECT=true
        warn "Project deletion confirmed. This will remove ALL resources in the project."
    else
        DELETE_PROJECT=false
        log "Project will be kept, only specific resources will be deleted."
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # List and delete Cloud Functions that match our naming pattern
    local functions=$(gcloud functions list --filter="name:dns-security-processor" --format="value(name)" --regions="$REGION" 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        for func in $functions; do
            info "Deleting Cloud Function: $func"
            if gcloud functions delete "$func" --region="$REGION" --quiet 2>/dev/null; then
                log "  ✅ Cloud Function $func deleted"
            else
                warn "  ❌ Failed to delete Cloud Function $func"
            fi
        done
    else
        info "No Cloud Functions found to delete"
    fi
    
    log "Cloud Functions cleanup completed ✅"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    local subscriptions=$(gcloud pubsub subscriptions list --filter="name:dns-alert-processor" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$subscriptions" ]; then
        for sub in $subscriptions; do
            info "Deleting Pub/Sub subscription: $(basename "$sub")"
            if gcloud pubsub subscriptions delete "$(basename "$sub")" --quiet 2>/dev/null; then
                log "  ✅ Subscription $(basename "$sub") deleted"
            else
                warn "  ❌ Failed to delete subscription $(basename "$sub")"
            fi
        done
    else
        info "No Pub/Sub subscriptions found to delete"
    fi
    
    # Delete topics
    local topics=$(gcloud pubsub topics list --filter="name:dns-security-alerts" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$topics" ]; then
        for topic in $topics; do
            info "Deleting Pub/Sub topic: $(basename "$topic")"
            if gcloud pubsub topics delete "$(basename "$topic")" --quiet 2>/dev/null; then
                log "  ✅ Topic $(basename "$topic") deleted"
            else
                warn "  ❌ Failed to delete topic $(basename "$topic")"
            fi
        done
    else
        info "No Pub/Sub topics found to delete"
    fi
    
    log "Pub/Sub resources cleanup completed ✅"
}

# Function to delete Security Command Center notifications
delete_scc_notifications() {
    log "Deleting Security Command Center notifications..."
    
    if [ -z "${ORG_ID:-}" ]; then
        warn "No organization ID available. Skipping Security Command Center cleanup."
        return 0
    fi
    
    # List and delete SCC notifications
    local notifications=$(gcloud scc notifications list --organization="$ORG_ID" --filter="name:dns-threat-export" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$notifications" ]; then
        for notification in $notifications; do
            local notification_id=$(basename "$notification")
            info "Deleting Security Command Center notification: $notification_id"
            if gcloud scc notifications delete "$notification_id" --organization="$ORG_ID" --quiet 2>/dev/null; then
                log "  ✅ SCC notification $notification_id deleted"
            else
                warn "  ❌ Failed to delete SCC notification $notification_id"
            fi
        done
    else
        info "No Security Command Center notifications found to delete"
    fi
    
    log "Security Command Center notifications cleanup completed ✅"
}

# Function to delete Cloud Armor resources
delete_cloud_armor_resources() {
    log "Deleting Cloud Armor security policies..."
    
    # List and delete security policies
    local policies=$(gcloud compute security-policies list --filter="name:dns-protection-policy" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            info "Deleting Cloud Armor security policy: $policy"
            if gcloud compute security-policies delete "$policy" --quiet 2>/dev/null; then
                log "  ✅ Security policy $policy deleted"
            else
                warn "  ❌ Failed to delete security policy $policy"
            fi
        done
    else
        info "No Cloud Armor security policies found to delete"
    fi
    
    log "Cloud Armor resources cleanup completed ✅"
}

# Function to delete DNS resources
delete_dns_resources() {
    log "Deleting DNS resources..."
    
    # Delete DNS managed zones first
    local zones=$(gcloud dns managed-zones list --filter="name:security-zone" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$zones" ]; then
        for zone in $zones; do
            info "Deleting DNS managed zone: $zone"
            if gcloud dns managed-zones delete "$zone" --quiet 2>/dev/null; then
                log "  ✅ DNS zone $zone deleted"
            else
                warn "  ❌ Failed to delete DNS zone $zone"
            fi
        done
    else
        info "No DNS managed zones found to delete"
    fi
    
    # Delete DNS policies
    local policies=$(gcloud dns policies list --filter="name:dns-security-policy" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            info "Deleting DNS policy: $policy"
            if gcloud dns policies delete "$policy" --quiet 2>/dev/null; then
                log "  ✅ DNS policy $policy deleted"
            else
                warn "  ❌ Failed to delete DNS policy $policy"
            fi
        done
    else
        info "No DNS policies found to delete"
    fi
    
    log "DNS resources cleanup completed ✅"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete custom log metrics
    info "Deleting custom log metrics..."
    if gcloud logging metrics delete dns_malware_queries --quiet 2>/dev/null; then
        log "  ✅ Custom log metric dns_malware_queries deleted"
    else
        warn "  ❌ Failed to delete custom log metric dns_malware_queries (may not exist)"
    fi
    
    # Delete monitoring alert policies
    info "Checking for monitoring alert policies..."
    local policies=$(gcloud alpha monitoring policies list --filter='displayName:"DNS Threat Detection Alert"' --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            local policy_id=$(basename "$policy")
            info "Deleting monitoring alert policy: $policy_id"
            if gcloud alpha monitoring policies delete "$policy_id" --quiet 2>/dev/null; then
                log "  ✅ Alert policy $policy_id deleted"
            else
                warn "  ❌ Failed to delete alert policy $policy_id"
            fi
        done
    else
        info "No monitoring alert policies found to delete"
    fi
    
    log "Monitoring resources cleanup completed ✅"
}

# Function to delete the entire project
delete_project() {
    if [ "$DELETE_PROJECT" = true ]; then
        log "Deleting entire project..."
        
        warn "⚠️  FINAL WARNING: About to delete project '$PROJECT_ID'"
        warn "This action is IRREVERSIBLE and will remove ALL resources in the project."
        echo
        read -p "Type the project ID '$PROJECT_ID' to confirm deletion: " project_confirmation
        
        if [ "$project_confirmation" = "$PROJECT_ID" ]; then
            info "Deleting project $PROJECT_ID..."
            if gcloud projects delete "$PROJECT_ID" --quiet 2>/dev/null; then
                log "  ✅ Project $PROJECT_ID deletion initiated"
                log "  ⏳ Project deletion may take several minutes to complete"
            else
                error "  ❌ Failed to delete project $PROJECT_ID"
            fi
        else
            warn "Project ID confirmation failed. Project deletion cancelled."
            log "Individual resources have been deleted, but project remains."
        fi
    else
        log "Keeping project $PROJECT_ID as requested"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    # Check Cloud Functions
    local remaining_functions=$(gcloud functions list --filter="name:dns-security-processor" --format="value(name)" --regions="$REGION" 2>/dev/null | wc -l)
    info "Remaining Cloud Functions: $remaining_functions"
    
    # Check Pub/Sub topics
    local remaining_topics=$(gcloud pubsub topics list --filter="name:dns-security-alerts" --format="value(name)" 2>/dev/null | wc -l)
    info "Remaining Pub/Sub topics: $remaining_topics"
    
    # Check Cloud Armor policies
    local remaining_policies=$(gcloud compute security-policies list --filter="name:dns-protection-policy" --format="value(name)" 2>/dev/null | wc -l)
    info "Remaining Cloud Armor policies: $remaining_policies"
    
    # Check DNS resources
    local remaining_zones=$(gcloud dns managed-zones list --filter="name:security-zone" --format="value(name)" 2>/dev/null | wc -l)
    local remaining_dns_policies=$(gcloud dns policies list --filter="name:dns-security-policy" --format="value(name)" 2>/dev/null | wc -l)
    info "Remaining DNS zones: $remaining_zones"
    info "Remaining DNS policies: $remaining_dns_policies"
    
    # Summary
    local total_remaining=$((remaining_functions + remaining_topics + remaining_policies + remaining_zones + remaining_dns_policies))
    
    if [ "$total_remaining" -eq 0 ]; then
        log "All targeted resources have been successfully removed ✅"
    else
        warn "Some resources may still exist. Please check manually if needed."
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup completed! 🧹"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo
    echo "=== REMOVED RESOURCES ==="
    echo "• Cloud Functions (dns-security-processor)"
    echo "• Pub/Sub topics and subscriptions (dns-security-alerts-*)"
    echo "• Cloud Armor security policies (dns-protection-policy-*)"
    echo "• DNS policies and managed zones (dns-security-policy-*, security-zone-*)"
    echo "• Custom log metrics (dns_malware_queries)"
    echo "• Monitoring alert policies (DNS Threat Detection)"
    if [ -n "${ORG_ID:-}" ]; then
        echo "• Security Command Center notifications (dns-threat-export-*)"
    fi
    if [ "$DELETE_PROJECT" = true ]; then
        echo "• Entire project: $PROJECT_ID"
    fi
    echo
    if [ "$DELETE_PROJECT" = false ]; then
        echo "=== REMAINING RESOURCES ==="
        echo "• Project: $PROJECT_ID (kept as requested)"
        echo "• Any resources not created by this recipe"
        echo
        echo "=== NEXT STEPS ==="
        echo "• Verify all resources are removed from Cloud Console"
        echo "• Check for any remaining charges in billing"
        echo "• Consider disabling APIs if no longer needed"
    else
        echo "=== PROJECT DELETION ==="
        echo "• Project deletion initiated and may take several minutes"
        echo "• All resources in the project will be removed"
        echo "• Billing will stop once deletion is complete"
    fi
    echo
    log "Log file saved to: $LOG_FILE"
}

# Function to handle safe exit
safe_exit() {
    local exit_code=${1:-0}
    if [ $exit_code -eq 0 ]; then
        log "✅ DNS Threat Detection cleanup completed successfully!"
    else
        error "❌ Cleanup encountered errors. Check log file: $LOG_FILE"
    fi
    exit $exit_code
}

# Main execution
main() {
    log "🧹 Starting DNS Threat Detection cleanup"
    
    check_prerequisites
    get_current_config
    confirm_deletion
    
    if [ "$DELETE_PROJECT" = false ]; then
        delete_cloud_functions
        delete_pubsub_resources
        delete_scc_notifications
        delete_cloud_armor_resources
        delete_dns_resources
        delete_monitoring_resources
        verify_cleanup
    fi
    
    delete_project
    display_summary
    safe_exit 0
}

# Handle script interruption
trap 'error "Script interrupted by user"; safe_exit 1' INT TERM

# Run main function
main "$@"