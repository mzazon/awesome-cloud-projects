# Infrastructure as Code for Scalable Browser Testing Pipelines with Playwright and DevOps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Browser Testing Pipelines with Playwright and DevOps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az login`)
- Azure subscription with appropriate permissions for:
  - Azure Playwright Testing (preview service)
  - Azure DevOps
  - Azure Container Registry
  - Resource Group management
- Node.js 18.x or later (for Playwright development)
- Azure DevOps organization access
- Appropriate permissions for resource creation and service principal management

> **Note**: Azure Playwright Testing is currently in preview and available in East US, West US 3, East Asia, and West Europe regions.

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-playwright-testing \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-playwright-testing \
    --name main \
    --query properties.provisioningState
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
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

# Verify deployment (optional)
az playwright workspace show \
    --name pw-workspace-$(openssl rand -hex 3) \
    --resource-group rg-playwright-testing
```

## Configuration

### Environment Variables

Before deployment, set these environment variables:

```bash
export AZURE_REGION="eastus"
export RESOURCE_GROUP="rg-playwright-testing"
export DEVOPS_ORG="your-devops-org"
export PROJECT_NAME="playwright-testing-project"
export RANDOM_SUFFIX=$(openssl rand -hex 3)
export PLAYWRIGHT_WORKSPACE="pw-workspace-${RANDOM_SUFFIX}"
export ACR_NAME="acr${RANDOM_SUFFIX}"
```

### Bicep Parameters

The Bicep template accepts the following parameters:

- `location`: Azure region for deployment (default: eastus)
- `resourceGroupName`: Name of the resource group
- `playwrightWorkspaceName`: Name of the Playwright workspace
- `containerRegistryName`: Name of the Azure Container Registry
- `devopsOrganization`: Azure DevOps organization name
- `projectName`: Azure DevOps project name
- `tags`: Common tags for all resources

### Terraform Variables

Configure variables in `terraform/terraform.tfvars`:

```hcl
azure_region = "eastus"
resource_group_name = "rg-playwright-testing"
playwright_workspace_name = "pw-workspace-unique"
container_registry_name = "acrunique123"
devops_organization = "your-devops-org"
project_name = "playwright-testing-project"
tags = {
  environment = "production"
  project     = "browser-testing"
}
```

## Deployment Details

### Resources Created

1. **Azure Playwright Testing Workspace**
   - Managed cloud browsers for testing
   - Scalable test execution environment
   - Integrated reporting and analytics

2. **Azure Container Registry**
   - Private container registry for test images
   - Secure storage for custom browser configurations
   - Integration with DevOps pipelines

3. **Azure DevOps Project**
   - Source code repository
   - CI/CD pipeline configuration
   - Work item tracking and collaboration

4. **Service Connections**
   - Azure Resource Manager connection
   - Container Registry authentication
   - Secure credential management

### Security Considerations

- All resources are deployed with least privilege access
- Service connections use managed identities where possible
- Container registry has admin access disabled by default
- Playwright workspace uses secure token authentication
- All resources are tagged for governance and cost management

## Post-Deployment Configuration

### 1. Configure Azure DevOps Pipeline

After infrastructure deployment, configure your testing pipeline:

```bash
# Create pipeline variables
az pipelines variable create \
    --name PlaywrightServiceUrl \
    --value "$(az playwright workspace show --name $PLAYWRIGHT_WORKSPACE --resource-group $RESOURCE_GROUP --query properties.serviceEndpoint -o tsv)" \
    --project $PROJECT_NAME

# Create secure access token variable
az pipelines variable create \
    --name PlaywrightServiceAccessToken \
    --value "$(az playwright workspace show --name $PLAYWRIGHT_WORKSPACE --resource-group $RESOURCE_GROUP --query properties.accessToken -o tsv)" \
    --secret true \
    --project $PROJECT_NAME
```

### 2. Set Up Test Repository

```bash
# Clone the created repository
git clone https://dev.azure.com/$DEVOPS_ORG/$PROJECT_NAME/_git/$PROJECT_NAME
cd $PROJECT_NAME

# Initialize Playwright test structure
mkdir -p playwright-tests/{tests,pages,fixtures}
cd playwright-tests

# Install dependencies
npm init -y
npm install --save-dev @playwright/test
npm install --save-dev @azure/microsoft-playwright-testing
```

### 3. Configure Playwright for Azure

Create `playwright.config.js`:

```javascript
const { defineConfig } = require('@playwright/test');
const { getServiceConfig } = require('@azure/microsoft-playwright-testing');

module.exports = defineConfig({
  testDir: './tests',
  timeout: 30000,
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  reporter: [
    ['html'],
    ['junit', { outputFile: 'test-results.xml' }],
    ['@azure/microsoft-playwright-testing/reporter']
  ],
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] }
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] }
    }
  ],
  ...getServiceConfig()
});
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Playwright workspace status
az playwright workspace show \
    --name $PLAYWRIGHT_WORKSPACE \
    --resource-group $RESOURCE_GROUP \
    --query properties.provisioningState

# Test container registry connectivity
az acr check-health --name $ACR_NAME

# Verify DevOps project
az devops project show --project $PROJECT_NAME
```

### Test Playwright Integration

```bash
# Run sample test with Azure service
cd playwright-tests
PLAYWRIGHT_SERVICE_URL=$(az playwright workspace show --name $PLAYWRIGHT_WORKSPACE --resource-group $RESOURCE_GROUP --query properties.serviceEndpoint -o tsv) \
PLAYWRIGHT_SERVICE_ACCESS_TOKEN=$(az playwright workspace show --name $PLAYWRIGHT_WORKSPACE --resource-group $RESOURCE_GROUP --query properties.accessToken -o tsv) \
npx playwright test --reporter=@azure/microsoft-playwright-testing/reporter
```

## Monitoring and Troubleshooting

### Common Issues

1. **Playwright workspace creation fails**
   - Verify region support for Azure Playwright Testing
   - Check subscription limits and quotas
   - Ensure proper permissions for preview services

2. **Pipeline authentication issues**
   - Verify service connections are properly configured
   - Check managed identity permissions
   - Validate access tokens are not expired

3. **Test execution failures**
   - Verify Playwright service URL is accessible
   - Check network connectivity from build agents
   - Validate test code compatibility with Azure service

### Monitoring

```bash
# Check workspace health
az playwright workspace show \
    --name $PLAYWRIGHT_WORKSPACE \
    --resource-group $RESOURCE_GROUP \
    --query properties.status

# Monitor pipeline runs
az pipelines runs list \
    --project $PROJECT_NAME \
    --pipeline-name "Playwright-Testing-Pipeline" \
    --top 10
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name $RESOURCE_GROUP \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion when prompted
```

### Manual Cleanup Steps

If automated cleanup fails, manually remove resources:

```bash
# Delete DevOps project
az devops project delete \
    --id $(az devops project show --project $PROJECT_NAME --query id -o tsv) \
    --yes

# Delete Playwright workspace
az playwright workspace delete \
    --name $PLAYWRIGHT_WORKSPACE \
    --resource-group $RESOURCE_GROUP \
    --yes

# Delete container registry
az acr delete \
    --name $ACR_NAME \
    --resource-group $RESOURCE_GROUP \
    --yes

# Finally, delete resource group
az group delete \
    --name $RESOURCE_GROUP \
    --yes
```

## Cost Optimization

### Estimated Monthly Costs

- **Azure Playwright Testing**: ~$20-40 (based on test execution time)
- **Azure Container Registry**: ~$5-10 (Basic tier)
- **Azure DevOps**: Free tier available, paid plans start at $6/user/month
- **Total**: ~$25-60/month depending on usage

### Cost-Saving Tips

1. **Optimize test execution**:
   - Use test sharding to reduce execution time
   - Run tests only on relevant browsers for each feature
   - Implement smart test selection based on code changes

2. **Resource management**:
   - Use Basic tier for Container Registry unless advanced features are needed
   - Monitor Playwright workspace usage and adjust test frequency
   - Clean up old test artifacts regularly

3. **Pipeline optimization**:
   - Use conditional triggers to avoid unnecessary test runs
   - Implement test result caching for unchanged code
   - Use parallel jobs efficiently to reduce overall execution time

## Customization

### Extending the Solution

1. **Add more browsers**: Update `playwright.config.js` to include additional browser configurations
2. **Implement visual testing**: Add visual regression testing capabilities
3. **Multi-environment support**: Create separate workspaces for different environments
4. **Advanced reporting**: Integrate with Azure Application Insights for detailed analytics
5. **Performance testing**: Combine with Azure Load Testing for comprehensive quality gates

### Environment-Specific Configurations

Create separate parameter files for different environments:

```bash
# Development environment
bicep/parameters.dev.json

# Staging environment
bicep/parameters.staging.json

# Production environment
bicep/parameters.prod.json
```

## Support

For issues with this infrastructure code:

1. **Azure Playwright Testing**: [Azure Playwright Testing documentation](https://docs.microsoft.com/en-us/azure/playwright-testing/)
2. **Azure DevOps**: [Azure DevOps documentation](https://docs.microsoft.com/en-us/azure/devops/)
3. **Playwright**: [Playwright documentation](https://playwright.dev/)
4. **Azure Container Registry**: [ACR documentation](https://docs.microsoft.com/en-us/azure/container-registry/)

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update documentation for any new parameters or resources
3. Verify all deployment methods (Bicep, Terraform, Bash) work correctly
4. Update cost estimates if new resources are added
5. Test cleanup procedures thoroughly

## License

This infrastructure code is provided as-is under the same license as the original recipe documentation.