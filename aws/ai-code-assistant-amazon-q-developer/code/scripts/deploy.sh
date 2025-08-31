#!/bin/bash

# Amazon Q Developer Setup - Deployment Script
# Automates the installation and setup of Amazon Q Developer extension for VS Code
# Author: AWS Recipe Generator
# Version: 1.0

set -e  # Exit on any error
set -o pipefail  # Exit on any pipe failure

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
VSCODE_EXTENSION_ID="AmazonWebServices.amazon-q-vscode"
Q_MARKETPLACE_URL="https://marketplace.visualstudio.com/items?itemName=AmazonWebServices.amazon-q-vscode"

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_step "Checking Prerequisites"
    
    local missing_deps=()
    
    # Check for VS Code
    if ! command_exists code; then
        missing_deps+=("Visual Studio Code (code command)")
    else
        local vscode_version
        vscode_version=$(code --version | head -n1)
        print_success "VS Code found: ${vscode_version}"
        log "VS Code version: ${vscode_version}"
        
        # Check VS Code version is 1.85.0 or higher
        local version_major version_minor
        version_major=$(echo "${vscode_version}" | cut -d. -f1)
        version_minor=$(echo "${vscode_version}" | cut -d. -f2)
        
        if [[ ${version_major} -lt 1 ]] || [[ ${version_major} -eq 1 && ${version_minor} -lt 85 ]]; then
            print_warning "VS Code version ${vscode_version} may not be compatible. Recommended: 1.85.0 or higher"
        fi
    fi
    
    # Check internet connectivity
    if ! curl -s --connect-timeout 5 https://marketplace.visualstudio.com >/dev/null; then
        missing_deps+=("Internet connection to VS Code Marketplace")
    else
        print_success "Internet connectivity verified"
    fi
    
    # Check for AWS CLI (optional)
    if command_exists aws; then
        local aws_version
        aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
        print_success "AWS CLI found (optional): ${aws_version}"
        log "AWS CLI version: ${aws_version}"
    else
        print_warning "AWS CLI not found (optional - proceeding with Builder ID setup)"
    fi
    
    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
    fi
    
    print_success "All prerequisites satisfied"
}

# Function to prepare environment
prepare_environment() {
    print_step "Preparing Environment"
    
    # Set environment variables
    export VSCODE_EXTENSION_ID="${VSCODE_EXTENSION_ID}"
    export Q_MARKETPLACE_URL="${Q_MARKETPLACE_URL}"
    
    log "Environment variables set:"
    log "  VSCODE_EXTENSION_ID=${VSCODE_EXTENSION_ID}"
    log "  Q_MARKETPLACE_URL=${Q_MARKETPLACE_URL}"
    
    print_success "Environment prepared for Amazon Q Developer setup"
}

# Function to install Amazon Q Developer extension
install_extension() {
    print_step "Installing Amazon Q Developer Extension"
    
    # Check if extension is already installed
    if code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_warning "Amazon Q Developer extension is already installed"
        log "Extension already installed: ${VSCODE_EXTENSION_ID}"
        return 0
    fi
    
    # Install the extension
    log "Installing extension: ${VSCODE_EXTENSION_ID}"
    if code --install-extension "${VSCODE_EXTENSION_ID}" --force 2>&1 | tee -a "${LOG_FILE}"; then
        print_success "Amazon Q Developer extension installed successfully"
    else
        print_error "Failed to install Amazon Q Developer extension"
    fi
    
    # Verify installation
    if code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_success "Extension installation verified"
    else
        print_error "Extension installation verification failed"
    fi
}

# Function to launch VS Code with extension
launch_vscode() {
    print_step "Launching VS Code with Amazon Q Extension"
    
    # Check if VS Code is already running
    if pgrep -f "Visual Studio Code" >/dev/null 2>&1 || pgrep -f "code" >/dev/null 2>&1; then
        print_warning "VS Code appears to be already running"
    fi
    
    # Launch VS Code in the background
    log "Launching VS Code"
    if code . >/dev/null 2>&1 &
    then
        print_success "VS Code launched successfully"
        print_color "Look for the Amazon Q icon in the VS Code activity bar (left sidebar)" "${BLUE}"
        print_color "The Amazon Q icon appears as a stylized 'Q' symbol" "${BLUE}"
    else
        print_warning "Failed to launch VS Code automatically - please launch manually"
    fi
}

# Function to provide setup instructions
provide_setup_instructions() {
    print_step "Amazon Q Developer Setup Instructions"
    
    cat << EOF

$(print_color "🔧 Next Steps for Amazon Q Developer Setup:" "${BLUE}")

1. $(print_color "Locate Amazon Q in VS Code:" "${GREEN}")
   - Look for the Amazon Q icon in the activity bar (left sidebar)
   - Click the Amazon Q icon to open the panel

2. $(print_color "Authenticate with Amazon Q:" "${GREEN}")
   - Click 'Start using Amazon Q' or similar prompt
   - Choose your authentication method:
     • AWS Builder ID: Free individual use (recommended for new users)
     • IAM Identity Center: Enterprise/Pro subscription

3. $(print_color "For AWS Builder ID (Free):" "${GREEN}")
   - Select "Personal account" or "AWS Builder ID" option
   - Click "Continue" to open browser authentication
   - Create a new Builder ID account if needed (free)
   - Complete the authentication process in your browser
   - Return to VS Code when authentication completes

4. $(print_color "Configure Settings (Optional):" "${GREEN}")
   - Open VS Code Settings (Ctrl+, or Cmd+,)
   - Search for "Amazon Q" in settings
   - Adjust preferences for inline suggestions and chat behavior

5. $(print_color "Test Amazon Q Features:" "${GREEN}")
   - Create a new code file (e.g., test.py, test.js)
   - Start typing code to see inline suggestions
   - Open Amazon Q chat panel and ask questions
   - Try agent commands like /dev, /test, /review, /doc

$(print_color "📚 Additional Resources:" "${BLUE}")
- Extension marketplace: ${Q_MARKETPLACE_URL}
- AWS Documentation: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/
- Builder ID Setup: https://docs.aws.amazon.com/amazonq/latest/qdeveloper-ug/q-in-IDE-setup.html

EOF
}

# Function to perform validation
validate_deployment() {
    print_step "Validating Deployment"
    
    # Check extension installation
    if code --list-extensions 2>/dev/null | grep -q "${VSCODE_EXTENSION_ID}"; then
        print_success "Amazon Q Developer extension is installed"
    else
        print_error "Amazon Q Developer extension is not installed"
    fi
    
    # Check extension is enabled
    local extension_status
    extension_status=$(code --list-extensions --show-versions 2>/dev/null | grep "${VSCODE_EXTENSION_ID}" || echo "not found")
    if [[ "${extension_status}" != "not found" ]]; then
        print_success "Extension status: ${extension_status}"
        log "Extension status: ${extension_status}"
    else
        print_error "Extension not found in enabled extensions"
    fi
    
    print_success "Deployment validation completed"
}

# Function to generate deployment summary
generate_summary() {
    print_step "Deployment Summary"
    
    cat << EOF

$(print_color "🚀 Amazon Q Developer Deployment Complete!" "${GREEN}")

$(print_color "What was deployed:" "${BLUE}")
✅ Amazon Q Developer VS Code extension (${VSCODE_EXTENSION_ID})
✅ VS Code launched with extension active
✅ Setup instructions provided for authentication

$(print_color "Authentication Options:" "${BLUE}")
• AWS Builder ID: Free tier with generous usage limits
• IAM Identity Center: Enterprise Pro features (\$19/user/month)

$(print_color "Key Features Available:" "${BLUE}")
• Inline code suggestions (15+ programming languages)
• AI-powered chat interface with AWS expertise
• Security scanning and vulnerability detection
• Agent commands for advanced development tasks
• Integration with AWS documentation and best practices

$(print_color "Cost Information:" "${BLUE}")
• AWS Builder ID: Free (no AWS account required)
• Amazon Q Developer Pro: \$19/user/month (IAM Identity Center)

$(print_color "Next Steps:" "${BLUE}")
1. Complete authentication setup in VS Code
2. Configure settings based on your preferences
3. Test inline suggestions and chat features
4. Explore agent commands for advanced functionality

$(print_color "Log file location: ${LOG_FILE}" "${YELLOW}")

EOF
}

# Main deployment function
main() {
    print_color "Amazon Q Developer Setup - Deployment Script" "${BLUE}"
    print_color "================================================" "${BLUE}"
    
    # Initialize log file
    echo "Amazon Q Developer deployment started at $(date)" > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    prepare_environment
    install_extension
    launch_vscode
    provide_setup_instructions
    validate_deployment
    generate_summary
    
    print_success "Amazon Q Developer deployment completed successfully!"
    log "Deployment completed successfully at $(date)"
}

# Script execution with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Handle script interruption
    trap 'print_error "Script interrupted by user"' INT TERM
    
    # Run main function
    main "$@"
fi