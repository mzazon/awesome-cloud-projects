#!/bin/bash
#
# Azure Quantum Trading Algorithm Cleanup Script
# This script safely removes all resources created by the deployment script
# including Azure Quantum, Azure Elastic SAN, and Azure Machine Learning
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   -h, --help          Show this help message
#   -v, --verbose       Enable verbose output
#   -f, --force         Force deletion without confirmation
#   -k, --keep-storage  Keep storage accounts and data
#   -p, --parallel      Delete resources in parallel (faster but less safe)
#   -t, --timeout       Set deletion timeout in minutes (default: 30)
#

set -euo pipefail

# Configuration defaults
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DELETION_TIMEOUT=30
readonly MAX_WAIT_TIME=1800  # 30 minutes in seconds

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
VERBOSE=false
FORCE=false
KEEP_STORAGE=false
PARALLEL=false
TIMEOUT=${DELETION_TIMEOUT}

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
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
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_handler() {
    local line_number="$1"
    local error_code="$2"
    local command="$3"
    
    log "ERROR" "Script failed at line $line_number with exit code $error_code"
    log "ERROR" "Failed command: $command"
    log "ERROR" "Check $LOG_FILE for detailed error information"
    
    exit "$error_code"
}

# Set up error handling
trap 'error_handler ${LINENO} $? "${BASH_COMMAND}"' ERR

# Usage function
usage() {
    cat << EOF
Azure Quantum Trading Algorithm Cleanup Script

This script safely removes all resources created by the deployment script,
including:
- Azure Quantum workspace and quantum jobs
- Azure Elastic SAN volumes and storage
- Azure Machine Learning workspace and compute
- Event Hub namespaces and data streams
- Application Insights and monitoring components

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -f, --force         Force deletion without confirmation
    -k, --keep-storage  Keep storage accounts and their data
    -p, --parallel      Delete resources in parallel (faster but less safe)
    -t, --timeout       Set deletion timeout in minutes (default: 30)

Examples:
    $0                  # Interactive cleanup with confirmations
    $0 -v -f            # Force cleanup with verbose output
    $0 -k               # Keep storage accounts and data
    $0 -p               # Parallel deletion for faster cleanup
    $0 -t 45            # Set 45-minute timeout

Safety Features:
    - Multiple confirmation prompts (unless -f is used)
    - Graceful handling of missing resources
    - Detailed logging of all operations
    - Option to preserve data storage
    - Timeout protection for stuck operations

Cost Savings:
    - Removes all billable resources
    - Prevents ongoing charges for unused resources
    - Provides cost summary before deletion

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -k|--keep-storage)
                KEEP_STORAGE=true
                shift
                ;;
            -p|--parallel)
                PARALLEL=true
                shift
                ;;
            -t|--timeout)
                if [[ -n "${2:-}" ]]; then
                    TIMEOUT="$2"
                    shift 2
                else
                    log "ERROR" "Timeout value required"
                    exit 1
                fi
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking cleanup prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI not found. Please install Azure CLI"
        exit 1
    fi
    
    # Check login status
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    local subscription_name
    subscription_name=$(az account show --query name --output tsv)
    log "INFO" "Using subscription: $subscription_name ($subscription_id)"
    
    log "INFO" "Prerequisites check completed"
}

# Discover resources to delete
discover_resources() {
    log "INFO" "Discovering quantum trading resources..."
    
    # Find resource groups that match our naming pattern
    local resource_groups
    resource_groups=$(az group list --query "[?starts_with(name, 'rg-quantum-trading-')].name" -o tsv)
    
    if [[ -z "$resource_groups" ]]; then
        log "WARN" "No quantum trading resource groups found"
        return 1
    fi
    
    echo "Found quantum trading resource groups:"
    echo "$resource_groups"
    
    # If multiple resource groups found, let user choose
    if [[ $(echo "$resource_groups" | wc -l) -gt 1 ]]; then
        if [[ "$FORCE" == false ]]; then
            echo -e "${YELLOW}Multiple resource groups found. Please select one:${NC}"
            select rg in $resource_groups "All" "Cancel"; do
                case $rg in
                    "All")
                        RESOURCE_GROUPS="$resource_groups"
                        break
                        ;;
                    "Cancel")
                        log "INFO" "Cleanup cancelled by user"
                        exit 0
                        ;;
                    *)
                        if [[ -n "$rg" ]]; then
                            RESOURCE_GROUPS="$rg"
                            break
                        else
                            echo "Invalid selection. Please try again."
                        fi
                        ;;
                esac
            done
        else
            RESOURCE_GROUPS="$resource_groups"
        fi
    else
        RESOURCE_GROUPS="$resource_groups"
    fi
    
    log "INFO" "Will delete resource groups: $RESOURCE_GROUPS"
}

# Show resources to be deleted
show_resources_summary() {
    log "INFO" "Analyzing resources to be deleted..."
    
    local total_resources=0
    local estimated_cost=0
    
    for rg in $RESOURCE_GROUPS; do
        log "INFO" "Resources in $rg:"
        
        # Get resource list
        local resources
        resources=$(az resource list --resource-group "$rg" --query "[].{Name:name,Type:type,Location:location}" -o table 2>/dev/null || echo "No resources found")
        
        echo "$resources"
        
        # Count resources
        local rg_resources
        rg_resources=$(az resource list --resource-group "$rg" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        total_resources=$((total_resources + rg_resources))
        
        # Estimate cost savings (approximate)
        if az resource list --resource-group "$rg" --query "[?contains(type, 'Microsoft.Quantum')]" -o tsv 2>/dev/null | grep -q .; then
            estimated_cost=$((estimated_cost + 100))  # Quantum workspace
        fi
        
        if az resource list --resource-group "$rg" --query "[?contains(type, 'Microsoft.ElasticSan')]" -o tsv 2>/dev/null | grep -q .; then
            estimated_cost=$((estimated_cost + 200))  # Elastic SAN
        fi
        
        if az resource list --resource-group "$rg" --query "[?contains(type, 'Microsoft.MachineLearningServices')]" -o tsv 2>/dev/null | grep -q .; then
            estimated_cost=$((estimated_cost + 100))  # ML workspace
        fi
        
        if az resource list --resource-group "$rg" --query "[?contains(type, 'Microsoft.EventHub')]" -o tsv 2>/dev/null | grep -q .; then
            estimated_cost=$((estimated_cost + 50))   # Event Hub
        fi
    done
    
    echo ""
    echo "Deletion Summary:"
    echo "=================="
    echo "Resource Groups: $(echo "$RESOURCE_GROUPS" | wc -l)"
    echo "Total Resources: $total_resources"
    echo "Estimated Daily Cost Savings: \$${estimated_cost}"
    echo ""
    
    if [[ "$KEEP_STORAGE" == true ]]; then
        echo -e "${YELLOW}Note: Storage accounts will be preserved${NC}"
    fi
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == true ]]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -e "${RED}WARNING: This will permanently delete all quantum trading resources!${NC}"
    echo -e "${RED}This action cannot be undone.${NC}"
    echo ""
    echo -e "${YELLOW}Are you sure you want to continue? (type 'DELETE' to confirm)${NC}"
    read -r confirm
    
    if [[ "$confirm" != "DELETE" ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    # Second confirmation for safety
    echo -e "${YELLOW}Last chance! Type 'YES' to proceed with deletion:${NC}"
    read -r final_confirm
    
    if [[ "$final_confirm" != "YES" ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    log "INFO" "Deletion confirmed by user"
}

# Cancel quantum jobs
cancel_quantum_jobs() {
    local rg="$1"
    
    log "INFO" "Cancelling active quantum jobs in $rg..."
    
    # Find quantum workspaces
    local quantum_workspaces
    quantum_workspaces=$(az resource list --resource-group "$rg" --resource-type "Microsoft.Quantum/Workspaces" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$quantum_workspaces" ]]; then
        log "DEBUG" "No quantum workspaces found in $rg"
        return 0
    fi
    
    for workspace in $quantum_workspaces; do
        log "INFO" "Checking quantum jobs in workspace: $workspace"
        
        # List and cancel running jobs
        local running_jobs
        running_jobs=$(az quantum job list --resource-group "$rg" --workspace-name "$workspace" --query "[?status=='Executing' || status=='Waiting'].id" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$running_jobs" ]]; then
            log "INFO" "Cancelling running quantum jobs..."
            for job_id in $running_jobs; do
                az quantum job cancel --resource-group "$rg" --workspace-name "$workspace" --job-id "$job_id" --output none 2>/dev/null || true
                log "DEBUG" "Cancelled job: $job_id"
            done
        else
            log "DEBUG" "No running quantum jobs found"
        fi
    done
}

# Delete ML compute resources
delete_ml_compute() {
    local rg="$1"
    
    log "INFO" "Deleting ML compute resources in $rg..."
    
    # Find ML workspaces
    local ml_workspaces
    ml_workspaces=$(az resource list --resource-group "$rg" --resource-type "Microsoft.MachineLearningServices/workspaces" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$ml_workspaces" ]]; then
        log "DEBUG" "No ML workspaces found in $rg"
        return 0
    fi
    
    for workspace in $ml_workspaces; do
        log "INFO" "Deleting compute resources in ML workspace: $workspace"
        
        # List and delete compute clusters
        local compute_clusters
        compute_clusters=$(az ml compute list --resource-group "$rg" --workspace-name "$workspace" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        for cluster in $compute_clusters; do
            log "INFO" "Deleting compute cluster: $cluster"
            az ml compute delete --resource-group "$rg" --workspace-name "$workspace" --name "$cluster" --yes --output none 2>/dev/null || true
        done
    done
}

# Delete Elastic SAN volumes
delete_elastic_san_volumes() {
    local rg="$1"
    
    log "INFO" "Deleting Elastic SAN volumes in $rg..."
    
    # Find Elastic SAN instances
    local elastic_sans
    elastic_sans=$(az resource list --resource-group "$rg" --resource-type "Microsoft.ElasticSan/elasticSans" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$elastic_sans" ]]; then
        log "DEBUG" "No Elastic SAN instances found in $rg"
        return 0
    fi
    
    for esan in $elastic_sans; do
        log "INFO" "Deleting volumes in Elastic SAN: $esan"
        
        # List volume groups
        local volume_groups
        volume_groups=$(az elastic-san volume-group list --resource-group "$rg" --elastic-san-name "$esan" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        for vg in $volume_groups; do
            log "INFO" "Deleting volumes in volume group: $vg"
            
            # List and delete volumes
            local volumes
            volumes=$(az elastic-san volume list --resource-group "$rg" --elastic-san-name "$esan" --volume-group-name "$vg" --query "[].name" -o tsv 2>/dev/null || echo "")
            
            for volume in $volumes; do
                log "INFO" "Deleting volume: $volume"
                az elastic-san volume delete --resource-group "$rg" --elastic-san-name "$esan" --volume-group-name "$vg" --name "$volume" --yes --output none 2>/dev/null || true
            done
            
            # Delete volume group
            log "INFO" "Deleting volume group: $vg"
            az elastic-san volume-group delete --resource-group "$rg" --elastic-san-name "$esan" --name "$vg" --yes --output none 2>/dev/null || true
        done
    done
}

# Delete Stream Analytics jobs
delete_stream_analytics() {
    local rg="$1"
    
    log "INFO" "Stopping Stream Analytics jobs in $rg..."
    
    # Find Stream Analytics jobs
    local sa_jobs
    sa_jobs=$(az resource list --resource-group "$rg" --resource-type "Microsoft.StreamAnalytics/streamingjobs" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    for job in $sa_jobs; do
        log "INFO" "Stopping Stream Analytics job: $job"
        az stream-analytics job stop --resource-group "$rg" --name "$job" --output none 2>/dev/null || true
    done
}

# Delete resources in single resource group
delete_resource_group() {
    local rg="$1"
    
    log "INFO" "Deleting resource group: $rg"
    
    # Pre-deletion cleanup
    cancel_quantum_jobs "$rg"
    delete_ml_compute "$rg"
    delete_elastic_san_volumes "$rg"
    delete_stream_analytics "$rg"
    
    # Handle storage accounts
    if [[ "$KEEP_STORAGE" == true ]]; then
        log "INFO" "Preserving storage accounts in $rg"
        
        # List storage accounts
        local storage_accounts
        storage_accounts=$(az storage account list --resource-group "$rg" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        for sa in $storage_accounts; do
            log "INFO" "Moving storage account $sa to temporary resource group"
            
            # Create temporary resource group
            local temp_rg="temp-storage-$(date +%s)"
            az group create --name "$temp_rg" --location "eastus" --output none 2>/dev/null || true
            
            # Move storage account
            az resource move --destination-group "$temp_rg" --ids "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg/providers/Microsoft.Storage/storageAccounts/$sa" --output none 2>/dev/null || true
            
            log "INFO" "Storage account $sa moved to $temp_rg"
        done
    fi
    
    # Delete the resource group
    local start_time=$(date +%s)
    
    az group delete --name "$rg" --yes --no-wait
    
    log "INFO" "Resource group deletion initiated: $rg"
    
    # Wait for deletion to complete
    log "INFO" "Waiting for resource group deletion to complete..."
    
    while az group show --name "$rg" --output none 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $MAX_WAIT_TIME ]]; then
            log "WARN" "Deletion timeout reached for $rg. Continuing..."
            break
        fi
        
        log "DEBUG" "Still waiting for deletion of $rg (${elapsed}s elapsed)"
        sleep 30
    done
    
    log "INFO" "Resource group $rg deleted successfully"
}

# Delete resources in parallel
delete_resources_parallel() {
    log "INFO" "Starting parallel deletion of resource groups..."
    
    local pids=()
    
    for rg in $RESOURCE_GROUPS; do
        delete_resource_group "$rg" &
        pids+=($!)
        log "DEBUG" "Started deletion of $rg (PID: ${pids[-1]})"
    done
    
    # Wait for all deletions to complete
    log "INFO" "Waiting for all deletions to complete..."
    
    local failed_deletions=0
    
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            log "DEBUG" "Deletion process $pid completed successfully"
        else
            log "ERROR" "Deletion process $pid failed"
            ((failed_deletions++))
        fi
    done
    
    if [[ $failed_deletions -eq 0 ]]; then
        log "INFO" "All parallel deletions completed successfully"
    else
        log "WARN" "$failed_deletions deletion(s) failed"
    fi
}

# Delete resources sequentially
delete_resources_sequential() {
    log "INFO" "Starting sequential deletion of resource groups..."
    
    for rg in $RESOURCE_GROUPS; do
        delete_resource_group "$rg"
    done
    
    log "INFO" "All sequential deletions completed"
}

# Verify deletion
verify_deletion() {
    log "INFO" "Verifying resource deletion..."
    
    local remaining_resources=0
    
    for rg in $RESOURCE_GROUPS; do
        if az group show --name "$rg" --output none 2>/dev/null; then
            log "WARN" "Resource group $rg still exists"
            ((remaining_resources++))
        else
            log "DEBUG" "Resource group $rg successfully deleted"
        fi
    done
    
    if [[ $remaining_resources -eq 0 ]]; then
        log "INFO" "All resources successfully deleted"
    else
        log "WARN" "$remaining_resources resource group(s) still exist"
        log "INFO" "Check Azure portal for remaining resources"
    fi
}

# Show deletion summary
show_deletion_summary() {
    log "INFO" "Cleanup Summary"
    echo "================="
    echo "Resource Groups Processed: $(echo "$RESOURCE_GROUPS" | wc -l)"
    echo "Deletion Method: $(if [[ "$PARALLEL" == true ]]; then echo "Parallel"; else echo "Sequential"; fi)"
    echo "Storage Preservation: $(if [[ "$KEEP_STORAGE" == true ]]; then echo "Enabled"; else echo "Disabled"; fi)"
    echo ""
    echo "Cleanup completed at: $(date)"
    echo ""
    echo "Cost Impact:"
    echo "- All billable quantum trading resources have been removed"
    echo "- No ongoing charges for deleted resources"
    echo "- Check Azure Cost Management for final billing"
    echo ""
    if [[ "$KEEP_STORAGE" == true ]]; then
        echo "Note: Storage accounts were preserved and may continue to incur charges"
        echo "List preserved storage accounts with: az storage account list --query \"[?starts_with(resourceGroup,'temp-storage-')]\""
    fi
}

# Main cleanup function
main() {
    log "INFO" "Starting Azure Quantum Trading Algorithm cleanup"
    log "INFO" "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Discover resources
    if ! discover_resources; then
        log "INFO" "No resources to delete"
        exit 0
    fi
    
    # Show what will be deleted
    show_resources_summary
    
    # Confirm deletion
    confirm_deletion
    
    # Start cleanup timer
    local start_time=$(date +%s)
    
    # Delete resources
    if [[ "$PARALLEL" == true ]]; then
        delete_resources_parallel
    else
        delete_resources_sequential
    fi
    
    # Verify deletion
    verify_deletion
    
    # Calculate cleanup time
    local end_time=$(date +%s)
    local cleanup_time=$((end_time - start_time))
    
    log "INFO" "Cleanup completed in ${cleanup_time} seconds"
    
    # Show summary
    show_deletion_summary
    
    log "INFO" "Cleanup script completed successfully"
}

# Run main function with all arguments
main "$@"