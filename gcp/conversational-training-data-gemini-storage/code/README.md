# Infrastructure as Code for Conversational AI Training Data Generation with Gemini and Cloud Storage

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Conversational AI Training Data Generation with Gemini and Cloud Storage".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Storage bucket creation and management
  - Cloud Functions deployment
  - Vertex AI API access
  - IAM role management
  - Service account creation
- Basic understanding of conversational AI and machine learning concepts
- Estimated cost: $5-15 for resources created during deployment

> **Note**: This solution uses Vertex AI Gemini API which charges per token. Costs will vary based on the volume of conversational data generated.

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Enable required APIs
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/DEPLOYMENT_NAME \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo="https://github.com/your-repo/path" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/DEPLOYMENT_NAME
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify deployment
terraform output
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

# Verify deployment
gcloud functions list --filter="name~conversation"
gsutil ls gs://training-data-*
```

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage**: Bucket with organized folder structure for training data
- **Cloud Functions**: 
  - Conversation generator using Gemini API
  - Data processor for formatting training data
- **IAM Roles**: Service accounts with appropriate permissions
- **Vertex AI**: API enablement for Gemini model access
- **Monitoring**: Cloud Logging and basic monitoring setup

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | N/A | Yes |
| `region` | Deployment region | `us-central1` | No |
| `bucket_prefix` | Cloud Storage bucket name prefix | `training-data` | No |
| `function_memory` | Cloud Function memory allocation | `1024MB` | No |
| `function_timeout` | Cloud Function timeout | `540s` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | N/A | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `bucket_name` | Cloud Storage bucket name | Auto-generated | No |
| `enable_versioning` | Enable bucket versioning | `true` | No |
| `conversation_scenarios` | List of conversation scenarios | See variables.tf | No |

### Environment Variables for Scripts

| Variable | Description | Example |
|----------|-------------|---------|
| `PROJECT_ID` | Google Cloud Project ID | `my-ai-project` |
| `REGION` | Deployment region | `us-central1` |
| `ZONE` | Deployment zone | `us-central1-a` |

## Usage Examples

### Generate Training Data

After deployment, use the Cloud Functions to generate conversational training data:

```bash
# Get function URL (from Terraform output or gcloud)
FUNCTION_URL=$(gcloud functions describe conversation-generator \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Generate customer support conversations
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "num_conversations": 20,
        "scenario": "customer_support"
    }'

# Generate e-commerce conversations  
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "num_conversations": 15,
        "scenario": "e_commerce"
    }'
```

### Process Generated Data

```bash
# Get processor function URL
PROCESSOR_URL=$(gcloud functions describe data-processor \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Process conversations into training formats
curl -X POST ${PROCESSOR_URL} \
    -H "Content-Type: application/json" \
    -d '{"bucket_name": "BUCKET_NAME"}'
```

### Access Training Data

```bash
# List generated conversations
gsutil ls gs://BUCKET_NAME/raw-conversations/

# Download formatted training data
gsutil cp gs://BUCKET_NAME/formatted-training/training_data.jsonl ./
gsutil cp gs://BUCKET_NAME/formatted-training/training_data.csv ./

# View processing statistics
gsutil cat gs://BUCKET_NAME/processed-conversations/processing_stats.json
```

## Monitoring and Observability

### View Function Logs

```bash
# Monitor conversation generation
gcloud functions logs read conversation-generator \
    --region=${REGION} \
    --limit=50

# Monitor data processing
gcloud functions logs read data-processor \
    --region=${REGION} \
    --limit=20
```

### Check Storage Usage

```bash
# Monitor bucket size and object count
gsutil du -sh gs://BUCKET_NAME
gsutil ls -l gs://BUCKET_NAME/** | wc -l
```

### Monitor API Usage

```bash
# Check Vertex AI API usage
gcloud logging read "resource.type=vertex_ai_endpoint" --limit=20

# Monitor function invocations
gcloud logging read "resource.type=cloud_function" --limit=20
```

## Security Considerations

### IAM Permissions

The infrastructure creates service accounts with minimal required permissions:

- **Cloud Functions Service Account**:
  - `storage.objectCreator` on the training data bucket
  - `aiplatform.user` for Vertex AI API access
  - `logging.logWriter` for function logging

- **Default Service Account**: Used for Cloud Functions runtime

### Data Protection

- **Bucket Versioning**: Enabled by default for data protection
- **IAM Policies**: Restrict access to authorized service accounts only
- **API Access**: Vertex AI access limited to specific service accounts
- **Network Security**: Cloud Functions use default VPC with standard security

### Best Practices Implemented

- Least privilege IAM roles
- Service account isolation
- Audit logging enabled
- Resource labeling for governance
- Automatic cleanup policies

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable storage.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.admin"
   ```

3. **Function Deployment Fails**
   ```bash
   # Check Cloud Build status
   gcloud builds list --limit=5
   
   # View detailed function logs
   gcloud functions logs read FUNCTION_NAME --limit=50
   ```

4. **Storage Access Issues**
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://BUCKET_NAME
   
   # Test bucket access
   echo "test" | gsutil cp - gs://BUCKET_NAME/test.txt
   ```

### Debugging Steps

1. **Verify Prerequisites**:
   - Check gcloud authentication: `gcloud auth list`
   - Verify project access: `gcloud projects describe ${PROJECT_ID}`
   - Confirm billing: `gcloud billing projects describe ${PROJECT_ID}`

2. **Check Resource Status**:
   - Functions: `gcloud functions list`
   - Storage: `gsutil ls`
   - APIs: `gcloud services list --enabled`

3. **Review Logs**:
   - Function logs: `gcloud functions logs read FUNCTION_NAME`
   - Build logs: `gcloud builds log BUILD_ID`
   - Audit logs: `gcloud logging read "protoPayload.authenticationInfo.principalEmail=SERVICE_ACCOUNT"`

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/DEPLOYMENT_NAME

# Verify cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification
gcloud functions list --filter="name~conversation"
gsutil ls gs://training-data-*
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Functions
gcloud functions delete conversation-generator --region=${REGION} --quiet
gcloud functions delete data-processor --region=${REGION} --quiet

# Delete Storage bucket
gsutil -m rm -r gs://BUCKET_NAME

# Delete service accounts (if created)
gcloud iam service-accounts delete SERVICE_ACCOUNT_EMAIL --quiet
```

## Cost Management

### Cost Estimation

- **Cloud Storage**: ~$0.02 per GB per month
- **Cloud Functions**: $0.0000004 per invocation + $0.0000025 per GB-second
- **Vertex AI Gemini**: ~$0.0003 per 1K input tokens, ~$0.0012 per 1K output tokens
- **Cloud Logging**: First 50GB per month free

### Cost Optimization Tips

1. **Use Lifecycle Policies**: Automatically archive old training data
   ```bash
   gsutil lifecycle set lifecycle.json gs://BUCKET_NAME
   ```

2. **Monitor Function Costs**: Set up budget alerts
   ```bash
   gcloud billing budgets create --billing-account=BILLING_ACCOUNT \
       --display-name="AI Training Budget" \
       --budget-amount=50
   ```

3. **Optimize Generation Batch Size**: Generate conversations in batches to reduce function invocation costs

## Customization

### Adding New Conversation Scenarios

1. **Update Templates**: Modify `conversation_templates.json`:
   ```json
   {
     "scenario": "finance",
     "context": "Financial advisory and banking support",
     "user_intents": ["account_inquiry", "loan_application", "investment_advice"],
     "conversation_length": "4-6 exchanges",
     "tone": "professional, trustworthy"
   }
   ```

2. **Redeploy Functions**: Update and redeploy the conversation generator function

### Extending Data Formats

1. **Modify Processor**: Add new format functions to the data processor
2. **Update Templates**: Include new format in processing workflow
3. **Test Compatibility**: Ensure new formats work with your ML frameworks

### Integration with ML Pipelines

1. **Add Webhook Triggers**: Configure Cloud Functions to trigger on storage events
2. **Connect to Vertex AI**: Automatically start training jobs when new data is processed
3. **Implement Quality Gates**: Add data validation before training

## Support

- **Recipe Documentation**: Refer to the original recipe for detailed implementation steps
- **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs), [Cloud Storage](https://cloud.google.com/storage/docs)
- **Community Support**: Google Cloud Community forums and Stack Overflow
- **Professional Support**: Google Cloud Support (for paid support plans)

## Contributing

To improve this infrastructure code:

1. Follow Google Cloud best practices
2. Test changes in a development environment
3. Update documentation for any new features
4. Consider backwards compatibility
5. Include appropriate error handling and logging

---

**Note**: This infrastructure deploys a production-ready conversational AI training data generation system. Monitor costs and adjust batch sizes based on your specific requirements and budget constraints.