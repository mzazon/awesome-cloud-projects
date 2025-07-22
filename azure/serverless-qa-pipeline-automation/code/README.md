# Infrastructure as Code for Serverless QA Pipeline Automation with Container Apps and Load Testing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless QA Pipeline Automation with Container Apps and Load Testing".

## Overview

This solution demonstrates how to build comprehensive automated quality assurance pipelines using Azure Container Apps Jobs for orchestrating containerized testing workflows and Azure Load Testing for scalable performance validation. The infrastructure includes multiple testing job types, monitoring integration, and CI/CD pipeline automation.

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Architecture

The solution deploys:
- Azure Container Apps Environment with Log Analytics integration
- Multiple Container Apps Jobs for different testing scenarios
- Azure Load Testing resource for performance validation
- Azure Storage Account for test artifacts and results
- Azure Monitor integration for comprehensive observability

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure subscription with appropriate permissions for Container Apps, Load Testing, and Monitor services
- Docker Desktop installed for local container development and testing
- Azure DevOps organization with project access (for CI/CD integration)
- Basic understanding of containerization, testing frameworks, and CI/CD pipelines

### Required Azure Permissions

- Contributor role on the target subscription or resource group
- Container Apps Environment Administrator role
- Load Testing Contributor role
- Log Analytics Contributor role
- Storage Account Contributor role

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Create resource group
az group create --name rg-qa-pipeline --location eastus

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-qa-pipeline \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-qa-pipeline \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment (check created resources)
az resource list --resource-group rg-qa-pipeline --output table
```

## Configuration Options

### Bicep Parameters

The `parameters.json` file contains customizable values:

```json
{
  "environmentName": {
    "value": "qa-pipeline-demo"
  },
  "location": {
    "value": "eastus"
  },
  "containerEnvironmentName": {
    "value": "cae-qa-pipeline"
  },
  "logAnalyticsWorkspaceName": {
    "value": "law-qa-pipeline"
  },
  "loadTestingResourceName": {
    "value": "lt-qa-pipeline"
  },
  "storageAccountPrefix": {
    "value": "stqa"
  }
}
```

### Terraform Variables

Customize the deployment by modifying `terraform.tfvars`:

```hcl
resource_group_name = "rg-qa-pipeline"
location = "eastus"
environment_name = "qa-pipeline-demo"
container_environment_name = "cae-qa-pipeline"
log_analytics_workspace_name = "law-qa-pipeline"
load_testing_resource_name = "lt-qa-pipeline"
storage_account_prefix = "stqa"
```

### Bash Script Configuration

Edit the environment variables at the top of `deploy.sh`:

```bash
# Configuration variables
export RESOURCE_GROUP="rg-qa-pipeline"
export LOCATION="eastus"
export ENVIRONMENT_NAME="qa-pipeline-demo"
export CONTAINER_ENV_NAME="cae-qa-pipeline"
export LOG_ANALYTICS_NAME="law-qa-pipeline"
export LOAD_TEST_NAME="lt-qa-pipeline"
export STORAGE_ACCOUNT_PREFIX="stqa"
```

## Post-Deployment Steps

### 1. Configure Container Apps Jobs

After deployment, configure your testing jobs with appropriate container images:

```bash
# Update unit test job with your testing image
az containerapp job update \
    --name unit-test-job \
    --resource-group rg-qa-pipeline \
    --image youracr.azurecr.io/unit-tests:latest

# Update integration test job
az containerapp job update \
    --name integration-test-job \
    --resource-group rg-qa-pipeline \
    --image youracr.azurecr.io/integration-tests:latest
```

### 2. Upload Load Testing Scripts

```bash
# Create JMeter test scripts and upload to storage
az storage blob upload \
    --file your-load-test.jmx \
    --name load-test-scripts/performance-test.jmx \
    --container-name load-test-scripts \
    --account-name $(terraform output -raw storage_account_name)
```

### 3. Configure Azure DevOps Integration

Import the provided pipeline template (`azure-pipelines-qa.yml`) into your Azure DevOps project and configure the service connection.

## Testing the Deployment

### 1. Verify Container Apps Environment

```bash
# Check environment status
az containerapp env show \
    --name cae-qa-pipeline \
    --resource-group rg-qa-pipeline \
    --query '{name:name,location:location,provisioningState:provisioningState}'
```

### 2. Test Job Execution

```bash
# Start a test job manually
az containerapp job start \
    --name unit-test-job \
    --resource-group rg-qa-pipeline

# Monitor job execution
az containerapp job execution list \
    --name unit-test-job \
    --resource-group rg-qa-pipeline \
    --query '[0].{status:status,startTime:startTime,endTime:endTime}'
```

### 3. Verify Load Testing Resource

```bash
# Check load testing resource
az load show \
    --name lt-qa-pipeline \
    --resource-group rg-qa-pipeline \
    --query '{name:name,location:location,provisioningState:provisioningState}'
```

## Monitoring and Observability

### Azure Monitor Integration

The deployment includes Log Analytics workspace integration for comprehensive monitoring:

```bash
# Query recent container app logs
az monitor log-analytics query \
    --workspace $(terraform output -raw log_analytics_workspace_id) \
    --analytics-query "ContainerAppConsoleLogs_CL | where TimeGenerated > ago(1h) | take 10"
```

### Performance Metrics

Access performance metrics through Azure Monitor:

```bash
# Get job execution metrics
az monitor metrics list \
    --resource $(terraform output -raw container_environment_id) \
    --metric "JobExecutions" \
    --start-time 2024-01-01T00:00:00Z \
    --end-time 2024-01-01T23:59:59Z
```

## Scaling and Optimization

### Job Scaling Configuration

Modify job parallelism and resource allocation:

```bash
# Update job resource allocation
az containerapp job update \
    --name performance-test-job \
    --resource-group rg-qa-pipeline \
    --parallelism 5 \
    --cpu 2.0 \
    --memory 4Gi
```

### Cost Optimization

- Use consumption-based pricing for Container Apps Jobs
- Configure appropriate timeout values to avoid unnecessary costs
- Monitor job execution patterns and optimize resource allocation
- Use Azure Cost Management for cost tracking and optimization

## Security Best Practices

### Identity and Access Management

The infrastructure implements several security best practices:

- Managed identities for service-to-service authentication
- Role-based access control (RBAC) for resource access
- Network security groups for traffic control
- Secrets management through Azure Key Vault integration

### Network Security

```bash
# Configure network security if needed
az containerapp env update \
    --name cae-qa-pipeline \
    --resource-group rg-qa-pipeline \
    --internal-only true
```

## Troubleshooting

### Common Issues

1. **Job Execution Failures**
   ```bash
   # Check job execution logs
   az containerapp job execution show \
       --name unit-test-job \
       --resource-group rg-qa-pipeline \
       --job-execution-name <execution-name>
   ```

2. **Container Apps Environment Issues**
   ```bash
   # Check environment health
   az containerapp env show \
       --name cae-qa-pipeline \
       --resource-group rg-qa-pipeline \
       --query properties.provisioningState
   ```

3. **Load Testing Resource Problems**
   ```bash
   # Verify load testing resource status
   az load show \
       --name lt-qa-pipeline \
       --resource-group rg-qa-pipeline \
       --query properties.provisioningState
   ```

### Debug Commands

```bash
# Enable debug logging for Azure CLI
export AZURE_CLI_DEBUG=1

# Check resource group resources
az resource list \
    --resource-group rg-qa-pipeline \
    --output table

# Verify role assignments
az role assignment list \
    --resource-group rg-qa-pipeline \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-qa-pipeline \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
az resource list \
    --resource-group rg-qa-pipeline \
    --output table
```

## Estimated Costs

### Monthly Cost Breakdown (Development/Testing)

- **Container Apps Jobs**: $20-40/month (based on execution time)
- **Azure Load Testing**: $15-30/month (based on test runs)
- **Log Analytics Workspace**: $10-20/month (based on data ingestion)
- **Storage Account**: $5-10/month (based on artifact storage)
- **Azure Monitor**: $5-15/month (based on metrics and alerts)

**Total Estimated Monthly Cost**: $55-115 for development/testing workloads

### Production Considerations

- Costs will scale with test frequency and complexity
- Consider Azure Reserved Instances for predictable workloads
- Use Azure Cost Management for monitoring and optimization
- Implement automatic cleanup of old test artifacts

## Support and Resources

### Official Documentation

- [Azure Container Apps Jobs Documentation](https://docs.microsoft.com/en-us/azure/container-apps/jobs)
- [Azure Load Testing Documentation](https://docs.microsoft.com/en-us/azure/load-testing/)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

### Best Practices

- [Container Apps Best Practices](https://docs.microsoft.com/en-us/azure/container-apps/jobs-best-practices)
- [Azure Load Testing Best Practices](https://docs.microsoft.com/en-us/azure/load-testing/concept-load-testing-concepts)
- [Azure DevOps Integration Patterns](https://docs.microsoft.com/en-us/azure/devops/pipelines/)

### Community Resources

- [Azure Container Apps GitHub Repository](https://github.com/microsoft/azure-container-apps)
- [Azure Load Testing Samples](https://github.com/Azure-Samples/azure-load-testing-samples)

## Contributing

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.

## License

This infrastructure code is provided under the same license as the parent repository.