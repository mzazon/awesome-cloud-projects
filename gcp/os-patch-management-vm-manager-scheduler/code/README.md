# Infrastructure as Code for OS Patch Management with VM Manager and Cloud Scheduler

This directory contains Infrastructure as Code (IaC) implementations for the recipe "OS Patch Management with VM Manager and Cloud Scheduler".

## Overview

This solution establishes a comprehensive automated OS patch management system using Google Cloud's VM Manager for patch deployment and compliance reporting, Cloud Scheduler for orchestrated timing, and Cloud Monitoring for visibility and alerting capabilities.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Appropriate Google Cloud permissions for:
  - Compute Engine API
  - VM Manager (OS Config API)
  - Cloud Scheduler API
  - Cloud Functions API
  - Cloud Monitoring API
  - Cloud Logging API
  - Cloud Storage API
- Terraform installed (version 1.0+) for Terraform deployment
- Basic knowledge of Linux/Windows system administration and Google Cloud services
- Estimated cost: $10-50/month for test environment (varies by VM instance types and monitoring usage)

> **Note**: VM Manager is included with Google Cloud at no additional cost. You only pay for the underlying Compute Engine resources and any Cloud Monitoring usage beyond the free tier.

## Architecture Components

The infrastructure includes:

- **VM Instances**: Test VMs with OS Config agent enabled
- **Cloud Storage**: Bucket for pre/post-patch scripts
- **Cloud Functions**: Serverless patch orchestration
- **Cloud Scheduler**: Automated patch deployment timing
- **Cloud Monitoring**: Dashboards and alerting
- **VM Manager**: Patch deployment and compliance tracking

## Quick Start

### Using Infrastructure Manager

Google Cloud's Infrastructure Manager is the recommended approach for GCP-native deployments:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment
gcloud infra-manager deployments create patch-mgmt-deployment \
    --location=us-central1 \
    --source=. \
    --input-values=project_id=${PROJECT_ID}
```

### Using Terraform

For multi-cloud compatibility and advanced infrastructure management:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}"

# Deploy the infrastructure
terraform apply -var="project_id=${PROJECT_ID}"
```

### Using Bash Scripts

For simple deployments and learning purposes:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
# Required
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional - will be auto-generated if not set
export INSTANCE_GROUP_NAME="patch-test-group"
export SCHEDULER_JOB_NAME="patch-deployment"
export FUNCTION_NAME="patch-trigger"
```

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID
- `region`: Default region for resources
- `zone`: Default zone for VM instances
- `vm_count`: Number of test VMs to create (default: 3)
- `machine_type`: VM instance type (default: e2-medium)
- `disk_size`: Boot disk size in GB (default: 20)
- `patch_schedule`: Cron schedule for patch deployment (default: "0 2 * * SUN")

### Infrastructure Manager Variables

Customize deployment in `infrastructure-manager/main.yaml`:

```yaml
inputs:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    required: true
  region:
    description: "Default region for resources"
    type: string
    default: "us-central1"
  vm_count:
    description: "Number of test VMs"
    type: number
    default: 3
```

## Deployment Details

### VM Manager Setup

The infrastructure automatically:

1. Creates VM instances with OS Config agent enabled
2. Configures proper metadata for VM Manager integration
3. Sets up IAM permissions for patch management
4. Enables required APIs and services

### Patch Orchestration

The system includes:

1. **Cloud Function**: Programmatic patch deployment control
2. **Cloud Scheduler**: Automated timing (weekly by default)
3. **Cloud Storage**: Pre/post-patch script storage
4. **Monitoring**: Dashboards and alerting for patch status

### Security Configuration

- VM instances use service accounts with minimal required permissions
- OS Config agent communicates securely with VM Manager
- Cloud Functions use environment-based configuration
- All storage buckets use Google-managed encryption

## Validation

After deployment, verify the infrastructure:

### Check VM Manager Status

```bash
# List all VM instances
gcloud compute instances list --filter="name:patch-test-vm"

# Check OS Config agent status
gcloud compute instances describe patch-test-vm-1 \
    --zone=${ZONE} \
    --format="value(metadata.items[key=enable-osconfig].value)"
```

### Verify Patch Management

```bash
# Check OS inventory collection
gcloud compute os-config inventories describe \
    --instance=patch-test-vm-1 \
    --instance-zone=${ZONE} \
    --format="table(updateTime,osInfo.shortName,osInfo.version)"

# List patch deployments
gcloud compute os-config patch-deployments list
```

### Test Cloud Function

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe patch-trigger \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test function (optional)
curl -X POST $FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"trigger":"test-patch-deployment"}'
```

### Verify Scheduler Job

```bash
# Check scheduler job status
gcloud scheduler jobs describe patch-deployment \
    --location=${REGION} \
    --format="table(name,schedule,state,lastAttemptTime)"

# Manually trigger for testing
gcloud scheduler jobs run patch-deployment --location=${REGION}
```

## Monitoring and Alerting

### Cloud Monitoring Dashboards

Access monitoring dashboards:

1. Go to Cloud Console → Monitoring
2. Find "VM Patch Management Dashboard"
3. Monitor patch deployment status and system health

### Alert Policies

The infrastructure creates alert policies for:

- Patch deployment failures
- VM instance availability
- OS Config agent health
- Cloud Function errors

### Logs and Debugging

View logs for troubleshooting:

```bash
# Cloud Function logs
gcloud functions logs read patch-trigger --region=${REGION}

# VM Manager logs
gcloud logging read "resource.type=gce_instance AND logName=projects/${PROJECT_ID}/logs/OSConfigAgent"

# Scheduler job logs
gcloud logging read "resource.type=cloud_scheduler_job AND resource.labels.job_id=patch-deployment"
```

## Customization

### Adding More VMs

To manage additional VMs:

1. **Tag existing VMs**: Add `patch-management` tag
2. **Update instance filters**: Modify patch deployment configurations
3. **Adjust monitoring**: Update dashboards for additional instances

### Custom Patch Scripts

Modify pre/post-patch scripts:

1. Edit `scripts/pre-patch-backup.sh` for custom backup logic
2. Edit `scripts/post-patch-validation.sh` for custom validation
3. Update Cloud Storage bucket with modified scripts

### Patch Scheduling

Customize patch deployment timing:

1. **Terraform**: Update `patch_schedule` variable
2. **Infrastructure Manager**: Modify scheduler configuration
3. **Scripts**: Edit Cloud Scheduler job creation

### Advanced Monitoring

Enhance monitoring capabilities:

1. Add custom metrics for patch compliance
2. Create additional alert policies
3. Integrate with external monitoring systems
4. Set up notification channels (email, SMS, etc.)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete patch-mgmt-deployment \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

Verify all resources are cleaned up:

```bash
# Check for remaining VMs
gcloud compute instances list --filter="name:patch-test-vm"

# Check for remaining functions
gcloud functions list --filter="name:patch-trigger"

# Check for remaining scheduler jobs
gcloud scheduler jobs list --filter="name:patch-deployment"

# Check for remaining storage buckets
gsutil ls -p ${PROJECT_ID} | grep patch-scripts
```

## Troubleshooting

### Common Issues

1. **VM Manager not working**:
   - Verify OS Config agent is enabled: `enable-osconfig=TRUE`
   - Check VM has proper service account permissions
   - Ensure OS Config API is enabled

2. **Patch deployment failing**:
   - Check Cloud Function logs for errors
   - Verify patch scripts are accessible in Cloud Storage
   - Ensure VMs have internet connectivity for updates

3. **Scheduler job not triggering**:
   - Verify scheduler job is in ENABLED state
   - Check Cloud Function permissions
   - Review scheduler job configuration

4. **Monitoring not showing data**:
   - Verify Cloud Monitoring API is enabled
   - Check metric collection delays (can take 5-10 minutes)
   - Ensure proper IAM permissions for monitoring

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:osconfig.googleapis.com"

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --format="table(bindings.role)" \
    --filter="bindings.members:*compute*"

# Test VM Manager connectivity
gcloud compute ssh patch-test-vm-1 --zone=${ZONE} \
    --command="sudo systemctl status google-osconfig-agent"
```

## Best Practices

1. **Security**:
   - Use least privilege IAM roles
   - Enable VPC firewall rules appropriately
   - Regularly update patch scripts
   - Monitor for failed patch deployments

2. **Operations**:
   - Test patch deployments in non-production first
   - Schedule patches during maintenance windows
   - Monitor system health after patching
   - Maintain backup and recovery procedures

3. **Cost Optimization**:
   - Use appropriate VM instance types
   - Clean up test resources regularly
   - Monitor Cloud Monitoring usage
   - Use sustained use discounts for long-running VMs

## Support

For issues with this infrastructure code:

1. Check the original recipe documentation
2. Review Google Cloud VM Manager documentation
3. Consult Google Cloud support for service-specific issues
4. Use `gcloud feedback` to report CLI issues

## Additional Resources

- [VM Manager Documentation](https://cloud.google.com/compute/docs/vm-manager)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Monitoring Documentation](https://cloud.google.com/monitoring/docs)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)