# Infrastructure as Code for Voice-Driven Workflow Automation with Speech Recognition

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Voice-Driven Workflow Automation with Speech Recognition".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Azure subscription with appropriate permissions
- Azure CLI v2.0 or later installed and configured
- Power Platform environment with Power Automate premium license
- Resource creation permissions for:
  - Cognitive Services
  - Logic Apps
  - Storage Accounts
  - Resource Groups

### Tool-Specific Prerequisites

#### Bicep
- Azure CLI with Bicep extension installed
- PowerShell or Bash terminal

#### Terraform
- Terraform v1.0 or later
- Azure Provider for Terraform

#### Scripts
- Bash shell environment
- curl utility for testing
- jq for JSON processing (optional but recommended)

### Cost Considerations
- Estimated monthly cost: $20-50 for development/testing
- Azure AI Speech Services: 5 hours free per month, then pay-per-use
- Logic Apps: Pay-per-execution model
- Storage Account: Standard LRS pricing
- Power Platform: Premium license required for full functionality

## Quick Start

### Using Bicep (Recommended for Azure)

1. **Deploy the infrastructure:**
   ```bash
   cd bicep/
   
   # Create resource group
   az group create \
       --name rg-voice-automation \
       --location eastus
   
   # Deploy Bicep template
   az deployment group create \
       --resource-group rg-voice-automation \
       --template-file main.bicep \
       --parameters @parameters.json
   ```

2. **Verify deployment:**
   ```bash
   # Check deployment status
   az deployment group show \
       --resource-group rg-voice-automation \
       --name main \
       --query properties.provisioningState
   ```

### Using Terraform

1. **Initialize and deploy:**
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Review planned changes
   terraform plan
   
   # Apply infrastructure changes
   terraform apply
   ```

2. **Verify resources:**
   ```bash
   # Show deployed resources
   terraform show
   
   # Get important outputs
   terraform output speech_service_endpoint
   terraform output logic_app_callback_url
   ```

### Using Bash Scripts

1. **Set environment variables:**
   ```bash
   export RESOURCE_GROUP_NAME="rg-voice-automation-$(date +%s)"
   export LOCATION="eastus"
   export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
   ```

2. **Deploy infrastructure:**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. **Verify deployment:**
   ```bash
   # Check resource group
   az group show --name $RESOURCE_GROUP_NAME
   
   # List created resources
   az resource list --resource-group $RESOURCE_GROUP_NAME --output table
   ```

## Configuration Options

### Bicep Parameters

Key parameters available in `bicep/parameters.json`:

- `speechServiceName`: Name for Azure AI Speech Service
- `logicAppName`: Name for the Logic App workflow
- `storageAccountName`: Name for storage account (must be globally unique)
- `location`: Azure region for deployment
- `speechServiceSku`: Pricing tier for Speech Service (default: S0)

### Terraform Variables

Key variables in `terraform/variables.tf`:

- `resource_group_name`: Name of the resource group
- `location`: Azure region
- `speech_service_name`: Speech service instance name
- `logic_app_name`: Logic App workflow name
- `storage_account_name`: Storage account name
- `tags`: Resource tags for organization and cost tracking

### Script Configuration

Environment variables used by deployment scripts:

- `RESOURCE_GROUP`: Target resource group name
- `LOCATION`: Azure region for resources
- `SPEECH_SERVICE_NAME`: Speech service instance name
- `LOGIC_APP_NAME`: Logic App workflow name
- `STORAGE_ACCOUNT_NAME`: Storage account name

## Post-Deployment Configuration

### 1. Power Platform Setup

After Azure infrastructure deployment, configure Power Platform components:

1. **Create Power Automate Flow:**
   - Navigate to Power Automate portal
   - Import the flow definition from the recipe
   - Configure Dataverse connections
   - Set up approval workflows

2. **Configure Dataverse Tables:**
   - Create the required tables: `voice_automation_approvals` and `voice_automation_audit`
   - Set up proper permissions and security roles
   - Configure data relationships

3. **Set up Power Apps Interface:**
   - Create new Canvas app in Power Apps
   - Import voice interface configuration
   - Connect to Dataverse tables
   - Configure Speech Service integration

### 2. Speech Service Configuration

1. **Access Speech Studio:**
   - Navigate to Speech Studio in Azure portal
   - Create custom commands project
   - Import command definitions from recipe
   - Train and publish speech model

2. **Configure Custom Commands:**
   - Set up approval/rejection patterns
   - Configure update record commands
   - Test voice recognition accuracy
   - Deploy to production endpoint

### 3. Logic App Integration

1. **Update Logic App Workflow:**
   - Configure HTTP trigger endpoint
   - Set up Power Automate webhook connection
   - Test end-to-end integration
   - Enable monitoring and logging

## Testing the Deployment

### 1. Verify Azure Resources

```bash
# Test Speech Service availability
az cognitiveservices account show \
    --name $SPEECH_SERVICE_NAME \
    --resource-group $RESOURCE_GROUP \
    --query '{name:name,state:properties.provisioningState,endpoint:properties.endpoint}'

# Check Logic App status
az logic workflow show \
    --name $LOGIC_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query '{name:name,state:state}'
```

### 2. Test Voice Command Processing

```bash
# Get Logic App trigger URL
LOGIC_APP_URL=$(az logic workflow trigger list \
    --name $LOGIC_APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --query '[0].properties.callbackUrl' --output tsv)

# Test approve request command
curl -X POST "$LOGIC_APP_URL" \
    -H "Content-Type: application/json" \
    -d '{
      "text": "approve request 12345",
      "confidence": 0.95,
      "userId": "test.user@company.com"
    }'
```

### 3. Validate Power Platform Integration

- Test Power Automate flow execution
- Verify Dataverse record creation
- Confirm audit trail functionality
- Test Power Apps voice interface

## Troubleshooting

### Common Issues

1. **Speech Service Authentication Errors:**
   - Verify API keys are correctly configured
   - Check service endpoint URLs
   - Ensure proper IAM permissions

2. **Logic App Connection Failures:**
   - Validate HTTP trigger configuration
   - Check webhook URLs and authentication
   - Review Logic App run history for errors

3. **Power Platform Permission Issues:**
   - Verify Power Platform licensing
   - Check Dataverse permissions
   - Ensure proper environment configuration

### Debugging Steps

1. **Check Azure Resource Status:**
   ```bash
   # Verify all resources are running
   az resource list \
       --resource-group $RESOURCE_GROUP \
       --query '[].{name:name,type:type,state:properties.provisioningState}' \
       --output table
   ```

2. **Monitor Logic App Execution:**
   ```bash
   # Check recent Logic App runs
   az logic workflow run list \
       --name $LOGIC_APP_NAME \
       --resource-group $RESOURCE_GROUP \
       --query '[0:5].{status:status,startTime:startTime,trigger:trigger.name}'
   ```

3. **Test Speech Service Connectivity:**
   ```bash
   # Get Speech Service endpoint and key
   SPEECH_ENDPOINT=$(az cognitiveservices account show \
       --name $SPEECH_SERVICE_NAME \
       --resource-group $RESOURCE_GROUP \
       --query properties.endpoint --output tsv)
   
   SPEECH_KEY=$(az cognitiveservices account keys list \
       --name $SPEECH_SERVICE_NAME \
       --resource-group $RESOURCE_GROUP \
       --query key1 --output tsv)
   
   echo "Speech Service Endpoint: $SPEECH_ENDPOINT"
   echo "Speech Service Key: [REDACTED]"
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-voice-automation \
    --yes \
    --no-wait

# Verify deletion
az group exists --name rg-voice-automation
```

### Using Terraform

```bash
cd terraform/

# Destroy all managed resources
terraform destroy

# Clean up state files (optional)
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Power Platform Cleanup

> **Important**: Azure resource deletion does not automatically remove Power Platform components.

1. **Remove Power Automate Flows:**
   - Navigate to Power Automate portal
   - Delete custom flows created for voice automation
   - Remove any associated connections

2. **Clean up Dataverse:**
   - Delete custom tables: `voice_automation_approvals` and `voice_automation_audit`
   - Remove any test data
   - Clean up security roles and permissions

3. **Remove Power Apps:**
   - Delete the voice automation Canvas app
   - Remove any associated data connections
   - Clean up shared resources

## Security Considerations

### Azure Resources
- Speech Service keys are stored securely in Azure Key Vault (if configured)
- Logic Apps use managed identity for authentication where possible
- Network security groups restrict access to necessary ports only
- All resources use Azure RBAC for access control

### Power Platform
- Dataverse uses environment-level security
- Power Automate flows run under service accounts with minimal permissions
- Audit trails are maintained for all voice commands
- Data loss prevention policies should be configured

### Best Practices
- Regularly rotate Speech Service API keys
- Monitor Logic App execution logs for anomalies
- Implement approval workflows for sensitive voice commands
- Use Azure Monitor for comprehensive logging and alerting

## Customization

### Adding New Voice Commands

1. **Update Speech Service Configuration:**
   - Add new command patterns to Speech Studio
   - Train model with new vocabulary
   - Test recognition accuracy

2. **Modify Logic App Workflow:**
   - Update command parsing logic
   - Add new business logic branches
   - Configure error handling

3. **Extend Power Platform Flows:**
   - Create new Power Automate flows for additional processes
   - Update Dataverse schema if needed
   - Test end-to-end functionality

### Scaling for Production

1. **Performance Optimization:**
   - Upgrade Speech Service to higher SKU if needed
   - Implement Logic App scaling policies
   - Optimize Power Platform flow execution

2. **Monitoring and Alerting:**
   - Set up Azure Monitor dashboards
   - Configure alerts for service failures
   - Implement usage analytics

3. **Security Hardening:**
   - Enable Azure Key Vault integration
   - Implement network isolation
   - Configure advanced threat protection

## Support

For issues with this infrastructure code:

1. **Azure-specific Issues**: Refer to [Azure documentation](https://docs.microsoft.com/en-us/azure/)
2. **Power Platform Issues**: Check [Power Platform documentation](https://docs.microsoft.com/en-us/power-platform/)
3. **Recipe Questions**: Review the original recipe documentation
4. **Integration Issues**: Consult [Azure AI Speech Service documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/)

## Additional Resources

- [Azure AI Speech Service Documentation](https://docs.microsoft.com/en-us/azure/cognitive-services/speech-service/)
- [Power Platform Integration Guide](https://docs.microsoft.com/en-us/power-platform/guidance/integration/overview)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)