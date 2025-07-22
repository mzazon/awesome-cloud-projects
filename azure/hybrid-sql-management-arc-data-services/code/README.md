# Infrastructure as Code for Hybrid SQL Management with Arc-enabled Data Services

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Hybrid SQL Management with Arc-enabled Data Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.25.0 or later installed and configured
- Kubernetes cluster (AKS, on-premises, or other cloud provider) with at least 4 vCPUs and 8GB RAM
- kubectl configured to access your Kubernetes cluster
- Azure Data Studio or SQL Server Management Studio for database management
- Appropriate Azure permissions (Owner or Contributor on subscription)
- Azure Arc data services CLI extension: `az extension add --name arcdata`

## Architecture Overview

This solution deploys:
- Azure Arc Data Controller on Kubernetes
- Azure Arc-enabled SQL Managed Instance
- Log Analytics Workspace for monitoring
- Azure Monitor integration with alerts and dashboards
- Security policies and governance controls

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group <resource-group-name> \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters sqlManagedInstanceName=sql-mi-arc \
    --parameters dataControllerName=arc-dc-controller
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
kubectl get pods -n arc --watch
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | eastus | Yes |
| `resourceGroupName` | Resource group name | rg-arc-data-services | Yes |
| `dataControllerName` | Arc Data Controller name | arc-dc-controller | Yes |
| `sqlManagedInstanceName` | SQL Managed Instance name | sql-mi-arc | Yes |
| `logAnalyticsWorkspaceName` | Log Analytics workspace name | law-arc-monitoring | Yes |
| `kubernetesNamespace` | Kubernetes namespace | arc | No |

### SQL Managed Instance Configuration

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `sqlCoresRequest` | CPU cores requested | 2 | No |
| `sqlCoresLimit` | CPU cores limit | 4 | No |
| `sqlMemoryRequest` | Memory requested | 2Gi | No |
| `sqlMemoryLimit` | Memory limit | 4Gi | No |
| `sqlStorageClassData` | Storage class for data | default | No |
| `sqlStorageClassLogs` | Storage class for logs | default | No |
| `sqlVolumeSizeData` | Data volume size | 5Gi | No |
| `sqlVolumeSizeLogs` | Log volume size | 5Gi | No |
| `sqlTier` | Service tier | GeneralPurpose | No |

## Post-Deployment Steps

### 1. Verify Deployment

```bash
# Check Azure Arc Data Controller status
az arcdata dc status show \
    --resource-group <resource-group-name> \
    --name <data-controller-name>

# Verify Kubernetes resources
kubectl get pods -n arc
kubectl get services -n arc
```

### 2. Connect to SQL Managed Instance

```bash
# Get SQL Managed Instance endpoint
az sql mi-arc show \
    --resource-group <resource-group-name> \
    --name <sql-mi-name> \
    --query status.endpoints.primary

# Connect using Azure Data Studio or sqlcmd
# Default credentials are set during deployment
```

### 3. Configure Monitoring

```bash
# View monitoring dashboard in Azure Portal
az monitor app-insights workbook list \
    --resource-group <resource-group-name>

# Check Log Analytics workspace
az monitor log-analytics workspace show \
    --resource-group <resource-group-name> \
    --workspace-name <workspace-name>
```

## Monitoring and Alerting

The deployment includes:

- **Log Analytics Workspace**: Centralized logging and monitoring
- **Azure Monitor Integration**: Metrics and performance monitoring
- **Alert Rules**: 
  - High CPU utilization (>80%)
  - Low storage space (>85% used)
  - Failed connections
- **Action Groups**: Email notifications for alerts
- **Monitoring Workbook**: Custom dashboard for Arc SQL metrics

### View Monitoring Data

```bash
# Query Log Analytics for Arc data
az monitor log-analytics query \
    --workspace <workspace-id> \
    --analytics-query "AzureActivity | where ResourceProvider == 'Microsoft.AzureArcData' | take 10"

# Check metrics
az monitor metrics list \
    --resource "/subscriptions/<subscription-id>/resourceGroups/<rg>/providers/Microsoft.AzureArcData/sqlManagedInstances/<sql-mi-name>" \
    --metric-names "Percentage CPU"
```

## Security Considerations

### Default Security Features

- **Azure Policy**: Enforces security and compliance standards
- **RBAC**: Role-based access control integration
- **Network Security**: Kubernetes network policies
- **Encryption**: Data at rest and in transit encryption
- **Authentication**: Azure AD integration support

### Security Best Practices

1. **Use Azure Key Vault** for secrets management
2. **Enable network policies** in Kubernetes
3. **Configure firewall rules** for SQL Managed Instance
4. **Regular security updates** for Arc agents
5. **Monitor security events** through Azure Monitor

## Troubleshooting

### Common Issues

1. **Arc Data Controller Not Ready**
   ```bash
   # Check pod status and logs
   kubectl get pods -n arc
   kubectl logs -n arc deployment/controller
   ```

2. **SQL Managed Instance Connection Issues**
   ```bash
   # Verify service endpoints
   kubectl get services -n arc
   kubectl describe service <sql-mi-service> -n arc
   ```

3. **Monitoring Data Not Flowing**
   ```bash
   # Check Log Analytics configuration
   az monitor log-analytics workspace show \
       --resource-group <rg> \
       --workspace-name <workspace>
   ```

### Log Collection

```bash
# Collect Arc data services logs
az arcdata dc export \
    --resource-group <resource-group-name> \
    --name <data-controller-name> \
    --type logs \
    --path ./arc-logs

# Kubernetes cluster logs
kubectl logs -n arc --selector=app.kubernetes.io/name=controller
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name <resource-group-name> \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Clean up Terraform state
rm -rf .terraform*
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
kubectl get pods -n arc
az group show --name <resource-group-name>
```

### Manual Cleanup Steps

If automated cleanup fails:

```bash
# Remove SQL Managed Instance
az sql mi-arc delete \
    --resource-group <resource-group-name> \
    --name <sql-mi-name> \
    --yes

# Remove Arc Data Controller
az arcdata dc delete \
    --resource-group <resource-group-name> \
    --name <data-controller-name> \
    --yes

# Clean Kubernetes namespace
kubectl delete namespace arc

# Remove Azure resources
az group delete \
    --name <resource-group-name> \
    --yes
```

## Customization

### Environment Variables

Set these environment variables before deployment:

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_RESOURCE_GROUP="your-resource-group"
export AZURE_LOCATION="eastus"
export SQL_ADMIN_USERNAME="arcadmin"
export SQL_ADMIN_PASSWORD="YourSecurePassword123!"
export KUBERNETES_NAMESPACE="arc"
```

### Custom Configuration

1. **Storage Classes**: Modify storage class parameters in the configuration files
2. **Resource Limits**: Adjust CPU and memory limits based on your requirements
3. **Monitoring**: Customize alert thresholds and notification channels
4. **Security**: Add additional security policies and compliance rules

## Cost Optimization

### Resource Sizing

- **Development**: 2 vCPU, 4GB RAM, 5GB storage
- **Testing**: 4 vCPU, 8GB RAM, 10GB storage
- **Production**: 8+ vCPU, 16+ GB RAM, 100+ GB storage

### Cost Monitoring

```bash
# View cost analysis
az consumption usage list \
    --start-date 2025-01-01 \
    --end-date 2025-01-31

# Set up budget alerts
az consumption budget create \
    --budget-name "arc-sql-budget" \
    --amount 100 \
    --time-grain Monthly \
    --time-period start-date=2025-01-01
```

## Support and Resources

- **Azure Arc Documentation**: https://docs.microsoft.com/en-us/azure/azure-arc/
- **Azure Arc Data Services**: https://docs.microsoft.com/en-us/azure/azure-arc/data/
- **Azure Monitor**: https://docs.microsoft.com/en-us/azure/azure-monitor/
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Azure CLI Reference**: https://docs.microsoft.com/en-us/cli/azure/

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Tested with**: 
  - Azure CLI v2.25.0+
  - Kubernetes v1.21+
  - Azure Arc Data Services extension v1.0+

For issues with this infrastructure code, refer to the original recipe documentation or the Azure Arc Data Services documentation.