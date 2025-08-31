# Infrastructure as Code for Word Count API with Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Word Count API with Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud account with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Admin
  - Storage Admin
  - Service Usage Admin
  - Project Editor (for enabling APIs)
- `jq` command-line JSON processor (for testing)
- `curl` command-line tool (for API testing)

## Architecture Overview

This solution deploys:

- **Cloud Function**: HTTP-triggered serverless function for text analysis
- **Cloud Storage Bucket**: Storage for file-based text processing
- **IAM Bindings**: Secure access between services
- **API Services**: Required Google Cloud APIs (Cloud Functions, Storage, Build, Run)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for infrastructure as code, providing native integration with Google Cloud services and built-in state management.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DEPLOYMENT_NAME="word-count-api"

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --service-account=${PROJECT_ID}@appspot.gserviceaccount.com \
    --local-source=infrastructure-manager/ \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

Terraform provides a mature, multi-cloud infrastructure as code solution with extensive Google Cloud provider support and community modules.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Get outputs
terraform output function_url
```

### Using Bash Scripts

Bash scripts provide direct `gcloud` CLI commands for environments where Infrastructure Manager or Terraform are not preferred.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployed API (optional)
./scripts/test-api.sh

# View deployment status
gcloud functions list --filter="name:word-count-api"
```

## Configuration Variables

Each implementation supports the following customizable variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `function_name` | Cloud Function name | `word-count-api` | No |
| `bucket_name` | Storage bucket name | Auto-generated | No |
| `function_memory` | Function memory allocation | `256Mi` | No |
| `function_timeout` | Function timeout in seconds | `60` | No |
| `max_instances` | Maximum function instances | `10` | No |

## Testing the Deployment

After successful deployment, test the API functionality:

```bash
# Get the function URL (varies by deployment method)
# For Terraform: terraform output function_url
# For Infrastructure Manager: Check deployment outputs
# For Bash: Stored in $FUNCTION_URL variable

# Test API health check
curl -X GET "${FUNCTION_URL}"

# Test direct text analysis
curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d '{
      "text": "This is a sample text for word counting analysis."
    }' | jq '.'

# Test file-based analysis (requires uploading a file first)
echo "Sample document content for analysis." > test.txt
gcloud storage cp test.txt gs://${BUCKET_NAME}/test.txt

curl -X POST "${FUNCTION_URL}" \
    -H "Content-Type: application/json" \
    -d "{
      \"bucket_name\": \"${BUCKET_NAME}\",
      \"file_path\": \"test.txt\"
    }" | jq '.'
```

Expected response format:
```json
{
  "analysis": {
    "word_count": 6,
    "character_count": 42,
    "character_count_no_spaces": 36,
    "paragraph_count": 1,
    "estimated_reading_time_minutes": 1
  },
  "input_source": "direct_text",
  "api_version": "1.0"
}
```

## Monitoring and Logging

After deployment, monitor your resources:

```bash
# View function logs
gcloud functions logs read word-count-api --gen2 --limit=20

# Monitor function metrics
gcloud functions describe word-count-api --gen2 \
    --format="table(name,state,updateTime)"

# Check storage bucket usage
gcloud storage ls -L gs://${BUCKET_NAME}

# View function performance metrics in Cloud Console
echo "Visit: https://console.cloud.google.com/functions/details/${REGION}/word-count-api?project=${PROJECT_ID}"
```

## Security Considerations

This deployment implements security best practices:

- **Least Privilege IAM**: Function service account has minimal required permissions
- **Uniform Bucket Access**: Cloud Storage bucket uses uniform bucket-level access
- **HTTPS Only**: Function automatically provides HTTPS endpoints
- **CORS Headers**: Configured for secure cross-origin requests
- **Input Validation**: Function validates all input parameters
- **Error Handling**: Comprehensive error responses without sensitive information exposure

## Cost Optimization

The deployment is optimized for cost efficiency:

- **Free Tier Compatible**: Stays within Cloud Functions free tier limits
- **Auto-scaling**: Scales to zero when not in use
- **Optimized Memory**: Uses minimal memory allocation (256Mi)
- **Regional Storage**: Uses regional storage class for frequently accessed files
- **Lifecycle Management**: Consider adding bucket lifecycle rules for long-term storage

Estimated monthly costs (beyond free tier):
- Cloud Functions: $0.40 per 1M invocations
- Cloud Storage: $0.020 per GB-month (regional storage)
- Cloud Build: $0.003 per build-minute

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up Terraform state (optional)
rm -rf .terraform terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --filter="name:word-count-api"
gcloud storage buckets list --filter="name:word-count-files"
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   # Enable required APIs
   gcloud services enable cloudfunctions.googleapis.com storage.googleapis.com cloudbuild.googleapis.com run.googleapis.com
   ```

2. **Insufficient Permissions**
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles to your user account
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/cloudfunctions.admin"
   ```

3. **Function Deployment Fails**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5
   
   # View detailed build logs
   gcloud builds log [BUILD_ID]
   ```

4. **Storage Access Issues**
   ```bash
   # Verify bucket permissions
   gcloud storage buckets get-iam-policy gs://${BUCKET_NAME}
   
   # Test bucket access
   echo "test" | gcloud storage cp - gs://${BUCKET_NAME}/test-access.txt
   ```

### Validation Commands

```bash
# Verify all components are deployed
gcloud functions describe word-count-api --gen2 --format="value(state)"
gcloud storage buckets describe gs://${BUCKET_NAME} --format="value(name)"

# Test connectivity
curl -f -X GET "${FUNCTION_URL}" > /dev/null && echo "✅ Function accessible" || echo "❌ Function not accessible"

# Check function health
gcloud functions logs read word-count-api --gen2 --limit=1 --format="value(textPayload)"
```

## Customization

### Function Configuration

Modify function settings in your chosen IaC implementation:

- **Memory**: Increase for larger document processing
- **Timeout**: Extend for complex text analysis
- **Concurrency**: Adjust max instances based on expected load
- **Environment Variables**: Add configuration parameters

### Security Enhancements

For production deployments, consider:

- Enable IAM authentication instead of `--allow-unauthenticated`
- Implement API key validation
- Add request rate limiting
- Enable Cloud Armor for DDoS protection
- Configure VPC connector for private network access

### Performance Optimization

- Use Cloud CDN for caching frequent requests
- Implement Cloud Memorystore for result caching
- Add Cloud Monitoring alerts for performance tracking
- Configure auto-scaling parameters based on usage patterns

## Support

For issues with this infrastructure code, refer to:

- [Original recipe documentation](../word-count-api-functions.md)
- [Google Cloud Functions documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For recipe-specific questions, consult the main recipe file in the parent directory.