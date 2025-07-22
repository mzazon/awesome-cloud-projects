# Infrastructure as Code for Continuous Performance Testing with Azure Load Testing and Azure DevOps

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Continuous Performance Testing with Azure Load Testing and Azure DevOps".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2 installed and configured
- Azure subscription with appropriate permissions
- Azure DevOps organization and project (for pipeline integration)
- OpenSSL for generating random values (included in most Linux/macOS systems)
- Target application deployed in Azure for testing
- Appropriate permissions for:
  - Resource Group creation
  - Azure Load Testing resource creation
  - Application Insights resource creation
  - Azure Monitor alert creation
  - Service Principal creation

## Quick Start

### Using Bicep (Recommended)

```bash
# Clone or navigate to the bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-loadtest-devops \
    --template-file main.bicep \
    --parameters targetAppUrl="https://your-app.azurewebsites.net"
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
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Note: You'll be prompted for required parameters
```

## Configuration Parameters

### Common Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | eastus | No |
| `resourceGroupName` | Name of the resource group | rg-loadtest-devops | No |
| `loadTestName` | Name of the Azure Load Testing resource | alt-perftest-demo | No |
| `appInsightsName` | Name of Application Insights resource | ai-perftest-demo | No |
| `targetAppUrl` | URL of the target application to test | - | Yes |
| `environment` | Environment tag for resources | demo | No |

### Bicep Parameters

Override parameters by creating a parameters file or using `--parameters` flag:

```bash
# Using parameters file
az deployment group create \
    --resource-group rg-loadtest-devops \
    --template-file main.bicep \
    --parameters @parameters.json

# Using inline parameters
az deployment group create \
    --resource-group rg-loadtest-devops \
    --template-file main.bicep \
    --parameters targetAppUrl="https://your-app.azurewebsites.net" \
    --parameters location="westus2"
```

### Terraform Variables

Customize deployment by creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
location = "westus2"
resource_group_name = "rg-loadtest-prod"
target_app_url = "https://your-app.azurewebsites.net"
environment = "production"
```

## Deployed Resources

This infrastructure creates the following Azure resources:

- **Resource Group**: Container for all resources
- **Azure Load Testing**: Managed load testing service
- **Application Insights**: Application performance monitoring
- **Azure Monitor Action Group**: Alert notification configuration
- **Azure Monitor Metric Alerts**: Performance threshold alerts
- **Service Principal**: Authentication for Azure DevOps integration

## Post-Deployment Configuration

### 1. Azure DevOps Service Connection

After deployment, configure the service connection in Azure DevOps:

1. Navigate to your Azure DevOps project
2. Go to **Project Settings** → **Service connections**
3. Click **New service connection** → **Azure Resource Manager**
4. Choose **Service principal (manual)**
5. Use the service principal details from the deployment output

### 2. Load Test Files

Create the following files in your repository:

#### JMeter Test Script (`loadtest-scripts/performance-test.jmx`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="API Performance Test">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments">
        <collectionProp name="Arguments.arguments">
          <elementProp name="HOST" elementType="Argument">
            <stringProp name="Argument.name">HOST</stringProp>
            <stringProp name="Argument.value">${__P(host,example.com)}</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Users">
        <intProp name="ThreadGroup.num_threads">50</intProp>
        <intProp name="ThreadGroup.ramp_time">30</intProp>
        <longProp name="ThreadGroup.duration">180</longProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET Homepage">
          <stringProp name="HTTPSampler.domain">${HOST}</stringProp>
          <stringProp name="HTTPSampler.protocol">https</stringProp>
          <stringProp name="HTTPSampler.path">/</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
        </HTTPSamplerProxy>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
```

#### Load Test Configuration (`loadtest-scripts/loadtest-config.yaml`)
```yaml
version: v0.1
testId: performance-baseline
displayName: API Performance Baseline Test
testPlan: performance-test.jmx
description: Validates API performance meets SLA requirements
engineInstances: 1

configurationFiles:
- performance-test.jmx

failureCriteria:
- avg(response_time_ms) > 1000
- percentage(error) > 5
- avg(requests_per_sec) < 100

env:
- name: host
  value: your-app.azurewebsites.net

autoStop:
  errorPercentage: 90
  timeWindow: 60
```

#### Azure Pipeline (`azure-pipelines.yml`)
```yaml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  loadTestResource: '$(LOAD_TEST_NAME)'
  loadTestResourceGroup: '$(RESOURCE_GROUP_NAME)'

stages:
- stage: Build
  jobs:
  - job: BuildApplication
    steps:
    - task: UseDotNet@2
      inputs:
        packageType: 'sdk'
        version: '8.x'
    
    - script: |
        echo "Building application..."
        # Add your build commands here
      displayName: 'Build Application'
    
    - publish: $(System.DefaultWorkingDirectory)
      artifact: drop

- stage: PerformanceTest
  dependsOn: Build
  jobs:
  - job: RunLoadTest
    steps:
    - checkout: self
    
    - task: AzureCLI@2
      displayName: 'Execute Load Test'
      inputs:
        azureSubscription: 'Azure-Service-Connection'
        scriptType: 'bash'
        scriptLocation: 'inlineScript'
        inlineScript: |
          # Create test run
          TEST_RUN_ID=$(az load test create \
              --test-id "performance-baseline" \
              --load-test-resource $(loadTestResource) \
              --resource-group $(loadTestResourceGroup) \
              --test-plan "./loadtest-scripts/performance-test.jmx" \
              --load-test-config-file "./loadtest-scripts/loadtest-config.yaml" \
              --display-name "Pipeline Run - $(Build.BuildId)" \
              --description "Automated test from pipeline" \
              --query testRunId \
              --output tsv)
          
          echo "Test run created: $TEST_RUN_ID"
          
          # Wait for test completion
          az load test-run wait \
              --test-run-id $TEST_RUN_ID \
              --load-test-resource $(loadTestResource) \
              --resource-group $(loadTestResourceGroup)
          
          # Get test results
          az load test-run metrics \
              --test-run-id $TEST_RUN_ID \
              --load-test-resource $(loadTestResource) \
              --resource-group $(loadTestResourceGroup) \
              --metric-namespace LoadTestRunMetrics

    - task: PublishTestResults@2
      displayName: 'Publish Load Test Results'
      inputs:
        testResultsFormat: 'JUnit'
        testResultsFiles: '**/loadtest-results.xml'
        failTaskOnFailedTests: true
```

## Validation

### Verify Deployment

```bash
# Check Azure Load Testing resource
az load show \
    --name $(LOAD_TEST_NAME) \
    --resource-group $(RESOURCE_GROUP_NAME) \
    --output table

# Check Application Insights
az monitor app-insights component show \
    --app $(APP_INSIGHTS_NAME) \
    --resource-group $(RESOURCE_GROUP_NAME) \
    --output table

# List monitoring alerts
az monitor metrics alert list \
    --resource-group $(RESOURCE_GROUP_NAME) \
    --output table
```

### Test Load Testing Service

```bash
# Create a manual test run
az load test create \
    --test-id "validation-test" \
    --load-test-resource $(LOAD_TEST_NAME) \
    --resource-group $(RESOURCE_GROUP_NAME) \
    --test-plan "./loadtest-scripts/performance-test.jmx" \
    --display-name "Manual Validation Test" \
    --engine-instances 1
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-loadtest-devops \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup

If you need to clean up resources individually:

```bash
# Delete service principal
az ad sp delete --id $(SERVICE_PRINCIPAL_ID)

# Delete monitoring alerts
az monitor metrics alert delete \
    --name "alert-high-response-time" \
    --resource-group $(RESOURCE_GROUP_NAME)

az monitor metrics alert delete \
    --name "alert-high-error-rate" \
    --resource-group $(RESOURCE_GROUP_NAME)

# Delete action group
az monitor action-group delete \
    --name "ag-perftest-alerts" \
    --resource-group $(RESOURCE_GROUP_NAME)

# Delete resource group
az group delete \
    --name $(RESOURCE_GROUP_NAME) \
    --yes \
    --no-wait
```

## Troubleshooting

### Common Issues

1. **Service Principal Creation Fails**
   - Ensure you have sufficient permissions to create service principals
   - Check Azure AD permissions for your account

2. **Load Test Execution Fails**
   - Verify target application URL is accessible
   - Check Azure DevOps service connection configuration
   - Ensure JMeter test script is valid

3. **Monitoring Alerts Not Triggering**
   - Verify metric names and thresholds are correct
   - Check action group email configuration
   - Ensure load test is generating sufficient metrics

### Debugging Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group $(RESOURCE_GROUP_NAME) \
    --name $(DEPLOYMENT_NAME)

# View activity log
az monitor activity-log list \
    --resource-group $(RESOURCE_GROUP_NAME) \
    --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)

# Check service principal permissions
az role assignment list \
    --assignee $(SERVICE_PRINCIPAL_ID) \
    --output table
```

## Security Considerations

- Service principal uses least privilege access (Load Test Contributor role)
- Application Insights data is encrypted at rest
- Load test results are stored securely in Azure
- Action groups support secure webhook integration
- Monitor alerts can be configured with secure notification channels

## Cost Optimization

- Azure Load Testing charges based on test execution time
- Use engineInstances parameter to control concurrent test engines
- Configure autoStop to prevent runaway tests
- Monitor Application Insights data ingestion costs
- Consider using Azure Budget alerts for cost control

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation
2. Refer to [Azure Load Testing documentation](https://docs.microsoft.com/en-us/azure/load-testing/)
3. Review [Azure DevOps documentation](https://docs.microsoft.com/en-us/azure/devops/)
4. Check [Azure Monitor documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

## Additional Resources

- [Azure Load Testing best practices](https://docs.microsoft.com/en-us/azure/load-testing/best-practices)
- [Azure DevOps service connections](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints)
- [JMeter documentation](https://jmeter.apache.org/usermanual/index.html)
- [Azure Monitor alerts](https://docs.microsoft.com/en-us/azure/azure-monitor/platform/alerts-overview)