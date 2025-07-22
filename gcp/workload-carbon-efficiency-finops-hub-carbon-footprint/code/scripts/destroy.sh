#!/bin/bash

# =============================================================================
# GCP Carbon Efficiency with FinOps Hub 2.0 Cleanup Script
# =============================================================================
# 
# This script safely removes all resources created by the carbon efficiency
# monitoring solution, including Cloud Functions, monitoring dashboards,
# workflows, and IAM resources.
#
# Prerequisites:
# - Google Cloud CLI installed and configured
# - Access to the project where resources were deployed
# - Appropriate IAM permissions for resource deletion
#
# Usage: ./destroy.sh [--project-id PROJECT_ID] [--region REGION] [--force] [--dry-run]
#
# =============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly CLEANUP_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Default configuration
DEFAULT_REGION="us-central1"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

print_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║            GCP Carbon Efficiency with FinOps Hub 2.0 Cleanup                 ║
║                                                                               ║
║  This script safely removes all resources created by the carbon efficiency    ║
║  monitoring solution. All data and configurations will be permanently         ║
║  deleted and cannot be recovered.                                             ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
}

confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log_info "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "This action will permanently delete ALL carbon efficiency monitoring resources"
    log_warning "Including:"
    echo "  • Cloud Functions and their source code"
    echo "  • Monitoring dashboards and alert policies"
    echo "  • Cloud Workflows and scheduled jobs"
    echo "  • Service accounts and IAM bindings"
    echo "  • Pub/Sub topics and messages"
    echo "  • Custom metrics and historical data"
    echo
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ ! "$REPLY" =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    echo
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Discover Cloud Functions
    FUNCTIONS=($(gcloud functions list --regions="$REGION" \
        --filter="name:carbon-efficiency" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover monitoring dashboards
    DASHBOARDS=($(gcloud monitoring dashboards list \
        --filter="displayName:Carbon Efficiency" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover alert policies
    ALERT_POLICIES=($(gcloud alpha monitoring policies list \
        --filter="displayName:Carbon Efficiency" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover workflows
    WORKFLOWS=($(gcloud workflows list --locations="$REGION" \
        --filter="name:carbon-efficiency" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover scheduler jobs
    SCHEDULER_JOBS=($(gcloud scheduler jobs list --locations="$REGION" \
        --filter="name:carbon-efficiency" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover Pub/Sub topics
    PUBSUB_TOPICS=($(gcloud pubsub topics list \
        --filter="name:carbon-optimization" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    # Discover service accounts
    SERVICE_ACCOUNTS=($(gcloud iam service-accounts list \
        --filter="displayName:Carbon Efficiency" \
        --format="value(email)" 2>/dev/null || echo ""))
    
    log_success "Resource discovery completed"
}

print_resource_summary() {
    echo
    log_info "Resources to be deleted:"
    echo
    
    if [[ ${#FUNCTIONS[@]} -gt 0 && -n "${FUNCTIONS[0]}" ]]; then
        echo "📊 Cloud Functions (${#FUNCTIONS[@]}):"
        for func in "${FUNCTIONS[@]}"; do
            [[ -n "$func" ]] && echo "   • $func"
        done
    fi
    
    if [[ ${#DASHBOARDS[@]} -gt 0 && -n "${DASHBOARDS[0]}" ]]; then
        echo "📈 Monitoring Dashboards (${#DASHBOARDS[@]}):"
        for dashboard in "${DASHBOARDS[@]}"; do
            [[ -n "$dashboard" ]] && echo "   • $dashboard"
        done
    fi
    
    if [[ ${#ALERT_POLICIES[@]} -gt 0 && -n "${ALERT_POLICIES[0]}" ]]; then
        echo "🚨 Alert Policies (${#ALERT_POLICIES[@]}):"
        for policy in "${ALERT_POLICIES[@]}"; do
            [[ -n "$policy" ]] && echo "   • $policy"
        done
    fi
    
    if [[ ${#WORKFLOWS[@]} -gt 0 && -n "${WORKFLOWS[0]}" ]]; then
        echo "🔄 Workflows (${#WORKFLOWS[@]}):"
        for workflow in "${WORKFLOWS[@]}"; do
            [[ -n "$workflow" ]] && echo "   • $workflow"
        done
    fi
    
    if [[ ${#SCHEDULER_JOBS[@]} -gt 0 && -n "${SCHEDULER_JOBS[0]}" ]]; then
        echo "⏰ Scheduler Jobs (${#SCHEDULER_JOBS[@]}):"
        for job in "${SCHEDULER_JOBS[@]}"; do
            [[ -n "$job" ]] && echo "   • $job"
        done
    fi
    
    if [[ ${#PUBSUB_TOPICS[@]} -gt 0 && -n "${PUBSUB_TOPICS[0]}" ]]; then
        echo "📬 Pub/Sub Topics (${#PUBSUB_TOPICS[@]}):"
        for topic in "${PUBSUB_TOPICS[@]}"; do
            [[ -n "$topic" ]] && echo "   • $topic"
        done
    fi
    
    if [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 && -n "${SERVICE_ACCOUNTS[0]}" ]]; then
        echo "🔐 Service Accounts (${#SERVICE_ACCOUNTS[@]}):"
        for sa in "${SERVICE_ACCOUNTS[@]}"; do
            [[ -n "$sa" ]] && echo "   • $sa"
        done
    fi
    
    echo
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_cloud_functions() {
    if [[ ${#FUNCTIONS[@]} -eq 0 || -z "${FUNCTIONS[0]}" ]]; then
        log_info "No Cloud Functions to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Functions..."
    
    for func in "${FUNCTIONS[@]}"; do
        if [[ -n "$func" ]]; then
            log_info "Deleting function: $func"
            if gcloud functions delete "$func" \
                --region="$REGION" \
                --quiet 2>/dev/null; then
                log_success "Deleted function: $func"
            else
                log_warning "Failed to delete function: $func (may not exist)"
            fi
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # Delete alert policies first
    if [[ ${#ALERT_POLICIES[@]} -gt 0 && -n "${ALERT_POLICIES[0]}" ]]; then
        for policy in "${ALERT_POLICIES[@]}"; do
            if [[ -n "$policy" ]]; then
                log_info "Deleting alert policy: $policy"
                if gcloud alpha monitoring policies delete "$policy" \
                    --quiet 2>/dev/null; then
                    log_success "Deleted alert policy: $policy"
                else
                    log_warning "Failed to delete alert policy: $policy"
                fi
            fi
        done
    fi
    
    # Delete dashboards
    if [[ ${#DASHBOARDS[@]} -gt 0 && -n "${DASHBOARDS[0]}" ]]; then
        for dashboard in "${DASHBOARDS[@]}"; do
            if [[ -n "$dashboard" ]]; then
                log_info "Deleting dashboard: $dashboard"
                if gcloud monitoring dashboards delete "$dashboard" \
                    --quiet 2>/dev/null; then
                    log_success "Deleted dashboard: $dashboard"
                else
                    log_warning "Failed to delete dashboard: $dashboard"
                fi
            fi
        done
    fi
    
    # Delete custom metrics (if any)
    log_info "Cleaning up custom metrics..."
    local metrics=(
        "custom.googleapis.com/carbon_efficiency/score"
        "custom.googleapis.com/optimization/carbon_impact"
        "custom.googleapis.com/gemini/recommendation_effectiveness"
        "custom.googleapis.com/gemini/carbon_impact_score"
    )
    
    for metric in "${metrics[@]}"; do
        if gcloud monitoring metrics-descriptors delete "$metric" \
            --quiet 2>/dev/null; then
            log_success "Deleted custom metric: $metric"
        else
            log_info "Custom metric not found or already deleted: $metric"
        fi
    done
    
    log_success "Monitoring resources cleanup completed"
}

delete_workflows() {
    if [[ ${#WORKFLOWS[@]} -eq 0 || -z "${WORKFLOWS[0]}" ]]; then
        log_info "No workflows to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Workflows..."
    
    for workflow in "${WORKFLOWS[@]}"; do
        if [[ -n "$workflow" ]]; then
            log_info "Deleting workflow: $workflow"
            if gcloud workflows delete "$workflow" \
                --location="$REGION" \
                --quiet 2>/dev/null; then
                log_success "Deleted workflow: $workflow"
            else
                log_warning "Failed to delete workflow: $workflow"
            fi
        fi
    done
    
    log_success "Workflows cleanup completed"
}

delete_scheduler_jobs() {
    if [[ ${#SCHEDULER_JOBS[@]} -eq 0 || -z "${SCHEDULER_JOBS[0]}" ]]; then
        log_info "No scheduler jobs to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Scheduler jobs..."
    
    for job in "${SCHEDULER_JOBS[@]}"; do
        if [[ -n "$job" ]]; then
            log_info "Deleting scheduler job: $job"
            if gcloud scheduler jobs delete "$job" \
                --location="$REGION" \
                --quiet 2>/dev/null; then
                log_success "Deleted scheduler job: $job"
            else
                log_warning "Failed to delete scheduler job: $job"
            fi
        fi
    done
    
    log_success "Scheduler jobs cleanup completed"
}

delete_pubsub_topics() {
    if [[ ${#PUBSUB_TOPICS[@]} -eq 0 || -z "${PUBSUB_TOPICS[0]}" ]]; then
        log_info "No Pub/Sub topics to delete"
        return 0
    fi
    
    log_info "Deleting Pub/Sub topics..."
    
    for topic in "${PUBSUB_TOPICS[@]}"; do
        if [[ -n "$topic" ]]; then
            log_info "Deleting Pub/Sub topic: $topic"
            if gcloud pubsub topics delete "$topic" \
                --quiet 2>/dev/null; then
                log_success "Deleted Pub/Sub topic: $topic"
            else
                log_warning "Failed to delete Pub/Sub topic: $topic"
            fi
        fi
    done
    
    log_success "Pub/Sub topics cleanup completed"
}

delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -eq 0 || -z "${SERVICE_ACCOUNTS[0]}" ]]; then
        log_info "No service accounts to delete"
        return 0
    fi
    
    log_info "Deleting service accounts..."
    
    for sa in "${SERVICE_ACCOUNTS[@]}"; do
        if [[ -n "$sa" ]]; then
            log_info "Removing IAM policy bindings for: $sa"
            
            # Remove IAM policy bindings
            local roles=(
                "roles/billing.carbonViewer"
                "roles/recommender.viewer"
                "roles/monitoring.editor"
                "roles/cloudfunctions.invoker"
                "roles/workflows.invoker"
                "roles/logging.logWriter"
                "roles/pubsub.publisher"
            )
            
            for role in "${roles[@]}"; do
                if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                    --member="serviceAccount:$sa" \
                    --role="$role" \
                    --quiet 2>/dev/null; then
                    log_info "Removed role $role from $sa"
                else
                    log_info "Role $role not found for $sa"
                fi
            done
            
            log_info "Deleting service account: $sa"
            if gcloud iam service-accounts delete "$sa" \
                --quiet 2>/dev/null; then
                log_success "Deleted service account: $sa"
            else
                log_warning "Failed to delete service account: $sa"
            fi
        fi
    done
    
    log_success "Service accounts cleanup completed"
}

delete_log_sinks() {
    log_info "Cleaning up log sinks..."
    
    local sinks=(
        "finops-hub-insights"
    )
    
    for sink in "${sinks[@]}"; do
        if gcloud logging sinks delete "$sink" \
            --quiet 2>/dev/null; then
            log_success "Deleted log sink: $sink"
        else
            log_info "Log sink not found: $sink"
        fi
    done
    
    log_success "Log sinks cleanup completed"
}

cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    local temp_files=(
        "carbon-efficiency-dashboard.json"
        "efficiency-alert-policy.json"
        "carbon-efficiency-workflow.yaml"
        "gemini-finops-config.json"
        "gemini-metrics-script.py"
    )
    
    local temp_dirs=(
        "carbon-efficiency-function"
        "optimization-automation"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed temporary file: $file"
        fi
    done
    
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_success "Removed temporary directory: $dir"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# =============================================================================
# Validation and Verification
# =============================================================================

verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --regions="$REGION" \
        --filter="name:carbon-efficiency" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_functions" -gt 0 ]]; then
        log_warning "$remaining_functions Cloud Functions still exist"
        remaining_resources=$((remaining_resources + remaining_functions))
    fi
    
    # Check dashboards
    local remaining_dashboards
    remaining_dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:Carbon Efficiency" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_dashboards" -gt 0 ]]; then
        log_warning "$remaining_dashboards monitoring dashboards still exist"
        remaining_resources=$((remaining_resources + remaining_dashboards))
    fi
    
    # Check workflows
    local remaining_workflows
    remaining_workflows=$(gcloud workflows list --locations="$REGION" \
        --filter="name:carbon-efficiency" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_workflows" -gt 0 ]]; then
        log_warning "$remaining_workflows workflows still exist"
        remaining_resources=$((remaining_resources + remaining_workflows))
    fi
    
    # Check service accounts
    local remaining_sas
    remaining_sas=$(gcloud iam service-accounts list \
        --filter="displayName:Carbon Efficiency" \
        --format="value(email)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_sas" -gt 0 ]]; then
        log_warning "$remaining_sas service accounts still exist"
        remaining_resources=$((remaining_resources + remaining_sas))
    fi
    
    if [[ "$remaining_resources" -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Check manually if needed."
    fi
    
    return 0
}

# =============================================================================
# Main Cleanup Logic
# =============================================================================

print_cleanup_summary() {
    cat << EOF

╔═══════════════════════════════════════════════════════════════════════════════╗
║                            CLEANUP SUMMARY                                   ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                               ║
║  🎯 Project ID: ${PROJECT_ID:-'Not specified'}                               ║
║  🌍 Region: ${REGION}                                                 ║
║                                                                               ║
║  🗑️  Resources Cleaned:                                                      ║
║     • Cloud Functions: carbon-efficiency-correlator, optimizer               ║
║     • Monitoring Dashboards and Alert Policies                               ║
║     • Cloud Workflows and Scheduler Jobs                                     ║
║     • Service Accounts and IAM Bindings                                      ║
║     • Pub/Sub Topics and Log Sinks                                           ║
║     • Custom Metrics and Local Files                                         ║
║                                                                               ║
║  📝 Log File: ${LOG_FILE}                                                     ║
║                                                                               ║
║  💡 Note: FinOps Hub 2.0 and Cloud Carbon Footprint are billing              ║
║     account features and remain available for other projects.                ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝

EOF
}

parse_arguments() {
    PROJECT_ID=""
    REGION="$DEFAULT_REGION"
    FORCE=false
    DRY_RUN=false
    
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
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Clean up GCP Carbon Efficiency with FinOps Hub 2.0 solution resources.

OPTIONS:
    --project-id PROJECT_ID     GCP project ID (required if not set in gcloud)
    --region REGION            GCP region (default: us-central1)
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be deleted without executing
    --help, -h                 Show this help message

EXAMPLES:
    $0                                          # Interactive cleanup
    $0 --project-id my-project --force          # Force cleanup
    $0 --dry-run                               # Show cleanup plan

WARNING:
    This will permanently delete all carbon efficiency monitoring resources.
    This action cannot be undone.

EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Get project ID from gcloud if not provided
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID not specified and not set in gcloud config"
            log_info "Use --project-id PROJECT_ID or run: gcloud config set project PROJECT_ID"
            exit 1
        fi
    fi
}

main() {
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    log_info "Starting cleanup at $(date)"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Print banner
    print_banner
    
    # Set project
    if ! gcloud config set project "$PROJECT_ID" --quiet 2>/dev/null; then
        log_error "Failed to set project: $PROJECT_ID"
        exit 1
    fi
    
    # Discover resources
    discover_resources
    
    # Print resource summary
    print_resource_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Main cleanup sequence (order matters for dependencies)
    log_info "Starting cleanup process..."
    
    delete_scheduler_jobs
    delete_workflows
    delete_cloud_functions
    delete_monitoring_resources
    delete_pubsub_topics
    delete_log_sinks
    delete_service_accounts
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Print summary
    print_cleanup_summary
    
    log_success "Cleanup completed successfully at $(date)"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes"
}

# Execute main function with all arguments
main "$@"