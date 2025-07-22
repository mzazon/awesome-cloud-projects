# Infrastructure as Code for Multi-Cloud Cost Optimization with Cloud Billing API and Cloud Recommender

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Cloud Cost Optimization with Cloud Billing API and Cloud Recommender".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud organization with multiple projects
- Billing Account Administrator or Editor role for cost management
- Project Editor role for deploying Cloud Functions and Pub/Sub
- BigQuery Admin role for data analysis and reporting
- Terraform installed (version 1.0+) for Terraform deployment
- Appropriate IAM permissions for resource creation
- Estimated cost: $50-100/month for moderate usage across 10-20 projects

## Project Structure

```
code/
├── infrastructure-manager/
│   └── main.yaml                    # Infrastructure Manager configuration
├── terraform/
│   ├── main.tf                      # Main Terraform configuration
│   ├── variables.tf                 # Input variables
│   ├── outputs.tf                   # Output values
│   ├── versions.tf                  # Provider version constraints
│   ├── terraform.tfvars.example     # Example variable values
│   └── README.md                    # Terraform-specific documentation
├── scripts/
│   ├── deploy.sh                    # Automated deployment script
│   └── destroy.sh                   # Cleanup script
└── README.md                        # This file
```

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID="cost-optimization-$(date +%s)"
export REGION="us-central1"
export BILLING_ACCOUNT_ID=$(gcloud billing accounts list --format="value(name)" --limit=1)

# Create project and enable APIs
gcloud projects create ${PROJECT_ID} --name="Cost Optimization System"
gcloud config set project ${PROJECT_ID}
gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}

# Enable required APIs
gcloud services enable cloudbilling.googleapis.com \
    cloudfunctions.googleapis.com \
    pubsub.googleapis.com \
    bigquery.googleapis.com \
    storage.googleapis.com \
    recommender.googleapis.com \
    cloudscheduler.googleapis.com \
    monitoring.googleapis.com \
    config.googleapis.com

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-optimization \
    --service-account "projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/main.yaml" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Set up environment variables
export PROJECT_ID="cost-optimization-$(date +%s)"
export REGION="us-central1"
export BILLING_ACCOUNT_ID=$(gcloud billing accounts list --format="value(name)" --limit=1)

# Create project and enable APIs (if not using automated scripts)
gcloud projects create ${PROJECT_ID} --name="Cost Optimization System"
gcloud config set project ${PROJECT_ID}
gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT_ID}

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
region = "${REGION}"
billing_account_id = "${BILLING_ACCOUNT_ID}"
organization_id = "your-org-id"
slack_webhook_url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
EOF

# Plan and apply the infrastructure
terraform plan
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow the prompts to configure your environment
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

- `project_id`: Google Cloud project ID for the cost optimization system
- `region`: Primary region for resource deployment
- `billing_account_id`: Billing account to monitor and optimize
- `organization_id`: Google Cloud organization ID
- `dataset_name`: BigQuery dataset name for cost analytics
- `notification_email`: Email address for cost optimization alerts

### Terraform Variables

Available variables in `terraform/variables.tf`:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | ✅ |
| `region` | Primary region for resources | `us-central1` | ❌ |
| `billing_account_id` | Billing account ID to monitor | - | ✅ |
| `organization_id` | Google Cloud organization ID | - | ✅ |
| `dataset_name` | BigQuery dataset name | `cost_optimization` | ❌ |
| `slack_webhook_url` | Slack webhook for notifications | `""` | ❌ |
| `notification_email` | Email for alerts | `admin@example.com` | ❌ |
| `function_timeout` | Cloud Function timeout | `300` | ❌ |
| `scheduler_timezone` | Timezone for scheduled jobs | `America/New_York` | ❌ |

### Bash Script Configuration

The deployment script will prompt for:

- Project ID for the cost optimization system
- Google Cloud region preference
- Billing account ID to monitor
- Organization ID (optional)
- Slack webhook URL (optional)
- Email address for notifications

## Deployment Architecture

The infrastructure creates the following resources:

### Core Services
- **BigQuery Dataset**: Data warehouse for cost analytics and recommendations
- **Cloud Storage Bucket**: Storage for reports and intermediate data
- **Pub/Sub Topics**: Event-driven messaging for workflow coordination
- **Cloud Functions**: Serverless processing for cost analysis and recommendations

### Automation & Scheduling
- **Cloud Scheduler**: Automated triggers for regular cost analysis
- **Cloud Monitoring**: Observability and alerting for the optimization system
- **IAM Roles**: Least privilege access controls for all components

### Data Processing Pipeline
- **Cost Analysis Function**: Retrieves and processes billing data
- **Recommendation Engine**: Generates optimization suggestions using Cloud Recommender
- **Optimization Automation**: Implements automated responses and alerting

## Validation & Testing

After deployment, validate the system:

1. **Check Function Deployment**:
   ```bash
   gcloud functions list --filter="name:analyze-costs OR name:generate-recommendations"
   ```

2. **Verify BigQuery Setup**:
   ```bash
   bq ls ${PROJECT_ID}:cost_optimization
   ```

3. **Test Pub/Sub Topics**:
   ```bash
   gcloud pubsub topics list --filter="name:cost-optimization"
   ```

4. **Validate Scheduled Jobs**:
   ```bash
   gcloud scheduler jobs list
   ```

5. **Test Manual Trigger**:
   ```bash
   gcloud scheduler jobs run daily-cost-analysis
   ```

## Monitoring & Operations

### Dashboard Access

- **Cloud Monitoring**: Access cost optimization dashboard in the Google Cloud Console
- **BigQuery**: Query cost analysis tables for custom reports
- **Cloud Storage**: Download generated cost optimization reports

### Key Metrics

- Function execution success rate
- Cost analysis processing time
- Number of recommendations generated
- Potential savings identified
- Alert trigger frequency

### Troubleshooting

Common issues and solutions:

1. **Function Timeouts**: Increase timeout in configuration
2. **BigQuery Permissions**: Verify service account has BigQuery Admin role
3. **Billing API Errors**: Ensure billing account access permissions
4. **Pub/Sub Message Loss**: Check subscription acknowledgment settings

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/cost-optimization
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

### Manual Cleanup

If automated cleanup fails:

```bash
# Delete Cloud Functions
gcloud functions delete analyze-costs --quiet
gcloud functions delete generate-recommendations --quiet
gcloud functions delete optimize-resources --quiet

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete cost-analysis-sub --quiet
gcloud pubsub topics delete cost-optimization-topic --quiet

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:cost_optimization

# Delete Cloud Storage bucket
gsutil -m rm -r gs://cost-optimization-bucket

# Delete Cloud Scheduler jobs
gcloud scheduler jobs delete daily-cost-analysis --quiet

# Delete the project
gcloud projects delete ${PROJECT_ID}
```

## Security Considerations

### IAM Best Practices

- Service accounts use least privilege principle
- Cloud Functions have minimal required permissions
- BigQuery access is restricted to specific datasets
- Billing API access is limited to read-only operations

### Data Protection

- All data is encrypted at rest and in transit
- Cloud Storage buckets use versioning for data protection
- BigQuery datasets include access logging
- Sensitive configuration uses Secret Manager

### Network Security

- Functions use private Google networks
- No public endpoints exposed unnecessarily
- VPC Service Controls can be enabled for additional isolation

## Cost Optimization

### Resource Efficiency

- Cloud Functions use minimal memory allocation
- BigQuery queries are optimized for cost efficiency
- Cloud Storage uses standard tier for cost optimization
- Pub/Sub topics use minimal retention periods

### Expected Savings

Organizations typically achieve:
- 15-25% cost reduction through automated optimization
- 30-40% reduction in cost analysis overhead
- 50-60% faster identification of optimization opportunities
- ROI typically achieved within 2-3 months

## Customization

### Adding Custom Recommendations

Extend the recommendation engine by:

1. Adding custom logic in the recommendation Cloud Function
2. Creating additional BigQuery tables for custom metrics
3. Implementing domain-specific optimization rules
4. Integrating with third-party cost optimization tools

### Multi-Cloud Integration

To extend to other cloud providers:

1. Add AWS Cost Management API integration
2. Include Azure Cost Management API calls
3. Create unified cost reporting across providers
4. Implement cross-cloud optimization recommendations

## Support & Documentation

- **Recipe Documentation**: Refer to the original recipe markdown file
- **Google Cloud Billing API**: [Official Documentation](https://cloud.google.com/billing/docs/reference/rest)
- **Cloud Recommender**: [Best Practices Guide](https://cloud.google.com/recommender/docs/overview)
- **FinOps Hub**: [Implementation Guide](https://cloud.google.com/billing/docs/how-to/finops-hub)
- **Cost Optimization**: [Architecture Patterns](https://cloud.google.com/architecture/cost-optimization)

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud security best practices
3. Update documentation for any configuration changes
4. Validate cost impacts of modifications
5. Submit pull requests with detailed change descriptions

## License

This infrastructure code is provided as-is for educational and implementation purposes. Refer to your organization's policies for production deployment guidelines.