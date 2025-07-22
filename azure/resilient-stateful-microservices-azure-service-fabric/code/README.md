# Infrastructure as Code for Resilient Stateful Microservices with Azure Service Fabric and Durable Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resilient Stateful Microservices with Azure Service Fabric and Durable Functions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- .NET 6.0 SDK or later for Service Fabric development
- Visual Studio 2022 or Visual Studio Code with Azure extensions
- Understanding of microservices architecture and distributed systems concepts
- Estimated cost: $50-100 per day for development environment

### Required Azure Permissions

- Contributor or Owner role on the subscription
- Service Fabric Cluster Administrator role
- SQL Server Contributor role
- Storage Account Contributor role
- Application Insights Component Contributor role

## Quick Start

### Using Bicep

```bash
# Navigate to Bicep directory
cd bicep/

# Create resource group
az group create --name rg-microservices-orchestration --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-microservices-orchestration \
    --template-file main.bicep \
    --parameters @parameters.json

# Monitor deployment
az deployment group show \
    --resource-group rg-microservices-orchestration \
    --name main
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Monitor deployment status
az group show --name rg-microservices-orchestration --query "properties.provisioningState"
```

## Architecture Overview

This implementation deploys:

- **Azure Service Fabric Cluster** (3 nodes) with Windows Server 2019
- **Azure SQL Database** for state management and persistence
- **Azure Function App** with Durable Functions for workflow orchestration
- **Azure Storage Account** for Durable Functions state and telemetry
- **Application Insights** for monitoring and distributed tracing
- **Azure Key Vault** for certificate and secret management

## Configuration Parameters

### Bicep Parameters

```json
{
  "resourceGroupName": {
    "value": "rg-microservices-orchestration"
  },
  "location": {
    "value": "eastus"
  },
  "clusterName": {
    "value": "sf-cluster-demo"
  },
  "sqlServerName": {
    "value": "sql-orchestration-demo"
  },
  "functionAppName": {
    "value": "func-orchestrator-demo"
  },
  "storageAccountName": {
    "value": "storchestrationdemo"
  },
  "appInsightsName": {
    "value": "ai-orchestration-demo"
  },
  "sqlAdminUsername": {
    "value": "sqladmin"
  },
  "sqlAdminPassword": {
    "value": "ComplexPassword123!"
  },
  "certificatePassword": {
    "value": "CertPassword123!"
  }
}
```

### Terraform Variables

```hcl
# terraform.tfvars
resource_group_name = "rg-microservices-orchestration"
location           = "eastus"
cluster_name       = "sf-cluster-demo"
sql_server_name    = "sql-orchestration-demo"
function_app_name  = "func-orchestrator-demo"
storage_account_name = "storchestrationdemo"
app_insights_name  = "ai-orchestration-demo"
sql_admin_username = "sqladmin"
sql_admin_password = "ComplexPassword123!"
certificate_password = "CertPassword123!"
```

## Post-Deployment Steps

### 1. Deploy Service Fabric Application

```bash
# Package and deploy the microservices application
az sf application upload \
    --path ./ServiceFabricApp \
    --cluster-endpoint https://$(terraform output -raw cluster_fqdn):19080 \
    --application-type-name MicroservicesApp \
    --application-type-version 1.0.0

# Create application instance
az sf application create \
    --cluster-endpoint https://$(terraform output -raw cluster_fqdn):19080 \
    --application-name fabric:/MicroservicesApp \
    --application-type-name MicroservicesApp \
    --application-type-version 1.0.0
```

### 2. Deploy Durable Functions

```bash
# Build and deploy the Durable Functions orchestrator
cd DurableFunctionsOrchestrator/
dotnet build
dotnet publish -c Release

# Deploy to Function App
az functionapp deployment source config-zip \
    --resource-group rg-microservices-orchestration \
    --name $(terraform output -raw function_app_name) \
    --src bin/Release/net6.0/publish.zip
```

### 3. Configure Application Settings

```bash
# Set Function App configuration
az functionapp config appsettings set \
    --name $(terraform output -raw function_app_name) \
    --resource-group rg-microservices-orchestration \
    --settings \
    "SqlConnectionString=$(terraform output -raw sql_connection_string)" \
    "ServiceFabricConnectionString=https://$(terraform output -raw cluster_fqdn):19080" \
    "APPINSIGHTS_INSTRUMENTATIONKEY=$(terraform output -raw app_insights_key)"
```

## Monitoring and Validation

### Health Checks

```bash
# Verify Service Fabric cluster health
az sf cluster show \
    --resource-group rg-microservices-orchestration \
    --name $(terraform output -raw cluster_name) \
    --query "clusterState"

# Check Function App status
az functionapp show \
    --name $(terraform output -raw function_app_name) \
    --resource-group rg-microservices-orchestration \
    --query "state"

# Validate SQL Database connectivity
az sql db show \
    --resource-group rg-microservices-orchestration \
    --server $(terraform output -raw sql_server_name) \
    --name MicroservicesState \
    --query "status"
```

### Testing the Workflow

```bash
# Test order processing workflow
FUNCTION_URL=$(az functionapp show \
    --name $(terraform output -raw function_app_name) \
    --resource-group rg-microservices-orchestration \
    --query "defaultHostName" --output tsv)

curl -X POST "https://${FUNCTION_URL}/api/OrderProcessingOrchestrator" \
    -H "Content-Type: application/json" \
    -d '{
        "OrderId": "ORD-001",
        "CustomerId": "CUST-123",
        "Amount": 99.99,
        "ProductId": "PROD-456",
        "Quantity": 2
    }'
```

### Monitoring Queries

```bash
# Query Application Insights for workflow metrics
az monitor app-insights query \
    --app $(terraform output -raw app_insights_name) \
    --analytics-query "traces | where message contains 'Order' | order by timestamp desc | take 20"

# Monitor Service Fabric service health
az sf service list \
    --cluster-endpoint https://$(terraform output -raw cluster_fqdn):19080 \
    --application-name fabric:/MicroservicesApp
```

## Cleanup

### Using Bicep

```bash
# Delete resource group (removes all resources)
az group delete \
    --name rg-microservices-orchestration \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -auto-approve

# Clean up state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
az group show --name rg-microservices-orchestration --query "properties.provisioningState" || echo "Resource group not found"
```

## Customization

### Scaling Configuration

Modify the following parameters to adjust scaling:

```hcl
# Service Fabric cluster size
variable "cluster_size" {
  description = "Number of nodes in the Service Fabric cluster"
  type        = number
  default     = 3
}

# SQL Database performance tier
variable "sql_sku" {
  description = "SQL Database SKU"
  type        = string
  default     = "S1"
}

# Function App plan
variable "function_app_plan_sku" {
  description = "App Service Plan SKU for Function App"
  type        = string
  default     = "Y1"  # Consumption plan
}
```

### Security Configuration

```hcl
# Enable advanced security features
variable "enable_sql_threat_detection" {
  description = "Enable SQL threat detection"
  type        = bool
  default     = true
}

variable "enable_service_fabric_reverse_proxy" {
  description = "Enable Service Fabric reverse proxy"
  type        = bool
  default     = false
}

variable "enable_app_insights_profiler" {
  description = "Enable Application Insights profiler"
  type        = bool
  default     = false
}
```

### Cost Optimization

```hcl
# Use spot instances for development
variable "use_spot_instances" {
  description = "Use spot instances for Service Fabric nodes"
  type        = bool
  default     = false
}

# Auto-pause SQL Database
variable "sql_auto_pause_delay" {
  description = "Auto-pause delay for SQL Database in minutes"
  type        = number
  default     = 60
}
```

## Troubleshooting

### Common Issues

1. **Service Fabric Cluster Creation Fails**
   - Check subscription limits for VM cores
   - Verify certificate configuration
   - Ensure proper network security group rules

2. **Function App Deployment Issues**
   - Verify storage account accessibility
   - Check Application Insights configuration
   - Validate connection strings

3. **SQL Database Connection Problems**
   - Verify firewall rules
   - Check authentication credentials
   - Validate network connectivity

### Debug Commands

```bash
# Check deployment logs
az deployment group show \
    --resource-group rg-microservices-orchestration \
    --name main \
    --query "properties.error"

# View Service Fabric events
az sf cluster events \
    --cluster-endpoint https://$(terraform output -raw cluster_fqdn):19080 \
    --start-time-utc "2024-01-01T00:00:00Z" \
    --end-time-utc "2024-12-31T23:59:59Z"

# Check Function App logs
az functionapp log tail \
    --name $(terraform output -raw function_app_name) \
    --resource-group rg-microservices-orchestration
```

## Cost Estimation

### Development Environment (Daily)
- Service Fabric Cluster (3 x D2s_v3): ~$30-40
- SQL Database (S1): ~$5-10
- Function App (Consumption): ~$0-5
- Storage Account: ~$1-2
- Application Insights: ~$1-2
- **Total: ~$37-59 per day**

### Production Environment (Monthly)
- Service Fabric Cluster (5 x D4s_v3): ~$500-700
- SQL Database (Premium): ~$150-300
- Function App (Premium): ~$50-100
- Storage Account: ~$20-50
- Application Insights: ~$50-100
- **Total: ~$770-1,250 per month**

## Best Practices

1. **Security**: Use Azure Key Vault for certificate management
2. **Monitoring**: Enable Application Insights for all services
3. **Networking**: Implement proper network security groups
4. **Backup**: Configure SQL Database backup policies
5. **Scaling**: Use autoscaling for Function Apps
6. **Cost**: Monitor resource usage and optimize accordingly

## Support

For issues with this infrastructure code:
- Review the original recipe documentation
- Check Azure Service Fabric documentation
- Consult Azure Durable Functions documentation
- Review Application Insights troubleshooting guides

## Additional Resources

- [Azure Service Fabric Documentation](https://docs.microsoft.com/en-us/azure/service-fabric/)
- [Azure Durable Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/durable/)
- [Azure SQL Database Documentation](https://docs.microsoft.com/en-us/azure/azure-sql/database/)
- [Application Insights Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)