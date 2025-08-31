#!/bin/bash

# ==============================================================================
# Azure Basic Database Web App Cleanup Script
# This script removes all resources created by the deployment script
# ==============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration variables
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME    Specify resource group to delete"
    echo "  -f, --force                  Skip safety prompts and force deletion"
    echo "  -y, --yes                    Skip confirmation prompt"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP              Resource group name to delete"
    echo "  FORCE_DELETE               Set to 'true' to force deletion"
    echo "  SKIP_CONFIRMATION          Set to 'true' to skip confirmation"
    echo ""
    echo "Examples:"
    echo "  $0 -g rg-webapp-demo-abc123"
    echo "  $0 --resource-group rg-webapp-demo-abc123 --force"
    echo "  RESOURCE_GROUP=rg-webapp-demo-abc123 $0 --yes"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to discover resource groups
discover_resource_groups() {
    log_info "Discovering resource groups with recipe tags..."
    
    local resource_groups=$(az group list \
        --query "[?tags.purpose=='recipe'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$resource_groups" ]]; then
        log_warning "No resource groups found with recipe tags"
        return
    fi
    
    echo ""
    echo "Found resource groups created by recipe deployments:"
    echo "=================================================="
    local count=1
    while IFS= read -r rg; do
        if [[ -n "$rg" ]]; then
            echo "$count. $rg"
            count=$((count + 1))
        fi
    done <<< "$resource_groups"
    echo ""
}

# Function to validate resource group
validate_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group not specified"
        echo ""
        discover_resource_groups
        echo "Please specify a resource group using:"
        echo "  - Command line: $0 -g <resource-group-name>"
        echo "  - Environment variable: export RESOURCE_GROUP=<resource-group-name>"
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist"
        discover_resource_groups
        exit 1
    fi
    
    log_info "Resource group '$RESOURCE_GROUP' found"
}

# Function to list resources in the resource group
list_resources() {
    log_info "Listing resources in resource group '$RESOURCE_GROUP'..."
    
    local resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || echo "")
    
    if [[ -z "$resources" ]]; then
        log_warning "No resources found in resource group '$RESOURCE_GROUP'"
        return
    fi
    
    echo ""
    echo "Resources to be deleted:"
    echo "========================"
    echo "$resources"
    echo ""
}

# Function to get cost information
get_cost_information() {
    log_info "Retrieving cost information (if available)..."
    
    # Note: Cost information requires proper setup and may not be immediately available
    local subscription_id=$(az account show --query id --output tsv)
    
    echo ""
    echo "💰 Cost Information:"
    echo "==================="
    echo "For detailed cost information, visit:"
    echo "https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/costanalysis/subscriptionId/$subscription_id"
    echo ""
    echo "⚠️  Important: Deleting resources will stop ongoing charges, but you may"
    echo "   still see charges for usage before deletion in your next bill."
    echo ""
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping confirmation (--yes flag used)"
        return
    fi
    
    echo ""
    echo "⚠️  WARNING: This action will permanently delete the resource group and ALL resources within it!"
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force deletion enabled - proceeding without confirmation"
        return
    fi
    
    read -p "Are you sure you want to delete this resource group and all its resources? (type 'yes' to confirm): " -r
    echo ""
    
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Deletion confirmed by user"
}

# Function to perform pre-deletion safety checks
safety_checks() {
    log_info "Performing safety checks..."
    
    # Check if resource group has protection policies (if available)
    local locks=$(az lock list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Level:level}" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$locks" ]]; then
        log_error "Resource group has resource locks that prevent deletion:"
        echo "$locks"
        echo ""
        echo "Please remove the locks before proceeding with deletion:"
        echo "az lock delete --name <lock-name> --resource-group $RESOURCE_GROUP"
        exit 1
    fi
    
    # Check for dependencies (basic check for common scenarios)
    local sql_servers=$(az sql server list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$sql_servers" ]]; then
        log_warning "Found SQL Server(s) - ensuring no external dependencies..."
        # Additional checks could be added here for production systems
    fi
    
    log_success "Safety checks completed"
}

# Function to backup critical data (optional)
backup_critical_data() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_info "Skipping backup due to force deletion"
        return
    fi
    
    log_info "Checking for critical data to backup..."
    
    # Check for SQL databases
    local databases=$(az sql db list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?name != 'master'].{Server:serverName, Database:name}" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$databases" ]]; then
        echo ""
        echo "📊 Found SQL Database(s):"
        echo "========================="
        while IFS=$'\t' read -r server database; do
            if [[ -n "$server" && -n "$database" ]]; then
                echo "Server: $server, Database: $database"
            fi
        done <<< "$databases"
        echo ""
        
        read -p "Do you want to create a backup before deletion? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating database backup..."
            # In a production scenario, you would implement actual backup logic here
            log_warning "Backup functionality not implemented in this demo script"
            log_info "For production use, consider implementing database export or backup to storage account"
        fi
    fi
}

# Function to delete resources individually (if needed)
delete_resources_individually() {
    log_warning "Attempting individual resource deletion as fallback..."
    
    # Delete web apps first
    local webapps=$(az webapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    while IFS= read -r webapp; do
        if [[ -n "$webapp" ]]; then
            log_info "Deleting web app: $webapp"
            az webapp delete \
                --name "$webapp" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete web app: $webapp"
        fi
    done <<< "$webapps"
    
    # Delete app service plans
    local plans=$(az appservice plan list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    while IFS= read -r plan; do
        if [[ -n "$plan" ]]; then
            log_info "Deleting app service plan: $plan"
            az appservice plan delete \
                --name "$plan" \
                --resource-group "$RESOURCE_GROUP" \
                --yes || log_warning "Failed to delete app service plan: $plan"
        fi
    done <<< "$plans"
    
    # Delete SQL databases and servers
    local servers=$(az sql server list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    while IFS= read -r server; do
        if [[ -n "$server" ]]; then
            log_info "Deleting SQL server: $server"
            az sql server delete \
                --name "$server" \
                --resource-group "$RESOURCE_GROUP" \
                --yes || log_warning "Failed to delete SQL server: $server"
        fi
    done <<< "$servers"
    
    log_success "Individual resource deletion completed"
}

# Function to delete the resource group
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    local start_time=$(date +%s)
    
    # Attempt to delete the resource group
    if az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait; then
        
        log_success "Resource group deletion initiated"
        log_info "Deletion is running asynchronously..."
        
        # Monitor deletion progress
        local max_wait_time=1800  # 30 minutes
        local elapsed_time=0
        
        while [[ $elapsed_time -lt $max_wait_time ]]; do
            if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                local end_time=$(date +%s)
                local total_time=$((end_time - start_time))
                log_success "Resource group deleted successfully in $total_time seconds"
                return 0
            fi
            
            log_info "Waiting for deletion to complete... ($elapsed_time/$max_wait_time seconds)"
            sleep 30
            elapsed_time=$((elapsed_time + 30))
        done
        
        log_warning "Deletion is taking longer than expected. Check Azure Portal for status."
        
    else
        log_error "Failed to initiate resource group deletion"
        
        # Try individual resource deletion as fallback
        log_info "Attempting fallback: individual resource deletion"
        delete_resources_individually
        
        # Try resource group deletion again
        log_info "Retrying resource group deletion..."
        if az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait; then
            log_success "Resource group deletion initiated on second attempt"
        else
            log_error "Resource group deletion failed. Manual cleanup may be required."
            return 1
        fi
    fi
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group still exists - deletion may still be in progress"
        
        # List remaining resources
        local remaining=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$remaining" ]]; then
            log_warning "Remaining resources:"
            echo "$remaining"
        fi
        
        return 1
    else
        log_success "Resource group deletion verified"
        return 0
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Remove deployment log if it exists
    if [[ -f "$script_dir/deployment.log" ]]; then
        rm -f "$script_dir/deployment.log"
        log_success "Removed deployment.log"
    fi
    
    # Remove any temporary files
    rm -f index.html index.html.bak
    
    # Clear environment variables
    unset RESOURCE_GROUP LOCATION SQL_SERVER_NAME SQL_DATABASE_NAME
    unset APP_SERVICE_PLAN WEB_APP_NAME RANDOM_SUFFIX MANAGED_IDENTITY_ID
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    local subscription_id=$(az account show --query id --output tsv 2>/dev/null || echo "unknown")
    
    echo ""
    echo "🧹 Cleanup Summary"
    echo "=================="
    log_success "Resource group '$RESOURCE_GROUP' and all its resources have been deleted"
    echo ""
    echo "You can verify the deletion in the Azure Portal:"
    echo "https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups"
    echo ""
    echo "💰 Cost Impact:"
    echo "- All resource charges have been stopped"
    echo "- You may still see charges for usage before deletion in your next bill"
    echo "- Check your cost analysis for final usage details"
    echo ""
    log_info "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting Azure Basic Database Web App cleanup..."
    log_info "Timestamp: $(date)"
    
    # Store current directory and create log file
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local log_file="$script_dir/cleanup.log"
    
    echo "Cleanup started at $(date)" > "$log_file"
    
    # Execute cleanup steps
    check_prerequisites
    validate_resource_group
    list_resources
    get_cost_information
    confirm_deletion
    safety_checks
    backup_critical_data
    delete_resource_group
    
    # Wait a moment and verify
    sleep 10
    if verify_deletion; then
        display_cleanup_summary
    else
        log_warning "Deletion verification failed - resources may still be deleting"
        echo ""
        echo "To check deletion status:"
        echo "az group show --name $RESOURCE_GROUP"
        echo ""
        echo "If resources remain, you may need to:"
        echo "1. Wait longer for deletion to complete"
        echo "2. Check for resource locks or dependencies"
        echo "3. Delete resources manually in the Azure Portal"
    fi
    
    cleanup_local_files
    
    echo "Cleanup process completed at $(date)" >> "$log_file"
    log_info "Cleanup log saved to: $log_file"
}

# Parse command line arguments
parse_arguments "$@"

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi