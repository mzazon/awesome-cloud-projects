# Infrastructure as Code for Comprehensive Static App Testing Workflows with Container Jobs

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Comprehensive Static App Testing Workflows with Container Jobs".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login`)
- Azure subscription with appropriate permissions for:
  - Static Web Apps
  - Container Apps and Container Apps Environment
  - Container Registry
  - Load Testing
  - Application Insights
  - Log Analytics Workspace
  - Service Principal creation
- GitHub repository with your static web application code
- Docker Desktop or compatible container runtime (for custom test containers)
- Appropriate permissions for resource creation and management

## Quick Start

### Using Bicep
```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json

# Alternative: Deploy with inline parameters
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file bicep/main.bicep \
    --parameters staticWebAppName=<your-swa-name> \
                 githubRepoUrl=<your-github-repo-url> \
                 githubBranch=<your-branch>
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration

### Bicep Parameters

Key parameters you can customize in `bicep/parameters.json`:

- `staticWebAppName`: Name for your Static Web App
- `githubRepoUrl`: GitHub repository URL for your application
- `githubBranch`: Branch to deploy from (default: main)
- `containerAppsEnvironmentName`: Name for Container Apps Environment
- `containerRegistryName`: Name for Azure Container Registry
- `loadTestingResourceName`: Name for Load Testing resource
- `applicationInsightsName`: Name for Application Insights
- `logAnalyticsWorkspaceName`: Name for Log Analytics Workspace
- `location`: Azure region for deployment (default: eastus)

### Terraform Variables

Configure these variables in `terraform/terraform.tfvars`:

```hcl
resource_group_name = "your-resource-group"
location = "eastus"
static_web_app_name = "your-swa-name"
github_repo_url = "https://github.com/your-username/your-repo"
github_branch = "main"
container_apps_environment_name = "your-cae-name"
container_registry_name = "yourregistry"
load_testing_resource_name = "your-load-test-name"
application_insights_name = "your-app-insights-name"
log_analytics_workspace_name = "your-law-name"
```

## Architecture Overview

The infrastructure creates:

1. **Azure Static Web App** - Hosts your static web application with built-in CI/CD
2. **Container Apps Environment** - Managed environment for running containerized testing jobs
3. **Azure Container Registry** - Private registry for storing test container images
4. **Container Apps Jobs** - Serverless jobs for running integration and load tests
5. **Azure Load Testing** - Cloud-scale load testing service
6. **Application Insights** - Application performance monitoring
7. **Log Analytics Workspace** - Centralized logging and monitoring

## Post-Deployment Configuration

### GitHub Actions Setup

After deployment, configure GitHub Actions by adding these secrets to your repository:

1. **AZURE_CREDENTIALS**: Service principal credentials for Azure access
2. **AZURE_STATIC_WEB_APPS_API_TOKEN**: Deployment token for Static Web Apps

### Container Apps Jobs Configuration

The infrastructure creates two Container Apps Jobs:

1. **Integration Test Job** - Runs automated integration tests
2. **Load Test Job** - Executes performance and load tests

You can customize these jobs by updating the container images and commands in the IaC templates.

### Load Testing Configuration

After deployment, you can create load tests using:

```bash
# Create a load test
az load test create \
    --resource-group <your-resource-group> \
    --load-test-resource <load-test-resource-name> \
    --test-id <test-id> \
    --load-test-config-file <path-to-test-config>
```

## Monitoring and Observability

The infrastructure includes comprehensive monitoring:

- **Application Insights**: Monitors Static Web App performance
- **Container Apps Logs**: Tracks job execution and results
- **Log Analytics**: Centralized logging for all resources
- **Load Testing Metrics**: Performance test results and analytics

Access monitoring data through:
- Azure portal dashboards
- Application Insights analytics
- Log Analytics queries
- Azure Monitor alerts

## Customization

### Adding Custom Test Containers

1. Build and push custom test containers to the Container Registry
2. Update Container Apps Job configurations to use your custom images
3. Configure environment variables for test parameters

### Integrating with CI/CD Pipeline

The infrastructure supports integration with various CI/CD tools:

- **GitHub Actions**: Built-in integration with Static Web Apps
- **Azure DevOps**: Can trigger Container Apps Jobs via REST API
- **Jenkins**: Custom integration using Azure CLI or REST API

### Security Considerations

- Container Apps Jobs run in isolated environments
- Container Registry uses Azure AD authentication
- Static Web Apps include built-in security features
- Load Testing uses managed identity for authentication

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --name <your-resource-group> --yes --no-wait

# Or delete individual resources
az staticwebapp delete --name <static-web-app-name> --resource-group <resource-group>
az containerapp env delete --name <container-apps-env-name> --resource-group <resource-group>
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

## Cost Optimization

- **Static Web Apps**: Generous free tier for development
- **Container Apps Jobs**: Pay-per-execution pricing
- **Container Registry**: Basic SKU for development workloads
- **Load Testing**: Consumption-based pricing
- **Application Insights**: Sample rate configuration to control costs

## Troubleshooting

### Common Issues

1. **Static Web App deployment failures**
   - Verify GitHub repository permissions
   - Check build configuration in repository

2. **Container Apps Jobs not starting**
   - Verify Container Registry permissions
   - Check job configuration and environment variables

3. **Load Testing failures**
   - Ensure target URL is accessible
   - Verify Load Testing resource permissions

### Debugging Commands

```bash
# Check Static Web App status
az staticwebapp show --name <swa-name> --resource-group <rg-name>

# Monitor Container Apps Job execution
az containerapp job execution list --name <job-name> --resource-group <rg-name>

# View Container Apps logs
az containerapp logs show --name <job-name> --resource-group <rg-name>

# Check Load Testing resource
az load show --name <load-test-name> --resource-group <rg-name>
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure service documentation
3. Verify Azure CLI command syntax
4. Review Azure Resource Manager template references
5. Check Terraform Azure provider documentation

## Contributing

To improve this infrastructure code:

1. Follow Azure naming conventions
2. Use Azure Resource Manager best practices
3. Include comprehensive comments
4. Test all configurations thoroughly
5. Update documentation for any changes

---

**Note**: This infrastructure code is generated from the recipe "Comprehensive Static App Testing Workflows with Container Jobs". Refer to the original recipe for detailed implementation guidance and best practices.