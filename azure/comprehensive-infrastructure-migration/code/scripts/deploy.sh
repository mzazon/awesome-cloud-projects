#!/bin/bash

# Azure Infrastructure Migration Workflows - Deployment Script
# Recipe: Comprehensive Infrastructure Migration with Resource Mover and Update Manager
# Description: Deploys Azure Resource Mover, Update Manager, and monitoring infrastructure for cross-region migration

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE" >&2
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}" | tee -a "$LOG_FILE"
    fi
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR
trap 'cleanup_on_exit' EXIT

cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check logs at $LOG_FILE and $ERROR_LOG"
        warn "Run ./destroy.sh to clean up any partially created resources"
    fi
}

# Help function
show_help() {
    cat << EOF
Azure Infrastructure Migration Workflows - Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -s, --source-region     Source region for migration (default: eastus)
    -t, --target-region     Target region for migration (default: westus2)
    -g, --resource-group    Base resource group name (default: auto-generated)
    -n, --dry-run          Validate configuration without creating resources
    -d, --debug            Enable debug logging
    -f, --force            Skip confirmation prompts
    --skip-vm              Skip test VM creation (for existing infrastructure)
    --custom-suffix        Use custom suffix instead of random generation

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 -s eastus -t westus2                    # Deploy with specific regions
    $0 --dry-run                               # Validate without deploying
    $0 --debug --force                         # Deploy with debug logging, no prompts

ESTIMATED COST: $50-150 for testing resources over 2 hours
EOF
}

# Default configuration
SOURCE_REGION="eastus"
TARGET_REGION="westus2"
RESOURCE_GROUP=""
DRY_RUN=false
DEBUG=false
FORCE=false
SKIP_VM=false
CUSTOM_SUFFIX=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--source-region)
            SOURCE_REGION="$2"
            shift 2
            ;;
        -t|--target-region)
            TARGET_REGION="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --skip-vm)
            SKIP_VM=true
            shift
            ;;
        --custom-suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Get subscription info
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if regions are valid
    local valid_regions=$(az account list-locations --query "[].name" -o tsv | tr '\n' ' ')
    if [[ ! " $valid_regions " =~ " $SOURCE_REGION " ]]; then
        error "Invalid source region: $SOURCE_REGION"
        exit 1
    fi
    if [[ ! " $valid_regions " =~ " $TARGET_REGION " ]]; then
        error "Invalid target region: $TARGET_REGION"
        exit 1
    fi
    
    # Check if regions are different
    if [[ "$SOURCE_REGION" == "$TARGET_REGION" ]]; then
        error "Source and target regions must be different"
        exit 1
    fi
    
    # Check required provider registrations
    local required_providers=("Microsoft.Migrate" "Microsoft.Maintenance" "Microsoft.OperationalInsights" "Microsoft.Insights")
    for provider in "${required_providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$status" != "Registered" ]]; then
            warn "Provider $provider is not registered. Registering..."
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait || error "Failed to register provider $provider"
            fi
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Configuration setup
setup_configuration() {
    log "Setting up configuration..."
    
    # Generate unique suffix if not provided
    if [[ -z "$CUSTOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    else
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    fi
    
    # Set resource group name if not provided
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="rg-migration-${RANDOM_SUFFIX}"
    fi
    
    # Export environment variables
    export SOURCE_REGION
    export TARGET_REGION
    export RESOURCE_GROUP
    export RANDOM_SUFFIX
    export MOVE_COLLECTION_NAME="move-collection-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    export LOG_WORKSPACE_NAME="law-migration-${RANDOM_SUFFIX}"
    export MAINTENANCE_CONFIG_NAME="maint-migration-${RANDOM_SUFFIX}"
    
    log "Configuration:"
    log "  Source Region: $SOURCE_REGION"
    log "  Target Region: $TARGET_REGION"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Random Suffix: $RANDOM_SUFFIX"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    
    # Save configuration to file for destroy script
    cat > "${SCRIPT_DIR}/deployment.env" << EOF
SOURCE_REGION="$SOURCE_REGION"
TARGET_REGION="$TARGET_REGION"
RESOURCE_GROUP="$RESOURCE_GROUP"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
MOVE_COLLECTION_NAME="$MOVE_COLLECTION_NAME"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
LOG_WORKSPACE_NAME="$LOG_WORKSPACE_NAME"
MAINTENANCE_CONFIG_NAME="$MAINTENANCE_CONFIG_NAME"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log "Configuration saved to ${SCRIPT_DIR}/deployment.env"
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "This will create Azure resources in your subscription which may incur charges."
    warn "Estimated cost: \$50-150 for testing resources over 2 hours"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
}

# Create resource groups
create_resource_groups() {
    log "Creating resource groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create resource groups: $RESOURCE_GROUP, ${RESOURCE_GROUP}-target"
        return 0
    fi
    
    # Create source region resource group
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$SOURCE_REGION" \
        --tags purpose=migration-demo environment=test created-by=migration-script \
        2>> "$ERROR_LOG" || {
            error "Failed to create source resource group"
            return 1
        }
    
    # Create target region resource group
    az group create \
        --name "${RESOURCE_GROUP}-target" \
        --location "$TARGET_REGION" \
        --tags purpose=migration-target environment=test created-by=migration-script \
        2>> "$ERROR_LOG" || {
            error "Failed to create target resource group"
            return 1
        }
    
    log "✅ Resource groups created successfully"
}

# Create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create Log Analytics workspace: $LOG_WORKSPACE_NAME"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --location "$SOURCE_REGION" \
        --sku pergb2018 \
        --tags purpose=migration-monitoring environment=test \
        2>> "$ERROR_LOG" || {
            error "Failed to create Log Analytics workspace"
            return 1
        }
    
    log "✅ Log Analytics workspace created successfully"
}

# Create test infrastructure
create_test_infrastructure() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log "Skipping test infrastructure creation (--skip-vm flag)"
        return 0
    fi
    
    log "Creating test infrastructure in source region..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create test infrastructure (VNet, NSG, VM)"
        return 0
    fi
    
    # Create virtual network
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name vnet-source \
        --address-prefix 10.0.0.0/16 \
        --subnet-name subnet-default \
        --subnet-prefix 10.0.1.0/24 \
        --location "$SOURCE_REGION" \
        --tags purpose=migration-test environment=test \
        2>> "$ERROR_LOG" || {
            error "Failed to create virtual network"
            return 1
        }
    
    # Create network security group
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name nsg-source \
        --location "$SOURCE_REGION" \
        --tags purpose=migration-test environment=test \
        2>> "$ERROR_LOG" || {
            error "Failed to create network security group"
            return 1
        }
    
    # Create virtual machine
    log "Creating test virtual machine (this may take several minutes)..."
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name vm-source-test \
        --image Ubuntu2204 \
        --size Standard_B2s \
        --vnet-name vnet-source \
        --subnet subnet-default \
        --nsg nsg-source \
        --generate-ssh-keys \
        --location "$SOURCE_REGION" \
        --tags environment=test purpose=migration-source \
        --no-wait \
        2>> "$ERROR_LOG" || {
            error "Failed to create virtual machine"
            return 1
        }
    
    # Wait for VM to be fully provisioned
    log "Waiting for VM to be fully provisioned..."
    az vm wait \
        --resource-group "$RESOURCE_GROUP" \
        --name vm-source-test \
        --created \
        --timeout 600 \
        2>> "$ERROR_LOG" || {
            error "VM creation timed out or failed"
            return 1
        }
    
    log "✅ Test infrastructure created successfully"
}

# Configure Resource Mover
configure_resource_mover() {
    log "Configuring Azure Resource Mover..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure Resource Mover collection: $MOVE_COLLECTION_NAME"
        return 0
    fi
    
    # Install Resource Mover extension if not already installed
    if ! az extension show --name resource-mover &> /dev/null; then
        log "Installing Azure Resource Mover CLI extension..."
        az extension add --name resource-mover 2>> "$ERROR_LOG" || {
            warn "Failed to install resource-mover extension, continuing..."
        }
    fi
    
    # Create move collection
    az resource-mover move-collection create \
        --resource-group "$RESOURCE_GROUP" \
        --move-collection-name "$MOVE_COLLECTION_NAME" \
        --source-region "$SOURCE_REGION" \
        --target-region "$TARGET_REGION" \
        --location "$SOURCE_REGION" \
        --tags purpose=migration-orchestration environment=test \
        2>> "$ERROR_LOG" || {
            error "Failed to create move collection"
            return 1
        }
    
    # Store move collection ID
    MOVE_COLLECTION_ID=$(az resource-mover move-collection show \
        --resource-group "$RESOURCE_GROUP" \
        --move-collection-name "$MOVE_COLLECTION_NAME" \
        --query id --output tsv 2>> "$ERROR_LOG") || {
            error "Failed to get move collection ID"
            return 1
        }
    
    export MOVE_COLLECTION_ID
    echo "MOVE_COLLECTION_ID=\"$MOVE_COLLECTION_ID\"" >> "${SCRIPT_DIR}/deployment.env"
    
    log "✅ Resource Mover configured successfully"
}

# Add resources to move collection
add_resources_to_collection() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log "Skipping resource addition to move collection (--skip-vm flag)"
        return 0
    fi
    
    log "Adding resources to move collection..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would add VM, VNet, and NSG to move collection"
        return 0
    fi
    
    # Get resource IDs
    VM_ID=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name vm-source-test \
        --query id --output tsv 2>> "$ERROR_LOG") || {
            error "Failed to get VM resource ID"
            return 1
        }
    
    VNET_ID=$(az network vnet show \
        --resource-group "$RESOURCE_GROUP" \
        --name vnet-source \
        --query id --output tsv 2>> "$ERROR_LOG") || {
            error "Failed to get VNet resource ID"
            return 1
        }
    
    NSG_ID=$(az network nsg show \
        --resource-group "$RESOURCE_GROUP" \
        --name nsg-source \
        --query id --output tsv 2>> "$ERROR_LOG") || {
            error "Failed to get NSG resource ID"
            return 1
        }
    
    # Add VM to move collection
    az resource-mover move-resource create \
        --resource-group "$RESOURCE_GROUP" \
        --move-collection-name "$MOVE_COLLECTION_NAME" \
        --name vm-source-test \
        --source-id "$VM_ID" \
        --target-resource-group "${RESOURCE_GROUP}-target" \
        2>> "$ERROR_LOG" || {
            error "Failed to add VM to move collection"
            return 1
        }
    
    # Add VNet to move collection
    az resource-mover move-resource create \
        --resource-group "$RESOURCE_GROUP" \
        --move-collection-name "$MOVE_COLLECTION_NAME" \
        --name vnet-source \
        --source-id "$VNET_ID" \
        --target-resource-group "${RESOURCE_GROUP}-target" \
        2>> "$ERROR_LOG" || {
            error "Failed to add VNet to move collection"
            return 1
        }
    
    # Add NSG to move collection
    az resource-mover move-resource create \
        --resource-group "$RESOURCE_GROUP" \
        --move-collection-name "$MOVE_COLLECTION_NAME" \
        --name nsg-source \
        --source-id "$NSG_ID" \
        --target-resource-group "${RESOURCE_GROUP}-target" \
        2>> "$ERROR_LOG" || {
            error "Failed to add NSG to move collection"
            return 1
        }
    
    log "✅ Resources added to move collection successfully"
}

# Configure Update Manager
configure_update_manager() {
    log "Configuring Azure Update Manager..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure Update Manager maintenance configuration"
        return 0
    fi
    
    # Enable dynamic extension installation
    az config set extension.use_dynamic_install=yes_without_prompt 2>> "$ERROR_LOG" || {
        warn "Failed to enable dynamic extension installation"
    }
    
    # Create maintenance configuration
    az maintenance configuration create \
        --resource-group "${RESOURCE_GROUP}-target" \
        --name "$MAINTENANCE_CONFIG_NAME" \
        --location "$TARGET_REGION" \
        --maintenance-scope "InGuestPatch" \
        --maintenance-window-start-date-time "2024-12-15 03:00:00" \
        --maintenance-window-duration "02:00" \
        --maintenance-window-recur-every "1Week" \
        --maintenance-window-days-of-week "Saturday" \
        --maintenance-window-time-zone "UTC" \
        --install-patches-linux-classifications "Critical Security" \
        --install-patches-reboot-setting "IfRequired" \
        2>> "$ERROR_LOG" || {
            error "Failed to create maintenance configuration"
            return 1
        }
    
    # Get maintenance configuration ID
    MAINTENANCE_CONFIG_ID=$(az maintenance configuration show \
        --resource-group "${RESOURCE_GROUP}-target" \
        --name "$MAINTENANCE_CONFIG_NAME" \
        --query id --output tsv 2>> "$ERROR_LOG") || {
            error "Failed to get maintenance configuration ID"
            return 1
        }
    
    export MAINTENANCE_CONFIG_ID
    echo "MAINTENANCE_CONFIG_ID=\"$MAINTENANCE_CONFIG_ID\"" >> "${SCRIPT_DIR}/deployment.env"
    
    log "✅ Update Manager configured successfully"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating migration monitoring dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create Azure Workbook for migration monitoring"
        return 0
    fi
    
    # Create workbook template
    cat > "${SCRIPT_DIR}/migration-workbook.json" << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Infrastructure Migration Dashboard\n\nThis workbook provides comprehensive monitoring for Azure Resource Mover migration workflows and Update Manager compliance status."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureActivity\n| where TimeGenerated > ago(24h)\n| where OperationNameValue contains \"Microsoft.Migrate\"\n| summarize OperationCount = count() by OperationNameValue, ResourceType\n| order by OperationCount desc",
        "size": 0,
        "title": "Migration Operations by Resource Type",
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureActivity\n| where TimeGenerated > ago(7d)\n| where OperationNameValue contains \"Microsoft.Maintenance\"\n| summarize ComplianceCount = count() by ActivityStatusValue\n| order by ComplianceCount desc",
        "size": 0,
        "title": "Update Compliance Status",
        "timeContext": {
          "durationMs": 604800000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    }
  ]
}
EOF
    
    # Deploy the workbook
    az monitor workbook create \
        --resource-group "$RESOURCE_GROUP" \
        --name "migration-monitoring-${RANDOM_SUFFIX}" \
        --display-name "Infrastructure Migration Monitoring" \
        --location "$SOURCE_REGION" \
        --workbook-source-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LOG_WORKSPACE_NAME" \
        --workbook-template-file "${SCRIPT_DIR}/migration-workbook.json" \
        --tags purpose=migration-monitoring environment=test \
        2>> "$ERROR_LOG" || {
            error "Failed to create monitoring workbook"
            return 1
        }
    
    log "✅ Migration monitoring dashboard created successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Validation complete - all configurations are valid"
        return 0
    fi
    
    # Check resource groups
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Source resource group validation failed"
        return 1
    fi
    
    if ! az group show --name "${RESOURCE_GROUP}-target" &> /dev/null; then
        error "Target resource group validation failed"
        return 1
    fi
    
    # Check Log Analytics workspace
    if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
        error "Log Analytics workspace validation failed"
        return 1
    fi
    
    # Check move collection
    if ! az resource-mover move-collection show --resource-group "$RESOURCE_GROUP" --move-collection-name "$MOVE_COLLECTION_NAME" &> /dev/null; then
        error "Move collection validation failed"
        return 1
    fi
    
    # Check maintenance configuration
    if ! az maintenance configuration show --resource-group "${RESOURCE_GROUP}-target" --name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
        error "Maintenance configuration validation failed"
        return 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Generate next steps
generate_next_steps() {
    log "Generating next steps documentation..."
    
    cat > "${SCRIPT_DIR}/next-steps.md" << EOF
# Azure Infrastructure Migration - Next Steps

## Deployment Summary
- **Deployment Date**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Source Region**: $SOURCE_REGION
- **Target Region**: $TARGET_REGION
- **Resource Group**: $RESOURCE_GROUP
- **Move Collection**: $MOVE_COLLECTION_NAME

## Migration Workflow Steps

### 1. Validate Migration Readiness
\`\`\`bash
az resource-mover move-collection validate \\
    --resource-group $RESOURCE_GROUP \\
    --move-collection-name $MOVE_COLLECTION_NAME
\`\`\`

### 2. Prepare Resources for Migration
\`\`\`bash
az resource-mover move-resource prepare \\
    --resource-group $RESOURCE_GROUP \\
    --move-collection-name $MOVE_COLLECTION_NAME \\
    --move-resource-name vm-source-test
\`\`\`

### 3. Initiate Migration
\`\`\`bash
az resource-mover move-resource initiate-move \\
    --resource-group $RESOURCE_GROUP \\
    --move-collection-name $MOVE_COLLECTION_NAME \\
    --move-resource-name vm-source-test
\`\`\`

### 4. Commit Migration
\`\`\`bash
az resource-mover move-resource commit \\
    --resource-group $RESOURCE_GROUP \\
    --move-collection-name $MOVE_COLLECTION_NAME \\
    --move-resource-name vm-source-test
\`\`\`

### 5. Apply Update Management
\`\`\`bash
# Get migrated VM ID
MIGRATED_VM_ID=\$(az vm show \\
    --resource-group ${RESOURCE_GROUP}-target \\
    --name vm-source-test \\
    --query id --output tsv)

# Assign maintenance configuration
az maintenance assignment create \\
    --resource-group ${RESOURCE_GROUP}-target \\
    --assignment-name assignment-$RANDOM_SUFFIX \\
    --maintenance-configuration-id $MAINTENANCE_CONFIG_ID \\
    --resource-id \$MIGRATED_VM_ID
\`\`\`

## Monitoring and Validation

### Check Migration Status
\`\`\`bash
az resource-mover move-collection show \\
    --resource-group $RESOURCE_GROUP \\
    --move-collection-name $MOVE_COLLECTION_NAME \\
    --query "{State:provisioningState, Region:targetRegion}" \\
    --output table
\`\`\`

### View Migration Dashboard
Access the Azure Workbook "Infrastructure Migration Monitoring" in the Azure portal:
https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/microsoft.insights/workbooks/migration-monitoring-$RANDOM_SUFFIX

## Cleanup
To remove all resources created by this deployment:
\`\`\`bash
./destroy.sh
\`\`\`

## Support
- Review deployment logs: $LOG_FILE
- Check error logs: $ERROR_LOG
- Azure Resource Mover documentation: https://docs.microsoft.com/en-us/azure/resource-mover/
- Azure Update Manager documentation: https://docs.microsoft.com/en-us/azure/update-manager/
EOF
    
    log "Next steps documentation saved to ${SCRIPT_DIR}/next-steps.md"
}

# Main deployment function
main() {
    log "Starting Azure Infrastructure Migration Workflows deployment..."
    log "Deployment ID: $(date +%s)-$RANDOM_SUFFIX"
    
    # Initialize logs
    echo "=== Azure Infrastructure Migration Deployment Log ===" > "$LOG_FILE"
    echo "=== Azure Infrastructure Migration Error Log ===" > "$ERROR_LOG"
    
    # Execute deployment steps
    check_prerequisites
    setup_configuration
    confirm_deployment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN MODE - NO RESOURCES WILL BE CREATED ==="
    fi
    
    create_resource_groups
    create_log_analytics
    create_test_infrastructure
    configure_resource_mover
    add_resources_to_collection
    configure_update_manager
    create_monitoring_dashboard
    validate_deployment
    generate_next_steps
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN COMPLETED SUCCESSFULLY ==="
        log "All configurations validated. Run without --dry-run to deploy resources."
    else
        log "🎉 Deployment completed successfully!"
        log ""
        log "Next steps:"
        log "1. Review the migration workflow in: ${SCRIPT_DIR}/next-steps.md"
        log "2. Validate and prepare resources for migration"
        log "3. Execute the migration workflow"
        log "4. Monitor progress in the Azure portal"
        log ""
        log "To clean up resources: ./destroy.sh"
        log "Estimated running cost: \$2-5 per hour"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi