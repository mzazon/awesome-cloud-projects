# Infrastructure as Code for Simple Healthcare Chatbot with Azure Health Bot

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Healthcare Chatbot with Azure Health Bot".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.0 or later)
- Azure subscription with contributor access to create Health Bot resources
- Basic understanding of healthcare compliance requirements (HIPAA/HITECH)
- For Terraform: Terraform CLI installed (version 1.0 or later)
- For Bicep: Azure CLI with Bicep extension installed

## Quick Start

### Using Bicep (Recommended)

```bash
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-healthbot-demo \
    --template-file main.bicep \
    --parameters location=eastus \
                 healthBotName=healthbot-$(openssl rand -hex 3) \
                 healthBotSku=F0
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply

# When prompted, confirm with 'yes'
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts for resource naming and configuration
```

## Architecture Overview

This infrastructure deploys:

- **Azure Health Bot Service**: HIPAA-compliant healthcare chatbot service
- **Resource Group**: Container for all healthcare bot resources
- **Built-in Medical Intelligence**: Pre-configured healthcare scenarios and medical databases
- **Web Chat Channel**: Secure, embeddable chat interface for patient interactions
- **Compliance Features**: Audit trails, data encryption, and HIPAA compliance configurations

## Configuration Options

### Common Parameters

- **Location**: Azure region for deployment (default: East US)
- **Resource Group**: Name of the resource group to contain all resources
- **Health Bot Name**: Unique name for the Azure Health Bot instance
- **SKU**: Pricing tier (F0 for free tier, S1 for standard)

### Bicep Parameters

Modify the parameters in `main.bicep` or pass them during deployment:

```bicep
param location string = 'eastus'
param resourceGroupName string = 'rg-healthbot-demo'
param healthBotName string = 'healthbot-${uniqueString(resourceGroup().id)}'
param healthBotSku string = 'F0'
param tags object = {
  purpose: 'healthcare-chatbot'
  environment: 'demo'
}
```

### Terraform Variables

Customize deployment by modifying `terraform.tfvars` or using command-line variables:

```hcl
# terraform.tfvars
location            = "East US"
resource_group_name = "rg-healthbot-demo"
health_bot_name     = "healthbot-unique-name"
health_bot_sku      = "F0"
environment         = "demo"
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these configuration steps:

1. **Access Health Bot Management Portal**:
   ```bash
   # Get the management portal URL from deployment outputs
   echo "Management Portal: $(az healthbot show --name <health-bot-name> --resource-group <resource-group> --query properties.botManagementPortalLink -o tsv)"
   ```

2. **Configure Healthcare Scenarios**:
   - Navigate to the Management Portal
   - Enable built-in scenarios (symptom checker, disease information, medication guidance)
   - Customize scenarios for your organization's specific needs

3. **Set Up Web Chat Channel**:
   - In the Management Portal, go to Integration > Channels
   - Enable the Web Chat channel
   - Configure channel settings and security options
   - Copy the embed code for your website or patient portal

4. **Configure HIPAA Compliance Settings**:
   - Review audit trail configuration
   - Set up data retention policies
   - Configure user consent management
   - Enable conversation encryption

## Testing the Deployment

### Verify Health Bot Service

```bash
# Check Health Bot deployment status
az healthbot show \
    --name <health-bot-name> \
    --resource-group <resource-group> \
    --query "properties.provisioningState" \
    --output tsv
```

Expected output: `Succeeded`

### Test Healthcare Scenarios

Access the Management Portal and test these scenarios:

- **Symptom Assessment**: "I have chest pain" or "I have a headache"
- **Disease Information**: "What is diabetes?" or "Tell me about hypertension"
- **Medication Queries**: "What is aspirin used for?" or "Side effects of ibuprofen"
- **Provider Guidance**: "What doctor treats back pain?" or "When should I see a cardiologist?"

### Validate Compliance Features

- Verify audit logging is enabled
- Check data encryption configuration
- Review user consent management settings
- Test session timeout and security features

## Customization

### Adding Custom Medical Scenarios

1. Access the Health Bot Management Portal
2. Navigate to Scenarios > Create New Scenario
3. Use the scenario editor to create organization-specific flows
4. Test scenarios in the portal before publishing

### Integration with External Systems

- **EHR Integration**: Use Azure Logic Apps to connect with FHIR services
- **Appointment Scheduling**: Integrate with scheduling systems via REST APIs
- **Analytics**: Connect to Azure Application Insights for conversation analytics

### Multi-Channel Support

Enable additional communication channels:

- **Microsoft Teams**: For internal healthcare staff communication
- **SMS**: For patient outreach and reminders
- **Facebook Messenger**: For patient engagement (if compliant with policies)

## Cost Optimization

### Pricing Tiers

- **F0 (Free)**: Limited to 3,000 messages per month, suitable for testing
- **S1 (Standard)**: Unlimited messages, starts at $500/month, includes premium features

### Cost Management

```bash
# Monitor Azure Health Bot costs
az consumption usage list \
    --scope "/subscriptions/<subscription-id>/resourceGroups/<resource-group>" \
    --start-date "2025-01-01" \
    --end-date "2025-01-31"
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all contained resources
az group delete \
    --name rg-healthbot-demo \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

## Security Considerations

### HIPAA Compliance

- Azure Health Bot includes built-in HIPAA compliance features
- Ensure proper Business Associate Agreement (BAA) with Microsoft
- Configure audit trails and data retention policies
- Review [Microsoft HIPAA compliance documentation](https://learn.microsoft.com/en-us/compliance/regulatory/offering-hipaa-hitech)

### Data Protection

- All conversations are encrypted in transit and at rest
- Patient data is processed according to healthcare compliance requirements
- Audit trails track all system interactions
- Session management includes automatic timeout for security

### Access Control

- Use Azure Active Directory for administrative access
- Implement role-based access control (RBAC) for management portal
- Monitor access logs for unauthorized attempts
- Regular review of user permissions and access patterns

## Troubleshooting

### Common Issues

1. **Deployment Failures**:
   - Verify Azure CLI authentication
   - Check subscription permissions
   - Ensure resource names are unique
   - Review quota limits for Health Bot services

2. **Management Portal Access**:
   - Verify user has appropriate Azure AD permissions
   - Check network connectivity and firewall rules
   - Clear browser cache and cookies
   - Try incognito/private browsing mode

3. **Channel Configuration**:
   - Verify channel settings in management portal
   - Check embed code integration on websites
   - Test cross-origin resource sharing (CORS) settings
   - Validate SSL/TLS certificate configuration

### Support Resources

- [Azure Health Bot Documentation](https://learn.microsoft.com/en-us/azure/health-bot/)
- [Azure Support Plans](https://azure.microsoft.com/en-us/support/plans/)
- [Healthcare Compliance Resources](https://learn.microsoft.com/en-us/compliance/regulatory/offering-hipaa-hitech)
- [Azure Architecture Center](https://learn.microsoft.com/en-us/azure/architecture/)

## Contributing

To improve this infrastructure code:

1. Test deployments in multiple Azure regions
2. Enhance security configurations
3. Add monitoring and alerting capabilities
4. Improve error handling in scripts
5. Update documentation with new Azure features

## License

This infrastructure code is provided as-is for educational and reference purposes. Ensure compliance with your organization's policies and healthcare regulations before production use.