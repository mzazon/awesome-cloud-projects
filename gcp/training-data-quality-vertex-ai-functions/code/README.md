# Infrastructure as Code for Training Data Quality Assessment with Vertex AI and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Training Data Quality Assessment with Vertex AI and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud account with billing enabled
- gcloud CLI installed and configured (or Cloud Shell access)
- Appropriate IAM permissions for:
  - Vertex AI (roles/aiplatform.user)
  - Cloud Functions (roles/cloudfunctions.admin)
  - Cloud Storage (roles/storage.admin)
  - IAM (roles/iam.serviceAccountAdmin)
  - Service Usage (roles/serviceusage.serviceUsageAdmin)
- Basic understanding of machine learning data validation concepts
- Python programming experience for Cloud Function development

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/training-data-quality \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source infrastructure-manager/ \
    --input-values project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh
```

## Infrastructure Components

This solution deploys the following Google Cloud resources:

### Core Services
- **Cloud Functions**: Serverless function for data quality analysis
- **Cloud Storage**: Bucket for training datasets and quality reports
- **Vertex AI**: Gemini API access for content analysis

### IAM and Security
- **Service Account**: Dedicated service account for Cloud Functions
- **IAM Bindings**: Least privilege permissions for Vertex AI and Storage access
- **API Services**: Required Google Cloud APIs enabled

### Monitoring and Logging
- **Cloud Logging**: Function execution logs and error tracking
- **Cloud Monitoring**: Performance metrics and alerting (optional)

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | none | ✅ |
| `REGION` | Deployment region | `us-central1` | ❌ |
| `BUCKET_NAME` | Storage bucket name (auto-generated if not provided) | `training-data-quality-${random}` | ❌ |
| `FUNCTION_NAME` | Cloud Function name | `data-quality-analyzer` | ❌ |

### Customizable Parameters

- **Function Memory**: Default 1024MB (configurable in IaC)
- **Function Timeout**: Default 540s (configurable in IaC)
- **Storage Class**: Default STANDARD (configurable in IaC)
- **Python Runtime**: Default python312 (latest supported)

## Post-Deployment Setup

After successful infrastructure deployment:

1. **Upload Sample Data**:
   ```bash
   # Create sample training dataset
   cat > sample_training_data.json << 'EOF'
   [
     {"text": "The software engineer completed the project efficiently", "label": "positive", "demographic": "male"},
     {"text": "She managed to finish the coding task adequately", "label": "neutral", "demographic": "female"}
   ]
   EOF
   
   # Upload to Cloud Storage
   gsutil cp sample_training_data.json gs://${BUCKET_NAME}/datasets/
   ```

2. **Test the Analysis Function**:
   ```bash
   # Get function URL from Terraform output or gcloud
   FUNCTION_URL=$(gcloud functions describe data-quality-analyzer --format="value(httpsTrigger.url)")
   
   # Create analysis request
   curl -X POST \
       -H "Content-Type: application/json" \
       -d '{
         "project_id": "'${PROJECT_ID}'",
         "region": "'${REGION}'",
         "bucket_name": "'${BUCKET_NAME}'",
         "dataset_path": "datasets/sample_training_data.json"
       }' \
       ${FUNCTION_URL}
   ```

3. **View Results**:
   ```bash
   # List generated quality reports
   gsutil ls gs://${BUCKET_NAME}/reports/
   
   # Download and view latest report
   LATEST_REPORT=$(gsutil ls gs://${BUCKET_NAME}/reports/ | tail -1)
   gsutil cp ${LATEST_REPORT} ./quality_report.json
   cat quality_report.json | jq '.'
   ```

## Monitoring and Troubleshooting

### View Function Logs
```bash
# Check Cloud Function execution logs
gcloud functions logs read data-quality-analyzer --limit 50

# Follow logs in real-time
gcloud functions logs read data-quality-analyzer --follow
```

### Monitor API Usage
```bash
# Check Vertex AI API quota usage
gcloud logging read 'resource.type="consumed_api" AND protoPayload.serviceName="aiplatform.googleapis.com"' --limit 10
```

### Debug Common Issues

1. **Permission Errors**:
   - Verify service account has required IAM roles
   - Check API enablement status
   
2. **Function Timeout**:
   - Increase timeout in IaC configuration
   - Optimize dataset size for testing

3. **Storage Access Issues**:
   - Verify bucket exists and is accessible
   - Check storage IAM permissions

## Cost Optimization

### Estimated Costs
- **Cloud Functions**: $0.40/million invocations + $0.0000025/GB-sec
- **Vertex AI Gemini API**: ~$0.00025-0.0005 per request
- **Cloud Storage**: $0.02/GB/month for Standard storage
- **Total for testing**: $15-25 (includes API calls and storage)

### Cost-Saving Tips
1. Use Cloud Scheduler for batch processing instead of continuous monitoring
2. Implement request batching for Vertex AI API calls
3. Set up budget alerts for cost monitoring
4. Use Cloud Storage lifecycle policies for report archival

## Security Considerations

### Best Practices Implemented
- **Least Privilege IAM**: Service account has minimal required permissions
- **API Security**: Function uses service account authentication
- **Data Encryption**: Storage bucket uses Google-managed encryption
- **Network Security**: Function runs in Google's secure environment

### Additional Security Enhancements
1. **VPC Connector**: Deploy function in private VPC (optional)
2. **Customer-Managed Encryption**: Use Cloud KMS for additional encryption
3. **Identity-Aware Proxy**: Add IAP for function access control
4. **Audit Logging**: Enable Cloud Audit Logs for compliance

## Cleanup

### Using Infrastructure Manager
```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/training-data-quality
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Delete Cloud Function
gcloud functions delete data-quality-analyzer --region=${REGION} --quiet

# Delete Storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Delete service account
gcloud iam service-accounts delete data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet

# Disable APIs (optional)
gcloud services disable cloudfunctions.googleapis.com
gcloud services disable aiplatform.googleapis.com
```

## Customization Examples

### Modify Function Configuration
```bash
# Deploy with custom memory and timeout
gcloud functions deploy data-quality-analyzer \
    --memory 2048MB \
    --timeout 900s \
    --runtime python312
```

### Add Custom Bias Metrics
Modify the `main.py` function code to include additional bias detection algorithms:

```python
def analyze_custom_bias_metrics(df):
    """Implement custom bias detection for specific use cases."""
    # Add industry-specific bias detection logic
    # Example: Healthcare data bias detection
    # Example: Financial services fairness metrics
    pass
```

### Integrate with CI/CD
```yaml
# Example Cloud Build configuration
steps:
- name: 'gcr.io/cloud-builders/gcloud'
  args: ['functions', 'deploy', 'data-quality-analyzer', '--source', '.']
```

## Integration Patterns

### Event-Driven Processing
```bash
# Add Pub/Sub trigger for automatic analysis
gcloud functions deploy data-quality-analyzer \
    --trigger-topic training-data-uploaded \
    --source .
```

### Scheduled Analysis
```bash
# Create Cloud Scheduler job for regular quality checks
gcloud scheduler jobs create http quality-check-schedule \
    --schedule="0 9 * * 1" \
    --uri=${FUNCTION_URL} \
    --http-method=POST \
    --message-body='{"project_id":"'${PROJECT_ID}'","bucket_name":"'${BUCKET_NAME}'"}'
```

## Support and Documentation

- **Recipe Documentation**: Refer to the parent recipe markdown file for detailed implementation steps
- **Google Cloud Documentation**: [Cloud Functions](https://cloud.google.com/functions/docs), [Vertex AI](https://cloud.google.com/vertex-ai/docs)
- **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Infrastructure Manager**: [Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

When modifying this infrastructure code:

1. Test all changes in a development environment
2. Validate security configurations
3. Update documentation for any new parameters
4. Follow Google Cloud best practices for resource naming and tagging
5. Consider cost implications of infrastructure changes

For issues with this infrastructure code, please refer to the original recipe documentation or Google Cloud support resources.