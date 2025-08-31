#!/bin/bash

##############################################################################
# Automated Event Creation with Apps Script and Calendar API - Deployment Script
# 
# This script automates the deployment of the Google Apps Script project
# and Google Sheets setup for automated event creation.
#
# Prerequisites:
# - Google Cloud SDK (gcloud) installed and configured
# - Google account with Workspace or personal access
# - Internet browser access for authentication
# - Basic familiarity with Google Sheets and Calendar
#
# Usage: ./deploy.sh [--dry-run] [--help]
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
readonly PROJECT_NAME="event-automation-$(date +%s)"
readonly SHEET_NAME="Event Schedule"
readonly CALENDAR_ID="primary"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Global variables
DRY_RUN=false
DEPLOYMENT_SUCCESS=false

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

spinner() {
    local pid=$1
    local message="$2"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${BLUE}[WORKING]${NC} ${spin:$i:1} $message"
        sleep 0.1
    done
    printf "\r"
}

confirm_action() {
    local message="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would execute: $message"
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log INFO "Operation cancelled by user"
        exit 0
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Automated Event Creation with Apps Script and Calendar API

OPTIONS:
    --dry-run    Show what would be done without making changes
    --help       Show this help message

EXAMPLES:
    $0                    # Deploy with interactive prompts
    $0 --dry-run         # Preview deployment steps
    $0 --help            # Show usage information

PREREQUISITES:
    - Google Cloud SDK installed and authenticated
    - Google account with appropriate permissions
    - Internet browser for authentication flows
    - Basic familiarity with Google Workspace services

EOF
}

##############################################################################
# Prerequisite Checks
##############################################################################

check_prerequisites() {
    log INFO "Checking deployment prerequisites..."
    
    local missing_deps=()
    
    # Check for required commands
    if ! command -v gcloud &> /dev/null; then
        missing_deps+=("gcloud (Google Cloud SDK)")
    fi
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        log WARN "jq not found - JSON processing will be limited"
    fi
    
    # Check internet connectivity
    if ! curl -s --head --connect-timeout 5 https://www.google.com > /dev/null; then
        missing_deps+=("Internet connectivity")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log ERROR "Missing prerequisites:"
        for dep in "${missing_deps[@]}"; do
            log ERROR "  - $dep"
        done
        log ERROR "Please install missing dependencies and retry"
        exit 1
    fi
    
    # Check Google Cloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        log ERROR "No active Google Cloud authentication found"
        log INFO "Please run: gcloud auth login"
        exit 1
    fi
    
    log INFO "✅ All prerequisites met"
}

check_google_services() {
    log INFO "Verifying Google Services access..."
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    
    if [[ -z "$active_account" ]]; then
        log ERROR "No active Google account found"
        exit 1
    fi
    
    log INFO "Active Google account: $active_account"
    
    # Check if we can access Google Apps Script
    log INFO "Checking Google Apps Script access..."
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "Google Apps Script requires browser-based authentication"
        log INFO "You will need to visit script.google.com manually"
    fi
    
    log INFO "✅ Google Services verification complete"
}

##############################################################################
# Deployment Functions
##############################################################################

create_environment_setup() {
    log INFO "Setting up deployment environment..."
    
    # Create temporary directory for deployment files
    local temp_dir="${SCRIPT_DIR}/temp-deployment-$(date +%s)"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$temp_dir"
        log INFO "Created temporary directory: $temp_dir"
    fi
    
    # Set environment variables
    export PROJECT_NAME="$PROJECT_NAME"
    export SHEET_NAME="$SHEET_NAME"
    export CALENDAR_ID="$CALENDAR_ID"
    export DEPLOYMENT_DIR="$temp_dir"
    
    log INFO "Environment variables configured:"
    log INFO "  PROJECT_NAME: $PROJECT_NAME"
    log INFO "  SHEET_NAME: $SHEET_NAME"
    log INFO "  CALENDAR_ID: $CALENDAR_ID"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Save environment to file for cleanup script
        cat > "${SCRIPT_DIR}/.deployment_env" << EOF
PROJECT_NAME="$PROJECT_NAME"
SHEET_NAME="$SHEET_NAME"
CALENDAR_ID="$CALENDAR_ID"
DEPLOYMENT_DIR="$temp_dir"
DEPLOYMENT_TIME="$(date -Iseconds)"
EOF
        log INFO "✅ Environment setup complete"
    else
        log INFO "[DRY-RUN] Would create environment setup"
    fi
}

create_google_sheet() {
    log INFO "Creating Google Sheet with event data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create Google Sheet: '$SHEET_NAME'"
        log INFO "[DRY-RUN] Would add sample event data"
        return 0
    fi
    
    log INFO "Manual step required:"
    log INFO "1. Navigate to https://sheets.google.com"
    log INFO "2. Create a new spreadsheet named: '$SHEET_NAME'"
    log INFO "3. Add the following headers in row 1:"
    log INFO "   Title | Date | Start Time | End Time | Description | Location | Attendees"
    log INFO "4. Add sample data in rows 2-4:"
    
    cat << 'EOF' | tee -a "$LOG_FILE"
Row 2: Team Standup | 2025-07-25 | 09:00 | 09:30 | Daily team sync | Conference Room A | team@company.com
Row 3: Project Review | 2025-07-26 | 14:00 | 15:00 | Quarterly project assessment | Main Office | stakeholders@company.com  
Row 4: Training Session | 2025-07-27 | 10:00 | 12:00 | New employee onboarding | Training Room | hr@company.com
EOF
    
    confirm_action "Please create the Google Sheet as described above and press Enter when complete"
    
    log INFO "✅ Google Sheet creation step completed"
}

deploy_apps_script() {
    log INFO "Deploying Google Apps Script project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would create Apps Script project: 'Event Automation Script'"
        log INFO "[DRY-RUN] Would deploy automation code"
        return 0
    fi
    
    log INFO "Manual Apps Script deployment required:"
    log INFO "1. Navigate to https://script.google.com"
    log INFO "2. Click 'New Project'"
    log INFO "3. Rename project to: 'Event Automation Script'"
    log INFO "4. Replace default code with the automation script"
    
    # Copy automation script to temporary location for easy access
    local script_source="${SCRIPT_DIR}/../terraform/scripts/automation.js"
    local script_dest="${DEPLOYMENT_DIR}/automation.js"
    
    if [[ -f "$script_source" ]]; then
        cp "$script_source" "$script_dest"
        log INFO "5. Copy the automation code from: $script_dest"
    else
        log WARN "Automation script source not found at: $script_source"
        log INFO "5. Use the JavaScript code from the recipe documentation"
    fi
    
    log INFO "6. Update the SHEET_ID placeholder with your actual sheet ID"
    log INFO "7. Save the project (Ctrl+S or Cmd+S)"
    
    confirm_action "Please complete the Apps Script setup as described above"
    
    log INFO "✅ Apps Script deployment step completed"
}

configure_automation_trigger() {
    log INFO "Configuring automation trigger..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would configure daily trigger at 8 AM"
        return 0
    fi
    
    log INFO "Setting up automated trigger:"
    log INFO "1. In your Apps Script project, run the 'createDailyTrigger' function"
    log INFO "2. Grant necessary permissions when prompted"
    log INFO "3. Verify the trigger was created in the Triggers section"
    
    confirm_action "Please configure the automation trigger as described"
    
    log INFO "✅ Automation trigger configuration completed"
}

test_deployment() {
    log INFO "Testing deployment functionality..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY-RUN] Would run test functions"
        log INFO "[DRY-RUN] Would verify calendar event creation"
        return 0
    fi
    
    log INFO "Running deployment tests:"
    log INFO "1. In Apps Script, run 'testEventReading' function"
    log INFO "2. Check execution logs for successful data reading"
    log INFO "3. Run 'testSingleEvent' function to create a test event"
    log INFO "4. Verify test event appears in your Google Calendar"
    log INFO "5. Run 'testFullAutomation' to test complete workflow"
    
    confirm_action "Please complete the testing steps above"
    
    log INFO "✅ Deployment testing completed"
}

##############################################################################
# Main Deployment Flow
##############################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
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
    echo "# Deployment Log - $(date -Iseconds)" > "$LOG_FILE"
    
    log INFO "Starting deployment of Automated Event Creation with Apps Script"
    log INFO "Project: $PROJECT_NAME"
    log INFO "Dry run mode: $DRY_RUN"
    
    # Trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Execute deployment steps
    check_prerequisites
    check_google_services
    create_environment_setup
    create_google_sheet
    deploy_apps_script
    configure_automation_trigger
    test_deployment
    
    DEPLOYMENT_SUCCESS=true
    
    log INFO "🎉 Deployment completed successfully!"
    log INFO "📋 Next steps:"
    log INFO "  1. Test event creation by adding data to your Google Sheet"
    log INFO "  2. Monitor Apps Script execution logs for any issues"
    log INFO "  3. Check your Google Calendar for automated events"
    log INFO "  4. Review email notifications for automation summaries"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "📄 Deployment log saved to: $LOG_FILE"
        log INFO "🗑️  To clean up resources, run: ./destroy.sh"
    fi
}

cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 && "$DEPLOYMENT_SUCCESS" == "false" ]]; then
        log ERROR "Deployment failed with exit code: $exit_code"
        log INFO "Check the log file for details: $LOG_FILE"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log INFO "To clean up any partial deployment, run: ./destroy.sh"
        fi
    fi
    
    # Clean up temporary files if dry run
    if [[ "$DRY_RUN" == "true" && -n "${DEPLOYMENT_DIR:-}" && -d "$DEPLOYMENT_DIR" ]]; then
        rm -rf "$DEPLOYMENT_DIR"
    fi
}

# Execute main function
main "$@"