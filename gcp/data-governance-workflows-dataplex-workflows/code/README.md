# Infrastructure as Code for Data Governance Workflows with Dataplex and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Data Governance Workflows with Dataplex and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with appropriate permissions
- Terraform installed (version 1.0 or later) for Terraform implementation
- Basic understanding of data governance principles
- Estimated cost: $50-100 for testing environment

### Required APIs

The following APIs must be enabled in your Google Cloud project:

- Dataplex API (`dataplex.googleapis.com`)
- Cloud Workflows API (`workflows.googleapis.com`)
- Cloud Data Loss Prevention API (`dlp.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Cloud Asset API (`cloudasset.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)

### IAM Permissions

Your account or service account needs the following roles:

- `roles/dataplex.admin` - Dataplex lake and zone management
- `roles/workflows.admin` - Cloud Workflows management
- `roles/dlp.admin` - Cloud DLP configuration
- `roles/bigquery.admin` - BigQuery dataset and table management
- `roles/cloudfunctions.admin` - Cloud Functions deployment
- `roles/monitoring.admin` - Cloud Monitoring configuration
- `roles/logging.admin` - Cloud Logging configuration
- `roles/storage.admin` - Cloud Storage bucket management

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-deployment \
    --service-account "projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo "https://github.com/your-org/your-repo.git" \
    --git-source-directory "infrastructure-manager/" \
    --git-source-ref "main" \
    --input-values "project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure implements an intelligent data governance solution with the following components:

- **Dataplex Lake**: Unified data catalog and governance
- **Cloud Workflows**: Orchestration of governance processes
- **Cloud DLP**: Sensitive data detection and classification
- **BigQuery**: Analytics and reporting for governance metrics
- **Cloud Functions**: Custom data quality assessment logic
- **Cloud Monitoring**: Performance and health monitoring
- **Cloud Storage**: Data lake storage with versioning

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud project ID | *Required* |
| `REGION` | Google Cloud region | `us-central1` |
| `ZONE` | Google Cloud zone | `us-central1-a` |
| `BUCKET_NAME` | Storage bucket name | Generated with random suffix |
| `DATASET_NAME` | BigQuery dataset name | Generated with random suffix |
| `LAKE_NAME` | Dataplex lake name | Generated with random suffix |

### Terraform Variables

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `project_id` | string | Google Cloud project ID | *Required* |
| `region` | string | Google Cloud region | `us-central1` |
| `zone` | string | Google Cloud zone | `us-central1-a` |
| `environment` | string | Environment name | `dev` |
| `data_retention_days` | number | Data retention in days | `30` |
| `enable_monitoring` | bool | Enable monitoring resources | `true` |
| `dlp_scan_frequency` | string | DLP scan frequency | `WEEKLY` |

### Infrastructure Manager Variables

Variables are defined in the `variables.yaml` file and can be customized:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
environment: "dev"
data_retention_days: 30
enable_monitoring: true
dlp_scan_frequency: "WEEKLY"
```

## Post-Deployment Steps

After successful deployment, follow these steps to complete the setup:

1. **Upload sample data to test governance workflows**:
   ```bash
   echo "Customer email: test@example.com, Phone: 555-123-4567" > sample-data.txt
   gsutil cp sample-data.txt gs://your-bucket-name/sample-data.txt
   ```

2. **Execute the governance workflow**:
   ```bash
   gcloud workflows run intelligent-governance-workflow \
       --location=${REGION} \
       --data='{"trigger": "manual", "scope": "full_scan"}'
   ```

3. **Verify BigQuery tables contain governance data**:
   ```bash
   bq query --use_legacy_sql=false \
   "SELECT * FROM \`${PROJECT_ID}.governance_analytics.data_quality_metrics\` LIMIT 5;"
   ```

4. **Access monitoring dashboard**:
   - Navigate to Cloud Monitoring in Google Cloud Console
   - View the "Data Governance Dashboard" for metrics visualization

## Monitoring and Alerting

The infrastructure includes comprehensive monitoring:

- **Data Quality Metrics**: Tracked in BigQuery with visualization in Cloud Monitoring
- **Workflow Execution Logs**: Available in Cloud Logging
- **Alert Policies**: Configured for quality score thresholds and workflow failures
- **Custom Metrics**: Log-based metrics for governance events

### Key Metrics to Monitor

- Data quality scores by asset and zone
- Sensitive data detection counts
- Workflow execution success rates
- DLP scan completion status
- Compliance violation trends

## Security Considerations

- **IAM Roles**: Least privilege access for all service accounts
- **Data Encryption**: All data encrypted at rest and in transit
- **VPC Security**: Network isolation where applicable
- **Audit Logging**: Comprehensive audit trail for all governance activities
- **Sensitive Data Protection**: Cloud DLP for automatic sensitive data detection

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify IAM roles are correctly assigned
3. **Quota Limitations**: Check project quotas for BigQuery, Cloud Functions, and Dataplex
4. **Workflow Execution Failures**: Check Cloud Logging for detailed error messages

### Debugging Steps

```bash
# Check workflow execution status
gcloud workflows executions list --workflow=intelligent-governance-workflow --location=${REGION}

# View workflow execution details
gcloud workflows executions describe EXECUTION_ID --workflow=intelligent-governance-workflow --location=${REGION}

# Check function logs
gcloud functions logs read data-quality-assessor --region=${REGION}

# Verify Dataplex lake status
gcloud dataplex lakes describe governance-lake --location=${REGION}
```

## Cleanup

### Using Infrastructure Manager (Google Cloud)

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/governance-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

After running automated cleanup, verify these resources are removed:

- Dataplex lakes and zones
- Cloud Workflows
- Cloud Functions
- BigQuery datasets
- Cloud Storage buckets
- DLP templates and triggers
- Monitoring policies and dashboards

## Cost Optimization

To optimize costs in your deployment:

1. **Use appropriate BigQuery slots**: Consider on-demand vs. reserved slots based on usage
2. **Configure data retention policies**: Set appropriate retention periods for logs and metrics
3. **Schedule workflows efficiently**: Avoid unnecessary frequent executions
4. **Use Cloud Storage lifecycle policies**: Automatically transition data to cheaper storage classes
5. **Monitor resource usage**: Use Cloud Monitoring to track resource utilization

## Customization

### Extending the Solution

1. **Add custom data quality rules**: Modify the Cloud Function to include domain-specific quality checks
2. **Integrate with external systems**: Extend workflows to integrate with third-party governance tools
3. **Implement advanced alerting**: Create custom notification channels for different stakeholder groups
4. **Add data lineage tracking**: Integrate with Cloud Data Fusion for comprehensive lineage visualization

### Advanced Configurations

- **Multi-region deployment**: Modify Terraform variables to deploy across multiple regions
- **Custom DLP templates**: Create organization-specific sensitive data detection rules
- **Enhanced monitoring**: Add custom metrics and dashboards for business-specific KPIs
- **Automated remediation**: Extend workflows to automatically fix common data quality issues

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Review Terraform provider documentation for configuration details

## Version Information

- **Recipe Version**: 1.0
- **Last Updated**: 2025-07-12
- **Terraform Provider Versions**: See `versions.tf` for specific version constraints
- **Infrastructure Manager Version**: Latest available in Google Cloud

## Contributing

When modifying this infrastructure:

1. Update variable descriptions and defaults appropriately
2. Maintain backward compatibility where possible
3. Update documentation to reflect changes
4. Test changes in a development environment first
5. Follow Google Cloud best practices for resource naming and tagging