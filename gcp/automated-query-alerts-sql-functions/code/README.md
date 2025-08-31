# Infrastructure as Code for Automated Query Performance Alerts with Cloud SQL and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automated Query Performance Alerts with Cloud SQL and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 450.0.0 or later)
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Cloud SQL Admin
  - Cloud Functions Developer
  - Monitoring Admin
  - Security Admin
  - Service Usage Admin
- Terraform CLI (version 1.0 or later) for Terraform implementation
- Basic understanding of SQL databases and query performance concepts
- Estimated cost: $20-30 for Cloud SQL Enterprise instance + minimal charges for Cloud Functions and monitoring

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Enable required APIs
gcloud services enable config.googleapis.com

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/sql-alerts-deployment \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo=REPO_URL \
    --git-source-directory=gcp/automated-query-alerts-sql-functions/code/infrastructure-manager \
    --input-values=project_id=PROJECT_ID,region=REGION
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud sql instances list
gcloud functions list --gen2
gcloud alpha monitoring policies list
```

## Architecture Overview

This infrastructure deploys:

1. **Cloud SQL PostgreSQL Instance** with Query Insights enabled (Enterprise edition)
2. **Cloud Functions** (2nd generation) for intelligent alert processing
3. **Cloud Monitoring Alert Policy** for query performance thresholds
4. **Notification Channel** with webhook integration
5. **Sample Database Schema** with test data for validation
6. **IAM Roles and Permissions** following least privilege principle

## Configuration Options

### Infrastructure Manager Variables

```yaml
# Required variables
project_id: "your-gcp-project-id"
region: "us-central1"

# Optional customization
instance_tier: "db-custom-2-7680"
database_version: "POSTGRES_15"
storage_size: "20GB"
alert_threshold_seconds: 5.0
function_memory: "256MB"
function_timeout: "60s"
```

### Terraform Variables

```hcl
# terraform.tfvars example
project_id = "your-gcp-project-id"
region = "us-central1"
zone = "us-central1-a"

# Optional customization
instance_name_suffix = "prod"
database_tier = "db-custom-2-7680"
postgres_version = "POSTGRES_15"
storage_size_gb = 20
query_threshold_seconds = 5.0
alert_auto_close_duration = "1800s"
enable_query_insights = true
```

### Bash Script Environment Variables

```bash
# Required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export INSTANCE_TIER="db-custom-2-7680"
export DATABASE_VERSION="POSTGRES_15"
export STORAGE_SIZE="20GB"
export ALERT_THRESHOLD="5.0"
export FUNCTION_MEMORY="256MB"
export FUNCTION_TIMEOUT="60s"
```

## Validation & Testing

After deployment, verify the infrastructure:

```bash
# Check Cloud SQL instance status
gcloud sql instances describe [INSTANCE_NAME] \
    --format="table(name,state,settings.insightsConfig)"

# Verify Cloud Function deployment
gcloud functions describe [FUNCTION_NAME] \
    --gen2 \
    --region=[REGION]

# Test alert policy configuration
gcloud alpha monitoring policies list \
    --filter="displayName:[POLICY_NAME]"

# Access monitoring dashboards
echo "Query Insights: https://console.cloud.google.com/sql/instances/[INSTANCE_NAME]/insights"
echo "Monitoring: https://console.cloud.google.com/monitoring/alerting/policies"
```

## Testing the Alert System

1. **Connect to Cloud SQL instance**:
   ```bash
   gcloud sql connect [INSTANCE_NAME] --user=postgres --database=performance_test
   ```

2. **Execute slow test queries**:
   ```sql
   -- Cartesian join to trigger performance alert
   SELECT COUNT(*) FROM users u, orders o 
   WHERE u.id > 1000 AND o.amount > 100;
   
   -- Execute the slow function
   SELECT * FROM slow_query_test();
   ```

3. **Monitor alert processing**:
   ```bash
   # Watch Cloud Functions logs
   gcloud functions logs read [FUNCTION_NAME] \
       --gen2 \
       --region=[REGION] \
       --follow
   ```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/sql-alerts-deployment
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud sql instances list
gcloud functions list --gen2
gcloud alpha monitoring policies list
```

## Security Considerations

- **IAM Permissions**: All resources use least privilege principle
- **Database Security**: Cloud SQL uses private IP with authorized networks
- **Function Security**: Cloud Functions use service accounts with minimal permissions
- **Encryption**: All data encrypted at rest and in transit using Google-managed keys
- **Monitoring**: All operations logged to Cloud Logging for audit trails

## Cost Optimization

- **Cloud SQL**: Uses db-custom machine type for optimal performance/cost ratio
- **Storage**: Configured with automatic storage increase to prevent over-provisioning
- **Functions**: Uses minimum memory allocation with appropriate timeout
- **Monitoring**: Alert policies configured with auto-close to prevent alert fatigue

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   gcloud services enable sqladmin.googleapis.com cloudfunctions.googleapis.com monitoring.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="user:EMAIL" \
       --role="roles/cloudsql.admin"
   ```

3. **Cloud Function Deployment Fails**:
   ```bash
   # Check Cloud Build logs
   gcloud builds log --region=REGION
   ```

4. **Query Insights Not Collecting Data**:
   ```bash
   # Verify Query Insights is enabled
   gcloud sql instances describe INSTANCE_NAME \
       --format="value(settings.insightsConfig.queryInsightsEnabled)"
   ```

### Monitoring and Logs

- **Cloud SQL Logs**: `gcloud sql operations list --instance=INSTANCE_NAME`
- **Function Logs**: `gcloud functions logs read FUNCTION_NAME --gen2 --region=REGION`
- **Monitoring Alerts**: Cloud Console > Monitoring > Alerting

## Customization

### Extending Alert Logic

Modify the Cloud Function code to:
- Add custom notification channels (Slack, PagerDuty, email)
- Implement automated remediation actions
- Integrate with ticketing systems
- Add cost-based alerting thresholds

### Additional Monitoring

Enhance monitoring by adding:
- Connection pool monitoring
- Database lock detection
- Storage utilization alerts
- Backup failure notifications

### Multi-Instance Monitoring

Scale to monitor multiple instances:
- Use Cloud Monitoring workspaces
- Implement centralized alert routing
- Add cross-project monitoring capabilities
- Include geographic failover monitoring

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe in `automated-query-alerts-sql-functions.md`
2. **Google Cloud Documentation**: 
   - [Cloud SQL Query Insights](https://cloud.google.com/sql/docs/postgres/using-query-insights)
   - [Cloud Functions](https://cloud.google.com/functions/docs)
   - [Cloud Monitoring](https://cloud.google.com/monitoring/docs)
3. **Terraform Google Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Infrastructure Manager**: [Google Cloud Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Version Compatibility

- **Google Cloud CLI**: 450.0.0+
- **Terraform**: 1.0+
- **Google Provider**: 5.0+
- **Infrastructure Manager**: Latest
- **Cloud SQL**: PostgreSQL 15
- **Cloud Functions**: 2nd generation runtime

## Related Resources

- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/postgres/best-practices)
- [Query Performance Optimization](https://cloud.google.com/sql/docs/postgres/optimize-performance)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)
- [Serverless Best Practices](https://cloud.google.com/functions/docs/bestpractices)