# Infrastructure as Code for Adaptive ML Model Scaling with Azure AI Foundry and Compute Fleet

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Adaptive ML Model Scaling with Azure AI Foundry and Compute Fleet".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.60.0 or later installed and configured
- Azure subscription with appropriate permissions for:
  - Azure AI Foundry (preview features)
  - Azure Compute Fleet
  - Azure Machine Learning
  - Azure Monitor and Log Analytics
  - Azure Storage and Key Vault
- Understanding of machine learning workflows and Azure compute services
- Familiarity with Azure AI Foundry and agent orchestration concepts
- **Preview Access**: Ensure your subscription has access to Azure AI Foundry and Compute Fleet preview services

## Architecture Overview

This solution deploys:
- Azure AI Foundry Hub and Project for agent orchestration
- Azure Compute Fleet for dynamic ML compute scaling
- Azure Machine Learning workspace for model development
- Connected agents for cost optimization and performance monitoring
- Azure Monitor and Log Analytics for workload intelligence
- Automated scaling workflows and policies

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group your-resource-group \
    --template-file main.bicep \
    --parameters @parameters.json

# Or use the deployment script
chmod +x ../scripts/deploy.sh
../scripts/deploy.sh
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# Or use the deployment script
chmod +x ../scripts/deploy.sh
../scripts/deploy.sh
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration

### Key Parameters

- **Location**: Azure region for resource deployment (default: eastus)
- **Resource Group**: Target resource group for all resources
- **AI Foundry Name**: Name for the AI Foundry hub
- **Compute Fleet Name**: Name for the Azure Compute Fleet
- **ML Workspace Name**: Name for the Machine Learning workspace
- **VM Sizes**: Compute fleet VM size preferences and scaling profiles
- **Scaling Policies**: Thresholds and parameters for adaptive scaling

### Bicep Parameters

Edit `bicep/parameters.json` to customize:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "aiFourndryName": {
      "value": "aif-adaptive-ml"
    },
    "computeFleetName": {
      "value": "cf-ml-scaling"
    },
    "mlWorkspaceName": {
      "value": "mlw-scaling"
    }
  }
}
```

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
location = "eastus"
resource_group_name = "rg-ml-adaptive-scaling"
ai_foundry_name = "aif-adaptive-ml"
compute_fleet_name = "cf-ml-scaling"
ml_workspace_name = "mlw-scaling"

# Compute Fleet Configuration
vm_sizes_profile = [
  {
    name = "Standard_D4s_v3"
    rank = 1
  },
  {
    name = "Standard_D8s_v3"
    rank = 2
  },
  {
    name = "Standard_E4s_v3"
    rank = 3
  }
]

# Scaling Configuration
spot_capacity = 20
spot_min_capacity = 5
regular_capacity = 10
regular_min_capacity = 2
```

## Deployment Steps

### 1. Prerequisites Setup

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Register required providers
az provider register --namespace Microsoft.MachineLearningServices
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.OperationalInsights

# Create resource group
az group create --name rg-ml-adaptive-scaling --location eastus
```

### 2. Deploy Infrastructure

Choose your preferred deployment method from the Quick Start section above.

### 3. Post-Deployment Configuration

After infrastructure deployment, configure the agents and workflows:

```bash
# Configure AI Foundry agents
az ml agent create --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name ml-scaling-agent \
    --file agent-config.json

# Deploy scaling policies
az ml agent update --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name ml-scaling-agent \
    --add-policy @scaling-policy.json

# Enable automated workflows
az ml workflow enable --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name adaptive-ml-scaling
```

## Validation

### Verify Deployment

```bash
# Check AI Foundry deployment
az ml workspace show --resource-group rg-ml-adaptive-scaling \
    --name your-ai-foundry-name

# Verify Compute Fleet
az vm fleet show --resource-group rg-ml-adaptive-scaling \
    --name your-compute-fleet-name

# Check agent status
az ml agent show --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name ml-scaling-agent
```

### Test Scaling

```bash
# Submit test ML job to trigger scaling
az ml job submit --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ml-workspace-name \
    --name scaling-test-job \
    --compute compute-cluster \
    --command "python train_model.py --samples 100000"

# Monitor scaling actions
az ml agent logs --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name ml-scaling-agent \
    --tail 50
```

## Monitoring

### Azure Monitor Dashboard

Access the deployed monitoring dashboard:

```bash
# View scaling metrics dashboard
az monitor workbook show --resource-group rg-ml-adaptive-scaling \
    --name ML-Scaling-Dashboard
```

### Cost Monitoring

Track costs associated with adaptive scaling:

```bash
# View cost analysis
az consumption usage list --resource-group rg-ml-adaptive-scaling \
    --start-date 2025-01-01 --end-date 2025-01-31
```

### Performance Metrics

Monitor ML workload performance:

```bash
# Query performance metrics
az monitor metrics list --resource-group rg-ml-adaptive-scaling \
    --resource your-ml-workspace-name \
    --metric-names CpuUtilization,MemoryUtilization
```

## Troubleshooting

### Common Issues

1. **Preview Service Access**: Ensure your subscription has access to Azure AI Foundry and Compute Fleet preview services
2. **Quota Limits**: Verify compute quotas in your target region
3. **Resource Provider Registration**: Ensure all required providers are registered
4. **Permissions**: Verify sufficient permissions for all resource types

### Debug Commands

```bash
# Check resource provider registration
az provider show --namespace Microsoft.MachineLearningServices

# Verify quota limits
az vm list-usage --location eastus

# Check deployment status
az deployment group show --resource-group rg-ml-adaptive-scaling \
    --name main

# View activity logs
az monitor activity-log list --resource-group rg-ml-adaptive-scaling \
    --max-events 50
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name rg-ml-adaptive-scaling --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup

If automated cleanup fails:

```bash
# Stop workflows first
az ml workflow disable --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name adaptive-ml-scaling

# Delete agents
az ml agent delete --resource-group rg-ml-adaptive-scaling \
    --workspace-name your-ai-foundry-name \
    --name ml-scaling-agent

# Delete compute fleet
az vm fleet delete --resource-group rg-ml-adaptive-scaling \
    --name your-compute-fleet-name --yes

# Delete resource group
az group delete --name rg-ml-adaptive-scaling --yes
```

## Security Considerations

### Best Practices Implemented

- **Least Privilege Access**: IAM roles follow principle of least privilege
- **Network Security**: Virtual network isolation for compute resources
- **Data Encryption**: Encryption at rest and in transit for all data
- **Key Management**: Azure Key Vault for secrets and keys
- **Identity Management**: Azure Active Directory integration
- **Monitoring**: Comprehensive logging and alerting

### Security Configuration

```bash
# Enable Key Vault for secrets
az keyvault create --resource-group rg-ml-adaptive-scaling \
    --name kv-ml-scaling --location eastus

# Configure managed identity
az identity create --resource-group rg-ml-adaptive-scaling \
    --name mi-ml-scaling

# Enable network security
az network vnet create --resource-group rg-ml-adaptive-scaling \
    --name vnet-ml-scaling --address-prefixes 10.0.0.0/16
```

## Cost Optimization

### Cost Management Features

- **Spot Instance Integration**: Automatic spot instance usage for cost savings
- **Intelligent Scaling**: Demand-based scaling to minimize waste
- **Cost Monitoring**: Real-time cost tracking and alerts
- **Reserved Capacity**: Support for reserved instances where applicable

### Cost Tracking

```bash
# Set up cost alerts
az consumption budget create --resource-group rg-ml-adaptive-scaling \
    --budget-name ml-scaling-budget \
    --amount 1000 \
    --time-grain Monthly
```

## Customization

### Extending the Solution

1. **Multi-Region Deployment**: Modify templates for cross-region scaling
2. **Custom Agents**: Add specialized agents for specific workloads
3. **Advanced Policies**: Implement complex scaling policies
4. **Integration**: Connect with existing MLOps pipelines

### Template Modification

The infrastructure templates can be customized for specific requirements:

- **Bicep**: Modify `main.bicep` and parameter files
- **Terraform**: Update `main.tf` and variable definitions
- **Scripts**: Customize deployment scripts for environment-specific needs

## Support

### Documentation References

- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Azure Compute Fleet Documentation](https://learn.microsoft.com/en-us/azure/azure-compute-fleet/)
- [Azure Machine Learning Documentation](https://learn.microsoft.com/en-us/azure/machine-learning/)
- [Azure Monitor Documentation](https://learn.microsoft.com/en-us/azure/azure-monitor/)

### Getting Help

For issues with this infrastructure code:
1. Check the troubleshooting section above
2. Review Azure service status and limitations
3. Consult the original recipe documentation
4. Contact Azure support for service-specific issues

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Azure CLI Version**: 2.60.0+
- **Bicep Version**: Latest stable
- **Terraform Version**: >= 1.0
- **Azure Provider Version**: >= 3.0

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes thoroughly in development environment
2. Update documentation for any parameter changes
3. Validate against latest Azure best practices
4. Ensure compatibility with all deployment methods