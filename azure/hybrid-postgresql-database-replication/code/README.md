# Infrastructure as Code for Hybrid PostgreSQL Database Replication

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid PostgreSQL Database Replication with Azure Arc and Cloud Database".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template evolution)
- **Terraform**: Multi-cloud infrastructure as code using Azure Provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

- Azure CLI v2.62.0 or later installed and configured
- kubectl CLI tool installed (v1.28 or later)
- Kubernetes cluster (AKS, EKS, GKE, or on-premises) with minimum 4 vCPUs and 16GB RAM
- Azure subscription with Owner or Contributor access
- Appropriate permissions for:
  - Creating resource groups and Azure resources
  - Deploying to Kubernetes clusters
  - Managing Azure Arc-enabled services
  - Configuring Azure Event Grid and Data Factory
- Basic understanding of PostgreSQL replication concepts
- Azure Arc data services extension: `az extension add --name arcdata`

> **Note**: Azure Arc-enabled PostgreSQL is currently in preview. Review the [supplemental terms of use](https://azure.microsoft.com/en-us/support/legal/preview-supplemental-terms/) for preview features.

## Quick Start

### Using Bicep

```bash
# Clone the repository and navigate to the Bicep directory
cd bicep/

# Set required parameters
export LOCATION="eastus"
export RESOURCE_GROUP="rg-hybrid-postgres-demo"
export K8S_NAMESPACE="arc-data"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file main.bicep \
    --parameters @parameters.json
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
location = "eastus"
resource_group_name = "rg-hybrid-postgres-demo"
k8s_namespace = "arc-data"
admin_password = "P@ssw0rd123!"
EOF

# Deploy infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set environment variables
export LOCATION="eastus"
export RESOURCE_GROUP="rg-hybrid-postgres-demo"
export K8S_NAMESPACE="arc-data"

# Deploy infrastructure
./deploy.sh
```

## Architecture Overview

This infrastructure deploys a hybrid PostgreSQL database replication solution with the following components:

### Azure Resources

- **Azure Arc Data Controller**: Manages Arc-enabled data services on Kubernetes
- **Azure Database for PostgreSQL Flexible Server**: Cloud-based managed PostgreSQL
- **Azure Event Grid Topic**: Event-driven synchronization triggers
- **Azure Data Factory**: Orchestrates data pipeline and replication workflows
- **Azure Key Vault**: Secure storage for connection strings and credentials
- **Azure Monitor/Log Analytics**: Monitoring and alerting for hybrid environment

### On-Premises Components

- **Azure Arc-enabled PostgreSQL**: PostgreSQL running on Kubernetes with Arc management
- **Kubernetes Namespace**: Dedicated namespace for Arc data services
- **Monitoring Configuration**: PostgreSQL metrics collection and forwarding

## Configuration Options

### Bicep Parameters

Edit `parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": {
      "value": "eastus"
    },
    "postgresServerName": {
      "value": "azpg-hybrid-demo"
    },
    "adminUsername": {
      "value": "pgadmin"
    },
    "adminPassword": {
      "value": "P@ssw0rd123!"
    },
    "dataFactoryName": {
      "value": "adf-hybrid-demo"
    },
    "eventGridTopicName": {
      "value": "eg-topic-demo"
    },
    "keyVaultName": {
      "value": "kv-hybrid-demo"
    }
  }
}
```

### Terraform Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# Required variables
location = "eastus"
resource_group_name = "rg-hybrid-postgres-demo"
admin_password = "P@ssw0rd123!"

# Optional variables (defaults will be used if not specified)
postgres_server_name = "azpg-hybrid-demo"
admin_username = "pgadmin"
data_factory_name = "adf-hybrid-demo"
event_grid_topic_name = "eg-topic-demo"
key_vault_name = "kv-hybrid-demo"
k8s_namespace = "arc-data"
postgres_version = "14"
postgres_sku = "Standard_D2ds_v4"
storage_size_gb = 128
backup_retention_days = 7
```

## Post-Deployment Configuration

After infrastructure deployment, additional configuration is required:

### 1. Configure Kubernetes Arc Agent

```bash
# Connect your Kubernetes cluster to Azure Arc
az connectedk8s connect \
    --resource-group ${RESOURCE_GROUP} \
    --name ${K8S_CLUSTER_NAME}

# Install Arc data services extension
az k8s-extension create \
    --cluster-name ${K8S_CLUSTER_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --name arc-data-services \
    --cluster-type connectedClusters \
    --extension-type microsoft.arcdataservices \
    --auto-upgrade false \
    --scope cluster \
    --release-namespace arc \
    --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper
```

### 2. Deploy Arc Data Controller

```bash
# Create data controller using Azure CLI
az arcdata dc create \
    --resource-group ${RESOURCE_GROUP} \
    --name arc-dc-postgres \
    --location ${LOCATION} \
    --connectivity-mode indirect \
    --namespace ${K8S_NAMESPACE} \
    --subscription ${SUBSCRIPTION_ID}
```

### 3. Create Arc-enabled PostgreSQL Instance

```bash
# Deploy PostgreSQL server to Arc data controller
az postgres arc-server create \
    --name postgres-hybrid \
    --resource-group ${RESOURCE_GROUP} \
    --data-controller-name arc-dc-postgres \
    --cores-request 2 \
    --cores-limit 4 \
    --memory-request 4Gi \
    --memory-limit 8Gi \
    --storage-class-data default \
    --storage-class-logs default \
    --volume-size-data 50Gi \
    --volume-size-logs 10Gi
```

### 4. Configure Data Factory Pipeline

```bash
# Create and configure replication pipeline
az datafactory pipeline create \
    --factory-name ${DATA_FACTORY_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --name HybridPostgreSQLSync \
    --pipeline @pipeline-definition.json
```

## Monitoring and Troubleshooting

### Check Deployment Status

```bash
# Check Azure resources
az resource list \
    --resource-group ${RESOURCE_GROUP} \
    --output table

# Check Kubernetes resources
kubectl get all -n ${K8S_NAMESPACE}

# Check Arc data controller status
az arcdata dc status show \
    --resource-group ${RESOURCE_GROUP} \
    --name arc-dc-postgres
```

### View Logs

```bash
# Azure Data Factory logs
az datafactory pipeline-run show \
    --factory-name ${DATA_FACTORY_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --run-id <run-id>

# Kubernetes logs
kubectl logs -n ${K8S_NAMESPACE} -l app=postgresql

# Arc data controller logs
kubectl logs -n ${K8S_NAMESPACE} -l app=controller
```

### Common Issues

1. **Arc Data Controller Connection Issues**
   - Verify Kubernetes cluster connectivity
   - Check Azure Arc agent status
   - Ensure proper RBAC permissions

2. **PostgreSQL Deployment Failures**
   - Check resource quotas in Kubernetes
   - Verify storage class availability
   - Review Arc data controller logs

3. **Data Factory Pipeline Failures**
   - Validate connection strings in Key Vault
   - Check Event Grid topic permissions
   - Review pipeline activity logs

## Security Considerations

- All credentials are stored in Azure Key Vault
- Network security groups restrict database access
- Arc-enabled services use managed identities
- Data encryption in transit and at rest
- Least privilege access principles applied

## Cost Optimization

- Use Azure reservation discounts for predictable workloads
- Consider scaling down development environments
- Monitor Data Factory data movement costs
- Optimize PostgreSQL compute sizing based on usage
- Use lifecycle policies for log retention

## Validation & Testing

1. **Verify Arc Data Controller**:
   ```bash
   # Check Arc data controller status
   az arcdata dc list --resource-group ${RESOURCE_GROUP}
   
   # Verify Arc data controller pods
   kubectl get pods -n ${K8S_NAMESPACE} | grep controller
   ```

2. **Test Azure Database for PostgreSQL connectivity**:
   ```bash
   # Test connection to Azure PostgreSQL
   PGPASSWORD="P@ssw0rd123!" psql \
       -h ${AZURE_PG_NAME}.postgres.database.azure.com \
       -U pgadmin \
       -d postgres \
       -c "SELECT version();"
   ```

3. **Validate Data Factory pipeline execution**:
   ```bash
   # Trigger a test pipeline run
   az datafactory pipeline create-run \
       --factory-name ${ADF_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --name HybridPostgreSQLSync
   
   # Check pipeline run status
   az datafactory pipeline-run show \
       --factory-name ${ADF_NAME} \
       --resource-group ${RESOURCE_GROUP} \
       --run-id <run-id>
   ```

4. **Test end-to-end replication**:
   ```bash
   # Insert test data in Arc PostgreSQL
   kubectl exec -it postgres-hybrid-0 -n ${K8S_NAMESPACE} -- \
       psql -U postgres -c "
       CREATE TABLE IF NOT EXISTS test_replication (
         id SERIAL PRIMARY KEY,
         data TEXT,
         created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
       );
       INSERT INTO test_replication (data) VALUES ('Test replication data');
       "
   
   # Wait for sync and verify in Azure PostgreSQL
   sleep 30
   PGPASSWORD="P@ssw0rd123!" psql \
       -h ${AZURE_PG_NAME}.postgres.database.azure.com \
       -U pgadmin \
       -d postgres \
       -c "SELECT * FROM test_replication;"
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Navigate to scripts directory
cd scripts/

# Run cleanup script
./destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove resources:

```bash
# Remove Arc-enabled PostgreSQL instances
az postgres arc-server delete \
    --name postgres-hybrid \
    --resource-group ${RESOURCE_GROUP}

# Remove Arc data controller
az arcdata dc delete \
    --name arc-dc-postgres \
    --resource-group ${RESOURCE_GROUP} \
    --namespace ${K8S_NAMESPACE}

# Disconnect Kubernetes cluster from Arc
az connectedk8s delete \
    --resource-group ${RESOURCE_GROUP} \
    --name ${K8S_CLUSTER_NAME}

# Delete Kubernetes namespace
kubectl delete namespace ${K8S_NAMESPACE}
```

## Customization

### Adding Custom Monitoring

Extend the monitoring configuration by:

1. Adding custom metrics to the PostgreSQL configuration
2. Creating additional Azure Monitor alerts
3. Implementing custom dashboards in Azure Monitor workbooks
4. Integrating with third-party monitoring solutions

### Scaling the Solution

To scale for production environments:

1. **Multi-region deployment**: Deploy to multiple Azure regions
2. **High availability**: Configure zone-redundant PostgreSQL
3. **Load balancing**: Implement connection pooling
4. **Performance optimization**: Tune PostgreSQL parameters

### Integration with CI/CD

Integrate with Azure DevOps or GitHub Actions:

```yaml
# Example GitHub Actions workflow
name: Deploy Hybrid PostgreSQL Infrastructure

on:
  push:
    branches: [ main ]
    paths: [ 'infrastructure/**' ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Bicep template
      run: |
        az deployment group create \
          --resource-group ${{ secrets.RESOURCE_GROUP }} \
          --template-file infrastructure/bicep/main.bicep \
          --parameters @infrastructure/bicep/parameters.json
```

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Azure Arc documentation: https://docs.microsoft.com/en-us/azure/azure-arc/data/
3. Consult Azure Database for PostgreSQL documentation
4. Review Azure Data Factory troubleshooting guides
5. Check Kubernetes cluster logs and events

## Additional Resources

- [Azure Arc-enabled Data Services Documentation](https://docs.microsoft.com/en-us/azure/azure-arc/data/)
- [Azure Database for PostgreSQL Documentation](https://docs.microsoft.com/en-us/azure/postgresql/)
- [Azure Data Factory Documentation](https://docs.microsoft.com/en-us/azure/data-factory/)
- [Azure Event Grid Documentation](https://docs.microsoft.com/en-us/azure/event-grid/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)