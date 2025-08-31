# Infrastructure as Code for Interactive Quiz Generation with Vertex AI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Interactive Quiz Generation with Vertex AI and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a serverless quiz generation system that:
- Uses Vertex AI Gemini models for intelligent content analysis and question generation
- Implements Cloud Functions for scalable API endpoints (generation, delivery, scoring)
- Leverages Cloud Storage for secure content and quiz management
- Provides automated scoring with detailed feedback and analytics

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - `roles/cloudfunctions.admin`
  - `roles/storage.admin`
  - `roles/aiplatform.admin`
  - `roles/iam.serviceAccountAdmin`
  - `roles/serviceusage.serviceUsageAdmin`
- For Terraform: Terraform CLI installed (>= 1.5.0)
- For Infrastructure Manager: Access to Google Cloud Console or gcloud CLI

## Cost Considerations

Estimated costs for tutorial completion: $10-20
- Vertex AI (Gemini 1.5 Flash): ~$2-5 for token usage
- Cloud Functions: ~$1-3 for invocations and compute time
- Cloud Storage: ~$0.50 for object storage
- Additional charges may apply for extended usage

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended way to manage infrastructure as code, providing native integration with Google Cloud services.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/quiz-generation \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/infrastructure" \
    --git-source-directory="gcp/interactive-quiz-generation-vertex-ai-functions/code/infrastructure-manager" \
    --git-source-ref="main"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/us-central1/deployments/quiz-generation
```

### Using Terraform

Terraform provides a consistent workflow across multiple cloud providers and includes rich ecosystem support.

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs (function URLs, bucket name, etc.)
terraform output
```

### Using Bash Scripts

The bash scripts provide a simplified deployment experience with built-in error handling and progress indicators.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create service accounts and IAM bindings
# 3. Create Cloud Storage bucket with lifecycle policies
# 4. Deploy all three Cloud Functions
# 5. Display function URLs for testing
```

## Configuration Variables

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bucket_location` | Storage bucket location | `US` | No |
| `function_memory` | Memory allocation for functions | `512` | No |
| `function_timeout` | Function timeout in seconds | `300` | No |

### Infrastructure Manager Variables

Variables are defined in the YAML configuration file and can be customized before deployment.

## Deployed Resources

### Core Infrastructure
- **Cloud Storage Bucket**: Stores learning materials, generated quizzes, and results
- **Service Account**: Dedicated account for AI services with minimal required permissions
- **IAM Bindings**: Least-privilege access controls for secure operation

### Cloud Functions
- **Quiz Generator Function**: Processes content using Vertex AI Gemini models
- **Quiz Delivery Function**: Serves quizzes to students with proper answer filtering
- **Quiz Scoring Function**: Automated scoring with detailed feedback and analytics

### APIs and Services
- Vertex AI API (for Gemini model access)
- Cloud Functions API
- Cloud Storage API
- Cloud Build API (for function deployment)
- Artifact Registry API (for container storage)

## Post-Deployment Testing

After successful deployment, test the system functionality:

1. **Generate a Quiz**:
   ```bash
   # Get the generator function URL from outputs
   GENERATOR_URL=$(terraform output -raw quiz_generator_url)
   
   # Test with sample content
   curl -X POST ${GENERATOR_URL} \
       -H "Content-Type: application/json" \
       -d '{
           "content": "Cloud computing enables on-demand access to computing resources over the internet. Key benefits include scalability, cost-effectiveness, and flexibility.",
           "question_count": 3,
           "difficulty": "medium"
       }'
   ```

2. **Deliver a Quiz**:
   ```bash
   # Get quiz ID from generation response and delivery URL
   DELIVERY_URL=$(terraform output -raw quiz_delivery_url)
   QUIZ_ID="your-quiz-id"
   
   curl "${DELIVERY_URL}?quiz_id=${QUIZ_ID}"
   ```

3. **Score Submission**:
   ```bash
   # Get scoring URL
   SCORING_URL=$(terraform output -raw quiz_scoring_url)
   
   curl -X POST ${SCORING_URL} \
       -H "Content-Type: application/json" \
       -d '{
           "quiz_id": "your-quiz-id",
           "student_id": "test-student",
           "answers": {
               "0": 1,
               "1": true,
               "2": "cloud services"
           }
       }'
   ```

## Monitoring and Observability

### Cloud Functions Monitoring
- View function metrics in Cloud Console
- Check function logs: `gcloud functions logs read FUNCTION_NAME`
- Monitor invocation counts, execution times, and error rates

### Vertex AI Usage Tracking
- Monitor token usage in Cloud Console
- Track model inference costs
- Set up budget alerts for AI spending

### Storage Analytics
- Monitor bucket usage and access patterns
- Review object lifecycle transitions
- Track storage costs and optimize retention policies

## Security Considerations

### IAM and Access Control
- Service account follows least privilege principle
- Functions use dedicated service account (not default)
- Storage bucket access restricted to service account

### Data Protection
- All API communication uses HTTPS
- Student answers and results stored securely in Cloud Storage
- Proper CORS configuration for web application integration

### API Security
- Functions validate input data
- Error handling prevents information disclosure
- Rate limiting can be added via Cloud Armor if needed

## Cleanup

### Using Infrastructure Manager
```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/quiz-generation
```

### Using Terraform
```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Confirm destruction when prompted
```

### Using Bash Scripts
```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete all Cloud Functions
# 2. Remove Cloud Storage bucket and contents
# 3. Delete service accounts
# 4. Clean up IAM bindings
# 5. Optionally disable APIs
```

### Manual Cleanup Verification
```bash
# Verify all resources are removed
gcloud functions list --filter="name~quiz"
gsutil ls -p ${PROJECT_ID} | grep quiz
gcloud iam service-accounts list --filter="email~quiz"
```

## Customization

### Adjusting AI Model Configuration
- Modify the Gemini model version in function code
- Adjust temperature and token limits for different content types
- Implement custom prompt templates for specific educational domains

### Scaling Configuration
- Increase function memory for processing larger documents
- Adjust function timeout for complex content analysis
- Configure concurrent execution limits based on usage patterns

### Storage Optimization
- Customize lifecycle policies for different content types
- Implement bucket notifications for automated processing
- Add encryption keys for enhanced security

### Integration Examples
- Connect to learning management systems (LMS)
- Integrate with authentication providers (Google Workspace, SAML)
- Add webhooks for real-time notifications

## Troubleshooting

### Common Issues

**Functions failing to deploy:**
- Verify APIs are enabled: `gcloud services list --enabled`
- Check IAM permissions: `gcloud projects get-iam-policy ${PROJECT_ID}`
- Review build logs: `gcloud builds list --limit=5`

**Vertex AI access errors:**
- Ensure Vertex AI API is enabled
- Verify service account has `roles/aiplatform.user`
- Check project quotas for Vertex AI usage

**Storage permission errors:**
- Confirm bucket exists: `gsutil ls gs://bucket-name`
- Verify service account has storage access
- Check bucket IAM policies

### Performance Optimization
- Monitor function cold starts and adjust memory allocation
- Implement connection pooling for storage operations
- Use Cloud CDN for frequently accessed quizzes
- Consider Cloud Run for sustained traffic patterns

### Cost Optimization
- Set up budget alerts for unexpected charges
- Monitor Vertex AI token usage patterns
- Implement caching for repeated content processing
- Use preemptible instances for batch processing

## Support and Documentation

### Google Cloud Documentation
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Additional Resources
- [Gemini Model Reference](https://cloud.google.com/vertex-ai/generative-ai/docs/model-reference/gemini)
- [Cloud Storage Best Practices](https://cloud.google.com/storage/docs/best-practices)
- [Serverless Best Practices](https://cloud.google.com/serverless/whitepaper)

### Community Support
- Google Cloud Community Forums
- Stack Overflow (google-cloud-platform tag)
- Terraform Google Provider GitHub Issues

For issues specific to this infrastructure code, refer to the original recipe documentation or create an issue in the repository.