#!/bin/bash

# AI Assistant with Custom Functions - Infrastructure Cleanup Script
# This script safely removes all resources deployed by the Bicep template

set -e  # Exit on any error

# Default values
DEFAULT_RESOURCE_GROUP="rg-ai-assistant-demo"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up AI Assistant infrastructure deployed with Bicep.

OPTIONS:
    -g, --resource-group NAME    Resource group name to delete (default: ${DEFAULT_RESOURCE_GROUP})
    -r, --resources-only         Delete individual resources, keep resource group
    -f, --force                  Skip confirmation prompts
    -l, --list                   List resources without deleting
    -h, --help                   Show this help message

EXAMPLES:
    # List resources in resource group
    $0 --list

    # Delete entire resource group with confirmation
    $0 -g "rg-ai-assistant-demo"

    # Delete only resources, keep resource group
    $0 --resources-only

    # Force delete without confirmation
    $0 --force
EOF
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi

    print_success "Prerequisites check completed"
}

list_resources() {
    print_info "Resources in resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 1
    fi

    # List all resources
    echo ""
    az resource list --resource-group "$RESOURCE_GROUP" --output table

    # Get resource count
    RESOURCE_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)
    echo ""
    print_info "Total resources: $RESOURCE_COUNT"

    # Estimate cost savings (rough calculation)
    if [[ $RESOURCE_COUNT -gt 0 ]]; then
        print_info "💰 Estimated monthly cost savings after deletion: \$20-100+ USD"
        print_info "🕒 Resources may take 5-15 minutes to fully delete"
    fi
}

delete_individual_resources() {
    print_info "Deleting individual resources..."

    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi

    # Get list of resources in reverse order (dependencies)
    local RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name, type:type, id:id}" --output json)
    
    if [[ $(echo "$RESOURCES" | jq '. | length') -eq 0 ]]; then
        print_info "No resources found in resource group"
        return 0
    fi

    # Delete resources by type in order to handle dependencies
    local RESOURCE_TYPES=(
        "Microsoft.Web/sites"
        "Microsoft.Web/serverfarms"
        "Microsoft.CognitiveServices/accounts"
        "Microsoft.KeyVault/vaults"
        "Microsoft.Insights/components"
        "Microsoft.OperationalInsights/workspaces"
        "Microsoft.Storage/storageAccounts"
    )

    for RESOURCE_TYPE in "${RESOURCE_TYPES[@]}"; do
        local RESOURCES_OF_TYPE=$(echo "$RESOURCES" | jq -r ".[] | select(.type==\"$RESOURCE_TYPE\") | .name")
        
        for RESOURCE_NAME in $RESOURCES_OF_TYPE; do
            if [[ -n "$RESOURCE_NAME" ]]; then
                print_info "Deleting $RESOURCE_TYPE: $RESOURCE_NAME"
                
                if az resource delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$RESOURCE_NAME" \
                    --resource-type "$RESOURCE_TYPE" \
                    --output none 2>/dev/null; then
                    print_success "Deleted: $RESOURCE_NAME"
                else
                    print_warning "Failed to delete or resource not found: $RESOURCE_NAME"
                fi
            fi
        done
    done

    # Delete any remaining resources
    local REMAINING=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)
    if [[ $REMAINING -gt 0 ]]; then
        print_warning "$REMAINING resources remain. Attempting bulk deletion..."
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv | \
        while read -r RESOURCE_ID; do
            if [[ -n "$RESOURCE_ID" ]]; then
                az resource delete --ids "$RESOURCE_ID" --output none 2>/dev/null || \
                print_warning "Failed to delete resource: $RESOURCE_ID"
            fi
        done
    fi

    print_success "Individual resource deletion completed"
}

delete_resource_group() {
    print_info "Deleting resource group: $RESOURCE_GROUP"

    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi

    # Show what will be deleted
    print_warning "This will delete ALL resources in the resource group:"
    list_resources

    if [[ "$FORCE_DELETE" != true ]]; then
        echo ""
        print_warning "⚠️  This action cannot be undone!"
        read -p "Are you sure you want to delete the entire resource group '$RESOURCE_GROUP'? (type 'yes' to confirm): " -r
        if [[ ! $REPLY == "yes" ]]; then
            print_info "Deletion cancelled"
            return 0
        fi
    fi

    print_info "Initiating resource group deletion..."
    
    if az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait; then
        print_success "Resource group deletion initiated"
        print_info "Deletion is running in the background and may take several minutes"
        print_info "You can check status with: az group show --name '$RESOURCE_GROUP'"
    else
        print_error "Failed to initiate resource group deletion"
        return 1
    fi
}

verify_cleanup() {
    print_info "Verifying cleanup..."
    
    # Wait a moment for Azure to process
    sleep 5

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        local REMAINING=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)
        if [[ $REMAINING -eq 0 ]]; then
            print_success "All resources successfully deleted"
            
            if [[ "$RESOURCES_ONLY" == true ]]; then
                print_info "Resource group '$RESOURCE_GROUP' is now empty but still exists"
            fi
        else
            print_warning "$REMAINING resources still exist (deletion may be in progress)"
            print_info "Run '$0 --list' to check remaining resources"
        fi
    else
        print_success "Resource group '$RESOURCE_GROUP' has been deleted"
    fi
}

show_cost_impact() {
    cat << EOF

💰 Cost Impact Summary:
- Azure OpenAI Service: No longer incurring token charges
- Azure Functions: No execution or hosting costs
- Storage Account: No storage or transaction fees
- Key Vault: No secret operation charges
- Application Insights: No ingestion or retention costs

📊 Typical savings: \$20-100+ USD per month (depending on usage)

🔒 Data Impact:
- All conversation history deleted
- Assistant configurations removed
- Function code and logs deleted
- Monitoring data purged

EOF
}

# Main script
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -r|--resources-only)
                RESOURCES_ONLY=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -l|--list)
                LIST_ONLY=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
    
    # Print configuration
    print_info "Cleanup Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Mode: $(if [[ "$RESOURCES_ONLY" == true ]]; then echo "Resources only"; else echo "Full resource group"; fi)"
    echo "  Force: $(if [[ "$FORCE_DELETE" == true ]]; then echo "Yes"; else echo "No"; fi)"
    echo ""

    # Run checks
    check_prerequisites

    # Handle different modes
    if [[ "$LIST_ONLY" == true ]]; then
        list_resources
        exit 0
    fi

    # Show resources before deletion
    if ! list_resources; then
        exit 0
    fi

    # Perform cleanup
    if [[ "$RESOURCES_ONLY" == true ]]; then
        delete_individual_resources
    else
        delete_resource_group
    fi

    # Verify cleanup
    verify_cleanup

    # Show cost impact
    show_cost_impact

    print_success "🧹 Cleanup completed!"
}

# Run main function with all arguments
main "$@"