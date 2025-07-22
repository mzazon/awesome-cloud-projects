# Azure Performance Regression Detection with Load Testing - Terraform Infrastructure

This Terraform configuration deploys a complete automated performance regression detection system using Azure Load Testing and Azure Monitor Workbooks, designed to integrate seamlessly with Azure DevOps CI/CD pipelines.

## Architecture Overview

The infrastructure provisions:

- **Azure Load Testing**: Managed load testing service for performance validation
- **Azure Container Apps**: Serverless container hosting with auto-scaling
- **Azure Container Registry**: Private container image registry
- **Log Analytics Workspace**: Centralized logging and metrics storage
- **Application Insights**: Application performance monitoring
- **Azure Monitor Workbooks**: Interactive performance dashboards
- **Metric Alerts**: Automated regression detection and notifications

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.60
- Azure subscription with appropriate permissions

### Required Permissions

Your Azure account needs the following roles:
- **Contributor** or **Owner** on the target subscription
- **User Access Administrator** (if creating role assignments)

### Authentication

Authenticate with Azure using one of these methods:

```bash
# Option 1: Azure CLI (recommended for local development)
az login

# Option 2: Service Principal (recommended for CI/CD)
az login --service-principal -u <app-id> -p <password> --tenant <tenant-id>

# Option 3: Managed Identity (for Azure-hosted runners)
az login --identity
```

## Quick Start

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd azure/implementing-automated-performance-regression-detection-with-azure-load-testing-and-azure-monitor-workbooks/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan Deployment

```bash
terraform plan
```

### 4. Deploy Infrastructure

```bash
terraform apply
```

### 5. Access Your Resources

After deployment, Terraform will output key information including:
- Container App URL for testing
- Azure portal links for monitoring
- Configuration files for load testing

## Configuration

### Basic Configuration

The minimal configuration uses all defaults:

```hcl
# terraform.tfvars
location = "East US"
environment = "dev"
project_name = "myproject"
```

### Advanced Configuration

```hcl
# terraform.tfvars
resource_group_name = "rg-performance-testing"
location = "East US 2"
environment = "production"
project_name = "ecommerce"

# Load Testing Configuration
load_test_name = "lt-ecommerce-prod"
load_test_description = "Production performance regression testing"

# Container Apps Configuration
container_app_cpu = "1.0"
container_app_memory = "2.0Gi"
container_app_min_replicas = 2
container_app_max_replicas = 10

# Monitoring Configuration
enable_monitoring_alerts = true
response_time_threshold_ms = 800
error_rate_threshold_percent = 3
alert_evaluation_frequency = 5

# Advanced Features
create_sample_load_test = true
create_performance_workbook = true
enable_container_insights = true

# Custom Tags
tags = {
  Environment = "production"
  Project     = "ecommerce"
  Team        = "platform"
  CostCenter  = "engineering"
}
```

## Variables Reference

### Required Variables

None - all variables have sensible defaults.

### Key Optional Variables

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `location` | Azure region | `"East US"` | `"West Europe"` |
| `environment` | Environment name | `"dev"` | `"prod"` |
| `project_name` | Project identifier | `"perftest"` | `"myapp"` |
| `container_app_cpu` | CPU allocation | `"0.5"` | `"1.0"` |
| `container_app_memory` | Memory allocation | `"1.0Gi"` | `"2.0Gi"` |
| `response_time_threshold_ms` | Alert threshold | `500` | `800` |
| `error_rate_threshold_percent` | Alert threshold | `5` | `3` |

### Complete Variables List

See [variables.tf](./variables.tf) for all available configuration options with descriptions and validation rules.

## Outputs

Key outputs include:

- **Application URLs**: Direct links to deployed applications
- **Resource Information**: IDs, names, and configuration details
- **Monitoring URLs**: Direct links to Azure portal resources
- **Configuration Templates**: Generated test configurations content
- **Useful Commands**: Azure CLI commands for common operations

## Usage Examples

### Basic Performance Testing

1. **Deploy the infrastructure**:
   ```bash
   terraform apply
   ```

2. **Test the application**:
   ```bash
   # Get the application URL from Terraform output
   curl -s https://$(terraform output -raw container_app_fqdn)
   ```

3. **Run a load test**:
   ```bash
   # Use the generated configuration
   az load test create --load-test-resource $(terraform output -raw load_test_name) \
                       --resource-group $(terraform output -raw resource_group_name) \
                       --test-plan loadtest.jmx \
                       --test-plan-config loadtest-config.yaml
   ```

### CI/CD Integration

The infrastructure includes an Azure DevOps pipeline template (`azure-pipelines.yml`) that demonstrates:

- Automated deployment to Container Apps
- Load test execution as part of the pipeline
- Performance regression detection
- Results publishing and notifications

### Custom Load Testing

1. **Modify the JMeter script** (`loadtest.jmx`):
   - Add new test scenarios
   - Configure different user loads
   - Add custom assertions

2. **Update the test configuration** (`loadtest-config.yaml`):
   - Adjust failure criteria
   - Configure test duration
   - Set environment variables

3. **Customize monitoring**:
   - Modify workbook queries
   - Add custom metrics
   - Configure additional alerts

## Monitoring and Observability

### Application Insights

The deployed Application Insights instance automatically collects:
- Request/response metrics
- Dependency telemetry
- Exception tracking
- Performance counters

### Log Analytics

All logs are centralized in the Log Analytics workspace:
- Application logs
- Container logs
- Load test results
- System metrics

### Performance Workbook

The Azure Monitor Workbook provides:
- Response time trends
- Error rate analysis
- Throughput monitoring
- Resource utilization graphs

### Custom Queries

Example KQL queries for performance analysis:

```kusto
// Average response time over time
requests
| where timestamp > ago(1h)
| summarize avg(duration) by bin(timestamp, 5m)
| render timechart

// Error rate by endpoint
requests
| where timestamp > ago(1h)
| summarize ErrorRate = countif(success == false) * 100.0 / count() by name
| order by ErrorRate desc
```

## Security Considerations

### Network Security

- Container Apps use HTTPS by default
- Ingress is configured for external access only where needed
- All inter-service communication is encrypted

### Identity and Access

- Uses Azure Managed Identity where possible
- Follows principle of least privilege
- Secrets are stored in Azure Key Vault (when configured)

### Monitoring Security

- Log Analytics workspace access is controlled via RBAC
- Application Insights data is encrypted at rest
- Alert notifications can be configured for security events

## Cost Management

### Cost Optimization

- Container Apps scale to zero when idle
- Load Testing is consumption-based
- Log Analytics retention is configurable
- Basic SKUs are used for development environments

### Estimated Costs

For a development environment with moderate usage:
- Container Apps: ~$20-50/month
- Load Testing: ~$10-30/month (based on test frequency)
- Log Analytics: ~$10-20/month
- Application Insights: ~$5-15/month

For production environments, costs will scale with:
- Number of container replicas
- Load test frequency and duration
- Log data volume
- Alert frequency

## Troubleshooting

### Common Issues

1. **Resource naming conflicts**:
   - Solution: The random suffix prevents most conflicts
   - Alternative: Customize resource names via variables

2. **Insufficient permissions**:
   - Solution: Ensure your account has Contributor role
   - Check: `az account show --query user.name`

3. **Container App deployment failures**:
   - Check: Container registry credentials
   - Verify: Image exists and is accessible

4. **Load test failures**:
   - Validate: Target application is accessible
   - Check: JMeter script syntax
   - Review: Test configuration parameters

### Debugging Commands

```bash
# Check resource status
az resource list --resource-group $(terraform output -raw resource_group_name) --output table

# View container app logs
az containerapp logs show --name $(terraform output -raw container_app_name) \
                         --resource-group $(terraform output -raw resource_group_name)

# Test connectivity
curl -I https://$(terraform output -raw container_app_fqdn)

# Check load test status
az load test show --name $(terraform output -raw load_test_name) \
                  --resource-group $(terraform output -raw resource_group_name)
```

## Maintenance

### Updates

- Regularly update Terraform providers
- Monitor Azure service updates
- Review and update alert thresholds
- Validate test configurations

### Backup

- Terraform state is the source of truth
- Export Application Insights queries
- Backup workbook configurations
- Document custom configurations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues with this Terraform configuration:
1. Check the troubleshooting section
2. Review Azure documentation
3. Open an issue in the repository
4. Consult the original recipe documentation

## License

This infrastructure code is provided under the same license as the parent repository.

## Resources and References

- [Azure Load Testing Documentation](https://docs.microsoft.com/en-us/azure/load-testing/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [Azure Monitor Workbooks Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Terraform Azure Provider Documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Performance Testing Best Practices](https://docs.microsoft.com/en-us/azure/load-testing/concept-load-testing-best-practices)