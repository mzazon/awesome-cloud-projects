#!/bin/bash

# Azure Infrastructure Inventory with Resource Graph - Deployment Script
# This script installs the Azure Resource Graph extension and executes comprehensive
# inventory queries to generate governance and compliance reports.

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly DRY_RUN="${DRY_RUN:-false}"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SUBSCRIPTION_ID=""
LOCATION="eastus"
RANDOM_SUFFIX=""
TOTAL_RESOURCES=""
RESOURCE_COUNTS=""
INVENTORY_QUERY=""

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

Deploy Azure Resource Graph infrastructure inventory solution.

OPTIONS:
    --location LOCATION     Azure region for operations (default: eastus)
    --dry-run              Show what would be done without executing
    --help                 Display this help message

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --location westus2
    $SCRIPT_NAME --dry-run

ENVIRONMENT VARIABLES:
    DRY_RUN                Set to 'true' to enable dry-run mode
    AZURE_SUBSCRIPTION_ID  Override default subscription ID

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --location)
                LOCATION="$2"
                shift 2
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
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure CLI version
    local cli_version
    cli_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $cli_version"

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON processing features will be limited."
        log_info "Install jq with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    fi

    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found. Using date-based suffix instead."
        RANDOM_SUFFIX=$(date +%s | tail -c 4)
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi

    log_success "Prerequisites check completed"
}

# Initialize Azure environment
initialize_azure_environment() {
    log_info "Initializing Azure environment..."

    # Get current subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        log_error "Failed to retrieve subscription ID"
        exit 1
    fi

    log_info "Using subscription: $SUBSCRIPTION_ID"
    log_info "Using location: $LOCATION"
    log_info "Random suffix: $RANDOM_SUFFIX"

    log_success "Azure environment initialized"
}

# Install Azure Resource Graph extension
install_resource_graph_extension() {
    log_info "Installing Azure Resource Graph CLI extension..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install resource-graph extension"
        return 0
    fi

    # Check if extension is already installed
    if az extension list --query "[?name=='resource-graph']" --output tsv | grep -q resource-graph; then
        log_info "Resource Graph extension already installed"
        
        # Update to latest version
        log_info "Updating Resource Graph extension to latest version..."
        az extension update --name resource-graph || {
            log_warning "Failed to update extension, continuing with current version"
        }
    else
        # Install the extension
        if az extension add --name resource-graph; then
            log_success "Resource Graph extension installed successfully"
        else
            log_error "Failed to install Resource Graph extension"
            exit 1
        fi
    fi

    # Verify extension installation
    local extension_info
    extension_info=$(az extension list --query "[?name=='resource-graph']" --output table)
    log_info "Installed extension details:"
    echo "$extension_info" | tee -a "$LOG_FILE"

    log_success "Resource Graph extension setup completed"
}

# Verify Resource Graph access and connectivity
verify_resource_graph_access() {
    log_info "Verifying Azure Resource Graph access..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify Resource Graph connectivity"
        return 0
    fi

    # Test basic Resource Graph connectivity
    log_info "Testing basic Resource Graph connectivity..."
    if az graph query -q "Resources | limit 5" --output table > /tmp/test_query.out 2>&1; then
        log_success "Resource Graph connectivity verified"
        log_info "Sample resources found:"
        head -10 /tmp/test_query.out | tee -a "$LOG_FILE"
    else
        log_error "Failed to connect to Resource Graph service"
        log_error "Error details:"
        cat /tmp/test_query.out | tee -a "$LOG_FILE"
        exit 1
    fi

    # Display available Resource Graph tables and schema
    log_info "Displaying available Resource Graph schema (first 10 columns)..."
    if az graph query -q "union * | getschema | project ColumnName, ColumnType | order by ColumnName asc" \
        --query "data[0:10]" --output table > /tmp/schema_query.out 2>&1; then
        log_info "Available schema columns:"
        cat /tmp/schema_query.out | tee -a "$LOG_FILE"
    else
        log_warning "Failed to retrieve schema information"
        cat /tmp/schema_query.out | tee -a "$LOG_FILE"
    fi

    # Clean up temporary files
    rm -f /tmp/test_query.out /tmp/schema_query.out

    log_success "Resource Graph access verification completed"
}

# Execute basic resource inventory query
execute_basic_inventory_query() {
    log_info "Executing basic resource inventory query..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute basic resource inventory query"
        return 0
    fi

    # Execute comprehensive resource inventory query
    log_info "Generating comprehensive resource inventory (first 50 resources)..."
    
    local basic_query="Resources
    | project name, type, location, resourceGroup, subscriptionId
    | order by type asc, name asc
    | limit 50"

    if az graph query -q "$basic_query" --output table > /tmp/basic_inventory.out 2>&1; then
        log_success "Basic resource inventory query executed successfully"
        log_info "Basic inventory results:"
        cat /tmp/basic_inventory.out | tee -a "$LOG_FILE"
    else
        log_error "Failed to execute basic inventory query"
        cat /tmp/basic_inventory.out | tee -a "$LOG_FILE"
        exit 1
    fi

    rm -f /tmp/basic_inventory.out
    log_success "Basic resource inventory query completed"
}

# Generate resource count by type report
generate_resource_type_report() {
    log_info "Generating resource count by type report..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate resource type distribution report"
        return 0
    fi

    # Create resource type summary report
    log_info "Creating resource type summary report..."
    
    local type_summary_query="Resources
    | summarize count() by type
    | order by count_ desc"

    if az graph query -q "$type_summary_query" --output table > /tmp/type_summary.out 2>&1; then
        log_success "Resource type summary report generated"
        log_info "Resource type distribution:"
        cat /tmp/type_summary.out | tee -a "$LOG_FILE"
    else
        log_error "Failed to generate resource type summary"
        cat /tmp/type_summary.out | tee -a "$LOG_FILE"
        return 1
    fi

    # Save detailed results for further analysis (if jq is available)
    if command -v jq &> /dev/null; then
        log_info "Saving detailed resource counts for analysis..."
        
        local detailed_query="Resources
        | summarize ResourceCount=count() by ResourceType=type
        | order by ResourceCount desc"

        if RESOURCE_COUNTS=$(az graph query -q "$detailed_query" --output json); then
            local type_count
            type_count=$(echo "$RESOURCE_COUNTS" | jq '.data | length' 2>/dev/null || echo "unknown")
            log_success "Resource type distribution report generated"
            log_info "Total unique resource types found: $type_count"
        else
            log_warning "Failed to save detailed resource counts"
        fi
    fi

    rm -f /tmp/type_summary.out
    log_success "Resource type report generation completed"
}

# Create location-based distribution report
create_location_distribution_report() {
    log_info "Creating location-based distribution report..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create location-based distribution report"
        return 0
    fi

    # Generate resource distribution by location
    log_info "Generating resource distribution by location..."
    
    local location_query="Resources
    | where location != ''
    | summarize ResourceCount=count() by Location=location
    | order by ResourceCount desc"

    if az graph query -q "$location_query" --output table > /tmp/location_dist.out 2>&1; then
        log_success "Location-based distribution report generated"
        log_info "Resource distribution by location:"
        cat /tmp/location_dist.out | tee -a "$LOG_FILE"
    else
        log_error "Failed to generate location distribution report"
        cat /tmp/location_dist.out | tee -a "$LOG_FILE"
        return 1
    fi

    # Create detailed location analysis with resource types
    log_info "Creating detailed location analysis with resource types (top 20)..."
    
    local detailed_location_query="Resources
    | where location != ''
    | summarize count() by location, type
    | order by location asc, count_ desc"

    if az graph query -q "$detailed_location_query" --query "data[0:20]" --output table > /tmp/location_detail.out 2>&1; then
        log_info "Detailed location analysis (top 20 results):"
        cat /tmp/location_detail.out | tee -a "$LOG_FILE"
    else
        log_warning "Failed to generate detailed location analysis"
        cat /tmp/location_detail.out | tee -a "$LOG_FILE"
    fi

    rm -f /tmp/location_dist.out /tmp/location_detail.out
    log_success "Location-based distribution report completed"
}

# Generate compliance and tagging report
generate_compliance_tagging_report() {
    log_info "Generating compliance and tagging report..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate compliance and tagging report"
        return 0
    fi

    # Analyze resource tagging compliance
    log_info "Analyzing resource tagging compliance..."
    
    local tagging_compliance_query="Resources
    | extend TagCount = array_length(todynamic(tags))
    | extend HasTags = case(TagCount > 0, 'Tagged', 'Untagged')
    | summarize count() by HasTags, type
    | order by type asc"

    if az graph query -q "$tagging_compliance_query" --output table > /tmp/tagging_compliance.out 2>&1; then
        log_success "Resource tagging compliance analysis completed"
        log_info "Tagging compliance by resource type:"
        cat /tmp/tagging_compliance.out | tee -a "$LOG_FILE"
    else
        log_error "Failed to analyze tagging compliance"
        cat /tmp/tagging_compliance.out | tee -a "$LOG_FILE"
        return 1
    fi

    # Identify resources missing critical tags
    log_info "Identifying resources missing critical tags (Environment or Owner)..."
    
    local missing_tags_query="Resources
    | where tags !has 'Environment' or tags !has 'Owner'
    | project name, type, resourceGroup, location, tags
    | limit 20"

    if az graph query -q "$missing_tags_query" --output table > /tmp/missing_tags.out 2>&1; then
        log_info "Resources missing critical tags (first 20):"
        cat /tmp/missing_tags.out | tee -a "$LOG_FILE"
    else
        log_warning "Failed to identify resources with missing tags"
        cat /tmp/missing_tags.out | tee -a "$LOG_FILE"
    fi

    rm -f /tmp/tagging_compliance.out /tmp/missing_tags.out
    log_success "Compliance and tagging report completed"
}

# Export comprehensive inventory report
export_comprehensive_inventory() {
    log_info "Exporting comprehensive inventory report..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would export comprehensive inventory to infrastructure-inventory-$(date +%Y%m%d).json"
        return 0
    fi

    # Define comprehensive inventory query
    INVENTORY_QUERY="Resources
    | project 
        ResourceName=name,
        ResourceType=type,
        Location=location,
        ResourceGroup=resourceGroup,
        SubscriptionId=subscriptionId,
        Tags=tags,
        ResourceId=id,
        Kind=kind
    | order by ResourceType asc, ResourceName asc"

    local export_file="infrastructure-inventory-$(date +%Y%m%d).json"
    
    # Execute query and save results
    log_info "Executing comprehensive inventory query and saving to $export_file..."
    
    if az graph query -q "$INVENTORY_QUERY" --output json > "$export_file" 2>/tmp/export_error.log; then
        log_success "Comprehensive inventory report exported to $export_file"
        
        # Display file size and record count if jq is available
        if command -v jq &> /dev/null && [[ -f "$export_file" ]]; then
            local record_count
            record_count=$(jq '.data | length' "$export_file" 2>/dev/null || echo "unknown")
            local file_size
            file_size=$(ls -lh "$export_file" | awk '{print $5}')
            log_info "Export file contains $record_count resources ($file_size)"
        fi
    else
        log_error "Failed to export comprehensive inventory"
        cat /tmp/export_error.log | tee -a "$LOG_FILE"
        return 1
    fi

    # Generate summary statistics
    log_info "Generating summary statistics..."
    
    local summary_query="Resources
    | summarize 
        TotalResources=count(),
        UniqueTypes=dcount(type),
        UniqueLocations=dcount(location),
        TaggedResources=countif(array_length(todynamic(tags)) > 0)"

    if az graph query -q "$summary_query" --output table > /tmp/summary_stats.out 2>&1; then
        log_info "Infrastructure summary statistics:"
        cat /tmp/summary_stats.out | tee -a "$LOG_FILE"
    else
        log_warning "Failed to generate summary statistics"
        cat /tmp/summary_stats.out | tee -a "$LOG_FILE"
    fi

    rm -f /tmp/export_error.log /tmp/summary_stats.out
    log_success "Comprehensive inventory export completed"
}

# Validate deployment
validate_deployment() {
    log_info "Validating inventory deployment..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate inventory queries and exports"
        return 0
    fi

    # Validate total resource count
    log_info "Validating total resource count..."
    
    if TOTAL_RESOURCES=$(az graph query -q "Resources | count" --query "data[0].count_" --output tsv 2>/dev/null); then
        log_success "Total resources discovered: $TOTAL_RESOURCES"
    else
        log_error "Failed to validate resource count"
        return 1
    fi

    # Verify subscription coverage
    log_info "Verifying subscription coverage..."
    
    local subscription_query="Resources
    | distinct subscriptionId
    | join kind=inner (ResourceContainers | where type == 'microsoft.resources/subscriptions')
        on \$left.subscriptionId == \$right.subscriptionId
    | project subscriptionId, SubscriptionName=name"

    if az graph query -q "$subscription_query" --output table > /tmp/subscription_coverage.out 2>&1; then
        log_info "Subscription coverage verification:"
        cat /tmp/subscription_coverage.out | tee -a "$LOG_FILE"
    else
        log_warning "Failed to verify subscription coverage"
        cat /tmp/subscription_coverage.out | tee -a "$LOG_FILE"
    fi

    # Test export functionality if file exists
    local export_file="infrastructure-inventory-$(date +%Y%m%d).json"
    if [[ -f "$export_file" ]]; then
        log_info "Validating exported inventory file..."
        
        if command -v jq &> /dev/null; then
            local exported_count
            exported_count=$(jq '.data | length' "$export_file" 2>/dev/null || echo "0")
            if [[ "$exported_count" -gt 0 ]]; then
                log_success "Successfully exported $exported_count resources to JSON file"
            else
                log_warning "Export file exists but contains no data"
            fi
        else
            if [[ -s "$export_file" ]]; then
                log_success "Export file created and contains data"
            else
                log_warning "Export file exists but appears to be empty"
            fi
        fi
    else
        log_warning "Export file $export_file not found"
    fi

    # Test query performance
    log_info "Testing query performance..."
    if time az graph query -q "Resources | count" --output json > /tmp/perf_test.out 2>&1; then
        log_info "Performance test completed successfully"
    else
        log_warning "Performance test failed"
        cat /tmp/perf_test.out | tee -a "$LOG_FILE"
    fi

    rm -f /tmp/subscription_coverage.out /tmp/perf_test.out
    log_success "Validation completed"
}

# Display deployment summary
display_summary() {
    log_info "=== Azure Resource Graph Inventory Deployment Summary ==="
    
    echo "Deployment Details:" | tee -a "$LOG_FILE"
    echo "  - Timestamp: $TIMESTAMP" | tee -a "$LOG_FILE"
    echo "  - Subscription ID: $SUBSCRIPTION_ID" | tee -a "$LOG_FILE"
    echo "  - Location: $LOCATION" | tee -a "$LOG_FILE"
    echo "  - Dry Run: $DRY_RUN" | tee -a "$LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Completed Operations:" | tee -a "$LOG_FILE"
        echo "  ✅ Azure Resource Graph extension installed/updated" | tee -a "$LOG_FILE"
        echo "  ✅ Resource Graph connectivity verified" | tee -a "$LOG_FILE"
        echo "  ✅ Basic resource inventory query executed" | tee -a "$LOG_FILE"
        echo "  ✅ Resource type distribution report generated" | tee -a "$LOG_FILE"
        echo "  ✅ Location-based distribution report created" | tee -a "$LOG_FILE"
        echo "  ✅ Compliance and tagging analysis completed" | tee -a "$LOG_FILE"
        echo "  ✅ Comprehensive inventory exported" | tee -a "$LOG_FILE"
        echo "  ✅ Deployment validation performed" | tee -a "$LOG_FILE"
        
        if [[ -n "$TOTAL_RESOURCES" ]]; then
            echo "  📊 Total resources discovered: $TOTAL_RESOURCES" | tee -a "$LOG_FILE"
        fi
        
        local export_file="infrastructure-inventory-$(date +%Y%m%d).json"
        if [[ -f "$export_file" ]]; then
            echo "  📄 Inventory exported to: $export_file" | tee -a "$LOG_FILE"
        fi
    fi
    
    echo "" | tee -a "$LOG_FILE"
    echo "Next Steps:" | tee -a "$LOG_FILE"
    echo "  1. Review the generated inventory reports" | tee -a "$LOG_FILE"
    echo "  2. Analyze tagging compliance and remediate missing tags" | tee -a "$LOG_FILE"
    echo "  3. Use exported JSON data for further analysis or integration" | tee -a "$LOG_FILE"
    echo "  4. Set up regular inventory reporting schedules" | tee -a "$LOG_FILE"
    echo "  5. Implement governance policies based on findings" | tee -a "$LOG_FILE"
    
    echo "" | tee -a "$LOG_FILE"
    echo "Useful Commands:" | tee -a "$LOG_FILE"
    echo "  - View all resource types: az graph query -q 'Resources | distinct type | sort by type asc'" | tee -a "$LOG_FILE"
    echo "  - Check untagged resources: az graph query -q 'Resources | where tags == \"{}\" | count'" | tee -a "$LOG_FILE"
    echo "  - Location summary: az graph query -q 'Resources | summarize count() by location'" | tee -a "$LOG_FILE"
    
    log_success "Azure Resource Graph inventory deployment completed successfully!"
    log_info "Log file: $LOG_FILE"
}

# Main deployment function
main() {
    log_info "Starting Azure Resource Graph inventory deployment..."
    log_info "Script: $SCRIPT_NAME"
    log_info "Version: 1.0"
    log_info "Timestamp: $TIMESTAMP"
    
    parse_arguments "$@"
    check_prerequisites
    initialize_azure_environment
    install_resource_graph_extension
    verify_resource_graph_access
    execute_basic_inventory_query
    generate_resource_type_report
    create_location_distribution_report
    generate_compliance_tagging_report
    export_comprehensive_inventory
    validate_deployment
    display_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi