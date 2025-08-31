# Infrastructure as Code for Personal Expense Tracker with App Engine and Cloud SQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Personal Expense Tracker with App Engine and Cloud SQL".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with error handling

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - App Engine Admin
  - Cloud SQL Admin
  - Service Account Admin
  - Project IAM Admin
- Python 3.9+ (for local development and testing)
- PostgreSQL client tools (for database verification)

## Architecture Overview

This infrastructure deploys:
- Google App Engine application (Python 3.9 runtime)
- Cloud SQL PostgreSQL instance (db-f1-micro tier)
- IAM service accounts and roles
- Database schema initialization
- Networking and security configurations

## Quick Start

### Using Infrastructure Manager

```bash
# Create and deploy infrastructure configuration
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/expense-tracker-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="variables.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/expense-tracker-deployment
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"
terraform plan

# Apply configuration
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud app describe
gcloud sql instances list
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `DB_TIER` | Cloud SQL instance tier | `db-f1-micro` | No |
| `APP_ENGINE_SERVICE` | App Engine service name | `default` | No |
| `DB_PASSWORD` | Database password | Auto-generated | No |

### Infrastructure Manager Variables

Edit `infrastructure-manager/variables.yaml`:

```yaml
project_id:
  value: "your-project-id"
region:
  value: "us-central1"
db_instance_tier:
  value: "db-f1-micro"
app_engine_location_id:
  value: "us-central"
```

### Terraform Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
db_instance_tier = "db-f1-micro"
db_disk_size_gb  = 10
app_max_instances = 2
```

## Post-Deployment Steps

### 1. Verify App Engine Deployment

```bash
# Check App Engine service status
gcloud app services list

# Get application URL
gcloud app browse

# Test application response
curl -I "https://$(gcloud app describe --format='value(defaultHostname)')"
```

### 2. Verify Cloud SQL Instance

```bash
# Check instance status
gcloud sql instances describe expense-tracker-db

# Test database connectivity
gcloud sql connect expense-tracker-db --user=postgres
```

### 3. Initialize Application Data

```bash
# Connect to database and verify schema
gcloud sql connect expense-tracker-db --user=postgres --database=expenses

# Run in SQL prompt:
# \dt
# SELECT COUNT(*) FROM expenses;
```

## Monitoring and Troubleshooting

### Application Logs

```bash
# View App Engine logs
gcloud app logs tail -s default

# View specific log entries
gcloud logging read "resource.type=gae_app AND resource.labels.module_id=default" --limit=50
```

### Database Monitoring

```bash
# Check database performance
gcloud sql operations list --instance=expense-tracker-db

# View database logs
gcloud logging read "resource.type=cloudsql_database" --limit=20
```

### Common Issues

1. **App Engine deployment fails**:
   ```bash
   # Check API enablement
   gcloud services list --enabled | grep appengine
   
   # Verify project has App Engine initialized
   gcloud app describe
   ```

2. **Database connection errors**:
   ```bash
   # Verify Cloud SQL instance is running
   gcloud sql instances describe expense-tracker-db --format="value(state)"
   
   # Check database user permissions
   gcloud sql users list --instance=expense-tracker-db
   ```

3. **Permission errors**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Check App Engine service account
   gcloud iam service-accounts describe ${PROJECT_ID}@appspot.gserviceaccount.com
   ```

## Cost Optimization

### Resource Sizing

- **App Engine**: F1 instance class for development (scales to 0)
- **Cloud SQL**: db-f1-micro instance for light workloads
- **Storage**: 10GB SSD disk with automatic backups

### Cost Monitoring

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Expense Tracker Budget" \
    --budget-amount=25USD \
    --threshold-rule=percent=0.8

# Monitor current spend
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID
```

## Security Considerations

### IAM Best Practices

- Service accounts use minimal required permissions
- Database access restricted to application service account
- Cloud SQL instance uses private IP when possible
- SSL/TLS encryption enabled for all connections

### Security Validation

```bash
# Verify SSL certificate
curl -vI "https://$(gcloud app describe --format='value(defaultHostname)')" 2>&1 | grep -i ssl

# Check database SSL enforcement
gcloud sql instances describe expense-tracker-db --format="value(settings.ipConfiguration.requireSsl)"

# Review IAM policies
gcloud projects get-iam-policy ${PROJECT_ID} --format="table(bindings.role,bindings.members)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/expense-tracker-deployment

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy

# Verify resources are deleted
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification
gcloud app services list
gcloud sql instances list
```

### Manual Cleanup (if needed)

```bash
# Delete App Engine versions (cannot delete default service)
gcloud app versions list
gcloud app versions delete VERSION_ID --service=default

# Delete Cloud SQL instance
gcloud sql instances delete expense-tracker-db

# Delete service accounts
gcloud iam service-accounts delete expense-tracker-sa@${PROJECT_ID}.iam.gserviceaccount.com
```

## Customization

### Adding Authentication

Extend the infrastructure to include Google Identity Platform:

```hcl
# Add to terraform/main.tf
resource "google_identity_platform_config" "default" {
  provider = google-beta
  project  = var.project_id
  
  sign_in {
    allow_duplicate_emails = false
    email {
      enabled           = true
      password_required = true
    }
  }
}
```

### Multi-Environment Support

Create environment-specific variable files:

```bash
# terraform/environments/dev.tfvars
project_id = "expense-tracker-dev"
db_instance_tier = "db-f1-micro"
app_max_instances = 1

# terraform/environments/prod.tfvars
project_id = "expense-tracker-prod"
db_instance_tier = "db-n1-standard-1"
app_max_instances = 5
```

### Adding Monitoring

Extend with Cloud Monitoring:

```hcl
resource "google_monitoring_alert_policy" "app_engine_error_rate" {
  display_name = "App Engine Error Rate"
  project      = var.project_id
  
  conditions {
    display_name = "App Engine error rate"
    condition_threshold {
      filter          = "resource.type=\"gae_app\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1
    }
  }
}
```

## Development Workflow

### Local Development

```bash
# Set up local environment
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
export DB_HOST="127.0.0.1"
export DB_USER="expense_user"
export DB_PASSWORD="your-password"
export DB_NAME="expenses"

# Start Cloud SQL Proxy
cloud_sql_proxy -instances=${PROJECT_ID}:${REGION}:expense-tracker-db=tcp:5432

# Run application locally
cd ../app/
python main.py
```

### Testing Infrastructure Changes

```bash
# Validate Terraform configuration
cd terraform/
terraform validate
terraform plan -detailed-exitcode

# Test Infrastructure Manager deployment
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/test-deployment \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="test-variables.yaml" \
    --preview
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe at `../expense-tracker-app-engine-sql.md`
2. **Google Cloud Documentation**: 
   - [App Engine](https://cloud.google.com/appengine/docs)
   - [Cloud SQL](https://cloud.google.com/sql/docs)
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Google Provider**: [Registry Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

## Version History

- **v1.0**: Initial implementation with App Engine and Cloud SQL
- **v1.1**: Added comprehensive monitoring and security configurations
- **Current**: Enhanced documentation and troubleshooting guides