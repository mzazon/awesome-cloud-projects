# Infrastructure as Code for Database Disaster Recovery with Backup and DR Service and Cloud SQL

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Disaster Recovery with Backup and DR Service and Cloud SQL".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud SQL Admin
  - Backup and DR Service Admin
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Cloud Monitoring Admin
  - Pub/Sub Admin
  - IAM Admin
- Estimated cost: $200-400/month for the deployed resources

## Quick Start

### Using Infrastructure Manager

```bash
# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export DEPLOYMENT_NAME="disaster-recovery-deployment"

# Deploy the infrastructure
gcloud infra-manager deployments create ${DEPLOYMENT_NAME} \
    --location=us-central1 \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://github.com/your-org/your-repo.git" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --inputs-file="infrastructure-manager/terraform.tfvars"

# Monitor deployment status
gcloud infra-manager deployments describe ${DEPLOYMENT_NAME} \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var-file="terraform.tfvars.example"

# Apply the infrastructure
terraform apply -var-file="terraform.tfvars.example"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Verify deployment (optional)
./scripts/validate.sh
```

## Configuration

### Required Variables

All implementations require the following variables to be configured:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `primary_region` | Primary region for resources | `us-central1` | Yes |
| `secondary_region` | Secondary region for DR | `us-east1` | Yes |
| `db_tier` | Cloud SQL instance tier | `db-custom-2-8192` | No |
| `backup_retention_days` | Backup retention period | `30` | No |
| `environment` | Environment name (dev/staging/prod) | `prod` | No |

### Terraform Variables

Copy `terraform.tfvars.example` to `terraform.tfvars` and customize:

```hcl
project_id = "your-project-id"
primary_region = "us-central1"
secondary_region = "us-east1"
db_tier = "db-custom-2-8192"
backup_retention_days = 30
environment = "prod"
```

### Infrastructure Manager Configuration

Edit `infrastructure-manager/terraform.tfvars` with your specific values:

```hcl
project_id = "your-project-id"
primary_region = "us-central1"
secondary_region = "us-east1"
```

## Deployment Details

### Infrastructure Components

This IaC deployment creates:

1. **Primary Database Infrastructure**:
   - Cloud SQL PostgreSQL instance with high availability
   - Regional persistent disks for storage
   - VPC network and firewall rules

2. **Disaster Recovery Infrastructure**:
   - Cross-region read replica in secondary region
   - Failover replica configuration
   - Automated backup schedules

3. **Backup and DR Service**:
   - Backup vaults in both regions
   - Backup plans with automated scheduling
   - Cross-region backup replication

4. **Orchestration Layer**:
   - Cloud Functions for DR automation
   - Cloud Scheduler for automated testing
   - Pub/Sub topics for event handling

5. **Monitoring and Alerting**:
   - Cloud Monitoring alert policies
   - Health check endpoints
   - Logging configuration

### Network Security

- Private IP configurations for database instances
- VPC firewall rules for secure access
- IAM roles with least privilege access
- Encryption at rest and in transit

### Automation Features

- Automated daily backups
- Weekly disaster recovery testing
- Health monitoring and alerting
- Automated failover capabilities

## Validation

After deployment, validate the infrastructure:

### Using Terraform

```bash
cd terraform/
terraform output primary_instance_name
terraform output dr_replica_name
terraform output backup_vault_primary
terraform output function_urls
```

### Using gcloud CLI

```bash
# Verify Cloud SQL instances
gcloud sql instances list

# Check backup vaults
gcloud backup-dr backup-vaults list --location=us-central1
gcloud backup-dr backup-vaults list --location=us-east1

# Test Cloud Functions
gcloud functions list --region=us-central1

# Verify monitoring setup
gcloud alpha monitoring policies list
```

### Test Disaster Recovery

```bash
# Run DR validation function
FUNCTION_URL=$(gcloud functions describe validate-backups \
    --region=us-central1 \
    --format="value(serviceConfig.uri)")

curl -X POST "${FUNCTION_URL}" \
    -H "Authorization: bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete ${DEPLOYMENT_NAME} \
    --location=us-central1 \
    --delete-policy=DELETE

# Verify cleanup
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **API Enablement**: Ensure all required APIs are enabled:
   ```bash
   gcloud services enable sqladmin.googleapis.com
   gcloud services enable backupdr.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   ```

2. **IAM Permissions**: Verify service account has required permissions:
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **Resource Quotas**: Check regional quotas for Cloud SQL and compute resources:
   ```bash
   gcloud compute project-info describe --project=$PROJECT_ID
   ```

### Debugging Deployment

1. **Terraform Debug Mode**:
   ```bash
   export TF_LOG=DEBUG
   terraform apply
   ```

2. **Infrastructure Manager Logs**:
   ```bash
   gcloud infra-manager deployments describe ${DEPLOYMENT_NAME} \
       --location=us-central1 \
       --format="yaml"
   ```

3. **Function Logs**:
   ```bash
   gcloud functions logs read orchestrate-disaster-recovery \
       --region=us-central1
   ```

## Cost Optimization

### Resource Sizing

- **Development**: Use `db-f1-micro` tier for testing
- **Production**: Scale to `db-custom-4-16384` for high-traffic applications
- **Backup Storage**: Configure appropriate retention periods

### Scheduling

- **Backup Frequency**: Adjust based on RPO requirements
- **DR Testing**: Schedule during off-peak hours
- **Resource Scaling**: Use Cloud SQL automatic scaling features

## Security Considerations

### Data Protection

- All databases use encryption at rest
- Backup vaults provide immutable storage
- Network traffic encrypted in transit
- Private IP configurations minimize exposure

### Access Control

- IAM roles follow least privilege principle
- Service accounts with minimal required permissions
- API keys and secrets stored in Secret Manager
- Audit logging enabled for all operations

### Compliance

- Backup retention meets regulatory requirements
- Cross-region replication for data residency
- Automated compliance reporting through monitoring
- Disaster recovery testing documentation

## Monitoring and Alerting

### Key Metrics

- Database availability and performance
- Backup success rates and timing
- Replication lag between regions
- Function execution success rates

### Alert Policies

- Primary database health status
- Backup failure notifications
- DR replica synchronization issues
- Function execution errors

### Dashboards

Access monitoring dashboards in Google Cloud Console:
- Cloud SQL monitoring
- Backup and DR Service status
- Cloud Functions performance
- Overall system health

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Status page for service issues
3. Consult Google Cloud documentation for each service
4. Review deployment logs for specific error messages

## References

- [Google Cloud SQL Disaster Recovery](https://cloud.google.com/sql/docs/mysql/intro-to-cloud-sql-disaster-recovery)
- [Backup and DR Service Documentation](https://cloud.google.com/backup-disaster-recovery/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)