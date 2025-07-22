# Cross-Database Analytics Federation with AlloyDB Omni and BigQuery - Terraform Infrastructure

This Terraform configuration deploys a complete federated analytics platform that combines AlloyDB Omni (simulated with Cloud SQL PostgreSQL) with BigQuery for real-time cross-database analytics without data movement.

## Architecture Overview

The infrastructure creates:

- **AlloyDB Omni Simulation**: Cloud SQL PostgreSQL instance for transactional data
- **BigQuery Data Warehouse**: Cloud-native analytics with federated query capabilities  
- **Dataplex Universal Catalog**: Unified data governance across hybrid environment
- **Cloud Functions**: Serverless orchestration and metadata synchronization
- **Cloud Storage**: Data lake foundation with organized structure
- **BigQuery Federation**: External connections for real-time cross-database queries

## Prerequisites

### Required Tools
- [Terraform](https://www.terraform.io/downloads.html) >= 1.5
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) configured with appropriate permissions
- A Google Cloud Project with billing enabled

### Required Permissions
Your user account or service account needs these IAM roles:
- `roles/bigquery.admin`
- `roles/cloudsql.admin` 
- `roles/dataplex.admin`
- `roles/cloudfunctions.admin`
- `roles/storage.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/resourcemanager.projectIamAdmin`
- `roles/serviceusage.serviceUsageAdmin`

### Cost Estimation
Expected monthly costs (varies by usage):
- Cloud SQL PostgreSQL: ~$50-100
- BigQuery: ~$5-20 (query and storage)
- Cloud Storage: ~$1-5
- Cloud Functions: ~$0-5
- Dataplex: ~$10-30
- **Total: ~$66-160/month**

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd gcp/cross-database-analytics-federation-alloydb-omni-bigquery/code/terraform/
```

### 2. Configure Variables
```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your settings
vim terraform.tfvars
```

Required variables to set:
```hcl
project_id  = "your-gcp-project-id"
db_password = "your-secure-database-password"
```

### 3. Initialize and Deploy
```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Verify Deployment
```bash
# Check outputs for connection information
terraform output

# Test BigQuery federation connection
terraform output sample_federated_query
```

## Configuration Options

### Core Configuration
```hcl
# Basic settings
project_id  = "analytics-federation-demo"
region      = "us-central1"
zone        = "us-central1-a"
environment = "dev"

# Database password (store securely)
db_password = "SecurePassword123!"
```

### Performance Tuning
```hcl
# Cloud SQL instance sizing
alloydb_tier      = "db-custom-4-16384"  # 4 vCPUs, 16GB RAM
alloydb_disk_size = 50                   # GB
alloydb_disk_type = "PD_SSD"

# Database performance flags
database_flags = {
  max_connections           = "300"
  effective_cache_size      = "12GB"
  shared_buffers           = "4GB"
  work_mem                 = "32MB"
}
```

### Security Configuration
```hcl
# Network access control
authorized_networks = [
  {
    name  = "office-network"
    value = "203.0.113.0/24"
  },
  {
    name  = "vpn-gateway"
    value = "10.0.0.0/8"
  }
]

# Enable production protections
deletion_protection = true
enable_high_availability = true
```

### Automation Settings
```hcl
# Metadata sync frequency
metadata_sync_schedule = "0 */4 * * *"  # Every 4 hours

# Cloud Function resources
cloud_function_memory  = 512  # MB
cloud_function_timeout = 120  # seconds
```

## Post-Deployment Setup

### 1. Create Sample Data
```bash
# Connect to Cloud SQL instance
gcloud sql connect $(terraform output -raw alloydb_instance_name) \
  --user=postgres --database=transactions

# Create sample tables and data (see recipe for SQL commands)
```

### 2. Test Federation
```bash
# Execute sample federated query in BigQuery
bq query --use_legacy_sql=false "$(terraform output -raw sample_federated_query)"

# View customer lifetime value analysis
bq query --use_legacy_sql=false \
  "SELECT * FROM \`$(terraform output -raw customer_lifetime_value_view_id)\` LIMIT 10"
```

### 3. Monitor Resources
```bash
# Check Cloud Function logs
gcloud functions logs read federation-metadata-sync \
  --region=$(terraform output -raw region)

# View Dataplex assets
gcloud dataplex assets list \
  --location=$(terraform output -raw region) \
  --lake=$(terraform output -raw dataplex_lake_name)
```

## Management and Operations

### Updating the Infrastructure
```bash
# Update variables in terraform.tfvars
# Then apply changes
terraform plan
terraform apply
```

### Backup and State Management
```bash
# Enable remote state storage (recommended for production)
# Uncomment backend configuration in versions.tf

# Create state bucket
gsutil mb gs://your-terraform-state-bucket

# Initialize with backend
terraform init -backend-config="bucket=your-terraform-state-bucket"
```

### Monitoring and Alerting
```bash
# View BigQuery query history
bq ls -j --max_results=10

# Check Cloud SQL performance
gcloud sql operations list --instance=$(terraform output -raw alloydb_instance_name)

# Monitor Cloud Function execution
gcloud functions logs read federation-metadata-sync --limit=50
```

## Troubleshooting

### Common Issues

**Federation Connection Fails**
```bash
# Check connection status
bq show --connection --location=$(terraform output -raw region) \
  $(terraform output -raw project_id).$(terraform output -raw region).$(terraform output -raw bigquery_connection_id)

# Test basic connectivity
gcloud sql connect $(terraform output -raw alloydb_instance_name) --user=postgres
```

**Cloud Function Errors**
```bash
# View detailed logs
gcloud functions logs read federation-metadata-sync \
  --region=$(terraform output -raw region) --limit=100

# Test function manually
curl -X POST -H "Content-Type: application/json" \
  -d '{"project_id":"'$(terraform output -raw project_id)'","connection_id":"'$(terraform output -raw bigquery_connection_id)'"}' \
  $(terraform output -raw cloud_function_url)
```

**Permission Issues**
```bash
# Check service account permissions
gcloud projects get-iam-policy $(terraform output -raw project_id) \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(terraform output -raw service_account_email)"
```

### Resource Cleanup
```bash
# Destroy all resources
terraform destroy

# Verify cleanup
gcloud sql instances list
gcloud functions list
bq ls
gsutil ls
```

## Advanced Configuration

### Multi-Environment Setup
```bash
# Use workspaces for multiple environments
terraform workspace new staging
terraform workspace new production

# Deploy to specific environment
terraform workspace select staging
terraform apply -var-file="staging.tfvars"
```

### Custom Function Code
```bash
# Modify function code in function_code/
# Update requirements.txt if adding dependencies
# Apply changes
terraform apply
```

### Integration with CI/CD
```yaml
# Example GitHub Actions workflow
name: Deploy Analytics Federation
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - uses: hashicorp/setup-terraform@v1
    - run: terraform init
    - run: terraform plan
    - run: terraform apply -auto-approve
```

## Security Best Practices

1. **Network Security**: Restrict `authorized_networks` to specific IP ranges
2. **Secrets Management**: Use Google Secret Manager for sensitive values
3. **IAM**: Follow principle of least privilege for service accounts
4. **Monitoring**: Enable audit logging and set up alerting
5. **Encryption**: Ensure encryption at rest and in transit (enabled by default)

## Support and Maintenance

- Monitor resource costs in Google Cloud Console
- Regularly update Terraform provider versions
- Review and rotate database passwords
- Monitor federation query performance
- Keep Cloud Function dependencies updated

For detailed implementation guidance, refer to the original recipe documentation.