# Infrastructure as Code for Hybrid Edge Infrastructure with Stack HCI and Arc

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid Edge Infrastructure with Stack HCI and Arc".

## Overview

This solution implements a comprehensive edge computing infrastructure using Azure Stack HCI for hyperconverged infrastructure and Azure Arc for centralized management. The deployment creates a hybrid cloud environment that enables organizations to process data at the edge while maintaining cloud-native management capabilities.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Architecture

The solution deploys:

- Azure Stack HCI cluster resources in Azure
- Azure Arc configuration for edge server management
- Azure Monitor with Log Analytics workspace for observability
- Azure Policy assignments for governance
- Azure Storage Account with File Sync for edge data synchronization
- AKS cluster on Azure Stack HCI for containerized workloads
- Sample edge applications and monitoring configuration

## Prerequisites

### Required Tools

- Azure CLI v2.35.0 or later installed and configured
- PowerShell 7.0+ with Azure PowerShell modules (for Bicep)
- Terraform v1.0+ (for Terraform implementation)
- kubectl (for Kubernetes management)
- Appropriate Azure subscription with permissions for:
  - Azure Stack HCI resource creation
  - Azure Arc resource management
  - Azure Monitor and Log Analytics
  - Azure Storage Account creation
  - Azure Policy management

### Hardware Requirements

- Azure Stack HCI validated hardware (minimum 2 nodes)
- Network connectivity between edge locations and Azure
- Active Directory Domain Services for cluster authentication
- Windows Admin Center for initial cluster configuration

### Azure Permissions

The deployment requires the following Azure RBAC roles:
- Contributor on the target resource group
- Azure Stack HCI Administrator
- Azure Arc Onboarding role
- Log Analytics Contributor
- Storage Account Contributor

### Cost Considerations

Estimated monthly cost: $500-2000 depending on:
- Number of HCI nodes and configuration
- Azure Monitor data ingestion volume
- Storage Account usage and sync frequency
- AKS workload resource consumption

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Review and customize parameters
cp parameters.example.json parameters.json
# Edit parameters.json with your values

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-edge-infrastructure \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-edge-infrastructure \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan the deployment
terraform plan -var-file="terraform.tfvars"

# Apply the configuration
terraform apply -var-file="terraform.tfvars"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export RESOURCE_GROUP="rg-edge-infrastructure"
export LOCATION="eastus"
export CLUSTER_NAME="hci-cluster-demo"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
az stack-hci cluster list --resource-group $RESOURCE_GROUP --output table
```

## Post-Deployment Configuration

### 1. Register Physical HCI Cluster

After deploying the Azure resources, you'll need to register your physical Azure Stack HCI cluster:

```bash
# On the HCI cluster nodes, download and run the registration script
Invoke-WebRequest -Uri "https://aka.ms/ashciregistration" -OutFile "HCIRegistration.ps1"
.\HCIRegistration.ps1 -SubscriptionId "your-subscription-id" -ResourceGroupName "rg-edge-infrastructure"
```

### 2. Install Azure Arc Agent on Servers

```bash
# Download and install Arc agent on each server
curl -L https://aka.ms/azcmagent -o ~/install_linux_azcmagent.sh
bash ~/install_linux_azcmagent.sh

# Connect server to Azure Arc
azcmagent connect \
    --resource-group "rg-edge-infrastructure" \
    --tenant-id "your-tenant-id" \
    --location "eastus" \
    --subscription-id "your-subscription-id"
```

### 3. Configure AKS on Azure Stack HCI

```bash
# Get AKS cluster credentials
az aksarc get-credentials \
    --resource-group rg-edge-infrastructure \
    --name aks-edge-cluster

# Verify cluster connectivity
kubectl get nodes

# Deploy sample applications
kubectl apply -f ../manifests/
```

## Validation & Testing

### Verify Azure Stack HCI Registration

```bash
# Check cluster status
az stack-hci cluster show \
    --resource-group rg-edge-infrastructure \
    --name hci-cluster-demo \
    --query "status"

# Verify cluster health
az stack-hci cluster list \
    --resource-group rg-edge-infrastructure \
    --output table
```

### Test Azure Arc Connectivity

```bash
# List connected machines
az connectedmachine list \
    --resource-group rg-edge-infrastructure \
    --output table

# Check agent status
az connectedmachine show \
    --resource-group rg-edge-infrastructure \
    --name arc-hci-server \
    --query "status"
```

### Validate Monitoring

```bash
# Query Log Analytics for HCI data
az monitor log-analytics query \
    --workspace la-edge-workspace \
    --analytics-query "Heartbeat | where Computer contains 'HCI' | take 10"

# Check Azure Monitor metrics
az monitor metrics list \
    --resource-group rg-edge-infrastructure \
    --resource hci-cluster-demo \
    --resource-type Microsoft.AzureStackHCI/clusters
```

### Test Kubernetes Workloads

```bash
# Check cluster status
kubectl cluster-info

# Verify node health
kubectl get nodes -o wide

# Check deployed workloads
kubectl get pods --all-namespaces

# Test service connectivity
kubectl get services --all-namespaces
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-edge-infrastructure \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-edge-infrastructure
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var-file="terraform.tfvars"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group exists --name rg-edge-infrastructure
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove resources in this order:

1. **AKS Clusters**: Delete any AKS clusters on Azure Stack HCI
2. **Arc Agents**: Disconnect Arc agents from servers
3. **HCI Cluster**: Unregister Azure Stack HCI cluster
4. **Azure Resources**: Delete Azure resource group

```bash
# Disconnect Arc agents
azcmagent disconnect

# Unregister HCI cluster (run on cluster)
Unregister-AzStackHCI

# Delete Azure resources
az group delete --name rg-edge-infrastructure --yes
```

## Customization

### Key Parameters

Each implementation supports customization through parameters/variables:

- **Resource Group**: Target resource group name
- **Location**: Azure region for cloud resources
- **Cluster Name**: Azure Stack HCI cluster name
- **Storage Configuration**: Storage account settings and sync options
- **Monitoring Settings**: Log Analytics workspace configuration
- **Network Configuration**: Virtual network and subnet settings
- **Security Settings**: Policy assignments and compliance rules

### Scaling Options

- **Multi-Node Clusters**: Increase HCI cluster node count
- **Multiple Locations**: Deploy to multiple edge locations
- **Workload Scaling**: Configure auto-scaling for AKS workloads
- **Storage Scaling**: Adjust storage quotas and sync frequency

### Security Hardening

- Enable Azure Security Center for Arc resources
- Configure Azure Sentinel for security monitoring
- Implement custom Azure Policy definitions
- Enable Azure Key Vault for secrets management

## Troubleshooting

### Common Issues

1. **HCI Registration Failures**
   ```bash
   # Check network connectivity
   Test-NetConnection -ComputerName management.azure.com -Port 443
   
   # Verify permissions
   Get-AzContext
   ```

2. **Arc Agent Connection Issues**
   ```bash
   # Check agent status
   azcmagent check
   
   # View agent logs
   journalctl -u himdsd
   ```

3. **AKS Connectivity Problems**
   ```bash
   # Check cluster status
   kubectl get nodes
   
   # Review cluster events
   kubectl get events --sort-by=.metadata.creationTimestamp
   ```

### Log Locations

- **Azure CLI logs**: `~/.azure/logs/`
- **Terraform logs**: Set `TF_LOG=DEBUG`
- **HCI logs**: Windows Event Logs on cluster nodes
- **Arc agent logs**: `/var/opt/azcmagent/log/` (Linux) or Event Viewer (Windows)

## Monitoring and Maintenance

### Key Metrics to Monitor

- HCI cluster health and performance
- Arc agent connectivity status
- Storage sync status and performance
- AKS cluster resource utilization
- Network connectivity and latency

### Maintenance Tasks

- Regular Azure CLI and PowerShell updates
- HCI cluster firmware and driver updates
- Arc agent updates (automatic by default)
- Kubernetes cluster updates
- Security policy compliance reviews

## Support and Documentation

### Official Documentation

- [Azure Stack HCI Documentation](https://docs.microsoft.com/en-us/azure-stack/hci/)
- [Azure Arc Documentation](https://docs.microsoft.com/en-us/azure/azure-arc/)
- [AKS on Azure Stack HCI](https://docs.microsoft.com/en-us/azure/aks/hybrid/)
- [Azure Monitor for Hybrid](https://docs.microsoft.com/en-us/azure/azure-monitor/agents/agents-overview)

### Community Resources

- [Azure Stack HCI Community](https://techcommunity.microsoft.com/t5/azure-stack-hci/bd-p/AzureStackHCI)
- [Azure Arc Community](https://techcommunity.microsoft.com/t5/azure-arc/bd-p/AzureArc)
- [Azure Kubernetes Service](https://github.com/Azure/AKS)

### Getting Help

For issues with this infrastructure code:
1. Review the troubleshooting section above
2. Check the original recipe documentation
3. Consult the official Azure documentation
4. Engage with the Azure community forums

## Contributing

To improve this infrastructure code:
1. Test changes in a development environment
2. Follow Azure naming conventions and best practices
3. Update documentation to reflect changes
4. Validate with both Bicep and Terraform implementations