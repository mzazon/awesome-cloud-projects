# Infrastructure as Code for Engineering High-Frequency Trading Risk Analytics with TPU Ironwood and Cloud Datastream

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Engineering High-Frequency Trading Risk Analytics with TPU Ironwood and Cloud Datastream".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code tool (YAML)
- **Terraform**: Multi-cloud infrastructure as code using the Google Cloud provider
- **Bash Scripts**: Deployment and cleanup scripts for manual resource management

## Architecture Overview

This solution deploys a high-performance trading risk analytics platform leveraging:

- **TPU Ironwood**: Seventh-generation tensor processing units for ultra-low latency AI inference
- **Cloud Datastream**: Real-time change data capture for streaming database replication
- **BigQuery**: High-performance analytics and data warehousing
- **Cloud Run**: Serverless container platform for API serving
- **Cloud Storage**: Object storage for model artifacts and data
- **Cloud Monitoring & Logging**: Comprehensive observability and alerting

## Prerequisites

### General Requirements

- Google Cloud Platform account with billing enabled
- Google Cloud CLI (gcloud) v450.0.0 or later installed and configured
- Appropriate IAM permissions for:
  - TPU resources (`roles/tpu.admin`)
  - Datastream resources (`roles/datastream.admin`)
  - BigQuery resources (`roles/bigquery.admin`)
  - Cloud Run resources (`roles/run.admin`)
  - Cloud Storage resources (`roles/storage.admin`)
  - Artifact Registry resources (`roles/artifactregistry.admin`)
  - AI Platform resources (`roles/aiplatform.admin`)
  - Monitoring resources (`roles/monitoring.admin`)

### Technical Requirements

- Advanced understanding of financial derivatives, risk analytics, and high-frequency trading
- Python 3.9+ development environment (for model deployment)
- Existing trading database (MySQL, PostgreSQL, or Oracle) with transaction data
- Docker installed (for Cloud Run container builds)

### Cost Considerations

**⚠️ Important Cost Warning**: This solution uses premium-tier infrastructure with substantial costs:

- TPU Ironwood clusters: $20-50 per hour per node
- High-throughput data streaming: $0.10 per GB processed
- BigQuery analysis: $5 per TB queried
- Cloud Run services: $0.40 per million requests

**Estimated daily cost**: $2,500-$5,000 depending on trading volume and TPU utilization.

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager API enabled
- `config-connector` components if using custom resources

#### Terraform
- Terraform v1.5.0 or later
- Google Cloud provider v4.84.0 or later
- Service account with appropriate permissions for Terraform state management

#### Bash Scripts
- `curl` and `jq` for API calls and JSON processing
- Sufficient permissions to create and manage all required resources

## Quick Start

### Prerequisites Setup

Before deploying with any method, configure your environment:

```bash
# Set your project ID
export PROJECT_ID="your-hft-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs
gcloud services enable tpu.googleapis.com
gcloud services enable datastream.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable logging.googleapis.com
```

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC solution, providing seamless integration with Google Cloud services.

```bash
# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/hft-risk-analytics \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file=terraform.tfvars

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/hft-risk-analytics

# View deployment resources
gcloud infra-manager resources list --deployment=projects/${PROJECT_ID}/locations/${REGION}/deployments/hft-risk-analytics
```

### Using Terraform

Terraform provides cross-cloud compatibility and advanced state management capabilities.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -auto-approve

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide step-by-step deployment with detailed progress indicators.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow the interactive prompts for configuration
```

## Configuration Options

### Environment Variables

Configure these environment variables before deployment:

```bash
# Core Configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Resource Configuration
export DATASET_ID="trading_analytics"
export BUCKET_NAME="hft-risk-data-$(openssl rand -hex 4)"
export TPU_NAME="ironwood-risk-tpu-$(openssl rand -hex 4)"
export CLOUD_RUN_SERVICE="risk-analytics-api-$(openssl rand -hex 4)"

# Database Configuration (for Datastream)
export TRADING_DB_HOST="your-trading-db-host"
export TRADING_DB_PORT="3306"
export TRADING_DB_USER="datastream_user"
export TRADING_DB_PASSWORD="your-secure-password"

# Security Configuration
export KMS_KEY_RING="hft-security-ring"
export KMS_KEY_NAME="hft-encryption-key"
```

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `tpu_accelerator_type`: TPU type (default: v6e-256)
- `dataset_location`: BigQuery dataset location
- `enable_monitoring`: Enable comprehensive monitoring (default: true)
- `trading_db_config`: Database connection configuration for Datastream

### Infrastructure Manager Configuration

Customize deployment in `infrastructure-manager/main.yaml`:

- Modify resource quotas and limits
- Adjust TPU cluster configuration
- Configure security policies
- Set monitoring thresholds

## Post-Deployment Configuration

### 1. Configure Trading Database Access

Set up your trading database for Datastream replication:

```sql
-- Create dedicated user for Datastream
CREATE USER 'datastream_user'@'%' IDENTIFIED BY 'your-secure-password';
GRANT REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'datastream_user'@'%';
GRANT SELECT ON trading_db.* TO 'datastream_user'@'%';

-- Enable binary logging
SET GLOBAL binlog_format = 'ROW';
SET GLOBAL binlog_row_image = 'FULL';
```

### 2. Deploy Risk Analytics Models

Upload your pre-trained risk models to the TPU cluster:

```bash
# Upload model artifacts to Cloud Storage
gsutil cp -r ./risk-models/* gs://${BUCKET_NAME}/models/

# Deploy models to TPU Ironwood
gcloud ai models deploy portfolio-risk-model \
    --region=${REGION} \
    --model=gs://${BUCKET_NAME}/models/portfolio-risk-v2.1 \
    --platform=tpu \
    --accelerator-type=tpu-v6e-256
```

### 3. Configure API Authentication

Set up authentication for the risk analytics API:

```bash
# Create API service account
gcloud iam service-accounts create risk-api-service \
    --display-name="Risk Analytics API Service Account"

# Grant necessary permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:risk-api-service@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:risk-api-service@${PROJECT_ID}.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"
```

## Validation & Testing

### 1. Verify TPU Ironwood Cluster

```bash
# Check TPU cluster status
gcloud compute tpus tpu-vm describe ${TPU_NAME} \
    --zone=${ZONE} \
    --format="table(name,state,acceleratorType,networkEndpoints[].ipAddress)"

# Test TPU connectivity
gcloud compute tpus tpu-vm ssh ${TPU_NAME} \
    --zone=${ZONE} \
    --command="python3 -c 'import tensorflow as tf; print(tf.config.list_physical_devices())'"
```

### 2. Validate Data Streaming

```bash
# Check Datastream pipeline status
gcloud datastream streams describe trading-data-stream \
    --location=${REGION} \
    --format="table(name,state,sourceConfig.mysqlSourceConfig.includeObjects)"

# Verify data ingestion in BigQuery
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as recent_records FROM \`${PROJECT_ID}.${DATASET_ID}.trading_positions\` 
     WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)"
```

### 3. Test Risk Analytics API

```bash
# Get Cloud Run service URL
export SERVICE_URL=$(gcloud run services describe ${CLOUD_RUN_SERVICE} \
    --region=${REGION} \
    --format="value(status.url)")

# Test API endpoint
curl -X POST "${SERVICE_URL}/calculate-risk" \
    -H "Content-Type: application/json" \
    -d '{
        "portfolio_id": "TEST_001",
        "positions": [
            {"symbol": "AAPL", "quantity": 1000, "price": 150.50}
        ]
    }' | jq .
```

### 4. Performance Testing

```bash
# Load test the API (requires Apache Bench)
ab -n 1000 -c 50 -T "application/json" \
    -p test-payload.json \
    "${SERVICE_URL}/calculate-risk"

# Monitor TPU utilization during load test
gcloud monitoring metrics list \
    --filter="metric.type=tpu.googleapis.com/accelerator/duty_cycle"
```

## Monitoring & Observability

### Access Monitoring Dashboards

1. **Cloud Monitoring Console**: Navigate to the Google Cloud Console → Monitoring
2. **Custom Dashboards**: View the automatically created "HFT Risk Analytics" dashboard
3. **Alerting Policies**: Monitor configured alerts for latency and error rates

### Key Metrics to Monitor

- **TPU Inference Latency**: Target < 1ms for risk calculations
- **API Response Time**: Target < 500ms for end-to-end requests
- **Data Streaming Lag**: Monitor Datastream replication delay
- **Error Rates**: Track API errors and model inference failures
- **Cost Metrics**: Monitor TPU utilization and data processing costs

### Log Analysis

```bash
# View Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${CLOUD_RUN_SERVICE}" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Monitor TPU performance logs
gcloud logging read "resource.type=tpu_worker" \
    --filter="severity>=WARNING" \
    --limit=20
```

## Troubleshooting

### Common Issues

#### TPU Quota Errors
```bash
# Check TPU quotas
gcloud compute project-info describe \
    --format="table(quotas.metric,quotas.usage,quotas.limit)" \
    | grep -i tpu

# Request quota increase if needed
gcloud alpha compute quotas list --filter="metric:TPU"
```

#### Datastream Connection Issues
```bash
# Test database connectivity
gcloud datastream connection-profiles test trading-db-source \
    --location=${REGION}

# Check firewall rules for database access
gcloud compute firewall-rules list \
    --filter="direction=INGRESS AND allowed.ports:3306"
```

#### API Performance Issues
```bash
# Check Cloud Run service configuration
gcloud run services describe ${CLOUD_RUN_SERVICE} \
    --region=${REGION} \
    --format="yaml(spec.template.spec.containers[0].resources)"

# Monitor cold start metrics
gcloud logging read "resource.type=cloud_run_revision AND textPayload:\"cold start\"" \
    --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/hft-risk-analytics

# Verify all resources are removed
gcloud infra-manager resources list --deployment=projects/${PROJECT_ID}/locations/${REGION}/deployments/hft-risk-analytics
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}" -auto-approve

# Clean up state files
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow interactive prompts for confirmation
```

### Manual Cleanup Verification

After running automated cleanup, verify critical resources are removed:

```bash
# Check for remaining TPU resources
gcloud compute tpus tpu-vm list --zone=${ZONE}

# Verify BigQuery datasets are deleted
bq ls --project_id=${PROJECT_ID}

# Check Cloud Storage buckets
gsutil ls -p ${PROJECT_ID}

# Verify Cloud Run services
gcloud run services list --region=${REGION}
```

## Security Considerations

### Data Protection

- All data is encrypted at rest using Google Cloud KMS
- Network traffic uses TLS 1.3 encryption
- Database credentials are stored in Secret Manager
- API access requires proper authentication tokens

### Access Control

- Principle of least privilege for all service accounts
- IAM roles are narrowly scoped to required permissions
- VPC Service Controls for data exfiltration protection
- Audit logging enabled for all resource access

### Compliance

- Supports SOC 2 Type II compliance requirements
- GDPR-compliant data handling practices
- Financial services regulatory compliance (Basel III, MiFID II)
- Audit trails for all trading and risk calculations

## Performance Optimization

### TPU Optimization

- Model sharding across multiple TPU cores
- Batch inference for improved throughput
- Custom inference pipelines for risk calculations
- Memory optimization for large financial datasets

### API Optimization

- Connection pooling for database access
- Response caching for frequently requested calculations
- Horizontal pod autoscaling based on demand
- Content compression for large responses

### Cost Optimization

- Preemptible TPU instances for non-critical workloads
- Automated scaling policies based on trading hours
- Data lifecycle management for historical data
- Resource scheduling for off-market hours

## Support & Documentation

### Additional Resources

- [Google Cloud TPU Documentation](https://cloud.google.com/tpu/docs)
- [Cloud Datastream Best Practices](https://cloud.google.com/datastream/docs/best-practices)
- [BigQuery Performance Tuning](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)
- [Cloud Run Production Guide](https://cloud.google.com/run/docs/production)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud Status page for service outages
3. Consult the original recipe documentation
4. Contact Google Cloud Support for platform-specific issues

### Contributing

When modifying this infrastructure:

1. Test changes in a development environment first
2. Update documentation for any configuration changes
3. Validate performance impact of modifications
4. Follow Google Cloud security best practices

---

**⚠️ Production Deployment Notice**: This infrastructure is designed for high-frequency trading environments with substantial computational and financial requirements. Ensure proper testing, monitoring, and cost controls before deploying in production trading systems.