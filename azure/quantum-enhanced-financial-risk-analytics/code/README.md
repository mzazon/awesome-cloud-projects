# Infrastructure as Code for Quantum-Enhanced Financial Risk Analytics Platform

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Quantum-Enhanced Financial Risk Analytics Platform".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for creating:
  - Azure Quantum workspaces
  - Azure Synapse Analytics workspaces
  - Azure Machine Learning workspaces
  - Azure Data Lake Storage accounts
  - Azure Key Vault instances
- Owner or Contributor role on the target subscription
- Understanding of financial risk modeling concepts
- Basic knowledge of quantum computing principles
- Estimated budget: $150-300 per day for development and testing

> **Warning**: This solution includes premium Azure services that may incur significant charges. Monitor resource usage carefully and implement cost controls before deploying to production environments.

## Architecture Overview

This solution deploys:

- **Azure Quantum Workspace**: Quantum optimization algorithms for portfolio management
- **Azure Synapse Analytics**: Unified analytics platform with Spark pools for data processing
- **Azure Machine Learning**: MLOps platform for advanced risk modeling
- **Azure Data Lake Storage Gen2**: Scalable data repository for financial datasets
- **Azure Key Vault**: Secure credential and secrets management
- **Integration Components**: Configurations for hybrid classical-quantum analytics

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Set deployment parameters
export LOCATION="eastus"
export RESOURCE_GROUP="rg-quantum-finance-$(openssl rand -hex 3)"
export DEPLOYMENT_NAME="quantum-finance-deployment"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --name ${DEPLOYMENT_NAME} \
    --parameters location=${LOCATION}

# Monitor deployment progress
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query "properties.provisioningState"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus"

# Apply the infrastructure
terraform apply -var="location=eastus"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow the prompts to configure deployment parameters
```

## Configuration Parameters

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | eastus | Azure region for resource deployment |
| `resourcePrefix` | string | qf-[randomString] | Prefix for all resource names |
| `synapseAdminLogin` | string | synapseadmin | SQL administrator login for Synapse |
| `synapseAdminPassword` | secureString | [generated] | SQL administrator password |
| `sparkPoolNodeSize` | string | Medium | Size of Spark pool nodes |
| `sparkPoolMinNodes` | int | 3 | Minimum number of Spark pool nodes |
| `sparkPoolMaxNodes` | int | 10 | Maximum number of Spark pool nodes |
| `tags` | object | {} | Resource tags for organization |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | eastus | Azure region for deployment |
| `resource_group_name` | string | [generated] | Resource group name |
| `environment` | string | dev | Environment designation |
| `enable_quantum_providers` | bool | true | Enable quantum computing providers |
| `synapse_spark_pool_size` | string | Medium | Spark pool node size |

## Post-Deployment Configuration

### 1. Configure Quantum Workspace

```bash
# Get quantum workspace details
QUANTUM_WORKSPACE=$(az quantum workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE_NAME} \
    --query "name" -o tsv)

# Add quantum providers
az quantum workspace provider add \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE} \
    --provider-id "Microsoft" \
    --provider-sku "DZI-Standard"
```

### 2. Upload Sample Data and Scripts

```bash
# Upload quantum analytics scripts to Data Lake
az storage blob upload-batch \
    --destination "risk-models" \
    --source "./sample-scripts/" \
    --account-name ${STORAGE_ACCOUNT_NAME}

# Upload sample portfolio data
az storage blob upload \
    --account-name ${STORAGE_ACCOUNT_NAME} \
    --container-name "portfolio-data" \
    --name "sample_portfolio.json" \
    --file "./sample-data/sample_portfolio.json"
```

### 3. Configure Synapse Integration

```bash
# Create linked service for Quantum workspace
az synapse linked-service create \
    --workspace-name ${SYNAPSE_WORKSPACE_NAME} \
    --name "QuantumLinkedService" \
    --file quantum-linked-service.json
```

## Validation and Testing

### 1. Verify Resource Deployment

```bash
# Check all resources are deployed successfully
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Verify Quantum workspace status
az quantum workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE_NAME} \
    --query "provisioningState"

# Check Synapse workspace
az synapse workspace show \
    --name ${SYNAPSE_WORKSPACE_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query "provisioningState"
```

### 2. Test Quantum Integration

```bash
# Run sample quantum optimization
az quantum job submit \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE_NAME} \
    --job-input-file "./sample-jobs/portfolio-optimization.json"
```

### 3. Validate Data Pipeline

```bash
# Test Synapse Spark pool
az synapse spark session create \
    --workspace-name ${SYNAPSE_WORKSPACE_NAME} \
    --spark-pool-name "sparkpool01" \
    --name "test-session"
```

## Monitoring and Maintenance

### Cost Management

```bash
# View current costs by resource group
az consumption usage list \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
    --start-date $(date -d '30 days ago' '+%Y-%m-%d') \
    --end-date $(date '+%Y-%m-%d')

# Set up budget alerts
az consumption budget create \
    --resource-group ${RESOURCE_GROUP} \
    --budget-name "quantum-finance-budget" \
    --amount 1000 \
    --time-grain Monthly
```

### Performance Monitoring

```bash
# Check Synapse workspace metrics
az monitor metrics list \
    --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Synapse/workspaces/${SYNAPSE_WORKSPACE_NAME}" \
    --metric "IntegrationActivityRunsEnded"

# Monitor Quantum job status
az quantum job list \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${QUANTUM_WORKSPACE_NAME} \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Monitor deletion progress
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -auto-approve

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify Key Vault soft-deletion
az keyvault list-deleted \
    --subscription ${SUBSCRIPTION_ID}

# Purge deleted Key Vault if needed
az keyvault purge \
    --name ${KEY_VAULT_NAME} \
    --subscription ${SUBSCRIPTION_ID}
```

## Troubleshooting

### Common Issues

1. **Quantum Workspace Provider Registration**:
   ```bash
   # Register quantum resource provider
   az provider register --namespace Microsoft.Quantum
   az provider show --namespace Microsoft.Quantum --query "registrationState"
   ```

2. **Synapse Firewall Configuration**:
   ```bash
   # Add client IP to Synapse firewall
   CLIENT_IP=$(curl -s http://ipinfo.io/ip)
   az synapse workspace firewall-rule create \
       --name "ClientIP" \
       --workspace-name ${SYNAPSE_WORKSPACE_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --start-ip-address ${CLIENT_IP} \
       --end-ip-address ${CLIENT_IP}
   ```

3. **Storage Account Access**:
   ```bash
   # Grant storage blob data contributor role
   az role assignment create \
       --assignee $(az ad signed-in-user show --query objectId -o tsv) \
       --role "Storage Blob Data Contributor" \
       --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}"
   ```

### Diagnostic Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query "properties.error"

# View detailed error information
az deployment operation group list \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query "[?properties.provisioningState=='Failed']"
```

## Security Considerations

### Network Security

- Synapse workspace configured with managed virtual network
- Key Vault access restricted to authorized services
- Storage account configured with firewall rules
- Private endpoints enabled for secure connectivity

### Identity and Access Management

- Managed identities used for service-to-service authentication
- Least privilege access principles applied
- Azure AD integration for user authentication
- Role-based access control (RBAC) configured

### Data Protection

- Encryption at rest enabled for all storage services
- TLS encryption for data in transit
- Azure Key Vault for secrets management
- Data Lake Storage configured with access control lists

## Advanced Configuration

### Custom Quantum Algorithms

1. **Upload Custom Algorithms**:
   ```bash
   # Upload quantum algorithms to storage
   az storage blob upload-batch \
       --destination "quantum-algorithms" \
       --source "./custom-algorithms/" \
       --account-name ${STORAGE_ACCOUNT_NAME}
   ```

2. **Configure Algorithm Parameters**:
   ```bash
   # Store algorithm configurations in Key Vault
   az keyvault secret set \
       --vault-name ${KEY_VAULT_NAME} \
       --name "quantum-algorithm-config" \
       --value '{"risk_aversion": 1.5, "max_iterations": 1000}'
   ```

### Integration with External Systems

1. **Market Data Integration**:
   ```bash
   # Configure Event Hub for real-time data ingestion
   az eventhubs namespace create \
       --resource-group ${RESOURCE_GROUP} \
       --name "market-data-hub-${RANDOM_SUFFIX}" \
       --location ${LOCATION}
   ```

2. **API Management**:
   ```bash
   # Deploy API Management for external access
   az apim create \
       --resource-group ${RESOURCE_GROUP} \
       --name "quantum-api-${RANDOM_SUFFIX}" \
       --publisher-name "Financial Analytics" \
       --publisher-email "admin@company.com" \
       --sku-name Developer
   ```

## Support and Documentation

- **Azure Quantum Documentation**: [https://docs.microsoft.com/en-us/azure/quantum/](https://docs.microsoft.com/en-us/azure/quantum/)
- **Azure Synapse Analytics**: [https://docs.microsoft.com/en-us/azure/synapse-analytics/](https://docs.microsoft.com/en-us/azure/synapse-analytics/)
- **Azure Machine Learning**: [https://docs.microsoft.com/en-us/azure/machine-learning/](https://docs.microsoft.com/en-us/azure/machine-learning/)
- **Financial Services on Azure**: [https://azure.microsoft.com/en-us/industries/financial/](https://azure.microsoft.com/en-us/industries/financial/)

For issues with this infrastructure code, refer to the original recipe documentation or open an issue in the repository.

---

**Note**: This infrastructure deployment creates a sophisticated quantum-enhanced financial analytics platform. Ensure you understand the cost implications and have appropriate permissions before deployment. Always test in a development environment before deploying to production.