# Infrastructure as Code for Simple Contact Form with Functions and Table Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Contact Form with Functions and Table Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (Microsoft's recommended IaC language)
- **Terraform**: Multi-cloud infrastructure as code using official Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured (version 2.57.0 or later)
- Active Azure subscription with appropriate permissions for:
  - Resource Group creation and management
  - Azure Functions deployment
  - Azure Storage Account creation
  - Table Storage operations
- Basic understanding of serverless architecture and HTTP APIs
- Text editor or IDE for customizing parameters

### Tool-Specific Prerequisites

#### For Bicep
- Azure CLI with Bicep extension (automatically installed with latest Azure CLI)
- PowerShell or Bash terminal

#### For Terraform
- Terraform installed (version 1.0 or later)
- Azure CLI authentication configured

#### For Bash Scripts
- Bash shell (Linux, macOS, or Windows with WSL)
- `curl` and `zip` utilities
- `openssl` for generating random values

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group "rg-contact-form" \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters uniqueSuffix=$(openssl rand -hex 3)
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for configuration values
# or you can set environment variables:
export LOCATION="eastus"
export RESOURCE_GROUP_PREFIX="rg-contact-form"
./scripts/deploy.sh
```

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for resources | `eastus` | No |
| `uniqueSuffix` | Unique suffix for resource names | Generated | No |
| `functionAppName` | Name for the Function App | `func-contact-{suffix}` | No |
| `storageAccountName` | Name for Storage Account | `stcontact{suffix}` | No |
| `resourceGroupName` | Name for Resource Group | `rg-recipe-{suffix}` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `location` | Azure region | `string` | `"East US"` | No |
| `resource_group_name` | Resource group name | `string` | `""` | No |
| `storage_account_name` | Storage account name | `string` | `""` | No |
| `function_app_name` | Function app name | `string` | `""` | No |
| `tags` | Resource tags | `map(string)` | `{}` | No |

### Environment Variables for Bash Scripts

| Variable | Description | Default |
|----------|-------------|---------|
| `LOCATION` | Azure region | `eastus` |
| `RESOURCE_GROUP_PREFIX` | Prefix for resource group | `rg-recipe` |
| `STORAGE_ACCOUNT_PREFIX` | Prefix for storage account | `stcontact` |
| `FUNCTION_APP_PREFIX` | Prefix for function app | `func-contact` |

## Deployment Details

### What Gets Deployed

1. **Resource Group**: Container for all resources with appropriate tags
2. **Storage Account**: 
   - Standard_LRS replication for cost efficiency
   - Configured for both Function App runtime and Table Storage
   - Table named "contacts" for storing form submissions
3. **Function App**:
   - Consumption plan for automatic scaling and pay-per-use pricing
   - Node.js 20 runtime environment
   - Application Insights integration for monitoring
4. **HTTP Trigger Function**:
   - Accepts POST requests at `/api/contact` endpoint
   - Validates form data (name, email, message)
   - Stores submissions in Table Storage
   - CORS-enabled for web integration

### Security Configuration

- Function-level authentication (function key required)
- CORS headers configured for web browser compatibility
- Input validation and sanitization
- Storage connection secured through managed identity where possible
- Application Insights for monitoring and logging

### Cost Estimation

Based on Azure pricing (subject to change):
- **Storage Account**: ~$0.05/month for minimal usage
- **Function App**: $0.000016 per execution + $0.000014 per GB-second
- **Application Insights**: First 5GB free, then $2.88/GB
- **Total estimated cost**: $0.50-$5.00/month depending on usage

## Testing Your Deployment

### 1. Verify Function App Status

```bash
# Using Azure CLI
az functionapp show \
    --name "<your-function-app-name>" \
    --resource-group "<your-resource-group>" \
    --query "state"
```

### 2. Test the Contact Form Endpoint

```bash
# Get the function URL and key
FUNCTION_URL=$(az functionapp function show \
    --resource-group "<your-resource-group>" \
    --name "<your-function-app-name>" \
    --function-name "contact-function" \
    --query "invokeUrlTemplate" \
    --output tsv)

FUNCTION_KEY=$(az functionapp keys list \
    --name "<your-function-app-name>" \
    --resource-group "<your-resource-group>" \
    --query "functionKeys.default" \
    --output tsv)

# Test the endpoint
curl -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "Test User",
        "email": "test@example.com", 
        "message": "Testing the contact form!"
    }'
```

### 3. Verify Data Storage

```bash
# Check stored contact submissions
az storage entity query \
    --table-name "contacts" \
    --account-name "<your-storage-account>" \
    --select "Name,Email,SubmittedAt"
```

## Integration with Web Applications

### HTML Form Example

```html
<form id="contactForm">
    <input type="text" name="name" placeholder="Your Name" required>
    <input type="email" name="email" placeholder="Your Email" required>
    <textarea name="message" placeholder="Your Message" required></textarea>
    <button type="submit">Send Message</button>
</form>

<script>
document.getElementById('contactForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const formData = new FormData(e.target);
    const data = Object.fromEntries(formData);
    
    try {
        const response = await fetch('YOUR_FUNCTION_URL', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
        });
        
        const result = await response.json();
        alert(response.ok ? 'Message sent!' : result.error);
    } catch (error) {
        alert('Error sending message');
    }
});
</script>
```

### React Component Example

```jsx
import { useState } from 'react';

function ContactForm() {
    const [formData, setFormData] = useState({ name: '', email: '', message: '' });
    const [status, setStatus] = useState('');

    const handleSubmit = async (e) => {
        e.preventDefault();
        setStatus('sending');
        
        try {
            const response = await fetch('YOUR_FUNCTION_URL', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(formData)
            });
            
            setStatus(response.ok ? 'success' : 'error');
        } catch (error) {
            setStatus('error');
        }
    };

    return (
        <form onSubmit={handleSubmit}>
            <input 
                type="text" 
                placeholder="Name"
                value={formData.name}
                onChange={(e) => setFormData({...formData, name: e.target.value})}
                required 
            />
            <input 
                type="email" 
                placeholder="Email"
                value={formData.email}
                onChange={(e) => setFormData({...formData, email: e.target.value})}
                required 
            />
            <textarea 
                placeholder="Message"
                value={formData.message}
                onChange={(e) => setFormData({...formData, message: e.target.value})}
                required 
            />
            <button type="submit" disabled={status === 'sending'}>
                {status === 'sending' ? 'Sending...' : 'Send Message'}
            </button>
            {status === 'success' && <p>Message sent successfully!</p>}
            {status === 'error' && <p>Error sending message. Please try again.</p>}
        </form>
    );
}
```

## Monitoring and Troubleshooting

### Application Insights Queries

```kusto
// View recent contact form submissions
traces
| where timestamp > ago(24h)
| where message contains "Contact form submitted"
| project timestamp, message, customDimensions

// Monitor function performance
requests
| where timestamp > ago(1h)
| where name == "contact-function"
| summarize avg(duration), count() by bin(timestamp, 5m)

// Check for errors
exceptions
| where timestamp > ago(24h)
| where cloud_RoleName == "your-function-app-name"
| project timestamp, type, outerMessage, operation_Name
```

### Common Issues

1. **CORS Errors**: Ensure your web domain is allowed or use wildcard (*)
2. **Function Key Issues**: Verify function key is correct and not expired
3. **Storage Connection**: Check storage account connection string configuration
4. **Validation Errors**: Ensure all required fields (name, email, message) are provided

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name "<your-resource-group>" \
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

# Or manually delete the resource group
az group delete --name "<your-resource-group>" --yes
```

## Customization

### Adding Email Notifications

To extend this solution with email notifications, consider integrating:
- Azure Communication Services for transactional emails
- Azure Logic Apps for workflow automation
- SendGrid integration through Azure Marketplace

### Enhanced Security

For production deployments, implement:
- Azure API Management for rate limiting
- Azure Application Gateway for WAF protection
- Managed Identity for secure resource access
- Azure Key Vault for secrets management

### Data Processing

Extend the solution with:
- Azure Event Grid for real-time notifications
- Azure Stream Analytics for form submission analytics
- Power BI for contact submission dashboards
- Azure Cognitive Services for content moderation

## Support

For issues with this infrastructure code:
1. Check the original recipe documentation for implementation details
2. Review Azure Functions documentation for configuration options
3. Consult Azure Table Storage best practices for data management
4. Use Azure Application Insights for runtime troubleshooting

For Azure-specific issues, refer to:
- [Azure Functions documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Azure Table Storage documentation](https://docs.microsoft.com/en-us/azure/storage/tables/)
- [Bicep documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Terraform Azure Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)