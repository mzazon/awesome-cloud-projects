# Infrastructure as Code for Resource Tagging and Cost Allocation with Policy Simulator and Cloud Asset Inventory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Resource Tagging and Cost Allocation with Policy Simulator and Cloud Asset Inventory".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Organization-level access for creating organization policies
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Organization Policy Administrator
  - Asset Inventory Viewer
  - BigQuery Admin
  - Cloud Functions Admin
  - Pub/Sub Admin
  - Storage Admin
  - Billing Account User

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Deploy the infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments create resource-tagging-deployment \
    --location=us-central1 \
    --source=. \
    --input-values="project_id=$(gcloud config get-value project),organization_id=$(gcloud organizations list --format='value(name)' --limit=1)"

# Check deployment status
gcloud infra-manager deployments describe resource-tagging-deployment \
    --location=us-central1
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the deployment plan
terraform plan \
    -var="project_id=$(gcloud config get-value project)" \
    -var="organization_id=$(gcloud organizations list --format='value(name)' --limit=1)"

# Apply the configuration
terraform apply \
    -var="project_id=$(gcloud config get-value project)" \
    -var="organization_id=$(gcloud organizations list --format='value(name)' --limit=1)"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for necessary configuration values
```

## Architecture Overview

This infrastructure creates:

1. **Organization Policy Constraints**: Custom constraints requiring mandatory resource tags
2. **Cloud Asset Inventory**: Asset feeds for real-time resource monitoring
3. **Pub/Sub Topics**: Message queues for asset change notifications
4. **Cloud Functions**: Serverless functions for tag compliance monitoring and reporting
5. **BigQuery Dataset**: Data warehouse for cost allocation analytics
6. **Cloud Storage Bucket**: Storage for billing exports and reports
7. **IAM Roles**: Necessary service account permissions

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | Google Cloud project ID | Required |
| `organization_id` | Organization ID for policy constraints | Required |
| `region` | Primary deployment region | `us-central1` |
| `dataset_name` | BigQuery dataset name | Generated with random suffix |
| `required_tags` | List of mandatory resource tags | `["department", "cost_center", "environment", "project_code"]` |

### Terraform Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | Google Cloud project ID | Required |
| `organization_id` | Organization ID for policy constraints | Required |
| `region` | Primary deployment region | `us-central1` |
| `zone` | Primary deployment zone | `us-central1-a` |
| `dataset_name` | BigQuery dataset name | Generated with random suffix |
| `function_memory` | Cloud Function memory allocation | `256MB` |
| `function_timeout` | Cloud Function timeout | `60s` |

### Bash Script Environment Variables

The deployment script uses these environment variables (will prompt if not set):

- `PROJECT_ID`: Google Cloud project ID
- `ORGANIZATION_ID`: Organization ID for policies
- `REGION`: Deployment region
- `ZONE`: Deployment zone

## Cost Estimation

Expected monthly costs for this infrastructure:

- **BigQuery**: $5-20 (storage and query processing)
- **Cloud Functions**: $1-5 (execution time and invocations)
- **Cloud Storage**: $1-3 (bucket storage)
- **Pub/Sub**: $1-2 (message processing)
- **Asset Inventory**: Included in Google Cloud pricing
- **Policy Simulator**: Free

**Total estimated cost**: $8-30 per month depending on usage

## Validation

After deployment, verify the infrastructure:

1. **Check Organization Policies**:
   ```bash
   gcloud org-policies list --organization=$ORGANIZATION_ID
   ```

2. **Verify Asset Feed**:
   ```bash
   gcloud asset feeds list --organization=$ORGANIZATION_ID
   ```

3. **Test Cloud Functions**:
   ```bash
   gcloud functions describe tag-compliance-function --region=$REGION
   gcloud functions describe cost-allocation-reporter --region=$REGION
   ```

4. **Verify BigQuery Dataset**:
   ```bash
   bq ls $PROJECT_ID:cost_allocation_*
   ```

5. **Test Policy Enforcement**:
   ```bash
   # This should fail due to missing required tags
   gcloud compute instances create test-instance \
       --zone=$ZONE \
       --machine-type=e2-micro \
       --image-family=debian-11 \
       --image-project=debian-cloud
   ```

## Usage

### Creating Compliant Resources

All resources must include the four required tags:

```bash
gcloud compute instances create compliant-instance \
    --zone=$ZONE \
    --machine-type=e2-micro \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --labels=department=engineering,cost_center=cc-001,environment=production,project_code=proj-123
```

### Generating Cost Reports

The automated reporting function can be triggered manually:

```bash
curl -X GET "https://$REGION-$PROJECT_ID.cloudfunctions.net/cost-allocation-reporter"
```

### Querying Cost Allocation Data

Access BigQuery views for cost analysis:

```sql
-- View compliance summary
SELECT * FROM `PROJECT_ID.DATASET_NAME.compliance_summary`
WHERE compliance_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY);

-- View cost allocation summary
SELECT * FROM `PROJECT_ID.DATASET_NAME.cost_allocation_summary`
WHERE billing_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY total_cost DESC;
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete resource-tagging-deployment \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="project_id=$(gcloud config get-value project)" \
    -var="organization_id=$(gcloud organizations list --format='value(name)' --limit=1)"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Organization Policy Permissions**: Ensure you have Organization Policy Administrator role
2. **Billing Export**: Configure billing export manually in Cloud Console if needed
3. **Function Deployment**: Check Cloud Build API is enabled for function deployment
4. **Asset Feed Creation**: Verify Asset Inventory API is enabled

### Debug Commands

```bash
# Check enabled APIs
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy $PROJECT_ID

# Check function logs
gcloud functions logs read tag-compliance-function --region=$REGION

# Monitor Pub/Sub messages
gcloud pubsub subscriptions create debug-subscription --topic=asset-changes
gcloud pubsub subscriptions pull debug-subscription --auto-ack
```

## Security Considerations

- Organization policies are applied at the organization level and affect all projects
- Service accounts use least privilege IAM roles
- BigQuery datasets are configured with appropriate access controls
- Cloud Functions are deployed with minimum required permissions
- All resources are tagged for proper cost allocation and governance

## Customization

### Adding Additional Resource Types

Modify the organization policy constraint to include additional resource types:

```yaml
resourceTypes:
- compute.googleapis.com/Instance
- storage.googleapis.com/Bucket
- container.googleapis.com/Cluster
- sql.googleapis.com/Instance  # Add Cloud SQL
- redis.googleapis.com/Instance  # Add Memorystore
```

### Custom Tag Requirements

Update the mandatory tags list in the configuration:

```yaml
condition: |
  has(resource.labels.department) &&
  has(resource.labels.cost_center) &&
  has(resource.labels.environment) &&
  has(resource.labels.project_code) &&
  has(resource.labels.owner)  # Add owner requirement
```

### Extended Reporting

Enhance the reporting function to include additional metrics:

- Resource type distribution
- Compliance trends over time
- Cost per business unit
- Tag utilization statistics

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Status page for service issues
3. Verify IAM permissions and API enablement
4. Consult Google Cloud documentation for specific services
5. Use `gcloud feedback` to report Google Cloud CLI issues

## Related Resources

- [Google Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs)
- [Organization Policy Constraints](https://cloud.google.com/resource-manager/docs/organization-policy/overview)
- [Policy Simulator](https://cloud.google.com/policy-intelligence/docs/iam-simulator-overview)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)
- [Resource Tagging Best Practices](https://cloud.google.com/resource-manager/docs/tags/tags-overview)