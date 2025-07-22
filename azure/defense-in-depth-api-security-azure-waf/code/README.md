# Infrastructure as Code for Defense-in-Depth API Security with Azure API Management and Web Application Firewall

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Defense-in-Depth API Security with Azure API Management and Web Application Firewall".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code with Azure provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50.0 or later installed and configured
- Azure account with Contributor permissions on a subscription
- Basic understanding of API security concepts and zero-trust architecture
- For Bicep: Azure CLI with Bicep extension installed
- For Terraform: Terraform v1.0+ installed
- Estimated cost: $150-300/month for Standard tier resources

### Bicep Prerequisites

```bash
# Install Bicep extension for Azure CLI
az bicep install

# Verify installation
az bicep version
```

### Terraform Prerequisites

```bash
# Install Terraform (using package manager or download from hashicorp.com)
# For macOS with Homebrew:
brew install terraform

# Verify installation
terraform version
```

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Set deployment parameters
RESOURCE_GROUP="rg-zero-trust-api-$(openssl rand -hex 3)"
LOCATION="eastus"

# Create resource group
az group create \
    --name ${RESOURCE_GROUP} \
    --location ${LOCATION}

# Deploy infrastructure
az deployment group create \
    --resource-group ${RESOURCE_GROUP} \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json \
    --parameters resourceGroupName=${RESOURCE_GROUP} \
    --parameters location=${LOCATION}
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan \
    -var="resource_group_name=rg-zero-trust-api-$(openssl rand -hex 3)" \
    -var="location=eastus"

# Apply infrastructure
terraform apply \
    -var="resource_group_name=rg-zero-trust-api-$(openssl rand -hex 3)" \
    -var="location=eastus"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts for configuration options
```

## Architecture Overview

This infrastructure deploys a comprehensive zero-trust API security architecture including:

- **Virtual Network**: Segmented subnets for Application Gateway, API Management, and Private Endpoints
- **Application Gateway**: Load balancer with integrated Web Application Firewall
- **Web Application Firewall**: OWASP Core Rule Set protection and custom security rules
- **API Management**: Internal mode deployment with comprehensive security policies
- **Private Link**: Secure connectivity for backend services
- **Monitoring**: Application Insights and Log Analytics for security observability

## Configuration Options

### Bicep Parameters

The `bicep/parameters.json` file contains configurable values:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "apimSkuName": {
      "value": "Standard"
    },
    "applicationGatewaySkuName": {
      "value": "WAF_v2"
    },
    "enablePrivateLink": {
      "value": true
    },
    "wafMode": {
      "value": "Prevention"
    },
    "rateLimitThreshold": {
      "value": 100
    }
  }
}
```

### Terraform Variables

Customize deployment by modifying variables in `terraform/terraform.tfvars`:

```hcl
# Resource configuration
resource_group_name = "rg-zero-trust-api"
location           = "eastus"
environment        = "demo"

# API Management configuration
apim_sku_name     = "Standard"
apim_capacity     = 1

# Application Gateway configuration
agw_sku_name      = "WAF_v2"
agw_capacity      = 2

# Security configuration
waf_mode                = "Prevention"
rate_limit_threshold   = 100
enable_private_link    = true

# Monitoring configuration
log_retention_days = 30
```

## Security Features

### Web Application Firewall Protection

- **OWASP Core Rule Set 3.2**: Protection against common web vulnerabilities
- **Rate Limiting**: Prevents abuse with configurable request thresholds
- **Custom Rules**: Tailored security rules for API-specific threats
- **Prevention Mode**: Actively blocks malicious requests

### API Management Security Policies

- **JWT Validation**: Azure AD authentication integration
- **Rate Limiting**: Per-client and global request limits
- **IP Filtering**: Network-based access controls
- **Security Headers**: Removal of sensitive server information
- **Request Logging**: Comprehensive audit trails

### Network Security

- **Virtual Network Integration**: API Management deployed in internal mode
- **Private Endpoints**: Secure backend connectivity without internet exposure
- **Network Segmentation**: Dedicated subnets for different security zones
- **Private DNS**: Internal name resolution for private resources

## Monitoring and Observability

### Application Insights Integration

- Real-time API performance monitoring
- Security event tracking and alerting
- Custom telemetry for business metrics
- Integration with Azure Monitor dashboards

### Log Analytics Workspace

- Centralized logging for all security events
- WAF attack pattern analysis
- API usage analytics and reporting
- Compliance audit trails

### Key Metrics to Monitor

- API request volumes and response times
- WAF blocked requests and attack patterns
- Authentication failures and security violations
- Rate limiting triggers and client behavior
- Backend service health and availability

## Validation and Testing

### Post-Deployment Verification

```bash
# Get Application Gateway public IP
AGW_PUBLIC_IP=$(az network public-ip show \
    --resource-group ${RESOURCE_GROUP} \
    --name agw-zerotrust-*-pip \
    --query ipAddress --output tsv)

# Test API endpoint availability
curl -X GET "http://${AGW_PUBLIC_IP}/secure/data" \
     -H "Authorization: Bearer your-jwt-token" \
     -v

# Test WAF protection (should return 403)
curl -X GET "http://${AGW_PUBLIC_IP}/secure/data" \
     -H "User-Agent: <script>alert('xss')</script>" \
     -v
```

### Security Testing

```bash
# Test rate limiting
for i in {1..15}; do
    curl -X GET "http://${AGW_PUBLIC_IP}/secure/data" \
         -w "%{http_code}\n" \
         -s -o /dev/null
done

# Verify private network isolation
APIM_GATEWAY_URL=$(az apim show \
    --resource-group ${RESOURCE_GROUP} \
    --name apim-zerotrust-* \
    --query gatewayUrl --output tsv)

curl -X GET "${APIM_GATEWAY_URL}/secure/data" \
     --connect-timeout 10 \
     --max-time 30
# Should fail with connection timeout
```

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete \
    --name ${RESOURCE_GROUP} \
    --yes \
    --no-wait

# Verify deletion
az group exists --name ${RESOURCE_GROUP}
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="resource_group_name=${RESOURCE_GROUP}" \
    -var="location=eastus"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

**API Management Deployment Timeout**
- API Management Standard tier deployment takes 20-30 minutes
- Use `--no-wait` flag for asynchronous deployment
- Monitor deployment status with `az deployment group show`

**WAF Blocking Legitimate Requests**
- Review WAF logs in Log Analytics workspace
- Adjust custom rules or exclusions as needed
- Consider switching to Detection mode for testing

**Private Endpoint Connectivity Issues**
- Verify DNS resolution for private endpoints
- Check network security group rules
- Ensure proper subnet delegation

**High Costs**
- Monitor resource usage with Azure Cost Management
- Consider using Consumption tier for API Management in development
- Review Application Gateway instance count and size

### Debug Commands

```bash
# Check API Management status
az apim show \
    --resource-group ${RESOURCE_GROUP} \
    --name apim-zerotrust-* \
    --query provisioningState

# Review WAF logs
az monitor log-analytics query \
    --workspace ${WORKSPACE_ID} \
    --analytics-query "AzureDiagnostics | where Category == 'ApplicationGatewayFirewallLog' | take 10"

# Check Application Gateway health
az network application-gateway show-backend-health \
    --resource-group ${RESOURCE_GROUP} \
    --name agw-zerotrust-*
```

## Customization

### Adding Custom WAF Rules

Edit the WAF policy configuration to add specific security rules for your APIs:

```bicep
// In main.bicep, add custom rules to the WAF policy
resource wafCustomRule 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies/customRules@2023-04-01' = {
  parent: wafPolicy
  name: 'BlockSpecificUserAgent'
  properties: {
    priority: 200
    ruleType: 'MatchRule'
    action: 'Block'
    matchConditions: [
      {
        matchVariables: [
          {
            variableName: 'RequestHeaders'
            selector: 'User-Agent'
          }
        ]
        operator: 'Contains'
        matchValues: ['BadBot']
        negateCondition: false
      }
    ]
  }
}
```

### API Policy Customization

Modify API Management policies in the template to add specific authentication or transformation requirements for your APIs.

### Scaling Configuration

Adjust capacity and SKU settings based on your expected traffic:

- **Development**: Basic/Standard tier with minimal capacity
- **Production**: Premium tier with auto-scaling enabled
- **High Availability**: Multi-region deployment with Traffic Manager

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for context
2. Check Azure service limits and quotas
3. Consult Azure API Management and Application Gateway documentation
4. Use Azure Support for production issues

## Security Best Practices

- Regularly update WAF rule sets and API policies
- Monitor security logs and set up alerting
- Implement certificate rotation for TLS/SSL
- Use managed identities for service-to-service authentication
- Enable diagnostic logging for all components
- Regular security assessments and penetration testing

## Cost Optimization

- Use Azure Advisor recommendations for cost optimization
- Consider reserved instances for predictable workloads
- Implement auto-scaling based on demand
- Monitor and optimize data transfer costs
- Use Azure Cost Management alerts and budgets