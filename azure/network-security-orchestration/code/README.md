# Infrastructure as Code for Network Security Orchestration with Logic Apps and NSG Rules

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Network Security Orchestration with Logic Apps and NSG Rules".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.50+ installed and configured
- Appropriate Azure subscription with Owner or Contributor permissions
- Basic understanding of Azure networking concepts and security group rules
- Knowledge of JSON syntax for Logic Apps workflow definitions

### Required Azure Permissions

The deploying user/service principal needs permissions to:
- Create and manage Logic Apps workflows
- Create and manage Network Security Groups
- Create and manage Virtual Networks
- Create and manage Azure Key Vault
- Create and manage Storage Accounts
- Create and manage Log Analytics workspaces
- Create and manage Azure Monitor resources

## Quick Start

### Using Bicep (Recommended)

```bash
# Deploy the infrastructure
az deployment group create \
    --resource-group rg-security-orchestration \
    --template-file bicep/main.bicep \
    --parameters @bicep/parameters.json
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
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
```

## Architecture Overview

This solution creates an automated network security orchestration system that includes:

- **Azure Logic Apps**: Serverless workflow orchestration engine
- **Network Security Groups**: Distributed firewall rules management
- **Azure Key Vault**: Secure credential and secret management
- **Azure Monitor**: Real-time event detection and alerting
- **Azure Storage**: Workflow state and compliance data storage
- **Log Analytics**: Comprehensive audit trails and reporting

## Configuration Parameters

### Bicep Parameters

Key parameters you can customize in `bicep/parameters.json`:

```json
{
  "resourcePrefix": {
    "value": "secorch"
  },
  "location": {
    "value": "eastus"
  },
  "environment": {
    "value": "demo"
  },
  "vnetAddressPrefix": {
    "value": "10.0.0.0/16"
  },
  "subnetAddressPrefix": {
    "value": "10.0.1.0/24"
  }
}
```

### Terraform Variables

Key variables you can customize in `terraform/terraform.tfvars`:

```hcl
resource_group_name = "rg-security-orchestration"
location           = "eastus"
resource_prefix    = "secorch"
environment        = "demo"
vnet_address_space = ["10.0.0.0/16"]
subnet_address_prefix = "10.0.1.0/24"
```

### Bash Script Variables

The deployment script uses environment variables that can be customized:

```bash
export RESOURCE_GROUP="rg-security-orchestration"
export LOCATION="eastus"
export RESOURCE_PREFIX="secorch"
```

## Deployment Details

### What Gets Deployed

1. **Resource Group**: Container for all security orchestration resources
2. **Azure Key Vault**: Stores sensitive credentials and API keys
3. **Storage Account**: Maintains workflow state and compliance data
4. **Virtual Network**: Provides secure network isolation
5. **Network Security Group**: Implements distributed firewall rules
6. **Logic Apps Workflow**: Orchestrates automated security responses
7. **Log Analytics Workspace**: Provides monitoring and compliance logging
8. **Azure Monitor**: Enables real-time threat detection

### Estimated Costs

- **Development/Testing**: $15-25 USD for 2-hour implementation
- **Production**: $50-100 USD per month (varies by usage)
- **Key Cost Factors**:
  - Logic Apps consumption (per execution)
  - Storage account usage
  - Log Analytics data ingestion
  - Azure Monitor alerts

## Security Considerations

### Built-in Security Features

- **Managed Identity**: Logic Apps uses managed identity for secure Azure service access
- **Key Vault Integration**: All sensitive credentials stored in Azure Key Vault
- **Network Isolation**: Resources deployed in dedicated virtual network
- **Encryption**: Data encrypted at rest and in transit
- **RBAC**: Role-based access control for all resources

### Security Best Practices

1. **Least Privilege**: Grant minimum permissions required
2. **Network Segmentation**: Use NSGs to control traffic flow
3. **Audit Logging**: Enable comprehensive logging for compliance
4. **Secret Management**: Never hardcode credentials in workflows
5. **Regular Updates**: Keep Logic Apps definitions current

## Monitoring and Compliance

### Built-in Monitoring

- **Logic Apps Metrics**: Workflow execution success/failure rates
- **NSG Flow Logs**: Network traffic analysis
- **Key Vault Audit Logs**: Access to sensitive credentials
- **Storage Analytics**: Data access patterns
- **Azure Monitor Alerts**: Real-time threat detection

### Compliance Features

- **Audit Trails**: Complete logging of all security actions
- **Data Retention**: Configurable retention periods (default: 90 days)
- **Compliance Reports**: Automated generation of security reports
- **Regulatory Support**: SOC 2, ISO 27001, industry-specific compliance

## Testing and Validation

### Post-Deployment Testing

1. **Verify Logic Apps Creation**:
   ```bash
   az logic workflow show \
       --name la-security-orchestrator-[suffix] \
       --resource-group rg-security-orchestration
   ```

2. **Test Security Event Processing**:
   ```bash
   # Trigger workflow with test security event
   curl -X POST "[Logic Apps Trigger URL]" \
       -H "Content-Type: application/json" \
       -d '{
         "threatType": "malicious_ip",
         "sourceIP": "192.168.1.100",
         "severity": "high",
         "action": "block"
       }'
   ```

3. **Validate NSG Rule Creation**:
   ```bash
   az network nsg rule show \
       --nsg-name nsg-protected-[suffix] \
       --resource-group rg-security-orchestration \
       --name "BlockMaliciousIP"
   ```

### Performance Testing

- **Workflow Execution Time**: < 30 seconds for standard security events
- **NSG Rule Application**: < 60 seconds for rule activation
- **Alert Processing**: < 5 minutes from detection to response
- **Scale Testing**: Supports 100+ concurrent security events

## Troubleshooting

### Common Issues

1. **Logic Apps Authentication Failures**:
   - Verify managed identity has required permissions
   - Check Azure AD service principal configuration

2. **NSG Rule Creation Failures**:
   - Confirm Logic Apps has Network Contributor role
   - Verify NSG rule priority conflicts

3. **Key Vault Access Denied**:
   - Validate Key Vault access policies
   - Check managed identity permissions

4. **Storage Account Connectivity**:
   - Verify storage account firewall rules
   - Check network connectivity from Logic Apps

### Debugging Steps

1. **Check Logic Apps Run History**:
   ```bash
   az logic workflow list-runs \
       --resource-group rg-security-orchestration \
       --name la-security-orchestrator-[suffix]
   ```

2. **Review Activity Logs**:
   ```bash
   az monitor activity-log list \
       --resource-group rg-security-orchestration \
       --max-events 50
   ```

3. **Validate Network Connectivity**:
   ```bash
   az network nsg show \
       --resource-group rg-security-orchestration \
       --name nsg-protected-[suffix]
   ```

## Cleanup

### Using Bicep

```bash
# Delete the resource group and all resources
az group delete \
    --name rg-security-orchestration \
    --yes \
    --no-wait
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:
- Resource Group and all contained resources
- Azure AD service principals (if created)
- Any custom RBAC role assignments
- Key Vault soft-deleted items (if retention is enabled)

## Customization

### Extending the Solution

1. **Additional Threat Sources**: Integrate with external threat intelligence feeds
2. **Multi-Region Deployment**: Deploy across multiple Azure regions
3. **Advanced Analytics**: Add Azure Sentinel integration
4. **Machine Learning**: Implement anomaly detection with Azure ML
5. **Compliance Automation**: Add regulatory reporting capabilities

### Configuration Examples

#### Custom Logic Apps Workflow

```json
{
  "definition": {
    "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
    "actions": {
      "Custom_Threat_Analysis": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "https://custom-threat-intel-api.com/analyze",
          "body": "@triggerBody()"
        }
      }
    }
  }
}
```

#### Advanced NSG Rules

```bash
# Create geo-blocking rule
az network nsg rule create \
    --nsg-name nsg-protected-[suffix] \
    --resource-group rg-security-orchestration \
    --name "Block-Suspicious-Countries" \
    --priority 200 \
    --direction Inbound \
    --access Deny \
    --protocol "*" \
    --source-address-prefixes "country-ip-ranges"
```

## Support and Documentation

### Azure Documentation References

- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Network Security Groups Best Practices](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Azure Key Vault Security](https://docs.microsoft.com/en-us/azure/key-vault/general/security-overview)
- [Azure Monitor Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/)

### Additional Resources

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Security Benchmark](https://docs.microsoft.com/en-us/security/benchmark/azure/)
- [Logic Apps Security Best Practices](https://docs.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app)

### Getting Help

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Azure service status at [Azure Status](https://status.azure.com/)
3. Consult Azure support documentation
4. Contact Azure support for service-specific issues

## Version History

- **v1.0**: Initial implementation with basic security orchestration
- **v1.1**: Added compliance monitoring and enhanced logging
- **Current**: Enhanced security features and documentation

---

**Note**: This infrastructure code is based on the "Network Security Orchestration with Logic Apps and NSG Rules" recipe. Ensure you understand the security implications and cost considerations before deploying in production environments.