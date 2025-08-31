#!/bin/bash

# Email Automation with Agent Builder and MCP - Cleanup Script
# This script safely removes all email automation infrastructure from Google Cloud Platform

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups"

# Configuration variables
PROJECT_ID=""
REGION=""
ZONE=""
SERVICE_ACCOUNT_EMAIL=""
DRY_RUN=false
FORCE_DESTROY=false
SKIP_CONFIRMATION=false
BACKUP_ENABLED=true

# Function definitions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    log "INFO" "${BLUE}$*${NC}"
}

success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

fatal() {
    error "$*"
    exit 1
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Email Automation with Agent Builder and MCP infrastructure on Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required if not found in state file)
    -r, --region REGION           GCP region (override state file)
    -d, --dry-run                 Show what would be destroyed without making changes
    -f, --force                   Force destruction without confirmation prompts
    -y, --yes                     Skip all confirmation prompts (same as --force)
    --no-backup                   Skip backing up configurations before destruction
    --functions-only              Only destroy Cloud Functions
    --pubsub-only                 Only destroy Pub/Sub resources
    --iam-only                    Only destroy IAM resources
    -h, --help                    Show this help message

EXAMPLES:
    $0                                    # Interactive destruction using state file
    $0 --project-id my-project-123        # Specify project explicitly
    $0 --dry-run                         # Preview what would be destroyed
    $0 --force --no-backup               # Fast destruction without prompts or backups
    $0 --functions-only                  # Only destroy Cloud Functions

SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Backup configurations before deletion
    - Dependency-aware resource deletion order
    - State file tracking for partial cleanups
    - Dry-run mode to preview changes

EOF
}

parse_arguments() {
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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force|-y|--yes)
                FORCE_DESTROY=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            --functions-only)
                DESTROY_SCOPE="functions"
                shift
                ;;
            --pubsub-only)
                DESTROY_SCOPE="pubsub"
                shift
                ;;
            --iam-only)
                DESTROY_SCOPE="iam"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fatal "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

load_state() {
    local key="$1"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2- || true
    fi
}

save_state() {
    local key="$1"
    local value="$2"
    
    if [[ ! -f "$STATE_FILE" ]]; then
        return
    fi
    
    # Remove existing key and add new value
    grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    echo "${key}=${value}" >> "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

remove_state_key() {
    local key="$1"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

load_configuration() {
    info "Loading configuration from state file..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        if [[ -z "$PROJECT_ID" ]]; then
            fatal "No state file found and no project ID provided. Use --project-id or see --help for usage."
        fi
        warning "No state file found. Manual configuration required."
        return
    fi
    
    # Load configuration from state file
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(load_state "PROJECT_ID")
    fi
    
    if [[ -z "$REGION" ]]; then
        REGION=$(load_state "REGION")
    fi
    
    if [[ -z "$ZONE" ]]; then
        ZONE=$(load_state "ZONE")
    fi
    
    SERVICE_ACCOUNT_EMAIL=$(load_state "SERVICE_ACCOUNT_EMAIL")
    
    # Validate loaded configuration
    if [[ -z "$PROJECT_ID" ]]; then
        fatal "Project ID not found in state file and not provided via --project-id"
    fi
    
    if [[ -z "$REGION" ]]; then
        REGION="us-central1"  # Default fallback
        warning "Region not found in state file, using default: $REGION"
    fi
    
    if [[ -z "$SERVICE_ACCOUNT_EMAIL" ]]; then
        SERVICE_ACCOUNT_EMAIL="email-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"
        warning "Service account email not found in state file, using default: $SERVICE_ACCOUNT_EMAIL"
    fi
    
    success "Configuration loaded: Project=$PROJECT_ID, Region=$REGION"
}

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        fatal "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        fatal "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        fatal "Project '$PROJECT_ID' not found or not accessible. Please check project ID and permissions."
    fi
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID" &> /dev/null
    gcloud config set compute/region "$REGION" &> /dev/null
    
    success "Prerequisites check passed"
}

execute_command() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    info "Executing: $cmd"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local exit_code=$?
        error "Command failed with exit code $exit_code: $cmd"
        return $exit_code
    fi
}

confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "${RED}⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️${NC}"
    echo
    echo "This will destroy the following Email Automation infrastructure:"
    echo "  • Project: $PROJECT_ID"
    echo "  • Region: $REGION"
    echo "  • Cloud Functions (4 functions)"
    echo "  • Pub/Sub topic and subscription"
    echo "  • Service account and IAM bindings"
    echo "  • Local configuration files"
    echo
    echo "${YELLOW}This action cannot be undone!${NC}"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Please confirm the project ID to proceed: " project_confirmation
    
    if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
        fatal "Project ID confirmation failed. Destruction cancelled."
    fi
    
    success "Destruction confirmed by user"
}

backup_configurations() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        info "Backup disabled, skipping configuration backup"
        return 0
    fi
    
    info "Backing up configurations before destruction..."
    
    mkdir -p "$BACKUP_DIR"
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/backup_${backup_timestamp}.tar.gz"
    
    # Create backup of configurations
    local backup_items=()
    
    # Backup state file if it exists
    if [[ -f "$STATE_FILE" ]]; then
        backup_items+=("$STATE_FILE")
    fi
    
    # Backup MCP configuration if it exists
    local mcp_config_dir="${SCRIPT_DIR}/../mcp-config"
    if [[ -d "$mcp_config_dir" ]]; then
        backup_items+=("$mcp_config_dir")
    fi
    
    # Backup function source code if it exists
    local functions_dir="${SCRIPT_DIR}/../functions"
    if [[ -d "$functions_dir" ]]; then
        backup_items+=("$functions_dir")
    fi
    
    if [[ ${#backup_items[@]} -gt 0 ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            tar -czf "$backup_file" -C "$SCRIPT_DIR" "${backup_items[@]/#$SCRIPT_DIR\//}" 2>/dev/null || true
            if [[ -f "$backup_file" ]]; then
                success "Configuration backup created: $backup_file"
            else
                warning "Failed to create backup file"
            fi
        else
            info "[DRY RUN] Would create backup: $backup_file"
        fi
    else
        info "No configurations found to backup"
    fi
}

destroy_cloud_functions() {
    info "Destroying Cloud Functions..."
    
    local functions=("gmail-webhook" "mcp-integration" "response-generator" "email-workflow")
    local destroyed_count=0
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --region="$REGION" &> /dev/null; then
            info "Destroying function: $func"
            execute_command "gcloud functions delete $func --region=${REGION} --quiet"
            if [[ $? -eq 0 ]]; then
                ((destroyed_count++))
                success "Function destroyed: $func"
                remove_state_key "FUNCTION_${func^^}"
            else
                error "Failed to destroy function: $func"
            fi
        else
            info "Function not found (already destroyed): $func"
        fi
    done
    
    if [[ $destroyed_count -gt 0 ]]; then
        success "$destroyed_count Cloud Functions destroyed"
    else
        info "No Cloud Functions found to destroy"
    fi
}

destroy_pubsub_resources() {
    info "Destroying Pub/Sub resources..."
    
    local destroyed_count=0
    
    # Destroy subscription first (depends on topic)
    if gcloud pubsub subscriptions describe gmail-webhook-sub &> /dev/null; then
        info "Destroying Pub/Sub subscription: gmail-webhook-sub"
        execute_command "gcloud pubsub subscriptions delete gmail-webhook-sub --quiet"
        if [[ $? -eq 0 ]]; then
            ((destroyed_count++))
            success "Subscription destroyed: gmail-webhook-sub"
            remove_state_key "PUBSUB_SUBSCRIPTION"
        else
            error "Failed to destroy subscription: gmail-webhook-sub"
        fi
    else
        info "Subscription not found (already destroyed): gmail-webhook-sub"
    fi
    
    # Destroy topic
    if gcloud pubsub topics describe gmail-notifications &> /dev/null; then
        info "Destroying Pub/Sub topic: gmail-notifications"
        execute_command "gcloud pubsub topics delete gmail-notifications --quiet"
        if [[ $? -eq 0 ]]; then
            ((destroyed_count++))
            success "Topic destroyed: gmail-notifications"
            remove_state_key "PUBSUB_TOPIC"
        else
            error "Failed to destroy topic: gmail-notifications"
        fi
    else
        info "Topic not found (already destroyed): gmail-notifications"
    fi
    
    if [[ $destroyed_count -gt 0 ]]; then
        success "$destroyed_count Pub/Sub resources destroyed"
    else
        info "No Pub/Sub resources found to destroy"
    fi
}

destroy_iam_resources() {
    info "Destroying IAM resources..."
    
    local destroyed_count=0
    
    # Remove IAM policy bindings first
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &> /dev/null; then
        info "Removing IAM policy bindings for service account..."
        
        local roles=(
            "roles/aiplatform.user"
            "roles/secretmanager.secretAccessor"
            "roles/pubsub.publisher"
            "roles/pubsub.subscriber"
            "roles/cloudfunctions.invoker"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            info "Removing role binding: $role"
            execute_command "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
                --member='serviceAccount:${SERVICE_ACCOUNT_EMAIL}' \
                --role='$role' --quiet" || true
        done
        
        # Remove Gmail API push service account binding
        execute_command "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
            --member='serviceAccount:gmail-api-push@system.gserviceaccount.com' \
            --role='roles/pubsub.publisher' --quiet" || true
        
        # Delete service account
        info "Destroying service account: $SERVICE_ACCOUNT_EMAIL"
        execute_command "gcloud iam service-accounts delete ${SERVICE_ACCOUNT_EMAIL} --quiet"
        if [[ $? -eq 0 ]]; then
            ((destroyed_count++))
            success "Service account destroyed: $SERVICE_ACCOUNT_EMAIL"
            remove_state_key "SERVICE_ACCOUNT_EMAIL"
        else
            error "Failed to destroy service account: $SERVICE_ACCOUNT_EMAIL"
        fi
    else
        info "Service account not found (already destroyed): $SERVICE_ACCOUNT_EMAIL"
    fi
    
    if [[ $destroyed_count -gt 0 ]]; then
        success "$destroyed_count IAM resources destroyed"
    else
        info "No IAM resources found to destroy"
    fi
}

cleanup_local_files() {
    info "Cleaning up local files..."
    
    local cleaned_count=0
    
    # Clean up function directories
    local functions_dir="${SCRIPT_DIR}/../functions"
    if [[ -d "$functions_dir" ]]; then
        info "Removing functions directory: $functions_dir"
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -rf "$functions_dir"
            if [[ ! -d "$functions_dir" ]]; then
                ((cleaned_count++))
                success "Functions directory removed"
            fi
        else
            info "[DRY RUN] Would remove: $functions_dir"
        fi
    fi
    
    # Clean up MCP configuration
    local mcp_config_dir="${SCRIPT_DIR}/../mcp-config"
    if [[ -d "$mcp_config_dir" ]]; then
        info "Removing MCP configuration directory: $mcp_config_dir"
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -rf "$mcp_config_dir"
            if [[ ! -d "$mcp_config_dir" ]]; then
                ((cleaned_count++))
                success "MCP configuration directory removed"
            fi
        else
            info "[DRY RUN] Would remove: $mcp_config_dir"
        fi
    fi
    
    # Clean up state file (after everything else is done)
    if [[ -f "$STATE_FILE" ]] && [[ "$DRY_RUN" != "true" ]]; then
        info "Removing state file: $STATE_FILE"
        rm -f "$STATE_FILE"
        if [[ ! -f "$STATE_FILE" ]]; then
            ((cleaned_count++))
            success "State file removed"
        fi
    elif [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would remove state file: $STATE_FILE"
    fi
    
    if [[ $cleaned_count -gt 0 ]]; then
        success "$cleaned_count local files/directories cleaned up"
    else
        info "No local files found to clean up"
    fi
}

verify_destruction() {
    info "Verifying destruction..."
    
    local remaining_resources=()
    
    # Check Cloud Functions
    local functions=("gmail-webhook" "mcp-integration" "response-generator" "email-workflow")
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --region="$REGION" &> /dev/null; then
            remaining_resources+=("Function: $func")
        fi
    done
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe gmail-notifications &> /dev/null; then
        remaining_resources+=("Pub/Sub topic: gmail-notifications")
    fi
    
    if gcloud pubsub subscriptions describe gmail-webhook-sub &> /dev/null; then
        remaining_resources+=("Pub/Sub subscription: gmail-webhook-sub")
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &> /dev/null; then
        remaining_resources+=("Service account: $SERVICE_ACCOUNT_EMAIL")
    fi
    
    # Check local files
    if [[ -f "$STATE_FILE" ]]; then
        remaining_resources+=("State file: $STATE_FILE")
    fi
    
    if [[ -d "${SCRIPT_DIR}/../functions" ]]; then
        remaining_resources+=("Functions directory")
    fi
    
    if [[ -d "${SCRIPT_DIR}/../mcp-config" ]]; then
        remaining_resources+=("MCP config directory")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        success "All resources successfully destroyed"
        return 0
    else
        warning "Some resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            echo "  • $resource"
        done
        return 1
    fi
}

display_destruction_summary() {
    info "Destruction Summary"
    echo
    echo "=========================================="
    echo "  Email Automation Destruction Complete"
    echo "=========================================="
    echo
    echo "Project ID:       $PROJECT_ID"
    echo "Region:           $REGION"
    echo "Timestamp:        $(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo "Destroyed Resources:"
    echo "  • Cloud Functions (4 functions)"
    echo "  • Pub/Sub topic and subscription"
    echo "  • Service account and IAM bindings"
    echo "  • Local configuration files"
    echo
    if [[ "$BACKUP_ENABLED" == "true" ]] && [[ -d "$BACKUP_DIR" ]]; then
        echo "Backups available in: $BACKUP_DIR"
        echo
    fi
    echo "Log file: $LOG_FILE"
    echo
    echo "The email automation infrastructure has been completely removed."
    echo "You can safely delete this directory if no longer needed."
    echo
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Destruction failed with exit code $exit_code"
        echo "Check the log file for details: $LOG_FILE"
        echo "Some resources may still exist and require manual cleanup."
    fi
}

main() {
    # Set up error handling
    trap cleanup_on_exit EXIT
    
    info "Starting Email Automation infrastructure destruction..."
    echo "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load configuration from state file or user input
    load_configuration
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm destruction with user
    confirm_destruction
    
    # Backup configurations before destruction
    backup_configurations
    
    # Execute destruction in dependency order
    case "${DESTROY_SCOPE:-all}" in
        "functions")
            destroy_cloud_functions
            ;;
        "pubsub")
            destroy_pubsub_resources
            ;;
        "iam")
            destroy_iam_resources
            ;;
        "all"|*)
            destroy_cloud_functions
            destroy_pubsub_resources
            destroy_iam_resources
            cleanup_local_files
            ;;
    esac
    
    # Verify destruction
    if verify_destruction; then
        display_destruction_summary
        success "Email Automation infrastructure destruction completed successfully!"
    else
        warning "Destruction completed with some remaining resources. Manual cleanup may be required."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"