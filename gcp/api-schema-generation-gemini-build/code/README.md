# Infrastructure as Code for API Schema Generation with Gemini Code Assist and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Schema Generation with Gemini Code Assist and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with comprehensive error handling

## Architecture Overview

This solution deploys an automated API documentation pipeline that:
- Analyzes source code using AI-powered analysis
- Generates OpenAPI schemas automatically via Cloud Build
- Validates schemas against industry standards
- Stores documentation artifacts in Cloud Storage
- Provides monitoring and alerting capabilities

## Prerequisites

### General Requirements
- Google Cloud project with billing enabled
- gcloud CLI installed and configured (or Cloud Shell)
- Appropriate IAM permissions for resource creation:
  - Cloud Build Editor
  - Cloud Functions Developer
  - Storage Admin
  - Service Account User
  - Project IAM Admin

### Tool-Specific Requirements

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Terraform configuration management understanding

#### Terraform
- Terraform >= 1.5.0 installed
- Google Cloud provider >= 4.84.0

#### Scripts
- Bash shell environment
- jq for JSON processing
- curl for API testing

## Quick Start

### Using Infrastructure Manager

```bash
# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/us-central1/deployments/api-schema-pipeline \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source=infrastructure-manager/ \
    --inputs-file=infrastructure-manager/terraform.tfvars
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow interactive prompts for configuration
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
```

### Customizable Parameters

| Parameter | Description | Default | Type |
|-----------|-------------|---------|------|
| `project_id` | Google Cloud Project ID | Required | string |
| `region` | Primary deployment region | us-central1 | string |
| `zone` | Primary deployment zone | us-central1-a | string |
| `bucket_name` | Cloud Storage bucket name | auto-generated | string |
| `function_memory` | Cloud Function memory allocation | 512MB | string |
| `function_timeout` | Cloud Function timeout | 120s | string |
| `build_timeout` | Cloud Build timeout | 600s | string |
| `enable_monitoring` | Enable monitoring dashboard | true | bool |

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bucket_name = "custom-api-schemas-bucket"
function_memory = "1024MB"
enable_monitoring = true

# Tags for resource organization
labels = {
  environment = "production"
  team        = "api-team"
  purpose     = "schema-generation"
}
```

## Deployed Resources

### Core Infrastructure
- **Cloud Storage Bucket**: Stores generated schemas and build artifacts
- **Cloud Functions**: 
  - Schema generator with Gemini Code Assist integration
  - Schema validator for quality control
- **Cloud Build**: Automated pipeline with triggers and validation
- **IAM Roles**: Service accounts with least privilege access

### Monitoring & Observability
- **Cloud Monitoring**: Dashboard for pipeline metrics
- **Cloud Logging**: Centralized log aggregation
- **Alerting Policies**: Notifications for build failures and validation errors

### Security
- **Service Accounts**: Dedicated accounts for each service
- **IAM Bindings**: Minimal required permissions
- **Storage Encryption**: Customer-managed encryption keys (optional)

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Check Cloud Functions
gcloud functions list --filter="name:schema-generator OR name:schema-validator"

# Verify Cloud Storage bucket
gsutil ls gs://BUCKET_NAME

# Test schema generation
curl -X POST "https://REGION-PROJECT_ID.cloudfunctions.net/schema-generator" \
    -H "Content-Type: application/json" \
    -d '{}'

# Check Cloud Build triggers
gcloud builds triggers list --filter="name:api-schema-generation-pipeline"
```

## Monitoring

### Key Metrics
- **Build Success Rate**: Percentage of successful pipeline executions
- **Function Duration**: Average execution time for schema generation
- **Schema Quality Score**: Validation results and best practice compliance
- **Storage Usage**: Artifact storage consumption over time

### Dashboards
Access the monitoring dashboard at:
```
https://console.cloud.google.com/monitoring/dashboards/custom/API_SCHEMA_PIPELINE_DASHBOARD_ID
```

### Alerts
Pre-configured alerts for:
- Build failures (>5% failure rate)
- Function timeouts or errors
- Storage quota warnings
- Schema validation failures

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Grant additional permissions
   gcloud projects add-iam-policy-binding PROJECT_ID \
       --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
       --role="roles/cloudbuild.builds.editor"
   ```

2. **Function Timeout Issues**
   ```bash
   # Increase function timeout
   gcloud functions deploy schema-generator \
       --timeout=300s \
       --memory=1024MB
   ```

3. **Build Trigger Not Firing**
   ```bash
   # Check trigger configuration
   gcloud builds triggers describe TRIGGER_NAME
   
   # Manually trigger build
   gcloud builds submit --config=cloudbuild.yaml
   ```

### Debug Logging

Enable debug logging for detailed troubleshooting:

```bash
# Set debug level logging
export GOOGLE_CLOUD_VERBOSITY=debug

# Check function logs
gcloud functions logs read schema-generator --limit=50

# Monitor build logs
gcloud builds log BUILD_ID --stream
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/us-central1/deployments/api-schema-pipeline
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow confirmation prompts
```

### Manual Cleanup

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Functions
gcloud functions delete schema-generator --quiet
gcloud functions delete schema-validator --quiet

# Delete Cloud Build triggers
gcloud builds triggers delete api-schema-generation-pipeline --quiet

# Delete Cloud Storage bucket
gsutil -m rm -r gs://BUCKET_NAME

# Remove IAM bindings
gcloud projects remove-iam-policy-binding PROJECT_ID \
    --member="serviceAccount:SERVICE_ACCOUNT_EMAIL" \
    --role="roles/cloudfunctions.developer"
```

## Cost Optimization

### Resource Sizing
- **Cloud Functions**: Start with 512MB memory, scale based on usage
- **Cloud Storage**: Use Standard class for frequently accessed schemas
- **Cloud Build**: Optimize build steps to reduce execution time

### Cost Monitoring
```bash
# Enable billing alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="API Schema Pipeline Budget" \
    --budget-amount=50USD \
    --threshold-rule=percent=80
```

## Security Considerations

### Best Practices Implemented
- Service accounts with minimal required permissions
- Cloud Storage bucket with uniform access control
- Function source code integrity validation
- Encrypted data transmission and storage
- Audit logging for all resource access

### Security Hardening Options
```bash
# Enable VPC Service Controls (optional)
gcloud access-context-manager perimeters create api-schema-perimeter \
    --policy=ACCESS_POLICY_ID \
    --title="API Schema Pipeline Perimeter"

# Configure private Google access
gcloud compute networks subnets update SUBNET_NAME \
    --region=REGION \
    --enable-private-ip-google-access
```

## Integration Options

### CI/CD Integration
```yaml
# GitHub Actions example
- name: Deploy Schema Pipeline
  uses: google-github-actions/setup-gcloud@v1
  with:
    project_id: ${{ secrets.GCP_PROJECT_ID }}
    service_account_key: ${{ secrets.GCP_SA_KEY }}
- run: ./scripts/deploy.sh
```

### API Gateway Integration
```bash
# Connect with API Gateway for documentation serving
gcloud api-gateway api-configs create schema-config \
    --api=api-schema-gateway \
    --openapi-spec=gs://BUCKET_NAME/openapi-schema.json
```

## Extension Ideas

1. **Multi-Language Support**: Extend schema generation for Java, Node.js, Python frameworks
2. **Version Management**: Implement semantic versioning for schema changes
3. **Documentation Portal**: Deploy interactive API documentation website
4. **Testing Integration**: Add contract testing with generated schemas
5. **Analytics**: Track API usage patterns and documentation access

## Support

### Documentation Links
- [Google Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Getting Help
- Check Cloud Console logs for detailed error messages
- Review build history in Cloud Build console
- Use `gcloud feedback` to report issues
- Consult the original recipe documentation for architectural guidance

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.