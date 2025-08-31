# Training Data Quality Assessment - Terraform Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) for deploying an automated training data quality assessment system using Vertex AI and Cloud Functions on Google Cloud Platform.

## Architecture Overview

The infrastructure deploys:

- **Cloud Storage Bucket**: Stores training datasets and analysis reports
- **Cloud Function**: Serverless processing engine for data quality analysis
- **Service Account**: Dedicated IAM identity with minimal required permissions
- **Vertex AI Integration**: Gemini models for advanced content analysis
- **Pub/Sub Topic** (optional): Automated triggers for new data uploads
- **Cloud Monitoring Dashboard** (optional): Performance and usage monitoring

## Features

- **Automated Bias Detection**: Implements Google Cloud recommended metrics (DPS, DPPTL)
- **Content Quality Analysis**: Uses Vertex AI Gemini for language assessment
- **Vocabulary Diversity Analysis**: Statistical analysis of text richness
- **Actionable Recommendations**: Prioritized suggestions for data improvement
- **Cost Controls**: Configurable limits and sample sizes
- **Security Best Practices**: Least privilege IAM and encrypted storage

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **Terraform** >= 1.5.0 installed
3. **gcloud CLI** installed and authenticated
4. **Required APIs** will be automatically enabled by Terraform:
   - Cloud Functions API
   - Vertex AI API
   - Cloud Storage API
   - Cloud Build API
   - Pub/Sub API
   - Cloud Monitoring API

## Quick Start

### 1. Initialize Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

```bash
# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration file
nano terraform.tfvars
```

**Required variables to set:**
```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Deployment

After deployment, use the output commands to test:

```bash
# Upload sample data (provided automatically)
gsutil ls gs://[bucket-name]/datasets/

# Trigger analysis via HTTP
curl -X POST -H "Content-Type: application/json" \
  -d '{
    "project_id": "your-project-id",
    "region": "us-central1", 
    "bucket_name": "your-bucket-name",
    "dataset_path": "datasets/sample_training_data.json"
  }' \
  [function-url]

# Check results
gsutil ls gs://[bucket-name]/reports/
```

## Configuration Options

### Environment-Specific Configurations

**Development:**
```hcl
environment = "dev"
function_memory_mb = 512
sample_size_for_analysis = 3
daily_api_call_limit = 50
allow_unauthenticated = true
```

**Production:**
```hcl
environment = "prod"
function_memory_mb = 2048
sample_size_for_analysis = 10
daily_api_call_limit = 500
allow_unauthenticated = false
enable_automatic_analysis = true
```

### Cost Optimization

Control costs with these variables:
- `sample_size_for_analysis`: Number of samples sent to Gemini API
- `daily_api_call_limit`: Maximum API calls per day
- `bucket_lifecycle_days`: Auto-delete old data
- `vertex_ai_model`: Choose between `gemini-1.5-flash` (cheaper) or `gemini-1.5-pro` (more capable)

### Security Configuration

- `allow_unauthenticated`: Set to `false` for production
- `ingress_settings`: Control network access
- `vpc_network` and `subnet`: Use custom VPC if required

## File Structure

```
terraform/
├── main.tf                    # Main infrastructure resources
├── variables.tf               # Variable definitions and validation
├── outputs.tf                 # Output values and usage information
├── versions.tf                # Provider requirements and configuration
├── terraform.tfvars.example  # Example configuration
├── README.md                  # This file
└── function_source/           # Cloud Function source code
    ├── main.py               # Function implementation
    └── requirements.txt      # Python dependencies
```

## Key Terraform Resources

### Core Infrastructure
- `google_storage_bucket.data_quality_bucket`: Main storage bucket
- `google_cloudfunctions_function.data_quality_analyzer`: Analysis function
- `google_service_account.function_sa`: Dedicated service account

### IAM and Security
- `google_project_iam_member.function_vertex_ai`: Vertex AI access
- `google_project_iam_member.function_storage`: Storage access
- `google_cloudfunctions_function_iam_member.invoker`: Function invocation

### Optional Features
- `google_pubsub_topic.data_upload_notifications`: Auto-trigger system
- `google_monitoring_dashboard.data_quality_dashboard`: Monitoring
- `google_storage_notification.data_upload_trigger`: Storage events

## Outputs and Usage

After deployment, Terraform provides:

- **Function URL**: HTTP endpoint for triggering analysis
- **Bucket Names**: Storage locations for data and reports
- **Test Commands**: Ready-to-use curl and gcloud commands
- **Monitoring URLs**: Links to dashboards and logs

## Data Quality Analysis Features

### Bias Detection Metrics

1. **Difference in Population Size (DPS)**
   - Measures demographic representation imbalance
   - Configurable threshold (default: 10%)

2. **Difference in Positive Proportions in True Labels (DPPTL)**
   - Detects label distribution bias across demographics
   - Follows Vertex AI fairness evaluation guidelines

### Content Quality Assessment

- **Language Consistency**: Grammar, spelling, clarity
- **Bias Detection**: Subtle language biases and stereotypes
- **Vocabulary Diversity**: Richness and variety of language
- **Sentiment Analysis**: Consistency with labels

### Report Generation

Reports include:
- Dataset statistics and metadata
- Bias analysis with quantified metrics
- Content quality scores and issues
- Prioritized recommendations for improvement
- Actionable next steps

## Monitoring and Observability

### Cloud Monitoring Dashboard

When enabled, provides:
- Function execution metrics
- API usage tracking
- Error rates and latency
- Cost tracking

### Cloud Logging

Function logs include:
- Analysis progress and timing
- Detailed error messages
- Performance metrics
- API call tracking

### Alerts and Notifications

Configure alerts for:
- Function failures
- High API usage
- Budget thresholds
- Analysis completion

## Cost Management

### Estimated Monthly Costs

- **Cloud Storage**: ~$0.023 per GB/month
- **Cloud Functions**: ~$0.0000004 per invocation + compute time
- **Vertex AI Gemini**: ~$0.001 per 1K input tokens
- **Total Estimated**: $5-25/month depending on usage

### Cost Control Features

1. **Configurable Sample Sizes**: Limit data sent to expensive APIs
2. **Daily API Limits**: Prevent unexpected charges
3. **Automatic Data Cleanup**: Delete old reports and temporary files
4. **Budget Alerts**: Monitor spending in real-time

## Security Best Practices

### Implemented Security Measures

- **Least Privilege IAM**: Minimal required permissions
- **Encrypted Storage**: All data encrypted at rest and in transit
- **Private Service Account**: Dedicated identity for function
- **HTTPS Only**: All communication over secure channels
- **Audit Logging**: Complete audit trail of all operations

### Additional Security Options

- **VPC Integration**: Deploy in private networks
- **Identity-based Access**: Require authentication
- **Custom IAM Roles**: Further restrict permissions
- **Private Google Access**: Access APIs without internet

## Troubleshooting

### Common Issues

1. **API Not Enabled**
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

2. **Permission Denied**
   ```bash
   gcloud auth application-default login
   ```

3. **Region Not Supported**
   - Ensure region supports both Vertex AI and Cloud Functions
   - Use `us-central1`, `us-east1`, or `europe-west1`

4. **Function Timeout**
   - Increase `function_timeout_seconds`
   - Reduce `sample_size_for_analysis`

### Debug Commands

```bash
# Check function logs
gcloud functions logs read data-quality-analyzer --region=us-central1

# Test function locally
gcloud functions call data-quality-analyzer --data='{"project_id":"..."}'

# Verify IAM permissions
gcloud projects get-iam-policy PROJECT_ID

# Check API enablement
gcloud services list --enabled
```

## Cleanup

### Destroy Infrastructure

```bash
# Destroy all resources
terraform destroy

# Confirm destruction
yes
```

### Manual Cleanup (if needed)

```bash
# Delete storage bucket contents
gsutil -m rm -r gs://bucket-name/*

# Delete function logs
gcloud logging sinks delete sink-name
```

## Support and Documentation

- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Google Cloud ML Fairness](https://cloud.google.com/vertex-ai/docs/evaluation/intro-evaluation-fairness)

## Contributing

To contribute improvements:

1. Test changes in development environment
2. Update documentation
3. Validate with `terraform plan`
4. Submit pull request with detailed description

## License

This infrastructure code is provided under the same license as the parent recipe project.