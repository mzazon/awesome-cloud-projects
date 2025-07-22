#!/bin/bash

# Azure Scalable HPC Workload Processing - Deployment Script
# This script deploys Azure Elastic SAN, Azure Batch, and supporting infrastructure
# for high-performance computing workloads

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        echo "[DRY-RUN] Description: $description"
        return 0
    fi
    
    log "$description"
    if eval "$cmd"; then
        success "$description completed"
        return 0
    else
        error "$description failed"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
    fi
    
    # Check if required extensions are installed
    log "Checking Azure CLI extensions..."
    if ! az extension show --name elastic-san &> /dev/null; then
        log "Installing Azure Elastic SAN extension..."
        az extension add --name elastic-san --yes
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-hpc-esan-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with consistent naming convention
    export ESAN_NAME="esan-hpc-${RANDOM_SUFFIX}"
    export BATCH_ACCOUNT="batch-hpc-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="sthpc${RANDOM_SUFFIX}"
    export VNET_NAME="vnet-hpc-${RANDOM_SUFFIX}"
    export SUBNET_NAME="subnet-batch-${RANDOM_SUFFIX}"
    export NSG_NAME="nsg-hpc-${RANDOM_SUFFIX}"
    export WORKSPACE_NAME="law-hpc-${RANDOM_SUFFIX}"
    
    # Validate region availability for Elastic SAN
    log "Validating region availability for Azure Elastic SAN..."
    ESAN_REGIONS=$(az elastic-san list-skus --query "[].locations[]" --output tsv 2>/dev/null || echo "eastus westus2 northeurope")
    if [[ ! $ESAN_REGIONS =~ $LOCATION ]]; then
        warning "Azure Elastic SAN may not be available in $LOCATION. Consider using eastus, westus2, or northeurope"
    fi
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
ESAN_NAME=${ESAN_NAME}
BATCH_ACCOUNT=${BATCH_ACCOUNT}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
VNET_NAME=${VNET_NAME}
SUBNET_NAME=${SUBNET_NAME}
NSG_NAME=${NSG_NAME}
WORKSPACE_NAME=${WORKSPACE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Elastic SAN: ${ESAN_NAME}"
    log "  Batch Account: ${BATCH_ACCOUNT}"
    log "  Storage Account: ${STORAGE_ACCOUNT}"
    
    success "Environment variables set"
}

# Function to create resource group and storage account
create_foundation() {
    log "Creating foundational resources..."
    
    execute_command \
        "az group create --name ${RESOURCE_GROUP} --location ${LOCATION} --tags purpose=hpc environment=demo workload=compute-intensive" \
        "Creating resource group"
    
    execute_command \
        "az storage account create --name ${STORAGE_ACCOUNT} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku Standard_LRS --kind StorageV2 --access-tier Hot --https-only true" \
        "Creating storage account"
    
    # Create container for scripts
    execute_command \
        "az storage container create --name scripts --account-name ${STORAGE_ACCOUNT} --auth-mode login" \
        "Creating scripts container"
    
    success "Foundational resources created"
}

# Function to create virtual network infrastructure
create_network_infrastructure() {
    log "Creating virtual network infrastructure..."
    
    execute_command \
        "az network vnet create --resource-group ${RESOURCE_GROUP} --name ${VNET_NAME} --address-prefix 10.0.0.0/16 --location ${LOCATION} --tags workload=hpc tier=network" \
        "Creating virtual network"
    
    execute_command \
        "az network vnet subnet create --resource-group ${RESOURCE_GROUP} --vnet-name ${VNET_NAME} --name ${SUBNET_NAME} --address-prefix 10.0.1.0/24" \
        "Creating Batch subnet"
    
    execute_command \
        "az network nsg create --resource-group ${RESOURCE_GROUP} --name ${NSG_NAME} --location ${LOCATION}" \
        "Creating network security group"
    
    execute_command \
        "az network nsg rule create --resource-group ${RESOURCE_GROUP} --nsg-name ${NSG_NAME} --name AllowHPCCommunication --protocol Tcp --priority 1000 --source-address-prefix 10.0.0.0/16 --source-port-range '*' --destination-address-prefix 10.0.0.0/16 --destination-port-range 1024-65535 --access Allow --direction Inbound" \
        "Creating HPC communication rule"
    
    execute_command \
        "az network vnet subnet update --resource-group ${RESOURCE_GROUP} --vnet-name ${VNET_NAME} --name ${SUBNET_NAME} --network-security-group ${NSG_NAME}" \
        "Associating NSG with subnet"
    
    success "Network infrastructure created"
}

# Function to create Azure Elastic SAN
create_elastic_san() {
    log "Creating Azure Elastic SAN..."
    
    execute_command \
        "az elastic-san create --resource-group ${RESOURCE_GROUP} --name ${ESAN_NAME} --location ${LOCATION} --base-size-tib 1 --extended-capacity-size-tib 2 --sku '{\"name\":\"Premium_LRS\",\"tier\":\"Premium\"}' --tags workload=hpc storage=shared-performance" \
        "Creating Elastic SAN instance"
    
    execute_command \
        "az elastic-san volume-group create --resource-group ${RESOURCE_GROUP} --elastic-san-name ${ESAN_NAME} --name hpc-volumes --protocol-type iSCSI --network-acls '{\"virtual-network-rules\":[{\"id\":\"/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${SUBNET_NAME}\",\"action\":\"Allow\"}]}'" \
        "Creating volume group"
    
    execute_command \
        "az elastic-san volume create --resource-group ${RESOURCE_GROUP} --elastic-san-name ${ESAN_NAME} --volume-group-name hpc-volumes --name data-input --size-gib 500 --tags purpose=input-data workload=hpc" \
        "Creating data input volume"
    
    execute_command \
        "az elastic-san volume create --resource-group ${RESOURCE_GROUP} --elastic-san-name ${ESAN_NAME} --volume-group-name hpc-volumes --name results-output --size-gib 1000 --tags purpose=output-data workload=hpc" \
        "Creating results output volume"
    
    execute_command \
        "az elastic-san volume create --resource-group ${RESOURCE_GROUP} --elastic-san-name ${ESAN_NAME} --volume-group-name hpc-volumes --name shared-libraries --size-gib 100 --tags purpose=shared-libs workload=hpc" \
        "Creating shared libraries volume"
    
    success "Azure Elastic SAN created"
}

# Function to create Azure Batch account and pool
create_batch_infrastructure() {
    log "Creating Azure Batch infrastructure..."
    
    execute_command \
        "az batch account create --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT} --location ${LOCATION} --storage-account ${STORAGE_ACCOUNT} --tags workload=hpc service=batch" \
        "Creating Batch account"
    
    execute_command \
        "az batch account login --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT}" \
        "Logging in to Batch account"
    
    # Create pool configuration file
    cat > batch-pool-config.json << EOF
{
    "id": "hpc-compute-pool",
    "vmSize": "Standard_HC44rs",
    "virtualMachineConfiguration": {
        "imageReference": {
            "publisher": "canonical",
            "offer": "0001-com-ubuntu-server-focal",
            "sku": "20_04-lts",
            "version": "latest"
        },
        "nodeAgentSkuId": "batch.node.ubuntu 20.04"
    },
    "targetDedicatedNodes": 2,
    "maxTasksPerNode": 1,
    "enableInterNodeCommunication": true,
    "networkConfiguration": {
        "subnetId": "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${SUBNET_NAME}"
    },
    "startTask": {
        "commandLine": "apt-get update && apt-get install -y open-iscsi multipath-tools python3-pip && pip3 install numpy",
        "waitForSuccess": true,
        "userIdentity": {
            "autoUser": {
                "scope": "pool",
                "elevationLevel": "admin"
            }
        }
    },
    "userAccounts": [
        {
            "name": "hpcuser",
            "password": "HPC@Pass123!",
            "elevationLevel": "admin"
        }
    ]
}
EOF
    
    execute_command \
        "az batch pool create --json-file batch-pool-config.json" \
        "Creating HPC compute pool"
    
    success "Batch infrastructure created"
}

# Function to create iSCSI mount script
create_iscsi_configuration() {
    log "Creating iSCSI configuration..."
    
    # Create iSCSI mount script
    cat > mount-elastic-san.sh << EOF
#!/bin/bash
# iSCSI configuration for Azure Elastic SAN

set -e

# Install iSCSI initiator
sudo apt-get update
sudo apt-get install -y open-iscsi multipath-tools

# Configure iSCSI initiator
sudo systemctl enable iscsid
sudo systemctl start iscsid

# Discover and login to Elastic SAN volumes
sudo iscsiadm -m discovery -t st -p ${ESAN_NAME}.${LOCATION}.cloudapp.azure.com:3260
sudo iscsiadm -m node --login

# Wait for devices to be available
sleep 10

# Create mount points
sudo mkdir -p /mnt/hpc-data
sudo mkdir -p /mnt/hpc-results
sudo mkdir -p /mnt/hpc-libraries

# Find and format the new devices
DEVICES=(\$(sudo fdisk -l | grep -E "Disk /dev/sd[b-z]" | awk '{print \$2}' | tr -d ':'))

if [ \${#DEVICES[@]} -ge 3 ]; then
    # Format devices
    sudo mkfs.ext4 \${DEVICES[0]}
    sudo mkfs.ext4 \${DEVICES[1]}
    sudo mkfs.ext4 \${DEVICES[2]}
    
    # Mount volumes
    sudo mount \${DEVICES[0]} /mnt/hpc-data
    sudo mount \${DEVICES[1]} /mnt/hpc-results
    sudo mount \${DEVICES[2]} /mnt/hpc-libraries
    
    # Configure automatic mounting
    echo "\${DEVICES[0]} /mnt/hpc-data ext4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab
    echo "\${DEVICES[1]} /mnt/hpc-results ext4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab
    echo "\${DEVICES[2]} /mnt/hpc-libraries ext4 defaults,_netdev 0 0" | sudo tee -a /etc/fstab
    
    # Set permissions for HPC user
    sudo chown -R hpcuser:hpcuser /mnt/hpc-*
    sudo chmod -R 755 /mnt/hpc-*
    
    echo "iSCSI volumes mounted successfully"
else
    echo "Warning: Expected 3 devices, found \${#DEVICES[@]}"
    echo "Available devices: \${DEVICES[*]}"
fi
EOF
    
    execute_command \
        "az storage blob upload --account-name ${STORAGE_ACCOUNT} --container-name scripts --name mount-elastic-san.sh --file mount-elastic-san.sh --overwrite --auth-mode login" \
        "Uploading iSCSI mount script"
    
    success "iSCSI configuration created"
}

# Function to create HPC workload
create_hpc_workload() {
    log "Creating HPC workload..."
    
    # Create sample HPC workload script
    cat > hpc-workload.py << EOF
#!/usr/bin/env python3
import os
import sys
import time
import json
import numpy as np
from datetime import datetime

def process_data_chunk(chunk_id, data_size=1000000):
    """Simulate compute-intensive data processing"""
    print(f"Processing chunk {chunk_id} with {data_size} elements")
    
    # Generate synthetic data
    data = np.random.rand(data_size)
    
    # Simulate computation (matrix operations)
    result = np.fft.fft(data)
    processed_data = np.abs(result)
    
    # Calculate statistics
    stats = {
        'chunk_id': chunk_id,
        'mean': float(np.mean(processed_data)),
        'std': float(np.std(processed_data)),
        'min': float(np.min(processed_data)),
        'max': float(np.max(processed_data)),
        'processing_time': time.time(),
        'hostname': os.uname().nodename
    }
    
    return stats

def main():
    chunk_id = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    
    # Process data chunk
    start_time = time.time()
    result = process_data_chunk(chunk_id)
    end_time = time.time()
    
    result['processing_duration'] = end_time - start_time
    
    # Write results to shared storage
    output_file = f"/mnt/hpc-results/chunk_{chunk_id}_results.json"
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Chunk {chunk_id} completed in {result['processing_duration']:.2f} seconds")
    print(f"Results saved to: {output_file}")

if __name__ == "__main__":
    main()
EOF
    
    execute_command \
        "az storage blob upload --account-name ${STORAGE_ACCOUNT} --container-name scripts --name hpc-workload.py --file hpc-workload.py --overwrite --auth-mode login" \
        "Uploading HPC workload script"
    
    success "HPC workload created"
}

# Function to submit HPC job
submit_hpc_job() {
    log "Submitting HPC job..."
    
    # Wait for pool to be ready
    log "Waiting for compute pool to be ready..."
    while true; do
        POOL_STATE=$(az batch pool show --pool-id hpc-compute-pool --query "allocationState" --output tsv 2>/dev/null || echo "unknown")
        if [[ "$POOL_STATE" == "steady" ]]; then
            break
        fi
        log "Pool state: $POOL_STATE - waiting 30 seconds..."
        sleep 30
    done
    
    execute_command \
        "az batch job create --id hpc-parallel-job --pool-id hpc-compute-pool" \
        "Creating Batch job"
    
    # Create multiple parallel tasks
    for i in {1..4}; do
        execute_command \
            "az batch task create --job-id hpc-parallel-job --task-id task-${i} --command-line 'bash -c \"wget -O /tmp/mount-elastic-san.sh https://${STORAGE_ACCOUNT}.blob.core.windows.net/scripts/mount-elastic-san.sh && chmod +x /tmp/mount-elastic-san.sh && /tmp/mount-elastic-san.sh && wget -O /tmp/hpc-workload.py https://${STORAGE_ACCOUNT}.blob.core.windows.net/scripts/hpc-workload.py && python3 /tmp/hpc-workload.py ${i}\"'" \
            "Creating task ${i}"
    done
    
    success "HPC job submitted"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring..."
    
    execute_command \
        "az monitor log-analytics workspace create --resource-group ${RESOURCE_GROUP} --workspace-name ${WORKSPACE_NAME} --location ${LOCATION} --sku PerGB2018" \
        "Creating Log Analytics workspace"
    
    # Get workspace ID
    WORKSPACE_ID=$(az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP} --workspace-name ${WORKSPACE_NAME} --query id --output tsv)
    
    execute_command \
        "az monitor diagnostic-settings create --resource \"/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Batch/batchAccounts/${BATCH_ACCOUNT}\" --name batch-diagnostics --workspace ${WORKSPACE_ID} --logs '[{\"category\":\"ServiceLog\",\"enabled\":true,\"retentionPolicy\":{\"days\":30,\"enabled\":true}}]' --metrics '[{\"category\":\"AllMetrics\",\"enabled\":true,\"retentionPolicy\":{\"days\":30,\"enabled\":true}}]'" \
        "Configuring Batch diagnostics"
    
    success "Monitoring configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Elastic SAN status
    ESAN_STATUS=$(az elastic-san show --resource-group ${RESOURCE_GROUP} --name ${ESAN_NAME} --query "provisioningState" --output tsv)
    if [[ "$ESAN_STATUS" == "Succeeded" ]]; then
        success "Elastic SAN deployment validated"
    else
        warning "Elastic SAN status: $ESAN_STATUS"
    fi
    
    # Check Batch account status
    BATCH_STATUS=$(az batch account show --resource-group ${RESOURCE_GROUP} --name ${BATCH_ACCOUNT} --query "provisioningState" --output tsv)
    if [[ "$BATCH_STATUS" == "Succeeded" ]]; then
        success "Batch account deployment validated"
    else
        warning "Batch account status: $BATCH_STATUS"
    fi
    
    # Check pool status
    POOL_STATUS=$(az batch pool show --pool-id hpc-compute-pool --query "state" --output tsv 2>/dev/null || echo "unknown")
    if [[ "$POOL_STATUS" == "active" ]]; then
        success "Batch pool deployment validated"
    else
        warning "Batch pool status: $POOL_STATUS"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Elastic SAN: ${ESAN_NAME}"
    echo "Batch Account: ${BATCH_ACCOUNT}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Virtual Network: ${VNET_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor job progress: az batch job show --job-id hpc-parallel-job"
    echo "2. Check task status: az batch task list --job-id hpc-parallel-job"
    echo "3. View results: az storage blob list --account-name ${STORAGE_ACCOUNT} --container-name scripts"
    echo "4. Clean up resources: ./destroy.sh"
    echo ""
    echo "Environment variables saved to .env file for cleanup script"
    success "Deployment completed successfully!"
}

# Main execution
main() {
    log "Starting Azure HPC Workload Processing deployment..."
    
    check_prerequisites
    set_environment_variables
    create_foundation
    create_network_infrastructure
    create_elastic_san
    create_batch_infrastructure
    create_iscsi_configuration
    create_hpc_workload
    submit_hpc_job
    configure_monitoring
    validate_deployment
    display_summary
    
    success "Deployment script completed successfully!"
}

# Trap to handle script interruption
trap 'error "Script interrupted. Some resources may have been created. Check Azure portal and run destroy.sh if needed."' INT TERM

# Execute main function
main "$@"