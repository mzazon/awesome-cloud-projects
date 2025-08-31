#!/bin/bash

#
# Azure Maps Store Locator Cleanup Script
#
# This script safely removes all resources created by the Azure Maps Store Locator deployment:
# - Azure Maps account
# - Resource group and all contained resources
# - Local application files (with confirmation)
#
# Author: Recipe Infrastructure Generator
# Version: 1.0
# Last Updated: 2025-01-12
#

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APP_DIR="${SCRIPT_DIR}/../app"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

#
# Logging and output functions
#
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

#
# Print script header
#
print_header() {
    echo ""
    echo "================================================================"
    echo "       Azure Maps Store Locator Cleanup Script"
    echo "================================================================"
    echo "This script will remove:"
    echo "  • Azure Maps account and subscription keys"
    echo "  • Resource group and all contained resources"
    echo "  • Local application files (optional)"
    echo "  • Deployment logs and temporary files"
    echo ""
    echo "⚠️  WARNING: This action cannot be undone!"
    echo "================================================================"
    echo ""
}

#
# Display usage information
#
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help                    Show this help message"
    echo "  -r, --resource-group RG       Specific resource group to delete"
    echo "  -f, --force                   Skip confirmation prompts"
    echo "  -k, --keep-files              Keep local application files"
    echo "  -l, --list-resources          List resources that would be deleted"
    echo "  -d, --dry-run                 Show what would be deleted without executing"
    echo "  -v, --verbose                 Enable verbose logging"
    echo ""
    echo "Environment Variables:"
    echo "  SKIP_CONFIRMATION            Skip all confirmation prompts (set to 'true')"
    echo "  KEEP_LOCAL_FILES             Keep local application files (set to 'true')"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive cleanup with confirmations"
    echo "  $0 --force                   # Cleanup without confirmations"
    echo "  $0 --keep-files              # Delete Azure resources but keep local files"
    echo "  $0 --resource-group rg-name  # Delete specific resource group"
    echo "  $0 --list-resources          # List what would be deleted"
    echo "  $0 --dry-run                 # Preview cleanup without executing"
    echo ""
}

#
# Prerequisite checks
#
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

#
# Discover deployed resources
#
discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Get current subscription info
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    
    log_info "Current subscription: ${subscription_name} (${subscription_id})"
    
    # Find resource groups with store locator tags
    local resource_groups=()
    while IFS= read -r rg; do
        if [[ -n "${rg}" ]]; then
            resource_groups+=("${rg}")
        fi
    done < <(az group list --query "[?tags.application=='store-locator' || contains(name, 'storemaps')].name" --output tsv)
    
    # If specific resource group provided, use that
    if [[ -n "${TARGET_RESOURCE_GROUP:-}" ]]; then
        if az group show --name "${TARGET_RESOURCE_GROUP}" &> /dev/null; then
            resource_groups=("${TARGET_RESOURCE_GROUP}")
            log_info "Using specified resource group: ${TARGET_RESOURCE_GROUP}"
        else
            log_error "Specified resource group '${TARGET_RESOURCE_GROUP}' not found"
            exit 1
        fi
    fi
    
    # If no resource groups found, try to find from deployment summary
    if [[ ${#resource_groups[@]} -eq 0 && -f "${APP_DIR}/DEPLOYMENT_SUMMARY.md" ]]; then
        local summary_rg=$(grep "Resource Group" "${APP_DIR}/DEPLOYMENT_SUMMARY.md" | head -1 | cut -d':' -f2 | xargs)
        if [[ -n "${summary_rg}" ]] && az group show --name "${summary_rg}" &> /dev/null; then
            resource_groups=("${summary_rg}")
            log_info "Found resource group from deployment summary: ${summary_rg}"
        fi
    fi
    
    if [[ ${#resource_groups[@]} -eq 0 ]]; then
        log_warning "No Azure Maps Store Locator resource groups found"
        log_info "This could mean:"
        log_info "  • Resources were already deleted"
        log_info "  • Resources were created with different names/tags"
        log_info "  • You're in a different subscription"
        return 1
    fi
    
    echo "DISCOVERED_RESOURCE_GROUPS=${resource_groups[*]}"
    return 0
}

#
# List resources that would be deleted
#
list_resources() {
    local resource_groups=("$@")
    
    echo ""
    echo "📋 Resources that would be deleted:"
    echo "=================================="
    
    local total_resources=0
    local total_cost_estimate=0
    
    for rg in "${resource_groups[@]}"; do
        echo ""
        echo "Resource Group: ${rg}"
        echo "----------------------------------------"
        
        # Get resource group location and tags
        local rg_info=$(az group show --name "${rg}" --query "{location:location, tags:tags}" --output json 2>/dev/null)
        if [[ -n "${rg_info}" ]]; then
            local location=$(echo "${rg_info}" | jq -r '.location // "unknown"')
            local created_date=$(echo "${rg_info}" | jq -r '.tags."created-date" // "unknown"')
            echo "  Location: ${location}"
            echo "  Created: ${created_date}"
            echo ""
        fi
        
        # List resources in the group
        local resources=$(az resource list --resource-group "${rg}" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null)
        
        if [[ -n "${resources}" ]]; then
            echo "${resources}"
            local resource_count=$(az resource list --resource-group "${rg}" --query "length(@)" --output tsv 2>/dev/null || echo "0")
            total_resources=$((total_resources + resource_count))
            echo ""
            echo "  Resources in group: ${resource_count}"
            
            # Check for Azure Maps accounts specifically
            local maps_accounts=$(az maps account list --resource-group "${rg}" --query "[].name" --output tsv 2>/dev/null)
            if [[ -n "${maps_accounts}" ]]; then
                echo "  Azure Maps accounts:"
                for account in ${maps_accounts}; do
                    local sku=$(az maps account show --resource-group "${rg}" --account-name "${account}" --query "sku.name" --output tsv 2>/dev/null || echo "unknown")
                    echo "    • ${account} (${sku})"
                done
            fi
        else
            echo "  No resources found in this group"
        fi
    done
    
    echo ""
    echo "📊 Summary:"
    echo "  • Resource Groups: ${#resource_groups[@]}"
    echo "  • Total Resources: ${total_resources}"
    echo "  • Estimated Monthly Savings: \$0-5 (mostly free tier usage)"
    echo ""
    
    # Check for local files
    if [[ -d "${APP_DIR}" ]]; then
        echo "📁 Local Application Files:"
        echo "  • Directory: ${APP_DIR}"
        local file_count=$(find "${APP_DIR}" -type f | wc -l)
        local dir_size=$(du -sh "${APP_DIR}" 2>/dev/null | cut -f1 || echo "unknown")
        echo "  • Files: ${file_count}"
        echo "  • Size: ${dir_size}"
        echo ""
    fi
}

#
# Confirm cleanup with user
#
confirm_cleanup() {
    local resource_groups=("$@")
    
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" || "${FORCE_CLEANUP:-false}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  CONFIRMATION REQUIRED"
    echo "========================"
    echo ""
    echo "You are about to permanently delete:"
    for rg in "${resource_groups[@]}"; do
        echo "  • Resource Group: ${rg} (and all contained resources)"
    done
    
    if [[ -d "${APP_DIR}" && "${KEEP_LOCAL_FILES:-false}" != "true" ]]; then
        echo "  • Local application files in: ${APP_DIR}"
    fi
    
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    # Multiple confirmation for safety
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo ""
    
    if [[ "${REPLY}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo "⚠️  FINAL CONFIRMATION"
    echo "====================="
    echo ""
    read -p "This will permanently delete ALL listed resources. Type 'DELETE' to proceed: " -r
    echo ""
    
    if [[ "${REPLY}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed cleanup operation"
}

#
# Delete Azure resource groups and resources
#
delete_azure_resources() {
    local resource_groups=("$@")
    
    log_info "Starting Azure resource cleanup..."
    
    local deletion_jobs=()
    
    for rg in "${resource_groups[@]}"; do
        log_info "Initiating deletion of resource group: ${rg}"
        
        # Check if resource group exists
        if ! az group show --name "${rg}" &> /dev/null; then
            log_warning "Resource group ${rg} not found, skipping"
            continue
        fi
        
        # Start async deletion
        log_info "  Starting deletion process (this may take several minutes)..."
        az group delete \
            --name "${rg}" \
            --yes \
            --no-wait \
            --output none
        
        deletion_jobs+=("${rg}")
        log_info "  Deletion initiated for: ${rg}"
    done
    
    if [[ ${#deletion_jobs[@]} -eq 0 ]]; then
        log_warning "No resource groups were found to delete"
        return 0
    fi
    
    # Wait for deletions to complete
    log_info "Waiting for resource group deletions to complete..."
    log_info "This may take 5-15 minutes depending on the resources..."
    
    local max_wait=1800  # 30 minutes maximum wait
    local wait_time=0
    local check_interval=30
    
    while [[ ${#deletion_jobs[@]} -gt 0 && ${wait_time} -lt ${max_wait} ]]; do
        local remaining_jobs=()
        
        for rg in "${deletion_jobs[@]}"; do
            if az group show --name "${rg}" &> /dev/null; then
                remaining_jobs+=("${rg}")
            else
                log_success "✅ Completed deletion of: ${rg}"
            fi
        done
        
        deletion_jobs=("${remaining_jobs[@]}")
        
        if [[ ${#deletion_jobs[@]} -gt 0 ]]; then
            log_info "  Still deleting: ${deletion_jobs[*]} (${wait_time}s elapsed)"
            sleep ${check_interval}
            wait_time=$((wait_time + check_interval))
        fi
    done
    
    # Final status check
    if [[ ${#deletion_jobs[@]} -eq 0 ]]; then
        log_success "🎉 All Azure resources deleted successfully!"
    else
        log_warning "⚠️  Some resource groups may still be deleting:"
        for rg in "${deletion_jobs[@]}"; do
            log_warning "    • ${rg} (check Azure portal for status)"
        done
        log_info "Deletion may continue in the background. Check the Azure portal to verify completion."
    fi
}

#
# Clean up local application files
#
cleanup_local_files() {
    if [[ "${KEEP_LOCAL_FILES:-false}" == "true" ]]; then
        log_info "Keeping local application files as requested"
        return 0
    fi
    
    if [[ ! -d "${APP_DIR}" ]]; then
        log_info "No local application files to clean up"
        return 0
    fi
    
    log_info "Cleaning up local application files..."
    
    # Show what will be deleted
    log_info "Local files to be removed:"
    find "${APP_DIR}" -type f | while read -r file; do
        log_info "  • ${file#${SCRIPT_DIR}/}"
    done
    
    # Confirm local file deletion if not already confirmed
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" && "${FORCE_CLEANUP:-false}" != "true" ]]; then
        echo ""
        read -p "Delete local application files? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping local application files"
            return 0
        fi
    fi
    
    # Create backup before deletion (just in case)
    local backup_dir="${SCRIPT_DIR}/backup-$(date '+%Y%m%d-%H%M%S')"
    if cp -r "${APP_DIR}" "${backup_dir}" 2>/dev/null; then
        log_info "Created backup at: ${backup_dir}"
    fi
    
    # Remove application directory
    if rm -rf "${APP_DIR}"; then
        log_success "✅ Local application files removed"
    else
        log_error "❌ Failed to remove local application files"
        return 1
    fi
    
    # Clean up logs older than 7 days
    find "${SCRIPT_DIR}" -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

#
# Generate cleanup report
#
generate_cleanup_report() {
    local start_time="$1"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "Generating cleanup report..."
    
    local report_file="${SCRIPT_DIR}/cleanup-report-$(date '+%Y%m%d-%H%M%S').txt"
    
    cat > "${report_file}" << EOF
# Azure Maps Store Locator Cleanup Report

## Cleanup Information
- **Start Time**: ${start_time}
- **End Time**: ${end_time}
- **Script Version**: 1.0
- **User**: $(whoami)
- **Subscription**: $(az account show --query name --output tsv 2>/dev/null || echo "unknown")

## Resources Removed
$(if [[ -n "${CLEANED_RESOURCE_GROUPS:-}" ]]; then
    echo "### Azure Resource Groups"
    for rg in ${CLEANED_RESOURCE_GROUPS}; do
        echo "- ${rg}"
    done
    echo ""
fi)

$(if [[ "${CLEANED_LOCAL_FILES:-false}" == "true" ]]; then
    echo "### Local Files"
    echo "- Application directory: ${APP_DIR}"
    echo "- Deployment logs and temporary files"
    echo ""
fi)

## Verification
- All Azure resources have been scheduled for deletion
- Billing should stop within 24 hours
- Any remaining charges should be minimal (typically \$0 for demo usage)

## Recovery
- Resources cannot be recovered once deleted
- Backup of local files may be available at: ${SCRIPT_DIR}/backup-*
- To redeploy, run the deployment script again

## Next Steps
- Verify in Azure portal that all resources are deleted
- Check Azure billing to confirm no ongoing charges
- Keep this report for your records

---
Generated by Azure Maps Store Locator Cleanup Script
EOF
    
    log_success "Cleanup report saved: ${report_file}"
    
    # Display summary
    echo ""
    echo "================================================================"
    echo "           🧹 CLEANUP COMPLETED SUCCESSFULLY! 🧹"
    echo "================================================================"
    echo ""
    echo "Summary of actions taken:"
    if [[ -n "${CLEANED_RESOURCE_GROUPS:-}" ]]; then
        echo "  ✅ Deleted Azure resource groups: ${CLEANED_RESOURCE_GROUPS}"
    fi
    if [[ "${CLEANED_LOCAL_FILES:-false}" == "true" ]]; then
        echo "  ✅ Removed local application files"
    fi
    echo "  ✅ Generated cleanup report: $(basename "${report_file}")"
    echo ""
    echo "Important notes:"
    echo "  • Resource deletion may take up to 15 minutes to complete"
    echo "  • Verify completion in the Azure portal"
    echo "  • Billing for deleted resources should stop within 24 hours"
    echo "  • This cleanup cannot be undone"
    echo ""
    echo "To redeploy the store locator:"
    echo "  ${SCRIPT_DIR}/deploy.sh"
    echo ""
    echo "================================================================"
    echo ""
}

#
# Main cleanup function
#
main() {
    local list_only=false
    local dry_run=false
    local verbose=false
    local force=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--resource-group)
                TARGET_RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                force=true
                FORCE_CLEANUP=true
                shift
                ;;
            -k|--keep-files)
                KEEP_LOCAL_FILES=true
                shift
                ;;
            -l|--list-resources)
                list_only=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Start cleanup process
    print_header
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        echo ""
    fi
    
    # Execute cleanup steps
    check_prerequisites
    
    # Discover resources to clean up
    local discovery_result
    discovery_result=$(discover_resources)
    
    if [[ $? -ne 0 ]]; then
        log_warning "No resources found to clean up"
        
        # Still offer to clean up local files
        if [[ -d "${APP_DIR}" ]]; then
            echo ""
            read -p "Clean up local application files only? (y/N): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                cleanup_local_files
                CLEANED_LOCAL_FILES=true
                generate_cleanup_report "${start_time}"
            fi
        fi
        
        exit 0
    fi
    
    # Parse discovered resource groups
    eval "${discovery_result}"
    local resource_groups=("${DISCOVERED_RESOURCE_GROUPS[@]}")
    
    # List resources
    list_resources "${resource_groups[@]}"
    
    if [[ "${list_only}" == "true" ]]; then
        log_info "Resource listing completed"
        exit 0
    fi
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "Dry run completed. No resources were deleted."
        exit 0
    fi
    
    # Confirm cleanup operation
    confirm_cleanup "${resource_groups[@]}"
    
    # Perform cleanup operations
    delete_azure_resources "${resource_groups[@]}"
    CLEANED_RESOURCE_GROUPS="${resource_groups[*]}"
    
    cleanup_local_files
    if [[ ! -d "${APP_DIR}" ]]; then
        CLEANED_LOCAL_FILES=true
    fi
    
    # Generate final report
    generate_cleanup_report "${start_time}"
    
    log_success "🧹 Azure Maps Store Locator cleanup completed successfully!"
}

# Trap to handle script interruption
trap 'log_error "Cleanup script interrupted. Some resources may still be deleting."; exit 1' INT TERM

# Execute main function with all arguments
main "$@"