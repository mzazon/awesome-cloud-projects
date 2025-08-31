# Infrastructure as Code for Simple Resource Cleanup with Automation and PowerShell

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Resource Cleanup with Automation and PowerShell".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (`az --version`)
- Azure subscription with Contributor permissions
- PowerShell 7.0+ (for runbook development and testing)
- Terraform 1.0+ (if using Terraform implementation)
- Bicep CLI (if using Bicep implementation)
- Basic understanding of Azure resource tagging strategies

> **Note**: Estimated cost for this solution is $5-10/month for Azure Automation (includes 500 minutes of runbook execution time).

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-cleanup-demo \
    --template-file bicep/main.bicep \
    --parameters environmentTag=dev \
                 automationAccountName=aa-cleanup-demo \
                 location=eastus

# Verify deployment
az automation account show \
    --name aa-cleanup-demo \
    --resource-group rg-cleanup-demo
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="resource_group_name=rg-cleanup-demo" \
               -var="environment_tag=dev"

# Deploy infrastructure
terraform apply -var="resource_group_name=rg-cleanup-demo" \
                -var="environment_tag=dev"

# Verify deployment
terraform output automation_account_name
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy with default parameters
./scripts/deploy.sh

# Deploy with custom parameters
export RESOURCE_GROUP="my-cleanup-rg"
export LOCATION="westus2"
export ENVIRONMENT="test"
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `automationAccountName` | string | `aa-cleanup-${uniqueString(resourceGroup().id)}` | Name for the Azure Automation account |
| `location` | string | `resourceGroup().location` | Azure region for deployment |
| `environmentTag` | string | `dev` | Environment tag for resource filtering |
| `cleanupScheduleEnabled` | bool | `true` | Whether to create automated cleanup schedule |
| `scheduleStartTime` | string | `02:00` | Time for automated cleanup (24-hour format) |
| `scheduleDaysOld` | int | `7` | Days old threshold for resource cleanup |

### Terraform Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `resource_group_name` | string | Required | Name of the resource group |
| `location` | string | `East US` | Azure region for deployment |
| `automation_account_name` | string | `aa-cleanup-${random_id}` | Name for the Azure Automation account |
| `environment_tag` | string | `dev` | Environment tag for resource filtering |
| `cleanup_schedule_enabled` | bool | `true` | Whether to create automated cleanup schedule |
| `schedule_days_old` | number | `7` | Days old threshold for resource cleanup |
| `tags` | map(string) | `{}` | Additional tags to apply to resources |

## Deployment Examples

### Development Environment

```bash
# Using Bicep for development setup
az deployment group create \
    --resource-group rg-cleanup-dev \
    --template-file bicep/main.bicep \
    --parameters environmentTag=dev \
                 cleanupScheduleEnabled=true \
                 scheduleDaysOld=3
```

### Production Environment

```bash
# Using Terraform for production with additional safety
cd terraform/
terraform apply \
    -var="resource_group_name=rg-cleanup-prod" \
    -var="environment_tag=prod" \
    -var="schedule_days_old=14" \
    -var="tags={Environment=production,CostCenter=IT,Owner=platform-team}"
```

### Testing Setup

```bash
# Using scripts for quick testing
export RESOURCE_GROUP="rg-cleanup-test"
export ENVIRONMENT="test"
export CLEANUP_DAYS_OLD="1"  # Aggressive cleanup for testing
./scripts/deploy.sh
```

## Post-Deployment Configuration

### 1. Test the Cleanup Runbook

```bash
# Get automation account details
export AUTOMATION_ACCOUNT=$(az automation account list \
    --resource-group rg-cleanup-demo \
    --query "[0].name" -o tsv)

# Start a dry-run test
az automation runbook start \
    --automation-account-name ${AUTOMATION_ACCOUNT} \
    --resource-group rg-cleanup-demo \
    --name "ResourceCleanupRunbook" \
    --parameters "DaysOld=0" "Environment=dev" "DryRun=true"
```

### 2. Create Test Resources

```bash
# Create test resource group with cleanup tags
az group create \
    --name rg-cleanup-test \
    --location eastus \
    --tags Environment=dev AutoCleanup=true

# Create test storage account
az storage account create \
    --name "sttest$(date +%s)" \
    --resource-group rg-cleanup-test \
    --location eastus \
    --sku Standard_LRS \
    --tags Environment=dev AutoCleanup=true
```

### 3. Monitor Cleanup Operations

```bash
# View recent runbook jobs
az automation job list \
    --automation-account-name ${AUTOMATION_ACCOUNT} \
    --resource-group rg-cleanup-demo \
    --query "[?runbookName=='ResourceCleanupRunbook'].[jobId,status,startTime]" \
    --output table

# Get job output
JOB_ID="your-job-id-here"
az automation job get-output \
    --automation-account-name ${AUTOMATION_ACCOUNT} \
    --resource-group rg-cleanup-demo \
    --job-id ${JOB_ID} \
    --stream-type "Output"
```

## Customization

### Modifying Cleanup Logic

The PowerShell runbook can be customized by editing the cleanup criteria:

1. **Age-based cleanup**: Modify `$DaysOld` parameter default value
2. **Tag-based filtering**: Update tag conditions in the runbook
3. **Resource type filtering**: Add resource type exclusions
4. **Cost-based cleanup**: Integrate with Azure Cost Management APIs

### Schedule Customization

Update the cleanup schedule in your IaC:

```bicep
// Weekly cleanup on Sundays at 2 AM
schedule: {
  frequency: 'Week'
  interval: 1
  weekDays: ['Sunday']
  startTime: '02:00'
}
```

### Adding Notifications

Extend the solution with Logic Apps for notifications:

```bash
# Add Logic App for notifications (example)
az logic workflow create \
    --resource-group rg-cleanup-demo \
    --name cleanup-notifications \
    --definition @notification-workflow.json
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-cleanup-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="resource_group_name=rg-cleanup-demo" \
    -var="environment_tag=dev"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Or manually clean up
export RESOURCE_GROUP="rg-cleanup-demo"
az group delete --name ${RESOURCE_GROUP} --yes --no-wait
```

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Verify your Azure CLI login and permissions
   az account show
   az role assignment list --assignee $(az account show --query user.name -o tsv)
   ```

2. **Runbook Execution Failures**
   ```bash
   # Check runbook job status
   az automation job show \
       --automation-account-name ${AUTOMATION_ACCOUNT} \
       --resource-group rg-cleanup-demo \
       --job-id ${JOB_ID}
   ```

3. **Missing Managed Identity Permissions**
   ```bash
   # Verify managed identity has proper role assignments
   PRINCIPAL_ID=$(az automation account show \
       --name ${AUTOMATION_ACCOUNT} \
       --resource-group rg-cleanup-demo \
       --query identity.principalId -o tsv)
   
   az role assignment list --assignee ${PRINCIPAL_ID}
   ```

### Debug Mode

Enable debug logging in the runbook by adding:

```powershell
$VerbosePreference = "Continue"
Write-Verbose "Debug information here"
```

## Security Considerations

- **Managed Identity**: Uses system-assigned managed identity for secure authentication
- **Least Privilege**: Contributor role is assigned only to necessary resource groups
- **Tag-based Protection**: Resources with `DoNotDelete=true` tag are protected
- **Audit Trail**: All cleanup operations are logged in Azure Activity Log
- **Dry-run Mode**: Test mode prevents accidental deletions during validation

## Cost Optimization

This solution helps reduce Azure costs by:

- Automatically removing unused development resources
- Preventing resource sprawl in test environments
- Providing detailed cleanup reports for cost analysis
- Supporting custom cost thresholds and policies

Typical cost savings: 30-60% reduction in development environment costs.

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../simple-resource-cleanup-automation-powershell.md)
2. Review [Azure Automation documentation](https://docs.microsoft.com/en-us/azure/automation/)
3. Consult [Azure PowerShell runbook guides](https://docs.microsoft.com/en-us/azure/automation/automation-runbook-types)
4. See [Azure Well-Architected Framework Cost Optimization](https://docs.microsoft.com/en-us/azure/well-architected/cost-optimization/)

## License

This infrastructure code is provided as-is under the same license as the recipe collection.