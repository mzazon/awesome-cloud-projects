# Infrastructure as Code for Edge-Secured Web Applications with Azure Static Web Apps and Front Door WAF

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Edge-Secured Web Applications with Azure Static Web Apps and Front Door WAF".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (declarative ARM template language)
- **Terraform**: Multi-cloud infrastructure as code using HashiCorp Configuration Language
- **Scripts**: Bash deployment and cleanup scripts for automated provisioning

## Prerequisites

- Azure CLI v2.53.0 or later installed and configured
- Azure subscription with Owner or Contributor permissions
- For Bicep: Azure CLI with Bicep extension installed
- For Terraform: Terraform v1.0+ installed with Azure provider
- Git installed for source code management
- Basic understanding of web security concepts and CDN principles

## Resource Overview

This infrastructure creates:

- **Azure Static Web Apps** (Standard tier) with enterprise features
- **Azure Front Door** (Standard tier) for global content delivery
- **Web Application Firewall (WAF) Policy** with OWASP protection and custom rules
- **Security configurations** including rate limiting and geo-filtering
- **Caching and compression** optimizations for performance

**Estimated Monthly Cost**: $15-30 USD (varies by traffic volume)

## Quick Start

### Using Bicep

Deploy the infrastructure using Azure's native Bicep language:

```bash
# Navigate to Bicep directory
cd bicep/

# Deploy main template with parameter file
az deployment group create \
    --resource-group "rg-secure-webapp" \
    --template-file main.bicep \
    --parameters @parameters.json

# Alternative: Deploy with inline parameters
az deployment group create \
    --resource-group "rg-secure-webapp" \
    --template-file main.bicep \
    --parameters location=eastus \
                 projectName=securewebapp \
                 environment=production
```

### Using Terraform

Deploy using HashiCorp Terraform for infrastructure automation:

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review planned changes
terraform plan -var="project_name=securewebapp" \
               -var="environment=production" \
               -var="location=East US"

# Apply infrastructure changes
terraform apply -var="project_name=securewebapp" \
                -var="environment=production" \
                -var="location=East US"

# View important outputs
terraform output
```

### Using Bash Scripts

Use automated scripts for streamlined deployment:

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export AZURE_LOCATION="East US"
export PROJECT_NAME="securewebapp"
export ENVIRONMENT="production"

# Deploy infrastructure
./deploy.sh

# View deployment status
az deployment group list --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}"
```

## Configuration Options

### Key Parameters

| Parameter | Description | Default | Bicep Variable | Terraform Variable |
|-----------|-------------|---------|----------------|-------------------|
| Project Name | Unique identifier for resources | `securewebapp` | `projectName` | `project_name` |
| Environment | Deployment environment | `production` | `environment` | `environment` |
| Location | Azure region | `East US` | `location` | `location` |
| SKU Tier | Service tier for Front Door | `Standard_AzureFrontDoor` | `frontDoorSku` | `front_door_sku` |
| WAF Mode | WAF operation mode | `Prevention` | `wafMode` | `waf_mode` |

### Security Configurations

The infrastructure includes these security features by default:

- **OWASP Top 10 Protection**: Microsoft Default Rule Set v2.1
- **Bot Protection**: Microsoft Bot Manager Rule Set v1.0
- **Rate Limiting**: 100 requests per minute per IP address
- **Geo-filtering**: Configurable country allowlist
- **HTTPS Enforcement**: Automatic HTTP to HTTPS redirection
- **Origin Protection**: Static Web App restricted to Front Door traffic only

### Performance Optimizations

- **Edge Caching**: 7-day cache duration for static assets (.css, .js, images)
- **Compression**: Automatic gzip compression for text-based content
- **Global Distribution**: Content served from 192+ Azure edge locations
- **Intelligent Routing**: Optimal path selection based on network conditions

## Validation & Testing

After deployment, verify the infrastructure:

```bash
# Test Front Door endpoint accessibility
FRONT_DOOR_ENDPOINT=$(az afd endpoint show \
    --endpoint-name "endpoint-${PROJECT_NAME}" \
    --profile-name "afd-${PROJECT_NAME}" \
    --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}" \
    --query hostName -o tsv)

curl -I "https://${FRONT_DOOR_ENDPOINT}"

# Test WAF protection (should return 403 Forbidden)
curl -X GET "https://${FRONT_DOOR_ENDPOINT}/?id=1' OR '1'='1"

# Test rate limiting (should return 429 after threshold)
for i in {1..150}; do
    curl -s -o /dev/null -w "%{http_code}\n" "https://${FRONT_DOOR_ENDPOINT}"
done | sort | uniq -c
```

## Monitoring & Observability

Enable comprehensive monitoring with these commands:

```bash
# Create Log Analytics workspace for WAF logs
az monitor log-analytics workspace create \
    --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}" \
    --workspace-name "law-${PROJECT_NAME}-${ENVIRONMENT}"

# Configure diagnostic settings for WAF
az monitor diagnostic-settings create \
    --name "waf-diagnostics" \
    --resource "$(az network front-door waf-policy show \
        --name "wafpolicy${PROJECT_NAME}" \
        --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}" \
        --query id -o tsv)" \
    --workspace "law-${PROJECT_NAME}-${ENVIRONMENT}" \
    --logs '[{"category":"FrontDoorWebApplicationFirewallLog","enabled":true}]'
```

## Cleanup

### Using Bicep

Remove resources deployed with Bicep:

```bash
# Delete the resource group and all contained resources
az group delete \
    --name "rg-secure-webapp" \
    --yes \
    --no-wait

# Verify deletion status
az group exists --name "rg-secure-webapp"
```

### Using Terraform

Clean up Terraform-managed infrastructure:

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all managed resources
terraform destroy -var="project_name=securewebapp" \
                  -var="environment=production" \
                  -var="location=East US"

# Verify state is empty
terraform show
```

### Using Bash Scripts

Use the automated cleanup script:

```bash
# Navigate to scripts directory
cd scripts/

# Set environment variables (if not already set)
export PROJECT_NAME="securewebapp"
export ENVIRONMENT="production"

# Run cleanup script with confirmation
./destroy.sh

# Verify resource cleanup
az resource list --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}"
```

## Customization

### Adding Custom WAF Rules

To add application-specific security rules, modify the WAF policy configuration:

**Bicep**: Edit the `customRules` array in `main.bicep`
**Terraform**: Modify the `custom_rule` blocks in `main.tf`
**Scripts**: Add additional `az network front-door waf-policy custom-rule create` commands

### Multi-Region Deployment

For global redundancy, deploy Static Web Apps in multiple regions:

1. Modify the template to include additional Static Web App instances
2. Configure Front Door origin groups with multiple origins
3. Implement health probes for automatic failover

### Custom Domain Configuration

To use your own domain:

1. Add a custom domain to the Front Door configuration
2. Configure DNS records to point to the Front Door endpoint
3. Enable managed SSL certificates or upload custom certificates

## Troubleshooting

### Common Issues

1. **WAF Blocking Legitimate Traffic**: Review WAF logs and adjust custom rules
2. **Static Web App Access Denied**: Verify Front Door integration configuration
3. **SSL Certificate Issues**: Check domain validation and DNS configuration
4. **Performance Issues**: Review caching rules and origin response times

### Debug Commands

```bash
# Check Front Door health probe status
az afd origin show \
    --origin-name "origin-swa" \
    --origin-group-name "og-staticwebapp" \
    --profile-name "afd-${PROJECT_NAME}" \
    --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}"

# View WAF policy configuration
az network front-door waf-policy show \
    --name "wafpolicy${PROJECT_NAME}" \
    --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}"

# Check Static Web App configuration
az staticwebapp show \
    --name "swa-${PROJECT_NAME}" \
    --resource-group "rg-${PROJECT_NAME}-${ENVIRONMENT}"
```

## Security Considerations

- **Least Privilege**: All IAM roles follow principle of least privilege
- **Encryption**: HTTPS enforced end-to-end with TLS 1.2+ 
- **Network Security**: Origin protection prevents direct access bypass
- **Compliance**: Configuration supports SOC, ISO, and PCI compliance requirements
- **Monitoring**: Comprehensive logging for security audit and compliance

## Support

For issues with this infrastructure code:

1. Refer to the original recipe documentation for context
2. Check Azure service status at [Azure Status](https://status.azure.com/)
3. Review Azure documentation for [Front Door](https://docs.microsoft.com/en-us/azure/frontdoor/) and [Static Web Apps](https://docs.microsoft.com/en-us/azure/static-web-apps/)
4. Consult the [Azure WAF documentation](https://docs.microsoft.com/en-us/azure/web-application-firewall/) for security configuration guidance

## Next Steps

After successful deployment, consider these enhancements:

1. **Azure Sentinel Integration**: Connect WAF logs to Azure Sentinel for advanced threat detection
2. **Private Endpoints**: Configure Private Link for enhanced network security
3. **Azure DevOps Integration**: Set up CI/CD pipelines for automated deployment
4. **Cost Optimization**: Implement Azure Cost Management alerts and recommendations
5. **Disaster Recovery**: Configure multi-region failover capabilities