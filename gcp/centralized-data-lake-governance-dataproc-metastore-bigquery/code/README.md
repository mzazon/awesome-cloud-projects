# Infrastructure as Code for Establishing Centralized Data Lake Governance with Dataproc Metastore and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Establishing Centralized Data Lake Governance with Dataproc Metastore and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Solution Overview

This IaC deploys a comprehensive data lake governance solution that includes:

- **Cloud Storage**: Data lake foundation with proper lifecycle management
- **BigLake Metastore**: Unified metadata management across analytics engines
- **BigQuery**: Data warehouse with external table integration
- **Dataproc**: Managed Spark/Hadoop clusters with metastore integration
- **Data Catalog**: Governance and lineage tracking capabilities
- **IAM**: Least privilege security controls

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Project owner or editor permissions for:
  - BigQuery
  - Dataproc
  - Cloud Storage
  - Metastore
  - Compute Engine
  - Data Catalog
- APIs enabled:
  - BigQuery API (`bigquery.googleapis.com`)
  - Dataproc API (`dataproc.googleapis.com`)
  - Cloud Storage API (`storage.googleapis.com`)
  - Metastore API (`metastore.googleapis.com`)
  - Compute Engine API (`compute.googleapis.com`)
  - Data Catalog API (`datacatalog.googleapis.com`)

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    projects/PROJECT_ID/locations/REGION/deployments/data-governance \
    --config-file infrastructure-manager/main.yaml \
    --labels=env=dev,team=data-engineering

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/PROJECT_ID/locations/REGION/deployments/data-governance
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=YOUR_PROJECT_ID" \
               -var="region=us-central1"

# Deploy the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" \
                -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# View deployment status
./scripts/status.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Primary region for resources"
    type: string
    default: "us-central1"
  environment:
    description: "Environment tag (dev, staging, prod)"
    type: string
    default: "dev"
  metastore_tier:
    description: "Metastore service tier"
    type: string
    default: "DEVELOPER"
```

### Terraform Variables

Customize deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Metastore configuration
metastore_tier = "DEVELOPER"  # Options: DEVELOPER, ENTERPRISE
metastore_version = "3.1.2"

# Dataproc configuration
dataproc_machine_type = "n1-standard-2"
dataproc_worker_count = 2
enable_preemptible = true

# Storage configuration
storage_class = "STANDARD"
enable_versioning = true

# Environment and tagging
environment = "dev"
team = "data-engineering"
```

### Bash Script Configuration

Set environment variables before running scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export METASTORE_TIER="DEVELOPER"
export DATAPROC_WORKERS="2"
export STORAGE_CLASS="STANDARD"
export ENVIRONMENT="dev"
```

## Deployment Details

### Resources Created

The IaC creates the following Google Cloud resources:

1. **Cloud Storage**:
   - Data lake bucket with lifecycle policies
   - Warehouse directory structure
   - Versioning and uniform bucket-level access

2. **BigLake Metastore**:
   - Managed Hive Metastore service
   - MySQL backend with automated backups
   - Network configuration for secure access

3. **BigQuery**:
   - Dataset with metastore integration
   - External tables pointing to Cloud Storage
   - Governance views and materialized views

4. **Dataproc**:
   - Autoscaling cluster with metastore integration
   - Preemptible worker nodes for cost optimization
   - Spark and Hive configuration

5. **Data Catalog**:
   - Entry groups for governance
   - Metadata entries with lineage tracking
   - Search and discovery capabilities

6. **IAM**:
   - Service accounts with least privilege access
   - Custom roles for data governance
   - Workload Identity for secure access

### Security Features

- **Encryption**: All data encrypted at rest and in transit
- **Network Security**: Private IP configurations where possible
- **Access Controls**: Fine-grained IAM permissions
- **Audit Logging**: Comprehensive audit trail configuration
- **Data Loss Prevention**: DLP API integration for sensitive data

### Cost Optimization

- **Preemptible Instances**: Used for Dataproc workers
- **Autoscaling**: Automatic scaling based on workload
- **Storage Classes**: Intelligent tiering for cost optimization
- **Serverless Services**: Pay-per-use BigQuery and Metastore
- **Resource Tagging**: Cost allocation and monitoring

## Post-Deployment Validation

### Verify Metastore Connectivity

```bash
# Check metastore status
gcloud metastore services describe governance-metastore \
    --location=$REGION \
    --format="table(name,state,endpointUri)"

# Test Hive connectivity from Dataproc
gcloud dataproc jobs submit hive \
    --cluster=analytics-cluster \
    --region=$REGION \
    --execute="SHOW DATABASES;"
```

### Test Cross-Engine Access

```bash
# Query from BigQuery
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) FROM \`$PROJECT_ID.governance_dataset.retail_data\`"

# Query from Spark
gcloud dataproc jobs submit spark \
    --cluster=analytics-cluster \
    --region=$REGION \
    --py-files=validation_script.py
```

### Validate Governance Policies

```bash
# Test data catalog search
gcloud data-catalog search \
    --query="customer analytics" \
    --scope=projects/$PROJECT_ID

# Check IAM permissions
gcloud projects get-iam-policy $PROJECT_ID
```

## Monitoring and Logging

### Stackdriver Integration

The infrastructure includes comprehensive monitoring:

- **Cloud Monitoring**: Metrics for all services
- **Cloud Logging**: Centralized log aggregation
- **Error Reporting**: Automatic error detection
- **Cloud Trace**: Distributed tracing for analytics workflows

### Custom Dashboards

Access pre-configured dashboards:

```bash
# View monitoring dashboard
gcloud monitoring dashboards list \
    --filter="displayName:Data Lake Governance"

# Check alert policies
gcloud alpha monitoring policies list \
    --filter="displayName:Metastore Health"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/PROJECT_ID/locations/REGION/deployments/data-governance

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                  -var="region=us-central1"

# Clean up state files
rm -rf .terraform/
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
./scripts/verify_cleanup.sh
```

### Manual Cleanup Verification

```bash
# Check for remaining resources
gcloud metastore services list --location=$REGION
gcloud dataproc clusters list --region=$REGION
bq ls --project_id=$PROJECT_ID
gsutil ls
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable metastore.googleapis.com \
       dataproc.googleapis.com \
       bigquery.googleapis.com
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy $PROJECT_ID \
       --flatten="bindings[].members" \
       --filter="bindings.members:user:$(gcloud config get-value account)"
   ```

3. **Metastore Connectivity Issues**:
   ```bash
   # Check network connectivity
   gcloud compute networks subnets list \
       --filter="region:$REGION"
   
   # Verify firewall rules
   gcloud compute firewall-rules list \
       --filter="name~metastore"
   ```

4. **Dataproc Cluster Creation Failures**:
   ```bash
   # Check cluster status
   gcloud dataproc clusters describe analytics-cluster \
       --region=$REGION \
       --format="table(status.state,status.stateStartTime)"
   ```

### Debug Commands

```bash
# Enable debug logging
export GOOGLE_CLOUD_LOG_LEVEL=debug

# Check operation status
gcloud operations list \
    --filter="operationType:metastore" \
    --limit=10

# View detailed logs
gcloud logging read \
    'resource.type="dataproc_cluster" AND severity>=ERROR' \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"
```

## Advanced Configuration

### Custom Metastore Configuration

For production deployments, consider:

```hcl
# terraform/variables.tf
variable "metastore_tier" {
  description = "Metastore service tier"
  type        = string
  default     = "ENTERPRISE"  # For production workloads
}

variable "metastore_scaling_factor" {
  description = "Scaling factor for metastore"
  type        = number
  default     = 2  # For high-availability
}
```

### Network Security Hardening

```hcl
# Private IP configuration
variable "enable_private_ip" {
  description = "Enable private IP for all resources"
  type        = bool
  default     = true
}

# VPC configuration
variable "create_vpc" {
  description = "Create dedicated VPC for data lake"
  type        = bool
  default     = true
}
```

### Multi-Region Deployment

```hcl
# Additional regions for disaster recovery
variable "backup_regions" {
  description = "Additional regions for backup and DR"
  type        = list(string)
  default     = ["us-east1", "europe-west1"]
}
```

## Performance Optimization

### Dataproc Tuning

```hcl
# High-performance configuration
variable "dataproc_config" {
  description = "Dataproc cluster configuration"
  type = object({
    machine_type    = string
    disk_size_gb   = number
    num_workers    = number
    preemptible    = bool
  })
  default = {
    machine_type    = "n1-highmem-4"
    disk_size_gb   = 500
    num_workers    = 10
    preemptible    = false
  }
}
```

### BigQuery Optimization

```sql
-- Clustering and partitioning for large datasets
CREATE TABLE `${project_id}.${dataset_id}.customer_analytics_optimized`
PARTITION BY DATE(transaction_date)
CLUSTER BY customer_id, product_category
AS SELECT * FROM `${project_id}.${dataset_id}.customer_analytics`;
```

## Support and Documentation

### Additional Resources

- [Google Cloud Metastore Documentation](https://cloud.google.com/dataproc-metastore/docs)
- [BigQuery External Data Sources](https://cloud.google.com/bigquery/docs/external-data-sources)
- [Dataproc Best Practices](https://cloud.google.com/dataproc/docs/concepts/best-practices)
- [Data Governance on Google Cloud](https://cloud.google.com/solutions/data-governance)

### Community Support

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Slack Community](https://gcp-community.slack.com)

### Professional Support

For enterprise deployments, consider:
- Google Cloud Professional Services
- Google Cloud Support Plans
- Certified Google Cloud Partners

---

**Note**: This infrastructure code implements the complete solution described in the recipe "Establishing Centralized Data Lake Governance with Dataproc Metastore and BigQuery". For detailed implementation steps and architectural explanations, refer to the original recipe documentation.