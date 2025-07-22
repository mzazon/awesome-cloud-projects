# Infrastructure as Code for Multi-Tenant Resource Scheduling with Cloud Scheduler and Cloud Filestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Tenant Resource Scheduling with Cloud Scheduler and Cloud Filestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud CLI) installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled (Cloud Functions, Cloud Scheduler, Cloud Filestore, Cloud Monitoring)
- Appropriate IAM permissions:
  - Compute Admin
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Cloud Filestore Admin
  - Monitoring Admin
  - Project Editor (or equivalent custom role)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project and region
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create multi-tenant-scheduler \
    --location=${REGION} \
    --source=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe multi-tenant-scheduler \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -var="project_id=$(gcloud config get-value project)"

# Apply the configuration
terraform apply -var="project_id=$(gcloud config get-value project)"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for confirmation and deploy all resources
```

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `resource_suffix` | Unique suffix for resources | Generated | No |
| `filestore_tier` | Filestore performance tier | `BASIC_HDD` | No |
| `filestore_capacity` | Filestore capacity in GB | `1024` | No |
| `function_memory` | Cloud Function memory (MB) | `512` | No |
| `function_timeout` | Cloud Function timeout (seconds) | `300` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `environment` | Environment name | `dev` | No |
| `filestore_tier` | Filestore performance tier | `BASIC_HDD` | No |
| `filestore_capacity_gb` | Filestore capacity in GB | `1024` | No |
| `enable_monitoring` | Enable Cloud Monitoring resources | `true` | No |
| `scheduler_time_zone` | Time zone for scheduler jobs | `America/New_York` | No |

### Bash Script Configuration

The bash scripts use environment variables that can be customized:

```bash
# Set custom configuration before running deploy.sh
export REGION="us-west1"
export ZONE="us-west1-a"
export FILESTORE_TIER="BASIC_SSD"
export FILESTORE_CAPACITY="2048"

./scripts/deploy.sh
```

## Architecture Components

This IaC deployment creates the following resources:

### Core Infrastructure
- **Cloud Filestore Instance**: Shared NFS storage for multi-tenant data
- **Cloud Function**: Resource orchestration and scheduling logic
- **Cloud Scheduler Jobs**: Automated tenant management tasks
- **Cloud Monitoring**: Dashboards and alerting policies

### Networking
- **VPC**: Default network with Filestore connectivity
- **Firewall Rules**: Secure access patterns for tenant isolation

### Security & IAM
- **Service Accounts**: Least-privilege access for Cloud Functions
- **IAM Bindings**: Appropriate permissions for resource management
- **Secret Manager**: Secure configuration storage (if enabled)

### Monitoring & Observability
- **Custom Metrics**: Tenant resource allocation tracking
- **Alert Policies**: Quota violation and system health alerts
- **Dashboards**: Multi-tenant resource utilization visualization

## Testing the Deployment

After deployment, test the multi-tenant scheduling system:

```bash
# Get the Cloud Function URL (adjust based on your deployment method)
FUNCTION_URL=$(gcloud functions describe resource-scheduler-* \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test tenant resource allocation
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "tenant_id": "tenant_a",
        "resource_type": "compute",
        "capacity": 3,
        "duration": 4
    }'

# Test quota enforcement
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "tenant_id": "tenant_c",
        "resource_type": "compute",
        "capacity": 15,
        "duration": 1
    }'
```

## Monitoring and Operations

### Accessing Dashboards

1. **Cloud Monitoring Console**: Navigate to Monitoring > Dashboards
2. **Custom Dashboard**: Look for "Multi-Tenant Resource Dashboard"
3. **Metrics Explorer**: Query `custom.googleapis.com/tenant/resource_allocations`

### Viewing Logs

```bash
# View Cloud Function logs
gcloud functions logs read resource-scheduler-* --region=${REGION}

# View Cloud Scheduler logs
gcloud logging read "resource.type=cloud_scheduler_job" --limit=50
```

### Managing Scheduler Jobs

```bash
# List all scheduler jobs
gcloud scheduler jobs list --filter="name:*tenant*"

# Manually trigger a job
gcloud scheduler jobs run tenant-cleanup-* --location=${REGION}

# Pause/resume a job
gcloud scheduler jobs pause tenant-cleanup-* --location=${REGION}
gcloud scheduler jobs resume tenant-cleanup-* --location=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete multi-tenant-scheduler \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=$(gcloud config get-value project)"

# Clean up state files (optional)
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup Verification

```bash
# Verify all resources are removed
gcloud filestore instances list
gcloud functions list
gcloud scheduler jobs list
gcloud monitoring dashboards list --filter="displayName:*Multi-Tenant*"
```

## Customization

### Extending Tenant Configurations

To add new tenants or modify quotas, update the tenant configuration in the Cloud Function:

```python
# In the function code, modify the get_tenant_quota function
tenant_quotas = {
    'tenant_a': 10,
    'tenant_b': 15,
    'tenant_c': 8,
    'tenant_d': 20,  # New tenant
    'default': 5
}
```

### Adding Custom Scheduler Jobs

Create additional scheduler jobs for specific tenant workflows:

```bash
# Example: Add weekend processing job
gcloud scheduler jobs create http weekend-batch-processing \
    --schedule="0 6 * * 6,0" \
    --uri="${FUNCTION_URL}" \
    --http-method=POST \
    --message-body='{"action":"weekend_batch","tenant_id":"all"}'
```

### Scaling Filestore Performance

For higher performance requirements, upgrade the Filestore tier:

```bash
# Update to BASIC_SSD tier
gcloud filestore instances update tenant-data-${RESOURCE_SUFFIX} \
    --zone=${ZONE} \
    --tier=BASIC_SSD
```

## Security Considerations

### Network Security
- Filestore uses private IP addresses within your VPC
- Cloud Functions communicate securely with Google APIs
- No public IP addresses are exposed unnecessarily

### Access Control
- Service accounts use least-privilege principles
- IAM roles are scoped to specific resource operations
- Tenant isolation is enforced through directory-based access

### Data Protection
- Filestore data is encrypted at rest by default
- Cloud Function environment variables are secure
- Audit logging tracks all resource access

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
2. **Insufficient Permissions**: Verify your account has the required IAM roles
3. **Quota Limits**: Check project quotas for Filestore, Functions, and Scheduler
4. **Region Availability**: Verify all services are available in your chosen region

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check resource quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# View deployment errors
gcloud functions logs read resource-scheduler-* --region=${REGION} --limit=100
```

### Performance Tuning

- **Filestore Performance**: Consider BASIC_SSD or HIGH_SCALE_SSD for better performance
- **Function Memory**: Increase memory allocation for CPU-intensive operations
- **Scheduler Frequency**: Adjust job schedules based on tenant workload patterns
- **Monitoring Retention**: Configure log retention policies for cost optimization

## Cost Optimization

### Resource Sizing
- Start with BASIC_HDD Filestore for development
- Use minimum function memory for simple operations
- Schedule jobs during off-peak hours when possible

### Monitoring Costs
- Set up billing alerts for unexpected cost increases
- Use Cloud Monitoring to track resource utilization
- Implement automated cleanup for unused tenant resources

### Best Practices
- Delete test resources promptly
- Use preemptible instances where appropriate
- Implement resource tagging for cost allocation
- Regular review of quota usage and optimization opportunities

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe markdown file
2. **Google Cloud Documentation**: 
   - [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
   - [Cloud Scheduler](https://cloud.google.com/scheduler/docs)
   - [Cloud Filestore](https://cloud.google.com/filestore/docs)
   - [Cloud Functions](https://cloud.google.com/functions/docs)
3. **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: Google Cloud Community forums and Stack Overflow

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Update variable documentation for any new parameters
3. Maintain compatibility across all deployment methods
4. Update this README with any new features or requirements
5. Follow Google Cloud security and performance best practices