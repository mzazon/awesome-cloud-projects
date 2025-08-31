#!/bin/bash

# Azure Infrastructure Inventory with Resource Graph - Cleanup Script
# This script cleans up generated inventory files and optionally removes
# the Azure Resource Graph extension.

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly DRY_RUN="${DRY_RUN:-false}"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
REMOVE_EXTENSION="false"
FORCE_CLEANUP="false"
SUBSCRIPTION_ID=""

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code"
    log_error "Check the log file for details: $LOG_FILE"
    exit $exit_code
}

trap cleanup_on_error ERR

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Clean up Azure Resource Graph infrastructure inventory solution.

OPTIONS:
    --remove-extension     Remove the Azure Resource Graph CLI extension
    --force               Skip confirmation prompts
    --dry-run             Show what would be done without executing
    --help                Display this help message

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --remove-extension
    $SCRIPT_NAME --force --remove-extension
    $SCRIPT_NAME --dry-run

ENVIRONMENT VARIABLES:
    DRY_RUN               Set to 'true' to enable dry-run mode

NOTE:
    This script only cleans up generated files and optionally removes the
    Resource Graph extension since no actual Azure resources are created.

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remove-extension)
                REMOVE_EXTENSION="true"
                shift
                ;;
            --force)
                FORCE_CLEANUP="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --help)
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

# Prerequisite checks
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_warning "Azure CLI is not installed. Limited cleanup operations available."
        return 0
    fi

    # Get current subscription ID if logged in
    if az account show &> /dev/null; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        log_info "Using subscription: $SUBSCRIPTION_ID"
    else
        log_warning "Not logged in to Azure. Some cleanup operations may be limited."
    fi

    log_success "Prerequisites check completed"
}

# Confirm cleanup operations
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warning "This will clean up the following:"
    echo "  - Generated inventory JSON files (infrastructure-inventory-*.json)"
    echo "  - Temporary files and logs"
    echo "  - Environment variables from current session"
    
    if [[ "$REMOVE_EXTENSION" == "true" ]]; then
        echo "  - Azure Resource Graph CLI extension (WARNING: This affects all future usage)"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove generated inventory files
remove_inventory_files() {
    log_info "Removing generated inventory files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove inventory files matching: infrastructure-inventory-*.json"
        if ls infrastructure-inventory-*.json 1> /dev/null 2>&1; then
            log_info "[DRY RUN] Files that would be removed:"
            ls -la infrastructure-inventory-*.json | tee -a "$LOG_FILE"
        else
            log_info "[DRY RUN] No inventory files found to remove"
        fi
        return 0
    fi

    # Find and remove inventory files
    local files_removed=0
    local total_size=0
    
    if ls infrastructure-inventory-*.json 1> /dev/null 2>&1; then
        log_info "Found inventory files to remove:"
        
        for file in infrastructure-inventory-*.json; do
            if [[ -f "$file" ]]; then
                local file_size
                file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
                total_size=$((total_size + file_size))
                
                log_info "  - $file ($(numfmt --to=iec $file_size 2>/dev/null || echo "${file_size} bytes"))"
                
                if rm -f "$file"; then
                    files_removed=$((files_removed + 1))
                else
                    log_error "Failed to remove $file"
                fi
            fi
        done
        
        if [[ $files_removed -gt 0 ]]; then
            log_success "Removed $files_removed inventory files (total: $(numfmt --to=iec $total_size 2>/dev/null || echo "${total_size} bytes"))"
        fi
    else
        log_info "No inventory files found to remove"
    fi

    # Remove temporary files created during deployment
    local temp_files=("/tmp/test_query.out" "/tmp/schema_query.out" "/tmp/basic_inventory.out" 
                     "/tmp/type_summary.out" "/tmp/location_dist.out" "/tmp/location_detail.out"
                     "/tmp/tagging_compliance.out" "/tmp/missing_tags.out" "/tmp/export_error.log"
                     "/tmp/summary_stats.out" "/tmp/subscription_coverage.out" "/tmp/perf_test.out")

    local temp_removed=0
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            if rm -f "$temp_file"; then
                temp_removed=$((temp_removed + 1))
            fi
        fi
    done

    if [[ $temp_removed -gt 0 ]]; then
        log_success "Removed $temp_removed temporary files"
    fi

    log_success "Inventory file cleanup completed"
}

# Clear environment variables
clear_environment_variables() {
    log_info "Clearing environment variables..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clear the following environment variables:"
        log_info "  - RESOURCE_COUNTS"
        log_info "  - INVENTORY_QUERY"
        log_info "  - TOTAL_RESOURCES"
        log_info "  - RANDOM_SUFFIX"
        log_info "  - LOCATION"
        log_info "  - SUBSCRIPTION_ID"
        return 0
    fi

    # List of variables to clear
    local variables=("RESOURCE_COUNTS" "INVENTORY_QUERY" "TOTAL_RESOURCES" 
                    "RANDOM_SUFFIX" "LOCATION" "SUBSCRIPTION_ID")
    
    local cleared_count=0
    for var in "${variables[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
            cleared_count=$((cleared_count + 1))
            log_info "  - Cleared $var"
        fi
    done

    if [[ $cleared_count -gt 0 ]]; then
        log_success "Cleared $cleared_count environment variables"
    else
        log_info "No environment variables to clear"
    fi

    log_success "Environment variable cleanup completed"
}

# Remove Azure Resource Graph extension
remove_resource_graph_extension() {
    if [[ "$REMOVE_EXTENSION" != "true" ]]; then
        return 0
    fi

    log_info "Removing Azure Resource Graph CLI extension..."

    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        log_warning "Azure CLI not available, cannot remove extension"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove resource-graph extension"
        return 0
    fi

    # Check if extension is installed
    if ! az extension list --query "[?name=='resource-graph']" --output tsv | grep -q resource-graph; then
        log_info "Resource Graph extension is not installed"
        return 0
    fi

    # Confirm extension removal with additional warning
    if [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo ""
        log_warning "IMPORTANT: Removing the Resource Graph extension will affect ALL future usage!"
        log_warning "You will need to reinstall it with 'az extension add --name resource-graph'"
        echo ""
        read -p "Are you absolutely sure you want to remove the extension? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
            log_info "Extension removal cancelled by user"
            return 0
        fi
    fi

    # Remove the extension
    log_info "Removing Resource Graph extension..."
    if az extension remove --name resource-graph; then
        log_success "Resource Graph extension removed successfully"
        log_info "To reinstall: az extension add --name resource-graph"
    else
        log_error "Failed to remove Resource Graph extension"
        return 1
    fi

    log_success "Extension removal completed"
}

# Clean up log files (optional)
cleanup_logs() {
    log_info "Cleaning up old log files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up log files older than 30 days"
        if find "$SCRIPT_DIR" -name "*.log" -type f -mtime +30 2>/dev/null | head -5; then
            log_info "[DRY RUN] Sample old log files found"
        else
            log_info "[DRY RUN] No old log files found"
        fi
        return 0
    fi

    # Remove log files older than 30 days
    local old_logs_removed=0
    
    if command -v find &> /dev/null; then
        while IFS= read -r -d '' log_file; do
            if rm -f "$log_file"; then
                old_logs_removed=$((old_logs_removed + 1))
                log_info "  - Removed old log: $(basename "$log_file")"
            fi
        done < <(find "$SCRIPT_DIR" -name "*.log" -type f -mtime +30 -print0 2>/dev/null)
    fi

    if [[ $old_logs_removed -gt 0 ]]; then
        log_success "Removed $old_logs_removed old log files"
    else
        log_info "No old log files to remove"
    fi

    log_success "Log cleanup completed"
}

# Validate cleanup operations
validate_cleanup() {
    log_info "Validating cleanup operations..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate cleanup completion"
        return 0
    fi

    local validation_errors=0

    # Check for remaining inventory files
    if ls infrastructure-inventory-*.json 1> /dev/null 2>&1; then
        log_warning "Some inventory files still exist:"
        ls -la infrastructure-inventory-*.json | tee -a "$LOG_FILE"
        validation_errors=$((validation_errors + 1))
    else
        log_success "All inventory files removed successfully"
    fi

    # Check extension status if removal was requested
    if [[ "$REMOVE_EXTENSION" == "true" ]] && command -v az &> /dev/null; then
        if az extension list --query "[?name=='resource-graph']" --output tsv 2>/dev/null | grep -q resource-graph; then
            log_warning "Resource Graph extension is still installed"
            validation_errors=$((validation_errors + 1))
        else
            log_success "Resource Graph extension removed successfully"
        fi
    fi

    # Check for remaining temporary files
    local temp_files=("/tmp/test_query.out" "/tmp/schema_query.out" "/tmp/basic_inventory.out")
    local remaining_temp=0
    
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            remaining_temp=$((remaining_temp + 1))
        fi
    done

    if [[ $remaining_temp -gt 0 ]]; then
        log_warning "$remaining_temp temporary files still exist"
        validation_errors=$((validation_errors + 1))
    else
        log_success "All temporary files cleaned up"
    fi

    if [[ $validation_errors -eq 0 ]]; then
        log_success "Cleanup validation passed"
    else
        log_warning "Cleanup validation found $validation_errors issues"
    fi

    return $validation_errors
}

# Display cleanup summary
display_summary() {
    log_info "=== Azure Resource Graph Inventory Cleanup Summary ==="
    
    echo "Cleanup Details:" | tee -a "$LOG_FILE"
    echo "  - Timestamp: $TIMESTAMP" | tee -a "$LOG_FILE"
    echo "  - Dry Run: $DRY_RUN" | tee -a "$LOG_FILE"
    echo "  - Force Mode: $FORCE_CLEANUP" | tee -a "$LOG_FILE"
    echo "  - Remove Extension: $REMOVE_EXTENSION" | tee -a "$LOG_FILE"
    
    if [[ -n "$SUBSCRIPTION_ID" ]]; then
        echo "  - Subscription ID: $SUBSCRIPTION_ID" | tee -a "$LOG_FILE"
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Completed Operations:" | tee -a "$LOG_FILE"
        echo "  ✅ Generated inventory files removed" | tee -a "$LOG_FILE"
        echo "  ✅ Temporary files cleaned up" | tee -a "$LOG_FILE"
        echo "  ✅ Environment variables cleared" | tee -a "$LOG_FILE"
        echo "  ✅ Old log files cleaned up" | tee -a "$LOG_FILE"
        
        if [[ "$REMOVE_EXTENSION" == "true" ]]; then
            echo "  ✅ Resource Graph extension removed" | tee -a "$LOG_FILE"
        else
            echo "  ℹ️  Resource Graph extension preserved (use --remove-extension to remove)" | tee -a "$LOG_FILE"
        fi
        
        echo "  ✅ Cleanup validation performed" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    echo "Important Notes:" | tee -a "$LOG_FILE"
    echo "  - No actual Azure resources were created or need cleanup" | tee -a "$LOG_FILE"
    echo "  - Azure Resource Graph service remains available for future use" | tee -a "$LOG_FILE"
    
    if [[ "$REMOVE_EXTENSION" == "true" && "$DRY_RUN" == "false" ]]; then
        echo "  - Resource Graph extension was removed - reinstall with: az extension add --name resource-graph" | tee -a "$LOG_FILE"
    elif [[ "$REMOVE_EXTENSION" != "true" ]]; then
        echo "  - Resource Graph extension remains installed for future inventory operations" | tee -a "$LOG_FILE"
    fi
    
    echo "" | tee -a "$LOG_FILE"
    echo "Future Usage:" | tee -a "$LOG_FILE"
    echo "  - Run deploy.sh again to generate new inventory reports" | tee -a "$LOG_FILE"
    echo "  - Use Azure Portal Resource Graph Explorer for interactive queries" | tee -a "$LOG_FILE"
    echo "  - Access Azure Resource Graph documentation at:" | tee -a "$LOG_FILE"
    echo "    https://learn.microsoft.com/en-us/azure/governance/resource-graph/" | tee -a "$LOG_FILE"
    
    log_success "Azure Resource Graph inventory cleanup completed successfully!"
    log_info "Log file: $LOG_FILE"
}

# Main cleanup function
main() {
    log_info "Starting Azure Resource Graph inventory cleanup..."
    log_info "Script: $SCRIPT_NAME"
    log_info "Version: 1.0"
    log_info "Timestamp: $TIMESTAMP"
    
    parse_arguments "$@"
    check_prerequisites
    confirm_cleanup
    remove_inventory_files
    clear_environment_variables
    remove_resource_graph_extension
    cleanup_logs
    validate_cleanup
    display_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi