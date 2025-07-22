# Infrastructure as Code for Infrastructure Change Monitoring with Cloud Asset Inventory and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Infrastructure Change Monitoring with Cloud Asset Inventory and Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Project Editor role or custom role with the following permissions:
  - Cloud Asset Inventory Admin (`roles/cloudasset.admin`)
  - Pub/Sub Admin (`roles/pubsub.admin`)
  - Cloud Functions Admin (`roles/cloudfunctions.admin`)
  - BigQuery Admin (`roles/bigquery.admin`)
  - Monitoring Admin (`roles/monitoring.admin`)
  - Service Account User (`roles/iam.serviceAccountUser`)
- For Terraform: Terraform installed (version 1.0+)
- Estimated cost: $20-50/month for moderate infrastructure monitoring

> **Note**: Cloud Asset Inventory feeds can take up to 10 minutes to become active and begin publishing messages.

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Enable required APIs
gcloud services enable cloudasset.googleapis.com \
    pubsub.googleapis.com \
    cloudfunctions.googleapis.com \
    bigquery.googleapis.com \
    monitoring.googleapis.com \
    config.googleapis.com

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/infrastructure-monitoring \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Enable required APIs
gcloud services enable cloudasset.googleapis.com \
    pubsub.googleapis.com \
    cloudfunctions.googleapis.com \
    bigquery.googleapis.com \
    monitoring.googleapis.com

# Deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This solution deploys:

1. **Cloud Asset Inventory Feed**: Monitors all resource changes in real-time
2. **Pub/Sub Topic & Subscription**: Handles asset change event messaging
3. **Cloud Function**: Processes change events and transforms data
4. **BigQuery Dataset & Table**: Stores audit trail for compliance reporting
5. **Cloud Monitoring Alerts**: Provides proactive notification of critical changes

## Configuration Options

### Infrastructure Manager Variables

Edit the `terraform.tfvars` file in the `infrastructure-manager/` directory:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
topic_name         = "infrastructure-changes"
dataset_name       = "infrastructure_audit"
function_name      = "process-asset-changes"
feed_name          = "infrastructure-feed"
alert_threshold    = 10
```

### Terraform Variables

Set variables via command line, `terraform.tfvars` file, or environment variables:

```bash
# Via command line
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1" \
    -var="alert_threshold=15"

# Via terraform.tfvars file
echo 'project_id = "your-project-id"' > terraform.tfvars
echo 'region = "us-central1"' >> terraform.tfvars
```

### Bash Script Environment Variables

The deploy script uses these environment variables (with defaults):

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"
export TOPIC_NAME="infrastructure-changes"
export DATASET_NAME="infrastructure_audit"
export FUNCTION_NAME="process-asset-changes"
export FEED_NAME="infrastructure-feed"
```

## Validation & Testing

After deployment, validate the solution:

1. **Check Asset Feed Status**:
   ```bash
   gcloud asset feeds list --project=${PROJECT_ID}
   ```

2. **Test Change Detection**:
   ```bash
   # Create a test resource
   gcloud compute addresses create test-address --region=${REGION}
   
   # Wait for processing
   sleep 30
   
   # Query BigQuery for the change
   bq query --use_legacy_sql=false \
   "SELECT timestamp, asset_name, change_type 
    FROM \`${PROJECT_ID}.${DATASET_NAME}.asset_changes\` 
    WHERE asset_name LIKE '%test-address%' 
    ORDER BY timestamp DESC LIMIT 5"
   
   # Clean up
   gcloud compute addresses delete test-address --region=${REGION} --quiet
   ```

3. **Verify Function Logs**:
   ```bash
   gcloud functions logs read ${FUNCTION_NAME} --limit=10
   ```

## Monitoring & Alerting

The solution includes:

- **Custom Metrics**: Infrastructure change rates and patterns
- **Alert Policies**: Notifications for high change volumes (>10 changes/5min by default)
- **BigQuery Analytics**: Historical trend analysis and compliance reporting

Access monitoring dashboards:
```bash
# View custom metrics
gcloud logging read "resource.type=cloud_function" --limit=10

# List alert policies
gcloud alpha monitoring policies list
```

## Compliance & Security

### Data Protection
- BigQuery dataset includes column-level security
- Asset change data is encrypted at rest and in transit
- IAM roles follow least privilege principle

### Audit Trail
- Complete audit trail stored in BigQuery with timestamp precision
- Change history includes before/after states for compliance
- Asset lineage tracking via ancestors field

### Retention Policy
Configure BigQuery table expiration for compliance requirements:
```bash
bq update --time_partitioning_expiration 7776000 ${PROJECT_ID}:${DATASET_NAME}.asset_changes
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/infrastructure-monitoring
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Remove asset feed
gcloud asset feeds delete ${FEED_NAME} --project=${PROJECT_ID}

# Remove Cloud Function
gcloud functions delete ${FUNCTION_NAME} --quiet

# Remove Pub/Sub resources
gcloud pubsub subscriptions delete ${SUBSCRIPTION_NAME}
gcloud pubsub topics delete ${TOPIC_NAME}

# Remove BigQuery dataset
bq rm -r -f ${PROJECT_ID}:${DATASET_NAME}

# Remove alert policies (list and delete manually)
gcloud alpha monitoring policies list
```

## Troubleshooting

### Common Issues

1. **Asset Feed Not Receiving Messages**:
   - Verify Pub/Sub topic exists and has correct permissions
   - Check Asset Inventory API is enabled
   - Ensure feed configuration includes correct content type

2. **Cloud Function Errors**:
   - Check function logs: `gcloud functions logs read ${FUNCTION_NAME}`
   - Verify IAM permissions for BigQuery and Monitoring
   - Ensure environment variables are set correctly

3. **BigQuery Insert Failures**:
   - Verify dataset and table exist
   - Check table schema matches function expectations
   - Ensure BigQuery API is enabled

4. **Missing Change Events**:
   - Asset feeds can take up to 10 minutes to activate
   - Some resource types may not be supported by Asset Inventory
   - Check feed configuration for asset type filters

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled | grep -E "(asset|pubsub|functions|bigquery)"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Test Pub/Sub message flow
gcloud pubsub topics publish ${TOPIC_NAME} --message="test message"

# Check function deployment status
gcloud functions describe ${FUNCTION_NAME}
```

## Performance Optimization

### Scaling Considerations

- **Pub/Sub**: Automatically scales based on message volume
- **Cloud Functions**: Adjust memory allocation based on processing requirements
- **BigQuery**: Consider partitioning large audit tables by date
- **Asset Feeds**: Use asset type filters to reduce message volume

### Cost Optimization

- Configure BigQuery table expiration policies
- Use Pub/Sub message filtering to reduce function invocations
- Implement Cloud Function timeout optimization
- Consider regional resource placement for data locality

## Customization

### Extending Functionality

1. **Add Resource Type Filtering**:
   ```bash
   # Modify asset feed to monitor specific resource types
   gcloud asset feeds update ${FEED_NAME} \
       --asset-types="compute.googleapis.com/Instance,storage.googleapis.com/Bucket"
   ```

2. **Custom Alert Conditions**:
   - Modify alert policies for specific resource types
   - Add notification channels (email, Slack, PagerDuty)
   - Implement multi-condition alerts

3. **Enhanced Analytics**:
   - Create Looker Studio dashboards
   - Add Data Studio compliance reports
   - Implement BigQuery ML for anomaly detection

4. **Integration Patterns**:
   - Connect to Security Command Center
   - Integrate with Cloud Workflows for automated response
   - Add webhook notifications for external systems

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Asset Inventory [documentation](https://cloud.google.com/asset-inventory/docs)
3. Refer to Pub/Sub [best practices](https://cloud.google.com/pubsub/docs/best-practices)
4. Consult Cloud Functions [troubleshooting guide](https://cloud.google.com/functions/docs/troubleshooting)
5. Review BigQuery [operations guide](https://cloud.google.com/bigquery/docs/best-practices-storage)

For infrastructure-specific issues, consult the respective tool documentation:
- [Infrastructure Manager](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)