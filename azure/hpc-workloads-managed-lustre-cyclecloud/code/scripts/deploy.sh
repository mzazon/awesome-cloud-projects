#!/bin/bash

# =============================================================================
# Azure HPC with Managed Lustre and CycleCloud - Deployment Script
# =============================================================================
# This script deploys the complete Azure HPC environment with:
# - Azure Managed Lustre high-performance file system
# - Azure CycleCloud for HPC cluster orchestration
# - Slurm scheduler with auto-scaling compute nodes
# - Azure Monitor for performance tracking
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Script metadata
SCRIPT_NAME="deploy.sh"
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date +%s)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
        exit 1
    fi
    
    # Check if SSH key generation tools are available
    if ! command -v ssh-keygen &> /dev/null; then
        error "ssh-keygen is not available. Please install OpenSSH client tools."
        exit 1
    fi
    
    # Check if OpenSSL is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not available for random string generation."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not available. Some features may be limited."
    fi
    
    log "Prerequisites check completed successfully"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set primary environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-hpc-lustre-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-East US}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set HPC-specific variables
    export LUSTRE_NAME="${LUSTRE_NAME:-lustre-hpc-${RANDOM_SUFFIX}}"
    export CYCLECLOUD_NAME="${CYCLECLOUD_NAME:-cc-hpc-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-sthpc${RANDOM_SUFFIX}}"
    export VNET_NAME="${VNET_NAME:-vnet-hpc-${RANDOM_SUFFIX}}"
    export SSH_KEY_NAME="${SSH_KEY_NAME:-hpc-ssh-key}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-hpc-${RANDOM_SUFFIX}}"
    
    # Display configuration
    info "Deployment Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription ID: $SUBSCRIPTION_ID"
    info "  Lustre Name: $LUSTRE_NAME"
    info "  CycleCloud Name: $CYCLECLOUD_NAME"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Virtual Network: $VNET_NAME"
    
    # Create deployment state directory
    export STATE_DIR="./deployment-state-${RANDOM_SUFFIX}"
    mkdir -p "$STATE_DIR"
    
    # Save environment variables for cleanup script
    cat > "$STATE_DIR/environment.env" << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
LUSTRE_NAME=$LUSTRE_NAME
CYCLECLOUD_NAME=$CYCLECLOUD_NAME
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
VNET_NAME=$VNET_NAME
SSH_KEY_NAME=$SSH_KEY_NAME
LOG_ANALYTICS_WORKSPACE=$LOG_ANALYTICS_WORKSPACE
RANDOM_SUFFIX=$RANDOM_SUFFIX
STATE_DIR=$STATE_DIR
EOF
    
    log "Environment setup completed"
}

# =============================================================================
# SSH Key Generation
# =============================================================================

generate_ssh_keys() {
    log "Generating SSH key pair for cluster authentication..."
    
    # Create SSH directory if it doesn't exist
    mkdir -p ~/.ssh
    
    # Generate SSH key pair if it doesn't exist
    if [[ ! -f ~/.ssh/${SSH_KEY_NAME} ]]; then
        ssh-keygen -t rsa -b 4096 -f ~/.ssh/${SSH_KEY_NAME} -N "" -C "hpc-cluster-key-${RANDOM_SUFFIX}"
        log "SSH key pair generated: ~/.ssh/${SSH_KEY_NAME}"
    else
        warn "SSH key already exists: ~/.ssh/${SSH_KEY_NAME}"
    fi
    
    # Export public key for later use
    export SSH_PUBLIC_KEY=$(cat ~/.ssh/${SSH_KEY_NAME}.pub)
    
    # Save SSH key path to state file
    echo "SSH_KEY_PATH=$HOME/.ssh/${SSH_KEY_NAME}" >> "$STATE_DIR/environment.env"
    
    log "SSH key setup completed"
}

# =============================================================================
# Resource Group Creation
# =============================================================================

create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=hpc-demo environment=production deployment=automated
        
        log "Resource group created successfully"
    fi
}

# =============================================================================
# Storage Account Creation
# =============================================================================

create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account name is available
    local availability=$(az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable -o tsv)
    if [[ "$availability" == "false" ]]; then
        error "Storage account name $STORAGE_ACCOUNT is not available"
        exit 1
    fi
    
    # Create storage account with Data Lake capabilities
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --tags purpose=hpc-demo environment=production
    
    log "Storage account created with Data Lake capabilities"
}

# =============================================================================
# Network Infrastructure
# =============================================================================

create_network_infrastructure() {
    log "Creating high-performance virtual network infrastructure..."
    
    # Create virtual network with dedicated subnets for HPC workloads
    az network vnet create \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name compute-subnet \
        --subnet-prefixes 10.0.1.0/24 \
        --tags purpose=hpc-demo environment=production
    
    # Create dedicated subnet for CycleCloud management
    az network vnet subnet create \
        --name management-subnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefixes 10.0.2.0/24
    
    # Create subnet for storage and file system access
    az network vnet subnet create \
        --name storage-subnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefixes 10.0.3.0/24
    
    log "HPC network infrastructure configured with optimized subnets"
}

# =============================================================================
# Azure Managed Lustre Deployment
# =============================================================================

deploy_lustre_filesystem() {
    log "Deploying Azure Managed Lustre file system..."
    
    # Install Azure Managed Lustre CLI extension
    if ! az extension list | grep -q "amlfs"; then
        log "Installing Azure Managed Lustre CLI extension..."
        az extension add --name amlfs
    fi
    
    # Get storage subnet ID
    local storage_subnet_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/storage-subnet"
    
    # Create Azure Managed Lustre file system with high-performance configuration
    az amlfs create \
        --name "$LUSTRE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --file-system-type "Durable" \
        --storage-type "SSD" \
        --throughput-per-unit-mb 1000 \
        --storage-capacity-tib 4 \
        --subnet-id "$storage_subnet_id" \
        --tags purpose=hpc-demo environment=production
    
    log "Lustre file system creation initiated..."
    
    # Wait for Lustre file system provisioning to complete
    log "Waiting for Lustre file system provisioning to complete (this may take 10-15 minutes)..."
    az amlfs wait \
        --name "$LUSTRE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --created \
        --timeout 1800  # 30 minutes timeout
    
    # Get Lustre mount information
    local lustre_mount_ip=$(az amlfs show \
        --name "$LUSTRE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "mountCommand" \
        --output tsv | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+')
    
    # Save Lustre mount information to state file
    echo "LUSTRE_MOUNT_IP=$lustre_mount_ip" >> "$STATE_DIR/environment.env"
    
    log "Azure Managed Lustre file system provisioned successfully"
    log "Lustre mount IP: $lustre_mount_ip"
}

# =============================================================================
# CycleCloud Deployment
# =============================================================================

deploy_cyclecloud() {
    log "Deploying Azure CycleCloud server..."
    
    # Get management subnet ID
    local management_subnet_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/management-subnet"
    
    # Create CycleCloud management VM with optimized configuration
    az vm create \
        --name "$CYCLECLOUD_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --image "microsoft-ads:azure-cyclecloud:cyclecloud81:8.1.0" \
        --size Standard_D4s_v3 \
        --subnet "$management_subnet_id" \
        --admin-username azureuser \
        --ssh-key-values "$SSH_PUBLIC_KEY" \
        --storage-sku Premium_LRS \
        --os-disk-size-gb 128 \
        --tags purpose=hpc-demo environment=production
    
    # Wait for VM to be ready
    log "Waiting for CycleCloud VM to be ready..."
    az vm wait --name "$CYCLECLOUD_NAME" --resource-group "$RESOURCE_GROUP" --created
    
    # Get CycleCloud VM public IP
    local cyclecloud_ip=$(az vm show \
        --name "$CYCLECLOUD_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --show-details \
        --query publicIps \
        --output tsv)
    
    # Save CycleCloud IP to state file
    echo "CYCLECLOUD_IP=$cyclecloud_ip" >> "$STATE_DIR/environment.env"
    
    log "CycleCloud server deployed successfully"
    log "CycleCloud IP: $cyclecloud_ip"
    log "Access CycleCloud web interface at: https://$cyclecloud_ip"
    
    # Create Lustre mount script for cluster nodes
    create_lustre_mount_script
}

# =============================================================================
# Lustre Mount Script Generation
# =============================================================================

create_lustre_mount_script() {
    log "Creating Lustre mount script for cluster nodes..."
    
    # Get Lustre mount IP from state file
    local lustre_mount_ip=$(grep "LUSTRE_MOUNT_IP=" "$STATE_DIR/environment.env" | cut -d'=' -f2)
    
    # Create CycleCloud cluster initialization script for Lustre mounting
    cat > "$STATE_DIR/lustre-mount-script.sh" << EOF
#!/bin/bash
# Lustre client mount script for CycleCloud nodes
# This script is executed on each compute node during cluster initialization

set -e

# Install Lustre client packages
yum install -y lustre-client

# Create mount point
mkdir -p /mnt/lustre

# Mount Lustre file system
mount -t lustre ${lustre_mount_ip}@tcp:/lustrefs /mnt/lustre

# Add to fstab for persistent mounting
echo "${lustre_mount_ip}@tcp:/lustrefs /mnt/lustre lustre defaults,_netdev 0 0" >> /etc/fstab

# Set appropriate permissions for HPC workloads
chmod 755 /mnt/lustre

# Create test directory
mkdir -p /mnt/lustre/test

echo "Lustre file system mounted successfully on \$(hostname)"
EOF
    
    chmod +x "$STATE_DIR/lustre-mount-script.sh"
    
    log "Lustre mount script created: $STATE_DIR/lustre-mount-script.sh"
}

# =============================================================================
# Azure Monitor Setup
# =============================================================================

setup_monitoring() {
    log "Setting up Azure Monitor for HPC performance tracking..."
    
    # Create Log Analytics workspace for HPC monitoring
    az monitor log-analytics workspace create \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --tags purpose=hpc-demo environment=production
    
    # Get workspace ID for agent configuration
    local workspace_id=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId \
        --output tsv)
    
    # Save workspace ID to state file
    echo "WORKSPACE_ID=$workspace_id" >> "$STATE_DIR/environment.env"
    
    log "Azure Monitor configured for HPC performance tracking"
    log "Log Analytics Workspace ID: $workspace_id"
}

# =============================================================================
# Post-Deployment Configuration
# =============================================================================

post_deployment_configuration() {
    log "Performing post-deployment configuration..."
    
    # Display deployment summary
    info "=== HPC Deployment Summary ==="
    info "Resource Group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    info "Lustre File System: $LUSTRE_NAME"
    info "CycleCloud Server: $CYCLECLOUD_NAME"
    info "Storage Account: $STORAGE_ACCOUNT"
    info "Virtual Network: $VNET_NAME"
    
    # Get CycleCloud IP
    local cyclecloud_ip=$(grep "CYCLECLOUD_IP=" "$STATE_DIR/environment.env" | cut -d'=' -f2)
    
    info "=== Next Steps ==="
    info "1. Access CycleCloud web interface: https://$cyclecloud_ip"
    info "2. Complete CycleCloud initial setup wizard"
    info "3. Configure HPC cluster template with Slurm scheduler"
    info "4. Deploy and start HPC cluster"
    info "5. Submit test workloads to validate functionality"
    
    info "=== Important Files ==="
    info "- SSH Private Key: ~/.ssh/${SSH_KEY_NAME}"
    info "- SSH Public Key: ~/.ssh/${SSH_KEY_NAME}.pub"
    info "- Lustre Mount Script: $STATE_DIR/lustre-mount-script.sh"
    info "- Environment Variables: $STATE_DIR/environment.env"
    
    # Calculate deployment time
    local deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    local deployment_minutes=$((deployment_duration / 60))
    local deployment_seconds=$((deployment_duration % 60))
    
    log "Deployment completed successfully in ${deployment_minutes}m ${deployment_seconds}s"
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Source environment variables if they exist
    if [[ -f "$STATE_DIR/environment.env" ]]; then
        source "$STATE_DIR/environment.env"
    fi
    
    # Delete resource group if it was created
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        warn "Deleting resource group: $RESOURCE_GROUP"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait || true
    fi
    
    # Clean up SSH keys
    if [[ -n "${SSH_KEY_NAME:-}" ]]; then
        rm -f ~/.ssh/${SSH_KEY_NAME}* || true
    fi
    
    # Clean up state directory
    if [[ -n "${STATE_DIR:-}" ]]; then
        rm -rf "$STATE_DIR" || true
    fi
    
    error "Cleanup completed. Please check Azure portal for any remaining resources."
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    log "Starting Azure HPC deployment with Managed Lustre and CycleCloud"
    log "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    generate_ssh_keys
    create_resource_group
    create_storage_account
    create_network_infrastructure
    deploy_lustre_filesystem
    deploy_cyclecloud
    setup_monitoring
    post_deployment_configuration
    
    log "Azure HPC deployment completed successfully!"
    log "State files saved in: $STATE_DIR"
}

# =============================================================================
# Script Execution
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi