# Infrastructure as Code for Multi-Cloud Resource Discovery with Cloud Location Finder and Pub/Sub

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Cloud Resource Discovery with Cloud Location Finder and Pub/Sub".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud Platform account with billing enabled and project owner permissions
- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Terraform (if using Terraform implementation) version 1.5.0 or later
- Appropriate permissions for resource creation:
  - Cloud Location Finder API access
  - Pub/Sub Admin
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Storage Admin
  - Monitoring Admin

## Quick Start

### Using Infrastructure Manager (Recommended)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-cloud-discovery \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-org/your-repo" \
    --git-source-directory="gcp/multi-cloud-resource-discovery-location-finder-pub-sub/code/infrastructure-manager" \
    --git-source-ref="main"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# View deployment status
gcloud functions list
gcloud pubsub topics list
gcloud scheduler jobs list
```

## Architecture Overview

This infrastructure deploys a complete multi-cloud resource discovery system with the following components:

- **Cloud Location Finder API**: Aggregates location data across Google Cloud, AWS, Azure, and OCI
- **Pub/Sub Topic & Subscription**: Handles asynchronous processing of location data
- **Cloud Functions**: Processes location intelligence and generates recommendations
- **Cloud Storage**: Stores location reports and historical data
- **Cloud Scheduler**: Automates periodic location discovery
- **Cloud Monitoring**: Provides observability and alerting

## Configuration

### Environment Variables

The following environment variables can be customized:

| Variable | Description | Default |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud Project ID | Required |
| `REGION` | Deployment region | `us-central1` |
| `ZONE` | Deployment zone | `us-central1-a` |
| `FUNCTION_TIMEOUT` | Function timeout in seconds | `300` |
| `FUNCTION_MEMORY` | Function memory allocation | `512MB` |
| `SCHEDULE_FREQUENCY` | Discovery schedule (cron format) | `0 */6 * * *` |

### Terraform Variables

When using Terraform, customize the deployment by modifying `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
function_timeout_seconds = 300
function_memory_mb      = 512
schedule_frequency      = "0 */6 * * *"
enable_monitoring      = true
storage_location       = "US"
```

### Infrastructure Manager Variables

For Infrastructure Manager deployments, update the input values in the deployment configuration:

```yaml
inputValues:
  project_id:
    inputValue: "your-project-id"
  region:
    inputValue: "us-central1"
  zone:
    inputValue: "us-central1-a"
```

## Monitoring and Observability

The deployed infrastructure includes comprehensive monitoring:

### Custom Metrics

- `custom.googleapis.com/multicloud/total_locations`: Total locations discovered
- Function execution metrics via Cloud Functions monitoring
- Pub/Sub message processing metrics

### Dashboards

A pre-configured Cloud Monitoring dashboard provides visibility into:
- Location discovery trends
- Function execution performance
- Message processing rates
- Error rates and latencies

### Alerts

Alert policies monitor:
- Function execution failures
- Message processing delays
- API quota exhaustion
- Storage access errors

## Testing the Deployment

### Verify Core Components

```bash
# Check if APIs are enabled
gcloud services list --enabled --filter="name:cloudlocationfinder.googleapis.com OR name:pubsub.googleapis.com OR name:cloudfunctions.googleapis.com"

# Verify Pub/Sub topic creation
gcloud pubsub topics list --filter="name:location-discovery"

# Check Cloud Function status
gcloud functions list --filter="name:process-locations"

# Verify Cloud Scheduler job
gcloud scheduler jobs list --filter="name:location-sync"
```

### Test Manual Execution

```bash
# Trigger manual location discovery
gcloud scheduler jobs run location-sync-[suffix]

# Monitor function logs
gcloud functions logs read process-locations-[suffix] --limit=10

# Check generated reports
gsutil ls gs://location-reports-[suffix]/reports/
```

### Validate Data Flow

```bash
# Publish test message
gcloud pubsub topics publish location-discovery-[suffix] \
    --message='{"trigger":"test","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'

# Verify message processing
sleep 30
gcloud functions logs read process-locations-[suffix] --limit=5
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-cloud-discovery
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completion
gcloud functions list
gcloud pubsub topics list
gcloud scheduler jobs list
gsutil ls gs://location-reports-*
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining resources
gcloud functions delete process-locations-[suffix] --region=${REGION} --quiet
gcloud pubsub subscriptions delete location-discovery-[suffix]-sub --quiet
gcloud pubsub topics delete location-discovery-[suffix] --quiet
gcloud scheduler jobs delete location-sync-[suffix] --quiet
gsutil -m rm -r gs://location-reports-[suffix]

# Remove monitoring resources
gcloud monitoring dashboards list --filter="displayName:'Multi-Cloud Location Discovery Dashboard'"
gcloud alpha monitoring policies list --filter="displayName:'Location Discovery Function Failures'"
```

## Cost Optimization

### Estimated Costs

| Resource | Monthly Cost (USD) | Notes |
|----------|-------------------|--------|
| Cloud Functions | $5-15 | Based on 6-hour execution schedule |
| Pub/Sub | $1-3 | Message volume dependent |
| Cloud Storage | $1-5 | Report storage and retention |
| Cloud Scheduler | $0.10 | Per job execution |
| Cloud Monitoring | $2-8 | Custom metrics and dashboards |

### Cost Reduction Strategies

1. **Adjust Discovery Frequency**: Modify the scheduler to run less frequently
2. **Function Memory Optimization**: Reduce memory allocation if processing is CPU-bound
3. **Storage Lifecycle**: Implement lifecycle policies for old reports
4. **Monitoring Optimization**: Reduce custom metric retention periods

## Troubleshooting

### Common Issues

**Function Deployment Failures**
```bash
# Check function logs for deployment errors
gcloud functions logs read process-locations-[suffix] --limit=20

# Verify required APIs are enabled
gcloud services list --enabled --filter="cloudfunctions.googleapis.com"
```

**Pub/Sub Message Processing Issues**
```bash
# Check subscription backlog
gcloud pubsub subscriptions describe location-discovery-[suffix]-sub

# Monitor message flow
gcloud pubsub topics publish location-discovery-[suffix] --message='{"test": true}'
```

**Storage Access Problems**
```bash
# Verify bucket permissions
gsutil iam get gs://location-reports-[suffix]

# Test bucket access
gsutil ls gs://location-reports-[suffix]
```

**API Quota Issues**
```bash
# Check quota usage
gcloud logging read 'protoPayload.methodName="google.cloud.location.finder.v1.LocationFinderService.GetLocations"' --limit=10

# Monitor API usage in Cloud Console
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug environment variable for Cloud Function
gcloud functions deploy process-locations-[suffix] \
    --set-env-vars DEBUG=true,LOG_LEVEL=DEBUG \
    --update-env-vars
```

## Security Considerations

### IAM Best Practices

- Function uses minimal required permissions
- Service accounts follow principle of least privilege
- Pub/Sub subscriptions are private to the project
- Storage buckets use uniform bucket-level access

### Data Security

- All data is encrypted at rest using Google-managed keys
- Location data is processed within Google Cloud boundaries
- No sensitive data is logged in function execution

### Network Security

- Functions run in Google's secure serverless environment
- Pub/Sub messages are encrypted in transit
- Storage access uses authenticated requests only

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example Cloud Build configuration
steps:
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        cd terraform/
        terraform init
        terraform plan
        terraform apply -auto-approve
```

### Monitoring Integration

```bash
# Export metrics to external systems
gcloud monitoring metrics list --filter="custom.googleapis.com/multicloud" \
    --format="json" > metrics_export.json
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../multi-cloud-resource-discovery-location-finder-pub-sub.md)
2. Review [Google Cloud Location Finder documentation](https://cloud.google.com/location-finder/docs)
3. Consult [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
4. Reference [Pub/Sub best practices](https://cloud.google.com/pubsub/docs/best-practices)

## Contributing

When modifying this infrastructure:

1. Test changes in a development project
2. Update documentation for any new variables or outputs
3. Validate security configurations
4. Update cost estimates if resource requirements change
5. Ensure backward compatibility with existing deployments