# Infrastructure as Code for Persistent AI Customer Support with Agent Engine Memory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Persistent AI Customer Support with Agent Engine Memory".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Project with billing enabled
- Required APIs enabled (or permissions to enable them):
  - Cloud Functions API
  - Firestore API
  - Vertex AI API
  - Cloud Build API
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Developer
  - Firestore User
  - Vertex AI User
  - Project Editor (or equivalent granular permissions)

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/persistent-support-agent \
    --service-account projects/$PROJECT_ID/serviceAccounts/infra-manager@$PROJECT_ID.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Configuration

### Environment Variables

All implementations support these configuration options:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `FUNCTION_MEMORY` | Memory allocation for Cloud Functions | `512MB` | No |
| `FUNCTION_TIMEOUT` | Timeout for Cloud Functions | `300s` | No |
| `FIRESTORE_LOCATION` | Firestore database location | `us-central1` | No |

### Terraform Variables

The Terraform implementation includes additional customization options in `variables.tf`:

```bash
# Example terraform.tfvars
project_id = "my-support-project"
region = "us-central1"
function_memory = "512MB"
function_timeout = "300s"
firestore_location = "us-central1"
enable_apis = true
```

### Infrastructure Manager Variables

Create a `terraform.tfvars` file for Infrastructure Manager deployment:

```bash
project_id = "my-support-project"
region = "us-central1"
```

## Architecture Components

The infrastructure creates the following resources:

### Core Services
- **Firestore Database**: Native mode database for conversation memory storage
- **Cloud Functions**: 
  - Memory retrieval function for conversation context
  - Main support chat function with AI integration
- **Vertex AI**: Gemini model for natural language processing

### IAM and Security
- Service accounts with least privilege access
- IAM bindings for Firestore and Vertex AI access
- Cloud Functions invoker permissions

### Networking
- HTTP triggers for Cloud Functions
- CORS configuration for web interface access

## Validation & Testing

After deployment, verify the infrastructure:

### Test Memory Retrieval Function

```bash
# Get the memory retrieval function URL
RETRIEVE_MEMORY_URL=$(gcloud functions describe retrieve-memory-${RANDOM_SUFFIX} \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test with sample data
curl -X POST ${RETRIEVE_MEMORY_URL} \
    -H "Content-Type: application/json" \
    -d '{"customer_id": "test-customer-001"}'
```

### Test Support Chat Function

```bash
# Get the chat function URL
CHAT_FUNCTION_URL=$(gcloud functions describe support-chat-${RANDOM_SUFFIX} \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test conversation
curl -X POST ${CHAT_FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "customer_id": "test-customer-001",
      "message": "I need help with my account"
    }'
```

### Verify Firestore Database

```bash
# List Firestore collections
gcloud firestore collections list

# Query conversations (if any exist)
gcloud alpha firestore query \
    --collection-path=conversations \
    --limit=5
```

## Monitoring and Logging

### Cloud Functions Logs

```bash
# View memory retrieval function logs
gcloud functions logs read retrieve-memory-${RANDOM_SUFFIX} \
    --region=${REGION} \
    --limit=50

# View chat function logs
gcloud functions logs read support-chat-${RANDOM_SUFFIX} \
    --region=${REGION} \
    --limit=50
```

### Vertex AI Usage

```bash
# Monitor Vertex AI usage in Cloud Console
# Navigate to: Vertex AI > Generative AI > Usage
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/persistent-support-agent
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Functions
gcloud functions delete retrieve-memory-${RANDOM_SUFFIX} --region=${REGION} --quiet
gcloud functions delete support-chat-${RANDOM_SUFFIX} --region=${REGION} --quiet

# Delete Firestore database
gcloud firestore databases delete --database='(default)' --quiet
```

## Cost Optimization

### Estimated Costs

- **Cloud Functions**: Pay-per-invocation (first 2M invocations free monthly)
- **Firestore**: Pay-per-operation and storage (~$0.06 per 100K operations)
- **Vertex AI**: Pay-per-token (~$0.001 per 1K input tokens for Gemini)

### Cost Management

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Support Agent Budget" \
    --budget-amount=50USD

# Monitor usage
gcloud logging read "resource.type=cloud_function" \
    --limit=10 \
    --format="table(timestamp, resource.labels.function_name, severity)"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable firestore.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

2. **Permission Denied Errors**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.developer"
   ```

3. **Firestore Database Creation Issues**
   ```bash
   # Ensure Firestore is in Native mode
   gcloud firestore databases create \
       --location=${REGION} \
       --type=firestore-native
   ```

4. **Function Deployment Timeout**
   ```bash
   # Increase deployment timeout
   gcloud functions deploy function-name \
       --timeout=540s \
       --memory=1024MB
   ```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug environment variables
export CLOUDSDK_CORE_VERBOSITY=debug
export TF_LOG=DEBUG  # For Terraform

# Run deployment with verbose output
gcloud functions deploy --verbosity=debug
```

## Security Considerations

### Data Protection
- Conversation data is encrypted at rest in Firestore
- Cloud Functions use Google-managed service accounts
- HTTPS-only communication between components

### Access Control
- Functions use least privilege IAM roles
- Customer data isolation through Firestore security rules
- API access requires proper authentication headers

### Compliance
- GDPR compliance through data retention policies
- SOC 2 Type II compliance via Google Cloud
- Data residency controls through region selection

## Customization

### Adding Custom Features

1. **Sentiment Analysis Integration**
   ```bash
   # Enable Natural Language API
   gcloud services enable language.googleapis.com
   
   # Update function code to include sentiment analysis
   # See scripts/add-sentiment-analysis.sh
   ```

2. **Multi-language Support**
   ```bash
   # Enable Translation API
   gcloud services enable translate.googleapis.com
   
   # Update function with translation capabilities
   # See scripts/add-translation.sh
   ```

3. **Advanced Analytics**
   ```bash
   # Enable BigQuery for analytics
   gcloud services enable bigquery.googleapis.com
   
   # Create analytics pipeline
   # See terraform/modules/analytics/
   ```

## Support

### Documentation Links
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help
- For Google Cloud issues: [Google Cloud Support](https://cloud.google.com/support)
- For Terraform issues: [Terraform Documentation](https://www.terraform.io/docs)
- For recipe-specific questions: Refer to the original recipe documentation

### Community Resources
- [Google Cloud Community](https://cloud.google.com/community)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development project
2. Validate with `terraform plan` and `gcloud --dry-run`
3. Update documentation for any new variables or outputs
4. Follow Google Cloud and Terraform best practices
5. Include appropriate comments and descriptions

## License

This infrastructure code is provided under the same license as the original recipe documentation.