# Infrastructure as Code for Enterprise Database Analytics with Oracle and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Database Analytics with Oracle and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual orchestration

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 531.0.0 or later)
- Google Cloud project with billing enabled
- Oracle Database@Google Cloud access (requires approval from Google Cloud sales)
- Appropriate IAM permissions for resource creation:
  - Oracle Database Administrator
  - AI Platform Admin
  - BigQuery Admin
  - Monitoring Admin
  - Service Usage Admin
  - Compute Admin
- Terraform installed (version 1.0 or later) if using Terraform implementation
- Basic knowledge of Oracle SQL, Python, and machine learning concepts

> **Important**: Oracle Database@Google Cloud requires partnership approval and may have regional availability limitations. Currently available in us-east4, us-west1, europe-west2, and europe-west3. Contact Google Cloud sales for access eligibility.

## Architecture Overview

This solution deploys:

- Oracle Database@Google Cloud with Exadata infrastructure
- Autonomous Database instance for analytics workloads
- Vertex AI environment with workbench and model endpoints
- BigQuery dataset with Oracle connectivity
- Cloud Monitoring with performance alerts
- Cloud Functions for automated data pipeline orchestration
- Cloud Scheduler for automated pipeline execution

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses Terraform configurations with additional Google Cloud integration.

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments create oracle-analytics-deployment \
    --location=${REGION} \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/oracle-analytics/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe oracle-analytics-deployment \
    --location=${REGION}
```

### Using Terraform

Direct Terraform deployment using the Google Cloud provider with support for Oracle Database@Google Cloud resources.

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

Manual deployment using Google Cloud CLI commands with proper error handling and validation.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Run deployment script
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Configuration Variables

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | ✅ |
| `region` | Deployment region | `us-central1` | ✅ |
| `oracle_instance_name` | Oracle infrastructure name | `oracle-analytics-${random}` | ❌ |
| `vertex_endpoint_name` | Vertex AI endpoint name | `oracle-ml-endpoint-${random}` | ❌ |
| `enable_monitoring` | Enable Cloud Monitoring alerts | `true` | ❌ |
| `environment` | Environment label | `production` | ❌ |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | `string` | - | ✅ |
| `region` | Deployment region | `string` | `us-central1` | ✅ |
| `zone` | Deployment zone | `string` | `us-central1-a` | ❌ |
| `oracle_shape` | Oracle Exadata shape | `string` | `Exadata.X9M` | ❌ |
| `oracle_storage_count` | Number of storage servers | `number` | `3` | ❌ |
| `oracle_compute_count` | Number of compute nodes | `number` | `2` | ❌ |
| `vertex_machine_type` | Workbench machine type | `string` | `n1-standard-4` | ❌ |
| `bigquery_location` | BigQuery dataset location | `string` | `US` | ❌ |
| `labels` | Resource labels | `map(string)` | `{}` | ❌ |

### Script Environment Variables

| Variable | Description | Example | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | `my-analytics-project` | ✅ |
| `REGION` | Deployment region | `us-central1` | ✅ |
| `ZONE` | Deployment zone | `us-central1-a` | ❌ |
| `ORACLE_ADMIN_PASSWORD` | Oracle admin password | `SecurePassword123!` | ✅ |

## Validation & Testing

After deployment, validate the infrastructure using these commands:

```bash
# Verify Oracle Database@Google Cloud infrastructure
gcloud oracle-database cloud-exadata-infrastructures list --location=${REGION}

# Check Autonomous Database status
gcloud oracle-database autonomous-databases list --location=${REGION}

# Validate Vertex AI resources
gcloud ai endpoints list --region=${REGION}
gcloud notebooks instances list --location=${ZONE}

# Verify BigQuery dataset
bq ls ${PROJECT_ID}:oracle_analytics_*

# Test Cloud Monitoring alerts
gcloud alpha monitoring policies list --filter="displayName:Oracle"

# Check Cloud Functions deployment
gcloud functions list --filter="name:oracle-analytics-pipeline"

# Validate Cloud Scheduler jobs
gcloud scheduler jobs list --filter="name:oracle-analytics-schedule"
```

## Monitoring and Operations

The deployed infrastructure includes comprehensive monitoring:

- **Oracle Performance Monitoring**: CPU utilization, memory usage, and storage metrics
- **Vertex AI Model Monitoring**: Prediction latency, accuracy metrics, and endpoint health
- **BigQuery Analytics**: Query performance and cost monitoring
- **Pipeline Monitoring**: Function execution logs and scheduler job status

Access monitoring dashboards:

```bash
# View Oracle database metrics
gcloud logging read 'resource.type="oracle_database"' --limit=10

# Monitor Vertex AI model performance
gcloud ai endpoints list --region=${REGION} --format="table(displayName,deployedModels[0].model)"

# Check pipeline execution logs
gcloud functions logs read oracle-analytics-pipeline-${RANDOM_SUFFIX} --limit=10
```

## Cost Optimization

Estimated costs for this deployment:

- **Oracle Database@Google Cloud**: $500-1200/month (depends on Exadata configuration)
- **Vertex AI**: $50-200/month (based on model usage and workbench runtime)
- **BigQuery**: $20-100/month (based on data volume and query frequency)
- **Cloud Monitoring**: $10-30/month (based on metric volume)
- **Cloud Functions/Scheduler**: $5-20/month (based on execution frequency)

Cost optimization strategies:

1. **Oracle Auto-scaling**: Enable automatic compute scaling based on workload
2. **Vertex AI Spot Instances**: Use preemptible instances for training workloads
3. **BigQuery Partitioning**: Implement table partitioning to reduce query costs
4. **Monitoring Retention**: Adjust log retention periods based on compliance needs

## Security Considerations

This deployment implements enterprise security best practices:

- **Least Privilege IAM**: Custom service accounts with minimal required permissions
- **Network Security**: Private networking for Oracle and Vertex AI resources
- **Data Encryption**: Encryption at rest and in transit for all data
- **Audit Logging**: Comprehensive audit trails for all resource access
- **Secret Management**: Secure password storage using Secret Manager

Security validation:

```bash
# Review IAM bindings
gcloud projects get-iam-policy ${PROJECT_ID}

# Check security policies
gcloud compute security-policies list

# Validate encryption settings
gcloud oracle-database autonomous-databases describe ${ADB_NAME} \
    --location=${REGION} --format="value(encryptionKey)"
```

## Troubleshooting

### Common Issues

1. **Oracle Database@Google Cloud Access Denied**
   - Verify partnership approval with Google Cloud sales
   - Check regional availability (us-east4, us-west1, europe-west2, europe-west3)
   - Ensure proper IAM permissions

2. **Vertex AI Resource Creation Failures**
   - Verify API enablement: `gcloud services list --enabled | grep aiplatform`
   - Check quota limits: `gcloud compute project-info describe --format="value(quotas)"`
   - Validate service account permissions

3. **BigQuery Connection Errors**
   - Verify Oracle database connectivity and firewall rules
   - Check service account permissions for BigQuery and Oracle resources
   - Validate connection string format

4. **Pipeline Execution Failures**
   - Review Cloud Function logs: `gcloud functions logs read oracle-analytics-pipeline`
   - Check Cloud Scheduler job configuration and permissions
   - Verify environment variables and secret access

### Support Resources

- [Oracle Database@Google Cloud Documentation](https://cloud.google.com/oracle/database/docs/overview)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete oracle-analytics-deployment \
    --location=${REGION} \
    --quiet

# Verify resource cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources are deleted
./scripts/validate-cleanup.sh
```

> **Warning**: Oracle Database@Google Cloud infrastructure deletion may take 30-45 minutes to complete. Ensure all dependent resources are removed before deleting the Exadata infrastructure.

## Customization

### Adding Custom Monitoring

To add custom monitoring metrics:

1. **Infrastructure Manager**: Modify `monitoring.yaml` to include additional alert policies
2. **Terraform**: Update `monitoring.tf` with new `google_monitoring_alert_policy` resources
3. **Scripts**: Add monitoring configuration to `scripts/configure-monitoring.sh`

### Scaling Configuration

Adjust Oracle and Vertex AI resources based on workload requirements:

- **Oracle Scaling**: Modify `oracle_compute_count` and `oracle_storage_count` variables
- **Vertex AI Scaling**: Update `vertex_machine_type` and enable auto-scaling policies
- **BigQuery Optimization**: Configure slot reservations for predictable workloads

### Integration Extensions

The infrastructure can be extended with:

- **Data Pipeline Integration**: Add Cloud Dataflow for real-time streaming
- **Advanced Analytics**: Include Looker Studio for business intelligence
- **Security Enhancement**: Implement VPC Service Controls and Private Google Access
- **Backup Automation**: Configure automated backup policies for Oracle databases

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for implementation guidance
2. Check Google Cloud provider documentation for resource configuration
3. Consult Oracle Database@Google Cloud support for database-specific issues
4. Reference Vertex AI documentation for ML platform questions

For infrastructure-specific issues, create an issue in the repository with:
- Deployment method used (Infrastructure Manager/Terraform/Scripts)
- Error messages and logs
- Environment configuration details
- Steps to reproduce the issue