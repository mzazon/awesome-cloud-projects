# Infrastructure as Code for Form Data Validation with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Form Data Validation with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (cloudfunctions.admin)
  - Firestore (datastore.owner)
  - Cloud Logging (logging.admin)
  - Service Usage (serviceusage.serviceUsageConsumer)
- Python 3.12 runtime support in target region

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="form-validation-deployment"

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --local-source="infrastructure-manager/"
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Deploy infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Functions (2nd Gen)**: HTTP-triggered serverless function for form validation
- **Firestore Database**: Native mode NoSQL database for storing validated submissions
- **Cloud Logging**: Centralized logging and monitoring
- **IAM Roles**: Least privilege service accounts and permissions

## Configuration Options

### Infrastructure Manager Variables

Customize deployment by modifying `infrastructure-manager/main.yaml`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_name`: Cloud Function name (default: validate-form-data)
- `memory_mb`: Function memory allocation (default: 256MB)
- `timeout_seconds`: Function timeout (default: 60s)

### Terraform Variables

Customize deployment using variables in `terraform/variables.tf`:

```bash
# Example with custom values
terraform apply \
    -var="project_id=my-project" \
    -var="region=europe-west1" \
    -var="function_name=custom-form-validator" \
    -var="memory_mb=512" \
    -var="timeout_seconds=120"
```

### Bash Script Environment Variables

Set these environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"           # Required
export REGION="us-central1"                   # Optional, defaults to us-central1
export FUNCTION_NAME="validate-form-data"     # Optional, defaults to validate-form-data
export MEMORY_MB="256"                        # Optional, defaults to 256MB
export TIMEOUT_SECONDS="60"                   # Optional, defaults to 60s
```

## Testing the Deployment

After successful deployment, test the form validation endpoint:

```bash
# Get function URL (replace with actual URL from deployment output)
FUNCTION_URL="https://your-region-your-project.cloudfunctions.net/validate-form-data"

# Test with valid data
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "John Smith",
        "email": "john@example.com",
        "phone": "555-123-4567",
        "message": "This is a test message for form validation."
    }'

# Test with invalid data
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
        "name": "A",
        "email": "invalid-email",
        "phone": "123",
        "message": "Short"
    }'
```

Expected responses:
- Valid data: `{"success": true, "message": "Form submitted successfully", "id": "document-id"}`
- Invalid data: `{"success": false, "errors": ["validation error messages"]}`

## Monitoring and Logs

### View Function Logs

```bash
# View recent function execution logs
gcloud functions logs read validate-form-data \
    --region=${REGION} \
    --limit=20

# Follow logs in real-time
gcloud functions logs tail validate-form-data \
    --region=${REGION}
```

### View Firestore Data

```bash
# List form submissions
gcloud firestore documents list \
    --collection=form_submissions \
    --limit=10

# View specific document
gcloud firestore documents describe \
    --collection=form_submissions \
    --document=DOCUMENT_ID
```

### Access Cloud Console

- **Cloud Functions**: `https://console.cloud.google.com/functions/list?project=${PROJECT_ID}`
- **Firestore**: `https://console.cloud.google.com/firestore/data?project=${PROJECT_ID}`
- **Cloud Logging**: `https://console.cloud.google.com/logs/query?project=${PROJECT_ID}`

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
```

### Using Terraform

```bash
cd terraform/
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **HTTPS Only**: All communication encrypted in transit
- **Input Validation**: Comprehensive server-side validation and sanitization
- **CORS Configuration**: Configurable cross-origin resource sharing
- **Error Handling**: Secure error responses without information leakage

## Cost Optimization

- **Pay-per-request**: Cloud Functions only charges for actual invocations
- **Right-sized Memory**: Default 256MB allocation optimized for typical form processing
- **Firestore Free Tier**: Includes 1GB storage and 50K reads/writes per day
- **Cloud Logging**: 50GB monthly allotment included in free tier

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure service accounts have required IAM roles
2. **Function Deployment Failed**: Check Python requirements and source code syntax
3. **Firestore Access Denied**: Verify Firestore API is enabled and database is created
4. **CORS Errors**: Function includes CORS headers for web browser compatibility

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:(cloudfunctions.googleapis.com OR firestore.googleapis.com)"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Test function locally (requires Functions Framework)
cd function-source/
pip install -r requirements.txt
functions-framework --target=validate_form_data --debug
```

## Extension Ideas

This infrastructure can be extended to support:

- **Email Notifications**: Add SendGrid or Gmail API integration
- **Analytics Dashboard**: Connect to BigQuery and Looker Studio
- **Advanced Security**: Implement reCAPTCHA and rate limiting
- **Multi-language Support**: Add Cloud Translation API
- **File Uploads**: Integrate with Cloud Storage for attachments

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify IAM permissions and API enablement
4. Consult Cloud Functions troubleshooting guides

## Version Information

- **Terraform**: Requires version >= 1.0
- **Google Cloud Provider**: >= 4.0
- **Infrastructure Manager**: Latest available version
- **Python Runtime**: 3.12 (latest supported in Cloud Functions)
- **Functions Framework**: 3.x