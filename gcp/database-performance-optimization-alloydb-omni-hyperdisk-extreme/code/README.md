# Infrastructure as Code for Database Performance Optimization with AlloyDB Omni and Hyperdisk Extreme

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Database Performance Optimization with AlloyDB Omni and Hyperdisk Extreme".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Docker installed locally for AlloyDB Omni container management
- Project with billing enabled and appropriate quotas for c3-highmem-8 instances
- IAM permissions for:
  - Compute Engine (instances, disks, networks)
  - Cloud Functions (create, deploy, invoke)
  - Cloud Monitoring (dashboards, alerts, policies)
  - Cloud Logging (read, write)
- Estimated cost: $15-25 for resources created during deployment

> **Warning**: This recipe uses high-performance compute and storage resources that incur significant costs. Ensure proper cleanup to avoid unexpected charges.

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply \
    projects/PROJECT_ID/locations/REGION/deployments/alloydb-perf-deployment \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --local-source="." \
    --input-values="project_id=PROJECT_ID,region=REGION"

# Monitor deployment status
gcloud infra-manager deployments describe \
    projects/PROJECT_ID/locations/REGION/deployments/alloydb-perf-deployment
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=PROJECT_ID" -var="region=us-central1"

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
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
gcloud compute instances list --filter="name~alloydb-vm"
gcloud compute disks list --filter="name~hyperdisk-extreme"
```

## Architecture Overview

This infrastructure deploys:

- **Compute Engine VM**: c3-highmem-8 instance optimized for database workloads
- **Hyperdisk Extreme**: Ultra-high performance storage with 100,000 IOPS
- **AlloyDB Omni**: PostgreSQL-compatible database with columnar engine
- **Cloud Monitoring**: Performance dashboards and metrics collection
- **Cloud Functions**: Automated performance scaling logic
- **Alert Policies**: Proactive monitoring and notification system

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `machine_type` | VM instance type | `c3-highmem-8` | No |
| `disk_size_gb` | Hyperdisk Extreme size | `500` | No |
| `provisioned_iops` | Hyperdisk IOPS | `100000` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | - | Yes |
| `region` | Deployment region | `string` | `us-central1` | No |
| `zone` | Deployment zone | `string` | `us-central1-a` | No |
| `instance_name_prefix` | VM instance name prefix | `string` | `alloydb-vm` | No |
| `disk_name_prefix` | Disk name prefix | `string` | `hyperdisk-extreme` | No |
| `enable_monitoring` | Enable monitoring dashboard | `bool` | `true` | No |
| `enable_alerting` | Enable alert policies | `bool` | `true` | No |

### Bash Script Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud Project ID | `alloydb-perf-project` |
| `REGION` | Deployment region | `us-central1` |
| `ZONE` | Deployment zone | `us-central1-a` |
| `INSTANCE_NAME` | VM instance name | `alloydb-vm-${RANDOM_SUFFIX}` |
| `DISK_NAME` | Hyperdisk name | `hyperdisk-extreme-${RANDOM_SUFFIX}` |
| `FUNCTION_NAME` | Cloud Function name | `perf-scaler-${RANDOM_SUFFIX}` |

## Post-Deployment Setup

After infrastructure deployment, complete the AlloyDB Omni setup:

1. **Connect to VM Instance**:
   ```bash
   gcloud compute ssh INSTANCE_NAME --zone=ZONE
   ```

2. **Deploy AlloyDB Omni Container**:
   ```bash
   # Pull and run AlloyDB Omni
   sudo docker pull gcr.io/alloydb-omni/alloydb-omni:latest
   sudo docker run -d --name alloydb-omni \
     --restart unless-stopped \
     -p 5432:5432 \
     -v /var/lib/alloydb/data:/var/lib/postgresql/data \
     -e POSTGRES_PASSWORD=AlloyDB_Secure_2025! \
     -e POSTGRES_DB=analytics_db \
     gcr.io/alloydb-omni/alloydb-omni:latest
   ```

3. **Load Sample Data**:
   ```bash
   # Connect to database and create test tables
   sudo docker exec -i alloydb-omni psql -U postgres -d analytics_db < sample_data.sql
   ```

## Validation & Testing

### Performance Validation

```bash
# Test database performance
gcloud compute ssh INSTANCE_NAME --zone=ZONE --command='
  sudo docker exec -i alloydb-omni psql -U postgres -d analytics_db -c "
    SELECT category, COUNT(*) as transaction_count, AVG(amount) as avg_amount
    FROM transactions 
    WHERE transaction_date >= NOW() - INTERVAL '\''7 days'\''
    GROUP BY category;"
'

# Test storage performance
gcloud compute ssh INSTANCE_NAME --zone=ZONE --command='
  sudo fio --name=test --ioengine=libaio --iodepth=64 \
    --rw=randread --bs=4k --direct=1 --size=1G --runtime=30 \
    --filename=/var/lib/alloydb/test_file --group_reporting
'
```

### Monitoring Validation

```bash
# Check monitoring dashboard
gcloud monitoring dashboards list --filter="displayName:AlloyDB"

# Test scaling function
FUNCTION_URL=$(gcloud functions describe FUNCTION_NAME --format="value(httpsTrigger.url)")
curl -X POST ${FUNCTION_URL} -H "Content-Type: application/json" -d '{"test": true}'
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/PROJECT_ID/locations/REGION/deployments/alloydb-perf-deployment \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource deletion
gcloud compute instances list --filter="name~alloydb-vm"
gcloud compute disks list --filter="name~hyperdisk-extreme"
gcloud functions list --filter="name~perf-scaler"
```

## Troubleshooting

### Common Issues

1. **Quota Exceeded**: Ensure sufficient quota for c3-highmem-8 instances
   ```bash
   gcloud compute project-info describe --project=PROJECT_ID
   ```

2. **Hyperdisk Extreme Unavailable**: Check regional availability
   ```bash
   gcloud compute disk-types list --filter="name:hyperdisk-extreme"
   ```

3. **AlloyDB Omni Container Issues**: Verify Docker installation and permissions
   ```bash
   gcloud compute ssh INSTANCE_NAME --command='sudo docker ps -a'
   ```

4. **Function Deployment Failures**: Check Cloud Functions API enablement
   ```bash
   gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com"
   ```

### Performance Optimization

- **Storage Performance**: Monitor IOPS utilization and adjust provisioned IOPS
- **Database Tuning**: Use AlloyDB Omni's autopilot features for automatic optimization
- **Instance Scaling**: Use Cloud Functions to automatically scale compute resources
- **Monitoring**: Set up custom alerts for performance thresholds

## Security Considerations

- **Network Security**: VM uses default VPC with automatic firewall rules
- **Database Security**: AlloyDB Omni configured with strong password authentication
- **IAM Permissions**: Follow least privilege principle for service accounts
- **Encryption**: Hyperdisk Extreme uses Google-managed encryption keys
- **Function Security**: Cloud Functions deployed with appropriate IAM bindings

## Cost Optimization

- **Hyperdisk Extreme**: High-performance storage incurs premium costs
- **c3-highmem-8**: Consider smaller instance types for development/testing
- **Monitoring**: Basic Cloud Monitoring included; advanced features may incur costs
- **Functions**: Pay-per-invocation pricing model for scaling automation

## Support and Resources

- [AlloyDB Omni Documentation](https://cloud.google.com/alloydb/docs/omni/overview)
- [Hyperdisk Performance Guide](https://cloud.google.com/compute/docs/disks/hyperdisks)
- [Cloud Monitoring Best Practices](https://cloud.google.com/monitoring/best-practices)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.