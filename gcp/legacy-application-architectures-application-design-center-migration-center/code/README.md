# Infrastructure as Code for Legacy Application Architectures with Application Design Center and Migration Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Legacy Application Architectures with Application Design Center and Migration Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Terraform 1.0+ installed (for Terraform implementation)
- Appropriate GCP permissions for resource creation:
  - Migration Center Admin
  - Application Design Center Admin
  - Cloud Build Editor
  - Cloud Deploy Admin
  - Cloud Run Admin
  - Service Usage Admin
  - Project Editor
- Docker installed for local containerization
- Git configured for source repository operations
- Estimated cost: $50-100 for resources during development and testing

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/legacy-modernization \
    --service-account=$SERVICE_ACCOUNT \
    --local-source="."

# Check deployment status
gcloud infra-manager deployments describe projects/$PROJECT_ID/locations/$REGION/deployments/legacy-modernization
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review deployment plan
terraform plan \
    -var="project_id=$PROJECT_ID" \
    -var="region=$REGION"

# Apply infrastructure
terraform apply \
    -var="project_id=$PROJECT_ID" \
    -var="region=$REGION"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Follow the interactive prompts to complete deployment
```

## Architecture Overview

This infrastructure deployment creates:

- **Migration Center**: Discovery source and client for legacy application assessment
- **Application Design Center**: Collaborative space for application modernization design
- **Cloud Source Repositories**: Git repository for modernized application code
- **Cloud Build**: CI/CD pipeline with automated triggers
- **Cloud Deploy**: Multi-environment deployment pipeline
- **Cloud Run**: Serverless container hosting for modernized applications
- **Cloud Monitoring**: Observability and alerting for deployed services

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  app_name:
    description: "Application name prefix"
    type: string
    default: "legacy-app"
```

### Terraform Variables

Configure via `terraform.tfvars` or command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
app_name = "legacy-app"
repository_name = "modernized-apps"
service_name = "modernized-service"
```

### Bash Script Variables

Set environment variables before running:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export APP_NAME="legacy-app"
export REPOSITORY_NAME="modernized-apps"
export SERVICE_NAME="modernized-service"
```

## Post-Deployment Steps

After infrastructure deployment, complete these manual steps:

1. **Configure Discovery Client**: Deploy the Migration Center discovery client in your legacy environment
2. **Design Application Architecture**: Use Application Design Center to create modernized application designs
3. **Upload Application Code**: Push your application code to the created source repository
4. **Configure Monitoring**: Set up custom dashboards and alerting policies
5. **Test CI/CD Pipeline**: Trigger builds and deployments to validate the pipeline

## Validation Commands

Verify the deployment with these commands:

```bash
# Check Migration Center resources
gcloud migration-center sources list --location=$REGION

# Verify Application Design Center
gcloud application-design-center spaces list --location=$REGION

# Check Cloud Build triggers
gcloud builds triggers list

# Verify Cloud Deploy pipeline
gcloud deploy delivery-pipelines list --region=$REGION

# Test Cloud Run service
gcloud run services list --region=$REGION
```

## Monitoring and Observability

The deployment includes:

- **Cloud Monitoring Dashboard**: Pre-configured dashboard for application metrics
- **Alert Policies**: Automated alerts for error rates and performance issues
- **Cloud Logging**: Centralized logging for all services
- **Cloud Trace**: Request tracing for performance analysis

Access monitoring resources:

```bash
# View monitoring dashboards
gcloud monitoring dashboards list

# Check alert policies
gcloud alpha monitoring policies list

# View recent logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/legacy-modernization

# Verify deletion
gcloud infra-manager deployments list --location=$REGION
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy \
    -var="project_id=$PROJECT_ID" \
    -var="region=$REGION"

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

## Troubleshooting

### Common Issues

1. **API Enablement**: Ensure all required APIs are enabled:
   ```bash
   gcloud services enable migrationcenter.googleapis.com \
       applicationdesigncenter.googleapis.com \
       cloudbuild.googleapis.com \
       clouddeploy.googleapis.com \
       run.googleapis.com
   ```

2. **IAM Permissions**: Verify service account has required permissions:
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **Resource Quotas**: Check regional quotas for Cloud Run and other services:
   ```bash
   gcloud compute project-info describe --project=$PROJECT_ID
   ```

### Debug Commands

```bash
# Check deployment logs
gcloud logging read "resource.type=gce_instance OR resource.type=cloud_function" --limit=100

# Verify API enablement
gcloud services list --enabled --filter="name:migrationcenter OR name:applicationdesigncenter"

# Check service account permissions
gcloud iam service-accounts get-iam-policy $SERVICE_ACCOUNT_EMAIL
```

## Security Considerations

This deployment implements security best practices:

- **Least Privilege IAM**: Service accounts with minimal required permissions
- **VPC Security**: Proper network segmentation and firewall rules
- **Data Encryption**: Encryption at rest and in transit for all services
- **Secret Management**: Secure storage of API keys and credentials
- **Audit Logging**: Comprehensive audit trails for all operations

## Cost Optimization

To minimize costs:

1. **Use Resource Labels**: All resources are tagged for cost tracking
2. **Set Auto-scaling Limits**: Cloud Run services have configured maximum instances
3. **Enable Monitoring Alerts**: Cost-based alerts prevent unexpected charges
4. **Clean Up Regularly**: Use provided cleanup scripts to remove unused resources

## Support and Documentation

- [Migration Center Documentation](https://cloud.google.com/migration-center/docs)
- [Application Design Center Guide](https://cloud.google.com/application-design-center/docs)
- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Cloud Deploy Documentation](https://cloud.google.com/deploy/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

For issues with this infrastructure code, refer to the original recipe documentation or the respective service documentation.

## Contributing

To enhance this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any new variables or outputs
3. Ensure security best practices are maintained
4. Validate with terraform plan/validate before committing

## License

This infrastructure code is provided as part of the cloud recipes repository. Refer to the main repository license for usage terms.