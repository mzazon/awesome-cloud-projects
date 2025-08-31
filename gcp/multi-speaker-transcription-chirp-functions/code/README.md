# Infrastructure as Code for Multi-Speaker Transcription with Chirp and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Speaker Transcription with Chirp and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Terraform 1.0+ (for Terraform implementation)
- Appropriate permissions for resource creation:
  - Speech-to-Text API Admin
  - Cloud Functions Admin
  - Storage Admin
  - Cloud Build Editor
  - Service Account Admin
  - Project IAM Admin
- Active Google Cloud project with billing enabled

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC solution that provides declarative infrastructure management with built-in drift detection and state management.

```bash
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create a deployment
gcloud infra-manager deployments create multi-speaker-transcription \
    --location=${REGION} \
    --service-account=$(gcloud config get-value account) \
    --git-source-repo="https://github.com/your-repo/multi-speaker-transcription" \
    --git-source-directory="infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe multi-speaker-transcription \
    --location=${REGION}
```

### Using Terraform

Terraform provides consistent infrastructure management across multiple cloud providers with extensive community support and advanced state management capabilities.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Verify resources were created
terraform show
```

### Using Bash Scripts

Bash scripts provide direct CLI-based deployment for simple automation and CI/CD integration without additional tooling dependencies.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud functions list --filter="name:process-audio-transcription"
gsutil ls -p ${PROJECT_ID} | grep -E "(audio-input|transcripts-output)"
```

## Configuration

### Environment Variables

All implementations support the following environment variables:

- `PROJECT_ID`: Google Cloud project ID (required)
- `REGION`: Deployment region (default: us-central1)
- `RANDOM_SUFFIX`: Unique suffix for resource names (auto-generated if not set)

### Terraform Variables

The Terraform implementation accepts these variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
function_memory    = "2GB"
function_timeout   = 540
max_instances     = 5
storage_class     = "STANDARD"
```

### Infrastructure Manager Configuration

Infrastructure Manager uses the `main.yaml` configuration file with these key parameters:

```yaml
variables:
  project_id:
    description: "Google Cloud project ID"
    type: string
  
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  
  function_config:
    description: "Cloud Function configuration"
    type: object
    default:
      memory: "2GB"
      timeout: 540
      max_instances: 5
```

## Architecture Overview

The infrastructure deploys:

1. **Cloud Storage Buckets**:
   - Input bucket for audio files with lifecycle policies
   - Output bucket for transcription results
   - Proper IAM permissions and security settings

2. **Cloud Function**:
   - Event-triggered function for audio processing
   - Chirp 3 model integration with speaker diarization
   - Automatic scaling and error handling
   - Environment variables for bucket configuration

3. **IAM Service Accounts**:
   - Function service account with minimal required permissions
   - Speech-to-Text API access
   - Storage read/write permissions

4. **API Enablement**:
   - Cloud Speech-to-Text API
   - Cloud Functions API
   - Cloud Storage API
   - Cloud Build API

## Testing Your Deployment

After deployment, test the infrastructure:

1. **Upload a test audio file**:
   ```bash
   # Download sample audio
   curl -L "https://storage.googleapis.com/cloud-samples-tests/speech/multi-speaker-sample.wav" \
       -o test-audio.wav
   
   # Upload to input bucket
   gsutil cp test-audio.wav gs://${PROJECT_ID}-audio-input-*/
   ```

2. **Monitor function execution**:
   ```bash
   # Check function logs
   gcloud functions logs read process-audio-transcription \
       --region=${REGION} \
       --limit=10
   ```

3. **Verify output generation**:
   ```bash
   # List generated transcripts
   gsutil ls gs://${PROJECT_ID}-transcripts-output-*/transcripts/
   
   # Download and view results
   gsutil cp gs://${PROJECT_ID}-transcripts-output-*/transcripts/* ./
   ```

## Monitoring and Observability

The infrastructure includes built-in monitoring:

- **Cloud Functions Metrics**: Execution count, duration, errors
- **Cloud Storage Metrics**: Request count, data transfer
- **Speech-to-Text Metrics**: API usage and success rates

Access monitoring dashboards:

```bash
# View function metrics
gcloud functions describe process-audio-transcription \
    --region=${REGION} \
    --format="value(status.url)"

# Check logs for errors
gcloud functions logs read process-audio-transcription \
    --region=${REGION} \
    --filter="severity>=ERROR"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete multi-speaker-transcription \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -f terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --filter="name:process-audio-transcription"
gsutil ls -p ${PROJECT_ID} | grep -E "(audio-input|transcripts-output)" || echo "Buckets cleaned up"
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Ensure proper IAM roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:$(gcloud config get-value account)" \
       --role="roles/cloudfunctions.admin"
   ```

2. **API Not Enabled**:
   ```bash
   # Enable required APIs
   gcloud services enable \
       speech.googleapis.com \
       cloudfunctions.googleapis.com \
       storage.googleapis.com \
       cloudbuild.googleapis.com
   ```

3. **Function Deployment Failures**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=5 --format="table(id,status,createTime)"
   ```

4. **Storage Access Issues**:
   ```bash
   # Verify bucket permissions
   gsutil iam get gs://${PROJECT_ID}-audio-input-*
   ```

### Performance Optimization

1. **Function Configuration**:
   - Increase memory for large audio files (up to 8GB)
   - Adjust timeout based on expected processing time
   - Configure concurrency limits to manage costs

2. **Storage Optimization**:
   - Use regional storage for better performance
   - Enable lifecycle policies for cost optimization
   - Consider Coldline storage for long-term retention

3. **Speech-to-Text Settings**:
   - Adjust speaker count ranges based on expected content
   - Enable only required features to optimize costs
   - Use appropriate audio encoding for best results

## Cost Estimation

Estimated costs for typical usage:

- **Cloud Functions**: $0.40 per 1M invocations + $0.0000025/GB-second
- **Cloud Storage**: $0.020/GB/month (Standard), $0.005/1000 operations
- **Speech-to-Text**: $0.006/15 seconds (Chirp 3), $0.003/15 seconds (speaker diarization)

Monthly cost example for 100 hours of audio processing:
- Functions: ~$10-15
- Storage: ~$5-10
- Speech-to-Text: ~$150-200
- **Total**: ~$165-225/month

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../multi-speaker-transcription-chirp-functions.md)
2. Review [Google Cloud Speech-to-Text documentation](https://cloud.google.com/speech-to-text/docs)
3. Consult [Cloud Functions best practices](https://cloud.google.com/functions/docs/bestpractices)
4. Visit [Infrastructure Manager documentation](https://cloud.google.com/infrastructure-manager/docs)
5. Reference [Terraform Google Cloud provider docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Security Considerations

The infrastructure follows Google Cloud security best practices:

- **Least Privilege IAM**: Service accounts have minimal required permissions
- **Private Storage**: Buckets are not publicly accessible
- **Encryption**: Data encrypted at rest and in transit by default
- **VPC Connector**: Optional VPC integration for enhanced network security
- **Audit Logging**: Cloud Audit Logs enabled for compliance

Review and customize security settings based on your organization's requirements.