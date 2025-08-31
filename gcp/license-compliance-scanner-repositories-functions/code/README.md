# Infrastructure as Code for License Compliance Scanner with Source Repositories and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "License Compliance Scanner with Source Repositories and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Source Repositories Admin
  - Cloud Functions Admin
  - Storage Admin
  - Cloud Scheduler Admin
  - Service Account Admin
- Python 3.12 runtime support in target region

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Update the configuration file with your project details
sed -i "s/PROJECT_ID_PLACEHOLDER/${PROJECT_ID}/g" main.yaml
sed -i "s/REGION_PLACEHOLDER/${REGION}/g" main.yaml

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/license-scanner \
    --config-file=main.yaml \
    --project=${PROJECT_ID}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Plan the deployment
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Run deployment script
./scripts/deploy.sh
```

## Resource Overview

This infrastructure creates the following Google Cloud resources:

### Core Components
- **Cloud Source Repository**: Git repository for source code storage
- **Cloud Storage Bucket**: Storage for compliance reports with versioning
- **Cloud Function**: License scanning function with Python 3.12 runtime
- **Cloud Scheduler Jobs**: Automated scanning triggers (daily and weekly)

### Supporting Resources
- **Service Account**: Dedicated service account for Cloud Function
- **IAM Bindings**: Least privilege access permissions
- **API Enablement**: Required Google Cloud APIs

## Configuration Options

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Primary region for resources | `us-central1` | No |
| `zone` | Compute zone | `us-central1-a` | No |
| `bucket_versioning` | Enable bucket versioning | `true` | No |
| `function_memory` | Cloud Function memory allocation | `512` | No |
| `function_timeout` | Cloud Function timeout in seconds | `120` | No |
| `daily_schedule` | Cron schedule for daily scans | `0 9 * * 1-5` | No |
| `weekly_schedule` | Cron schedule for weekly scans | `0 6 * * 1` | No |

### Infrastructure Manager Parameters

Similar parameters are available in the Infrastructure Manager configuration file (`main.yaml`). Update the parameters section to customize your deployment.

## Sample Application Code

The infrastructure automatically creates a sample application with dependencies for testing:

- **Python dependencies**: Flask, requests, numpy, scancode-toolkit
- **Node.js dependencies**: express, lodash, moment, axios
- **License types**: MIT, BSD-3-Clause, Apache-2.0 (all permissive licenses)

## Testing the Deployment

After deployment, test the license scanner:

```bash
# Get the Cloud Function URL
FUNCTION_URL=$(gcloud functions describe license-scanner-function \
    --format="value(httpsTrigger.url)" \
    --region=${REGION})

# Trigger a manual scan
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"test": true}'

# Check for generated reports
gsutil ls gs://license-reports-*/reports/

# View the latest report
gsutil cp $(gsutil ls gs://license-reports-*/reports/ | tail -1) ./latest-report.json
cat latest-report.json | python3 -m json.tool
```

## Monitoring and Maintenance

### View Function Logs
```bash
gcloud functions logs read license-scanner-function \
    --region=${REGION} \
    --limit=50
```

### Check Scheduler Job Status
```bash
gcloud scheduler jobs list \
    --location=${REGION} \
    --format="table(name,schedule,state,lastAttemptTime)"
```

### Monitor Bucket Usage
```bash
gsutil du -sh gs://license-reports-*
gsutil ls -la gs://license-reports-*/reports/
```

## Cleanup

### Using Infrastructure Manager (GCP)

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/license-scanner \
    --project=${PROJECT_ID}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

## Security Considerations

### Implemented Security Features
- **Least Privilege IAM**: Service account with minimal required permissions
- **Bucket Versioning**: Audit trail for compliance reports
- **Function Authentication**: HTTP trigger with authentication controls
- **API Security**: Selective API enablement

### Additional Security Recommendations
- Enable Cloud Audit Logs for compliance tracking
- Implement VPC Service Controls for data perimeter security
- Use Cloud KMS for report encryption
- Set up Cloud Security Command Center for monitoring
- Configure Cloud IAM Conditions for fine-grained access control

## Cost Optimization

### Estimated Monthly Costs (Small Repository)
- Cloud Functions: $1-3 (based on execution frequency)
- Cloud Storage: $1-2 (report storage)
- Cloud Scheduler: $0.10 (job executions)
- Cloud Source Repositories: $1 (private repository)
- **Total**: $3-6 per month

### Cost Optimization Tips
- Adjust function memory allocation based on actual usage
- Implement lifecycle policies for old compliance reports
- Use regional storage for cost savings
- Monitor function execution times and optimize code
- Consider using Cloud Build for batch processing larger repositories

## Troubleshooting

### Common Issues

**Function Deployment Fails**
```bash
# Check quota limits
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Verify API enablement
gcloud services list --enabled
```

**Repository Access Issues**
```bash
# Check repository permissions
gcloud source repos get-iam-policy REPO_NAME

# Verify service account permissions
gcloud projects get-iam-policy PROJECT_ID
```

**Scheduler Job Failures**
```bash
# Check job execution history
gcloud scheduler jobs describe JOB_NAME --location=REGION

# View function logs for errors
gcloud functions logs read FUNCTION_NAME --region=REGION
```

**Storage Permission Errors**
```bash
# Verify bucket IAM policies
gsutil iam get gs://BUCKET_NAME

# Check service account key
gcloud iam service-accounts keys list --iam-account=SERVICE_ACCOUNT_EMAIL
```

## Customization Examples

### Adding Email Notifications

```bash
# Create a Pub/Sub topic for notifications
gcloud pubsub topics create license-compliance-alerts

# Update function to publish to topic on violations
# (Requires code modification)
```

### Integration with CI/CD

```bash
# Create additional Cloud Build trigger
gcloud builds triggers create cloud-source-repositories \
    --repo-name=REPO_NAME \
    --branch-pattern=main \
    --build-config=cloudbuild.yaml
```

### Multi-Repository Scanning

```bash
# Deploy additional repositories
for repo in repo1 repo2 repo3; do
    gcloud source repos create $repo
done

# Update function to iterate through multiple repositories
# (Requires code modification)
```

## Support and Documentation

- [Cloud Source Repositories Documentation](https://cloud.google.com/source-repositories/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)
- [ScanCode Toolkit Documentation](https://scancode-toolkit.readthedocs.io/)
- [SPDX License List](https://spdx.org/licenses/)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.

## License

This infrastructure code is provided as-is under the same license as the parent recipe repository.