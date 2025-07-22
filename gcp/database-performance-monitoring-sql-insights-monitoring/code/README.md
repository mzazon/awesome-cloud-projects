# Infrastructure as Code for Database Performance Monitoring with Cloud SQL Insights and Cloud Monitoring

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Performance Monitoring with Cloud SQL Insights and Cloud Monitoring".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud SQL Admin
  - Cloud Functions Developer
  - Monitoring Admin
  - Pub/Sub Admin
  - Storage Admin
  - Project Editor (for API enablement)
- Terraform installed (version >= 1.0) for Terraform deployment
- Basic understanding of database monitoring concepts

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that uses standard Terraform configuration.

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/db-monitoring-deployment \
    --service-account "projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source "infrastructure-manager/"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/db-monitoring-deployment
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete monitoring solution
./scripts/deploy.sh

# Follow the prompts to configure your project settings
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `terraform.tfvars` file in the `infrastructure-manager/` directory:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Database configuration
db_tier              = "db-perf-optimized-N-2"
db_storage_size      = 100
db_backup_start_time = "02:00"

# Monitoring configuration
alert_cpu_threshold    = 0.8
alert_query_time_threshold = 5000

# Function configuration
function_memory = 256
function_timeout = 60
```

### Terraform Variables

Edit the `terraform.tfvars.example` file and rename it to `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Database instance configuration
database_instance_name = "performance-db"
database_tier         = "db-perf-optimized-N-2"
database_edition      = "ENTERPRISE_PLUS"
storage_size          = 100

# Monitoring configuration
enable_query_insights = true
cpu_alert_threshold  = 0.8
query_time_threshold = 5000

# Tags
labels = {
  environment = "monitoring"
  project     = "database-performance"
  recipe      = "sql-insights-monitoring"
}
```

### Bash Script Configuration

The bash scripts will prompt for configuration or can use environment variables:

```bash
# Set environment variables before running deploy.sh
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export DB_TIER="db-perf-optimized-N-2"
export STORAGE_SIZE="100"

./scripts/deploy.sh
```

## Architecture Overview

The infrastructure creates:

1. **Cloud SQL PostgreSQL Instance** (Enterprise Plus edition)
   - Query Insights enabled for performance analysis
   - Automated backups and maintenance windows
   - SSD storage with auto-increase enabled

2. **Cloud Monitoring Dashboard**
   - Real-time database performance metrics
   - Query Insights visualization
   - Custom performance indicators

3. **Alerting Policies**
   - High CPU utilization alerts
   - Slow query detection
   - Automated notification triggers

4. **Cloud Functions**
   - Alert processing and analysis
   - Performance report generation
   - Intelligent recommendations

5. **Supporting Services**
   - Pub/Sub for alert notifications
   - Cloud Storage for performance reports
   - IAM roles and service accounts

## Validation

After deployment, verify the infrastructure:

```bash
# Check Cloud SQL instance status
gcloud sql instances describe ${DB_INSTANCE_NAME}

# Verify Query Insights is enabled
gcloud sql instances describe ${DB_INSTANCE_NAME} \
    --format="value(settings.insightsConfig.queryInsightsEnabled)"

# List monitoring dashboards
gcloud monitoring dashboards list \
    --filter="displayName:'Cloud SQL Performance Monitoring Dashboard'"

# Check alerting policies
gcloud alpha monitoring policies list \
    --filter="displayName:('Cloud SQL High CPU Usage' OR 'Cloud SQL Slow Query Detection')"

# Verify Cloud Function deployment
gcloud functions describe ${FUNCTION_NAME}
```

## Testing the Monitoring System

Generate test database activity to validate monitoring:

```bash
# Connect to the database
gcloud sql connect ${DB_INSTANCE_NAME} --user=postgres --database=performance_test

# Run test queries (in psql)
CREATE TABLE test_monitoring (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_monitoring (name) 
SELECT 'Test User ' || generate_series(1, 1000);

-- Generate query load for monitoring
SELECT COUNT(*) FROM test_monitoring WHERE name LIKE '%User 5%';
SELECT * FROM test_monitoring ORDER BY created_at DESC LIMIT 100;
```

## Monitoring and Maintenance

### View Performance Reports

```bash
# List generated performance reports
gsutil ls gs://${BUCKET_NAME}/performance-reports/

# Download a specific report
gsutil cp gs://${BUCKET_NAME}/performance-reports/[report-name].json ./
```

### Access Query Insights

1. Navigate to Cloud SQL in the Google Cloud Console
2. Select your database instance
3. Go to "Query Insights" tab
4. Review top queries, execution times, and recommendations

### Dashboard Access

1. Navigate to Cloud Monitoring in the Google Cloud Console
2. Go to "Dashboards"
3. Open "Cloud SQL Performance Monitoring Dashboard"
4. Review real-time performance metrics

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/db-monitoring-deployment

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud SQL instance
gcloud sql instances delete ${DB_INSTANCE_NAME} --quiet

# Delete Cloud Function
gcloud functions delete ${FUNCTION_NAME} --quiet

# Delete Pub/Sub topic
gcloud pubsub topics delete ${TOPIC_NAME} --quiet

# Delete Storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Delete alerting policies
gcloud alpha monitoring policies list \
    --filter="displayName:('Cloud SQL High CPU Usage' OR 'Cloud SQL Slow Query Detection')" \
    --format="value(name)" | \
    xargs -I {} gcloud alpha monitoring policies delete {} --quiet
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**
   ```bash
   # Enable required APIs
   gcloud services enable sqladmin.googleapis.com
   gcloud services enable monitoring.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles to your account
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/cloudsql.admin"
   ```

3. **Query Insights Not Showing Data**
   - Ensure the Cloud SQL instance has the Enterprise Plus edition
   - Wait 10-15 minutes for data collection to begin
   - Generate database activity to trigger insights collection

4. **Alerts Not Triggering**
   - Verify notification channels are properly configured
   - Check that the Cloud Function has appropriate permissions
   - Review alerting policy thresholds and conditions

### Debug Commands

```bash
# Check Cloud Function logs
gcloud functions logs read ${FUNCTION_NAME} --limit=50

# View Cloud SQL operation logs
gcloud sql operations list --instance=${DB_INSTANCE_NAME}

# Check Pub/Sub message flow
gcloud pubsub subscriptions pull ${TOPIC_NAME}-subscription --auto-ack --limit=5
```

## Cost Optimization

- **Cloud SQL Enterprise Plus**: Consider downgrading to Standard edition if advanced Query Insights features are not needed
- **Storage**: Enable storage auto-increase but set reasonable limits
- **Function Memory**: Optimize Cloud Function memory allocation based on actual usage
- **Retention**: Configure appropriate log and metrics retention periods

## Security Considerations

- All resources use least-privilege IAM roles
- Cloud SQL instance uses private IP when possible
- Encryption at rest and in transit enabled by default
- Service accounts have minimal required permissions
- Regular security updates recommended

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify IAM permissions and API enablement
4. Review Cloud Function logs for error details

## Additional Resources

- [Cloud SQL Enterprise Plus Features](https://cloud.google.com/sql/docs/postgres/enterprise-plus)
- [Query Insights Documentation](https://cloud.google.com/sql/docs/postgres/using-query-insights)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)
- [Cloud Functions Monitoring](https://cloud.google.com/functions/docs/monitoring)