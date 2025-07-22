# Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner - Terraform Implementation

This Terraform configuration deploys a comprehensive disaster recovery solution that combines AlloyDB for PostgreSQL workloads and Cloud Spanner for globally distributed data, with automated backup orchestration and cross-region failover capabilities.

## 🏗️ Architecture Overview

The infrastructure creates a multi-layered disaster recovery strategy across two Google Cloud regions:

- **AlloyDB**: Primary cluster with continuous backup, secondary cluster with read replicas
- **Cloud Spanner**: Multi-regional instance with automatic global distribution
- **Cloud Storage**: Cross-region backup storage with lifecycle management
- **Cloud Functions**: Serverless orchestration for backup operations (code separate)
- **Cloud Scheduler**: Automated backup scheduling (requires function deployment)
- **Pub/Sub**: Event-driven data synchronization messaging
- **Monitoring**: Comprehensive observability and alerting

## 📋 Prerequisites

### Required Software
- [Terraform](https://www.terraform.io/downloads.html) >= 1.6.0
- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) >= 400.0.0
- [Git](https://git-scm.com/) for version control

### Google Cloud Setup
1. **Project Setup**:
   ```bash
   # Create a new project (optional)
   gcloud projects create your-project-id
   
   # Set the active project
   gcloud config set project your-project-id
   
   # Enable billing on the project
   gcloud billing projects link your-project-id --billing-account=BILLING_ACCOUNT_ID
   ```

2. **Authentication**:
   ```bash
   # Authenticate with Google Cloud
   gcloud auth login
   
   # Set up application default credentials
   gcloud auth application-default login
   ```

3. **Required IAM Permissions**:
   Your account needs the following roles:
   - `roles/alloydb.admin` - AlloyDB Admin
   - `roles/spanner.admin` - Cloud Spanner Admin
   - `roles/storage.admin` - Storage Admin
   - `roles/cloudfunctions.developer` - Cloud Functions Developer
   - `roles/cloudscheduler.admin` - Cloud Scheduler Admin
   - `roles/pubsub.admin` - Pub/Sub Admin
   - `roles/compute.networkAdmin` - Compute Network Admin
   - `roles/iam.serviceAccountAdmin` - Service Account Admin
   - `roles/monitoring.admin` - Monitoring Admin

### Cost Considerations
- **Estimated Monthly Cost**: $1,280-2,550 USD
- **AlloyDB**: $400-800/month for primary cluster
- **Cloud Spanner**: $600-1,200/month for multi-regional instance
- **Storage**: $50-200/month for backup buckets
- **Networking**: $20-100/month for cross-region traffic

> ⚠️ **Important**: This creates production-grade infrastructure with associated costs. Review the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for accurate estimates.

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <repository-url>
cd gcp/multi-database-disaster-recovery-alloydb-spanner/code/terraform

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your specific configuration:

```hcl
# Basic Configuration
project_id       = "your-project-id"
environment      = "production"
primary_region   = "us-central1"
secondary_region = "us-east1"

# Database Configuration
db_admin_password = "your-secure-password-here"
cluster_name     = "alloydb-dr"

# Spanner Configuration
spanner_processing_units = 2000
spanner_config          = "nam-eur-asia1"

# Storage Configuration
backup_bucket_prefix = "dr-backup"

# Monitoring Configuration
enable_monitoring = true

# Labels for resource organization
labels = {
  team        = "data-platform"
  cost_center = "engineering"
  compliance  = "required"
}
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan
```

### 4. Verify Deployment

```bash
# Check AlloyDB clusters
gcloud alloydb clusters list --regions=us-central1,us-east1

# Check Cloud Spanner instance
gcloud spanner instances list

# Check storage buckets
gsutil ls -p your-project-id

# Check Pub/Sub topics
gcloud pubsub topics list
```

## 📁 File Structure

```
terraform/
├── main.tf           # Main infrastructure resources
├── variables.tf      # Input variable definitions
├── outputs.tf        # Output value definitions
├── versions.tf       # Provider and version constraints
├── README.md         # This documentation
├── terraform.tfvars.example  # Example variable values
└── .gitignore        # Git ignore patterns
```

## 🔧 Configuration Reference

### Required Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `project_id` | string | Google Cloud Project ID | `"my-project-123"` |
| `db_admin_password` | string | AlloyDB admin password | `"secure-password"` |

### Important Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `primary_region` | `"us-central1"` | Primary deployment region |
| `secondary_region` | `"us-east1"` | Disaster recovery region |
| `spanner_processing_units` | `2000` | Spanner capacity |
| `alloydb_cpu_count` | `4` | AlloyDB instance CPUs |
| `backup_retention_days` | `30` | Backup retention period |
| `enable_monitoring` | `true` | Enable monitoring/alerting |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `primary_subnet_cidr` | `"10.0.0.0/24"` | Primary subnet CIDR |
| `secondary_subnet_cidr` | `"10.1.0.0/24"` | Secondary subnet CIDR |

## 🔍 Key Outputs

After deployment, important outputs include:

- **Connection Information**: Database endpoints and credentials
- **Resource IDs**: For automation and management scripts
- **Validation Commands**: Commands to verify deployment
- **Monitoring URLs**: Links to dashboards and metrics

Access outputs with:
```bash
terraform output
terraform output -json > outputs.json
```

## 🔒 Security Considerations

### Implemented Security Features
- ✅ Private IP addresses for AlloyDB instances
- ✅ VPC network isolation
- ✅ Uniform bucket-level access on storage
- ✅ Service account with least-privilege IAM
- ✅ Deletion protection on critical resources
- ✅ Encrypted storage and transit

### Additional Recommendations
1. **Enable VPC Service Controls** for network perimeter security
2. **Use Customer-Managed Encryption Keys (CMEK)** for enhanced control
3. **Implement Cloud Armor** for DDoS protection
4. **Set up Cloud Security Command Center** for security insights
5. **Regular security scans** with Cloud Security Scanner

### Password Management
```bash
# Generate secure password
openssl rand -base64 32

# Store in Secret Manager (recommended)
gcloud secrets create alloydb-admin-password --data-file=-

# Reference in Terraform
data "google_secret_manager_secret_version" "db_password" {
  secret = "alloydb-admin-password"
}
```

## 📊 Monitoring and Alerting

### Included Monitoring
- AlloyDB cluster health and performance metrics
- Cloud Spanner instance utilization and latency
- Storage bucket usage and access patterns
- Network connectivity and throughput
- Backup job success/failure rates

### Setting Up Dashboards
```bash
# Create monitoring dashboard (after deployment)
gcloud monitoring dashboards create \
    --config-from-file=dashboard-config.json

# List existing dashboards
gcloud monitoring dashboards list
```

### Alerting Policies
Configure alerts for:
- Database instance failures
- Backup job failures
- High CPU/memory utilization
- Network connectivity issues
- Storage quota approaching limits

## 🔄 Disaster Recovery Procedures

### Backup Verification
```bash
# List AlloyDB backups
gcloud alloydb backups list --region=us-central1

# Verify Spanner backups
gcloud spanner backup-schedules list \
    --instance=INSTANCE_ID \
    --database=critical-data
```

### Failover Testing
1. **Planned Failover Testing**:
   - Test read replica promotion
   - Verify application connectivity
   - Validate data consistency

2. **Cross-Region Backup Testing**:
   - Restore from secondary region
   - Verify data integrity
   - Test application failover

### Recovery Procedures
Detailed runbooks should include:
- RTO/RPO targets (configured via variables)
- Failover decision criteria
- Step-by-step recovery procedures
- Communication protocols
- Validation checklists

## 🛠️ Maintenance and Updates

### Regular Maintenance Tasks
1. **Review backup schedules** and adjust based on business needs
2. **Monitor storage costs** and optimize lifecycle policies
3. **Update provider versions** for security patches
4. **Test disaster recovery procedures** monthly
5. **Review and rotate service account keys** quarterly

### Terraform State Management
```bash
# For production, use remote state
terraform {
  backend "gcs" {
    bucket = "your-terraform-state-bucket"
    prefix = "disaster-recovery/terraform.tfstate"
  }
}

# Import existing resources if needed
terraform import google_alloydb_cluster.primary projects/PROJECT/locations/REGION/clusters/CLUSTER_ID
```

### Upgrading Provider Versions
```bash
# Check for provider updates
terraform init -upgrade

# Plan with new provider version
terraform plan

# Apply updates during maintenance window
terraform apply
```

## 🧪 Testing and Validation

### Infrastructure Tests
```bash
# Validate Terraform configuration
terraform validate

# Check formatting
terraform fmt -check

# Security scan (using checkov)
pip install checkov
checkov -f main.tf

# Cost estimation (using infracost)
infracost breakdown --path .
```

### Functional Tests
```bash
# Test AlloyDB connectivity
gcloud alloydb instances describe INSTANCE_ID \
    --cluster=CLUSTER_ID \
    --region=REGION

# Test Spanner connectivity
gcloud spanner databases execute-sql critical-data \
    --instance=INSTANCE_ID \
    --sql="SELECT 1"

# Test backup creation
gcloud alloydb backups create test-backup \
    --cluster=CLUSTER_ID \
    --region=REGION
```

## 🚨 Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   gcloud services enable alloydb.googleapis.com
   gcloud services enable spanner.googleapis.com
   ```

2. **Quota Exceeded**:
   ```bash
   # Check quotas
   gcloud compute project-info describe --project=PROJECT_ID
   
   # Request quota increase via Cloud Console
   ```

3. **Network Connectivity Issues**:
   ```bash
   # Check service networking connection
   gcloud services vpc-peerings list \
       --network=NETWORK_NAME
   ```

4. **Terraform State Issues**:
   ```bash
   # Refresh state
   terraform refresh
   
   # Import existing resource
   terraform import RESOURCE_TYPE.NAME RESOURCE_ID
   ```

### Debugging Commands
```bash
# Enable Terraform debug logging
export TF_LOG=DEBUG
terraform plan

# Check Google Cloud API calls
export GOOGLE_CLOUD_VERBOSITY=debug

# Validate network connectivity
gcloud compute networks describe NETWORK_NAME
```

## 🧹 Cleanup

### Development/Testing Cleanup
```bash
# Destroy all resources (CAUTION: This deletes everything)
terraform destroy

# Destroy specific resources
terraform destroy -target=google_alloydb_cluster.secondary
```

### Production Cleanup
For production environments, follow a careful cleanup process:

1. **Backup Critical Data**:
   ```bash
   # Create final backups before cleanup
   gcloud alloydb backups create final-backup \
       --cluster=CLUSTER_ID \
       --region=REGION
   ```

2. **Remove Deletion Protection**:
   ```bash
   terraform apply -var="enable_deletion_protection=false"
   ```

3. **Gradual Resource Removal**:
   ```bash
   # Remove non-critical resources first
   terraform destroy -target=google_cloud_scheduler_job.backup_job
   terraform destroy -target=google_cloudfunctions2_function.orchestrator
   
   # Remove storage after verifying backups
   terraform destroy -target=google_storage_bucket.primary_backup
   
   # Finally remove databases
   terraform destroy -target=google_alloydb_cluster.primary
   ```

## 📞 Support and Contributing

### Getting Help
- Review the [AlloyDB documentation](https://cloud.google.com/alloydb/docs)
- Check [Cloud Spanner best practices](https://cloud.google.com/spanner/docs/best-practices)
- Visit [Terraform Google Provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make changes and test thoroughly
4. Submit a pull request with detailed description

### Reporting Issues
When reporting issues, include:
- Terraform version and provider versions
- Complete error messages
- Relevant configuration snippets
- Steps to reproduce the issue

---

## 📄 License

This Terraform configuration is provided as-is for educational and production use. Review and modify according to your organization's requirements and security policies.

## ⚡ Quick Reference

### Essential Commands
```bash
# Initial setup
terraform init
terraform plan
terraform apply

# Daily operations
terraform output
terraform refresh
terraform validate

# Maintenance
terraform fmt
terraform init -upgrade
terraform plan -refresh-only

# Emergency
terraform destroy -target=RESOURCE
terraform import RESOURCE_TYPE.NAME ID
```

### Important Files
- `main.tf` - Core infrastructure
- `variables.tf` - Configuration options
- `outputs.tf` - Deployment information
- `terraform.tfvars` - Your specific values

> 🎯 **Success Tip**: Start with default values, then customize based on your specific requirements. Test in a development environment before applying to production.