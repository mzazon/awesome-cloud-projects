# Infrastructure as Code for Scalable Audio Content Distribution with Chirp 3 and Memorystore Valkey

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Scalable Audio Content Distribution with Chirp 3 and Memorystore Valkey".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Solution Overview

This infrastructure deploys a scalable audio content distribution platform using Google Cloud's Chirp 3 instant custom voice technology, Memorystore for Valkey caching, and Cloud CDN for global distribution. The solution provides:

- Real-time audio generation with Chirp 3 custom voices
- High-performance caching with sub-millisecond response times
- Global content delivery through Cloud CDN
- Serverless auto-scaling with Cloud Functions and Cloud Run
- Enterprise-grade security and monitoring

## Prerequisites

- Google Cloud Project with billing enabled
- gcloud CLI installed and configured (version 450.0.0 or later)
- Terraform installed (version 1.5.0 or later) - for Terraform deployment
- Appropriate IAM permissions for resource creation:
  - Compute Admin
  - Storage Admin
  - Cloud Functions Admin
  - Service Account Admin
  - Memorystore Admin
  - CDN Admin
- Access to Chirp 3 instant custom voice (allowlist required)
- Estimated cost: $50-200/month depending on usage volume

> **Important**: Chirp 3 instant custom voice requires allowlist approval. Contact Google Cloud sales to be added to the allowlist before deployment.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that provides native integration with Google Cloud services.

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable Infrastructure Manager API
gcloud services enable inframanager.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/audio-distribution \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-terraform-bucket/infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/audio-distribution
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem support.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View important outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple deployment option that follows the exact recipe implementation steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will prompt for confirmation and display progress
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `ZONE` | Compute zone | `us-central1-a` | No |
| `BUCKET_NAME` | Storage bucket name | Auto-generated | No |
| `VALKEY_INSTANCE` | Memorystore instance name | Auto-generated | No |
| `FUNCTION_NAME` | Cloud Function name | Auto-generated | No |

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize your deployment:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
bucket_name           = "custom-audio-bucket"
valkey_instance_name  = "custom-audio-cache"
function_name         = "custom-audio-processor"
valkey_memory_size_gb = 2
valkey_node_count     = 3
```

### Infrastructure Manager Variables

Customize deployment by editing `infrastructure-manager/main.yaml`:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  # Additional variables...
```

## Architecture Components

The infrastructure creates the following resources:

### Storage & CDN
- **Cloud Storage Bucket**: Stores generated audio files with lifecycle policies
- **Cloud CDN**: Global content delivery with optimized caching for audio content
- **Load Balancer**: HTTP(S) load balancing with global IP

### Compute & Functions
- **Cloud Functions**: Serverless audio processing with Text-to-Speech integration
- **Cloud Run**: Scalable audio management service API
- **Container Registry**: Stores containerized applications

### Caching & Database
- **Memorystore for Valkey**: High-performance in-memory caching cluster
- **VPC Network**: Isolated network for secure communication

### Security & IAM
- **Service Accounts**: Least-privilege access for each component
- **IAM Policies**: Fine-grained permissions management
- **VPC Security**: Network-level isolation and access controls

## Validation & Testing

After deployment, validate the infrastructure:

### 1. Check Service Endpoints

```bash
# Get Cloud Run service URL
export SERVICE_URL=$(gcloud run services describe audio-management-service \
    --platform managed --region ${REGION} --format="value(status.url)")

# Test health endpoint
curl ${SERVICE_URL}/health
```

### 2. Test Audio Generation

```bash
# Test single audio generation
curl -X POST "${SERVICE_URL}/api/audio/generate" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Testing scalable audio distribution platform.",
        "voiceConfig": {"languageCode": "en-US", "voiceName": "en-US-Casual"}
    }'
```

### 3. Verify Caching Performance

```bash
# Test cache hit (repeat the same request)
curl -X POST "${SERVICE_URL}/api/audio/generate" \
    -H "Content-Type: application/json" \
    -d '{
        "text": "Testing scalable audio distribution platform.",
        "voiceConfig": {"languageCode": "en-US", "voiceName": "en-US-Casual"}
    }' | jq '.cached, .processingTime'
```

### 4. Check Cache Statistics

```bash
# View cache performance metrics
curl "${SERVICE_URL}/api/cache/stats" | jq .
```

## Monitoring & Observability

### Cloud Monitoring

The infrastructure includes monitoring for:

- **Cloud Functions**: Execution metrics, errors, and latency
- **Cloud Run**: Request volume, response times, and resource utilization
- **Memorystore**: Cache hit ratios, memory usage, and connection metrics
- **Cloud CDN**: Cache performance, origin load, and global distribution

### Logging

Access logs through Cloud Logging:

```bash
# View Cloud Function logs
gcloud functions logs read ${FUNCTION_NAME} --region ${REGION}

# View Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision" --limit 50
```

### Custom Metrics

Monitor application-specific metrics:

- Audio generation volume and processing times
- Cache hit/miss ratios
- CDN performance by region
- User experience metrics

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/audio-distribution

# Confirm deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Confirm when prompted
# Type 'yes' to proceed with destruction
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
# Follow the prompts to complete cleanup
```

### Manual Cleanup Verification

After automated cleanup, verify all resources are removed:

```bash
# Check for remaining Cloud Run services
gcloud run services list --region=${REGION}

# Check for remaining Cloud Functions
gcloud functions list --region=${REGION}

# Check for remaining Storage buckets
gsutil ls -p ${PROJECT_ID}

# Check for remaining Memorystore instances
gcloud memcache instances list --region=${REGION}
```

## Troubleshooting

### Common Issues

1. **Chirp 3 Access Denied**
   - Ensure your project is allowlisted for Chirp 3 instant custom voice
   - Contact Google Cloud sales for access approval

2. **Quota Exceeded Errors**
   - Check quotas in Google Cloud Console
   - Request quota increases if needed
   - Consider alternative regions with available capacity

3. **Network Connectivity Issues**
   - Verify VPC network and subnet configuration
   - Check firewall rules for Memorystore access
   - Ensure proper service account permissions

4. **Function Deployment Failures**
   - Check Cloud Build service is enabled
   - Verify service account has necessary permissions
   - Review function logs for specific error messages

### Debug Commands

```bash
# Check API enablement status
gcloud services list --enabled | grep -E "(texttospeech|memcache|storage|cloudfunctions)"

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" \
    --format="table(bindings.role,bindings.members)"

# Test Text-to-Speech API access
gcloud auth print-access-token | xargs -I {} curl -H "Authorization: Bearer {}" \
    "https://texttospeech.googleapis.com/v1/voices"
```

## Performance Optimization

### Scaling Recommendations

- **Cloud Functions**: Configure max instances based on expected concurrent requests
- **Cloud Run**: Set min instances > 0 for reduced cold start latency
- **Memorystore**: Scale cluster nodes based on cache hit ratio targets
- **Cloud CDN**: Configure cache policies optimized for audio content patterns

### Cost Optimization

- **Storage Lifecycle**: Automatically transition old audio files to cheaper storage classes
- **Cache TTL**: Optimize cache expiration times based on content update frequency
- **Regional Deployment**: Deploy closer to primary user base to reduce egress costs
- **Spot Instances**: Use preemptible instances for batch processing workloads

## Security Best Practices

The infrastructure implements security best practices:

- **Least Privilege IAM**: Each service account has minimal required permissions
- **Network Isolation**: VPC network isolates Memorystore cluster
- **Encryption**: Data encrypted at rest and in transit
- **API Security**: Function authentication and rate limiting
- **Audit Logging**: Comprehensive audit trail for all operations

## Support & Documentation

- **Recipe Documentation**: Refer to the original recipe markdown for detailed implementation guidance
- **Google Cloud Documentation**: [Cloud Text-to-Speech](https://cloud.google.com/text-to-speech/docs), [Memorystore for Valkey](https://cloud.google.com/memorystore/docs/valkey), [Cloud CDN](https://cloud.google.com/cdn/docs)
- **Terraform Provider**: [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- **Community Support**: Google Cloud Community forums and Stack Overflow

## Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud security best practices
3. Update documentation for any configuration changes
4. Validate all IaC implementations work correctly
5. Submit issues or improvements via the repository

## License

This infrastructure code is provided as part of the cloud recipes repository. Refer to the repository license for usage terms.