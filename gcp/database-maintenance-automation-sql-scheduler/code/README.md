# Infrastructure as Code for Database Maintenance Automation with Cloud SQL and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Maintenance Automation with Cloud SQL and Cloud Scheduler".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for step-by-step execution

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud SQL Admin API
  - Cloud Functions API
  - Cloud Scheduler API
  - Cloud Monitoring API
  - Cloud Logging API
  - Cloud Storage API
- IAM permissions for:
  - Cloud SQL Admin
  - Cloud Functions Developer
  - Cloud Scheduler Admin
  - Storage Admin
  - Monitoring Admin
- Estimated cost: $15-30/month for Cloud SQL db-f1-micro instance and associated serverless resources

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure at scale with built-in state management and team collaboration features.

```bash
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export DEPLOYMENT_NAME="db-maintenance-$(openssl rand -hex 3)"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/[SERVICE_ACCOUNT_EMAIL]" \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive module ecosystem for flexible infrastructure management.

```bash
cd terraform/

# Initialize Terraform and download providers
terraform init

# Review planned infrastructure changes
terraform plan \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Apply infrastructure configuration
terraform apply \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# View outputs for verification
terraform output
```

### Using Bash Scripts

Bash scripts provide direct cloud CLI execution following the original recipe steps with enhanced automation.

```bash
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure step-by-step
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create storage bucket with lifecycle policies
# 3. Deploy Cloud SQL instance with optimization settings
# 4. Create and deploy Cloud Function for maintenance
# 5. Configure Cloud Scheduler jobs
# 6. Set up monitoring and alerting policies
# 7. Create performance dashboard
```

## Architecture Overview

The infrastructure deploys:

- **Cloud SQL MySQL 8.0 instance** with automated backups and monitoring
- **Cloud Storage bucket** for maintenance logs with lifecycle management
- **Cloud Function** for automated maintenance operations
- **Cloud Scheduler jobs** for precise timing control
- **Cloud Monitoring policies** for proactive alerting
- **Performance dashboard** for operational visibility

## Configuration Options

### Infrastructure Manager Variables

Edit `terraform.tfvars` to customize the deployment:

```hcl
project_id = "your-project-id"
region = "us-central1"
db_tier = "db-f1-micro"
maintenance_schedule = "0 2 * * *"
monitoring_schedule = "0 */6 * * *"
```

### Terraform Variables

Customize deployment through variables:

```bash
# Required variables
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Optional customizations
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="db_tier=db-f1-micro" \
    -var="db_name=maintenance_app" \
    -var="function_memory=256" \
    -var="function_timeout=540" \
    -var="maintenance_timezone=America/New_York"
```

### Bash Script Configuration

Modify environment variables at the top of `deploy.sh`:

```bash
export REGION="us-central1"
export DB_TIER="db-f1-micro"
export FUNCTION_MEMORY="256MB"
export FUNCTION_TIMEOUT="540s"
export MAINTENANCE_SCHEDULE="0 2 * * *"
export MONITORING_SCHEDULE="0 */6 * * *"
```

## Verification and Testing

After deployment, verify the infrastructure:

### Check Cloud SQL Instance

```bash
# Verify instance is running
gcloud sql instances list

# Check database configuration
gcloud sql instances describe [INSTANCE_NAME]
```

### Test Cloud Function

```bash
# List deployed functions
gcloud functions list

# Test function execution
gcloud functions call [FUNCTION_NAME] --region=[REGION]
```

### Verify Scheduler Jobs

```bash
# List scheduler jobs
gcloud scheduler jobs list --location=[REGION]

# Manually trigger maintenance job
gcloud scheduler jobs run [JOB_NAME] --location=[REGION]
```

### Check Monitoring Setup

```bash
# List alerting policies
gcloud alpha monitoring policies list

# View dashboards
gcloud monitoring dashboards list
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment and all resources
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Scheduler jobs
# 2. Remove Cloud Function
# 3. Delete monitoring policies and dashboards
# 4. Remove Cloud SQL instance
# 5. Delete storage bucket and contents
# 6. Clean environment variables
```

## Cost Optimization

To minimize costs during testing:

1. **Use smaller instance sizes**: Change `db_tier` to `db-f1-micro` for testing
2. **Limit function memory**: Use 256MB memory allocation for Cloud Functions
3. **Enable storage lifecycle**: Automatically transition logs to cheaper storage classes
4. **Clean up promptly**: Run cleanup scripts after testing to avoid ongoing charges

## Security Considerations

The infrastructure implements several security best practices:

- **IAM least privilege**: Service accounts with minimal required permissions
- **Network security**: Private IP configuration for Cloud SQL
- **Encryption**: Data encrypted at rest and in transit
- **Audit logging**: Comprehensive logging for compliance
- **Secret management**: Secure handling of database credentials

## Monitoring and Alerting

The solution includes:

- **CPU utilization alerts**: Notification when database CPU exceeds 80%
- **Connection monitoring**: Alerts for high connection counts
- **Performance dashboard**: Visual monitoring of key metrics
- **Maintenance logs**: Detailed audit trail in Cloud Storage
- **Function execution monitoring**: Serverless operation tracking

## Troubleshooting

### Common Issues

1. **API not enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient permissions**: Verify IAM roles are correctly assigned
3. **Resource quotas**: Check project quotas for Cloud SQL and Cloud Functions
4. **Function timeout**: Adjust timeout settings for complex maintenance operations
5. **Network connectivity**: Verify Cloud SQL proxy configuration for function connectivity

### Debug Commands

```bash
# Check API status
gcloud services list --enabled

# View function logs
gcloud functions logs read [FUNCTION_NAME] --region=[REGION]

# Check scheduler job execution
gcloud logging read "resource.type=cloud_scheduler_job" --limit=10

# Monitor SQL instance performance
gcloud sql operations list --instance=[INSTANCE_NAME]
```

## Customization

### Adding Custom Maintenance Tasks

Modify the Cloud Function source code to include additional maintenance operations:

1. **Index optimization**: Add custom index analysis and recommendations
2. **Query performance tuning**: Implement automated query optimization
3. **Backup verification**: Add automated backup integrity checks
4. **Security audits**: Include database security compliance checking

### Scaling for Multiple Environments

Extend the infrastructure for multi-environment support:

1. **Environment-specific configurations**: Use Terraform workspaces or separate variable files
2. **Cross-project deployment**: Configure service account impersonation
3. **Centralized monitoring**: Aggregate metrics across multiple database instances
4. **Disaster recovery**: Implement cross-region backup and failover procedures

## Support

For issues with this infrastructure code:

1. **Recipe documentation**: Refer to the original recipe for detailed explanations
2. **Google Cloud documentation**: Consult official service documentation
3. **Terraform provider docs**: Reference the Google Cloud Terraform provider documentation
4. **Community support**: Use Google Cloud Community forums for additional help

## Related Resources

- [Cloud SQL Best Practices](https://cloud.google.com/sql/docs/best-practices)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Scheduler Guide](https://cloud.google.com/scheduler/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)