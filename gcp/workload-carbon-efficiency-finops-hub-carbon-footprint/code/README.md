# Infrastructure as Code for Workload Carbon Efficiency with FinOps Hub 2.0 and Cloud Carbon Footprint

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Workload Carbon Efficiency with FinOps Hub 2.0 and Cloud Carbon Footprint".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated infrastructure management

## Architecture Overview

This solution creates an intelligent carbon efficiency system that combines Google Cloud's FinOps Hub 2.0 with Cloud Carbon Footprint monitoring to optimize both cost and environmental impact. The infrastructure includes:

- Service accounts with appropriate IAM permissions for carbon footprint monitoring
- Cloud Functions for data correlation and optimization automation
- Cloud Monitoring dashboards and alert policies for efficiency tracking
- Cloud Workflows for automated reporting and optimization scheduling
- Cloud Scheduler for regular efficiency analysis
- Pub/Sub topics for event-driven optimization triggers

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Google Cloud project with billing account access
- Appropriate IAM permissions:
  - Billing Account Administrator
  - Monitoring Admin
  - Cloud Functions Developer
  - Workflows Admin
  - IAM Admin
- Existing Google Cloud workloads with billing and carbon footprint data (minimum 30 days recommended)
- Estimated cost: $50-100 for Cloud Functions, monitoring, and API calls during testing

## Project Setup

Before deploying the infrastructure, ensure your Google Cloud project is properly configured:

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Enable required APIs
gcloud services enable cloudbilling.googleapis.com
gcloud services enable recommender.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable workflows.googleapis.com

# Get your billing account ID
export BILLING_ACCOUNT_ID=$(gcloud billing accounts list --format="value(name)" --limit=1)
```

## Quick Start

### Using Infrastructure Manager

Google Cloud Infrastructure Manager provides native infrastructure as code capabilities with tight integration to Google Cloud services.

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-efficiency-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars.example"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-efficiency-deployment

# View deployment outputs
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-efficiency-deployment \
    --format="value(outputs)"
```

### Using Terraform

Terraform provides a provider-agnostic approach to infrastructure management with excellent Google Cloud support.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform with required providers
terraform init

# Review the planned infrastructure changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -var="billing_account_id=${BILLING_ACCOUNT_ID}"

# Apply the infrastructure configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -var="billing_account_id=${BILLING_ACCOUNT_ID}"

# View outputs after successful deployment
terraform output
```

### Using Bash Scripts

Automated scripts provide a quick deployment option that combines Infrastructure Manager or Terraform with additional configuration steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy the complete carbon efficiency infrastructure
./scripts/deploy.sh

# The script will:
# 1. Validate prerequisites and permissions
# 2. Enable required APIs
# 3. Deploy infrastructure using Terraform
# 4. Configure monitoring dashboards
# 5. Set up automated workflows
# 6. Validate the deployment
```

## Configuration Options

### Key Variables

Customize the deployment by modifying these variables in your chosen implementation:

- **project_id**: Your Google Cloud project ID
- **region**: Primary deployment region (default: us-central1)
- **billing_account_id**: Your billing account ID for carbon footprint access
- **efficiency_threshold**: Carbon efficiency score threshold for alerts (default: 70.0)
- **scheduler_frequency**: How often to run efficiency analysis (default: daily at 9 AM)
- **function_memory**: Memory allocation for Cloud Functions (default: 512MB)
- **workflow_timeout**: Timeout for workflow executions (default: 300s)

### Terraform Variables

Copy and customize the variables file:

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values
```

### Infrastructure Manager Configuration

Customize the deployment by editing the inputs in `infrastructure-manager/terraform.tfvars.example`:

```hcl
project_id = "your-project-id"
region = "us-central1"
billing_account_id = "your-billing-account-id"
efficiency_threshold = 70.0
```

## Post-Deployment Configuration

After successful deployment, complete these configuration steps:

### 1. Access FinOps Hub 2.0

```bash
echo "Navigate to FinOps Hub: https://console.cloud.google.com/billing/finops"
echo "Verify utilization insights and Gemini recommendations are visible"
```

### 2. Verify Carbon Footprint Access

```bash
echo "Navigate to Carbon Footprint: https://console.cloud.google.com/carbon"
echo "Confirm carbon emissions data is visible for your billing account"
```

### 3. Test the Carbon Efficiency Function

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe carbon-efficiency-correlator \
    --region=${REGION} --format="value(httpsTrigger.url)")

# Test the function
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"action": "test_correlation"}'
```

### 4. Validate Monitoring Dashboard

```bash
# List created dashboards
gcloud monitoring dashboards list --format="table(displayName,name)"

# Access the dashboard
echo "Navigate to: https://console.cloud.google.com/monitoring/dashboards"
echo "Look for 'Carbon Efficiency & FinOps Hub Dashboard'"
```

## Monitoring and Alerts

The deployed infrastructure includes comprehensive monitoring:

### Custom Metrics

- `custom.googleapis.com/carbon_efficiency/score`: Overall efficiency score
- `custom.googleapis.com/gemini/recommendation_effectiveness`: Gemini recommendation impact
- `custom.googleapis.com/optimization/carbon_impact`: Optimization impact tracking

### Alert Policies

- **Low Carbon Efficiency**: Triggers when efficiency score drops below 70
- **High Recommendation Count**: Alerts when many optimization opportunities exist
- **Function Errors**: Notifies of Cloud Function execution failures

### Dashboard Features

- Real-time carbon efficiency scoring
- Compute instance utilization trends
- Recommendation impact visualization
- Historical efficiency tracking

## Validation and Testing

### Verify Infrastructure Deployment

```bash
# Check all deployed resources
gcloud functions list --format="table(name,status,runtime)"
gcloud workflows list --format="table(name,state,updateTime)"
gcloud scheduler jobs list --format="table(name,state,schedule)"

# Test workflow execution
gcloud workflows run carbon-efficiency-workflow \
    --location=${REGION} \
    --data='{"trigger": "manual_test"}'
```

### Test Optimization Automation

```bash
# Trigger optimization workflow
gcloud pubsub topics publish carbon-optimization \
    --message='{"optimization_type": "rightsizing"}'

# Check function logs
gcloud functions logs read carbon-efficiency-optimizer --limit=10
```

### Verify Monitoring Setup

```bash
# List custom metrics
gcloud monitoring metrics list \
    --filter="metric.type:custom.googleapis.com/carbon_efficiency/*"

# Check alert policies
gcloud alpha monitoring policies list \
    --format="table(displayName,enabled,combiner)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/carbon-efficiency-deployment

# Confirm deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all managed infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -var="billing_account_id=${BILLING_ACCOUNT_ID}"

# Confirm all resources are removed
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Functions and workflows
# 2. Remove monitoring dashboards and alerts
# 3. Clean up IAM service accounts
# 4. Remove Pub/Sub topics and schedulers
# 5. Validate complete cleanup
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
gcloud functions list
gcloud workflows list
gcloud scheduler jobs list
gcloud monitoring dashboards list
gcloud alpha monitoring policies list
gcloud iam service-accounts list --filter="email:carbon-efficiency-sa@*"
```

## Troubleshooting

### Common Issues

#### Carbon Footprint Data Not Available

```bash
# Check billing account permissions
gcloud billing accounts get-iam-policy ${BILLING_ACCOUNT_ID}

# Verify carbon footprint API access
gcloud services list --enabled --filter="name:cloudbilling.googleapis.com"
```

#### Function Deployment Failures

```bash
# Check function deployment status
gcloud functions describe carbon-efficiency-correlator --region=${REGION}

# Review function logs for errors
gcloud functions logs read carbon-efficiency-correlator --limit=50
```

#### Workflow Execution Issues

```bash
# Check workflow status
gcloud workflows describe carbon-efficiency-workflow --location=${REGION}

# Review execution history
gcloud workflows executions list --workflow=carbon-efficiency-workflow --location=${REGION}
```

#### Permission Errors

```bash
# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:carbon-efficiency-sa@*"

# Check required API enablement
gcloud services list --enabled --filter="name:(cloudbilling.googleapis.com OR recommender.googleapis.com OR monitoring.googleapis.com)"
```

### Debugging Tips

1. **Check API Quotas**: Verify you haven't exceeded API quotas for Cloud Functions or Monitoring
2. **Billing Account Access**: Ensure your billing account has carbon footprint data enabled (may take up to 21 days for new accounts)
3. **Regional Availability**: Some services may not be available in all regions; use supported regions like us-central1
4. **IAM Propagation**: IAM changes can take up to 10 minutes to propagate; wait before testing

## Security Considerations

The deployed infrastructure follows security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Function Security**: Cloud Functions use authenticated triggers where appropriate
- **Data Encryption**: All data is encrypted at rest and in transit
- **Access Logging**: All resource access is logged for audit purposes
- **Network Security**: Functions and workflows use VPC-native networking when available

## Cost Optimization

Expected monthly costs for the carbon efficiency infrastructure:

- **Cloud Functions**: $5-15 (based on execution frequency)
- **Cloud Monitoring**: $10-20 (custom metrics and dashboards)
- **Cloud Workflows**: $1-5 (execution-based pricing)
- **Cloud Scheduler**: $0.10 per job per month
- **Pub/Sub**: $1-3 (message volume dependent)

**Total Estimated Cost**: $17-43 per month

### Cost Reduction Tips

1. Adjust function memory allocation based on actual usage
2. Optimize workflow execution frequency for your needs
3. Use Cloud Monitoring alerting to avoid unnecessary function executions
4. Implement function timeout optimization to prevent long-running executions

## Integration with FinOps Hub 2.0

This infrastructure integrates seamlessly with Google Cloud's FinOps Hub 2.0:

- **Utilization Insights**: Automated correlation with carbon footprint data
- **Gemini Recommendations**: AI-powered optimization suggestions
- **Waste Detection**: Identification of underutilized resources
- **Cost-Carbon Correlation**: Analysis of financial and environmental impact

## Advanced Configuration

### Custom Metrics Configuration

Add additional metrics by modifying the Cloud Functions:

```python
# Example: Add custom carbon intensity metric
descriptor = monitoring_v3.MetricDescriptor()
descriptor.type = "custom.googleapis.com/carbon/intensity_score"
descriptor.metric_kind = monitoring_v3.MetricDescriptor.MetricKind.GAUGE
descriptor.value_type = monitoring_v3.MetricDescriptor.ValueType.DOUBLE
```

### Workflow Customization

Modify the workflow YAML to add custom optimization logic:

```yaml
- custom_optimization:
    call: googleapis.compute.v1.instances.setMachineType
    args:
      project: ${project_id}
      zone: ${zone}
      instance: ${instance_name}
      body:
        machineType: ${recommended_machine_type}
```

## Support and Documentation

- **Google Cloud FinOps Hub**: [Documentation](https://cloud.google.com/billing/docs/finops-hub)
- **Cloud Carbon Footprint**: [Service Guide](https://cloud.google.com/carbon-footprint/docs)
- **Infrastructure Manager**: [Documentation](https://cloud.google.com/infrastructure-manager/docs)
- **Terraform Google Provider**: [Registry](https://registry.terraform.io/providers/hashicorp/google/latest)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate with multiple Google Cloud projects
3. Ensure backward compatibility
4. Update documentation accordingly
5. Follow Google Cloud security best practices

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production deployment guidelines.