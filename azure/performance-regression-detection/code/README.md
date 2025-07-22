# Infrastructure as Code for Performance Regression Detection with Load Testing and Monitor Workbooks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Performance Regression Detection with Load Testing and Monitor Workbooks".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template successor)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI version 2.60 or later installed and configured
- Azure subscription with Owner or Contributor access
- Azure DevOps organization with project administrator privileges
- Basic understanding of performance testing concepts
- For Terraform: Terraform v1.0+ installed
- For Bicep: Azure CLI with Bicep extension installed

## Cost Considerations

Estimated monthly cost: $50-100 based on:
- Azure Load Testing usage frequency
- Container Apps compute consumption
- Log Analytics workspace data ingestion
- Azure Monitor alert rules

## Quick Start

### Using Bicep

Deploy the complete infrastructure using Azure's native IaC language:

```bash
# Navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-perftest \
    --template-file main.bicep \
    --parameters location=eastus \
                 environmentSuffix=demo \
                 containerImageName=nginx:latest

# Monitor deployment status
az deployment group show \
    --resource-group rg-perftest \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

Deploy using the industry-standard multi-cloud IaC tool:

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="location=eastus" \
               -var="environment_suffix=demo"

# Apply the infrastructure
terraform apply -var="location=eastus" \
                -var="environment_suffix=demo"

# View outputs
terraform output
```

### Using Bash Scripts

Use the automated deployment scripts for quick setup:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with interactive prompts
./scripts/deploy.sh

# Or deploy with environment variables
RESOURCE_GROUP="rg-perftest-demo" \
LOCATION="eastus" \
ENVIRONMENT_SUFFIX="demo" \
./scripts/deploy.sh
```

## Architecture Components

This infrastructure deployment creates:

### Core Resources
- **Azure Load Testing**: Managed service for high-scale performance testing
- **Azure Container Apps Environment**: Serverless container hosting platform
- **Azure Container Registry**: Private container image registry
- **Log Analytics Workspace**: Centralized logging and analytics
- **Azure Monitor Workbook**: Performance visualization dashboard

### Monitoring & Alerting
- **Application Insights**: Application performance monitoring
- **Alert Rules**: Automated regression detection
- **Action Groups**: Notification and remediation workflows

### Security Components
- **Managed Identity**: Secure service-to-service authentication
- **Role Assignments**: Least privilege access controls
- **Key Vault**: Secure secrets management (optional)

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environmentSuffix` | string | `demo` | Suffix for unique resource naming |
| `containerImageName` | string | `nginx:latest` | Container image for demo application |
| `loadTestEngineInstances` | int | `1` | Number of load testing engine instances |
| `containerAppMinReplicas` | int | `1` | Minimum container app replicas |
| `containerAppMaxReplicas` | int | `5` | Maximum container app replicas |
| `logRetentionDays` | int | `30` | Log Analytics retention period |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `location` | string | `eastus` | Azure region for resource deployment |
| `environment_suffix` | string | `demo` | Suffix for unique resource naming |
| `resource_group_name` | string | `rg-perftest` | Resource group name |
| `container_image` | string | `nginx:latest` | Container image for demo application |
| `load_test_instances` | number | `1` | Number of load testing engine instances |
| `container_cpu` | number | `0.5` | Container CPU allocation |
| `container_memory` | string | `1.0Gi` | Container memory allocation |

### Environment Variables (Bash Scripts)

| Variable | Default | Description |
|----------|---------|-------------|
| `RESOURCE_GROUP` | `rg-perftest-${RANDOM}` | Resource group name |
| `LOCATION` | `eastus` | Azure region |
| `ENVIRONMENT_SUFFIX` | `demo` | Resource naming suffix |
| `CONTAINER_IMAGE` | `nginx:latest` | Demo application image |
| `SUBSCRIPTION_ID` | Auto-detected | Azure subscription ID |

## Post-Deployment Setup

After infrastructure deployment, complete these configuration steps:

### 1. Configure Azure DevOps Integration

```bash
# Create service connection in Azure DevOps
az devops service-endpoint azurerm create \
    --azure-rm-service-principal-id $(terraform output -raw client_id) \
    --azure-rm-subscription-id $(terraform output -raw subscription_id) \
    --azure-rm-tenant-id $(terraform output -raw tenant_id) \
    --name "LoadTestConnection"
```

### 2. Upload Load Test Configuration

```bash
# Get load testing resource name
LOAD_TEST_NAME=$(terraform output -raw load_test_name)

# Upload test configuration
az load test create \
    --load-test-resource $LOAD_TEST_NAME \
    --resource-group $(terraform output -raw resource_group_name) \
    --test-id performance-baseline \
    --display-name "Performance Regression Test" \
    --description "Automated performance regression detection" \
    --test-plan loadtest.jmx \
    --engine-instances 1
```

### 3. Configure Pipeline Variables

Set these variables in your Azure DevOps pipeline:

- `LOAD_TEST_NAME`: Output from deployment
- `RESOURCE_GROUP`: Resource group name
- `APP_URL`: Container app URL from outputs
- `WORKSPACE_ID`: Log Analytics workspace ID

## Monitoring and Alerts

### Performance Metrics Dashboard

Access the Azure Monitor Workbook:

```bash
# Get workbook URL
az monitor app-insights workbook show \
    --resource-group $(terraform output -raw resource_group_name) \
    --name "Performance Regression Dashboard" \
    --query properties.workbookId
```

### Alert Configuration

The deployment creates these alert rules:

1. **Response Time Regression**: Triggers when average response time exceeds 500ms
2. **Error Rate Regression**: Triggers when error rate exceeds 5%
3. **Resource Utilization**: Monitors container resource consumption

### Custom Queries

Use these Kusto queries in Log Analytics:

```kql
// Performance trend analysis
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(24h)
| summarize AvgResponseTime = avg(todouble(Properties_s.duration)) by bin(TimeGenerated, 5m)
| render timechart

// Error rate monitoring
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| summarize ErrorRate = countif(Properties_s.status >= 400) * 100.0 / count() by bin(TimeGenerated, 5m)
| render timechart
```

## Troubleshooting

### Common Issues

1. **Deployment Failures**
   - Verify Azure CLI authentication: `az account show`
   - Check subscription permissions
   - Ensure unique resource names

2. **Load Test Execution Issues**
   - Verify network connectivity to target application
   - Check Container Apps service status
   - Review load test configuration

3. **Monitoring Data Missing**
   - Confirm Application Insights configuration
   - Verify Log Analytics workspace connection
   - Check data ingestion delays (5-10 minutes normal)

### Diagnostic Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group $RESOURCE_GROUP \
    --name main \
    --query properties.provisioningState

# Verify container app status
az containerapp show \
    --name $(terraform output -raw container_app_name) \
    --resource-group $(terraform output -raw resource_group_name) \
    --query properties.runningStatus

# Check load testing resource
az load show \
    --name $(terraform output -raw load_test_name) \
    --resource-group $(terraform output -raw resource_group_name) \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-perftest \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all infrastructure
terraform destroy -var="location=eastus" \
                  -var="environment_suffix=demo"

# Verify destruction
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify resource deletion
az group exists --name $RESOURCE_GROUP
```

### Manual Cleanup Verification

```bash
# List remaining resources (should be empty)
az resource list \
    --resource-group $RESOURCE_GROUP \
    --output table

# Check for orphaned resources
az resource list \
    --tag purpose=performance-testing \
    --output table
```

## Customization

### Scaling Configuration

Modify these parameters to adjust performance and cost:

- **Load Test Scale**: Increase `loadTestEngineInstances` for higher load generation
- **Container Scale**: Adjust `containerAppMaxReplicas` for traffic handling
- **Monitoring Retention**: Change `logRetentionDays` for cost optimization

### Security Hardening

Additional security configurations available:

- Enable Azure Key Vault for secrets management
- Configure private endpoints for Container Registry
- Implement network security groups for traffic filtering
- Enable Azure Security Center monitoring

### Integration Extensions

Extend the solution with:

- Azure Chaos Studio for resilience testing
- Azure Application Gateway for advanced routing
- Azure API Management for API performance testing
- Azure Machine Learning for intelligent baseline management

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service status at [Azure Status](https://status.azure.com/)
3. Consult Azure documentation:
   - [Azure Load Testing](https://docs.microsoft.com/en-us/azure/load-testing/)
   - [Azure Container Apps](https://docs.microsoft.com/en-us/azure/container-apps/)
   - [Azure Monitor Workbooks](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)

## Version Information

- Recipe Version: 1.0
- Bicep Language Version: Latest stable
- Terraform Azure Provider: ~> 3.0
- Azure CLI Minimum Version: 2.60+
- Last Updated: 2025-07-12