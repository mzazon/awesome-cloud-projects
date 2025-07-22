# Infrastructure as Code for Database Query Optimization with BigQuery AI and Cloud Composer

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Query Optimization with BigQuery AI and Cloud Composer".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Project with billing enabled and appropriate APIs enabled:
  - BigQuery API
  - Cloud Composer API
  - Vertex AI API
  - Cloud Monitoring API
  - Cloud Build API
  - Cloud Storage API
- IAM permissions for:
  - BigQuery Admin
  - Cloud Composer Admin
  - Vertex AI Admin
  - Storage Admin
  - Monitoring Admin
- Understanding of SQL query optimization concepts and Apache Airflow workflows
- Estimated cost: $50-100 for Cloud Composer environment, $20-40 for BigQuery query processing, $10-20 for Vertex AI model training during testing

> **Note**: This recipe uses preview features like BigQuery AI query optimization and Gemini integration. Ensure your project has access to these features and review the [BigQuery AI documentation](https://cloud.google.com/bigquery/docs/ai-query-assistance) for current availability.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply \
    --location=${REGION} \
    --deployment-id=bigquery-optimization \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/im-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}" \
    --local-source="infrastructure-manager/"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review and customize variables
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

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys an intelligent query optimization system with the following components:

### Core Services
- **BigQuery**: Data warehouse with AI-powered query optimization features
- **Cloud Composer**: Managed Apache Airflow for workflow orchestration
- **Vertex AI**: Machine learning platform for query analysis and optimization predictions
- **Cloud Monitoring**: Performance monitoring and alerting

### Key Features
- Automated query performance monitoring using BigQuery Information Schema
- AI-driven optimization recommendations using Vertex AI models
- Orchestrated optimization workflows with Cloud Composer DAGs
- Materialized view creation for frequently accessed data patterns
- Real-time monitoring and alerting for optimization effectiveness

### Data Flow
1. Query execution generates performance metrics in BigQuery
2. Cloud Composer DAG monitors performance data on schedule
3. Vertex AI analyzes query patterns and generates optimization recommendations
4. Automated implementation of optimizations (materialized views, query rewrites)
5. Cloud Monitoring tracks optimization effectiveness and system health

## Configuration

### Infrastructure Manager Variables

Configure the following in `infrastructure-manager/main.yaml`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `composer_environment_name`: Name for the Cloud Composer environment
- `dataset_name`: BigQuery dataset name for optimization analytics
- `bucket_name`: Cloud Storage bucket for Composer and ML artifacts

### Terraform Variables

Configure the following in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Composer Configuration
composer_node_count    = 3
composer_machine_type  = "n1-standard-2"
composer_disk_size     = "100GB"

# BigQuery Configuration
dataset_location = "US"
table_expiration_ms = null

# Monitoring Configuration
notification_email = "your-email@example.com"
```

### Script Configuration

The bash scripts use environment variables for configuration:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export COMPOSER_ENV_NAME="query-optimizer"
```

## Post-Deployment Setup

After infrastructure deployment, complete these setup steps:

### 1. Upload Optimization DAG

```bash
# Upload the query optimization DAG to Composer
gcloud composer environments storage dags import \
    --environment=query-optimizer \
    --location=${REGION} \
    --source=scripts/query_optimization_dag.py
```

### 2. Configure Airflow Variables

```bash
# Set Airflow variables for the DAG
gcloud composer environments run query-optimizer \
    --location=${REGION} \
    variables set -- PROJECT_ID ${PROJECT_ID}

gcloud composer environments run query-optimizer \
    --location=${REGION} \
    variables set -- DATASET_NAME optimization_analytics
```

### 3. Generate Sample Data

```bash
# Create sample data for testing optimization
bq query --use_legacy_sql=false \
    --destination_table=${PROJECT_ID}:optimization_analytics.sales_transactions \
    "SELECT 
       GENERATE_UUID() as transaction_id,
       CAST(RAND() * 1000000 as INT64) as customer_id,
       ROUND(RAND() * 1000, 2) as amount,
       TIMESTAMP_SUB(CURRENT_TIMESTAMP(), 
         INTERVAL CAST(RAND() * 365 * 24 * 60 * 60 as INT64) SECOND) as transaction_date
     FROM UNNEST(GENERATE_ARRAY(1, 100000)) as num"
```

### 4. Access Airflow UI

```bash
# Get Airflow web UI URL
gcloud composer environments describe query-optimizer \
    --location=${REGION} \
    --format="value(config.airflowUri)"
```

## Monitoring and Validation

### Query Performance Dashboard

Access the Cloud Monitoring dashboard to view:
- Query execution trends
- Optimization success rates
- Resource utilization metrics
- Cost optimization tracking

### BigQuery Optimization Metrics

```bash
# Check optimization recommendations
bq query --use_legacy_sql=false \
    "SELECT 
       optimization_type,
       COUNT(*) as recommendation_count,
       AVG(estimated_improvement_percent) as avg_improvement
     FROM \`${PROJECT_ID}.optimization_analytics.optimization_recommendations\`
     GROUP BY optimization_type"
```

### Airflow DAG Status

```bash
# Check DAG execution status
gcloud composer environments run query-optimizer \
    --location=${REGION} \
    dags state query_optimization_pipeline $(date +%Y-%m-%d)
```

## Troubleshooting

### Common Issues

1. **Composer Environment Creation Timeout**
   - Composer environments can take 15-20 minutes to create
   - Check IAM permissions for the Composer service account
   - Verify all required APIs are enabled

2. **BigQuery Access Denied**
   - Ensure BigQuery Admin role is assigned
   - Check dataset and table permissions
   - Verify project billing is enabled

3. **Vertex AI Model Training Failures**
   - Check Vertex AI API is enabled
   - Verify training data quality and format
   - Review service account permissions for Vertex AI

4. **DAG Import Failures**
   - Validate Python syntax in DAG files
   - Check required Python packages are available
   - Verify Airflow connections and variables

### Debug Commands

```bash
# Check Composer environment logs
gcloud composer environments storage logs list \
    --environment=query-optimizer \
    --location=${REGION}

# View BigQuery job history
bq ls -j --max_results=10 ${PROJECT_ID}

# Check Vertex AI training job status
gcloud ai custom-jobs list --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    --location=${REGION} \
    --deployment-id=bigquery-optimization \
    --quiet
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

### Manual Cleanup (if needed)

```bash
# Delete Composer environment
gcloud composer environments delete query-optimizer \
    --location=${REGION} \
    --quiet

# Delete BigQuery dataset
bq rm -r -f optimization_analytics

# Delete Cloud Storage bucket
gsutil -m rm -r gs://your-bucket-name

# Delete monitoring resources
gcloud monitoring dashboards list \
    --filter="displayName:'BigQuery Query Optimization Dashboard'" \
    --format="value(name)" | \
xargs -I {} gcloud monitoring dashboards delete {} --quiet
```

## Cost Optimization

### Resource Costs

- **Cloud Composer**: ~$150-300/month for standard environment
- **BigQuery**: Query processing costs based on data scanned
- **Vertex AI**: Training and prediction costs based on usage
- **Cloud Storage**: Minimal storage costs for DAG files and artifacts
- **Cloud Monitoring**: Basic monitoring included, advanced features may incur costs

### Cost Reduction Strategies

1. **Right-size Composer Environment**: Start with smaller node counts and scale as needed
2. **Optimize BigQuery Queries**: Use partitioning and clustering to reduce data scanned
3. **Schedule Model Training**: Train ML models during off-peak hours
4. **Use Preemptible Instances**: Consider preemptible nodes for Composer workers
5. **Monitor Resource Usage**: Set up budget alerts to track spending

## Security Considerations

### IAM Best Practices

- Use principle of least privilege for service accounts
- Enable audit logging for all services
- Regularly review and rotate service account keys
- Use Workload Identity where possible

### Data Protection

- Enable encryption at rest for BigQuery datasets
- Use VPC Service Controls for additional network security
- Implement data governance policies for optimization analytics
- Regular security scanning of Composer environment

### Network Security

- Deploy Composer in private IP environment
- Use Private Google Access for service communication
- Implement firewall rules for restricted access
- Enable VPC Flow Logs for network monitoring

## Advanced Configuration

### Custom Optimization Logic

Modify the Airflow DAG to include custom optimization rules:

```python
# Add custom optimization logic in query_optimization_dag.py
def custom_optimization_rules(query_text):
    # Implement organization-specific optimization patterns
    # Return optimization recommendations
    pass
```

### Integration with External Systems

- Connect to data catalog systems for enhanced metadata
- Integrate with cost management tools for budget tracking
- Add integration with alerting systems (PagerDuty, Slack)
- Connect to business intelligence tools for reporting

### Performance Tuning

- Adjust Composer worker scaling parameters
- Optimize BigQuery slot allocation
- Tune Vertex AI model parameters
- Configure monitoring alert thresholds

## Support and Documentation

- [BigQuery AI Query Optimization](https://cloud.google.com/bigquery/docs/ai-query-assistance)
- [Cloud Composer Documentation](https://cloud.google.com/composer/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Original Recipe Documentation](../database-query-optimization-bigquery-ai-composer.md)

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation for specific services.