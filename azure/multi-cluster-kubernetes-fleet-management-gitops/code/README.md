# Infrastructure as Code for Multi-Cluster Kubernetes Fleet Management with GitOps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Cluster Kubernetes Fleet Management with GitOps".

## Available Implementations

- **Bicep**: Microsoft's recommended infrastructure as code language for Azure
- **Terraform**: Multi-cloud infrastructure as code using official Azure provider
- **Scripts**: Bash deployment and cleanup scripts for manual deployment

## Prerequisites

- Azure CLI v2.46.0 or later installed and configured
- kubectl v1.28+ installed for Kubernetes cluster management
- Helm v3.12+ installed for deploying Azure Service Operator
- Azure subscription with Owner or Contributor permissions
- OpenSSL for generating random values
- jq for JSON processing

## Architecture Overview

This solution deploys:
- Azure Kubernetes Fleet Manager for centralized multi-cluster orchestration
- Three AKS clusters distributed across different Azure regions (East US, West US 2, Central US)
- Azure Service Operator (ASO) installed on each cluster for Azure resource management
- Azure Container Registry for centralized image management
- Azure Key Vault for secure secret management
- Sample multi-region storage accounts demonstrating cross-region resource provisioning

## Quick Start

### Using Bicep
```bash
cd bicep/

# Login to Azure
az login

# Set subscription (if needed)
az account set --subscription "your-subscription-id"

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-fleet-demo \
    --template-file main.bicep \
    --parameters location=eastus

# Get deployment outputs
az deployment group show \
    --resource-group rg-fleet-demo \
    --name main \
    --query properties.outputs
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Deployment Details

### Resource Groups
- Primary resource group for Fleet Manager and shared resources
- Regional resource placement for optimal performance

### AKS Clusters
- **Cluster 1**: East US region with 2 Standard_DS2_v2 nodes
- **Cluster 2**: West US 2 region with 2 Standard_DS2_v2 nodes  
- **Cluster 3**: Central US region with 2 Standard_DS2_v2 nodes
- All clusters use Azure CNI networking and Azure network policies
- Managed identity enabled for secure Azure resource access

### Azure Service Operator
- Deployed on all clusters using Helm charts
- Configured with Service Principal for Azure resource management
- Limited CRD pattern for security and performance optimization
- cert-manager installed as prerequisite

### Network Configuration
- Azure CNI for optimal pod networking performance
- Azure Network Policy for microsegmentation
- Multi-region deployment for high availability

### Security Features
- Managed identities for cluster authentication
- Service Principal with least privilege access for ASO
- Azure Key Vault integration for secret management
- Network policies for pod-to-pod communication control

## Post-Deployment Configuration

### 1. Connect to AKS Clusters
```bash
# Get credentials for all clusters
az aks get-credentials --resource-group rg-fleet-demo --name aks-fleet-1
az aks get-credentials --resource-group rg-fleet-demo --name aks-fleet-2
az aks get-credentials --resource-group rg-fleet-demo --name aks-fleet-3

# Verify connectivity
kubectl config get-contexts
```

### 2. Install Azure Service Operator
```bash
# The deployment scripts automatically install ASO, but you can verify:
kubectl get pods -n azureserviceoperator-system --context aks-fleet-1
kubectl get pods -n azureserviceoperator-system --context aks-fleet-2
kubectl get pods -n azureserviceoperator-system --context aks-fleet-3
```

### 3. Join Clusters to Fleet
```bash
# Clusters are automatically joined during deployment
# Verify fleet membership:
az fleet member list --resource-group rg-fleet-demo --fleet-name multicluster-fleet
```

### 4. Deploy Sample Applications
```bash
# Create application namespaces
kubectl create namespace fleet-app --context aks-fleet-1
kubectl create namespace fleet-app --context aks-fleet-2
kubectl create namespace fleet-app --context aks-fleet-3

# Deploy region-specific applications with storage
# (Scripts include sample application deployment)
```

## Validation and Testing

### 1. Verify Fleet Manager Status
```bash
# Check fleet health
az fleet show --resource-group rg-fleet-demo --name multicluster-fleet

# List fleet members
az fleet member list --resource-group rg-fleet-demo --fleet-name multicluster-fleet --output table
```

### 2. Test Azure Service Operator
```bash
# Check ASO pod status across clusters
for cluster in aks-fleet-1 aks-fleet-2 aks-fleet-3; do
    echo "Checking $cluster..."
    kubectl get pods -n azureserviceoperator-system --context $cluster
done

# Verify Azure resources created via ASO
kubectl get storageaccounts,registries,vaults -A --context aks-fleet-1
```

### 3. Test Cross-Region Connectivity
```bash
# Create test pods in each cluster
kubectl run test-pod --image=mcr.microsoft.com/azure-cli --context aks-fleet-1 -- sleep 3600
kubectl run test-pod --image=mcr.microsoft.com/azure-cli --context aks-fleet-2 -- sleep 3600
kubectl run test-pod --image=mcr.microsoft.com/azure-cli --context aks-fleet-3 -- sleep 3600

# Test network connectivity between regions
kubectl exec test-pod --context aks-fleet-1 -- ping -c 3 google.com
```

### 4. Validate Update Orchestration
```bash
# Create a test update run
az fleet updaterun create \
    --resource-group rg-fleet-demo \
    --fleet-name multicluster-fleet \
    --name test-update \
    --upgrade-type NodeImageOnly \
    --node-image-selection Latest

# Monitor update progress
az fleet updaterun show \
    --resource-group rg-fleet-demo \
    --fleet-name multicluster-fleet \
    --name test-update
```

## Customization

### Variables and Parameters

#### Bicep Parameters
- `location`: Primary Azure region (default: eastus)
- `resourceGroupName`: Resource group name prefix
- `fleetName`: Fleet Manager instance name
- `clusterPrefix`: AKS cluster naming prefix
- `nodeCount`: Number of nodes per cluster (default: 2)
- `nodeVmSize`: VM size for cluster nodes (default: Standard_DS2_v2)

#### Terraform Variables
- `location`: Primary Azure region
- `resource_group_name`: Resource group for all resources
- `fleet_name`: Fleet Manager name
- `cluster_locations`: List of regions for AKS clusters
- `node_count`: Number of nodes per cluster
- `node_vm_size`: VM size for cluster nodes
- `kubernetes_version`: Kubernetes version for clusters

#### Environment Variables for Scripts
- `RESOURCE_GROUP`: Resource group name
- `LOCATION`: Primary Azure region
- `FLEET_NAME`: Fleet Manager name
- `SUBSCRIPTION_ID`: Azure subscription ID

### Scaling Configuration

#### Horizontal Scaling
```bash
# Scale cluster node count
az aks scale \
    --resource-group rg-fleet-demo \
    --name aks-fleet-1 \
    --node-count 4

# Add additional node pools
az aks nodepool add \
    --resource-group rg-fleet-demo \
    --cluster-name aks-fleet-1 \
    --name gpu-pool \
    --node-count 2 \
    --node-vm-size Standard_NC6s_v3
```

#### Vertical Scaling
```bash
# Upgrade cluster to larger VM sizes
az aks nodepool update \
    --resource-group rg-fleet-demo \
    --cluster-name aks-fleet-1 \
    --name nodepool1 \
    --node-vm-size Standard_DS3_v2
```

### Security Hardening

#### Network Security
```bash
# Enable private clusters
az aks update \
    --resource-group rg-fleet-demo \
    --name aks-fleet-1 \
    --enable-private-cluster

# Configure authorized IP ranges
az aks update \
    --resource-group rg-fleet-demo \
    --name aks-fleet-1 \
    --api-server-authorized-ip-ranges "your-ip-range/32"
```

#### Pod Security
```bash
# Enable Azure Policy for Kubernetes
az aks enable-addons \
    --resource-group rg-fleet-demo \
    --name aks-fleet-1 \
    --addons azure-policy

# Apply pod security standards
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: secure-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
EOF
```

## Monitoring and Observability

### Azure Monitor Integration
```bash
# Enable Container Insights
az aks enable-addons \
    --resource-group rg-fleet-demo \
    --name aks-fleet-1 \
    --addons monitoring

# Configure log analytics workspace
az monitor log-analytics workspace create \
    --resource-group rg-fleet-demo \
    --workspace-name fleet-logs
```

### Prometheus and Grafana
```bash
# Install Prometheus using Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace

# Configure Grafana dashboards for fleet monitoring
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
```

## Troubleshooting

### Common Issues

#### Fleet Manager Connection Issues
```bash
# Check fleet member status
az fleet member show \
    --resource-group rg-fleet-demo \
    --fleet-name multicluster-fleet \
    --name member-1

# Verify cluster identity permissions
az aks show --resource-group rg-fleet-demo --name aks-fleet-1 --query identity
```

#### Azure Service Operator Issues
```bash
# Check ASO logs
kubectl logs -n azureserviceoperator-system -l app.kubernetes.io/name=azure-service-operator

# Verify Service Principal permissions
az ad sp show --id your-sp-id --query appRoles
```

#### Networking Issues
```bash
# Test DNS resolution
kubectl run test-dns --image=busybox --restart=Never -- nslookup kubernetes.default

# Check network policies
kubectl get networkpolicies --all-namespaces
```

### Log Analysis
```bash
# View fleet update logs
az fleet updaterun list \
    --resource-group rg-fleet-demo \
    --fleet-name multicluster-fleet

# Check cluster event logs
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --name rg-fleet-demo --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
az group show --name rg-fleet-demo --query provisioningState
```

### Manual Cleanup (if needed)
```bash
# Remove fleet members first
az fleet member delete \
    --resource-group rg-fleet-demo \
    --fleet-name multicluster-fleet \
    --name member-1 \
    --yes

# Delete AKS clusters
az aks delete \
    --resource-group rg-fleet-demo \
    --name aks-fleet-1 \
    --yes \
    --no-wait

# Delete Fleet Manager
az fleet delete \
    --resource-group rg-fleet-demo \
    --name multicluster-fleet \
    --yes

# Clean up Service Principal
az ad sp delete --id your-service-principal-id

# Remove resource group
az group delete --name rg-fleet-demo --yes
```

## Cost Optimization

### Resource Optimization
- Use Azure Reserved Instances for predictable workloads
- Implement cluster autoscaling to optimize node usage
- Use spot instances for development/testing clusters
- Monitor resource utilization with Azure Cost Management

### Estimated Monthly Costs
- AKS clusters (3 x 2 nodes): ~$300-400/month
- Fleet Manager: No additional cost
- Azure Container Registry: ~$5-10/month
- Azure Key Vault: ~$1-2/month
- Storage accounts: ~$5-10/month
- **Total estimated cost: ~$400-600/month**

## Additional Resources

- [Azure Kubernetes Fleet Manager Documentation](https://learn.microsoft.com/en-us/azure/kubernetes-fleet/overview)
- [Azure Service Operator Documentation](https://azure.github.io/azure-service-operator/)
- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Multi-Cluster Kubernetes Patterns](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/containers/aks-multi-cluster)
- [Azure Well-Architected Framework](https://learn.microsoft.com/en-us/azure/well-architected/)

## Support

For issues with this infrastructure code, refer to:
1. The original recipe documentation
2. Azure documentation for specific services
3. Community forums and GitHub issues for open-source tools
4. Azure support for production issues

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Validate against the original recipe requirements
3. Update documentation as needed
4. Follow Azure and infrastructure-as-code best practices