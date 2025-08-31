#!/bin/bash

#
# Content Approval Workflows with AI Builder and Power Automate - Deployment Script
# 
# This script automates the deployment of intelligent content approval system using
# AI Builder's prompt templates, Power Automate workflows, SharePoint Online, and Teams.
#
# Prerequisites:
# - Microsoft 365 subscription with Power Platform access (E3/E5 or standalone licenses)
# - SharePoint Online site collection with document library creation permissions  
# - Power Automate premium license for AI Builder capabilities
# - Teams admin permissions for creating custom apps and workflows
# - PnP PowerShell module installed for SharePoint configuration
#
# Usage: ./deploy.sh
#

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment_$(date +%Y%m%d_%H%M%S).log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${LOG_FILE} for detailed error information"
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# Save deployment state
save_deployment_state() {
    local component=$1
    local status=$2
    echo "${component}=${status}" >> "${DEPLOYMENT_STATE_FILE}"
    log_info "Saved deployment state: ${component}=${status}"
}

# Check if component is already deployed
is_component_deployed() {
    local component=$1
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        grep -q "^${component}=completed$" "${DEPLOYMENT_STATE_FILE}" 2>/dev/null || return 1
    else
        return 1
    fi
}

# Cleanup function for graceful exit
cleanup() {
    log_info "Performing cleanup operations..."
    # Add any cleanup logic here if needed
}

trap cleanup EXIT

# Display banner
display_banner() {
    echo "================================================================"
    echo "  Content Approval Workflows Deployment Script"
    echo "  AI Builder + Power Automate + SharePoint + Teams"
    echo "================================================================"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_prereqs=()
    
    # Check if PowerShell is available
    if ! command -v pwsh >/dev/null 2>&1; then
        missing_prereqs+=("PowerShell Core (pwsh)")
    fi
    
    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        missing_prereqs+=("Azure CLI")
    fi
    
    # Check if curl is available for API calls
    if ! command -v curl >/dev/null 2>&1; then
        missing_prereqs+=("curl")
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq >/dev/null 2>&1; then
        missing_prereqs+=("jq")
    fi
    
    if [[ ${#missing_prereqs[@]} -gt 0 ]]; then
        log_error "Missing prerequisites:"
        for prereq in "${missing_prereqs[@]}"; do
            log_error "  - ${prereq}"
        done
        log_error "Please install missing prerequisites and try again."
        exit 1
    fi
    
    log_success "All prerequisites are available"
}

# Get user configuration
get_user_configuration() {
    log_info "Gathering deployment configuration..."
    
    # Set environment variables for deployment
    if [[ -z "${TENANT_NAME:-}" ]]; then
        read -p "Enter your Microsoft 365 tenant name (e.g., contoso): " TENANT_NAME
        export TENANT_NAME
    fi
    
    if [[ -z "${TENANT_DOMAIN:-}" ]]; then
        TENANT_DOMAIN="${TENANT_NAME}.onmicrosoft.com"
        export TENANT_DOMAIN
    fi
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
        export RANDOM_SUFFIX
    fi
    
    # Set SharePoint site and library names
    export SITE_NAME="content-approval-${RANDOM_SUFFIX}"
    export SITE_URL="https://${TENANT_NAME}.sharepoint.com/sites/${SITE_NAME}"
    export LIBRARY_NAME="DocumentsForApproval"
    export LIBRARY_DISPLAY_NAME="Documents for Approval"
    
    log_info "Configuration:"
    log_info "  Tenant: ${TENANT_NAME}"  
    log_info "  Site Name: ${SITE_NAME}"
    log_info "  Site URL: ${SITE_URL}"
    log_info "  Library Name: ${LIBRARY_DISPLAY_NAME}"
    
    # Confirm configuration with user
    echo ""
    read -p "Continue with this configuration? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Check Azure authentication
check_azure_authentication() {
    log_info "Checking Azure authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        log_info "Azure CLI not authenticated. Please sign in..."
        az login --allow-no-subscriptions
    fi
    
    # Get current user information
    local user_info
    user_info=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "unknown")
    log_success "Authenticated as: ${user_info}"
}

# Check PowerShell modules
check_powershell_modules() {
    log_info "Checking PowerShell modules..."
    
    # Create PowerShell script to check and install modules
    cat > "${SCRIPT_DIR}/check_modules.ps1" << 'EOF'
$ErrorActionPreference = "Stop"

# Check for PnP PowerShell module
$pnpModule = Get-Module -ListAvailable -Name "PnP.PowerShell" | Select-Object -First 1
if (-not $pnpModule) {
    Write-Host "Installing PnP PowerShell module..." -ForegroundColor Yellow
    Install-Module -Name "PnP.PowerShell" -Force -AllowClobber -Scope CurrentUser
    Write-Host "PnP PowerShell module installed successfully" -ForegroundColor Green
} else {
    Write-Host "PnP PowerShell module is already installed (Version: $($pnpModule.Version))" -ForegroundColor Green
}

# Check for Microsoft Graph PowerShell module
$graphModule = Get-Module -ListAvailable -Name "Microsoft.Graph" | Select-Object -First 1
if (-not $graphModule) {
    Write-Host "Installing Microsoft Graph PowerShell module..." -ForegroundColor Yellow
    Install-Module -Name "Microsoft.Graph" -Force -AllowClobber -Scope CurrentUser
    Write-Host "Microsoft Graph PowerShell module installed successfully" -ForegroundColor Green
} else {
    Write-Host "Microsoft Graph PowerShell module is already installed (Version: $($graphModule.Version))" -ForegroundColor Green
}
EOF
    
    pwsh -File "${SCRIPT_DIR}/check_modules.ps1"
    rm -f "${SCRIPT_DIR}/check_modules.ps1"
    
    log_success "PowerShell modules are ready"
}

# Create SharePoint site and document library
create_sharepoint_resources() {
    if is_component_deployed "sharepoint"; then
        log_info "SharePoint resources already deployed, skipping..."
        return 0
    fi
    
    log_info "Creating SharePoint site and document library..."
    
    # Create PowerShell script for SharePoint operations
    cat > "${SCRIPT_DIR}/create_sharepoint.ps1" << EOF
\$ErrorActionPreference = "Stop"

try {
    # Import PnP PowerShell module
    Import-Module PnP.PowerShell -Force
    
    Write-Host "Connecting to SharePoint Admin Center..." -ForegroundColor Yellow
    
    # Connect to SharePoint Online Admin Center
    Connect-PnPOnline -Url "https://${TENANT_NAME}-admin.sharepoint.com" -Interactive
    
    Write-Host "Creating SharePoint team site..." -ForegroundColor Yellow
    
    # Create new SharePoint team site
    \$site = New-PnPSite -Type TeamSite \`
        -Title "Content Approval Workflows" \`
        -Alias "${SITE_NAME}" \`
        -Description "Intelligent content approval system with AI Builder and Power Automate" \`
        -IsPublic:\$false
    
    Write-Host "SharePoint site created: \$(\$site.Url)" -ForegroundColor Green
    
    # Wait for site to be fully provisioned
    Start-Sleep -Seconds 30
    
    # Connect to the new site
    Connect-PnPOnline -Url "${SITE_URL}" -Interactive
    
    Write-Host "Creating document library with content approval..." -ForegroundColor Yellow
    
    # Create document library with content approval enabled
    \$library = New-PnPList -Title "${LIBRARY_DISPLAY_NAME}" \`
        -Template DocumentLibrary \`
        -EnableContentTypes \`
        -EnableVersioning
    
    # Enable content approval on the library
    Set-PnPList -Identity "${LIBRARY_NAME}" \`
        -EnableContentApproval \$true \`
        -EnableMinorVersions \$true
    
    Write-Host "Adding custom columns for AI analysis..." -ForegroundColor Yellow
    
    # Add custom columns for AI analysis results
    Add-PnPField -List "${LIBRARY_NAME}" \`
        -DisplayName "Content Category" \`
        -InternalName "ContentCategory" \`
        -Type Text \`
        -Group "AI Analysis"
    
    Add-PnPField -List "${LIBRARY_NAME}" \`
        -DisplayName "AI Review Summary" \`
        -InternalName "AIReviewSummary" \`
        -Type Note \`
        -Group "AI Analysis"
    
    Add-PnPField -List "${LIBRARY_NAME}" \`
        -DisplayName "Risk Level" \`
        -InternalName "RiskLevel" \`
        -Type Choice \`
        -Choices "Low","Medium","High","Critical" \`
        -Group "AI Analysis"
    
    Add-PnPField -List "${LIBRARY_NAME}" \`
        -DisplayName "Workflow Status" \`
        -InternalName "WorkflowStatus" \`
        -Type Choice \`
        -Choices "Pending","In Review","Approved","Rejected" \`
        -DefaultValue "Pending" \`
        -Group "Workflow"
    
    Write-Host "Document library configured successfully" -ForegroundColor Green
    
    # Get library information
    \$libraryInfo = Get-PnPList -Identity "${LIBRARY_NAME}"
    Write-Host "Library URL: \$(\$libraryInfo.DefaultViewUrl)" -ForegroundColor Green
    
    Write-Host "SharePoint resources created successfully!" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create SharePoint resources: \$(\$_.Exception.Message)"
    exit 1
}
EOF
    
    if pwsh -File "${SCRIPT_DIR}/create_sharepoint.ps1"; then
        rm -f "${SCRIPT_DIR}/create_sharepoint.ps1"
        save_deployment_state "sharepoint" "completed"
        log_success "SharePoint site and document library created successfully"
    else
        rm -f "${SCRIPT_DIR}/create_sharepoint.ps1"
        log_error "Failed to create SharePoint resources"
        return 1
    fi
}

# Configure AI Builder prompt
configure_ai_builder() {
    if is_component_deployed "ai_builder"; then
        log_info "AI Builder prompt already configured, skipping..."
        return 0
    fi
    
    log_info "Configuring AI Builder prompt for content analysis..."
    
    log_warning "AI Builder prompt configuration requires manual setup:"
    echo ""
    echo "Please complete the following steps manually:"
    echo "1. Navigate to https://make.powerapps.com/"
    echo "2. Select 'AI hub' > 'Prompts' from left navigation"
    echo "3. Choose 'Create custom prompt'"
    echo "4. Configure the prompt with these settings:"
    echo "   - Name: Content Approval Analyzer"
    echo "   - Description: Analyzes document content for approval routing"
    echo "   - Input Type: Text (document content)"
    echo ""
    echo "5. Use this prompt template:"
    echo "   'Analyze the following document content and provide a JSON response"
    echo "   with these fields: category (Marketing, Legal, Technical, General),"
    echo "   riskLevel (Low, Medium, High, Critical), summary (2-3 sentences),"
    echo "   recommendations (approval actions needed)."
    echo ""
    echo "   Document content: {DocumentContent}'"
    echo ""
    echo "6. Test the prompt with sample content"
    echo "7. Save and publish the prompt"
    echo ""
    
    read -p "Have you completed the AI Builder prompt configuration? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        save_deployment_state "ai_builder" "completed"
        log_success "AI Builder prompt configuration completed"
    else
        log_warning "AI Builder prompt configuration marked as incomplete"
        log_warning "Please complete this step before proceeding with the workflow"
    fi
}

# Create Power Automate workflow
create_power_automate_workflow() {
    if is_component_deployed "power_automate"; then
        log_info "Power Automate workflow already configured, skipping..."
        return 0
    fi
    
    log_info "Configuring Power Automate workflow..."
    
    log_warning "Power Automate workflow requires manual configuration:"
    echo ""
    echo "Please complete the following steps manually:"
    echo "1. Navigate to https://make.powerautomate.com/"
    echo "2. Select 'Create' > 'Automated cloud flow'"
    echo "3. Configure the trigger:"
    echo "   - Flow Name: Intelligent Content Approval Workflow"
    echo "   - Trigger: SharePoint - When a file is created (properties only)"
    echo "   - Site Address: ${SITE_URL}"
    echo "   - Library Name: ${LIBRARY_DISPLAY_NAME}"
    echo ""
    echo "4. Add these workflow steps in sequence:"
    echo "   a. 'Get file content' (SharePoint connector)"
    echo "   b. 'Create text with AI Builder' (use your custom prompt)"
    echo "   c. 'Parse JSON' (parse AI Builder response)"
    echo "   d. 'Update file properties' (add AI analysis to SharePoint)"
    echo "   e. 'Condition' (based on risk level from AI analysis)"
    echo "   f. 'Start and wait for an approval' (based on risk assessment)"
    echo "   g. 'Post adaptive card and wait for response' (Teams)"
    echo "   h. 'Update file properties' (final approval status)"
    echo ""
    echo "5. Configure conditional routing:"
    echo "   - High/Critical Risk: Multiple approvers (Legal + Manager)"
    echo "   - Medium Risk: Single approver (Content Manager)"  
    echo "   - Low Risk: Auto-approve or manager approval"
    echo ""
    echo "6. Test the workflow with a sample document"
    echo "7. Save and enable the workflow"
    echo ""
    
    read -p "Have you completed the Power Automate workflow configuration? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        save_deployment_state "power_automate" "completed"
        log_success "Power Automate workflow configuration completed"
    else
        log_warning "Power Automate workflow configuration marked as incomplete"
        log_warning "Please complete this step to enable the approval automation"
    fi
}

# Configure Teams integration
configure_teams_integration() {
    if is_component_deployed "teams"; then
        log_info "Teams integration already configured, skipping..."
        return 0
    fi
    
    log_info "Configuring Teams integration..."
    
    log_warning "Teams integration configuration:"
    echo ""
    echo "The Power Automate workflow includes Teams integration via adaptive cards."
    echo "Ensure the following:"
    echo ""
    echo "1. Teams notifications are configured in the Power Automate workflow"
    echo "2. Adaptive cards include:"
    echo "   - Document title and metadata"
    echo "   - AI analysis summary and risk level"
    echo "   - Approve/Reject action buttons"
    echo "   - Deep link back to SharePoint document"
    echo "   - Comments field for approval feedback"
    echo ""
    echo "3. Channel notifications are set up for:"
    echo "   - Content Team Channel (for all approvals)"
    echo "   - Management Channel (for high-risk escalations)"
    echo ""
    echo "4. Test Teams notifications with a sample approval"
    echo ""
    
    read -p "Have you configured Teams integration in your workflow? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        save_deployment_state "teams" "completed"
        log_success "Teams integration configuration completed"
    else
        log_warning "Teams integration configuration marked as incomplete"
    fi
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=()
    
    # Check SharePoint site accessibility
    log_info "Validating SharePoint site access..."
    if curl -s -I "${SITE_URL}" | grep -q "200 OK"; then
        log_success "SharePoint site is accessible"
    else
        validation_errors+=("SharePoint site is not accessible")
    fi
    
    # Check if manual configurations are completed
    if ! is_component_deployed "ai_builder"; then
        validation_errors+=("AI Builder prompt not configured")
    fi
    
    if ! is_component_deployed "power_automate"; then
        validation_errors+=("Power Automate workflow not configured")
    fi
    
    if ! is_component_deployed "teams"; then
        validation_errors+=("Teams integration not configured")
    fi
    
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_warning "Deployment validation found issues:"
        for error in "${validation_errors[@]}"; do
            log_warning "  - ${error}"
        done
        log_warning "Please address these issues for full functionality"
    else
        log_success "All deployment components validated successfully"
    fi
}

# Generate deployment summary
generate_deployment_summary() {
    log_info "Generating deployment summary..."
    
    local summary_file="${SCRIPT_DIR}/deployment_summary_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "${summary_file}" << EOF
# Content Approval Workflows Deployment Summary

## Deployment Information
- **Date**: $(date)
- **Tenant**: ${TENANT_NAME}
- **Site URL**: ${SITE_URL}
- **Library**: ${LIBRARY_DISPLAY_NAME}

## Deployed Components

### SharePoint Resources
- [x] SharePoint team site created
- [x] Document library with content approval enabled
- [x] Custom columns for AI analysis results
- [x] Workflow metadata fields configured

### AI Builder Configuration
- [ ] Custom prompt for content analysis (requires manual setup)
- [ ] Prompt testing and validation (requires manual setup)

### Power Automate Workflow
- [ ] Automated cloud flow created (requires manual setup)
- [ ] SharePoint trigger configured (requires manual setup)
- [ ] AI Builder integration (requires manual setup)
- [ ] Conditional approval routing (requires manual setup)

### Teams Integration
- [ ] Adaptive cards for approvals (requires manual setup)
- [ ] Channel notifications configured (requires manual setup)

## Next Steps

1. **Complete AI Builder Setup**:
   - Navigate to https://make.powerapps.com/
   - Create custom prompt for content analysis
   - Test with sample documents

2. **Configure Power Automate Workflow**:
   - Navigate to https://make.powerautomate.com/
   - Create automated flow with SharePoint trigger
   - Integrate AI Builder prompt
   - Set up conditional approval logic

3. **Test the Complete System**:
   - Upload a test document to the SharePoint library
   - Verify AI analysis populates metadata
   - Confirm approval workflow triggers
   - Test Teams notifications and adaptive cards

4. **Optimize and Monitor**:
   - Monitor AI Builder credit consumption
   - Adjust prompt complexity based on usage
   - Fine-tune approval routing rules
   - Set up workflow analytics and reporting

## Resources

- **SharePoint Site**: ${SITE_URL}
- **Power Apps Maker Portal**: https://make.powerapps.com/
- **Power Automate Portal**: https://make.powerautomate.com/
- **Teams Admin Center**: https://admin.teams.microsoft.com/
- **Deployment Log**: ${LOG_FILE}

## Support

For issues with this deployment:
1. Check the deployment log: ${LOG_FILE}
2. Review Microsoft 365 service health
3. Verify Power Platform licenses and permissions
4. Consult the original recipe documentation

---
*Generated by Content Approval Workflows Deployment Script*
EOF
    
    log_success "Deployment summary generated: ${summary_file}"
    
    # Display summary
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    cat "${summary_file}"
    echo "=========================="
}

# Main deployment function
main() {
    display_banner
    
    # Initialize logging
    log "Starting Content Approval Workflows deployment..."
    log "Script version: 1.0"
    log "Log file: ${LOG_FILE}"
    
    # Pre-deployment checks
    check_prerequisites
    get_user_configuration
    check_azure_authentication
    check_powershell_modules
    
    # Core deployment steps
    log_info "Beginning deployment process..."
    
    create_sharepoint_resources
    configure_ai_builder
    create_power_automate_workflow
    configure_teams_integration
    
    # Post-deployment validation
    validate_deployment
    generate_deployment_summary
    
    log_success "Content Approval Workflows deployment completed!"
    log_info "Please review the deployment summary and complete manual configuration steps"
    log_info "Deployment log available at: ${LOG_FILE}"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi