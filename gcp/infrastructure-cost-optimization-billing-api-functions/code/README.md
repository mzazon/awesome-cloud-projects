# Infrastructure as Code for Infrastructure Cost Optimization with Cloud Billing API and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Cost Optimization with Cloud Billing API and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Billing Account Administrator or Billing Account Costs Manager
  - Cloud Functions Developer
  - BigQuery Admin
  - Pub/Sub Admin
  - Cloud Scheduler Admin
  - Project IAM Admin
- Basic understanding of FinOps principles and cloud cost management
- Estimated cost: $15-25/month for BigQuery storage, Cloud Functions execution, and monitoring resources

## Quick Start

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export BILLING_ACCOUNT_ID="your-billing-account-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-optimization \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="main.yaml"
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export BILLING_ACCOUNT_ID="your-billing-account-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Required Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `billing_account_id` | Billing Account ID for budget creation | - | Yes |
| `region` | Google Cloud region for resources | `us-central1` | No |
| `budget_amount` | Monthly budget amount in USD | `1000` | No |
| `dataset_location` | BigQuery dataset location | `US` | No |

### Optional Customizations

- **Budget Thresholds**: Modify budget alert thresholds (default: 50%, 90%, 100%)
- **Function Memory**: Adjust Cloud Function memory allocation (default: 512MB)
- **Function Timeout**: Modify function execution timeout (default: 540s)
- **Schedule Frequency**: Change cost analysis scheduling (default: daily at 9 AM)
- **Anomaly Detection Sensitivity**: Adjust statistical thresholds for anomaly detection

## Architecture Components

This infrastructure deploys:

### Data Infrastructure
- **BigQuery Dataset**: Central data warehouse for billing and cost analytics
- **Cost Anomalies Table**: Structured storage for anomaly detection results
- **Billing Export Configuration**: Automated data pipeline from Cloud Billing API

### Compute Resources
- **Cost Analysis Function**: Serverless function for trend analysis and recommendations
- **Anomaly Detection Function**: Machine learning-based spending anomaly detection
- **Optimization Function**: Resource utilization analysis and optimization recommendations

### Event-Driven Architecture
- **Pub/Sub Topic**: Message queue for cost optimization events and alerts
- **Budget Configuration**: Automated spending thresholds with Pub/Sub notifications
- **Cloud Scheduler Jobs**: Automated execution of cost analysis workflows

### Monitoring & Alerting
- **Budget Alerts**: Multi-tier spending notifications (50%, 90%, 100%)
- **Cost Anomaly Tracking**: Statistical analysis for unusual spending patterns
- **Optimization Recommendations**: Automated resource rightsizing suggestions

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Verify BigQuery Resources
```bash
# Check dataset creation
bq ls ${PROJECT_ID}:cost_optimization_*

# Verify table schema
bq show ${PROJECT_ID}:cost_optimization_*/cost_anomalies
```

### 2. Test Cloud Functions
```bash
# Get function URLs
gcloud functions list --filter="name:cost-opt-*"

# Test cost analysis function
COST_ANALYSIS_URL=$(gcloud functions describe cost-opt-*-cost-analysis \
    --format="value(httpsTrigger.url)")
curl -X GET ${COST_ANALYSIS_URL}
```

### 3. Verify Pub/Sub Configuration
```bash
# List topics and subscriptions
gcloud pubsub topics list --filter="name:cost-optimization-alerts"
gcloud pubsub subscriptions list --filter="topic:cost-optimization-alerts"

# Test message publishing
gcloud pubsub topics publish cost-optimization-alerts \
    --message='{"test": "cost optimization system"}'
```

### 4. Check Scheduled Jobs
```bash
# Verify scheduler configuration
gcloud scheduler jobs list --filter="name:cost-*-scheduler"

# Check job execution history
gcloud scheduler jobs describe cost-analysis-scheduler
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-optimization
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

## Security Considerations

### IAM and Access Control
- Functions use least-privilege service accounts
- BigQuery dataset access restricted to cost optimization workflows
- Pub/Sub topics secured with appropriate IAM bindings
- Budget notifications limited to authorized recipients

### Data Protection
- Billing data encrypted at rest in BigQuery
- Function environment variables secured
- Network traffic encrypted in transit
- Audit logging enabled for all cost-related activities

### Budget Controls
- Multiple alert thresholds prevent budget overruns
- Pub/Sub integration enables automated responses
- Cost anomaly detection provides early warning system
- Resource optimization recommendations reduce unnecessary spending

## Monitoring and Observability

### Cloud Monitoring Integration
- Function execution metrics and error rates
- BigQuery query performance and costs
- Pub/Sub message throughput and latency
- Budget alert delivery status

### Logging and Debugging
- Structured logging in all Cloud Functions
- BigQuery query execution logs
- Scheduler job execution history
- Pub/Sub message delivery tracking

### Performance Optimization
- Function cold start minimization
- BigQuery query optimization
- Efficient data partitioning strategies
- Cost-effective storage class selection

## Cost Optimization Features

### Automated Analysis
- **Daily Cost Trends**: Automatic analysis of spending patterns across all services
- **Anomaly Detection**: Statistical algorithms identify unusual spending spikes
- **Optimization Recommendations**: Resource rightsizing and scheduling suggestions
- **Budget Monitoring**: Proactive alerts at customizable spending thresholds

### Machine Learning Capabilities
- **Predictive Analytics**: Forecast future costs based on historical patterns
- **Usage Pattern Analysis**: Identify underutilized resources for optimization
- **Seasonal Trend Detection**: Adapt to business cycle variations
- **Cost Attribution**: Granular analysis by project, service, and resource labels

### Automation Workflows
- **Scheduled Analysis**: Regular cost review without manual intervention
- **Event-Driven Alerts**: Immediate response to budget threshold violations
- **Optimization Triggers**: Automated recommendations based on usage patterns
- **Remediation Integration**: Foundation for automated cost optimization actions

## Troubleshooting

### Common Issues

1. **Billing Export Not Working**
   - Verify billing account permissions
   - Check BigQuery dataset location settings
   - Ensure billing export is properly configured

2. **Function Deployment Failures**
   - Validate service account permissions
   - Check function memory and timeout settings
   - Verify environment variable configuration

3. **Budget Alerts Not Firing**
   - Confirm Pub/Sub topic permissions
   - Validate billing account linkage
   - Check budget threshold configuration

4. **BigQuery Query Errors**
   - Verify dataset and table existence
   - Check billing export data availability
   - Validate query syntax and permissions

### Debug Commands

```bash
# Check function logs
gcloud functions logs read cost-opt-*-cost-analysis --limit=50

# Verify BigQuery billing export
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) FROM \`${PROJECT_ID}.cost_optimization_*.gcp_billing_export_v1_*\`"

# Test Pub/Sub connectivity
gcloud pubsub topics list-subscriptions cost-optimization-alerts

# Check scheduler job status
gcloud scheduler jobs run cost-analysis-scheduler
```

## Extensions and Enhancements

### Advanced Features
- **Multi-Project Analysis**: Extend to organization-wide cost optimization
- **Custom ML Models**: Implement Vertex AI for sophisticated cost predictions
- **Integration APIs**: Connect with external FinOps tools and platforms
- **Automated Remediation**: Build functions that automatically implement optimizations

### Third-Party Integrations
- **Slack/Teams Notifications**: Real-time cost alerts in collaboration tools
- **ITSM Integration**: Automatic ticket creation for cost anomalies
- **Dashboard Tools**: Connect with Grafana, Tableau, or custom visualizations
- **Cost Allocation**: Advanced chargeback and showback capabilities

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Review function logs for detailed error information
4. Validate IAM permissions and service configurations

## License

This infrastructure code is provided as-is for educational and implementation purposes. Modify as needed for your specific requirements and security policies.