# AlloyDB AI Performance Automation - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code for deploying a comprehensive AlloyDB AI performance automation system that combines AlloyDB AI's vector capabilities with Cloud Monitoring intelligence and automated optimization workflows.

## Architecture Overview

The infrastructure deploys:

- **AlloyDB AI Cluster**: PostgreSQL-compatible database with AI enhancements and vector search capabilities
- **Cloud Monitoring**: Performance metrics collection and alerting
- **Vertex AI**: Machine learning for performance pattern analysis and optimization recommendations
- **Cloud Functions**: Serverless automation for applying optimization recommendations
- **Cloud Scheduler**: Automated performance analysis and reporting
- **VPC Network**: Secure private networking for database access
- **Pub/Sub**: Event-driven communication between components

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud CLI** installed and configured:
   ```bash
   gcloud --version
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.0):
   ```bash
   terraform --version
   ```

3. **Required Google Cloud APIs** enabled:
   ```bash
   gcloud services enable alloydb.googleapis.com
   gcloud services enable compute.googleapis.com
   gcloud services enable monitoring.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable cloudscheduler.googleapis.com
   gcloud services enable servicenetworking.googleapis.com
   ```

4. **Appropriate IAM permissions**:
   - AlloyDB Admin
   - Compute Network Admin
   - Cloud Functions Admin
   - Vertex AI User
   - Monitoring Admin
   - Service Account Admin
   - Security Admin (for Secret Manager)

5. **Billing account** configured for cost monitoring features

## Quick Start

### 1. Initialize Terraform

```bash
cd terraform/
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your configuration:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
environment                    = "dev"
resource_prefix               = "alloydb-perf"
alloydb_cpu_count            = 4
alloydb_memory_size_gb       = 16
alloydb_availability_type    = "ZONAL"
performance_analysis_schedule = "*/15 * * * *"
daily_report_schedule        = "0 9 * * *"
monitoring_enabled           = true
enable_cost_alerts           = true
daily_cost_budget_usd        = 100

# Network configuration
vpc_cidr_range        = "10.0.0.0/24"
private_service_cidr  = "10.1.0.0/16"

# Security settings
enable_iam_authentication = true
authorized_networks       = []

# Resource tagging
labels = {
  environment = "dev"
  purpose     = "performance-automation"
  team        = "data-engineering"
}
```

### 3. Plan and Apply

```bash
# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply
```

### 4. Access Your Deployment

After successful deployment, Terraform will output connection information and management URLs.

## Configuration Variables

### Core Infrastructure

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Primary region for deployment | `us-central1` | No |
| `zone` | Primary zone for deployment | `us-central1-a` | No |
| `environment` | Environment name (dev/staging/prod) | `dev` | No |
| `resource_prefix` | Prefix for all resource names | `alloydb-perf` | No |

### AlloyDB Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `alloydb_cluster_id` | Unique cluster identifier | auto-generated | No |
| `alloydb_cpu_count` | Number of vCPUs | `4` | No |
| `alloydb_memory_size_gb` | Memory in GB | `16` | No |
| `alloydb_availability_type` | ZONAL or REGIONAL | `ZONAL` | No |
| `alloydb_backup_enabled` | Enable automated backups | `true` | No |
| `alloydb_backup_retention_days` | Backup retention period | `7` | No |

### Monitoring and Automation

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `monitoring_enabled` | Enable Cloud Monitoring integration | `true` | No |
| `performance_analysis_schedule` | Cron schedule for analysis | `*/15 * * * *` | No |
| `daily_report_schedule` | Cron schedule for reports | `0 9 * * *` | No |
| `performance_threshold_latency_ms` | Query latency alert threshold | `1000` | No |
| `alert_notification_channels` | Notification channel IDs | `[]` | No |

### Network Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `vpc_cidr_range` | CIDR range for VPC subnet | `10.0.0.0/24` | No |
| `private_service_cidr` | CIDR for private service connection | `10.1.0.0/16` | No |
| `authorized_networks` | Authorized networks for database access | `[]` | No |

### Cloud Functions

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `function_runtime` | Python runtime version | `python311` | No |
| `function_memory_mb` | Memory allocation in MB | `512` | No |
| `function_timeout_seconds` | Function timeout | `540` | No |

## Deployment Features

### Automated Performance Optimization

The system automatically:

1. **Collects Performance Metrics**: Every 15 minutes via Cloud Scheduler
2. **Analyzes Performance Data**: Using Cloud Monitoring and custom database queries  
3. **Generates AI Recommendations**: Via Vertex AI-powered analysis
4. **Applies Safe Optimizations**: Through automated Cloud Functions
5. **Tracks Optimization Results**: Using vector embeddings for pattern learning

### Monitoring and Alerting

- **Real-time Dashboard**: Cloud Monitoring dashboard for performance visualization
- **Intelligent Alerts**: AI-driven anomaly detection and alerting
- **Performance Scoring**: Custom metrics for overall database health
- **Daily Reports**: Automated performance summary generation

### Security Features

- **Private Networking**: VPC with private service connections
- **IAM Authentication**: Optional database authentication via Google Cloud IAM
- **Secret Management**: Database credentials stored in Secret Manager
- **Network Isolation**: AlloyDB cluster isolated in private network

### Cost Management

- **Budget Alerts**: Configurable cost monitoring and alerts
- **Resource Tagging**: Comprehensive labeling for cost allocation
- **Auto-scaling**: Performance-based resource optimization

## Post-Deployment Steps

### 1. Connect to AlloyDB

```bash
# Get database password from Secret Manager
export DB_PASSWORD=$(gcloud secrets versions access latest --secret="alloydb-password-XXXXX")

# Connect using Cloud SQL Proxy (recommended)
cloud-sql-proxy --alloydb projects/PROJECT_ID/locations/REGION/clusters/CLUSTER_NAME

# Or connect directly (requires network access)
psql "postgresql://postgres:$DB_PASSWORD@INSTANCE_IP:5432/postgres"
```

### 2. Configure Vector Extensions

```sql
-- Enable vector extension for performance analysis
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify extension installation
SELECT * FROM pg_extension WHERE extname = 'vector';
```

### 3. Test Performance Optimization

```bash
# Trigger manual performance analysis
gcloud pubsub topics publish alloydb-performance-events-XXXXX \
    --message='{"action":"analyze_performance","cluster":"CLUSTER_NAME"}'

# Check function execution logs
gcloud functions logs read alloydb-performance-optimizer-XXXXX \
    --gen2 --region=REGION --limit=10
```

### 4. Access Monitoring Dashboard

Visit the Cloud Monitoring dashboard URL provided in Terraform outputs to view real-time performance metrics and AI optimization actions.

## Management Operations

### Manual Performance Analysis

```bash
# Trigger immediate performance analysis
gcloud pubsub topics publish $(terraform output -raw performance_events_topic_name) \
    --message='{"action":"analyze_performance"}'

# Generate performance report
gcloud pubsub topics publish $(terraform output -raw performance_events_topic_name) \
    --message='{"action":"generate_report"}'
```

### Scaling Operations

```bash
# Update AlloyDB instance resources
terraform apply -var="alloydb_cpu_count=8" -var="alloydb_memory_size_gb=32"

# Modify performance analysis frequency
terraform apply -var="performance_analysis_schedule=*/5 * * * *"
```

### Monitoring and Troubleshooting

```bash
# View Cloud Function logs
gcloud functions logs read $(terraform output -raw performance_optimizer_function_name) \
    --gen2 --region=$(terraform output -raw deployment_region)

# Check Cloud Scheduler job status
gcloud scheduler jobs describe performance-analyzer-XXXXX \
    --location=$(terraform output -raw deployment_region)

# Monitor AlloyDB cluster status
gcloud alloydb clusters describe $(terraform output -raw alloydb_cluster_name) \
    --region=$(terraform output -raw deployment_region)
```

## Customization Examples

### Advanced Monitoring Configuration

```hcl
# Enable comprehensive alerting
alert_notification_channels = [
    "projects/PROJECT_ID/notificationChannels/CHANNEL_ID_1",
    "projects/PROJECT_ID/notificationChannels/CHANNEL_ID_2"
]

# Adjust performance thresholds
performance_threshold_latency_ms = 500

# Enable production-grade availability
alloydb_availability_type = "REGIONAL"
```

### High-Performance Configuration

```hcl
# Scale for high-performance workloads
alloydb_cpu_count      = 16
alloydb_memory_size_gb = 64

# Increase function resources
function_memory_mb = 2048
function_timeout_seconds = 540

# More frequent optimization
performance_analysis_schedule = "*/5 * * * *"
```

### Cost-Optimized Configuration

```hcl
# Minimal configuration for development
alloydb_cpu_count      = 2
alloydb_memory_size_gb = 8
alloydb_availability_type = "ZONAL"

# Reduced monitoring frequency
performance_analysis_schedule = "0 */4 * * *"  # Every 4 hours
daily_report_schedule = "0 6 * * 1"            # Weekly reports

# Cost controls
enable_cost_alerts = true
daily_cost_budget_usd = 25
```

## Cleanup

To remove all deployed resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify cleanup (optional)
gcloud alloydb clusters list --filter="name:alloydb-perf"
gcloud compute networks list --filter="name:alloydb-perf"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has the required IAM roles
3. **Network Connectivity**: Check VPC and firewall configurations
4. **Resource Quotas**: Verify project quotas for AlloyDB and other services

### Getting Help

- Check Terraform outputs for connection information
- Review Cloud Function logs for optimization details
- Monitor Cloud Logging for system events
- Contact support with specific error messages and resource IDs

## License

This infrastructure code is provided under the Apache 2.0 License. See the recipe documentation for additional details and usage guidelines.