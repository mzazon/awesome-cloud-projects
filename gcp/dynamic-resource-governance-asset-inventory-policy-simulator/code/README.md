# Infrastructure as Code for Dynamic Resource Governance with Cloud Asset Inventory and Policy Simulator

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dynamic Resource Governance with Cloud Asset Inventory and Policy Simulator".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Asset Inventory Admin
  - Pub/Sub Admin
  - Cloud Functions Admin
  - Service Account Admin
  - Policy Simulator Admin
  - Project IAM Admin
- Organization-level access for comprehensive governance implementation
- Basic understanding of Google Cloud IAM and resource management

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply governance-deployment \
    --location=${REGION} \
    --config=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager implementation supports the following variables:

- `project_id`: Google Cloud project ID (required)
- `region`: Google Cloud region for resources (default: us-central1)
- `random_suffix`: Random suffix for unique resource names (auto-generated)
- `asset_feed_name`: Name for the Cloud Asset Inventory feed
- `topic_name`: Name for the Pub/Sub topic
- `function_memory`: Memory allocation for Cloud Functions (default: 1GB)
- `function_timeout`: Timeout for Cloud Functions (default: 540s)

### Terraform Variables

The Terraform implementation includes these configurable variables:

- `project_id`: Google Cloud project ID (required)
- `region`: Google Cloud region (default: us-central1)
- `zone`: Google Cloud zone (default: us-central1-a)
- `environment`: Environment name (default: production)
- `labels`: Common labels for all resources
- `enable_apis`: Whether to enable required APIs (default: true)
- `asset_types`: Asset types to monitor (default: all types)
- `function_source_bucket`: Bucket for Cloud Function source code

## Architecture Overview

The infrastructure deploys the following components:

1. **Cloud Asset Inventory Feed**: Monitors all resource changes across the organization
2. **Pub/Sub Topic and Subscription**: Handles event-driven messaging for governance workflows
3. **Cloud Functions**: Three serverless functions for different aspects of governance:
   - Asset Analyzer: Processes asset changes and assesses risk levels
   - Policy Validator: Validates policy changes using Policy Simulator
   - Compliance Engine: Orchestrates compliance enforcement actions
4. **IAM Service Account**: Dedicated service account with least-privilege permissions
5. **Cloud Logging and Monitoring**: Comprehensive logging and metrics for governance operations

## Security Considerations

The infrastructure implements several security best practices:

- **Least Privilege Access**: Service accounts have minimal required permissions
- **Network Security**: Functions are deployed with appropriate VPC configurations
- **Encryption**: All data is encrypted at rest and in transit
- **Audit Trail**: Comprehensive logging for all governance actions
- **Resource Tagging**: Consistent labeling for resource management and cost tracking

## Monitoring and Alerting

The solution includes built-in monitoring capabilities:

- **Cloud Logging**: Centralized logging for all governance activities
- **Cloud Monitoring**: Metrics and dashboards for governance system health
- **Custom Metrics**: Compliance metrics and policy violation tracking
- **Alert Policies**: Automated alerts for high-risk compliance violations

## Cost Estimation

Estimated monthly costs for moderate enterprise usage:

- **Cloud Functions**: $10-15 (based on execution frequency)
- **Pub/Sub**: $2-5 (message volume dependent)
- **Cloud Asset Inventory**: $3-7 (organization size dependent)
- **Cloud Logging**: $2-5 (log volume dependent)
- **Total**: Approximately $15-25 per month

> **Note**: Costs may vary based on organization size, resource change frequency, and governance complexity.

## Validation and Testing

After deployment, validate the infrastructure using these steps:

1. **Verify Asset Feed**:
   ```bash
   gcloud asset feeds list
   ```

2. **Check Pub/Sub Topic**:
   ```bash
   gcloud pubsub topics list
   ```

3. **Validate Cloud Functions**:
   ```bash
   gcloud functions list --regions=${REGION}
   ```

4. **Test Governance Workflow**:
   ```bash
   # Create a test resource to trigger governance workflow
   gcloud compute instances create test-governance-vm \
       --zone=${ZONE} \
       --machine-type=e2-micro \
       --image-family=debian-11 \
       --image-project=debian-cloud
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete governance-deployment \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Permission Denied**: Verify IAM permissions for deployment service account
3. **Quota Exceeded**: Check Google Cloud quotas for Cloud Functions and Pub/Sub
4. **Asset Feed Creation**: Requires organization-level permissions

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check function logs
gcloud functions logs read FUNCTION_NAME --region=${REGION}

# Monitor Pub/Sub messages
gcloud pubsub subscriptions pull compliance-subscription --auto-ack
```

## Customization

### Extending the Solution

1. **Custom Risk Assessment**: Modify the asset analyzer function to implement organization-specific risk scoring
2. **Integration with ITSM**: Extend the compliance engine to create tickets in your ticketing system
3. **Multi-Cloud Support**: Add functions to monitor resources across AWS and Azure
4. **Advanced Remediation**: Implement automated remediation actions for common compliance violations

### Configuration Files

Each implementation includes example configuration files:

- `terraform.tfvars.example`: Sample Terraform variables
- `parameters.yaml`: Infrastructure Manager parameters
- `config.env`: Environment variables for bash scripts

## Support and Documentation

For additional support and documentation:

- [Google Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs)
- [Google Cloud Policy Simulator Documentation](https://cloud.google.com/policy-intelligence/docs/iam-simulator-overview)
- [Google Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Original Recipe Documentation](../dynamic-resource-governance-asset-inventory-policy-simulator.md)

## Contributing

When making changes to the infrastructure code:

1. Test changes in a development environment
2. Update variable descriptions and documentation
3. Ensure security best practices are maintained
4. Update cost estimates if resource usage changes
5. Validate all implementations work correctly

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Review and modify according to your organization's requirements and security policies.