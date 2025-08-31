# Infrastructure as Code for URL Shortener with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "URL Shortener with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (Cloud Functions Admin)
  - Cloud Firestore (Cloud Datastore Owner)
  - Cloud Build (Cloud Build Editor)
  - Service Account (Service Account User)
- Node.js 20 or higher (for function deployment)
- Terraform >= 1.0 (for Terraform implementation)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that uses standard Terraform configurations with enhanced Google Cloud integration.

```bash
# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/url-shortener-deployment \
    --service-account=${SERVICE_ACCOUNT_EMAIL} \
    --git-source-repo=https://source.developers.google.com/p/${PROJECT_ID}/r/url-shortener-repo \
    --git-source-directory=infrastructure-manager/

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/url-shortener-deployment
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Get function URL
terraform output function_url
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for project ID and region if not set
# It will also handle API enablement and service account creation
```

## Configuration Variables

### Infrastructure Manager / Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud Project ID | `string` | n/a | Yes |
| `region` | Google Cloud region for resources | `string` | `us-central1` | No |
| `function_name` | Name of the Cloud Function | `string` | `url-shortener` | No |
| `function_memory` | Memory allocation for Cloud Function (MB) | `number` | `256` | No |
| `function_timeout` | Timeout for Cloud Function (seconds) | `number` | `60` | No |
| `max_instances` | Maximum number of function instances | `number` | `10` | No |
| `firestore_location` | Firestore database location | `string` | `us-central` | No |

### Environment Variables for Bash Scripts

Set these environment variables before running the bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="url-shortener"
```

## Architecture Overview

The infrastructure deploys:

1. **Cloud Function**: HTTP-triggered serverless function handling URL shortening and redirection
2. **Cloud Firestore**: NoSQL database storing URL mappings and analytics
3. **IAM Service Account**: Dedicated service account with minimal required permissions
4. **API Services**: Required Google Cloud APIs (Cloud Functions, Firestore, Cloud Build)

## Deployed Resources

### Google Cloud Services
- `google_cloudfunctions_function`: HTTP-triggered Cloud Function
- `google_firestore_database`: Firestore database in Native mode
- `google_service_account`: Dedicated service account for the function
- `google_service_account_iam_binding`: IAM permissions for Firestore access
- `google_project_service`: Enabled APIs (Cloud Functions, Firestore, Cloud Build)

### Function Configuration
- **Runtime**: Node.js 20
- **Trigger**: HTTP
- **Memory**: 256MB (configurable)
- **Timeout**: 60 seconds (configurable)
- **Max Instances**: 10 (configurable)
- **Authentication**: Unauthenticated (public access)

## Usage After Deployment

### Creating Short URLs

```bash
# Get the function URL (replace with your actual URL)
FUNCTION_URL=$(gcloud functions describe url-shortener --region=${REGION} --format="value(httpsTrigger.url)")

# Create a short URL
curl -X POST ${FUNCTION_URL}/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://cloud.google.com/functions"}'
```

### Using Short URLs

```bash
# Access a short URL (replace 'AbC123' with actual short ID)
curl -I ${FUNCTION_URL}/AbC123
```

### API Documentation

```bash
# Get API information
curl ${FUNCTION_URL}/
```

## Monitoring and Observability

The deployed infrastructure includes:

- **Cloud Logging**: Function execution logs automatically captured
- **Cloud Monitoring**: Built-in metrics for function invocations, errors, and duration
- **Error Reporting**: Automatic error tracking and alerting

Access monitoring data:

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

# View function metrics in Cloud Console
echo "Metrics: https://console.cloud.google.com/monitoring/dashboards/resourceList/cloudfunctions_function"
```

## Security Considerations

The infrastructure implements security best practices:

1. **Least Privilege IAM**: Service account has minimal required permissions
2. **Firestore Security Rules**: Database access controlled via security rules
3. **HTTPS Only**: All traffic encrypted in transit
4. **Input Validation**: Function validates URLs and handles malicious input
5. **CORS Configuration**: Proper cross-origin resource sharing setup

## Cost Optimization

The serverless architecture provides cost-effective scaling:

- **Cloud Functions**: Pay per invocation (2M invocations/month free)
- **Firestore**: Pay per operation (50K reads/writes/day free)
- **No idle costs**: Resources scale to zero when not in use

Estimated costs for typical usage:
- **Development**: $0.00/month (within free tier)
- **Small production**: $0.01-$0.50/month
- **Medium traffic**: $1-$10/month (1M+ requests)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/url-shortener-deployment

# Clean up any remaining resources
gcloud infra-manager operations list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# It handles dependencies and provides progress feedback
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Function
gcloud functions delete ${FUNCTION_NAME} --region=${REGION} --quiet

# Delete Firestore database (WARNING: This deletes all data)
gcloud firestore databases delete --database='(default)' --quiet

# Remove service account
gcloud iam service-accounts delete url-shortener-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Troubleshooting

### Common Issues

1. **Function deployment fails**:
   ```bash
   # Check API enablement
   gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com"
   
   # Verify billing is enabled
   gcloud billing projects describe ${PROJECT_ID}
   ```

2. **Firestore permission errors**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
     --flatten="bindings[].members" \
     --filter="bindings.members:url-shortener-sa@${PROJECT_ID}.iam.gserviceaccount.com"
   ```

3. **Function timeout errors**:
   ```bash
   # Check function logs for errors
   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION} --limit=50
   ```

### Debug Mode

Enable debug logging for bash scripts:

```bash
# Run deployment with debug output
DEBUG=1 ./scripts/deploy.sh

# Run cleanup with debug output
DEBUG=1 ./scripts/destroy.sh
```

## Customization

### Function Code Updates

To update the function code:

1. Modify the function source in `scripts/function/index.js`
2. Redeploy using your chosen method
3. The infrastructure will automatically update the function

### Scaling Configuration

Adjust function scaling by modifying variables:

```bash
# For Terraform
terraform apply -var="max_instances=100" -var="function_memory=512"

# For bash scripts, edit scripts/deploy.sh
export MAX_INSTANCES=100
export MEMORY_SIZE=512
```

### Custom Domain

To use a custom domain:

1. Register domain and configure DNS
2. Create SSL certificate
3. Configure Cloud Load Balancer
4. Update function deployment

## Development Workflow

### Local Testing

```bash
# Install Function Framework
npm install -g @google-cloud/functions-framework

# Run function locally
cd scripts/function/
npm install
npx functions-framework --target=urlShortener --port=8080

# Test locally
curl -X POST http://localhost:8080/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Deploy URL Shortener
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: google-github-actions/setup-gcloud@v1
      - run: ./scripts/deploy.sh
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../url-shortener-functions-firestore.md)
2. Review [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Consult [Cloud Firestore documentation](https://cloud.google.com/firestore/docs)
4. Visit [Google Cloud Support](https://cloud.google.com/support)

## Version History

- **v1.0**: Initial implementation with Infrastructure Manager, Terraform, and Bash scripts
- **v1.1**: Added enhanced monitoring and security configurations

## Contributing

To contribute improvements:

1. Test changes in a development project
2. Update relevant documentation
3. Ensure all IaC implementations stay synchronized
4. Verify cleanup procedures work correctly