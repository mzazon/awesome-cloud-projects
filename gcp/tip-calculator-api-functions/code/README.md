# Infrastructure as Code for Tip Calculator API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Tip Calculator API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Artifact Registry Admin
  - Cloud Build Service Account
  - Service Usage Admin
  - Logging Admin
- Python 3.12+ for local testing (optional)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for declarative infrastructure management, providing native integration with Google Cloud services and built-in state management.

```bash
# Create deployment configuration
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export DEPLOYMENT_NAME="tip-calculator-deployment"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/infrastructure" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main"

# Alternative: Deploy from local files
gcloud infra-manager deployments apply ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --local-source="infrastructure-manager/"
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive community modules, making it ideal for multi-cloud environments or teams familiar with HashiCorp tools.

```bash
cd terraform/

# Initialize Terraform with Google Cloud provider
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure changes
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View important outputs
terraform output function_url
terraform output function_name
```

### Using Bash Scripts

Bash scripts provide imperative deployment using gcloud CLI commands, offering maximum flexibility and transparency into the deployment process.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export FUNCTION_NAME="tip-calculator"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployed function
FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
    --region ${REGION} \
    --format="value(httpsTrigger.url)")

curl "${FUNCTION_URL}?bill_amount=100&tip_percentage=18&number_of_people=4"
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  function_name:
    description: "Cloud Function name"
    type: string
    default: "tip-calculator"
  runtime:
    description: "Python runtime version"
    type: string
    default: "python312"
  memory:
    description: "Function memory allocation"
    type: string
    default: "256MB"
  timeout:
    description: "Function timeout in seconds"
    type: number
    default: 60
```

### Terraform Variables

Customize deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id    = "your-project-id"
region        = "us-central1"
function_name = "tip-calculator"
runtime       = "python312"
memory_mb     = 256
timeout_s     = 60

# Optional: Custom labels
labels = {
  environment = "demo"
  application = "tip-calculator"
  team        = "development"
}
```

### Bash Script Environment Variables

Configure deployment using environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export FUNCTION_NAME="tip-calculator"
export RUNTIME="python312"
export MEMORY="256MB"
export TIMEOUT="60s"
```

## Testing the Deployment

After successful deployment, test the tip calculator API:

```bash
# Get function URL (varies by deployment method)
# For Infrastructure Manager:
FUNCTION_URL=$(gcloud infra-manager deployments describe ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --format="value(outputs.function_url.value)")

# For Terraform:
FUNCTION_URL=$(terraform output -raw function_url)

# For Bash scripts:
FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
    --region ${REGION} \
    --format="value(httpsTrigger.url)")

# Test with GET request
curl "${FUNCTION_URL}?bill_amount=87.45&tip_percentage=20&number_of_people=3"

# Test with POST request
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "bill_amount": 150.75,
        "tip_percentage": 18,
        "number_of_people": 6
    }'

# Test error handling
curl "${FUNCTION_URL}?bill_amount=-50&tip_percentage=15"
```

Expected successful response:
```json
{
  "input": {
    "bill_amount": 87.45,
    "tip_percentage": 20.0,
    "number_of_people": 3
  },
  "calculations": {
    "tip_amount": 17.49,
    "total_amount": 104.94,
    "per_person": {
      "bill_share": 29.15,
      "tip_share": 5.83,
      "total_share": 34.98
    }
  },
  "formatted_summary": "Bill: $87.45 | Tip (20%): $17.49 | Total: $104.94 | Per person: $34.98"
}
```

## Monitoring and Observability

View function logs and metrics:

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME} \
    --region ${REGION} \
    --limit 50

# View function metrics in Cloud Console
echo "Function metrics: https://console.cloud.google.com/functions/details/${REGION}/${FUNCTION_NAME}/metrics?project=${PROJECT_ID}"

# Monitor function invocations
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${FUNCTION_NAME}" \
    --limit=10 \
    --format="table(timestamp,severity,textPayload)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --quiet

# Verify resources are deleted
gcloud functions list --filter="name:${FUNCTION_NAME}"
```

### Using Terraform

```bash
cd terraform/

# Destroy all managed resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify function deletion
gcloud functions describe ${FUNCTION_NAME} \
    --region ${REGION} 2>&1 | grep "NOT_FOUND" && echo "✅ Function successfully deleted"
```

## Cost Optimization

This recipe is designed to stay within Google Cloud's free tier:

- **Cloud Functions**: 2 million invocations per month free
- **Cloud Build**: 120 build-minutes per day free
- **Artifact Registry**: 0.5 GB storage free
- **Cloud Logging**: 50 GB logs per month free

Monitor costs:
```bash
# Check current month's Cloud Functions usage
gcloud logging read "resource.type=cloud_function" \
    --format="value(timestamp)" \
    --filter="timestamp>=2025-01-01" | wc -l

# View cost breakdown in Cloud Console
echo "Billing: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Ensure required APIs are enabled
   gcloud services enable cloudfunctions.googleapis.com \
       cloudbuild.googleapis.com \
       artifactregistry.googleapis.com
   
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Deployment Failures**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # View detailed function information
   gcloud functions describe ${FUNCTION_NAME} --region ${REGION}
   ```

3. **Function Not Responding**:
   ```bash
   # Check function logs for errors
   gcloud functions logs read ${FUNCTION_NAME} --region ${REGION}
   
   # Verify function trigger configuration
   gcloud functions describe ${FUNCTION_NAME} \
       --region ${REGION} \
       --format="yaml(httpsTrigger)"
   ```

### Debug Mode

Enable verbose logging for troubleshooting:

```bash
# Enable debug logging for gcloud
export CLOUDSDK_CORE_VERBOSITY=debug

# Run deployment with detailed output
./scripts/deploy.sh 2>&1 | tee deployment.log
```

## Security Considerations

This recipe implements several security best practices:

- **Public Access**: Function allows unauthenticated access for demonstration purposes
- **CORS Headers**: Configured for web application integration
- **Input Validation**: Comprehensive validation prevents injection attacks
- **Error Handling**: Sanitized error messages prevent information disclosure

For production use, consider:

- Implementing authentication with [Cloud Identity](https://cloud.google.com/identity)
- Using [Cloud Armor](https://cloud.google.com/armor) for DDoS protection
- Enabling [VPC Service Controls](https://cloud.google.com/vpc-service-controls) for data exfiltration protection
- Implementing rate limiting and monitoring

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../tip-calculator-api-functions.md)
2. Review [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
3. Consult [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
4. Reference [Terraform Google Cloud provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Next Steps

Enhance your tip calculator API:

1. **Add Authentication**: Integrate with Firebase Auth or Cloud Identity
2. **Implement Caching**: Use Cloud Memorystore for frequently accessed calculations
3. **Create Frontend**: Build a web interface using App Engine or Cloud Run
4. **Add Persistence**: Store calculation history in Firestore
5. **Enable Monitoring**: Set up custom metrics and alerting with Cloud Monitoring