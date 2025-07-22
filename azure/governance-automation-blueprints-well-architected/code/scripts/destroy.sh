#!/bin/bash

# Destroy script for Enterprise-Grade Governance Automation with Azure Blueprints
# This script safely removes all resources created by the deployment script

set -e
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
SCRIPT_NAME="destroy.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}"
            ;;
    esac
    
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log "ERROR" "Cleanup failed with exit code ${exit_code}"
    log "ERROR" "Check ${LOG_FILE} for detailed error information"
    log "WARN" "Some resources may still exist - manual cleanup may be required"
    exit $exit_code
}

trap cleanup_on_error ERR

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Enterprise-Grade Governance Automation with Azure Blueprints

This script will remove all resources created by the deployment script including:
- Blueprint assignments and definitions
- Policy definitions and initiatives
- Resource groups and contained resources
- Monitoring configurations and dashboards

OPTIONS:
    -h, --help              Show this help message
    -r, --resource-group    Resource group name to delete
    -s, --subscription      Azure subscription ID (default: current)
    -b, --blueprint-name    Blueprint name to delete (default: enterprise-governance-blueprint)
    -y, --yes               Skip confirmation prompts
    -d, --dry-run           Show what would be deleted without executing
    -v, --verbose           Enable verbose logging
    --skip-prereqs          Skip prerequisite checks
    --force                 Force deletion even if errors occur

Examples:
    $0                                          # Interactive cleanup with prompts
    $0 -r my-governance-rg -y                  # Delete specific resource group without prompts
    $0 --dry-run                               # Show what would be deleted
    $0 --force                                 # Force deletion ignoring errors

WARNING: This script will permanently delete resources. Use with caution!

EOF
}

# Default values
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
BLUEPRINT_NAME="enterprise-governance-blueprint"
YES=false
DRY_RUN=false
VERBOSE=false
SKIP_PREREQS=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -b|--blueprint-name)
            BLUEPRINT_NAME="$2"
            shift 2
            ;;
        -y|--yes)
            YES=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
log "INFO" "Starting cleanup of Enterprise Governance Automation"
log "INFO" "Script: ${SCRIPT_NAME}"
log "INFO" "Log file: ${LOG_FILE}"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Get subscription ID if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    fi
    
    # Set subscription context
    az account set --subscription "${SUBSCRIPTION_ID}"
    
    # Export variables for use in functions
    export SUBSCRIPTION_ID BLUEPRINT_NAME RESOURCE_GROUP
    
    log "INFO" "Environment setup completed"
    log "INFO" "Subscription ID: ${SUBSCRIPTION_ID}"
    log "INFO" "Blueprint Name: ${BLUEPRINT_NAME}"
    if [[ -n "$RESOURCE_GROUP" ]]; then
        log "INFO" "Resource Group: ${RESOURCE_GROUP}"
    fi
}

# Confirmation prompt
confirm_destruction() {
    if $YES || $DRY_RUN; then
        return 0
    fi
    
    echo
    log "WARN" "This will permanently delete the following resources:"
    log "WARN" "  - Blueprint assignments and definitions"
    log "WARN" "  - Policy definitions and initiatives"
    log "WARN" "  - Resource groups and all contained resources"
    log "WARN" "  - Monitoring configurations and dashboards"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
}

# Find and list resources to be deleted
discover_resources() {
    log "INFO" "Discovering resources to be deleted..."
    
    # Find blueprint assignments
    local blueprint_assignments=$(az blueprint assignment list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'enterprise-governance') || contains(name, 'governance')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$blueprint_assignments" ]]; then
        log "INFO" "Found blueprint assignments: ${blueprint_assignments}"
    fi
    
    # Find policy initiatives
    local policy_initiatives=$(az policy set-definition list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'enterprise-security-initiative')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$policy_initiatives" ]]; then
        log "INFO" "Found policy initiatives: ${policy_initiatives}"
    fi
    
    # Find custom policy definitions
    local custom_policies=$(az policy definition list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'require-resource-tags')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$custom_policies" ]]; then
        log "INFO" "Found custom policies: ${custom_policies}"
    fi
    
    # Find resource groups if not specified
    if [[ -z "$RESOURCE_GROUP" ]]; then
        local governance_rgs=$(az group list \
            --subscription "${SUBSCRIPTION_ID}" \
            --query "[?contains(name, 'governance')].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$governance_rgs" ]]; then
            log "INFO" "Found governance resource groups: ${governance_rgs}"
            # Use the first found resource group
            RESOURCE_GROUP=$(echo "$governance_rgs" | head -n1)
            log "INFO" "Using resource group: ${RESOURCE_GROUP}"
        fi
    fi
    
    log "INFO" "Resource discovery completed"
}

# Remove blueprint assignments
remove_blueprint_assignments() {
    log "INFO" "Removing blueprint assignments..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would remove blueprint assignments"
        return 0
    fi
    
    # Remove specific assignment
    local assignment_name="enterprise-governance-assignment"
    if az blueprint assignment show --name "${assignment_name}" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Removing blueprint assignment: ${assignment_name}"
        az blueprint assignment delete \
            --name "${assignment_name}" \
            --subscription "${SUBSCRIPTION_ID}" \
            --yes || ($FORCE && log "WARN" "Failed to delete blueprint assignment, continuing...")
        log "INFO" "Blueprint assignment removed successfully"
    else
        log "WARN" "Blueprint assignment ${assignment_name} not found"
    fi
    
    # Remove any other governance-related assignments
    local other_assignments=$(az blueprint assignment list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'governance')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$other_assignments" ]]; then
        for assignment in $other_assignments; do
            log "INFO" "Removing additional blueprint assignment: ${assignment}"
            az blueprint assignment delete \
                --name "${assignment}" \
                --subscription "${SUBSCRIPTION_ID}" \
                --yes || ($FORCE && log "WARN" "Failed to delete ${assignment}, continuing...")
        done
    fi
}

# Remove blueprint definitions
remove_blueprint_definitions() {
    log "INFO" "Removing blueprint definitions..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would remove blueprint: ${BLUEPRINT_NAME}"
        return 0
    fi
    
    # Remove blueprint definition
    if az blueprint show --name "${BLUEPRINT_NAME}" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Removing blueprint definition: ${BLUEPRINT_NAME}"
        az blueprint delete \
            --name "${BLUEPRINT_NAME}" \
            --subscription "${SUBSCRIPTION_ID}" \
            --yes || ($FORCE && log "WARN" "Failed to delete blueprint, continuing...")
        log "INFO" "Blueprint definition removed successfully"
    else
        log "WARN" "Blueprint ${BLUEPRINT_NAME} not found"
    fi
}

# Remove policy definitions and initiatives
remove_policies() {
    log "INFO" "Removing policy definitions and initiatives..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would remove policy initiatives and definitions"
        return 0
    fi
    
    # Remove policy initiative
    local initiative_name="enterprise-security-initiative"
    if az policy set-definition show --name "${initiative_name}" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Removing policy initiative: ${initiative_name}"
        az policy set-definition delete \
            --name "${initiative_name}" \
            --subscription "${SUBSCRIPTION_ID}" || ($FORCE && log "WARN" "Failed to delete policy initiative, continuing...")
        log "INFO" "Policy initiative removed successfully"
    else
        log "WARN" "Policy initiative ${initiative_name} not found"
    fi
    
    # Remove custom policy definition
    local policy_name="require-resource-tags"
    if az policy definition show --name "${policy_name}" --subscription "${SUBSCRIPTION_ID}" &> /dev/null; then
        log "INFO" "Removing custom policy definition: ${policy_name}"
        az policy definition delete \
            --name "${policy_name}" \
            --subscription "${SUBSCRIPTION_ID}" || ($FORCE && log "WARN" "Failed to delete policy definition, continuing...")
        log "INFO" "Custom policy definition removed successfully"
    else
        log "WARN" "Custom policy definition ${policy_name} not found"
    fi
}

# Remove resource groups and contained resources
remove_resource_groups() {
    log "INFO" "Removing resource groups and contained resources..."
    
    if $DRY_RUN; then
        if [[ -n "$RESOURCE_GROUP" ]]; then
            log "INFO" "[DRY RUN] Would remove resource group: ${RESOURCE_GROUP}"
        else
            log "INFO" "[DRY RUN] Would discover and remove governance resource groups"
        fi
        return 0
    fi
    
    # Remove specified resource group
    if [[ -n "$RESOURCE_GROUP" ]]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log "INFO" "Removing resource group: ${RESOURCE_GROUP}"
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait || ($FORCE && log "WARN" "Failed to delete resource group, continuing...")
            log "INFO" "Resource group deletion initiated: ${RESOURCE_GROUP}"
        else
            log "WARN" "Resource group ${RESOURCE_GROUP} not found"
        fi
    else
        # Find and remove governance-related resource groups
        local governance_rgs=$(az group list \
            --subscription "${SUBSCRIPTION_ID}" \
            --query "[?contains(name, 'governance')].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$governance_rgs" ]]; then
            for rg in $governance_rgs; do
                log "INFO" "Removing governance resource group: ${rg}"
                az group delete \
                    --name "${rg}" \
                    --yes \
                    --no-wait || ($FORCE && log "WARN" "Failed to delete ${rg}, continuing...")
            done
            log "INFO" "Governance resource group deletions initiated"
        else
            log "WARN" "No governance resource groups found"
        fi
    fi
}

# Remove monitoring configurations
remove_monitoring() {
    log "INFO" "Removing monitoring configurations..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would remove monitoring alerts and action groups"
        return 0
    fi
    
    # Remove activity log alerts
    local alert_name="advisor-security-alert"
    if [[ -n "$RESOURCE_GROUP" ]] && az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        if az monitor activity-log alert show --name "${alert_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log "INFO" "Removing activity log alert: ${alert_name}"
            az monitor activity-log alert delete \
                --name "${alert_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || ($FORCE && log "WARN" "Failed to delete alert, continuing...")
        fi
        
        # Remove action groups
        local action_group_name="governance-alerts"
        if az monitor action-group show --name "${action_group_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log "INFO" "Removing action group: ${action_group_name}"
            az monitor action-group delete \
                --name "${action_group_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || ($FORCE && log "WARN" "Failed to delete action group, continuing...")
        fi
    else
        log "WARN" "Resource group not available for monitoring cleanup"
    fi
}

# Remove dashboards
remove_dashboards() {
    log "INFO" "Removing governance dashboards..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would remove governance dashboards"
        return 0
    fi
    
    # Remove governance dashboard
    local dashboard_name="enterprise-governance-dashboard"
    if [[ -n "$RESOURCE_GROUP" ]] && az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        if az portal dashboard show --name "${dashboard_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log "INFO" "Removing governance dashboard: ${dashboard_name}"
            az portal dashboard delete \
                --name "${dashboard_name}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || ($FORCE && log "WARN" "Failed to delete dashboard, continuing...")
        fi
    else
        log "WARN" "Resource group not available for dashboard cleanup"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "INFO" "Cleaning up temporary files..."
    
    # Remove any temporary files created during deployment
    local temp_files=(
        "${SCRIPT_DIR}/required-tags-policy.json"
        "${SCRIPT_DIR}/security-initiative.json"
        "${SCRIPT_DIR}/storage-template.json"
        "${SCRIPT_DIR}/governance-dashboard.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "INFO" "Removing temporary file: $file"
            rm -f "$file" || log "WARN" "Failed to remove $file"
        fi
    done
}

# Validate cleanup
validate_cleanup() {
    log "INFO" "Validating cleanup..."
    
    if $DRY_RUN; then
        log "INFO" "[DRY RUN] Would validate resource removal"
        return 0
    fi
    
    # Check blueprint assignments
    local remaining_assignments=$(az blueprint assignment list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'governance')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_assignments" ]]; then
        log "WARN" "Some blueprint assignments may still exist: ${remaining_assignments}"
    else
        log "INFO" "Blueprint assignments cleanup: VERIFIED"
    fi
    
    # Check policy initiatives
    local remaining_initiatives=$(az policy set-definition list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'enterprise-security-initiative')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_initiatives" ]]; then
        log "WARN" "Some policy initiatives may still exist: ${remaining_initiatives}"
    else
        log "INFO" "Policy initiatives cleanup: VERIFIED"
    fi
    
    # Check custom policies
    local remaining_policies=$(az policy definition list \
        --subscription "${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'require-resource-tags')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_policies" ]]; then
        log "WARN" "Some custom policies may still exist: ${remaining_policies}"
    else
        log "INFO" "Custom policies cleanup: VERIFIED"
    fi
    
    # Check resource groups
    if [[ -n "$RESOURCE_GROUP" ]]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log "WARN" "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
        else
            log "INFO" "Resource group cleanup: VERIFIED"
        fi
    fi
    
    log "INFO" "Cleanup validation completed"
}

# Main cleanup function
main() {
    log "INFO" "Starting Enterprise Governance Automation cleanup"
    
    # Check prerequisites unless skipped
    if ! $SKIP_PREREQS; then
        check_prerequisites
    fi
    
    # Setup environment
    setup_environment
    
    # Discover resources
    discover_resources
    
    # Confirm destruction
    confirm_destruction
    
    # Show cleanup plan if dry run
    if $DRY_RUN; then
        log "INFO" "DRY RUN MODE - Showing cleanup plan:"
        log "INFO" "Subscription ID: ${SUBSCRIPTION_ID}"
        log "INFO" "Blueprint Name: ${BLUEPRINT_NAME}"
        if [[ -n "$RESOURCE_GROUP" ]]; then
            log "INFO" "Resource Group: ${RESOURCE_GROUP}"
        fi
        log "INFO" "Components to remove:"
        log "INFO" "  - Blueprint assignments"
        log "INFO" "  - Blueprint definitions"
        log "INFO" "  - Policy initiatives and definitions"
        log "INFO" "  - Resource groups and contained resources"
        log "INFO" "  - Monitoring configurations"
        log "INFO" "  - Governance dashboards"
        log "INFO" "DRY RUN MODE - No resources will be deleted"
        exit 0
    fi
    
    # Execute cleanup steps in reverse order of creation
    remove_monitoring
    remove_dashboards
    remove_blueprint_assignments
    remove_blueprint_definitions
    remove_policies
    remove_resource_groups
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Validate cleanup
    validate_cleanup
    
    # Summary
    log "INFO" "Cleanup completed successfully!"
    log "INFO" "Resources removed:"
    log "INFO" "  - Blueprint assignments and definitions"
    log "INFO" "  - Policy initiatives and definitions"
    log "INFO" "  - Resource groups and contained resources"
    log "INFO" "  - Monitoring configurations"
    log "INFO" "  - Governance dashboards"
    
    log "WARN" "Note: Resource group deletions may take several minutes to complete"
    log "WARN" "Check the Azure Portal to verify all resources have been removed"
    
    log "INFO" "Cleanup log saved to: ${LOG_FILE}"
}

# Execute main function
main "$@"