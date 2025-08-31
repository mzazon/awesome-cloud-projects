#!/bin/bash

# Amazon Q Developer Cleanup - Destroy Script
# Removes Amazon Q Developer extension and cleans up configuration
# Author: AWS Recipe Generator
# Version: 1.0

set -e  # Exit on any error
set -o pipefail  # Exit on any pipe failure

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
VSCODE_EXTENSION_ID="AmazonWebServices.amazon-q-vscode"

# ANSI color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Function to print colored output
print_color() {
    echo -e "${2}${1}${NC}"
}

# Function to print step headers
print_step() {
    print_color "=== $1 ===" "${BLUE}"
    log "STEP: $1"
}

# Function to print success messages
print_success() {
    print_color "✅ $1" "${GREEN}"
    log "SUCCESS: $1"
}

# Function to print warning messages
print_warning() {
    print_color "⚠️  $1" "${YELLOW}"
    log "WARNING: $1"
}

# Function to print error messages and exit
print_error() {
    print_color "❌ $1" "${RED}"
    log "ERROR: $1"
    exit 1
}

# Function to print info messages
print_info() {
    print_color "ℹ️  $1" "${BLUE}"
    log "INFO: $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt user for confirmation
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${FORCE_YES}" == "true" ]]; then
        print_info "Auto-confirming: ${message}"
        return 0
    fi
    
    while true; do
        if [[ "${default}" == "y" ]]; then
            read -p "${message} [Y/n]: " -r response
            response=${response:-y}
        else
            read -p "${message} [y/N]: " -r response
            response=${response:-n}
        fi
        
        case "${response}" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                print_warning "Please answer yes (y) or no (n)"
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    # Check for VS Code
    if ! command_exists code; then
        print_error "VS Code (code command) not found. Cannot proceed with cleanup."
    fi
    
    local vscode_version
    vscode_version=$(code --version | head -n1)
    print_success "VS Code found: ${vscode_version}"
    log "VS Code version: ${vscode_version}"
    
    print_success "Prerequisites check completed"
}

# Function to display current extension status
show_extension_status() {
    print_step "Current Amazon Q Developer Extension Status"
    
    # Check if extension is installed
    if code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        local extension_info
        extension_info=$(code --list-extensions --show-versions 2>/dev/null | grep "${VSCODE_EXTENSION_ID}")
        print_info "Extension installed: ${extension_info}"
        log "Current extension status: ${extension_info}"
        
        # Check if extension is enabled
        print_info "Extension is currently installed and available"
        return 0
    else
        print_warning "Amazon Q Developer extension is not currently installed"
        log "Extension not found: ${VSCODE_EXTENSION_ID}"
        return 1
    fi
}

# Function to handle VS Code processes
handle_vscode_processes() {
    print_step "Checking VS Code Processes"
    
    # Check if VS Code is running
    if pgrep -f "Visual Studio Code" >/dev/null 2>&1 || pgrep -f "code" >/dev/null 2>&1; then
        print_warning "VS Code is currently running"
        
        if confirm_action "Would you like to close VS Code before proceeding?" "n"; then
            print_info "Attempting to close VS Code gracefully..."
            
            # Try to close VS Code gracefully
            pkill -f "Visual Studio Code" 2>/dev/null || true
            pkill -f "code" 2>/dev/null || true
            
            # Wait a moment for graceful shutdown
            sleep 3
            
            # Check if still running
            if pgrep -f "Visual Studio Code" >/dev/null 2>&1 || pgrep -f "code" >/dev/null 2>&1; then
                print_warning "VS Code is still running. You may need to close it manually."
            else
                print_success "VS Code closed successfully"
            fi
        else
            print_info "Continuing with VS Code running (extension changes will take effect after restart)"
        fi
    else
        print_success "VS Code is not currently running"
    fi
}

# Function to disable Amazon Q Developer extension
disable_extension() {
    print_step "Disabling Amazon Q Developer Extension"
    
    # Check if extension is installed
    if ! code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_warning "Extension is not installed, skipping disable step"
        return 0
    fi
    
    # Disable the extension
    log "Disabling extension: ${VSCODE_EXTENSION_ID}"
    if code --disable-extension "${VSCODE_EXTENSION_ID}" 2>&1 | tee -a "${LOG_FILE}"; then
        print_success "Amazon Q Developer extension disabled"
    else
        print_warning "Failed to disable extension (may not affect uninstallation)"
    fi
}

# Function to uninstall Amazon Q Developer extension
uninstall_extension() {
    print_step "Uninstalling Amazon Q Developer Extension"
    
    # Check if extension is installed
    if ! code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_warning "Extension is not installed, nothing to uninstall"
        return 0
    fi
    
    # Confirm uninstallation
    if ! confirm_action "Are you sure you want to uninstall the Amazon Q Developer extension?" "n"; then
        print_info "Extension uninstallation cancelled by user"
        return 0
    fi
    
    # Uninstall the extension
    log "Uninstalling extension: ${VSCODE_EXTENSION_ID}"
    if code --uninstall-extension "${VSCODE_EXTENSION_ID}" 2>&1 | tee -a "${LOG_FILE}"; then
        print_success "Amazon Q Developer extension uninstalled successfully"
    else
        print_error "Failed to uninstall Amazon Q Developer extension"
    fi
    
    # Verify uninstallation
    if code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_error "Extension uninstallation verification failed - extension still present"
    else
        print_success "Extension uninstallation verified"
    fi
}

# Function to provide authentication cleanup instructions
provide_auth_cleanup_instructions() {
    print_step "Authentication Cleanup Instructions"
    
    cat << EOF

$(print_color "🔧 Manual Authentication Cleanup Required:" "${YELLOW}")

To complete the cleanup of Amazon Q Developer, you may want to:

1. $(print_color "Sign out from Amazon Q (if VS Code is running):" "${BLUE}")
   - Open VS Code
   - Look for Amazon Q panel (if extension was running)
   - Find sign-out or disconnect option
   - Confirm sign-out when prompted

2. $(print_color "Revoke AWS Builder ID Authentication (optional):" "${BLUE}")
   - Visit AWS Builder ID console: https://profile.aws.amazon.com/
   - Review connected applications
   - Revoke Amazon Q Developer access if desired

3. $(print_color "Clear VS Code Settings (optional):" "${BLUE}")
   - Open VS Code Settings (Ctrl+, or Cmd+,)
   - Search for "Amazon Q" settings
   - Reset or remove custom configurations

4. $(print_color "Clear Extension Data (optional):" "${BLUE}")
   VS Code extension data locations:
   - Windows: %USERPROFILE%\.vscode\extensions\
   - macOS: ~/.vscode/extensions/
   - Linux: ~/.vscode/extensions/
   
   Look for folders containing 'amazon' or 'q-developer'

$(print_color "Note:" "${YELLOW}") Authentication tokens are managed by VS Code and AWS services.
Extension removal should clear most local data automatically.

EOF
}

# Function to clean up log files
cleanup_logs() {
    print_step "Cleaning Up Log Files"
    
    local deploy_log="${SCRIPT_DIR}/deploy.log"
    
    if [[ -f "${deploy_log}" ]]; then
        if confirm_action "Remove deployment log file (${deploy_log})?" "y"; then
            rm -f "${deploy_log}"
            print_success "Deployment log file removed"
            log "Deployment log file removed: ${deploy_log}"
        else
            print_info "Keeping deployment log file: ${deploy_log}"
        fi
    fi
    
    # Note: We don't remove the current destroy log until the end
    print_info "Current destroy log will be preserved: ${LOG_FILE}"
}

# Function to validate cleanup
validate_cleanup() {
    print_step "Validating Cleanup"
    
    # Check extension removal
    if code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_warning "Amazon Q Developer extension is still installed"
        log "Extension still present after cleanup attempt"
    else
        print_success "Amazon Q Developer extension successfully removed"
    fi
    
    print_success "Cleanup validation completed"
}

# Function to generate cleanup summary
generate_summary() {
    print_step "Cleanup Summary"
    
    cat << EOF

$(print_color "🧹 Amazon Q Developer Cleanup Complete!" "${GREEN}")

$(print_color "What was cleaned up:" "${BLUE}")
✅ Amazon Q Developer VS Code extension removed
✅ Extension disabled and uninstalled
✅ Cleanup instructions provided for authentication

$(print_color "Manual Steps (Optional):" "${BLUE}")
• Sign out from Amazon Q in VS Code (if running)
• Revoke AWS Builder ID authentication
• Clear VS Code settings and extension data
• Remove authentication tokens

$(print_color "Important Notes:" "${BLUE}")
• VS Code may need to be restarted to complete cleanup
• Authentication with AWS Builder ID remains active until manually revoked
• No AWS resources were created, so no cloud cleanup needed
• Extension can be reinstalled anytime from VS Code marketplace

$(print_color "To reinstall Amazon Q Developer:" "${BLUE}")
Run the deployment script again: ./deploy.sh

$(print_color "Log file location: ${LOG_FILE}" "${YELLOW}")

EOF
}

# Function to show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -f, --force-yes    Auto-confirm all prompts (non-interactive mode)
  -h, --help         Show this help message
  
Examples:
  $0                 Interactive cleanup with prompts
  $0 --force-yes     Non-interactive cleanup (auto-confirm all)

EOF
}

# Main cleanup function
main() {
    print_color "Amazon Q Developer Cleanup - Destroy Script" "${BLUE}"
    print_color "===============================================" "${BLUE}"
    
    # Initialize log file
    echo "Amazon Q Developer cleanup started at $(date)" > "${LOG_FILE}"
    
    # Check if extension is installed before proceeding
    if ! show_extension_status; then
        print_info "No Amazon Q Developer extension found to remove"
        if ! confirm_action "Continue with cleanup anyway?" "n"; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Run cleanup steps
    check_prerequisites
    handle_vscode_processes
    disable_extension
    uninstall_extension
    provide_auth_cleanup_instructions
    cleanup_logs
    validate_cleanup
    generate_summary
    
    print_success "Amazon Q Developer cleanup completed successfully!"
    log "Cleanup completed successfully at $(date)"
}

# Parse command line arguments
FORCE_YES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force-yes)
            FORCE_YES=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Script execution with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle script interruption
    trap 'print_error "Script interrupted by user"' INT TERM
    
    # Run main function
    main "$@"
fi