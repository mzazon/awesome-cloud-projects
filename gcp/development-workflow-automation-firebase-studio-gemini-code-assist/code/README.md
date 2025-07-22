# Infrastructure as Code for Development Workflow Automation with Firebase Studio and Gemini Code Assist

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Development Workflow Automation with Firebase Studio and Gemini Code Assist".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured (version 440.0 or later)
- Firebase CLI installed and authenticated (version 11.0 or later)
- Terraform installed (version 1.5 or later) for Terraform implementation
- Appropriate Google Cloud permissions for resource creation:
  - Cloud Storage Admin
  - Cloud Functions Admin
  - Eventarc Admin
  - Pub/Sub Admin
  - Firebase Admin
  - Service Account Admin
  - Project Editor (for API enablement)
- Billing enabled on your Google Cloud project
- Estimated cost: $10-20 for testing resources

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/dev-workflow-automation \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --git-source-repo=https://github.com/your-org/your-repo \
    --git-source-directory=gcp/development-workflow-automation-firebase-studio-gemini-code-assist/code/infrastructure-manager \
    --git-source-ref=main \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/dev-workflow-automation
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
./scripts/verify.sh
```

## Configuration

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts these input values:

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: us-central1)
- `environment`: Environment name (default: dev)
- `bucket_name_suffix`: Suffix for Cloud Storage bucket (auto-generated if not provided)
- `enable_monitoring`: Enable Cloud Monitoring dashboard (default: true)
- `function_memory`: Memory allocation for Cloud Function (default: 512MB)
- `function_timeout`: Timeout for Cloud Function (default: 300s)

### Terraform Variables

Configure deployment by setting variables in `terraform.tfvars` or via command line:

```hcl
# terraform.tfvars example
project_id = "my-ai-dev-project"
region = "us-central1"
environment = "development"
bucket_name_suffix = "dev123"
enable_monitoring = true
function_memory = 512
function_timeout = 300
```

### Environment Variables for Scripts

The bash scripts require these environment variables:

```bash
export PROJECT_ID="your-project-id"           # Required: GCP project ID
export REGION="us-central1"                   # Required: Deployment region
export ENVIRONMENT="dev"                      # Optional: Environment name
export BUCKET_NAME_SUFFIX="$(date +%s)"      # Optional: Bucket suffix
export ENABLE_MONITORING="true"              # Optional: Enable monitoring
```

## Architecture Deployed

This IaC deploys the following Google Cloud resources:

### Core Infrastructure

- **Cloud Storage Bucket**: Versioned storage for development artifacts with lifecycle policies
- **Pub/Sub Topic & Subscription**: Event messaging for development workflow coordination
- **Cloud Function**: Intelligent code review automation with Gemini Code Assist integration
- **Eventarc Trigger**: Event-driven workflow automation for storage events

### Security & Access

- **Service Accounts**: Dedicated service accounts with least-privilege IAM roles
- **IAM Bindings**: Proper permissions for cross-service communication
- **VPC Security**: Default network security with appropriate firewall rules

### Monitoring & Observability

- **Cloud Monitoring Dashboard**: Custom dashboard for workflow metrics and performance
- **Alerting Policies**: Automated alerts for function failures and workflow issues
- **Logging Configuration**: Structured logging for all components with retention policies

### Firebase Integration

- **Firebase Project Configuration**: Integration with Google Cloud project
- **Firebase Hosting**: Deployment target for generated web applications
- **Firebase Studio Workspace**: Development environment configuration

## Deployment Validation

After deployment, verify the infrastructure is working correctly:

### Test AI Code Generation Workflow

```bash
# Test code generation pipeline
echo '{"prompt": "Create a React component for user authentication", "type": "component"}' > test-request.json
gsutil cp test-request.json gs://${BUCKET_NAME}/requests/

# Check for generated artifacts (wait 30-60 seconds)
gsutil ls gs://${BUCKET_NAME}/generated/
```

### Verify Code Review Automation

```bash
# Check Cloud Function logs
gcloud functions logs read code-review-automation --limit=10

# Verify review results are generated
gsutil ls gs://${BUCKET_NAME}/reviews/
```

### Test Event-Driven Workflow

```bash
# Verify Eventarc trigger is active
gcloud eventarc triggers list --location=${REGION}

# Check Pub/Sub message processing
gcloud pubsub subscriptions pull code-events-sub --auto-ack --limit=5
```

### Validate Firebase Integration

```bash
# Verify Firebase project status
firebase projects:list

# Check Firebase hosting configuration
firebase hosting:sites:list
```

## Monitoring and Alerts

### Cloud Monitoring Dashboard

Access the custom dashboard at:
```
https://console.cloud.google.com/monitoring/dashboards/custom/${DASHBOARD_ID}
```

Key metrics monitored:
- Code generation rate and success percentage
- Code review automation performance
- Cloud Function execution metrics
- Storage bucket usage and access patterns
- Eventarc trigger success rates

### Alerting Policies

Configured alerts for:
- Cloud Function execution failures (>5 errors in 5 minutes)
- Storage bucket access denied errors
- Pub/Sub message processing delays
- Firebase hosting deployment failures

## Customization

### Extending the Code Review Function

Modify the Cloud Function source code to add custom review criteria:

1. Update `function_source/main.py` with additional checks
2. Redeploy using your chosen IaC method
3. Test with sample code artifacts

### Adding Custom Monitoring Metrics

Create additional monitoring dashboards:

```bash
# Create custom dashboard
gcloud monitoring dashboards create --config-from-file=custom-dashboard.json
```

### Firebase Studio Templates

Customize development templates by:

1. Modifying workspace configuration in `firebase-studio-workspace/`
2. Adding custom AI prompts for Gemini Code Assist
3. Updating template metadata for specific project needs

## Security Considerations

### IAM Best Practices

- Service accounts use least-privilege access
- Cross-service authentication via service account keys
- Regular rotation of service account keys recommended

### Data Protection

- Cloud Storage bucket uses customer-managed encryption
- All inter-service communication uses TLS encryption
- Sensitive configuration stored in Secret Manager

### Network Security

- Cloud Function runs in VPC with restricted egress
- Storage bucket has private access with signed URLs
- Eventarc triggers use authenticated invocation

## Troubleshooting

### Common Issues

1. **Cloud Function deployment failures**:
   ```bash
   # Check function status and logs
   gcloud functions describe code-review-automation
   gcloud functions logs read code-review-automation --limit=50
   ```

2. **Eventarc trigger not firing**:
   ```bash
   # Verify trigger configuration
   gcloud eventarc triggers describe code-review-trigger --location=${REGION}
   
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Storage bucket access issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://${BUCKET_NAME}
   
   # Test bucket access
   gsutil ls gs://${BUCKET_NAME}
   ```

4. **Firebase integration problems**:
   ```bash
   # Re-authenticate Firebase CLI
   firebase logout
   firebase login
   
   # Verify project association
   firebase use --add
   ```

### Debugging Commands

```bash
# Check all deployed resources
gcloud resource-manager tags list --parent=projects/${PROJECT_ID}

# Monitor real-time logs
gcloud logging tail "resource.type=cloud_function"

# Verify API enablement
gcloud services list --enabled --filter="name:storage OR name:cloudfunctions OR name:eventarc"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/dev-workflow-automation

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources removed
gcloud resource-manager tags list --parent=projects/${PROJECT_ID}
```

### Manual Cleanup (if needed)

```bash
# Remove any remaining Storage buckets
gsutil -m rm -r gs://${BUCKET_NAME}

# Delete Firebase project (optional)
firebase projects:delete ${PROJECT_ID}

# Remove any orphaned IAM bindings
gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/storage.admin"
```

## Cost Optimization

### Resource Sizing

- Cloud Function memory optimized for AI workloads (512MB default)
- Storage bucket with intelligent tiering for cost efficiency
- Pub/Sub configured with appropriate message retention

### Cost Monitoring

```bash
# Enable billing alerts
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="AI Dev Workflow Budget" \
    --budget-amount=50USD

# Monitor current costs
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT_ID}
```

## Performance Tuning

### Cloud Function Optimization

- Increase memory allocation for complex AI workloads
- Implement connection pooling for external API calls
- Use Cloud Build for faster deployment cycles

### Storage Performance

- Configure multi-regional storage for global access
- Implement CDN caching for frequently accessed artifacts
- Use parallel uploads for large code repositories

## Integration Examples

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
name: Deploy AI Dev Workflow
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: google-github-actions/setup-gcloud@v1
      - name: Deploy Infrastructure
        run: |
          cd terraform/
          terraform init
          terraform apply -auto-approve
```

### Local Development Setup

```bash
# Set up local development environment
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"
export PROJECT_ID="your-dev-project"

# Install dependencies
npm install -g firebase-tools
pip install google-cloud-storage google-cloud-functions

# Start local development server
firebase emulators:start --project=${PROJECT_ID}
```

## Support

For issues with this infrastructure code:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the original recipe documentation
3. Consult the [Google Cloud documentation](https://cloud.google.com/docs)
4. Check [Firebase documentation](https://firebase.google.com/docs) for Firebase-specific issues
5. Review [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development project
2. Validate all IaC implementations work correctly
3. Update documentation to reflect changes
4. Follow Google Cloud security best practices
5. Ensure backward compatibility where possible