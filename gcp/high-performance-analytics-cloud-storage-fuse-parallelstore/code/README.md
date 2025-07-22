# Infrastructure as Code for Accelerating High-Performance Analytics Workflows with Cloud Storage FUSE and Parallelstore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Accelerating High-Performance Analytics Workflows with Cloud Storage FUSE and Parallelstore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This implementation creates a high-performance analytics architecture that combines:

- **Cloud Storage with Hierarchical Namespace (HNS)** for scalable data ingestion
- **Parallelstore** with DAOS technology for ultra-fast intermediate processing
- **Cloud Dataproc cluster** for distributed analytics workloads
- **Compute Engine VMs** with dual storage mounts (Cloud Storage FUSE + Parallelstore)
- **BigQuery integration** for SQL analytics on processed data
- **Cloud Monitoring** for performance tracking and alerting

## Prerequisites

### Required Tools

- Google Cloud CLI (gcloud) installed and configured
- Terraform >= 1.5.0 (for Terraform implementation)
- Bash shell environment

### Required Permissions

Your Google Cloud account needs the following IAM roles:

- `roles/owner` or combination of:
  - `roles/compute.admin`
  - `roles/storage.admin`
  - `roles/dataproc.admin`
  - `roles/bigquery.admin`
  - `roles/parallelstore.admin`
  - `roles/monitoring.admin`
  - `roles/logging.admin`

### Billing and Quotas

- Billing account enabled on your Google Cloud project
- Sufficient quota for:
  - Compute Engine instances (c2-standard-16, c2-standard-8, c2-standard-4)
  - Parallelstore capacity (12TB minimum)
  - Cloud Dataproc clusters (1 master + 4 worker nodes)

### Cost Estimates

**Warning**: This implementation will incur significant costs:

- **Parallelstore**: ~$3,600/month for 12TB capacity
- **Compute Engine VMs**: ~$800/month for c2-standard-16
- **Cloud Dataproc**: ~$600/month for 5-node cluster
- **Cloud Storage**: ~$25/month for 1TB with HNS

**Total estimated monthly cost**: ~$5,025 (varies by usage and region)

> **Important**: Clean up resources immediately after testing to avoid unexpected charges

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Create Infrastructure Manager deployment
gcloud infra-manager deployments create high-perf-analytics \
    --location=${REGION} \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/iac-repo" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION},zone=${ZONE}"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned infrastructure
terraform plan -var="project_id=your-project-id" \
                -var="region=us-central1" \
                -var="zone=us-central1-a"

# Apply the infrastructure (requires confirmation)
terraform apply -var="project_id=your-project-id" \
                 -var="region=us-central1" \
                 -var="zone=us-central1-a"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh
```

## Post-Deployment Setup

After the infrastructure is deployed, you'll need to complete the data pipeline setup:

### 1. Upload Sample Data

```bash
# Create and upload sample analytics dataset
mkdir -p sample_data/raw/2024/01
for i in {1..100}; do
    echo "timestamp,sensor_id,value,location" > sample_data/raw/2024/01/sensor_data_${i}.csv
    for j in {1..1000}; do
        echo "$(date +%s),sensor_${i},$(($RANDOM%100)),zone_${j}" >> sample_data/raw/2024/01/sensor_data_${i}.csv
    done
done

# Upload to Cloud Storage
BUCKET_NAME=$(terraform output -raw bucket_name)
gcloud storage cp -r sample_data/ gs://${BUCKET_NAME}/
```

### 2. Submit Analytics Pipeline

```bash
# Get cluster and bucket names from Terraform outputs
CLUSTER_NAME=$(terraform output -raw dataproc_cluster_name)
BUCKET_NAME=$(terraform output -raw bucket_name)
ZONE=$(terraform output -raw zone)

# Submit the pre-configured PySpark job
gcloud dataproc jobs submit pyspark \
    gs://${BUCKET_NAME}/scripts/analytics_pipeline.py \
    --cluster=${CLUSTER_NAME} \
    --zone=${ZONE}
```

### 3. Query Results in BigQuery

```bash
# Get project ID and dataset name
PROJECT_ID=$(terraform output -raw project_id)

# Query the analytics results
bq query --use_legacy_sql=false \
    "SELECT sensor_id, avg_value 
     FROM \`${PROJECT_ID}.hpc_analytics.sensor_analytics\` 
     ORDER BY avg_value DESC 
     LIMIT 10"
```

## Performance Testing

### Validate Storage Performance

```bash
# Get VM instance name
VM_NAME=$(terraform output -raw analytics_vm_name)
ZONE=$(terraform output -raw zone)

# Test Cloud Storage FUSE performance
gcloud compute ssh ${VM_NAME} --zone=${ZONE} --command="
    echo 'Testing Cloud Storage FUSE performance...'
    time ls -la /mnt/gcs-data/sample_data/raw/2024/01/ | head -10
    
    echo 'Testing Parallelstore performance...'
    time dd if=/dev/zero of=/mnt/parallel-store/test_file bs=1M count=100
    time dd if=/mnt/parallel-store/test_file of=/dev/null bs=1M
    rm /mnt/parallel-store/test_file
"
```

### Monitor Performance Metrics

```bash
# View Parallelstore metrics
gcloud monitoring dashboards list --filter="displayName:Parallelstore"

# Check Dataproc job performance
gcloud dataproc jobs list --cluster=${CLUSTER_NAME} --zone=${ZONE}
```

## Customization

### Key Variables

The implementation supports the following customization variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | Google Cloud project ID | Required |
| `region` | GCP region for resources | `us-central1` |
| `zone` | GCP zone for resources | `us-central1-a` |
| `parallelstore_capacity_gib` | Parallelstore capacity in GiB | `12000` |
| `dataproc_worker_count` | Number of Dataproc worker nodes | `4` |
| `vm_machine_type` | Machine type for analytics VM | `c2-standard-16` |
| `enable_monitoring` | Enable Cloud Monitoring | `true` |

### Storage Configuration

To modify storage performance characteristics:

```bash
# For Terraform, update variables.tf:
variable "parallelstore_capacity_gib" {
  description = "Parallelstore capacity in GiB"
  type        = number
  default     = 12000  # Increase for higher performance
  validation {
    condition     = var.parallelstore_capacity_gib >= 12000
    error_message = "Parallelstore minimum capacity is 12000 GiB."
  }
}

# For higher performance, increase capacity:
terraform apply -var="parallelstore_capacity_gib=24000"
```

### Compute Scaling

To scale compute resources:

```bash
# Increase Dataproc cluster size
terraform apply -var="dataproc_worker_count=8"

# Use larger VM instance
terraform apply -var="vm_machine_type=c2-standard-30"
```

## Monitoring and Troubleshooting

### Key Metrics to Monitor

1. **Parallelstore Performance**:
   - Read/write throughput
   - IOPS performance
   - Latency metrics

2. **Dataproc Cluster Health**:
   - Job completion times
   - Resource utilization
   - Error rates

3. **Cost Tracking**:
   - Storage costs
   - Compute costs
   - Data transfer costs

### Common Issues

#### Parallelstore Creation Timeout

```bash
# Check Parallelstore status
gcloud parallelstore instances describe INSTANCE_NAME --location=ZONE

# If stuck in CREATING state, check quotas:
gcloud compute project-info describe --format="value(quotas[].limit,quotas[].usage,quotas[].metric)"
```

#### Storage Mount Failures

```bash
# Check VM startup script logs
gcloud compute instances get-serial-port-output VM_NAME --zone=ZONE

# Manually mount if needed
gcloud compute ssh VM_NAME --zone=ZONE --command="
    sudo gcsfuse --implicit-dirs BUCKET_NAME /mnt/gcs-data
    sudo mount -t nfs PARALLELSTORE_IP:/parallelstore /mnt/parallel-store
"
```

#### BigQuery External Table Errors

```bash
# Verify data format and location
bq show --format=prettyjson PROJECT_ID:DATASET.TABLE_NAME

# Check Cloud Storage permissions
gsutil iam get gs://BUCKET_NAME
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete high-perf-analytics \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Destroy all infrastructure
cd terraform/
terraform destroy -var="project_id=your-project-id" \
                   -var="region=us-central1" \
                   -var="zone=us-central1-a"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud compute instances list --filter="name~high-perf-analytics"
gcloud parallelstore instances list --location=${ZONE}
gcloud dataproc clusters list --region=${REGION}
gcloud storage ls gs://
bq ls
```

> **Important**: Verify that high-cost resources like Parallelstore instances are fully deleted to avoid ongoing charges

## Security Considerations

### IAM and Access Control

- VM instances use service accounts with minimal required permissions
- Parallelstore access is restricted to specific compute instances
- Cloud Storage buckets use uniform bucket-level access
- BigQuery datasets implement appropriate access controls

### Network Security

- All resources deployed in default VPC with appropriate firewall rules
- Parallelstore access restricted to internal IP ranges
- VM instances use private Google access for service communication

### Data Protection

- Cloud Storage buckets enable versioning for data protection
- Parallelstore provides built-in redundancy and fault tolerance
- Regular backup procedures should be implemented for critical data

## Performance Optimization Tips

1. **Data Organization**: Structure data in Cloud Storage to match access patterns
2. **Caching Strategy**: Keep frequently accessed data in Parallelstore
3. **Parallel Processing**: Leverage Dataproc's distributed processing capabilities
4. **Resource Sizing**: Monitor utilization and adjust instance sizes accordingly
5. **Cost Optimization**: Use Cloud Storage lifecycle policies for data tiering

## Support and Documentation

### Google Cloud Documentation

- [Cloud Storage FUSE Overview](https://cloud.google.com/storage/docs/cloud-storage-fuse/overview)
- [Parallelstore Documentation](https://cloud.google.com/parallelstore/docs)
- [Cloud Dataproc Documentation](https://cloud.google.com/dataproc/docs)
- [BigQuery External Tables](https://cloud.google.com/bigquery/docs/external-tables)

### Terraform Resources

- [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Terraform Best Practices](https://cloud.google.com/docs/terraform/best-practices-for-terraform)

### Troubleshooting

For issues with this infrastructure code:

1. Check the [original recipe documentation](../high-performance-analytics-cloud-storage-fuse-parallelstore.md)
2. Consult Google Cloud service status pages
3. Review Cloud Logging for error messages
4. Contact Google Cloud Support for service-specific issues

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any configuration changes
4. Validate changes with different deployment scenarios