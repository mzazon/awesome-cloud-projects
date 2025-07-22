# BigQuery Query Optimization with AI and Cloud Composer - Terraform Infrastructure

This Terraform configuration deploys a complete intelligent query optimization system using BigQuery AI features, Cloud Composer orchestration, and Vertex AI machine learning capabilities.

## Architecture Overview

The infrastructure creates an autonomous system that:

- **Monitors** BigQuery query performance in real-time
- **Analyzes** queries using AI to identify optimization opportunities  
- **Implements** optimizations automatically through Cloud Composer workflows
- **Tracks** improvement metrics and provides comprehensive monitoring

## Components Deployed

### Core Infrastructure

- **BigQuery Dataset**: Analytics dataset with performance monitoring views
- **Sample Tables**: Sales transactions table with realistic data for testing
- **Materialized Views**: Pre-computed aggregations for common query patterns
- **Cloud Composer Environment**: Managed Apache Airflow for workflow orchestration
- **Cloud Storage Bucket**: Storage for DAGs, ML models, and artifacts

### Machine Learning Components

- **Vertex AI Integration**: ML model for predicting optimization opportunities
- **Feature Engineering**: Automated extraction of query characteristics
- **Training Pipeline**: Automated model retraining based on performance data

### Monitoring and Alerting

- **Cloud Monitoring Dashboard**: Real-time visualization of query performance
- **Alert Policies**: Proactive notifications for performance issues
- **Performance Metrics**: Comprehensive tracking of optimization effectiveness

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **APIs Enabled**:
   - BigQuery API
   - Cloud Composer API
   - Vertex AI API
   - Cloud Monitoring API
   - Cloud Storage API
   - Compute Engine API

3. **IAM Permissions**:
   - BigQuery Admin
   - Cloud Composer Admin
   - Vertex AI User
   - Storage Admin
   - Monitoring Editor

4. **Tools Required**:
   - Terraform >= 1.5
   - gcloud CLI
   - Appropriate authentication configured

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd gcp/database-query-optimization-bigquery-ai-composer/code/terraform/

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit Variables

Edit `terraform.tfvars` with your project-specific values:

```hcl
project_id = "your-project-id"
region     = "us-central1"
environment = "prod"

# Optional customizations
dataset_name = "optimization_analytics"
composer_node_count = 3
enable_monitoring = true
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check BigQuery dataset
bq ls optimization_analytics_<suffix>

# Access Airflow UI (URL from terraform output)
terraform output composer_airflow_uri

# View monitoring dashboard (URL from terraform output)  
terraform output monitoring_dashboard_url
```

## Configuration Options

### Dataset Configuration

```hcl
# BigQuery dataset settings
dataset_name = "optimization_analytics"
dataset_location = "US"
sample_data_size = 100  # thousands of records

# Cost controls
enable_cost_controls = true
table_expiration_days = 7
```

### Cloud Composer Settings

```hcl
# Composer environment configuration
composer_node_count = 3
composer_machine_type = "n1-standard-2"
composer_disk_size = 100
composer_python_version = "3"
```

### Monitoring Configuration

```hcl
# Monitoring and alerting
enable_monitoring = true
alert_notification_channels = [
  "projects/PROJECT_ID/notificationChannels/CHANNEL_ID"
]
```

### Service Accounts

```hcl
# Create dedicated service accounts for each component
create_service_accounts = true
```

## Usage Instructions

### 1. Populate Sample Data

After deployment, generate sample data:

```bash
# Get dataset name from output
DATASET_NAME=$(terraform output -raw bigquery_dataset_id)

# Create sample sales data
bq query --use_legacy_sql=false \
  --destination_table=${PROJECT_ID}:${DATASET_NAME}.sales_transactions \
  "CREATE TABLE \`${PROJECT_ID}.${DATASET_NAME}.sales_transactions\` AS
   SELECT 
     GENERATE_UUID() as transaction_id,
     CAST(RAND() * 1000000 as INT64) as customer_id,
     CAST(RAND() * 100000 as INT64) as product_id,
     ROUND(RAND() * 1000, 2) as amount,
     TIMESTAMP_SUB(CURRENT_TIMESTAMP(), 
       INTERVAL CAST(RAND() * 365 * 24 * 60 * 60 as INT64) SECOND) as transaction_date,
     CASE 
       WHEN RAND() < 0.3 THEN 'online'
       WHEN RAND() < 0.7 THEN 'retail'
       ELSE 'mobile'
     END as channel
   FROM UNNEST(GENERATE_ARRAY(1, 100000)) as num"
```

### 2. Test Query Optimization

Run test queries to trigger optimization:

```bash
# Test query with optimization opportunities
bq query --use_legacy_sql=false \
  "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_transactions\`
   WHERE transaction_date >= '2024-01-01'
   ORDER BY amount DESC
   LIMIT 100"

# Query that benefits from materialized view
bq query --use_legacy_sql=false \
  "SELECT channel, SUM(amount)
   FROM \`${PROJECT_ID}.${DATASET_NAME}.sales_transactions\`
   WHERE DATE(transaction_date) = CURRENT_DATE()
   GROUP BY channel"
```

### 3. Monitor Optimization Pipeline

```bash
# Access Airflow UI
AIRFLOW_URI=$(terraform output -raw composer_airflow_uri)
echo "Airflow UI: ${AIRFLOW_URI}"

# Check optimization recommendations
bq query --use_legacy_sql=false \
  "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.optimization_recommendations\`
   ORDER BY created_timestamp DESC LIMIT 10"

# View performance metrics
bq query --use_legacy_sql=false \
  "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.query_performance_metrics\`
   WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
   ORDER BY duration_ms DESC LIMIT 10"
```

## Troubleshooting

### Common Issues

1. **Composer Environment Creation Timeout**
   ```bash
   # Check environment status
   gcloud composer environments describe ENVIRONMENT_NAME --location=REGION
   
   # Environment creation can take 15-20 minutes
   ```

2. **API Not Enabled Errors**
   ```bash
   # Enable required APIs
   gcloud services enable bigquery.googleapis.com composer.googleapis.com aiplatform.googleapis.com
   ```

3. **Permission Denied Errors**
   ```bash
   # Check current authentication
   gcloud auth list
   
   # Ensure proper IAM roles are assigned
   gcloud projects get-iam-policy PROJECT_ID
   ```

4. **BigQuery Job Failures**
   ```bash
   # Check BigQuery job history
   bq ls -j --max_results=10
   
   # Get job details
   bq show -j JOB_ID
   ```

### Debugging DAG Issues

```bash
# Check DAG status in Composer
gcloud composer environments storage dags list \
  --environment=ENVIRONMENT_NAME \
  --location=REGION

# View Airflow logs
gcloud composer environments storage logs list \
  --environment=ENVIRONMENT_NAME \
  --location=REGION
```

## Cost Management

### Estimated Monthly Costs

- **Cloud Composer**: $150-300 (based on node count and usage)
- **BigQuery Storage**: $5-20 (based on data volume)
- **BigQuery Queries**: $20-100 (based on query volume and optimization)
- **Cloud Storage**: $5-15 (for DAGs and ML artifacts)
- **Vertex AI Training**: $10-50 (based on training frequency)
- **Monitoring**: $5-15 (based on metrics volume)

**Total Estimated**: $195-500 per month

### Cost Optimization Tips

1. **Use table expiration** for temporary data
2. **Configure materialized view refresh intervals** appropriately
3. **Monitor query costs** and optimize expensive queries first
4. **Use Composer auto-scaling** features
5. **Enable BigQuery slot reservations** for predictable workloads

## Security Considerations

### Service Account Permissions

The infrastructure creates dedicated service accounts with minimal required permissions:

- **Composer SA**: BigQuery Admin, Storage Admin, AI Platform User
- **BigQuery SA**: BigQuery Data Editor, Job User  
- **Vertex AI SA**: AI Platform User, Storage Object User

### Data Protection

- **Encryption**: All data encrypted at rest and in transit
- **Access Controls**: IAM-based access to all resources
- **Network Security**: VPC-native networking for Composer
- **Audit Logging**: All activities logged for compliance

## Maintenance and Updates

### Regular Tasks

1. **Monitor materialized view refresh costs**
2. **Review optimization recommendations weekly**
3. **Update ML model training frequency based on data volume**
4. **Review and update alert thresholds**

### Upgrading Components

```bash
# Update Composer environment
gcloud composer environments update ENVIRONMENT_NAME \
  --location=REGION \
  --update-pypi-packages-from-file=requirements.txt

# Update Terraform configuration
terraform plan
terraform apply
```

## Support and Documentation

- [BigQuery Optimization Best Practices](https://cloud.google.com/bigquery/docs/best-practices-performance-overview)
- [Cloud Composer Documentation](https://cloud.google.com/composer/docs)
- [Vertex AI Training Documentation](https://cloud.google.com/vertex-ai/docs/training/overview)
- [BigQuery AI Features](https://cloud.google.com/bigquery/docs/ai-query-assistance)

## Contributing

To contribute improvements to this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit a pull request with detailed description

## License

This infrastructure code is provided under the Apache 2.0 License. See LICENSE file for details.