#!/bin/bash

##############################################################################
# Automated Event Creation with Apps Script and Calendar API - Cleanup Script
# 
# This script safely removes all resources created during the deployment
# of the Google Apps Script event automation system.
#
# Prerequisites:
# - Previous deployment using deploy.sh
# - Google Cloud SDK (gcloud) installed and configured
# - Internet browser access for manual cleanup steps
#
# Usage: ./destroy.sh [--force] [--dry-run] [--help]
##############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/.deployment_env"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Global variables
FORCE_MODE=false
DRY_RUN=false
CLEANUP_SUCCESS=false

# Deployment variables (loaded from environment file)
PROJECT_NAME=""
SHEET_NAME=""
CALENDAR_ID=""
DEPLOYMENT_DIR=""
DEPLOYMENT_TIME=""

##############################################################################
# Utility Functions
##############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

confirm_destructive_action() {
    local message="$1"
    
    if [[ "$FORCE_MODE" == "true" ]]; then
        log INFO "[FORCED] $message"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $message"
        return 0
    fi
    
    echo -e "${RED}[DESTRUCTIVE ACTION]${NC} $message"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    
    if [[ ! "$REPLY" == "yes" ]]; then
        log INFO "Destructive action cancelled by user"
        return 1
    fi
    
    return 0
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Automated Event Creation with Apps Script and Calendar API deployment

OPTIONS:
    --force      Skip confirmation prompts (use with caution)
    --dry-run    Show what would be destroyed without making changes
    --help       Show this help message

EXAMPLES:
    $0                    # Interactive cleanup with confirmations
    $0 --dry-run         # Preview cleanup steps
    $0 --force           # Automated cleanup without prompts (dangerous)
    $0 --help            # Show usage information

WARNING:
    This script will permanently delete:
    - Google Apps Script project (if manually deleted)
    - Google Sheet data (if manually deleted)
    - Calendar events (if manually deleted)
    - Automation triggers and settings

    Always backup important data before running cleanup!

EOF
}

##############################################################################
# Environment Loading and Validation
##############################################################################

load_deployment_environment() {
    log INFO "Loading deployment environment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log WARN "Deployment environment file not found: $ENV_FILE"
        log WARN "This may indicate no previous deployment or manual cleanup needed"
        
        # Set default values for manual cleanup mode
        PROJECT_NAME="event-automation-manual"
        SHEET_NAME="Event Schedule"
        CALENDAR_ID="primary"
        DEPLOYMENT_DIR=""
        DEPLOYMENT_TIME="unknown"
        
        log INFO "Using default values for manual cleanup mode"
        return 0
    fi
    
    # Source environment variables
    source "$ENV_FILE"
    
    log INFO "Loaded deployment environment:"
    log INFO "  PROJECT_NAME: $PROJECT_NAME"
    log INFO "  SHEET_NAME: $SHEET_NAME"
    log INFO "  CALENDAR_ID: $CALENDAR_ID"
    log INFO "  DEPLOYMENT_TIME: $DEPLOYMENT_TIME"
    
    if [[ -n "$DEPLOYMENT_DIR" && -d "$DEPLOYMENT_DIR" ]]; then
        log INFO "  DEPLOYMENT_DIR: $DEPLOYMENT_DIR (exists)"
    else
        log DEBUG "  DEPLOYMENT_DIR: $DEPLOYMENT_DIR (not found)"
    fi
    
    log INFO "✅ Environment loaded successfully"
}

validate_cleanup_prerequisites() {
    log INFO "Validating cleanup prerequisites..."
    
    # Check for required commands
    local missing_deps=()
    
    if ! command -v gcloud &> /dev/null; then
        missing_deps+=("gcloud (Google Cloud SDK)")
    fi
    
    # Check Google Cloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        log WARN "No active Google Cloud authentication found"
        log INFO "Some cleanup operations may require manual intervention"
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log WARN "Missing optional dependencies:"
        for dep in "${missing_deps[@]}"; do
            log WARN "  - $dep"
        done
        log INFO "Cleanup will proceed with manual steps where necessary"
    fi
    
    log INFO "✅ Prerequisites validation complete"
}

##############################################################################
# Cleanup Functions
##############################################################################

cleanup_apps_script_project() {
    log INFO "Cleaning up Google Apps Script project..."
    
    if ! confirm_destructive_action "Delete Google Apps Script project: 'Event Automation Script'"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would delete Apps Script project"
        return 0
    fi
    
    log INFO "Manual cleanup required for Apps Script:"
    log INFO "1. Navigate to https://script.google.com"
    log INFO "2. Find the project named: 'Event Automation Script'"
    log INFO "3. Click the three-dot menu and select 'Move to trash'"
    log INFO "4. Confirm deletion when prompted"
    
    if [[ "$FORCE_MODE" == "false" ]]; then
        read -p "Press Enter when Apps Script project cleanup is complete..."
    fi
    
    log INFO "✅ Apps Script project cleanup completed"
}

cleanup_automation_triggers() {
    log INFO "Cleaning up automation triggers..."
    
    if ! confirm_destructive_action "Remove all automation triggers"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would remove automation triggers"
        return 0
    fi
    
    log INFO "Manual trigger cleanup (if Apps Script project still exists):"
    log INFO "1. Open your Apps Script project at https://script.google.com"
    log INFO "2. Click on the 'Triggers' icon (clock symbol) in the left sidebar"
    log INFO "3. Delete all triggers by clicking the trash icon next to each"
    log INFO "4. Confirm deletion for each trigger"
    
    if [[ "$FORCE_MODE" == "false" ]]; then
        read -p "Press Enter when trigger cleanup is complete (or skip if project deleted)..."
    fi
    
    log INFO "✅ Automation triggers cleanup completed"
}

cleanup_test_events() {
    log INFO "Cleaning up test calendar events..."
    
    if ! confirm_destructive_action "Remove test events from Google Calendar"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would remove test calendar events"
        return 0
    fi
    
    log INFO "Manual test event cleanup:"
    log INFO "1. Navigate to https://calendar.google.com"
    log INFO "2. Look for events containing 'Test' or 'Automation Check' in the title"
    log INFO "3. Delete any test events created during deployment"
    log INFO "4. Review recent events for any unwanted automation-created events"
    
    log WARN "⚠️  Be careful not to delete important non-test events!"
    
    if [[ "$FORCE_MODE" == "false" ]]; then
        read -p "Press Enter when test event cleanup is complete..."
    fi
    
    log INFO "✅ Test events cleanup completed"
}

cleanup_google_sheet() {
    log INFO "Cleaning up Google Sheet..."
    
    if ! confirm_destructive_action "Delete or archive Google Sheet: '$SHEET_NAME'"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would clean up Google Sheet"
        return 0
    fi
    
    log INFO "Google Sheet cleanup options:"
    log INFO "Option 1 - Archive (Recommended):"
    log INFO "  1. Navigate to https://sheets.google.com"
    log INFO "  2. Find the sheet named: '$SHEET_NAME'"
    log INFO "  3. Right-click and select 'Move to Trash' or rename with 'ARCHIVED-' prefix"
    log INFO ""
    log INFO "Option 2 - Complete Deletion:"
    log INFO "  1. Move to trash as above"
    log INFO "  2. Empty the trash to permanently delete"
    
    log WARN "⚠️  Deleting the sheet will permanently remove all event data!"
    
    if [[ "$FORCE_MODE" == "false" ]]; then
        read -p "Press Enter when Google Sheet cleanup is complete..."
    fi
    
    log INFO "✅ Google Sheet cleanup completed"
}

cleanup_temporary_files() {
    log INFO "Cleaning up temporary files and directories..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would clean up temporary files"
        return 0
    fi
    
    local files_cleaned=0
    
    # Clean up deployment directory
    if [[ -n "$DEPLOYMENT_DIR" && -d "$DEPLOYMENT_DIR" ]]; then
        if confirm_destructive_action "Remove deployment directory: $DEPLOYMENT_DIR"; then
            rm -rf "$DEPLOYMENT_DIR"
            log INFO "Removed deployment directory: $DEPLOYMENT_DIR"
            ((files_cleaned++))
        fi
    fi
    
    # Clean up environment file
    if [[ -f "$ENV_FILE" ]]; then
        if confirm_destructive_action "Remove deployment environment file: $ENV_FILE"; then
            rm -f "$ENV_FILE"
            log INFO "Removed environment file: $ENV_FILE"
            ((files_cleaned++))
        fi
    fi
    
    # Clean up any backup files
    local backup_files
    mapfile -t backup_files < <(find "$SCRIPT_DIR" -name "*.backup" -type f 2>/dev/null || true)
    
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        if confirm_destructive_action "Remove ${#backup_files[@]} backup files"; then
            for file in "${backup_files[@]}"; do
                rm -f "$file"
                log DEBUG "Removed backup file: $file"
                ((files_cleaned++))
            done
        fi
    fi
    
    log INFO "✅ Temporary files cleanup completed (${files_cleaned} files cleaned)"
}

cleanup_authentication_tokens() {
    log INFO "Checking authentication token cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would check authentication tokens"
        return 0
    fi
    
    log INFO "Authentication cleanup (optional):"
    log INFO "If you no longer need Google Apps Script access:"
    log INFO "1. Visit https://myaccount.google.com/permissions"
    log INFO "2. Look for 'Google Apps Script' applications"
    log INFO "3. Remove access for any unwanted Apps Script applications"
    log INFO "4. Review and revoke any unnecessary Google Calendar permissions"
    
    log INFO "This step is optional and only recommended if you're done with Apps Script entirely"
    
    if [[ "$FORCE_MODE" == "false" ]]; then
        read -p "Press Enter to continue (authentication cleanup is optional)..."
    fi
    
    log INFO "✅ Authentication token cleanup information provided"
}

##############################################################################
# Main Cleanup Flow
##############################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_MODE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    echo "# Cleanup Log - $(date -Iseconds)" > "$LOG_FILE"
    
    log INFO "Starting cleanup of Automated Event Creation with Apps Script"
    log INFO "Force mode: $FORCE_MODE"
    log INFO "Dry run mode: $DRY_RUN"
    
    # Trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Show important warnings
    if [[ "$FORCE_MODE" == "true" ]]; then
        log WARN "⚠️  FORCE MODE ENABLED - All confirmations will be skipped!"
        log WARN "⚠️  This will permanently delete resources without prompts!"
        sleep 3
    fi
    
    # Load deployment environment
    load_deployment_environment
    validate_cleanup_prerequisites
    
    # Execute cleanup steps in reverse order of deployment
    log INFO "🧹 Beginning cleanup process..."
    
    cleanup_automation_triggers
    cleanup_test_events
    cleanup_apps_script_project
    cleanup_google_sheet
    cleanup_temporary_files
    cleanup_authentication_tokens
    
    CLEANUP_SUCCESS=true
    
    log INFO "🎉 Cleanup completed successfully!"
    log INFO "📋 Summary:"
    log INFO "  - Apps Script project cleanup instructions provided"
    log INFO "  - Automation triggers cleanup instructions provided" 
    log INFO "  - Test calendar events cleanup instructions provided"
    log INFO "  - Google Sheet cleanup instructions provided"
    log INFO "  - Temporary files and directories cleaned"
    log INFO "  - Authentication token cleanup information provided"
    
    log INFO "📄 Cleanup log saved to: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "✨ All automation resources have been cleaned up!"
        log INFO "🔒 Your Google account permissions remain intact for future use"
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 && "$CLEANUP_SUCCESS" == "false" ]]; then
        log ERROR "Cleanup failed with exit code: $exit_code"
        log INFO "Check the log file for details: $LOG_FILE"
        log INFO "You may need to complete some cleanup steps manually"
        
        log INFO "Manual cleanup checklist:"
        log INFO "  □ Delete Apps Script project at https://script.google.com"
        log INFO "  □ Remove automation triggers"
        log INFO "  □ Delete test calendar events at https://calendar.google.com"
        log INFO "  □ Archive or delete Google Sheet at https://sheets.google.com"
        log INFO "  □ Remove temporary files from: $SCRIPT_DIR"
    fi
}

# Execute main function
main "$@"