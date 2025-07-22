#!/bin/bash

# Azure Infrastructure Cost Optimization Cleanup Script
# This script safely removes all resources created by the deployment script

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Azure infrastructure for cost optimization deployment.

OPTIONS:
    -g, --resource-group     Resource group name (required if no config file)
    -d, --dry-run           Show what would be deleted without executing
    -f, --force             Skip confirmation prompts
    -h, --help              Show this help message
    --keep-logs             Keep Log Analytics workspace and historical data
    --partial-cleanup       Clean up specific resource types only

CLEANUP MODES:
    --automation-only       Remove only Automation Account and runbooks
    --monitoring-only       Remove only monitoring resources
    --test-resources-only   Remove only test VMs and temporary resources

EXAMPLES:
    $0                                    # Use config file from deployment
    $0 --resource-group rg-costopt-abc   # Specify resource group manually
    $0 --dry-run                         # Preview what would be deleted
    $0 --force --keep-logs               # Force cleanup but preserve logs

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            --partial-cleanup)
                PARTIAL_CLEANUP=true
                shift
                ;;
            --automation-only)
                AUTOMATION_ONLY=true
                shift
                ;;
            --monitoring-only)
                MONITORING_ONLY=true
                shift
                ;;
            --test-resources-only)
                TEST_RESOURCES_ONLY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    FORCE_CLEANUP=${FORCE_CLEANUP:-false}
    KEEP_LOGS=${KEEP_LOGS:-false}
    PARTIAL_CLEANUP=${PARTIAL_CLEANUP:-false}
    AUTOMATION_ONLY=${AUTOMATION_ONLY:-false}
    MONITORING_ONLY=${MONITORING_ONLY:-false}
    TEST_RESOURCES_ONLY=${TEST_RESOURCES_ONLY:-false}
}

# Load configuration from deployment
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from: $CONFIG_FILE"
        source "$CONFIG_FILE"
        
        # Display loaded configuration
        log "Loaded deployment configuration:"
        echo "  Resource Group: ${RESOURCE_GROUP:-not set}"
        echo "  Location: ${LOCATION:-not set}"
        echo "  Deployment: ${DEPLOYMENT_NAME:-not set}"
        echo "  Deployment Date: ${DEPLOYMENT_DATE:-not set}"
    else
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error "No configuration file found and no resource group specified."
            error "Either run from the scripts directory with a config file, or use --resource-group"
            exit 1
        fi
        warning "No configuration file found, using provided resource group: $RESOURCE_GROUP"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Get current subscription info
    local current_subscription_id
    current_subscription_id=$(az account show --query id --output tsv)
    local current_subscription_name
    current_subscription_name=$(az account show --query name --output tsv)
    
    log "Current subscription: $current_subscription_name ($current_subscription_id)"

    # Verify subscription matches if we have config
    if [[ -n "$SUBSCRIPTION_ID" && "$current_subscription_id" != "$SUBSCRIPTION_ID" ]]; then
        warning "Current subscription ($current_subscription_id) differs from deployment subscription ($SUBSCRIPTION_ID)"
        if [[ "$FORCE_CLEANUP" == "false" ]]; then
            read -p "Continue with cleanup? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi

    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' not found"
        exit 1
    fi

    success "Prerequisites check completed"
}

# Display resources to be deleted
show_cleanup_plan() {
    log "Analyzing resources in resource group: $RESOURCE_GROUP"
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "No resources found")
    
    if [[ "$resources" == "No resources found" ]]; then
        warning "No resources found in resource group $RESOURCE_GROUP"
        return 1
    fi

    echo
    echo "📋 Resources to be deleted:"
    echo "$resources"
    echo

    # Count resources by type
    local vm_count
    vm_count=$(az vm list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    local automation_count
    automation_count=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Automation/automationAccounts" --query "length([])" --output tsv 2>/dev/null || echo "0")
    local workspace_count
    workspace_count=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.OperationalInsights/workspaces" --query "length([])" --output tsv 2>/dev/null || echo "0")
    local logic_app_count
    logic_app_count=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Logic/workflows" --query "length([])" --output tsv 2>/dev/null || echo "0")

    echo "📊 Resource summary:"
    echo "  Virtual Machines: $vm_count"
    echo "  Automation Accounts: $automation_count"
    echo "  Log Analytics Workspaces: $workspace_count"
    echo "  Logic Apps: $logic_app_count"
    echo

    # Estimate deletion time
    local total_resources
    total_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    local estimated_time=$((total_resources * 2))
    
    if [[ $estimated_time -gt 60 ]]; then
        warning "Estimated cleanup time: $((estimated_time / 60)) minutes"
    else
        log "Estimated cleanup time: $estimated_time minutes"
    fi

    return 0
}

# Confirm cleanup operation
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        warning "Force cleanup enabled - skipping confirmation"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN mode - no confirmation needed"
        return 0
    fi

    echo
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will permanently delete all resources in resource group: $RESOURCE_GROUP"
    echo "This action cannot be undone!"
    echo

    read -p "Are you absolutely sure you want to continue? Type 'DELETE' to confirm: " -r
    echo

    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi

    success "Cleanup confirmed by user"
}

# Remove test resources
cleanup_test_resources() {
    if [[ "$MONITORING_ONLY" == "true" || "$AUTOMATION_ONLY" == "true" ]]; then
        return 0
    fi

    log "Removing test resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would remove test VMs and associated resources"
        return 0
    fi

    # Remove test VMs
    local test_vms
    test_vms=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[?tags.purpose=='testing'].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$test_vms" ]]; then
        log "Removing test VMs..."
        while IFS= read -r vm_name; do
            if [[ -n "$vm_name" ]]; then
                log "Deleting test VM: $vm_name"
                az vm delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$vm_name" \
                    --yes \
                    --no-wait
            fi
        done <<< "$test_vms"
        
        # Wait for VM deletions to complete
        log "Waiting for test VM deletions to complete..."
        sleep 30
    fi

    # Clean up orphaned NICs, disks, and NSGs from test VMs
    log "Cleaning up orphaned test resources..."
    
    # Remove NICs with test tags
    az network nic list --resource-group "$RESOURCE_GROUP" --query "[?tags.purpose=='testing'].name" --output tsv 2>/dev/null | while read -r nic_name; do
        if [[ -n "$nic_name" ]]; then
            az network nic delete --resource-group "$RESOURCE_GROUP" --name "$nic_name" --no-wait
        fi
    done

    # Remove disks with test tags
    az disk list --resource-group "$RESOURCE_GROUP" --query "[?tags.purpose=='testing'].name" --output tsv 2>/dev/null | while read -r disk_name; do
        if [[ -n "$disk_name" ]]; then
            az disk delete --resource-group "$RESOURCE_GROUP" --name "$disk_name" --yes --no-wait
        fi
    done

    success "Test resources cleanup initiated"
}

# Remove automation resources
cleanup_automation_resources() {
    if [[ "$MONITORING_ONLY" == "true" || "$TEST_RESOURCES_ONLY" == "true" ]]; then
        return 0
    fi

    log "Removing automation resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would remove Automation Accounts and runbooks"
        return 0
    fi

    # Remove Logic Apps
    local logic_apps
    logic_apps=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$logic_apps" ]]; then
        while IFS= read -r logic_app_name; do
            if [[ -n "$logic_app_name" ]]; then
                log "Deleting Logic App: $logic_app_name"
                az logic workflow delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$logic_app_name" \
                    --yes
            fi
        done <<< "$logic_apps"
    fi

    # Remove Automation Accounts
    local automation_accounts
    automation_accounts=$(az automation account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$automation_accounts" ]]; then
        while IFS= read -r account_name; do
            if [[ -n "$account_name" ]]; then
                log "Deleting Automation Account: $account_name"
                az automation account delete \
                    --name "$account_name" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes
            fi
        done <<< "$automation_accounts"
    fi

    success "Automation resources removed"
}

# Remove monitoring resources
cleanup_monitoring_resources() {
    if [[ "$AUTOMATION_ONLY" == "true" || "$TEST_RESOURCES_ONLY" == "true" ]]; then
        return 0
    fi

    if [[ "$KEEP_LOGS" == "true" ]]; then
        warning "Keeping Log Analytics workspace as requested"
        return 0
    fi

    log "Removing monitoring resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would remove Log Analytics workspaces and monitoring configurations"
        return 0
    fi

    # Remove diagnostic settings
    log "Removing diagnostic settings..."
    local diagnostic_settings
    diagnostic_settings=$(az monitor diagnostic-settings list --resource "$SUBSCRIPTION_ID" --query "[?name=='CostOptimizationLogs'].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$diagnostic_settings" ]]; then
        while IFS= read -r setting_name; do
            if [[ -n "$setting_name" ]]; then
                log "Removing diagnostic setting: $setting_name"
                az monitor diagnostic-settings delete \
                    --resource "$SUBSCRIPTION_ID" \
                    --name "$setting_name" || warning "Failed to remove diagnostic setting $setting_name"
            fi
        done <<< "$diagnostic_settings"
    fi

    # Remove alert rules
    local alert_rules
    alert_rules=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$alert_rules" ]]; then
        while IFS= read -r rule_name; do
            if [[ -n "$rule_name" ]]; then
                log "Removing alert rule: $rule_name"
                az monitor metrics alert delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$rule_name"
            fi
        done <<< "$alert_rules"
    fi

    # Remove Log Analytics workspaces
    local workspaces
    workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$workspaces" ]]; then
        while IFS= read -r workspace_name; do
            if [[ -n "$workspace_name" ]]; then
                log "Deleting Log Analytics workspace: $workspace_name"
                az monitor log-analytics workspace delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --workspace-name "$workspace_name" \
                    --yes
            fi
        done <<< "$workspaces"
    fi

    success "Monitoring resources removed"
}

# Remove resource group
cleanup_resource_group() {
    if [[ "$PARTIAL_CLEANUP" == "true" || "$AUTOMATION_ONLY" == "true" || "$MONITORING_ONLY" == "true" || "$TEST_RESOURCES_ONLY" == "true" ]]; then
        log "Skipping resource group deletion due to partial cleanup mode"
        return 0
    fi

    log "Removing resource group: $RESOURCE_GROUP"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete entire resource group: $RESOURCE_GROUP"
        return 0
    fi

    # Final check for any remaining resources
    local remaining_resources
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    
    if [[ "$remaining_resources" -gt 0 ]]; then
        warning "Found $remaining_resources remaining resources in resource group"
        log "Proceeding with resource group deletion..."
    fi

    # Delete the entire resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait

    success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Complete deletion may take several minutes to complete"
}

# Clean up configuration files
cleanup_config_files() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would remove configuration file: $CONFIG_FILE"
        return 0
    fi

    if [[ -f "$CONFIG_FILE" ]]; then
        log "Removing configuration file: $CONFIG_FILE"
        rm -f "$CONFIG_FILE"
        success "Configuration file removed"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Cleanup verification skipped"
        return 0
    fi

    log "Verifying cleanup completion..."

    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$PARTIAL_CLEANUP" == "true" || "$AUTOMATION_ONLY" == "true" || "$MONITORING_ONLY" == "true" || "$TEST_RESOURCES_ONLY" == "true" ]]; then
            log "Resource group still exists (expected for partial cleanup)"
            
            # List remaining resources
            local remaining_resources
            remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
            log "Remaining resources: $remaining_resources"
            
            if [[ "$remaining_resources" -gt 0 ]]; then
                log "Remaining resources in $RESOURCE_GROUP:"
                az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
            fi
        else
            warning "Resource group still exists - deletion may still be in progress"
            log "Check Azure Portal for deletion status"
        fi
    else
        success "✓ Resource group successfully deleted"
    fi

    # Check for any remaining role assignments (if we had principal ID)
    if [[ -n "$PRINCIPAL_ID" && "$AUTOMATION_ONLY" != "true" && "$TEST_RESOURCES_ONLY" != "true" ]]; then
        log "Checking for remaining role assignments..."
        local remaining_assignments
        remaining_assignments=$(az role assignment list --assignee "$PRINCIPAL_ID" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_assignments" -gt 0 ]]; then
            warning "Found $remaining_assignments remaining role assignments"
            log "These may be cleaned up automatically or require manual removal"
        fi
    fi

    success "Cleanup verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    log "Cleanup operation completed!"
    echo
    echo "📊 Cleanup Summary:"
    echo "  Resource Group: $RESOURCE_GROUP"
    
    if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
        echo "  Mode: Partial cleanup"
    elif [[ "$AUTOMATION_ONLY" == "true" ]]; then
        echo "  Mode: Automation resources only"
    elif [[ "$MONITORING_ONLY" == "true" ]]; then
        echo "  Mode: Monitoring resources only"
    elif [[ "$TEST_RESOURCES_ONLY" == "true" ]]; then
        echo "  Mode: Test resources only"
    else
        echo "  Mode: Complete cleanup"
    fi
    
    if [[ "$KEEP_LOGS" == "true" ]]; then
        echo "  Logs: Preserved"
    else
        echo "  Logs: Removed"
    fi
    
    echo "  Completion Time: $(date)"
    echo
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "All specified resources have been cleaned up"
        
        if [[ "$PARTIAL_CLEANUP" == "false" && "$AUTOMATION_ONLY" == "false" && "$MONITORING_ONLY" == "false" && "$TEST_RESOURCES_ONLY" == "false" ]]; then
            log "💰 Cost Impact: Resource deletion will stop all associated charges"
            log "📝 Recommendation: Verify in Azure Portal that all resources are deleted"
        fi
    else
        log "DRY-RUN completed. Use without --dry-run to actually delete resources."
    fi
}

# Main cleanup function
main() {
    log "Starting Azure Cost Optimization cleanup..."
    
    # Parse arguments
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "Running in DRY-RUN mode - no resources will be deleted"
    fi

    # Execute cleanup steps
    load_config
    check_prerequisites
    
    if ! show_cleanup_plan; then
        log "No resources to clean up"
        exit 0
    fi
    
    confirm_cleanup
    cleanup_test_resources
    cleanup_automation_resources
    cleanup_monitoring_resources
    cleanup_resource_group
    cleanup_config_files
    verify_cleanup
    show_cleanup_summary
}

# Error handling
trap 'error "Cleanup failed on line $LINENO. Exit code: $?"' ERR

# Run main function with all arguments
main "$@"