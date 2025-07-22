#!/bin/bash

# Azure Virtual Desktop with Azure Bastion Deployment Script
# This script deploys a secure multi-session virtual desktop infrastructure
# with Azure Virtual Desktop and Azure Bastion for secure administrative access

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log ERROR "Script failed at line $line_number with exit code $exit_code"
    log ERROR "Check the log file: $LOG_FILE"
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Virtual Desktop with Azure Bastion infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -y, --yes              Skip confirmation prompts
    -r, --region REGION    Azure region (default: eastus)
    -s, --suffix SUFFIX    Resource name suffix (default: random)
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0                     # Interactive deployment
    $0 -d                  # Dry run to see what would be deployed
    $0 -y -r westus2       # Deploy to westus2 without confirmation
    $0 -s prod             # Deploy with 'prod' suffix

ENVIRONMENT VARIABLES:
    DRY_RUN               Set to 'true' for dry run mode
    SKIP_CONFIRMATION     Set to 'true' to skip prompts
    AZURE_REGION          Default Azure region
    RESOURCE_SUFFIX       Default resource suffix

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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -r|--region)
                AZURE_REGION="$2"
                shift 2
                ;;
            -s|--suffix)
                RESOURCE_SUFFIX="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it first."
        log INFO "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log INFO "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check subscription
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log INFO "Using subscription: $subscription_name ($subscription_id)"
    
    # Check required tools
    local required_tools=("openssl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log ERROR "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check Azure resource providers
    log INFO "Checking Azure resource providers..."
    local providers=("Microsoft.DesktopVirtualization" "Microsoft.Network" "Microsoft.Compute" "Microsoft.KeyVault")
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$status" != "Registered" ]]; then
            log WARN "Provider $provider is not registered. Registering..."
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done
    
    log INFO "Prerequisites check completed successfully"
}

# Set environment variables
set_environment_variables() {
    log INFO "Setting environment variables..."
    
    # Set defaults
    export LOCATION="${AZURE_REGION:-eastus}"
    local suffix="${RESOURCE_SUFFIX:-$(openssl rand -hex 3)}"
    
    # Core resource names
    export RESOURCE_GROUP="rg-avd-infra-${suffix}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Network resources
    export VNET_NAME="vnet-avd-${suffix}"
    export AVD_SUBNET_NAME="subnet-avd-hosts"
    export BASTION_SUBNET_NAME="AzureBastionSubnet"
    
    # AVD resources
    export HOSTPOOL_NAME="hp-multi-session-${suffix}"
    export WORKSPACE_NAME="ws-remote-desktop-${suffix}"
    export APPGROUP_NAME="ag-desktop-${suffix}"
    export KEYVAULT_NAME="kv-avd-${suffix}"
    
    # VM configuration
    export VM_SIZE="Standard_D4s_v3"
    export VM_ADMIN_USERNAME="avdadmin"
    
    # Log all environment variables
    log DEBUG "Environment variables set:"
    log DEBUG "  LOCATION: $LOCATION"
    log DEBUG "  RESOURCE_GROUP: $RESOURCE_GROUP"
    log DEBUG "  VNET_NAME: $VNET_NAME"
    log DEBUG "  HOSTPOOL_NAME: $HOSTPOOL_NAME"
    log DEBUG "  WORKSPACE_NAME: $WORKSPACE_NAME"
    log DEBUG "  KEYVAULT_NAME: $KEYVAULT_NAME"
}

# Execute Azure CLI command with dry run support
execute_az_command() {
    local description="$1"
    shift
    local command=("$@")
    
    log INFO "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "DRY RUN: az ${command[*]}"
        return 0
    fi
    
    log DEBUG "Executing: az ${command[*]}"
    az "${command[@]}" || {
        log ERROR "Failed to execute: az ${command[*]}"
        return 1
    }
}

# Wait for resource to be ready
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_attempts="${4:-30}"
    local sleep_interval="${5:-30}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "DRY RUN: Would wait for $resource_type $resource_name"
        return 0
    fi
    
    log INFO "Waiting for $resource_type '$resource_name' to be ready..."
    
    for ((i=1; i<=max_attempts; i++)); do
        local status=""
        case "$resource_type" in
            "vm")
                status=$(az vm show --name "$resource_name" --resource-group "$resource_group" \
                    --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
                ;;
            "bastion")
                status=$(az network bastion show --name "$resource_name" --resource-group "$resource_group" \
                    --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
                ;;
            "hostpool")
                status=$(az desktopvirtualization hostpool show --name "$resource_name" --resource-group "$resource_group" \
                    --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
                ;;
        esac
        
        if [[ "$status" == "Succeeded" ]]; then
            log INFO "$resource_type '$resource_name' is ready"
            return 0
        fi
        
        log DEBUG "Attempt $i/$max_attempts: $resource_type status is '$status'"
        sleep "$sleep_interval"
    done
    
    log ERROR "$resource_type '$resource_name' failed to become ready within expected time"
    return 1
}

# Create resource group
create_resource_group() {
    log INFO "Creating resource group..."
    
    execute_az_command "Creating resource group $RESOURCE_GROUP" \
        group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=virtual-desktop environment=production deployment=automated
    
    log INFO "✅ Resource group created: $RESOURCE_GROUP"
}

# Create Key Vault
create_key_vault() {
    log INFO "Creating Azure Key Vault..."
    
    execute_az_command "Creating Key Vault $KEYVAULT_NAME" \
        keyvault create \
        --name "$KEYVAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-rbac-authorization true \
        --tags component=security purpose=certificate-management
    
    log INFO "✅ Key Vault created: $KEYVAULT_NAME"
}

# Create virtual network infrastructure
create_network_infrastructure() {
    log INFO "Creating virtual network infrastructure..."
    
    # Create virtual network with AVD subnet
    execute_az_command "Creating virtual network $VNET_NAME" \
        network vnet create \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefixes "10.0.0.0/16" \
        --subnet-name "$AVD_SUBNET_NAME" \
        --subnet-prefixes "10.0.1.0/24" \
        --tags component=networking purpose=virtual-desktop
    
    # Create Bastion subnet
    execute_az_command "Creating Bastion subnet" \
        network vnet subnet create \
        --name "$BASTION_SUBNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefixes "10.0.2.0/27"
    
    log INFO "✅ Virtual network infrastructure created"
}

# Configure network security groups
configure_network_security() {
    log INFO "Configuring network security groups..."
    
    # Create NSG for AVD subnet
    execute_az_command "Creating NSG for AVD hosts" \
        network nsg create \
        --name "nsg-avd-hosts" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags component=security purpose=network-filtering
    
    # Allow Azure Virtual Desktop service traffic
    execute_az_command "Adding AVD service traffic rule" \
        network nsg rule create \
        --name "AllowAVDServiceTraffic" \
        --nsg-name "nsg-avd-hosts" \
        --resource-group "$RESOURCE_GROUP" \
        --priority 1000 \
        --access Allow \
        --direction Outbound \
        --protocol Tcp \
        --destination-port-ranges 443 \
        --destination-address-prefixes "WindowsVirtualDesktop"
    
    # Allow Azure Bastion communication
    execute_az_command "Adding Bastion inbound rule" \
        network nsg rule create \
        --name "AllowBastionInbound" \
        --nsg-name "nsg-avd-hosts" \
        --resource-group "$RESOURCE_GROUP" \
        --priority 1100 \
        --access Allow \
        --direction Inbound \
        --protocol Tcp \
        --source-address-prefixes "10.0.2.0/27" \
        --destination-port-ranges 3389 22
    
    # Associate NSG with AVD subnet
    execute_az_command "Associating NSG with AVD subnet" \
        network vnet subnet update \
        --name "$AVD_SUBNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --network-security-group "nsg-avd-hosts"
    
    log INFO "✅ Network security groups configured"
}

# Deploy Azure Bastion
deploy_azure_bastion() {
    log INFO "Deploying Azure Bastion..."
    
    local bastion_name="bastion-avd-$(echo $RESOURCE_GROUP | cut -d'-' -f4)"
    local pip_name="pip-bastion-$(echo $RESOURCE_GROUP | cut -d'-' -f4)"
    
    # Create public IP for Azure Bastion
    execute_az_command "Creating public IP for Bastion" \
        network public-ip create \
        --name "$pip_name" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --allocation-method Static \
        --sku Standard \
        --tags component=networking purpose=bastion-access
    
    # Deploy Azure Bastion
    execute_az_command "Deploying Azure Bastion" \
        network bastion create \
        --name "$bastion_name" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet-name "$VNET_NAME" \
        --public-ip-address "$pip_name" \
        --sku Basic \
        --tags component=security purpose=secure-access
    
    wait_for_resource "bastion" "$bastion_name" "$RESOURCE_GROUP"
    
    log INFO "✅ Azure Bastion deployed successfully"
}

# Create AVD host pool
create_avd_hostpool() {
    log INFO "Creating Azure Virtual Desktop host pool..."
    
    execute_az_command "Creating AVD host pool $HOSTPOOL_NAME" \
        desktopvirtualization hostpool create \
        --name "$HOSTPOOL_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --host-pool-type Pooled \
        --load-balancer-type BreadthFirst \
        --max-session-limit 10 \
        --preferred-app-group-type Desktop \
        --start-vm-on-connect false \
        --tags component=virtual-desktop purpose=multi-session
    
    wait_for_resource "hostpool" "$HOSTPOOL_NAME" "$RESOURCE_GROUP"
    
    # Get registration token
    if [[ "$DRY_RUN" == "false" ]]; then
        export REGISTRATION_TOKEN=$(az desktopvirtualization hostpool \
            retrieve-registration-token \
            --name "$HOSTPOOL_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query token --output tsv)
        log DEBUG "Registration token obtained"
    fi
    
    log INFO "✅ Host pool created: $HOSTPOOL_NAME"
}

# Deploy session host VMs
deploy_session_hosts() {
    log INFO "Deploying session host virtual machines..."
    
    local vm_password=$(openssl rand -base64 32)
    
    # Deploy first session host
    local vm1_name="vm-avd-host-01-$(echo $RESOURCE_GROUP | cut -d'-' -f4)"
    execute_az_command "Creating first session host VM" \
        vm create \
        --name "$vm1_name" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --image "MicrosoftWindowsDesktop:Windows-11:win11-22h2-ent:latest" \
        --size "$VM_SIZE" \
        --admin-username "$VM_ADMIN_USERNAME" \
        --admin-password "$vm_password" \
        --vnet-name "$VNET_NAME" \
        --subnet "$AVD_SUBNET_NAME" \
        --nsg "nsg-avd-hosts" \
        --public-ip-address "" \
        --tags component=session-host purpose=multi-session-desktop
    
    # Deploy second session host
    local vm2_name="vm-avd-host-02-$(echo $RESOURCE_GROUP | cut -d'-' -f4)"
    execute_az_command "Creating second session host VM" \
        vm create \
        --name "$vm2_name" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --image "MicrosoftWindowsDesktop:Windows-11:win11-22h2-ent:latest" \
        --size "$VM_SIZE" \
        --admin-username "$VM_ADMIN_USERNAME" \
        --admin-password "$vm_password" \
        --vnet-name "$VNET_NAME" \
        --subnet "$AVD_SUBNET_NAME" \
        --nsg "nsg-avd-hosts" \
        --public-ip-address "" \
        --tags component=session-host purpose=multi-session-desktop
    
    # Wait for VMs to be ready
    wait_for_resource "vm" "$vm1_name" "$RESOURCE_GROUP"
    wait_for_resource "vm" "$vm2_name" "$RESOURCE_GROUP"
    
    # Store VM password in Key Vault
    if [[ "$DRY_RUN" == "false" ]]; then
        az keyvault secret set \
            --vault-name "$KEYVAULT_NAME" \
            --name "avd-admin-password" \
            --value "$vm_password" > /dev/null
        log DEBUG "VM password stored in Key Vault"
    fi
    
    log INFO "✅ Session host VMs created successfully"
}

# Configure session hosts with AVD agent
configure_session_hosts() {
    log INFO "Configuring session hosts with AVD agent..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "DRY RUN: Would install AVD agent on session hosts"
        return 0
    fi
    
    local vm1_name="vm-avd-host-01-$(echo $RESOURCE_GROUP | cut -d'-' -f4)"
    local vm2_name="vm-avd-host-02-$(echo $RESOURCE_GROUP | cut -d'-' -f4)"
    
    # Install AVD agent on first session host
    execute_az_command "Installing AVD agent on first session host" \
        vm extension set \
        --name "Microsoft.Powershell.DSC" \
        --publisher "Microsoft.Powershell" \
        --version "2.77" \
        --vm-name "$vm1_name" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "{\"ModulesUrl\":\"https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02507.240.zip\",\"ConfigurationFunction\":\"Configuration.ps1\\Configuration\",\"Properties\":{\"RegistrationInfoToken\":\"${REGISTRATION_TOKEN}\",\"aadJoin\":false}}"
    
    # Install AVD agent on second session host
    execute_az_command "Installing AVD agent on second session host" \
        vm extension set \
        --name "Microsoft.Powershell.DSC" \
        --publisher "Microsoft.Powershell" \
        --version "2.77" \
        --vm-name "$vm2_name" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "{\"ModulesUrl\":\"https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02507.240.zip\",\"ConfigurationFunction\":\"Configuration.ps1\\Configuration\",\"Properties\":{\"RegistrationInfoToken\":\"${REGISTRATION_TOKEN}\",\"aadJoin\":false}}"
    
    log INFO "✅ AVD agents installed on session hosts"
}

# Create application group and workspace
create_application_group_workspace() {
    log INFO "Creating application group and workspace..."
    
    # Create desktop application group
    execute_az_command "Creating desktop application group" \
        desktopvirtualization applicationgroup create \
        --name "$APPGROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --application-group-type Desktop \
        --host-pool-arm-path "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/hostPools/${HOSTPOOL_NAME}" \
        --tags component=virtual-desktop purpose=application-access
    
    # Create AVD workspace
    execute_az_command "Creating AVD workspace" \
        desktopvirtualization workspace create \
        --name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --application-group-references "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DesktopVirtualization/applicationGroups/${APPGROUP_NAME}" \
        --tags component=virtual-desktop purpose=user-interface
    
    log INFO "✅ Application group and workspace created"
}

# Configure Key Vault integration
configure_key_vault_integration() {
    log INFO "Configuring Azure Key Vault integration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "DRY RUN: Would configure Key Vault certificates and secrets"
        return 0
    fi
    
    # Create certificate for AVD services
    execute_az_command "Creating SSL certificate in Key Vault" \
        keyvault certificate create \
        --vault-name "$KEYVAULT_NAME" \
        --name "avd-ssl-cert" \
        --policy "{\"issuerParameters\":{\"name\":\"Self\"},\"keyProperties\":{\"exportable\":true,\"keySize\":2048,\"keyType\":\"RSA\",\"reuseKey\":false},\"secretProperties\":{\"contentType\":\"application/x-pkcs12\"},\"x509CertificateProperties\":{\"subject\":\"CN=avd-$(echo $RESOURCE_GROUP | cut -d'-' -f4).${LOCATION}.cloudapp.azure.com\",\"validityInMonths\":12}}"
    
    log INFO "✅ Key Vault integration configured"
}

# Display deployment summary
display_deployment_summary() {
    log INFO "Deployment completed successfully! 🎉"
    echo
    echo "==============================================="
    echo "    Azure Virtual Desktop Deployment Summary"
    echo "==============================================="
    echo
    echo "Resource Group:     $RESOURCE_GROUP"
    echo "Location:           $LOCATION"
    echo "Virtual Network:    $VNET_NAME"
    echo "Host Pool:          $HOSTPOOL_NAME"
    echo "Workspace:          $WORKSPACE_NAME"
    echo "Key Vault:          $KEYVAULT_NAME"
    echo
    echo "Next Steps:"
    echo "1. Access Azure portal and navigate to Azure Virtual Desktop"
    echo "2. Assign users to the application group: $APPGROUP_NAME"
    echo "3. Test connectivity using Azure Bastion for administrative access"
    echo "4. Configure user profile containers using FSLogix (optional)"
    echo "5. Set up monitoring and alerting using Azure Monitor"
    echo
    echo "Access URLs:"
    echo "- Azure Portal: https://portal.azure.com"
    echo "- AVD Client: https://rdweb.wvd.microsoft.com/arm/webclient"
    echo
    echo "Documentation:"
    echo "- Azure Virtual Desktop: https://learn.microsoft.com/en-us/azure/virtual-desktop/"
    echo "- Azure Bastion: https://learn.microsoft.com/en-us/azure/bastion/"
    echo
    echo "Log file: $LOG_FILE"
    echo "==============================================="
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "==============================================="
    echo "    Azure Virtual Desktop Deployment Plan"
    echo "==============================================="
    echo
    echo "This script will deploy the following resources:"
    echo "• Resource Group: $RESOURCE_GROUP"
    echo "• Virtual Network with subnets for AVD and Bastion"
    echo "• Network Security Groups with appropriate rules"
    echo "• Azure Bastion for secure administrative access"
    echo "• Azure Key Vault for certificate management"
    echo "• AVD Host Pool for multi-session desktops"
    echo "• 2 Windows 11 Enterprise multi-session VMs"
    echo "• AVD Workspace and Application Group"
    echo
    echo "Estimated deployment time: 30-45 minutes"
    echo "Estimated monthly cost: \$150-300 (varies by region and usage)"
    echo
    echo "Location: $LOCATION"
    echo "VM Size: $VM_SIZE"
    echo
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log INFO "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    log INFO "Starting Azure Virtual Desktop deployment script"
    log INFO "Script location: $SCRIPT_DIR"
    log INFO "Log file: $LOG_FILE"
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Running in DRY RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    set_environment_variables
    confirm_deployment
    
    # Main deployment steps
    create_resource_group
    create_key_vault
    create_network_infrastructure
    configure_network_security
    deploy_azure_bastion
    create_avd_hostpool
    deploy_session_hosts
    configure_session_hosts
    create_application_group_workspace
    configure_key_vault_integration
    
    if [[ "$DRY_RUN" == "false" ]]; then
        display_deployment_summary
    else
        log INFO "DRY RUN completed - no resources were created"
    fi
    
    log INFO "Deployment script completed successfully"
}

# Run main function with all arguments
main "$@"