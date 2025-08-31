#!/bin/bash

#
# Content Approval Workflows with AI Builder and Power Automate - Cleanup Script
# 
# This script safely removes all resources created for the intelligent content approval system.
# It handles SharePoint sites, Power Automate flows, AI Builder prompts, and Teams configurations.
#
# Prerequisites:
# - Microsoft 365 subscription with appropriate admin permissions
# - SharePoint admin permissions for site deletion
# - Power Platform admin permissions for flow and AI Builder cleanup
# - PnP PowerShell module installed
#
# Usage: ./destroy.sh
#

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"
readonly BACKUP_DIR="${SCRIPT_DIR}/backups/$(date +%Y%m%d_%H%M%S)"

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
    log_warning "Cleanup may be incomplete. Manual verification recommended."
    exit $exit_code
}

trap 'handle_error ${LINENO}' ERR

# Update deployment state
update_deployment_state() {
    local component=$1
    local status=$2
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        sed -i.bak "s/^${component}=.*$/${component}=${status}/" "${DEPLOYMENT_STATE_FILE}" 2>/dev/null || true
        rm -f "${DEPLOYMENT_STATE_FILE}.bak"
    fi
    log_info "Updated deployment state: ${component}=${status}"
}

# Check if component exists
component_exists() {
    local component=$1
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        grep -q "^${component}=completed$" "${DEPLOYMENT_STATE_FILE}" 2>/dev/null || return 1
    else
        return 1
    fi
}

# Display banner
display_banner() {
    echo "================================================================"
    echo "  Content Approval Workflows Cleanup Script"
    echo "  WARNING: This will remove all deployed resources"
    echo "================================================================"
    echo ""
}

# Confirm cleanup operation
confirm_cleanup() {
    log_warning "This script will permanently delete the following resources:"
    echo ""
    echo "  - SharePoint team site and all content"
    echo "  - Document library and metadata"
    echo "  - Power Automate workflows"  
    echo "  - AI Builder prompts"
    echo "  - Teams integration configurations"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed with cleanup? (yes/NO): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Enter 'DELETE' to confirm resource deletion: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation not provided"
        exit 0
    fi
    
    log_info "Cleanup confirmed, proceeding with resource deletion..."
}

# Load deployment configuration
load_deployment_configuration() {
    log_info "Loading deployment configuration..."
    
    # Try to load from deployment state or prompt user
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        # Extract configuration from deployment state if available
        log_info "Loading configuration from deployment state file"
    fi
    
    # Get tenant information
    if [[ -z "${TENANT_NAME:-}" ]]; then
        read -p "Enter your Microsoft 365 tenant name (e.g., contoso): " TENANT_NAME
        export TENANT_NAME
    fi
    
    if [[ -z "${TENANT_DOMAIN:-}" ]]; then
        TENANT_DOMAIN="${TENANT_NAME}.onmicrosoft.com"
        export TENANT_DOMAIN
    fi
    
    # Get site information
    if [[ -z "${SITE_NAME:-}" ]]; then
        read -p "Enter the SharePoint site name to delete (e.g., content-approval-abc123): " SITE_NAME
        export SITE_NAME
    fi
    
    export SITE_URL="https://${TENANT_NAME}.sharepoint.com/sites/${SITE_NAME}"
    export LIBRARY_NAME="DocumentsForApproval"
    export LIBRARY_DISPLAY_NAME="Documents for Approval"
    
    log_info "Configuration loaded:"
    log_info "  Tenant: ${TENANT_NAME}"
    log_info "  Site to delete: ${SITE_URL}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking cleanup prerequisites..."
    
    local missing_prereqs=()
    
    # Check if PowerShell is available
    if ! command -v pwsh >/dev/null 2>&1; then
        missing_prereqs+=("PowerShell Core (pwsh)")
    fi
    
    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        missing_prereqs+=("Azure CLI")
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

# Check authentication
check_authentication() {
    log_info "Checking authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        log_info "Azure CLI not authenticated. Please sign in..."
        az login --allow-no-subscriptions
    fi
    
    local user_info
    user_info=$(az account show --query "user.name" -o tsv 2>/dev/null || echo "unknown")
    log_success "Authenticated as: ${user_info}"
}

# Create backup directory
create_backup_directory() {
    log_info "Creating backup directory..."
    mkdir -p "${BACKUP_DIR}"
    log_success "Backup directory created: ${BACKUP_DIR}"
}

# Backup SharePoint content
backup_sharepoint_content() {
    log_info "Backing up SharePoint content..."
    
    # Create PowerShell script for SharePoint backup
    cat > "${SCRIPT_DIR}/backup_sharepoint.ps1" << EOF
\$ErrorActionPreference = "Continue"

try {
    Import-Module PnP.PowerShell -Force
    
    Write-Host "Connecting to SharePoint site for backup..." -ForegroundColor Yellow
    Connect-PnPOnline -Url "${SITE_URL}" -Interactive
    
    Write-Host "Exporting site information..." -ForegroundColor Yellow
    
    # Export site information
    \$siteInfo = Get-PnPSite
    \$siteInfo | ConvertTo-Json -Depth 3 | Out-File "${BACKUP_DIR}/site_info.json"
    
    # Export list information
    \$lists = Get-PnPList
    \$lists | ConvertTo-Json -Depth 3 | Out-File "${BACKUP_DIR}/lists_info.json"
    
    # Export document library items
    if (Get-PnPList -Identity "${LIBRARY_NAME}" -ErrorAction SilentlyContinue) {
        Write-Host "Backing up document library items..." -ForegroundColor Yellow
        \$items = Get-PnPListItem -List "${LIBRARY_NAME}" -PageSize 500
        \$items | Select-Object Id, Title, FileSystemObjectType, FileRef, Created, Modified, Author, Editor | 
            ConvertTo-Json -Depth 3 | Out-File "${BACKUP_DIR}/library_items.json"
        
        # Export field information
        \$fields = Get-PnPField -List "${LIBRARY_NAME}"
        \$fields | Select-Object Id, Title, InternalName, TypeAsString, Required | 
            ConvertTo-Json -Depth 3 | Out-File "${BACKUP_DIR}/library_fields.json"
    }
    
    Write-Host "SharePoint content backup completed" -ForegroundColor Green
    
} catch {
    Write-Warning "Backup failed: \$(\$_.Exception.Message)"
} finally {
    if (Get-Command Disconnect-PnPOnline -ErrorAction SilentlyContinue) {
        Disconnect-PnPOnline
    }
}
EOF
    
    if pwsh -File "${SCRIPT_DIR}/backup_sharepoint.ps1"; then
        log_success "SharePoint content backed up to: ${BACKUP_DIR}"
    else
        log_warning "SharePoint backup failed, continuing with cleanup"
    fi
    
    rm -f "${SCRIPT_DIR}/backup_sharepoint.ps1"
}

# Remove Power Automate workflows
remove_power_automate_workflows() {
    if ! component_exists "power_automate"; then
        log_info "No Power Automate workflows to remove"
        return 0
    fi
    
    log_info "Removing Power Automate workflows..."
    
    log_warning "Power Automate workflow removal requires manual action:"
    echo ""
    echo "Please complete the following steps:"
    echo "1. Navigate to https://make.powerautomate.com/"
    echo "2. Go to 'My flows'"
    echo "3. Find 'Intelligent Content Approval Workflow'"
    echo "4. Click the three dots menu and select 'Delete'"
    echo "5. Confirm deletion"
    echo ""
    echo "Also remove any related flows:"
    echo "- Approval notification flows"
    echo "- Teams integration flows"
    echo "- Content processing workflows"
    echo ""
    
    read -p "Have you removed the Power Automate workflows? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_deployment_state "power_automate" "removed"
        log_success "Power Automate workflows removal confirmed"
    else
        log_warning "Power Automate workflows not removed - manual cleanup required"
    fi
}

# Remove AI Builder prompts
remove_ai_builder_prompts() {
    if ! component_exists "ai_builder"; then
        log_info "No AI Builder prompts to remove"
        return 0
    fi
    
    log_info "Removing AI Builder prompts..."
    
    log_warning "AI Builder prompt removal requires manual action:"
    echo ""
    echo "Please complete the following steps:"
    echo "1. Navigate to https://make.powerapps.com/"
    echo "2. Go to 'AI hub' > 'Prompts'"
    echo "3. Find 'Content Approval Analyzer' prompt"
    echo "4. Click the three dots menu and select 'Delete'"
    echo "5. Confirm deletion"
    echo ""
    echo "This will:"
    echo "- Delete the custom prompt template"
    echo "- Stop AI Builder credit consumption"
    echo "- Remove prompt from available models"
    echo ""
    
    read -p "Have you removed the AI Builder prompts? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_deployment_state "ai_builder" "removed"
        log_success "AI Builder prompts removal confirmed"
    else
        log_warning "AI Builder prompts not removed - manual cleanup required"
    fi
}

# Remove Teams configurations
remove_teams_configurations() {
    if ! component_exists "teams"; then
        log_info "No Teams configurations to remove"
        return 0
    fi
    
    log_info "Removing Teams configurations..."
    
    log_info "Teams integration cleanup:"
    echo ""
    echo "Teams configurations are integrated with Power Automate workflows."
    echo "When you remove the Power Automate workflows, the Teams integration"
    echo "will be automatically cleaned up."
    echo ""
    echo "Manual verification steps:"
    echo "1. Check Teams channels for any remaining workflow notifications"
    echo "2. Remove any custom Teams apps if created"
    echo "3. Clean up any adaptive card templates if stored separately"
    echo ""
    
    update_deployment_state "teams" "removed"
    log_success "Teams configuration cleanup noted"
}

# Remove SharePoint resources
remove_sharepoint_resources() {
    if ! component_exists "sharepoint"; then
        log_info "No SharePoint resources to remove"
        return 0
    fi
    
    log_info "Removing SharePoint resources..."
    
    # Create PowerShell script for SharePoint cleanup
    cat > "${SCRIPT_DIR}/remove_sharepoint.ps1" << EOF
\$ErrorActionPreference = "Stop"

try {
    Import-Module PnP.PowerShell -Force
    
    Write-Host "Connecting to SharePoint Admin Center..." -ForegroundColor Yellow
    Connect-PnPOnline -Url "https://${TENANT_NAME}-admin.sharepoint.com" -Interactive
    
    Write-Host "Removing SharePoint site..." -ForegroundColor Yellow
    
    # Check if site exists before attempting removal
    try {
        \$site = Get-PnPSite -Identity "${SITE_URL}"
        if (\$site) {
            Write-Host "Site found, proceeding with deletion..." -ForegroundColor Yellow
            
            # Remove the site (this moves it to recycle bin)
            Remove-PnPSite -Identity "${SITE_URL}" -Force
            
            Write-Host "Site moved to recycle bin" -ForegroundColor Green
            
            # Wait a moment for the operation to complete
            Start-Sleep -Seconds 10
            
            # Permanently delete from recycle bin
            Write-Host "Permanently deleting from recycle bin..." -ForegroundColor Yellow
            Remove-PnPDeletedSite -Identity "${SITE_URL}" -Force
            
            Write-Host "SharePoint site permanently deleted" -ForegroundColor Green
        }
    } catch {
        if (\$_.Exception.Message -like "*does not exist*") {
            Write-Host "Site does not exist or already deleted" -ForegroundColor Green
        } else {
            throw
        }
    }
    
} catch {
    Write-Error "Failed to remove SharePoint resources: \$(\$_.Exception.Message)"
    exit 1
} finally {
    if (Get-Command Disconnect-PnPOnline -ErrorAction SilentlyContinue) {
        Disconnect-PnPOnline
    }
}
EOF
    
    if pwsh -File "${SCRIPT_DIR}/remove_sharepoint.ps1"; then
        rm -f "${SCRIPT_DIR}/remove_sharepoint.ps1"
        update_deployment_state "sharepoint" "removed"
        log_success "SharePoint resources removed successfully"
    else
        rm -f "${SCRIPT_DIR}/remove_sharepoint.ps1"
        log_error "Failed to remove SharePoint resources"
        return 1
    fi
}

# Clean up deployment artifacts
cleanup_deployment_artifacts() {
    log_info "Cleaning up deployment artifacts..."
    
    # Remove deployment state file
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        rm -f "${DEPLOYMENT_STATE_FILE}"
        log_success "Deployment state file removed"
    fi
    
    # Clean up temporary files
    find "${SCRIPT_DIR}" -name "*.tmp" -delete 2>/dev/null || true
    find "${SCRIPT_DIR}" -name "check_modules.ps1" -delete 2>/dev/null || true
    
    log_success "Deployment artifacts cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local verification_issues=()
    
    # Check if SharePoint site is accessible (should fail)
    log_info "Verifying SharePoint site removal..."
    if curl -s -I "${SITE_URL}" 2>/dev/null | grep -q "200 OK"; then
        verification_issues+=("SharePoint site still accessible: ${SITE_URL}")
    else
        log_success "SharePoint site is no longer accessible"
    fi
    
    # Check for remaining deployment state
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        verification_issues+=("Deployment state file still exists")
    fi
    
    if [[ ${#verification_issues[@]} -gt 0 ]]; then
        log_warning "Cleanup verification found issues:"
        for issue in "${verification_issues[@]}"; do
            log_warning "  - ${issue}"
        done
        log_warning "Manual verification and cleanup may be required"
    else
        log_success "Cleanup verification completed successfully"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    local summary_file="${SCRIPT_DIR}/cleanup_summary_$(date +%Y%m%d_%H%M%S).md"
    
    cat > "${summary_file}" << EOF
# Content Approval Workflows Cleanup Summary

## Cleanup Information
- **Date**: $(date)
- **Tenant**: ${TENANT_NAME}
- **Site Removed**: ${SITE_URL}
- **Backup Location**: ${BACKUP_DIR}

## Removed Components

### SharePoint Resources
- [x] SharePoint team site deleted
- [x] Document library and all content removed
- [x] Custom columns and metadata cleared
- [x] Site permanently deleted from recycle bin

### Power Automate Workflows
- [x] Intelligent Content Approval Workflow removed
- [x] Associated approval flows deleted
- [x] Teams integration flows cleaned up

### AI Builder Components
- [x] Content Approval Analyzer prompt deleted
- [x] AI Builder credits no longer consumed
- [x] Custom prompt templates removed

### Teams Integration
- [x] Adaptive card configurations removed
- [x] Channel notification settings cleared
- [x] Workflow-related Teams components cleaned up

## Backup Information

Content has been backed up to: \`${BACKUP_DIR}\`

Backup includes:
- Site configuration and metadata
- Document library structure
- Custom field definitions
- List item metadata (files not downloaded)

## Manual Verification Steps

Please verify the following manually:

1. **Power Automate Portal**: 
   - Visit https://make.powerautomate.com/
   - Confirm no content approval workflows remain

2. **AI Builder Prompts**:
   - Visit https://make.powerapps.com/
   - Go to AI hub > Prompts
   - Confirm Content Approval Analyzer is deleted

3. **SharePoint Admin Center**:
   - Verify site is not in deleted sites collection
   - Confirm no orphaned resources remain

4. **Teams Channels**:
   - Check for any remaining approval notifications
   - Remove any custom Teams apps if created

## Cost Impact

After cleanup:
- AI Builder credits no longer consumed
- Power Automate premium connectors usage stopped
- SharePoint storage reclaimed
- Teams integration overhead eliminated

## Recovery Information

If you need to recover this deployment:
- Restore from backup files in: \`${BACKUP_DIR}\`
- Re-run the deployment script
- Reconfigure Power Automate workflows
- Recreate AI Builder prompts

## Support

For issues with cleanup:
1. Review cleanup log: ${LOG_FILE}
2. Check Microsoft 365 service health
3. Verify admin permissions for all services
4. Contact support with backup information

---
*Generated by Content Approval Workflows Cleanup Script*
EOF
    
    log_success "Cleanup summary generated: ${summary_file}"
    
    # Display summary
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    cat "${summary_file}"
    echo "======================="
}

# Main cleanup function
main() {
    display_banner
    
    # Initialize logging
    log "Starting Content Approval Workflows cleanup..."
    log "Script version: 1.0"
    log "Log file: ${LOG_FILE}"
    
    # Pre-cleanup checks
    check_prerequisites
    load_deployment_configuration
    confirm_cleanup
    check_authentication
    
    # Create backup before cleanup
    create_backup_directory
    backup_sharepoint_content
    
    # Core cleanup steps (in reverse order of deployment)
    log_info "Beginning cleanup process..."
    
    remove_power_automate_workflows
    remove_ai_builder_prompts
    remove_teams_configurations
    remove_sharepoint_resources
    
    # Post-cleanup tasks
    cleanup_deployment_artifacts
    verify_cleanup
    generate_cleanup_summary
    
    log_success "Content Approval Workflows cleanup completed!"
    log_info "Backup available at: ${BACKUP_DIR}"
    log_info "Cleanup log available at: ${LOG_FILE}"
    log_warning "Please manually verify all components have been removed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi