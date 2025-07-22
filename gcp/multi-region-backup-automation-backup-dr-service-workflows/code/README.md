# Infrastructure as Code for Multi-Region Backup Automation with Backup and DR Service and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Region Backup Automation with Backup and DR Service and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v450.0.0 or later installed and configured
- Google Cloud project with billing enabled
- Required APIs enabled: Backup and DR API, Cloud Workflows API, Cloud Scheduler API, Cloud Monitoring API, Compute Engine API
- Appropriate IAM permissions for:
  - Backup and DR Service administration
  - Cloud Workflows creation and execution
  - Cloud Scheduler job management
  - Cloud Monitoring configuration
  - Compute Engine instance management
  - Service Account creation and management

## Cost Considerations

This implementation will create resources that incur costs:
- Backup and DR Service storage ($0.023/GB/month for standard backups)
- Cloud Workflows executions ($0.01 per 1000 executions)
- Cloud Scheduler jobs ($0.10 per job per month)
- Compute Engine instances for testing (varies by machine type and region)
- Cloud Monitoring (free tier available, additional charges for high-volume metrics)

Estimated monthly cost: $50-100 depending on backup data volume and execution frequency.

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"

# Create deployment
gcloud infra-manager deployments create backup-automation-deployment \
    --location=${PRIMARY_REGION} \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},primary_region=${PRIMARY_REGION},secondary_region=${SECONDARY_REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe backup-automation-deployment \
    --location=${PRIMARY_REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your values
cat > terraform.tfvars << EOF
project_id = "your-project-id"
primary_region = "us-central1"
secondary_region = "us-east1"
backup_vault_primary = "backup-vault-primary"
backup_vault_secondary = "backup-vault-secondary"
EOF

# Review the deployment plan
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"

# Run deployment script
./scripts/deploy.sh
```

## Configuration Options

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `primary_region` | Primary region for backup operations | `us-central1` | No |
| `secondary_region` | Secondary region for backup replication | `us-east1` | No |
| `backup_vault_primary` | Name for primary backup vault | `backup-vault-primary` | No |
| `backup_vault_secondary` | Name for secondary backup vault | `backup-vault-secondary` | No |
| `backup_retention_days` | Minimum retention period for backups | `30` | No |
| `backup_schedule` | Cron schedule for automated backups | `0 2 * * *` | No |
| `validation_schedule` | Cron schedule for backup validation | `0 3 * * 0` | No |
| `enable_monitoring` | Enable Cloud Monitoring dashboard and alerts | `true` | No |
| `instance_machine_type` | Machine type for test instance | `e2-medium` | No |
| `instance_disk_size_gb` | Boot disk size for test instance | `20` | No |

### Infrastructure Manager Inputs

The Infrastructure Manager deployment accepts the same variables as Terraform through the `--input-values` parameter:

```bash
gcloud infra-manager deployments create backup-automation-deployment \
    --location=${PRIMARY_REGION} \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},primary_region=${PRIMARY_REGION},secondary_region=${SECONDARY_REGION},backup_retention_days=30,enable_monitoring=true"
```

## Deployment Architecture

The IaC implementations deploy the following components:

### Core Infrastructure
- **Service Account**: Dedicated service account with minimal required permissions for backup operations
- **IAM Bindings**: Proper role assignments for backup automation and workflow execution
- **Backup Vaults**: Multi-region backup vaults with enforced retention policies

### Automation Layer
- **Cloud Workflows**: Serverless orchestration for backup operations across regions
- **Cloud Scheduler**: Automated scheduling for regular backup execution and validation
- **Test Resources**: Sample Compute Engine instance and persistent disk for testing

### Monitoring & Observability
- **Cloud Monitoring Dashboard**: Custom dashboard for backup operation visibility
- **Alert Policies**: Automated alerts for backup failures and performance issues
- **Log-based Metrics**: Custom metrics for backup success rates and execution times

## Validation

After deployment, verify the infrastructure:

### Check Backup Vaults
```bash
# List backup vaults in both regions
gcloud backup-dr backup-vaults list --format="table(name,location,state)"
```

### Verify Workflows
```bash
# List deployed workflows
gcloud workflows list --format="table(name,location,state)"
```

### Test Scheduler Jobs
```bash
# List scheduler jobs
gcloud scheduler jobs list --format="table(name,location,state,schedule)"
```

### Monitor Dashboard
```bash
# List monitoring dashboards
gcloud monitoring dashboards list --filter="displayName:*Backup*"
```

## Testing the Solution

### Manual Workflow Execution
```bash
# Get workflow name from terraform output or infrastructure manager
export WORKFLOW_NAME="backup-workflow-xxxxx"

# Execute workflow manually
gcloud workflows run ${WORKFLOW_NAME} \
    --location=${PRIMARY_REGION} \
    --data='{"backup_type": "manual_test"}'
```

### Verify Backup Creation
```bash
# Check backup plans and executions
gcloud backup-dr backup-plans list --location=${PRIMARY_REGION}
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete backup-automation-deployment \
    --location=${PRIMARY_REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${PRIMARY_REGION}
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm when prompted
```

### Using Bash Scripts
```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup (if needed)
If automated cleanup fails, manually remove resources:

```bash
# Delete scheduler jobs
gcloud scheduler jobs delete backup-scheduler-* --location=${PRIMARY_REGION} --quiet

# Delete workflows
gcloud workflows delete backup-workflow-* --location=${PRIMARY_REGION} --quiet

# Delete backup vaults (may take several minutes)
gcloud backup-dr backup-vaults delete backup-vault-primary --location=${PRIMARY_REGION} --quiet
gcloud backup-dr backup-vaults delete backup-vault-secondary --location=${SECONDARY_REGION} --quiet

# Delete test instances
gcloud compute instances delete backup-test-instance --zone=${PRIMARY_REGION}-a --quiet

# Delete service accounts
gcloud iam service-accounts delete backup-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Customization

### Modifying Backup Schedules
Edit the schedule variables in your configuration:
- `backup_schedule`: Change the cron expression for regular backups
- `validation_schedule`: Modify validation timing

### Adding Additional Regions
To support more regions:
1. Add new backup vault configurations
2. Update workflow definitions to include additional regions
3. Modify scheduler jobs for cross-region operations

### Custom Backup Policies
Extend the workflow definitions to implement:
- Resource-specific backup policies based on labels
- Conditional backup strategies
- Custom retention periods per workload type

### Enhanced Monitoring
Add custom metrics and alerts:
- Backup size trending
- Cross-region replication latency
- Cost optimization alerts
- Compliance reporting metrics

## Troubleshooting

### Common Issues

**Backup Vault Creation Fails**
- Verify Backup and DR API is enabled
- Check IAM permissions for service account
- Ensure regions support Backup and DR Service

**Workflow Execution Errors**
- Review workflow execution logs in Cloud Logging
- Verify service account has necessary permissions
- Check API quotas and limits

**Scheduler Job Failures**
- Validate OAuth service account configuration
- Check workflow endpoint URLs
- Review Cloud Scheduler logs

**Monitoring Setup Issues**
- Ensure Cloud Monitoring API is enabled
- Verify dashboard creation permissions
- Check alert notification channel configuration

### Getting Help

For additional support:
- Review Google Cloud Backup and DR Service documentation
- Check Cloud Workflows troubleshooting guides
- Consult Cloud Monitoring setup documentation
- Reference the original recipe for step-by-step implementation

## Security Considerations

This implementation follows security best practices:
- **Least Privilege**: Service accounts have minimal required permissions
- **Encryption**: All backups are encrypted at rest and in transit
- **Access Control**: Backup vaults enforce retention policies
- **Audit Logging**: All operations are logged for compliance
- **Network Security**: Resources use private networking where possible

## Performance Optimization

Consider these optimizations for production use:
- **Regional Placement**: Place backup vaults close to source data
- **Backup Windows**: Schedule during low-traffic periods
- **Retention Policies**: Implement lifecycle management for cost optimization
- **Parallel Processing**: Use workflow parallelism for large-scale backups
- **Monitoring Thresholds**: Set appropriate alert thresholds for your SLAs

## Support

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud provider documentation
3. Consult Terraform Google Cloud provider guides
4. Reference Infrastructure Manager documentation

This IaC implementation provides a production-ready foundation for multi-region backup automation that can be customized to meet specific organizational requirements.