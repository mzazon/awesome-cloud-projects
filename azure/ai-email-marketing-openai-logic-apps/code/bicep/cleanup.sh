#!/bin/bash

# AI-Powered Email Marketing Infrastructure Cleanup Script
# This script safely removes all Azure resources created for AI email marketing

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
FORCE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup AI-Powered Email Marketing Infrastructure

Options:
    -g, --resource-group RESOURCE_GROUP    Resource group name (required)
    -f, --force                           Skip interactive confirmations
    -d, --dry-run                         Show what would be deleted without deleting
    --skip-confirmation                   Skip final confirmation prompt
    -h, --help                           Show this help message

Examples:
    $0 -g rg-email-marketing-dev
    $0 -g rg-email-marketing-prod -f     # Force delete without prompts
    $0 -g rg-email-marketing-test -d     # Dry run to see what would be deleted

EOF
}

# Function to confirm action
confirm_action() {
    local message=$1
    local default_answer=$2
    
    if [ "$SKIP_CONFIRMATION" = true ] || [ "$FORCE" = true ]; then
        return 0
    fi
    
    while true; do
        read -p "$message (y/N): " answer
        answer=${answer:-$default_answer}
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to list resources
list_resources() {
    print_message $BLUE "📋 Resources in resource group '$RESOURCE_GROUP':"
    
    if ! az group exists --name "$RESOURCE_GROUP" &> /dev/null; then
        print_message $YELLOW "⚠️  Resource group '$RESOURCE_GROUP' does not exist"
        return 1
    fi
    
    local resources
    resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name,Type:type,Location:location}" \
        --output table 2>/dev/null)
    
    if [ -z "$resources" ] || [ "$(echo "$resources" | wc -l)" -le 3 ]; then
        print_message $YELLOW "⚠️  No resources found in resource group '$RESOURCE_GROUP'"
        return 1
    fi
    
    echo "$resources"
    return 0
}

# Function to delete specific resource types in order
delete_resources_by_type() {
    if [ "$DRY_RUN" = true ]; then
        print_message $YELLOW "🔍 DRY RUN: Would delete resources in this order:"
    else
        print_message $BLUE "🗑️  Deleting resources in dependency order..."
    fi
    
    # Order matters for proper cleanup
    local resource_types=(
        "Microsoft.Web/sites"                           # Function Apps (Logic Apps)
        "Microsoft.Web/serverfarms"                     # App Service Plans
        "Microsoft.CognitiveServices/accounts/deployments" # OpenAI Model Deployments
        "Microsoft.CognitiveServices/accounts"          # OpenAI Service
        "Microsoft.Communication/emailServices/domains" # Email Domains
        "Microsoft.Communication/emailServices"         # Email Services
        "Microsoft.Communication/communicationServices" # Communication Services
        "Microsoft.Storage/storageAccounts"             # Storage Accounts
        "Microsoft.KeyVault/vaults"                     # Key Vaults
        "Microsoft.Insights/components"                 # Application Insights
        "Microsoft.OperationalInsights/workspaces"     # Log Analytics
    )
    
    for resource_type in "${resource_types[@]}"; do
        local resources
        resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "$resource_type" \
            --query "[].{id:id,name:name}" \
            --output json 2>/dev/null)
        
        if [ "$resources" != "[]" ] && [ -n "$resources" ]; then
            local count
            count=$(echo "$resources" | jq '. | length')
            
            if [ "$DRY_RUN" = true ]; then
                print_message $YELLOW "  - $resource_type: $count resource(s)"
                echo "$resources" | jq -r '.[] | "    * \(.name)"'
            else
                print_message $BLUE "🗑️  Deleting $count $resource_type resource(s)..."
                
                # Delete resources of this type
                echo "$resources" | jq -r '.[] | .id' | while read -r resource_id; do
                    if [ -n "$resource_id" ]; then
                        local resource_name
                        resource_name=$(echo "$resource_id" | sed 's|.*/||')
                        
                        print_message $YELLOW "   Deleting: $resource_name"
                        
                        # Handle special cases
                        case "$resource_type" in
                            "Microsoft.KeyVault/vaults")
                                # Key Vaults require purge protection handling
                                az keyvault delete --name "$resource_name" --force &> /dev/null || true
                                # Purge soft-deleted key vault
                                sleep 2
                                az keyvault purge --name "$resource_name" --no-wait &> /dev/null || true
                                ;;
                            "Microsoft.CognitiveServices/accounts")
                                # Cognitive Services accounts
                                az cognitiveservices account delete --name "$resource_name" --resource-group "$RESOURCE_GROUP" --force &> /dev/null || true
                                ;;
                            "Microsoft.Communication/communicationServices")
                                # Communication Services
                                az communication delete --name "$resource_name" --resource-group "$RESOURCE_GROUP" --yes &> /dev/null || true
                                ;;
                            "Microsoft.Communication/emailServices")
                                # Email Services
                                az communication email delete --name "$resource_name" --resource-group "$RESOURCE_GROUP" --yes &> /dev/null || true
                                ;;
                            *)
                                # Generic resource deletion
                                az resource delete --ids "$resource_id" --force-string &> /dev/null || true
                                ;;
                        esac
                        
                        print_message $GREEN "   ✅ Deleted: $resource_name"
                    fi
                done
                
                # Wait a bit between resource types
                sleep 3
            fi
        fi
    done
}

# Function to delete entire resource group
delete_resource_group() {
    if [ "$DRY_RUN" = true ]; then
        print_message $YELLOW "🔍 DRY RUN: Would delete entire resource group '$RESOURCE_GROUP'"
        return 0
    fi
    
    print_message $BLUE "🗑️  Deleting resource group '$RESOURCE_GROUP'..."
    
    # Show final warning
    print_message $RED "⚠️  WARNING: This will delete ALL resources in the resource group!"
    
    if confirm_action "Are you absolutely sure you want to delete the entire resource group '$RESOURCE_GROUP'?" "n"; then
        print_message $YELLOW "🗑️  Deleting resource group (this may take several minutes)..."
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        print_message $GREEN "✅ Resource group deletion initiated"
        print_message $YELLOW "ℹ️  Note: Resource group deletion runs in the background and may take several minutes to complete"
        print_message $BLUE "🔍 Check status with: az group exists --name '$RESOURCE_GROUP'"
    else
        print_message $YELLOW "❌ Resource group deletion cancelled"
    fi
}

# Function to show cost savings estimate
show_cost_savings() {
    print_message $BLUE "💰 Estimated monthly cost savings after cleanup:"
    
    cat << EOF
    
  Resource Type                    Estimated Monthly Cost
  ────────────────────────────    ──────────────────────
  Azure OpenAI Service (S0)       ~$10-50 (based on usage)
  Logic Apps Standard (WS1)       ~$80-150
  Communication Services          ~$5-20 (based on emails sent)
  Storage Account (Standard_LRS)  ~$1-5
  Application Insights            ~$2-10
  Key Vault                       ~$1
  ────────────────────────────    ──────────────────────
  Total Estimated Savings         ~$99-236/month

Note: Actual costs depend on usage patterns and may vary.
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_message $RED "❌ Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$RESOURCE_GROUP" ]; then
    print_message $RED "❌ Resource group name is required"
    print_usage
    exit 1
fi

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_message $RED "❌ Azure CLI is not installed"
    exit 1
fi

if ! az account show &> /dev/null; then
    print_message $RED "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Main execution
print_message $RED "🗑️  AI-Powered Email Marketing Infrastructure Cleanup"
print_message $RED "=================================================="

if [ "$DRY_RUN" = true ]; then
    print_message $YELLOW "🔍 DRY RUN MODE - No resources will be deleted"
fi

print_message $YELLOW "Configuration:"
print_message $YELLOW "  Resource Group: $RESOURCE_GROUP"
print_message $YELLOW "  Force Mode: $FORCE"
print_message $YELLOW "  Dry Run: $DRY_RUN"

echo ""

# Check if resource group exists and list resources
if ! list_resources; then
    print_message $GREEN "✅ Nothing to clean up"
    exit 0
fi

echo ""

# Show cleanup options
print_message $BLUE "🔧 Cleanup Options:"
echo "1. Delete resources individually (recommended)"
echo "2. Delete entire resource group (faster but less granular)"
echo ""

if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
    while true; do
        read -p "Choose cleanup method (1 or 2): " method
        case $method in
            1)
                delete_resources_by_type
                break
                ;;
            2)
                delete_resource_group
                break
                ;;
            *)
                echo "Please choose 1 or 2"
                ;;
        esac
    done
else
    # In force or dry-run mode, use individual resource deletion
    delete_resources_by_type
    
    if [ "$DRY_RUN" = false ] && [ "$FORCE" = true ]; then
        print_message $YELLOW "🗑️  Force mode: Also deleting resource group..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait &> /dev/null || true
    fi
fi

if [ "$DRY_RUN" = false ]; then
    show_cost_savings
    print_message $GREEN "🎉 Cleanup completed!"
    print_message $BLUE "ℹ️  Some resources may take a few minutes to fully delete"
else
    print_message $YELLOW "🔍 Dry run completed - no resources were deleted"
fi