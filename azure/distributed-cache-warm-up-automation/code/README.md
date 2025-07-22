# Infrastructure as Code for Distributed Cache Warm-up Automation with Container Apps Jobs and Redis Enterprise

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Distributed Cache Warm-up Automation with Container Apps Jobs and Redis Enterprise".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Appropriate Azure permissions for resource creation:
  - Container Apps Environment management
  - Redis Enterprise cluster creation
  - Storage Account and Key Vault access
  - Log Analytics workspace management
  - Azure Monitor configuration
- Docker installed for local container image building (if customizing images)
- Estimated cost: $150-300/month for Redis Enterprise cluster and Container Apps environment

## Architecture Overview

This solution implements an automated distributed cache warm-up system using:

- **Azure Container Apps Jobs**: Serverless container orchestration for finite workloads
- **Azure Redis Enterprise**: High-performance enterprise-grade caching
- **Azure Storage Account**: Configuration and job coordination storage
- **Azure Key Vault**: Secure secret management
- **Azure Monitor**: Comprehensive observability and alerting

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Review and customize parameters
cp parameters.json.example parameters.json
# Edit parameters.json with your values

# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az containerapp env list --resource-group <your-resource-group>
az redis list --resource-group <your-resource-group>
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
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

# Review and customize variables in deploy.sh
# Edit scripts/deploy.sh to set your preferred values

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor deployment progress
# The script will provide status updates during deployment
```

## Configuration

### Bicep Parameters

Key parameters to customize in `parameters.json`:

```json
{
  "location": "eastus",
  "environmentPrefix": "cache-warmup",
  "redisSkuName": "Enterprise",
  "redisSkuFamily": "E",
  "redisSkuCapacity": 10,
  "containerJobSchedule": "0 */6 * * *",
  "containerJobParallelism": 4,
  "tags": {
    "purpose": "cache-warmup",
    "environment": "production"
  }
}
```

### Terraform Variables

Key variables to customize in `terraform.tfvars`:

```hcl
location = "East US"
environment_prefix = "cache-warmup"
redis_sku_name = "Enterprise"
redis_family = "E"
redis_capacity = 10
cron_schedule = "0 */6 * * *"
job_parallelism = 4

tags = {
  purpose = "cache-warmup"
  environment = "production"
}
```

### Bash Script Variables

Customize these variables in `scripts/deploy.sh`:

```bash
LOCATION="eastus"
REDIS_SKU="Enterprise"
REDIS_CAPACITY="10"
CONTAINER_JOB_SCHEDULE="0 */6 * * *"
WORKER_PARALLELISM="4"
```

## Post-Deployment Configuration

After infrastructure deployment, you'll need to:

1. **Build and Deploy Container Images**:
   ```bash
   # Build coordinator image
   docker build -f Dockerfile.coordinator -t <registry>/coordinator:latest .
   docker push <registry>/coordinator:latest
   
   # Build worker image  
   docker build -f Dockerfile.worker -t <registry>/worker:latest .
   docker push <registry>/worker:latest
   ```

2. **Update Container Apps Jobs with Image References**:
   ```bash
   # Update coordinator job
   az containerapp job update \
       --name <coordinator-job-name> \
       --resource-group <resource-group> \
       --image <registry>/coordinator:latest
   
   # Update worker job
   az containerapp job update \
       --name <worker-job-name> \
       --resource-group <resource-group> \
       --image <registry>/worker:latest
   ```

3. **Configure Managed Identity Permissions**:
   ```bash
   # Grant Container Apps access to Key Vault
   az keyvault set-policy \
       --name <keyvault-name> \
       --object-id <container-app-identity> \
       --secret-permissions get list
   ```

## Testing and Validation

### Manual Job Execution

```bash
# Start coordinator job manually
az containerapp job start \
    --name <coordinator-job-name> \
    --resource-group <resource-group>

# Monitor job execution
az containerapp job execution list \
    --name <coordinator-job-name> \
    --resource-group <resource-group> \
    --output table
```

### Cache Validation

```bash
# Test Redis connectivity
redis-cli -h <redis-hostname> -p 6380 -a <redis-key> --tls ping

# Check cache population
redis-cli -h <redis-hostname> -p 6380 -a <redis-key> --tls \
    eval "return #redis.call('keys', 'users:*')" 0
```

### Monitor Logs

```bash
# Query Container Apps logs
az monitor log-analytics query \
    --workspace <log-analytics-id> \
    --analytics-query "ContainerAppConsoleLogs_CL | where ContainerAppName_s contains 'coordinator' | project TimeGenerated, Log_s | order by TimeGenerated desc | take 10"
```

## Monitoring and Alerting

The infrastructure includes:

- **Azure Monitor** integration for comprehensive observability
- **Log Analytics** workspace for centralized logging
- **Alert rules** for job failure notifications
- **Action groups** for notification routing

Access monitoring through:
- Azure Portal > Monitor > Container Apps
- Log Analytics queries for detailed troubleshooting
- Alert notifications via configured action groups

## Security Features

- **Key Vault** integration for secure secret management
- **Managed Identity** for passwordless authentication
- **Private networking** options for Container Apps environment
- **Redis Enterprise** with SSL/TLS encryption
- **RBAC** integration for fine-grained access control

## Cost Optimization

- **Container Apps Jobs** scale to zero when not running
- **Scheduled execution** prevents unnecessary warm-up operations
- **Parallel processing** minimizes execution time
- **Redis Enterprise** includes built-in high availability

Expected monthly costs:
- Redis Enterprise E10: ~$200-250
- Container Apps environment: ~$50-100
- Storage and monitoring: ~$10-20

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion
az group show --name <resource-group-name>
```

## Troubleshooting

### Common Issues

1. **Container Image Pull Failures**:
   - Verify container registry access and image tags
   - Check managed identity permissions for container registry

2. **Redis Connection Issues**:
   - Verify Redis Enterprise deployment completion
   - Check Key Vault secret configuration
   - Validate network connectivity from Container Apps

3. **Job Execution Failures**:
   - Review Container Apps logs in Log Analytics
   - Check environment variable configuration
   - Verify managed identity permissions

4. **Monitoring Issues**:
   - Ensure Log Analytics workspace is properly linked
   - Check alert rule configurations
   - Verify action group settings

### Debug Commands

```bash
# Check Container Apps environment status
az containerapp env show --name <env-name> --resource-group <rg>

# View job execution history
az containerapp job execution list --name <job-name> --resource-group <rg>

# Check Redis status
az redis show --name <redis-name> --resource-group <rg>

# Validate Key Vault access
az keyvault secret list --vault-name <vault-name>
```

## Customization

### Extending the Solution

1. **Add Data Sources**: Modify worker containers to support additional data sources
2. **Implement Priority Queuing**: Use Azure Service Bus for advanced job orchestration
3. **Multi-Region Support**: Deploy across multiple Azure regions for geo-distributed caching
4. **Advanced Monitoring**: Integrate with Azure Application Insights for detailed performance metrics

### Performance Tuning

- Adjust Container Apps job parallelism based on data source capacity
- Optimize Redis Enterprise cluster size for your workload
- Configure appropriate cache TTL values
- Implement intelligent retry logic in worker containers

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Container Apps documentation: https://learn.microsoft.com/en-us/azure/container-apps/
3. Reference Azure Redis Enterprise documentation: https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/
4. Consult Azure monitoring best practices: https://learn.microsoft.com/en-us/azure/container-apps/observability

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Azure CLI Version**: 2.50.0+
- **Terraform Version**: 1.5.0+
- **Bicep Version**: Latest stable