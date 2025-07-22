# Infrastructure as Code for Unified Security Incident Response with Sentinel and Defender XDR

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Unified Security Incident Response with Sentinel and Defender XDR".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (recommended for Azure)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.37.0 or higher installed and configured
- Azure subscription with Global Administrator or Security Administrator privileges
- Microsoft Sentinel workspace with data connectors configured (manual setup required)
- Microsoft Defender XDR onboarded to the Azure AD tenant (manual setup required)
- Appropriate permissions for resource creation:
  - Security Administrator role
  - Logic App Contributor role
  - Monitor Contributor role
  - Workbook Contributor role
- PowerShell (for some advanced configurations)

## Architecture Overview

This solution deploys:
- Log Analytics workspace for security data collection
- Microsoft Sentinel SIEM solution with analytics rules
- Azure Logic Apps for automated incident response
- Security playbooks for standardized response actions
- Azure Monitor Workbooks for security operations dashboards
- Data connectors for Azure AD, Security Events, and Activity logs
- Unified security operations platform integration

## Quick Start

### Using Bicep (Recommended for Azure)

```bash
# Navigate to the bicep directory
cd bicep/

# Review and customize parameters in main.bicep
# Deploy the infrastructure
az deployment group create \
    --resource-group <your-resource-group> \
    --template-file main.bicep \
    --parameters workspaceName=<unique-workspace-name> \
                 logicAppName=<unique-logic-app-name> \
                 location=<azure-region>
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables in terraform.tfvars
# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export RESOURCE_GROUP="rg-security-ops"
export LOCATION="eastus"
export WORKSPACE_NAME="law-security-$(openssl rand -hex 3)"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export RESOURCE_GROUP="rg-security-ops"
export LOCATION="eastus"
export WORKSPACE_NAME="law-security-unique"
export LOGIC_APP_NAME="la-incident-response-unique"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
```

### Customization Options

#### Bicep Parameters
- `workspaceName`: Log Analytics workspace name (must be globally unique)
- `logicAppName`: Logic App name for incident response
- `location`: Azure region for deployment
- `dataRetentionDays`: Log retention period (default: 90 days)
- `alertRulesEnabled`: Enable/disable analytics rules (default: true)

#### Terraform Variables
- `resource_group_name`: Resource group name
- `location`: Azure region
- `workspace_name`: Log Analytics workspace name
- `logic_app_name`: Logic App name
- `data_retention_days`: Log retention period
- `tags`: Resource tags for organization

#### Script Configuration
Modify variables at the top of `scripts/deploy.sh`:
```bash
RESOURCE_GROUP="rg-security-ops"
LOCATION="eastus"
WORKSPACE_NAME="law-security-$(openssl rand -hex 3)"
LOGIC_APP_NAME="la-incident-response-$(openssl rand -hex 3)"
```

## Post-Deployment Configuration

### Manual Setup Required

1. **Microsoft Sentinel Data Connectors**: Configure data connectors in the Azure portal
   - Navigate to Microsoft Sentinel > Data connectors
   - Enable Azure Active Directory, Azure Activity, and Security Events connectors
   - Follow connector-specific setup instructions

2. **Microsoft Defender XDR Integration**: 
   - Ensure Defender XDR is onboarded to your Azure AD tenant
   - Configure unified security operations in security.microsoft.com

3. **Logic Apps Connections**:
   - Authorize API connections in the Azure portal
   - Configure notification endpoints (Slack, Teams, etc.)
   - Test playbook functionality

4. **Workbook Customization**:
   - Access workbooks in Azure portal under Monitor > Workbooks
   - Customize queries and visualizations for your environment
   - Configure alert thresholds and notifications

### Validation Steps

1. **Verify Sentinel Deployment**:
   ```bash
   az sentinel workspace show \
       --resource-group $RESOURCE_GROUP \
       --workspace-name $WORKSPACE_NAME
   ```

2. **Check Data Ingestion**:
   ```bash
   az monitor log-analytics query \
       --workspace $WORKSPACE_ID \
       --analytics-query "union withsource=TableName * | where TimeGenerated > ago(1h) | summarize Count = count() by TableName"
   ```

3. **Test Logic App**:
   ```bash
   az logic workflow show \
       --resource-group $RESOURCE_GROUP \
       --name $LOGIC_APP_NAME \
       --query "state"
   ```

## Security Considerations

### Implemented Security Features

- **Least Privilege Access**: IAM roles configured with minimum required permissions
- **Data Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private endpoints configured where applicable
- **Audit Logging**: Comprehensive logging enabled for all security operations
- **Access Controls**: Role-based access control (RBAC) implemented

### Additional Security Recommendations

1. **Enable Private Endpoints**: Configure private endpoints for Log Analytics workspace
2. **Configure Network Security Groups**: Restrict network access to security resources
3. **Implement Conditional Access**: Use Azure AD conditional access for enhanced security
4. **Enable Multi-Factor Authentication**: Require MFA for all security operations
5. **Regular Security Reviews**: Schedule periodic reviews of security configurations

## Monitoring and Maintenance

### Key Metrics to Monitor

- **Incident Response Time**: Average time to respond to security incidents
- **Alert Volume**: Number of security alerts generated daily
- **False Positive Rate**: Percentage of alerts that are false positives
- **Data Ingestion Rate**: Volume of security data being processed
- **Automation Success Rate**: Percentage of successfully automated responses

### Maintenance Tasks

1. **Regular Rule Updates**: Review and update analytics rules monthly
2. **Playbook Testing**: Test security playbooks quarterly
3. **Dashboard Updates**: Refresh workbook queries and visualizations
4. **Data Retention**: Monitor and adjust data retention policies
5. **Performance Optimization**: Optimize queries and reduce costs

## Cost Optimization

### Cost Factors

- **Log Analytics Workspace**: Pay-per-GB ingestion and retention
- **Microsoft Sentinel**: Additional cost per GB of data analyzed
- **Logic Apps**: Per-execution pricing for automation workflows
- **Data Connectors**: Some connectors may incur additional costs

### Cost Management Tips

1. **Data Sampling**: Use data sampling for high-volume log sources
2. **Retention Policies**: Implement tiered retention policies
3. **Query Optimization**: Optimize KQL queries for better performance
4. **Alert Tuning**: Reduce false positives to minimize unnecessary executions
5. **Resource Scheduling**: Use automation to scale resources based on demand

## Troubleshooting

### Common Issues

1. **Data Connector Issues**:
   - Verify permissions for data source access
   - Check network connectivity to data sources
   - Review connector configuration in Azure portal

2. **Analytics Rule Failures**:
   - Validate KQL query syntax
   - Check data availability for query time ranges
   - Verify workspace permissions

3. **Logic App Execution Errors**:
   - Review run history in Azure portal
   - Check API connection authentication
   - Validate JSON schemas and data formats

4. **Workbook Display Issues**:
   - Verify workspace permissions
   - Check query syntax and data availability
   - Validate time range selections

### Support Resources

- [Microsoft Sentinel Documentation](https://docs.microsoft.com/en-us/azure/sentinel/)
- [Azure Monitor Workbooks Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/visualize/workbooks-overview)
- [Azure Logic Apps Documentation](https://docs.microsoft.com/en-us/azure/logic-apps/)
- [Azure Security Center Documentation](https://docs.microsoft.com/en-us/azure/security-center/)

## Cleanup

### Using Bicep
```bash
# Delete the resource group and all resources
az group delete --name <your-resource-group> --yes --no-wait
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup Steps

1. **Verify Resource Deletion**: Check Azure portal to ensure all resources are deleted
2. **Review Azure AD**: Remove any custom applications or service principals if created
3. **Check Billing**: Verify no unexpected charges remain
4. **Clean Environment Variables**: Unset any exported environment variables

## Advanced Configuration

### Multi-Tenant Deployment

For organizations with multiple Azure AD tenants:

1. **Cross-Tenant Data Collection**: Configure data connectors for multiple tenants
2. **Centralized Monitoring**: Use Azure Lighthouse for cross-tenant security monitoring
3. **Unified Dashboards**: Create workbooks that aggregate data from multiple tenants

### Integration with External Systems

#### SIEM Integration
- Configure log forwarding to external SIEM systems
- Use Azure Event Hubs for real-time data streaming
- Implement custom connectors for proprietary security tools

#### Ticketing Systems
- Integrate with ServiceNow, Jira, or other ticketing systems
- Configure automatic ticket creation for security incidents
- Implement bi-directional synchronization for incident status

#### Threat Intelligence
- Configure threat intelligence feeds
- Implement automated IOC blocking
- Use Azure Sentinel threat intelligence connectors

## Performance Optimization

### Query Performance
- Use summary tables for frequently accessed data
- Implement query result caching
- Optimize KQL queries for better performance

### Scaling Considerations
- Configure auto-scaling for Logic Apps
- Use Azure Functions for compute-intensive operations
- Implement data partitioning for large datasets

### High Availability
- Deploy across multiple Azure regions
- Configure geo-redundant storage
- Implement disaster recovery procedures

## Compliance and Governance

### Compliance Features
- Enable audit logging for all security operations
- Implement data classification and labeling
- Configure compliance dashboards and reports

### Governance Policies
- Use Azure Policy for resource governance
- Implement resource naming conventions
- Configure cost management policies

## Version History

- v1.0: Initial implementation with basic security incident response
- v1.1: Added unified security operations platform integration
- v1.2: Enhanced automation capabilities and workbook templates
- v1.3: Improved multi-tenant support and external integrations

## Contributing

To contribute improvements to this IaC implementation:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request with detailed description

## License

This infrastructure code is provided under the MIT License. See LICENSE file for details.