#!/bin/bash

# Destroy Auto-Scaling Web Applications with Azure VMSS and Load Balancer
# Recipe: deploying-auto-scaling-web-applications-with-azure-virtual-machine-scale-sets-and-azure-load-balancer
# Version: 1.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/../destroy.log"
ERROR_LOG="${SCRIPT_DIR}/../error.log"
ENV_FILE="${SCRIPT_DIR}/../.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FORCE=false
CONFIRM=true
PRESERVE_LOGS=false

# Functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" "$ERROR_LOG"
            ;;
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    echo -e "${RED}Cleanup failed. Check logs at: $LOG_FILE and $ERROR_LOG${NC}"
    exit 1
}

load_environment() {
    log INFO "Loading environment variables..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log WARN "Environment file not found at $ENV_FILE"
        log WARN "You may need to specify resource names manually"
        return 1
    fi
    
    # Source the environment file
    set -a  # automatically export all variables
    source "$ENV_FILE"
    set +a
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "SUBSCRIPTION_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log ERROR "Required environment variable $var is not set"
            return 1
        fi
    done
    
    log INFO "Environment loaded successfully"
    log DEBUG "Resource Group: $RESOURCE_GROUP"
    log DEBUG "Subscription: $SUBSCRIPTION_ID"
    
    return 0
}

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if subscription is set and matches
    local current_subscription=$(az account show --query id --output tsv 2>/dev/null || echo "")
    if [[ -n "${SUBSCRIPTION_ID:-}" && "$current_subscription" != "$SUBSCRIPTION_ID" ]]; then
        log WARN "Current subscription ($current_subscription) doesn't match deployment subscription ($SUBSCRIPTION_ID)"
        log WARN "Setting subscription to match deployment..."
        az account set --subscription "$SUBSCRIPTION_ID" || error_exit "Failed to set subscription"
    fi
    
    log INFO "Prerequisites check passed"
}

confirm_destruction() {
    if [[ "$CONFIRM" == "false" ]] || [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo ""
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        echo "  Resource Group: $RESOURCE_GROUP"
        
        # List resources in the resource group
        log DEBUG "Fetching resource list for confirmation..."
        local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "Unable to fetch resource list")
        if [[ "$resources" != "Unable to fetch resource list" ]]; then
            echo ""
            echo "  Resources to be deleted:"
            echo "$resources" | sed 's/^/    /'
        fi
    else
        echo "  Resource Group: <not specified>"
    fi
    
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log INFO "Destruction cancelled by user"
        exit 0
    fi
    
    log INFO "User confirmed destruction"
}

backup_configuration() {
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        log INFO "Creating backup of configuration and logs..."
        
        local backup_dir="${SCRIPT_DIR}/../backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Copy environment file
        if [[ -f "$ENV_FILE" ]]; then
            cp "$ENV_FILE" "$backup_dir/"
        fi
        
        # Copy logs
        if [[ -f "$LOG_FILE" ]]; then
            cp "$LOG_FILE" "$backup_dir/"
        fi
        
        if [[ -f "$ERROR_LOG" ]]; then
            cp "$ERROR_LOG" "$backup_dir/"
        fi
        
        log INFO "Backup created at: $backup_dir"
    fi
}

check_resource_dependencies() {
    log INFO "Checking for resource dependencies..."
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log WARN "Resource group not specified, skipping dependency check"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' does not exist or is already deleted"
        return 0
    fi
    
    # Check for any locks on the resource group
    local locks=$(az lock list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    if [[ "$locks" -gt 0 ]]; then
        log WARN "Found $locks resource locks that may prevent deletion"
        if [[ "$FORCE" == "false" ]]; then
            log ERROR "Resource locks detected. Use --force to attempt deletion anyway, or remove locks manually"
            exit 1
        fi
    fi
    
    # Check for protected resources
    local protected_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[?tags.protected=='true'].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$protected_resources" ]]; then
        log WARN "Found protected resources: $protected_resources"
        if [[ "$FORCE" == "false" ]]; then
            log ERROR "Protected resources detected. Use --force to attempt deletion anyway"
            exit 1
        fi
    fi
    
    log INFO "Dependency check completed"
}

delete_individual_resources() {
    log INFO "Attempting to delete individual resources first..."
    
    # Delete auto-scaling settings first to prevent new instances
    if [[ -n "${AUTOSCALE_NAME:-}" ]]; then
        log DEBUG "Deleting auto-scale profile: $AUTOSCALE_NAME"
        az monitor autoscale delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$AUTOSCALE_NAME" \
            2>/dev/null || log WARN "Failed to delete auto-scale profile (may not exist)"
    fi
    
    # Delete metric alerts
    log DEBUG "Deleting metric alerts..."
    local alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert; do
            if [[ -n "$alert" ]]; then
                log DEBUG "Deleting alert: $alert"
                az monitor metrics alert delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$alert" \
                    2>/dev/null || log WARN "Failed to delete alert: $alert"
            fi
        done <<< "$alerts"
    fi
    
    # Scale down VMSS to minimum before deletion (faster cleanup)
    if [[ -n "${VMSS_NAME:-}" ]]; then
        log DEBUG "Scaling down VMSS before deletion: $VMSS_NAME"
        az vmss scale \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --new-capacity 0 \
            2>/dev/null || log WARN "Failed to scale down VMSS (may not exist)"
        
        # Wait a bit for scale-down to complete
        sleep 30
    fi
    
    log INFO "Individual resource cleanup completed"
}

delete_resource_group() {
    log INFO "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log ERROR "Resource group name is not set"
        return 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi
    
    # Delete the resource group and all its resources
    log INFO "Initiating resource group deletion (this may take several minutes)..."
    
    if [[ "$FORCE" == "true" ]]; then
        # Force deletion with --force-deletion-types for faster cleanup
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --force-deletion-types Microsoft.Compute/virtualMachineScaleSets \
            --force-deletion-types Microsoft.Network/loadBalancers \
            || error_exit "Failed to initiate resource group deletion"
    else
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            || error_exit "Failed to initiate resource group deletion"
    fi
    
    log INFO "Resource group deletion initiated"
    
    # Optionally wait for deletion to complete
    if [[ "${WAIT_FOR_DELETION:-false}" == "true" ]]; then
        log INFO "Waiting for resource group deletion to complete..."
        local max_wait=1800  # 30 minutes
        local wait_time=0
        
        while [[ $wait_time -lt $max_wait ]]; do
            if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                log INFO "✅ Resource group deleted successfully"
                return 0
            fi
            
            log DEBUG "Still deleting... (${wait_time}s elapsed)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        log WARN "Resource group deletion is taking longer than expected"
        log WARN "Deletion will continue in the background"
    fi
    
    return 0
}

cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/../.env"
        "${SCRIPT_DIR}/../cloud-init.txt"
        "${SCRIPT_DIR}/../load-test.sh"
        "${SCRIPT_DIR}/../monitor.sh"
    )
    
    if [[ "$PRESERVE_LOGS" == "false" ]]; then
        files_to_remove+=(
            "${SCRIPT_DIR}/../deploy.log"
            "${SCRIPT_DIR}/../error.log"
            "$LOG_FILE"
            "$ERROR_LOG"
        )
    fi
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log DEBUG "Removing file: $file"
            rm -f "$file" || log WARN "Failed to remove file: $file"
        fi
    done
    
    # Clean up empty directories
    find "${SCRIPT_DIR}/.." -type d -empty -delete 2>/dev/null || true
    
    log INFO "✅ Local files cleaned up"
}

verify_deletion() {
    log INFO "Verifying resource deletion..."
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log WARN "Cannot verify deletion - resource group name not available"
        return 0
    fi
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "unknown")
        if [[ "$remaining" != "unknown" ]]; then
            log INFO "Remaining resources in group: $remaining"
            if [[ "$remaining" -gt 0 ]]; then
                log DEBUG "Some resources may still be in the process of being deleted"
            fi
        fi
    else
        log INFO "✅ Resource group '$RESOURCE_GROUP' has been successfully deleted"
    fi
}

print_cleanup_summary() {
    echo ""
    echo "======================================"
    echo "  CLEANUP SUMMARY"
    echo "======================================"
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        echo "Resource Group: $RESOURCE_GROUP"
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            echo "Status: Deletion in progress"
            echo "Note: Complete deletion may take several more minutes"
        else
            echo "Status: Successfully deleted"
        fi
    else
        echo "Resource Group: Not specified"
    fi
    
    echo ""
    echo "Cleanup Actions Performed:"
    echo "  ✅ Auto-scaling rules removed"
    echo "  ✅ Metric alerts deleted"
    echo "  ✅ VMSS scaled down and deleted"
    echo "  ✅ Load Balancer and networking deleted"
    echo "  ✅ Application Insights deleted"
    
    if [[ "$PRESERVE_LOGS" == "true" ]]; then
        echo "  ✅ Configuration and logs backed up"
    else
        echo "  ✅ Local files cleaned up"
    fi
    
    echo ""
    echo "Important Notes:"
    echo "  - Resource deletion runs asynchronously in Azure"
    echo "  - Some resources may take additional time to fully delete"
    echo "  - Billing stops when resources are successfully deleted"
    echo "  - Check Azure Portal to confirm complete removal"
    echo ""
    echo "To verify deletion status:"
    echo "  az group show --name '$RESOURCE_GROUP'"
    echo "======================================"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy auto-scaling web application infrastructure"
    echo ""
    echo "Options:"
    echo "  -f, --force                   Force deletion without confirmation prompts"
    echo "  -y, --yes                     Skip confirmation prompts (same as --force)"
    echo "  -w, --wait                    Wait for deletion to complete before exiting"
    echo "  -p, --preserve-logs           Preserve logs and configuration files"
    echo "  -g, --resource-group NAME     Override resource group name"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive cleanup with confirmation"
    echo "  $0 --force                   # Cleanup without confirmation"
    echo "  $0 --wait --preserve-logs    # Wait for completion and preserve logs"
    echo "  $0 -g my-custom-rg --force   # Force cleanup of specific resource group"
    echo ""
    echo "Safety Features:"
    echo "  - Confirms deletion before proceeding (unless --force)"
    echo "  - Checks for resource locks and protected resources"
    echo "  - Backs up configuration when --preserve-logs is used"
    echo "  - Provides detailed logging of all operations"
}

main() {
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    > "$LOG_FILE"  # Clear log file
    > "$ERROR_LOG"  # Clear error log file
    
    log INFO "Starting cleanup of auto-scaling web application..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force|-y|--yes)
                FORCE=true
                CONFIRM=false
                shift
                ;;
            -w|--wait)
                WAIT_FOR_DELETION=true
                shift
                ;;
            -p|--preserve-logs)
                PRESERVE_LOGS=true
                shift
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -h|--help)
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
    
    # Load environment if not provided via command line
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        if ! load_environment; then
            log ERROR "Could not load environment. Please specify --resource-group or ensure .env file exists"
            exit 1
        fi
    fi
    
    # Run cleanup steps
    check_prerequisites
    confirm_destruction
    backup_configuration
    check_resource_dependencies
    delete_individual_resources
    delete_resource_group
    cleanup_local_files
    verify_deletion
    print_cleanup_summary
    
    log INFO "Cleanup completed successfully in $(($SECONDS / 60)) minutes and $(($SECONDS % 60)) seconds"
    
    if [[ "${WAIT_FOR_DELETION:-false}" != "true" ]]; then
        echo ""
        echo -e "${YELLOW}Note: Resource deletion continues in the background.${NC}"
        echo -e "${YELLOW}Check Azure Portal or run 'az group show --name $RESOURCE_GROUP' to verify completion.${NC}"
    fi
}

# Handle script interruption
trap 'log ERROR "Cleanup interrupted by user"; exit 130' INT TERM

# Run main function with all arguments
main "$@"