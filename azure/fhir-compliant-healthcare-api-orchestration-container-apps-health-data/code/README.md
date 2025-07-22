# Infrastructure as Code for Building FHIR-Compliant Healthcare API Orchestration

This directory contains Infrastructure as Code (IaC) implementations for the recipe "FHIR-Compliant Healthcare API Orchestration with Azure Container Apps and Azure Health Data Services".

## Available Implementations

- **Bicep**: Azure native infrastructure as code (ARM template language)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Azure CLI v2.53.0 or later installed and configured
- Active Azure subscription with appropriate permissions
- Healthcare APIs and Container Apps services enabled in target region
- Basic understanding of FHIR R4 standard and healthcare data concepts
- Docker knowledge for containerized application deployment
- Appropriate permissions for resource creation including:
  - Healthcare APIs service management
  - Container Apps environment management
  - API Management service deployment
  - Communication Services provisioning
  - Log Analytics workspace creation

## Quick Start

### Using Bicep

```bash
# Navigate to bicep directory
cd bicep/

# Create resource group
az group create --name rg-healthcare-fhir --location eastus

# Deploy infrastructure
az deployment group create \
    --resource-group rg-healthcare-fhir \
    --template-file main.bicep \
    --parameters @parameters.json

# Verify deployment
az deployment group show \
    --resource-group rg-healthcare-fhir \
    --name main
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Verify deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
az group show --name rg-healthcare-fhir-$(openssl rand -hex 3)
```

## Architecture Overview

This infrastructure deploys a comprehensive FHIR-compliant healthcare API orchestration platform including:

### Core Components
- **Azure Health Data Services Workspace**: Secure, compliant environment for PHI
- **FHIR R4 Service**: Managed HL7 FHIR implementation with authentication
- **Container Apps Environment**: Serverless container platform with monitoring
- **API Management Gateway**: Centralized API security and governance

### Microservices
- **Patient Management Service**: Handles FHIR Patient resources and operations
- **Provider Notification Service**: Manages healthcare provider communications
- **Workflow Orchestration Service**: Coordinates complex healthcare processes

### Supporting Services
- **Azure Communication Services**: HIPAA-compliant messaging and notifications
- **Log Analytics Workspace**: Centralized monitoring and compliance logging
- **Application Insights**: Application performance and health monitoring

## Configuration

### Environment Variables

The following environment variables are used across all implementations:

```bash
# Resource Configuration
export RESOURCE_GROUP="rg-healthcare-fhir-${RANDOM_SUFFIX}"
export LOCATION="eastus"
export RANDOM_SUFFIX=$(openssl rand -hex 3)

# Healthcare Services
export HEALTH_WORKSPACE="hw-healthcare-${RANDOM_SUFFIX}"
export FHIR_SERVICE="fhir-service-${RANDOM_SUFFIX}"

# Container Apps
export CONTAINER_ENV="cae-healthcare-${RANDOM_SUFFIX}"

# Supporting Services
export API_MANAGEMENT="apim-healthcare-${RANDOM_SUFFIX}"
export COMM_SERVICE="comm-healthcare-${RANDOM_SUFFIX}"
export LOG_ANALYTICS="log-healthcare-${RANDOM_SUFFIX}"
```

### Bicep Parameters

Key parameters available in `bicep/parameters.json`:

```json
{
  "location": {
    "value": "eastus"
  },
  "healthWorkspaceName": {
    "value": "hw-healthcare-demo"
  },
  "fhirServiceName": {
    "value": "fhir-service-demo"
  },
  "containerEnvironmentName": {
    "value": "cae-healthcare-demo"
  },
  "complianceMode": {
    "value": "hipaa"
  },
  "enableMonitoring": {
    "value": true
  }
}
```

### Terraform Variables

Key variables available in `terraform/variables.tf`:

```hcl
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-healthcare-fhir"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "compliance_mode" {
  description = "Compliance mode for healthcare resources"
  type        = string
  default     = "hipaa"
}

variable "enable_monitoring" {
  description = "Enable comprehensive monitoring"
  type        = bool
  default     = true
}
```

## Security and Compliance

### HIPAA Compliance Features
- **Data Encryption**: All data encrypted at rest and in transit
- **Access Controls**: Azure AD integration with RBAC
- **Audit Logging**: Comprehensive audit trails for all operations
- **Network Security**: Virtual network integration and private endpoints
- **Identity Management**: Managed identity for secure service communication

### Security Best Practices Implemented
- **Least Privilege Access**: Minimal required permissions for all services
- **Network Isolation**: Container Apps deployed in secure environment
- **Secret Management**: Azure Key Vault integration for sensitive data
- **API Security**: Authentication and authorization through API Management
- **Monitoring**: Real-time security monitoring and alerting

## Monitoring and Observability

### Log Analytics Integration
- Centralized logging for all healthcare microservices
- Custom healthcare-specific log queries
- Compliance reporting and audit trails
- Performance monitoring and alerting

### Application Insights
- Real-time application performance monitoring
- Healthcare workflow tracking
- Custom metrics for FHIR operations
- Error tracking and debugging

## Validation and Testing

### Post-Deployment Validation

```bash
# Verify FHIR service health
curl -H "Accept: application/fhir+json" \
     "${FHIR_ENDPOINT}/metadata"

# Check container app status
az containerapp show \
    --resource-group ${RESOURCE_GROUP} \
    --name patient-service \
    --query "properties.runningStatus"

# Test Communication Services
az communication show \
    --name ${COMM_SERVICE} \
    --resource-group ${RESOURCE_GROUP} \
    --query "provisioningState"

# Validate compliance configuration
az healthcareapis workspace show \
    --resource-group ${RESOURCE_GROUP} \
    --workspace-name ${HEALTH_WORKSPACE} \
    --query "properties"
```

### Health Check Endpoints

Each microservice exposes health check endpoints:

- Patient Service: `https://patient-service.{domain}/health`
- Provider Notification: `https://provider-notification-service.{domain}/health`
- Workflow Orchestration: `https://workflow-orchestration-service.{domain}/health`

## Cleanup

### Using Bicep

```bash
# Delete resource group and all resources
az group delete --name rg-healthcare-fhir --yes --no-wait

# Verify deletion
az group exists --name rg-healthcare-fhir
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource group deletion
az group exists --name rg-healthcare-fhir-${RANDOM_SUFFIX}
```

## Cost Optimization

### Resource Sizing Recommendations

- **Container Apps**: Start with minimal resources (0.25 CPU, 0.5Gi memory)
- **API Management**: Use Developer SKU for testing, Standard/Premium for production
- **Log Analytics**: Configure appropriate data retention policies
- **Communication Services**: Monitor usage and optimize based on communication patterns

### Cost Monitoring

```bash
# View resource group costs
az consumption usage list \
    --resource-group ${RESOURCE_GROUP} \
    --start-date $(date -d '7 days ago' +%Y-%m-%d) \
    --end-date $(date +%Y-%m-%d)

# Monitor Container Apps scaling
az containerapp show \
    --resource-group ${RESOURCE_GROUP} \
    --name workflow-orchestration-service \
    --query "properties.template.scale"
```

## Troubleshooting

### Common Issues

1. **FHIR Service Authentication**
   - Verify Azure AD tenant configuration
   - Check service principal permissions
   - Validate SMART on FHIR settings

2. **Container Apps Deployment**
   - Check container environment logs
   - Verify image accessibility
   - Review scaling configuration

3. **Communication Services**
   - Validate connection string format
   - Check regional availability
   - Verify compliance settings

### Debug Commands

```bash
# Check deployment status
az deployment group show \
    --resource-group ${RESOURCE_GROUP} \
    --name main

# View container app logs
az containerapp logs show \
    --resource-group ${RESOURCE_GROUP} \
    --name patient-service

# Monitor resource health
az monitor activity-log list \
    --resource-group ${RESOURCE_GROUP} \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S.%3NZ)
```

## Customization

### Adding New Microservices

1. Update Container Apps environment configuration
2. Add new service to API Management
3. Configure appropriate scaling policies
4. Update monitoring and logging

### Extending FHIR Resources

1. Review FHIR R4 specification for new resources
2. Update patient and provider services
3. Modify workflow orchestration logic
4. Update API Management policies

### Multi-Region Deployment

1. Create additional resource groups in target regions
2. Configure cross-region networking
3. Implement data replication strategies
4. Update monitoring for multi-region operations

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Azure Health Data Services documentation
3. Consult Azure Container Apps troubleshooting guides
4. Review Azure Communication Services documentation
5. Check Azure API Management configuration guides

## Additional Resources

- [Azure Health Data Services Documentation](https://docs.microsoft.com/en-us/azure/healthcare-apis/)
- [Azure Container Apps Documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- [FHIR R4 Specification](https://hl7.org/fhir/R4/)
- [Azure Well-Architected Framework for Healthcare](https://docs.microsoft.com/en-us/azure/architecture/framework/healthcare/)
- [Azure Communication Services Documentation](https://docs.microsoft.com/en-us/azure/communication-services/)

## Version Information

- **Infrastructure Version**: 1.0
- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Azure CLI Version**: 2.53.0+
- **Terraform Version**: 1.5.0+
- **Bicep Version**: 0.21.0+