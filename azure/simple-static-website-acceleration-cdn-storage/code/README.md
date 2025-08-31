# Infrastructure as Code for Static Website Acceleration with CDN and Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Static Website Acceleration with CDN and Storage".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code using Azure provider
- **Scripts**: Bash deployment and cleanup scripts with Azure CLI

## Prerequisites

- Azure CLI installed and configured (version 2.30.0 or later)
- Active Azure subscription with appropriate permissions:
  - Storage Account Contributor
  - CDN Profile Contributor
  - Resource Group Contributor
- Basic understanding of static website hosting concepts
- Web content files (HTML, CSS, JavaScript) ready for deployment

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to bicep directory
cd bicep/

# Deploy the infrastructure
az deployment group create \
    --resource-group rg-static-website \
    --template-file main.bicep \
    --parameters siteName=mystaticsite \
    --parameters location=eastus

# Upload your website content after deployment
az storage blob upload-batch \
    --account-name <storage-account-name> \
    --source ./website-content \
    --destination '$web'
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Follow the prompts for configuration
```

## Configuration Options

### Bicep Parameters

- `siteName`: Unique name for your static website (required)
- `location`: Azure region for deployment (default: eastus)
- `storageAccountSku`: Storage account performance tier (default: Standard_LRS)
- `cdnSku`: CDN profile SKU (default: Standard_Microsoft)

### Terraform Variables

- `resource_group_name`: Name for the resource group
- `location`: Azure region for resources
- `storage_account_name`: Storage account name (must be globally unique)
- `cdn_profile_name`: CDN profile name
- `cdn_endpoint_name`: CDN endpoint name
- `tags`: Resource tags for organization and billing

### Script Configuration

The deployment script will prompt for:
- Resource group name
- Azure region
- Storage account name
- CDN configuration preferences

## Deployment Process

### What Gets Created

1. **Resource Group**: Container for all resources
2. **Storage Account**: 
   - StorageV2 with Hot access tier
   - Static website hosting enabled
   - HTTPS-only access enforced
3. **CDN Profile**: Microsoft standard tier for global distribution
4. **CDN Endpoint**: 
   - Compression enabled for web content
   - Optimized for general web delivery
   - Query string caching configured

### Post-Deployment Steps

After infrastructure deployment, upload your website content:

```bash
# Upload HTML files
az storage blob upload-batch \
    --account-name <storage-account-name> \
    --source ./your-website-folder \
    --destination '$web' \
    --pattern "*.html" \
    --content-type "text/html"

# Upload CSS files
az storage blob upload-batch \
    --account-name <storage-account-name> \
    --source ./your-website-folder \
    --destination '$web' \
    --pattern "*.css" \
    --content-type "text/css"

# Upload JavaScript files
az storage blob upload-batch \
    --account-name <storage-account-name> \
    --source ./your-website-folder \
    --destination '$web' \
    --pattern "*.js" \
    --content-type "application/javascript"
```

## Validation

### Verify Deployment

1. **Check Resource Group**:
   ```bash
   az group show --name <resource-group-name>
   ```

2. **Verify Storage Account**:
   ```bash
   az storage account show --name <storage-account-name> \
       --resource-group <resource-group-name>
   ```

3. **Test Static Website**:
   ```bash
   # Get the static website URL
   WEBSITE_URL=$(az storage account show \
       --name <storage-account-name> \
       --resource-group <resource-group-name> \
       --query "primaryEndpoints.web" \
       --output tsv)
   
   echo "Website URL: $WEBSITE_URL"
   curl -I $WEBSITE_URL
   ```

4. **Test CDN Endpoint**:
   ```bash
   # Get CDN endpoint URL
   CDN_URL=$(az cdn endpoint show \
       --name <cdn-endpoint-name> \
       --profile-name <cdn-profile-name> \
       --resource-group <resource-group-name> \
       --query "hostName" \
       --output tsv)
   
   echo "CDN URL: https://$CDN_URL"
   curl -I https://$CDN_URL
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete --name <resource-group-name> --yes --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy
# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
# Follow the prompts for confirmation
```

## Customization

### Adding Custom Domain

To configure a custom domain for your CDN endpoint:

```bash
# Add custom domain to CDN endpoint
az cdn custom-domain create \
    --endpoint-name <cdn-endpoint-name> \
    --hostname <your-domain.com> \
    --name <custom-domain-name> \
    --profile-name <cdn-profile-name> \
    --resource-group <resource-group-name>

# Enable HTTPS for custom domain
az cdn custom-domain enable-https \
    --endpoint-name <cdn-endpoint-name> \
    --name <custom-domain-name> \
    --profile-name <cdn-profile-name> \
    --resource-group <resource-group-name>
```

### Advanced CDN Configuration

For additional CDN optimizations:

```bash
# Configure custom caching rules
az cdn endpoint rule add \
    --action-name "CacheExpiration" \
    --cache-behavior "SetIfMissing" \
    --cache-duration "7.00:00:00" \
    --endpoint-name <cdn-endpoint-name> \
    --match-variable "RequestScheme" \
    --operator "Equal" \
    --profile-name <cdn-profile-name> \
    --resource-group <resource-group-name> \
    --rule-name "CacheStaticContent"
```

### Monitoring Setup

Enable monitoring for your static website:

```bash
# Create Application Insights instance
az monitor app-insights component create \
    --app <app-insights-name> \
    --location <location> \
    --resource-group <resource-group-name> \
    --tags purpose=monitoring
```

## Troubleshooting

### Common Issues

1. **Storage Account Name Conflicts**:
   - Storage account names must be globally unique
   - Use the random suffix approach from the recipe
   - Try different names if deployment fails

2. **CDN Propagation Delays**:
   - CDN endpoints can take 5-10 minutes to become fully active
   - Allow time for global propagation before testing
   - Use cache-busting parameters during initial testing

3. **Content Upload Failures**:
   - Ensure proper authentication with Azure CLI
   - Verify storage account permissions
   - Check content-type headers for proper serving

### Debugging Commands

```bash
# Check resource deployment status
az deployment group show \
    --resource-group <resource-group-name> \
    --name <deployment-name>

# View activity logs
az monitor activity-log list \
    --resource-group <resource-group-name> \
    --max-events 50

# Test CDN cache headers
curl -H "Accept-Encoding: gzip" -I https://<cdn-endpoint>.azureedge.net
```

## Cost Optimization

### Storage Costs

- Use appropriate access tiers for content frequency
- Enable lifecycle policies for old content
- Monitor storage metrics and optimize accordingly

### CDN Costs

- Monitor bandwidth usage and cache hit ratios
- Use appropriate CDN tier for your traffic patterns
- Consider regional CDN if global distribution isn't needed

### Resource Tagging

All implementations include proper resource tagging for:
- Cost allocation and tracking
- Environment identification
- Automated management policies

## Security Considerations

### Storage Security

- HTTPS-only access is enforced by default
- Public read access is limited to the $web container
- Storage keys are managed through Azure Key Vault integration

### CDN Security

- Origin host header validation prevents direct access bypass
- Compression is enabled for supported content types
- DDoS protection is included with Standard Microsoft tier

## Performance Optimization

### Best Practices Implemented

- Automatic compression for text-based content
- Optimized query string caching behavior
- General web delivery optimization enabled
- Proper content-type headers for all file types

### Monitoring Performance

```bash
# Check CDN analytics
az cdn endpoint usage show \
    --name <cdn-endpoint-name> \
    --profile-name <cdn-profile-name> \
    --resource-group <resource-group-name>
```

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation
2. Check Azure documentation for specific services:
   - [Azure Storage static websites](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-blob-static-website)
   - [Azure CDN documentation](https://docs.microsoft.com/en-us/azure/cdn/)
3. Review Azure CLI reference documentation
4. Check service health status at [Azure Status](https://status.azure.com/)

## Next Steps

After successful deployment, consider implementing:

1. **Custom Domain Configuration**: Add your own domain name
2. **SSL Certificate Management**: Implement automatic certificate renewal
3. **Advanced Monitoring**: Set up Application Insights and custom dashboards
4. **CI/CD Integration**: Automate content deployment with GitHub Actions
5. **Security Enhancements**: Add Web Application Firewall rules