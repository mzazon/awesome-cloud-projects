#!/bin/bash

# Log-Driven Automation with Cloud Logging and Pub/Sub - Cleanup Script
# This script removes all resources created by the deployment script

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

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for script interruption
cleanup() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup failed. Check $ERROR_LOG for details."
    fi
}
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove log-driven automation infrastructure resources.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -s, --suffix SUFFIX          Resource name suffix (required if not using --all)
    --all                        Remove all log-automation resources (requires --confirm)
    --confirm                    Confirm destructive actions
    --dry-run                    Show what would be removed without making changes
    --force                      Skip confirmation prompts (dangerous)
    -h, --help                   Show this help message

EXAMPLES:
    $0 --project-id my-project --suffix abc123 --confirm
    $0 --project-id my-project --all --confirm
    $0 --project-id my-project --suffix abc123 --dry-run

SAFETY NOTE:
    This script will permanently delete cloud resources. Use --dry-run first
    to review what will be removed. Always specify --confirm for actual deletion.

EOF
}

# Parse command line arguments
parse_args() {
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
            -s|--suffix)
                SUFFIX="$2"
                shift 2
                ;;
            --all)
                REMOVE_ALL=true
                shift
                ;;
            --confirm)
                CONFIRMED=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Set default values
PROJECT_ID=""
REGION="us-central1"
SUFFIX=""
REMOVE_ALL=false
CONFIRMED=false
DRY_RUN=false
FORCE=false

# Parse arguments
parse_args "$@"

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    error "Project ID is required. Use --project-id or -p flag."
fi

if [[ "$REMOVE_ALL" == "false" && -z "$SUFFIX" ]]; then
    error "Either --suffix or --all must be specified."
fi

if [[ "$DRY_RUN" == "false" && "$CONFIRMED" == "false" && "$FORCE" == "false" ]]; then
    error "Destructive operations require --confirm flag or use --dry-run to preview."
fi

# Set resource names based on suffix or pattern matching
if [[ "$REMOVE_ALL" == "true" ]]; then
    TOPIC_PATTERN="incident-automation-*"
    FUNCTION_PATTERN="alert-processor-*|auto-remediate-*"
    SINK_PATTERN="automation-sink-*"
else
    TOPIC_NAME="incident-automation-${SUFFIX}"
    ALERT_FUNCTION_NAME="alert-processor-${SUFFIX}"
    REMEDIATION_FUNCTION_NAME="auto-remediate-${SUFFIX}"
    LOG_SINK_NAME="automation-sink-${SUFFIX}"
fi

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error "Project '$PROJECT_ID' does not exist or is not accessible."
    fi
    
    log "Prerequisites check passed"
}

# Function to configure gcloud
configure_gcloud() {
    info "Configuring gcloud..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would configure gcloud with project: $PROJECT_ID, region: $REGION"
        return
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log "gcloud configured successfully"
}

# Function to confirm destructive actions
confirm_destruction() {
    if [[ "$DRY_RUN" == "true" || "$FORCE" == "true" ]]; then
        return
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    warn "This will permanently delete the following resources:"
    
    if [[ "$REMOVE_ALL" == "true" ]]; then
        warn "  • ALL log-automation Pub/Sub topics and subscriptions"
        warn "  • ALL log-automation Cloud Functions"
        warn "  • ALL log-automation log sinks"
        warn "  • ALL log-automation log-based metrics"
        warn "  • ALL related Cloud Monitoring policies"
    else
        warn "  • Pub/Sub Topic: $TOPIC_NAME"
        warn "  • Cloud Functions: $ALERT_FUNCTION_NAME, $REMEDIATION_FUNCTION_NAME"
        warn "  • Log Sink: $LOG_SINK_NAME"
        warn "  • Log-based Metrics: error_rate_metric, exception_pattern_metric, latency_anomaly_metric"
        warn "  • Related Cloud Monitoring policies"
    fi
    
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Operation cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Function to remove Cloud Functions
remove_functions() {
    info "Removing Cloud Functions..."
    
    if [[ "$REMOVE_ALL" == "true" ]]; then
        # Get all matching functions
        local functions
        mapfile -t functions < <(gcloud functions list --format="value(name)" --filter="name~'(alert-processor-|auto-remediate-)'" 2>/dev/null || true)
        
        if [[ ${#functions[@]} -eq 0 ]]; then
            info "No log-automation functions found"
            return
        fi
        
        for func in "${functions[@]}"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete function: $func"
            else
                info "Deleting function: $func..."
                if gcloud functions delete "$func" --quiet 2>/dev/null; then
                    log "✅ Function '$func' deleted"
                else
                    warn "Failed to delete function '$func' (may not exist)"
                fi
            fi
        done
    else
        # Remove specific functions
        for func in "$ALERT_FUNCTION_NAME" "$REMEDIATION_FUNCTION_NAME"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete function: $func"
            else
                info "Deleting function: $func..."
                if gcloud functions delete "$func" --quiet 2>/dev/null; then
                    log "✅ Function '$func' deleted"
                else
                    warn "Function '$func' not found (may already be deleted)"
                fi
            fi
        done
    fi
}

# Function to remove Cloud Monitoring resources
remove_monitoring_resources() {
    info "Removing Cloud Monitoring alerting policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete monitoring policies and log-based metrics"
        return
    fi
    
    # Delete alerting policies related to log automation
    local policies
    mapfile -t policies < <(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName~'(High Error Rate Alert|High Latency Alert|Critical Log Pattern Alert)'" 2>/dev/null || true)
    
    for policy in "${policies[@]}"; do
        if [[ -n "$policy" ]]; then
            info "Deleting alerting policy: $policy..."
            if gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null; then
                log "✅ Alerting policy deleted"
            else
                warn "Failed to delete alerting policy"
            fi
        fi
    done
    
    # Delete log-based metrics
    local metrics=("error_rate_metric" "exception_pattern_metric" "latency_anomaly_metric")
    for metric in "${metrics[@]}"; do
        info "Deleting log-based metric: $metric..."
        if gcloud logging metrics delete "$metric" --quiet 2>/dev/null; then
            log "✅ Log-based metric '$metric' deleted"
        else
            warn "Log-based metric '$metric' not found (may already be deleted)"
        fi
    done
}

# Function to remove log sinks
remove_log_sinks() {
    info "Removing log sinks..."
    
    if [[ "$REMOVE_ALL" == "true" ]]; then
        # Get all matching sinks
        local sinks
        mapfile -t sinks < <(gcloud logging sinks list --format="value(name)" --filter="name~'automation-sink-'" 2>/dev/null || true)
        
        if [[ ${#sinks[@]} -eq 0 ]]; then
            info "No log-automation sinks found"
            return
        fi
        
        for sink in "${sinks[@]}"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete log sink: $sink"
            else
                info "Deleting log sink: $sink..."
                if gcloud logging sinks delete "$sink" --quiet 2>/dev/null; then
                    log "✅ Log sink '$sink' deleted"
                else
                    warn "Failed to delete log sink '$sink'"
                fi
            fi
        done
    else
        # Remove specific sink
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete log sink: $LOG_SINK_NAME"
        else
            info "Deleting log sink: $LOG_SINK_NAME..."
            if gcloud logging sinks delete "$LOG_SINK_NAME" --quiet 2>/dev/null; then
                log "✅ Log sink '$LOG_SINK_NAME' deleted"
            else
                warn "Log sink '$LOG_SINK_NAME' not found (may already be deleted)"
            fi
        fi
    fi
}

# Function to remove Pub/Sub resources
remove_pubsub_resources() {
    info "Removing Pub/Sub subscriptions and topics..."
    
    if [[ "$REMOVE_ALL" == "true" ]]; then
        # Remove all subscriptions first
        local subscriptions
        mapfile -t subscriptions < <(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep -E "(alert-subscription|remediation-subscription)" || true)
        
        for sub in "${subscriptions[@]}"; do
            if [[ -n "$sub" ]]; then
                local sub_name
                sub_name=$(basename "$sub")
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would delete subscription: $sub_name"
                else
                    info "Deleting subscription: $sub_name..."
                    if gcloud pubsub subscriptions delete "$sub_name" --quiet 2>/dev/null; then
                        log "✅ Subscription '$sub_name' deleted"
                    else
                        warn "Failed to delete subscription '$sub_name'"
                    fi
                fi
            fi
        done
        
        # Remove all matching topics
        local topics
        mapfile -t topics < <(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep "incident-automation-" || true)
        
        for topic in "${topics[@]}"; do
            if [[ -n "$topic" ]]; then
                local topic_name
                topic_name=$(basename "$topic")
                if [[ "$DRY_RUN" == "true" ]]; then
                    info "[DRY RUN] Would delete topic: $topic_name"
                else
                    info "Deleting topic: $topic_name..."
                    if gcloud pubsub topics delete "$topic_name" --quiet 2>/dev/null; then
                        log "✅ Topic '$topic_name' deleted"
                    else
                        warn "Failed to delete topic '$topic_name'"
                    fi
                fi
            fi
        done
    else
        # Remove specific subscriptions
        for sub in "alert-subscription" "remediation-subscription"; do
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete subscription: $sub"
            else
                info "Deleting subscription: $sub..."
                if gcloud pubsub subscriptions delete "$sub" --quiet 2>/dev/null; then
                    log "✅ Subscription '$sub' deleted"
                else
                    warn "Subscription '$sub' not found (may already be deleted)"
                fi
            fi
        done
        
        # Remove specific topic
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete topic: $TOPIC_NAME"
        else
            info "Deleting topic: $TOPIC_NAME..."
            if gcloud pubsub topics delete "$TOPIC_NAME" --quiet 2>/dev/null; then
                log "✅ Topic '$TOPIC_NAME' deleted"
            else
                warn "Topic '$TOPIC_NAME' not found (may already be deleted)"
            fi
        fi
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up temporary files"
        return
    fi
    
    # Remove any temporary policy files that might be left
    rm -f /tmp/*-policy.json 2>/dev/null || true
    
    log "✅ Temporary files cleaned up"
}

# Function to verify resource removal
verify_cleanup() {
    info "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check for remaining functions
    local remaining_functions
    if [[ "$REMOVE_ALL" == "true" ]]; then
        remaining_functions=$(gcloud functions list --format="value(name)" --filter="name~'(alert-processor-|auto-remediate-)'" 2>/dev/null | wc -l)
    else
        remaining_functions=$(gcloud functions list --format="value(name)" --filter="name:($ALERT_FUNCTION_NAME OR $REMEDIATION_FUNCTION_NAME)" 2>/dev/null | wc -l)
    fi
    
    if [[ "$remaining_functions" -gt 0 ]]; then
        warn "Some Cloud Functions may still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining topics
    local remaining_topics
    if [[ "$REMOVE_ALL" == "true" ]]; then
        remaining_topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -c "incident-automation-" || true)
    else
        remaining_topics=$(gcloud pubsub topics describe "$TOPIC_NAME" 2>/dev/null | wc -l)
    fi
    
    if [[ "$remaining_topics" -gt 0 ]]; then
        warn "Some Pub/Sub topics may still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining log sinks
    local remaining_sinks
    if [[ "$REMOVE_ALL" == "true" ]]; then
        remaining_sinks=$(gcloud logging sinks list --format="value(name)" --filter="name~'automation-sink-'" 2>/dev/null | wc -l)
    else
        remaining_sinks=$(gcloud logging sinks describe "$LOG_SINK_NAME" 2>/dev/null | wc -l)
    fi
    
    if [[ "$remaining_sinks" -gt 0 ]]; then
        warn "Some log sinks may still exist"
        ((cleanup_issues++))
    fi
    
    if [[ "$cleanup_issues" -eq 0 ]]; then
        log "✅ All resources successfully removed"
    else
        warn "Some resources may still exist. Check Google Cloud Console for manual cleanup."
    fi
}

# Function to display cleanup summary
show_summary() {
    echo ""
    log "=============================================="
    log "           CLEANUP SUMMARY"
    log "=============================================="
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    
    if [[ "$REMOVE_ALL" == "true" ]]; then
        log "Operation: Remove all log-automation resources"
    else
        log "Resource Suffix: $SUFFIX"
        log "Operation: Remove specific resources"
    fi
    
    log ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Mode: DRY RUN (no resources were actually removed)"
    else
        log "Resources Removed:"
        log "  • Cloud Functions (alert and remediation processors)"
        log "  • Pub/Sub Topics and Subscriptions"
        log "  • Log Sinks"
        log "  • Log-based Metrics"
        log "  • Cloud Monitoring Alerting Policies"
    fi
    
    log ""
    log "Cleanup completed at $(date)"
    log "=============================================="
}

# Main cleanup function
main() {
    log "Starting log-driven automation cleanup..."
    log "Cleanup options:"
    log "  Project: $PROJECT_ID"
    log "  Region: $REGION"
    if [[ "$REMOVE_ALL" == "true" ]]; then
        log "  Mode: Remove ALL log-automation resources"
    else
        log "  Suffix: $SUFFIX"
        log "  Mode: Remove specific resources"
    fi
    log "  Dry Run: $DRY_RUN"
    log "  Confirmed: $CONFIRMED"
    
    check_prerequisites
    configure_gcloud
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_functions
    remove_monitoring_resources
    remove_log_sinks
    remove_pubsub_resources
    cleanup_temp_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_cleanup
    fi
    
    show_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run completed. Use --confirm to perform actual cleanup."
    else
        log "✅ Log-driven automation cleanup completed!"
    fi
}

# Initialize log files
echo "Cleanup started at $(date)" > "$LOG_FILE"
echo "Error log for cleanup at $(date)" > "$ERROR_LOG"

# Run main cleanup
main "$@"