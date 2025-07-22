# Infrastructure as Code for Real-Time Translation Services with Cloud Speech-to-Text and Cloud Translation

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Translation Services with Cloud Speech-to-Text and Cloud Translation".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution deploys a real-time translation platform that includes:

- **Cloud Run**: Serverless container hosting for WebSocket-based translation service
- **Cloud Speech-to-Text**: Streaming audio transcription with real-time processing
- **Cloud Translation**: Multi-language text translation using neural networks
- **Firestore**: NoSQL database for conversation persistence and real-time sync
- **Cloud Storage**: Durable storage for audio files with lifecycle management
- **Pub/Sub**: Event messaging for analytics and asynchronous processing
- **IAM**: Service accounts and permissions for secure API access

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Required APIs enabled:
  - Cloud Speech-to-Text API
  - Cloud Translation API
  - Cloud Run API
  - Firestore API
  - Pub/Sub API
  - Cloud Build API
- Appropriate IAM permissions for resource creation:
  - `roles/editor` or equivalent granular permissions
  - `roles/iam.serviceAccountAdmin`
  - `roles/resourcemanager.projectIamAdmin`

### Tool-Specific Prerequisites

#### Infrastructure Manager
- `gcloud config-connector` CLI component (for Infrastructure Manager)
- Google Cloud project with Infrastructure Manager API enabled

#### Terraform
- Terraform v1.0+ installed
- Google Cloud provider v4.0+ compatible

#### Bash Scripts
- `curl` and `openssl` utilities
- Node.js 18+ for application deployment testing

## Cost Estimation

Expected costs for testing and development usage:

- **Cloud Speech-to-Text**: ~$0.024 per minute of audio
- **Cloud Translation**: ~$20 per 1M characters translated  
- **Cloud Run**: Pay-per-use (free tier: 2M requests/month)
- **Firestore**: Pay-per-use (free tier: 1GB storage, 50K reads/day)
- **Cloud Storage**: ~$0.02 per GB/month
- **Pub/Sub**: Pay-per-use (free tier: 10GB/month)

Total estimated cost for moderate testing: **$5-15/month**

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-platform \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Check deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-platform
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan the deployment
terraform plan -var-file="terraform.tfvars"

# Apply the infrastructure
terraform apply -var-file="terraform.tfvars"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export BILLING_ACCOUNT_ID="your-billing-account-id"

# Deploy the complete solution
./scripts/deploy.sh

# Test the deployment
curl -f "$(gcloud run services describe translation-service-$(openssl rand -hex 3) --region=${REGION} --format='value(status.url)')/health"
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Compute zone | `us-central1-a` | No |
| `service_name` | Cloud Run service name | `translation-service` | No |
| `enable_apis` | Enable required Google Cloud APIs | `true` | No |
| `firestore_location` | Firestore database location | `us-central1` | No |
| `storage_class` | Cloud Storage bucket class | `STANDARD` | No |
| `max_instances` | Cloud Run max instances | `10` | No |
| `memory_limit` | Cloud Run memory allocation | `2Gi` | No |
| `cpu_limit` | Cloud Run CPU allocation | `2` | No |

### Security Configuration

The infrastructure implements security best practices:

- **Service Account**: Dedicated service account with minimal required permissions
- **IAM Roles**: Least-privilege access for Speech-to-Text, Translation, and Firestore
- **Container Security**: Non-root container execution with health checks
- **Network Security**: Private container communication with public HTTPS endpoints
- **Data Protection**: Automatic encryption at rest and in transit
- **Lifecycle Management**: Automated cleanup of temporary audio files

### Performance Tuning

For production deployments, consider these optimizations:

- **Cloud Run**: Adjust `memory_limit` and `cpu_limit` based on concurrent users
- **Firestore**: Configure regional replication for global accessibility
- **Cloud Storage**: Use `NEARLINE` or `COLDLINE` storage classes for archival
- **Pub/Sub**: Configure message retention and dead letter queues
- **Load Testing**: Use Cloud Load Testing to validate performance under load

## Deployment Verification

After deployment, verify the solution works correctly:

### 1. Check Service Health

```bash
# Get Cloud Run service URL
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format="value(status.url)")

# Test health endpoint
curl -f "${SERVICE_URL}/health"
```

Expected response:
```json
{
  "status": "healthy",
  "timestamp": "2025-01-XX-TXXXX"
}
```

### 2. Verify WebSocket Connection

```bash
# Install wscat for WebSocket testing
npm install -g wscat

# Test WebSocket connection
WS_URL=$(echo ${SERVICE_URL} | sed 's/https:/wss:/')
wscat -c ${WS_URL}
```

Send test message:
```json
{"type":"start_session","sourceLanguage":"en-US","targetLanguages":["es","fr"]}
```

### 3. Check Resource Creation

```bash
# Verify Firestore database
gcloud firestore databases describe --database='(default)'

# Check Pub/Sub topics
gcloud pubsub topics list --filter="name:translation"

# Verify Cloud Storage bucket
gsutil ls -b gs://${PROJECT_ID}-audio-files

# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} \
    --flatten="bindings[].members" \
    --filter="bindings.members:translation-service@"
```

## Testing the Solution

### Real-Time Translation Test

Use the provided test client to validate end-to-end functionality:

```bash
# Navigate to the application test directory
cd ../translation-app/client-test/

# Open the test client in a web browser
open index.html
# Or on Linux: xdg-open index.html
```

The test client provides:
- Microphone access for audio recording
- WebSocket connection to the translation service
- Real-time display of transcripts and translations
- Support for multiple source and target languages

### Load Testing

For performance validation:

```bash
# Install artillery for load testing
npm install -g artillery

# Create load test configuration
cat > load-test.yml << EOF
config:
  target: '${SERVICE_URL}'
  phases:
    - duration: 60
      arrivalRate: 5
scenarios:
  - name: "Health check load test"
    requests:
      - get:
          url: "/health"
EOF

# Run load test
artillery run load-test.yml
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-platform \
    --quiet

# Wait for deletion to complete
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/translation-platform
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var-file="terraform.tfvars" -auto-approve

# Clean up local state
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource removal
gcloud run services list --filter="name:translation-service"
gcloud firestore databases list
gcloud pubsub topics list --filter="name:translation"
```

### Manual Cleanup (if needed)

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Run service
gcloud run services delete translation-service-* --region=${REGION} --quiet

# Delete Firestore database
gcloud firestore databases delete --database='(default)' --quiet

# Remove Cloud Storage bucket
gsutil -m rm -r gs://${PROJECT_ID}-audio-files

# Delete Pub/Sub resources
gcloud pubsub subscriptions delete translation-processor --quiet
gcloud pubsub topics delete translation-events translation-dlq --quiet

# Remove service account
gcloud iam service-accounts delete translation-service@${PROJECT_ID}.iam.gserviceaccount.com --quiet

# Optionally delete the entire project
gcloud projects delete ${PROJECT_ID} --quiet
```

## Troubleshooting

### Common Issues

#### 1. API Enablement Errors
```bash
# Manually enable required APIs
gcloud services enable speech.googleapis.com translate.googleapis.com \
    run.googleapis.com firestore.googleapis.com pubsub.googleapis.com \
    cloudbuild.googleapis.com
```

#### 2. Permission Denied Errors
```bash
# Check current user permissions
gcloud auth list
gcloud projects get-iam-policy ${PROJECT_ID}

# Ensure proper roles are assigned
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="user:$(gcloud config get-value account)" \
    --role="roles/editor"
```

#### 3. Cloud Run Deployment Failures
```bash
# Check Cloud Build logs
gcloud builds list --limit=5

# Verify service account permissions
gcloud iam service-accounts get-iam-policy translation-service@${PROJECT_ID}.iam.gserviceaccount.com
```

#### 4. WebSocket Connection Issues
- Verify Cloud Run service is publicly accessible
- Check firewall rules and VPC configuration
- Ensure proper CORS headers in the application
- Validate SSL certificate for HTTPS/WSS connections

### Debugging Commands

```bash
# View Cloud Run service logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
    --limit=50 --format="table(timestamp,textPayload)"

# Check Firestore operations
gcloud firestore operations list

# Monitor Pub/Sub message flow
gcloud pubsub subscriptions pull translation-processor --limit=10

# Verify service account key rotation
gcloud iam service-accounts keys list --iam-account=translation-service@${PROJECT_ID}.iam.gserviceaccount.com
```

## Customization

### Adding New Languages

To support additional languages, update the application configuration:

1. **Modify supported language codes** in the Cloud Run application
2. **Update Firestore security rules** for new language collections
3. **Configure Speech-to-Text models** for specific language variants
4. **Test translation quality** for new language pairs

### Scaling for Production

For production deployments:

1. **Increase Cloud Run limits**: Scale `max_instances`, `memory_limit`, and `cpu_limit`
2. **Implement monitoring**: Add Cloud Monitoring dashboards and alerts
3. **Configure backup strategies**: Set up Firestore backups and Cloud Storage replication
4. **Add security enhancements**: Implement API authentication and rate limiting
5. **Optimize costs**: Use preemptible instances and storage lifecycle policies

### Integration with Existing Systems

The solution can be integrated with:

- **Contact Center AI**: For customer service applications
- **Google Workspace**: For meeting translation capabilities
- **Mobile Applications**: Using the WebSocket API
- **IoT Devices**: For edge translation scenarios
- **Analytics Platforms**: Via Pub/Sub event streaming

## Support

For issues with this infrastructure code:

1. **Check the troubleshooting section** above for common solutions
2. **Review the original recipe documentation** for implementation details
3. **Consult Google Cloud documentation**:
   - [Cloud Speech-to-Text](https://cloud.google.com/speech-to-text/docs)
   - [Cloud Translation](https://cloud.google.com/translate/docs)
   - [Cloud Run](https://cloud.google.com/run/docs)
   - [Firestore](https://cloud.google.com/firestore/docs)
4. **Access community support**:
   - Stack Overflow with `google-cloud-platform` tag
   - Google Cloud Community Slack
   - GitHub issues for provider-specific problems

## Contributing

To improve this infrastructure code:

1. **Test thoroughly** in a development environment
2. **Follow Google Cloud best practices** for security and performance
3. **Update documentation** to reflect any changes
4. **Validate compatibility** with the latest provider versions
5. **Consider backward compatibility** when making changes

## License

This infrastructure code is provided as-is for educational and development purposes. Ensure compliance with your organization's policies and Google Cloud terms of service when deploying to production environments.