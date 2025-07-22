# Infrastructure as Code for Adaptive Code Quality Enforcement with DevOps Extensions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Adaptive Code Quality Enforcement with DevOps Extensions".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.37.0 or later)
- Azure DevOps organization with appropriate permissions
- Azure DevOps CLI extension installed (`az extension add --name azure-devops`)
- Azure subscription with Contributor access
- Basic understanding of CI/CD concepts and Azure DevOps services
- Development project with existing code repository for testing
- Estimated cost: $50-100/month for Azure services (varies by usage)

> **Note**: This recipe requires Azure DevOps Basic + Test Plans licensing for full functionality. Review [Azure DevOps pricing](https://azure.microsoft.com/en-us/pricing/details/devops/azure-devops-services/) for detailed cost information.

## Quick Start

### Using Bicep
```bash
cd bicep/
az deployment group create \
    --resource-group rg-code-quality-pipeline \
    --template-file main.bicep \
    --parameters devOpsOrganization=your-devops-org \
                 projectName=quality-pipeline-demo \
                 location=eastus
```

### Using Terraform
```bash
cd terraform/
terraform init
terraform plan -var="devops_organization=your-devops-org" \
               -var="project_name=quality-pipeline-demo" \
               -var="location=eastus"
terraform apply
```

### Using Bash Scripts
```bash
chmod +x scripts/deploy.sh
export DEVOPS_ORG="your-devops-organization"
export PROJECT_NAME="quality-pipeline-demo"
export LOCATION="eastus"
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys:

- **Azure DevOps Project**: Configured with advanced features for Git version control, Agile work tracking, and pipeline capabilities
- **Application Insights**: Real-time application performance monitoring for intelligent feedback loops
- **Storage Account**: State management for Logic Apps workflows
- **Logic Apps**: Automated workflows for intelligent quality evaluation and feedback
- **Azure Test Plans**: Comprehensive test management with manual and automated testing integration
- **DevOps Extensions**: Static analysis, code coverage, and security scanning tools
- **Quality Pipeline**: YAML-based CI/CD pipeline with intelligent quality gates
- **Quality Dashboard**: Real-time visibility into quality metrics and trends

## Configuration

### Environment Variables

The following environment variables can be set to customize the deployment:

```bash
# Required
export DEVOPS_ORG="your-devops-organization"
export PROJECT_NAME="quality-pipeline-demo"
export LOCATION="eastus"

# Optional (will use defaults if not set)
export RESOURCE_GROUP="rg-code-quality-pipeline"
export QUALITY_THRESHOLD="80"
export STORAGE_ACCOUNT_SKU="Standard_LRS"
```

### Customization Options

#### Bicep Parameters
- `devOpsOrganization`: Your Azure DevOps organization name
- `projectName`: Name for the DevOps project
- `location`: Azure region for resources
- `resourceGroupName`: Resource group name (default: rg-code-quality-pipeline)
- `qualityThreshold`: Quality score threshold for pipeline gates (default: 80)

#### Terraform Variables
- `devops_organization`: Your Azure DevOps organization name
- `project_name`: Name for the DevOps project
- `location`: Azure region for resources
- `resource_group_name`: Resource group name
- `quality_threshold`: Quality score threshold for pipeline gates
- `storage_account_sku`: Storage account SKU (default: Standard_LRS)

## Features

### Intelligent Quality Pipeline
- **Static Analysis**: Automated code quality scanning with SonarQube integration
- **Security Scanning**: Vulnerability detection and compliance checking
- **Code Coverage**: Comprehensive test coverage reporting
- **Quality Gates**: Automated quality thresholds with intelligent feedback
- **Performance Monitoring**: Real-time application performance tracking

### Test Management
- **Azure Test Plans**: Structured test case management and execution
- **Manual Testing**: Exploratory testing workflows with traceability
- **Automated Testing**: Integration with CI/CD pipelines
- **Test Reporting**: Comprehensive test results and coverage metrics

### Feedback Loops
- **Logic Apps**: Automated decision-making based on quality metrics
- **Application Insights**: Performance correlation with code quality
- **Dashboard**: Real-time quality metrics and trend analysis
- **Notifications**: Intelligent alerts based on quality thresholds

## Post-Deployment Configuration

### 1. Configure Azure DevOps Extensions

After deployment, install required extensions:

```bash
# Install SonarQube extension
az devops extension install \
    --extension-id sonarqube \
    --publisher-id SonarSource \
    --organization https://dev.azure.com/${DEVOPS_ORG}

# Install Code Coverage extension
az devops extension install \
    --extension-id code-coverage \
    --publisher-id ms-devlabs \
    --organization https://dev.azure.com/${DEVOPS_ORG}

# Install Security Code Scan extension
az devops extension install \
    --extension-id security-code-scan \
    --publisher-id ms-securitycodeanalysis \
    --organization https://dev.azure.com/${DEVOPS_ORG}
```

### 2. Configure Test Plans

Create test plans and suites:

```bash
# Create test plan
export TEST_PLAN_ID=$(az devops invoke \
    --area testplan \
    --resource testplans \
    --route-parameters project=${PROJECT_NAME} \
    --http-method POST \
    --in-file /dev/stdin <<EOF | jq -r '.id'
{
  "name": "Intelligent Quality Pipeline Tests",
  "description": "Comprehensive testing strategy for code quality enforcement",
  "startDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "endDate": "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)",
  "state": "Active"
}
EOF
)
```

### 3. Configure Pipeline Integration

Set up the quality pipeline with the generated infrastructure:

```bash
# Create pipeline YAML configuration
cat > azure-pipeline-quality.yml << 'EOF'
trigger:
  branches:
    include:
      - main
      - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'
  qualityThreshold: $(QUALITY_THRESHOLD)

stages:
- stage: QualityAnalysis
  displayName: 'Code Quality Analysis'
  jobs:
  - job: StaticAnalysis
    displayName: 'Static Code Analysis'
    steps:
    - task: SonarQubePrepare@5
      inputs:
        SonarQube: 'SonarQubeServiceConnection'
        scannerMode: 'MSBuild'
        projectKey: '$(PROJECT_NAME)'
        projectName: '$(PROJECT_NAME)'
    
    - task: DotNetCoreCLI@2
      inputs:
        command: 'build'
        projects: '**/*.csproj'
        arguments: '--configuration $(buildConfiguration)'
    
    - task: DotNetCoreCLI@2
      inputs:
        command: 'test'
        projects: '**/*Tests.csproj'
        arguments: '--configuration $(buildConfiguration) --collect:"XPlat Code Coverage"'
    
    - task: SonarQubeAnalyze@5
    
    - task: SonarQubePublish@5
      inputs:
        pollingTimeoutSec: '300'

- stage: TestExecution
  displayName: 'Test Execution'
  dependsOn: QualityAnalysis
  jobs:
  - job: AutomatedTesting
    displayName: 'Automated Test Suite'
    steps:
    - task: DotNetCoreCLI@2
      inputs:
        command: 'test'
        projects: '**/*IntegrationTests.csproj'
        arguments: '--configuration $(buildConfiguration) --logger trx --collect:"XPlat Code Coverage"'
    
    - task: PublishTestResults@2
      inputs:
        testResultsFormat: 'VSTest'
        testResultsFiles: '**/*.trx'
        failTaskOnFailedTests: true
    
    - task: PublishCodeCoverageResults@1
      inputs:
        codeCoverageTool: 'Cobertura'
        summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'

- stage: QualityGate
  displayName: 'Quality Gate Evaluation'
  dependsOn: TestExecution
  jobs:
  - job: EvaluateQuality
    displayName: 'Evaluate Quality Metrics'
    steps:
    - task: PowerShell@2
      inputs:
        targetType: 'inline'
        script: |
          # Calculate quality score based on metrics
          $qualityScore = 85  # This would be calculated from actual metrics
          Write-Host "Quality Score: $qualityScore"
          
          # Trigger Logic App for intelligent feedback
          $body = @{
            qualityScore = $qualityScore
            testResults = "$(Agent.JobStatus)"
            performanceMetrics = @{
              buildTime = "$(System.StageDisplayName)"
              testCoverage = 85
            }
          } | ConvertTo-Json
          
          Invoke-RestMethod -Uri "$(LOGIC_APP_URL)" -Method Post -Body $body -ContentType "application/json"
EOF

# Create pipeline
az pipelines create \
    --name "Intelligent Quality Pipeline" \
    --repository ${PROJECT_NAME} \
    --branch main \
    --yaml-path azure-pipeline-quality.yml \
    --project ${PROJECT_NAME}
```

## Validation

After deployment, verify the solution is working correctly:

1. **Check Azure DevOps Project**:
   ```bash
   az devops project show --project ${PROJECT_NAME} --output table
   ```

2. **Verify Application Insights**:
   ```bash
   az monitor app-insights component show \
       --app ai-quality-${RANDOM_SUFFIX} \
       --resource-group ${RESOURCE_GROUP}
   ```

3. **Test Logic Apps Workflow**:
   ```bash
   # Get Logic App URL from outputs
   LOGIC_APP_URL=$(az logic workflow show \
       --name la-quality-feedback-${RANDOM_SUFFIX} \
       --resource-group ${RESOURCE_GROUP} \
       --query accessEndpoint --output tsv)
   
   # Test webhook
   curl -X POST "${LOGIC_APP_URL}" \
        -H "Content-Type: application/json" \
        -d '{"qualityScore": 85, "testResults": "success"}'
   ```

4. **Verify Pipeline Creation**:
   ```bash
   az pipelines list --project ${PROJECT_NAME} --output table
   ```

## Cleanup

### Using Bicep
```bash
# Delete the resource group (removes all resources)
az group delete --name rg-code-quality-pipeline --yes --no-wait

# Delete Azure DevOps project
az devops project delete --id ${PROJECT_NAME} --yes
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

## Troubleshooting

### Common Issues

1. **DevOps Extension Installation Failures**:
   - Ensure you have sufficient permissions in your Azure DevOps organization
   - Check if extensions are already installed or need updates

2. **Logic Apps Deployment Issues**:
   - Verify storage account is created successfully
   - Check Logic Apps service availability in your selected region

3. **Pipeline Execution Failures**:
   - Ensure service connections are properly configured
   - Verify build agent has necessary permissions

4. **Test Plans Access Issues**:
   - Confirm you have Azure DevOps Basic + Test Plans licensing
   - Check project permissions for test plan creation

### Debugging

Enable debug logging for deployments:

```bash
# For Azure CLI
export AZURE_CLI_DIAGNOSTICS=on

# For Terraform
export TF_LOG=DEBUG
```

## Security Considerations

- **Least Privilege**: All IAM roles follow principle of least privilege
- **Service Connections**: Secure authentication for external services
- **Storage Encryption**: All storage accounts use encryption at rest
- **Network Security**: Appropriate network security groups and firewall rules
- **Secrets Management**: Sensitive data stored in Azure Key Vault (when applicable)

## Cost Optimization

- **Resource Sizing**: Appropriately sized resources for development workloads
- **Auto-scaling**: Logic Apps scale automatically based on demand
- **Storage Tiers**: Cost-effective storage configurations
- **Monitoring**: Application Insights sampling to control costs

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure DevOps documentation for service-specific issues
3. Consult Azure documentation for infrastructure problems
4. Review deployment logs for error details

## Contributing

When modifying this infrastructure code:
1. Follow Azure naming conventions
2. Update parameter descriptions
3. Test deployments in development environment
4. Update this README with any new features or requirements

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Bicep Version**: Latest stable
- **Terraform Version**: >= 1.0
- **Azure CLI Version**: >= 2.37.0