# Infrastructure as Code for Federated Container Storage Security with Azure Workload Identity and Container Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Federated Container Storage Security with Azure Workload Identity and Container Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code  
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.47.0 or later installed and configured
- kubectl command-line tool installed
- Helm v3.0+ installed for package management
- Appropriate Azure permissions for:
  - AKS cluster creation and management
  - Managed identity creation and configuration
  - Key Vault creation and RBAC management
  - Storage account and container storage operations
  - Resource group management
- Azure subscription with sufficient quota for:
  - AKS cluster (3 Standard_D2s_v3 nodes minimum)
  - Key Vault standard tier
  - Storage resources for container storage

## Architecture Overview

This infrastructure deploys:

- **AKS Cluster** with Workload Identity and OIDC issuer enabled
- **Azure Container Storage Extension** for ephemeral storage provisioning
- **User-Assigned Managed Identity** with federated credentials
- **Azure Key Vault** for secure secrets management
- **Storage Pool** with ephemeral disk backing for temporary workloads
- **RBAC Configuration** for secure access between components

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters clusterName=<your-cluster-name> \
    --parameters keyVaultName=<your-keyvault-name>

# Get AKS credentials
az aks get-credentials \
    --name <your-cluster-name> \
    --resource-group <your-resource-group>

# Verify deployment
kubectl get nodes
kubectl get storageclass
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="location=eastus" \
    -var="resource_group_name=rg-workload-identity-demo" \
    -var="cluster_name=aks-workload-identity-demo" \
    -var="key_vault_name=kv-workload-demo"

# Apply the configuration
terraform apply \
    -var="location=eastus" \
    -var="resource_group_name=rg-workload-identity-demo" \
    -var="cluster_name=aks-workload-identity-demo" \
    -var="key_vault_name=kv-workload-demo"

# Get AKS credentials
az aks get-credentials \
    --name $(terraform output -raw cluster_name) \
    --resource-group $(terraform output -raw resource_group_name)
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-workload-identity-demo"
export LOCATION="eastus"
export AKS_CLUSTER_NAME="aks-workload-identity-demo"
export KEY_VAULT_NAME="kv-workload-demo"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
kubectl get nodes
kubectl get storagepool -n acstor
```

## Post-Deployment Steps

After the infrastructure is deployed, follow these steps to complete the setup:

1. **Install Azure Container Storage Extension**:
   ```bash
   # Extension installation is included in the deployment scripts
   # Verify installation
   kubectl get pods -n acstor
   ```

2. **Create Storage Pool and Storage Class**:
   ```bash
   # Apply storage pool configuration
   kubectl apply -f - <<EOF
   apiVersion: containerstorage.azure.com/v1
   kind: StoragePool
   metadata:
     name: ephemeral-pool
     namespace: acstor
   spec:
     poolType:
       ephemeralDisk:
         diskType: temp
         diskSize: 100Gi
     nodePoolName: nodepool1
     reclaimPolicy: Delete
   EOF
   
   # Apply storage class
   kubectl apply -f - <<EOF
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: ephemeral-storage
   provisioner: containerstorage.csi.azure.com
   parameters:
     protocol: "nfs"
     storagePool: "ephemeral-pool"
     server: "ephemeral-pool.acstor.svc.cluster.local"
   volumeBindingMode: Immediate
   reclaimPolicy: Delete
   EOF
   ```

3. **Deploy Test Workload**:
   ```bash
   # Create namespace
   kubectl create namespace workload-identity-demo
   
   # Create service account (using output from infrastructure deployment)
   kubectl apply -f - <<EOF
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: workload-identity-sa
     namespace: workload-identity-demo
     annotations:
       azure.workload.identity/client-id: $(terraform output -raw managed_identity_client_id)
     labels:
       azure.workload.identity/use: "true"
   EOF
   
   # Deploy test workload (see recipe for complete deployment manifest)
   ```

## Configuration

### Bicep Parameters

The Bicep template accepts the following parameters:

- `location`: Azure region for resource deployment (default: eastus)
- `clusterName`: Name for the AKS cluster
- `keyVaultName`: Name for the Azure Key Vault (must be globally unique)
- `nodeCount`: Number of nodes in the AKS cluster (default: 3)
- `nodeVmSize`: VM size for cluster nodes (default: Standard_D2s_v3)

### Terraform Variables

The Terraform configuration uses these variables:

- `location`: Azure region for deployment
- `resource_group_name`: Name of the resource group
- `cluster_name`: Name for the AKS cluster
- `key_vault_name`: Name for the Key Vault
- `node_count`: Number of cluster nodes (default: 3)
- `node_vm_size`: VM size for nodes (default: Standard_D2s_v3)

## Validation

After deployment, validate the infrastructure:

1. **Verify AKS Cluster**:
   ```bash
   kubectl get nodes
   kubectl cluster-info
   ```

2. **Check Workload Identity Configuration**:
   ```bash
   # Verify OIDC issuer
   az aks show --name <cluster-name> --resource-group <resource-group> \
       --query "oidcIssuerProfile.issuerUrl" --output tsv
   
   # Check federated credentials
   az identity federated-credential list \
       --identity-name <managed-identity-name> \
       --resource-group <resource-group>
   ```

3. **Validate Container Storage**:
   ```bash
   # Check extension status
   az k8s-extension show \
       --cluster-name <cluster-name> \
       --resource-group <resource-group> \
       --cluster-type managedClusters \
       --name azure-container-storage
   
   # Verify storage components
   kubectl get pods -n acstor
   kubectl get storageclass
   ```

4. **Test Key Vault Access**:
   ```bash
   # Verify Key Vault and secret
   az keyvault secret show \
       --vault-name <key-vault-name> \
       --name storage-encryption-key
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <your-resource-group> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="location=eastus" \
    -var="resource_group_name=rg-workload-identity-demo" \
    -var="cluster_name=aks-workload-identity-demo" \
    -var="key_vault_name=kv-workload-demo"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show --name $RESOURCE_GROUP || echo "Resource group deleted successfully"
```

## Security Considerations

This infrastructure implements several security best practices:

- **Workload Identity**: Eliminates need for stored credentials in pods
- **Federated Authentication**: Uses OIDC token exchange for secure authentication
- **RBAC**: Implements least-privilege access for managed identities
- **Key Vault Integration**: Centralizes secrets management with secure access
- **Ephemeral Storage**: Temporary storage with automatic lifecycle management

## Troubleshooting

### Common Issues

1. **Extension Installation Failure**:
   ```bash
   # Check extension status
   az k8s-extension list \
       --cluster-name <cluster-name> \
       --resource-group <resource-group> \
       --cluster-type managedClusters
   
   # View extension logs
   kubectl logs -n acstor -l app.kubernetes.io/name=azure-container-storage
   ```

2. **Workload Identity Authentication Issues**:
   ```bash
   # Verify service account annotations
   kubectl get serviceaccount workload-identity-sa -n workload-identity-demo -o yaml
   
   # Check federated credential configuration
   az identity federated-credential list \
       --identity-name <managed-identity-name> \
       --resource-group <resource-group>
   ```

3. **Storage Pool Creation Problems**:
   ```bash
   # Check node labels and taints
   kubectl get nodes --show-labels
   
   # Verify storage pool status
   kubectl describe storagepool ephemeral-pool -n acstor
   ```

## Cost Estimation

Estimated costs for this infrastructure (East US region):

- **AKS Cluster**: ~$150-200/month (3 Standard_D2s_v3 nodes)
- **Key Vault**: ~$3-5/month (standard tier with minimal operations)
- **Container Storage**: Variable based on storage usage
- **Managed Identity**: No additional cost

> **Note**: Costs may vary based on region, usage patterns, and Azure pricing changes. Use the Azure Pricing Calculator for accurate estimates.

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation:
   - [Azure Workload Identity](https://docs.microsoft.com/en-us/azure/aks/workload-identity-overview)
   - [Azure Container Storage](https://docs.microsoft.com/en-us/azure/storage/container-storage/)
   - [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
3. Verify Azure CLI and kubectl versions
4. Check Azure service health and regional availability

## Contributing

When modifying this infrastructure:

- Follow Azure naming conventions
- Implement proper resource tagging
- Maintain security best practices
- Update documentation accordingly
- Test changes in a development environment first