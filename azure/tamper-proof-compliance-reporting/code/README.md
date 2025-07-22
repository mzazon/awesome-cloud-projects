# Infrastructure as Code for Tamper-Proof Compliance Reporting with Confidential Ledger

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Tamper-Proof Compliance Reporting with Confidential Ledger".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI installed and configured
- Azure subscription with appropriate permissions
- PowerShell Core (for Bicep deployments)
- Terraform v1.0+ (for Terraform deployments)
- Bash shell (for script deployments)
- OpenSSL (for generating random suffixes)

### Required Azure Permissions

- Contributor role on target resource group
- User Access Administrator role (for RBAC assignments)
- Confidential Ledger Contributor role
- Storage Account Contributor role
- Logic App Contributor role

## Quick Start

### Using Bicep

```bash
# Deploy the infrastructure
cd bicep/
az deployment group create \
    --resource-group rg-compliance \
    --template-file main.bicep \
    --parameters location=eastus \
    --parameters environment=demo
```

### Using Terraform

```bash
# Initialize and deploy
cd terraform/
terraform init
terraform plan -var="location=eastus" -var="environment=demo"
terraform apply -var="location=eastus" -var="environment=demo"
```

### Using Bash Scripts

```bash
# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure creates:

- **Azure Confidential Ledger**: Immutable audit trail storage in secure enclaves
- **Azure Logic Apps**: Workflow orchestration for compliance automation
- **Azure Monitor**: Event monitoring and alerting
- **Log Analytics Workspace**: Centralized logging and analytics
- **Azure Blob Storage**: Encrypted storage for compliance reports
- **Action Groups**: Alert routing and notification
- **RBAC Assignments**: Secure access control between services

## Configuration Options

### Bicep Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `location` | Azure region for deployment | eastus | Yes |
| `environment` | Environment tag (dev/test/prod) | demo | No |
| `aclName` | Confidential Ledger name | acl-${uniqueString} | No |
| `storageAccountName` | Storage account name | stcompliance${uniqueString} | No |
| `logicAppName` | Logic App name | la-compliance-${uniqueString} | No |
| `workspaceName` | Log Analytics workspace name | law-compliance-${uniqueString} | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `location` | Azure region for deployment | eastus | Yes |
| `environment` | Environment tag | demo | No |
| `resource_group_name` | Resource group name | rg-compliance-${random} | No |
| `acl_name` | Confidential Ledger name | acl-${random} | No |
| `storage_account_name` | Storage account name | stcompliance${random} | No |
| `logic_app_name` | Logic App name | la-compliance-${random} | No |
| `workspace_name` | Log Analytics workspace name | law-compliance-${random} | No |

## Deployment Examples

### Development Environment

```bash
# Using Bicep
az deployment group create \
    --resource-group rg-compliance-dev \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environment=dev

# Using Terraform
terraform apply \
    -var="location=eastus" \
    -var="environment=dev" \
    -var="resource_group_name=rg-compliance-dev"
```

### Production Environment

```bash
# Using Bicep
az deployment group create \
    --resource-group rg-compliance-prod \
    --template-file bicep/main.bicep \
    --parameters location=eastus \
    --parameters environment=prod

# Using Terraform
terraform apply \
    -var="location=eastus" \
    -var="environment=prod" \
    -var="resource_group_name=rg-compliance-prod"
```

## Validation

After deployment, verify the infrastructure:

### Check Confidential Ledger Status

```bash
# Get ledger endpoint
az confidentialledger show \
    --name ${ACL_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query "properties.ledgerUri" \
    --output tsv
```

### Test Logic App Workflow

```bash
# Get Logic App trigger URL
az logic workflow show \
    --name ${LOGIC_APP_NAME} \
    --resource-group ${RESOURCE_GROUP} \
    --query "accessEndpoint" \
    --output tsv

# Send test event
curl -X POST ${TRIGGER_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "alertType": "ComplianceViolation",
      "severity": "High",
      "description": "Test compliance event",
      "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
    }'
```

### Verify Storage Account Configuration

```bash
# Check storage account encryption
az storage account show \
    --name ${STORAGE_ACCOUNT} \
    --resource-group ${RESOURCE_GROUP} \
    --query "encryption" \
    --output table
```

## Security Configuration

### Confidential Ledger Security

- Hardware-backed secure enclaves (TEE)
- Cryptographic verification of all transactions
- Immutable audit trail with tamper-proof guarantees
- Private ledger type for enhanced security

### Storage Security

- Encryption at rest enabled
- HTTPS-only access enforced
- TLS 1.2 minimum version
- Blob versioning for audit trail
- Private access (no public access)

### RBAC Configuration

The infrastructure automatically configures:

- Logic App managed identity
- Confidential Ledger Contributor role
- Storage Blob Data Contributor role
- Monitoring Reader role
- Least privilege access principles

## Monitoring and Alerting

### Alert Rules

The deployment creates:

- **Compliance Violation Alerts**: CPU threshold monitoring
- **Security Event Alerts**: Log-based security monitoring
- **Action Groups**: Centralized alert routing

### Log Analytics Queries

Common queries for compliance monitoring:

```kusto
// Security events analysis
SecurityEvent
| where EventID == 4625
| summarize count() by Computer, Account
| order by count_ desc

// Compliance violations over time
AzureActivity
| where OperationName contains "Compliance"
| summarize count() by bin(TimeGenerated, 1h)
| render timechart
```

## Cost Optimization

### Estimated Monthly Costs

Based on moderate usage:
- Azure Confidential Ledger: ~$90/month
- Logic Apps: ~$20/month
- Storage Account: ~$10/month
- Log Analytics: ~$30/month
- **Total**: ~$150-200/month

### Cost Optimization Tips

1. **Use consumption-based pricing** for Logic Apps
2. **Configure appropriate retention** for Log Analytics
3. **Implement lifecycle policies** for blob storage
4. **Monitor usage patterns** and adjust accordingly

## Troubleshooting

### Common Issues

1. **Deployment Fails**: Check Azure CLI authentication and permissions
2. **Logic App Not Triggering**: Verify trigger URL and JSON payload format
3. **Storage Access Denied**: Confirm RBAC assignments are complete
4. **Confidential Ledger Unavailable**: Check region availability and quotas

### Debug Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name ${DEPLOYMENT_NAME} \
    --query "properties.provisioningState"

# View Logic App run history
az logic workflow list-run \
    --resource-group ${RESOURCE_GROUP} \
    --name ${LOGIC_APP_NAME} \
    --output table

# Check storage account permissions
az role assignment list \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
    --output table
```

## Cleanup

### Using Bicep

```bash
# Delete the resource group (removes all resources)
az group delete \
    --name rg-compliance \
    --yes \
    --no-wait
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="location=eastus" \
    -var="environment=demo"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify resource group deletion
az group exists --name rg-compliance

# List any remaining resources
az resource list --resource-group rg-compliance --output table
```

## Advanced Configuration

### Custom Logic App Workflow

To modify the Logic App workflow:

1. Edit the workflow definition in your IaC template
2. Update the JSON schema for custom triggers
3. Add additional connectors as needed
4. Redeploy the infrastructure

### Multi-Region Deployment

For disaster recovery, deploy to multiple regions:

```bash
# Primary region
terraform apply -var="location=eastus" -var="environment=prod"

# Secondary region
terraform apply -var="location=westus2" -var="environment=prod-dr"
```

### Integration with Existing Systems

- **Azure Sentinel**: Connect for security information and event management
- **Power BI**: Create compliance dashboards
- **Microsoft 365**: Integrate with compliance center
- **Third-party SIEM**: Use Logic Apps connectors

## Best Practices

### Security

- Regularly rotate access keys
- Monitor access patterns
- Enable Azure Security Center recommendations
- Implement conditional access policies

### Compliance

- Document all configuration changes
- Maintain audit trails for infrastructure changes
- Regular compliance assessments
- Automated testing of compliance workflows

### Operations

- Implement infrastructure as code for all changes
- Use Azure DevOps or GitHub Actions for CI/CD
- Monitor costs and usage patterns
- Regular backup and disaster recovery testing

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Azure service documentation
3. Consult provider-specific troubleshooting guides
4. Contact Azure support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes thoroughly in development environment
2. Follow provider best practices
3. Update documentation accordingly
4. Validate security configurations
5. Test cleanup procedures

## Version History

- **1.0**: Initial implementation with Bicep, Terraform, and Bash scripts
- Support for Azure Confidential Ledger, Logic Apps, and associated services
- Automated RBAC configuration and security hardening