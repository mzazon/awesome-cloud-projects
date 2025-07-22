# Infrastructure as Code for Serverless GPU Computing Pipelines with Cloud Run GPU and Cloud Workflows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Serverless GPU Computing Pipelines with Cloud Run GPU and Cloud Workflows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud Project with billing enabled
- Appropriate IAM permissions for resource creation:
  - Cloud Run Admin
  - Cloud Workflows Admin
  - Cloud Storage Admin
  - Eventarc Admin
  - Cloud Build Editor
  - Service Account Admin
  - Project IAM Admin
- Docker installed locally (for manual container building)
- Estimated cost: $0.50-$2.00 per hour during active pipeline execution

### Required APIs

The following APIs must be enabled in your Google Cloud project:

- Cloud Run API
- Cloud Workflows API
- Cloud Storage API
- Vertex AI API
- Cloud Build API
- Eventarc API
- Container Registry API

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply deployment-name \
    --location=${REGION} \
    --service-account=your-service-account@your-project.iam.gserviceaccount.com \
    --gcs-source=gs://your-bucket/path-to-config \
    --input-values=project_id=${PROJECT_ID},region=${REGION}
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This infrastructure deploys:

1. **Cloud Run Services**:
   - GPU-accelerated inference service with NVIDIA L4 GPUs
   - CPU-optimized preprocessing service
   - CPU-optimized post-processing service

2. **Cloud Workflows**:
   - Orchestration pipeline for ML workload coordination
   - Error handling and retry logic
   - Comprehensive logging and monitoring

3. **Cloud Storage**:
   - Input data bucket
   - Model storage bucket
   - Output results bucket

4. **Eventarc Triggers**:
   - Automatic pipeline execution on file uploads
   - Event-driven architecture for real-time processing

5. **IAM Configuration**:
   - Service accounts with least privilege permissions
   - Proper security boundaries between services

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `service_prefix` | Prefix for resource names | `ml-pipeline` | No |
| `gpu_memory` | Memory allocation for GPU service | `16Gi` | No |
| `gpu_cpu` | CPU allocation for GPU service | `4` | No |
| `max_instances` | Maximum instances per service | `10` | No |

### Terraform Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Deployment region | `us-central1` | No |
| `zone` | Deployment zone | `us-central1-a` | No |
| `service_prefix` | Prefix for resource names | `ml-pipeline` | No |
| `gpu_type` | GPU type for inference service | `nvidia-l4` | No |
| `gpu_memory` | Memory allocation for GPU service | `16Gi` | No |
| `gpu_cpu` | CPU allocation for GPU service | `4` | No |
| `preprocess_memory` | Memory for preprocessing service | `2Gi` | No |
| `postprocess_memory` | Memory for post-processing service | `1Gi` | No |
| `max_instances` | Maximum instances per service | `10` | No |
| `timeout_seconds` | Service timeout in seconds | `300` | No |

### Bash Script Configuration

Set these environment variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export SERVICE_PREFIX="ml-pipeline"  # Optional, will generate random if not set
```

## Deployment Process

### Phase 1: Container Images
1. Build GPU inference service container with CUDA support
2. Build preprocessing service container
3. Build post-processing service container
4. Push all images to Google Container Registry

### Phase 2: Cloud Run Services
1. Deploy GPU inference service with L4 GPU configuration
2. Deploy preprocessing service with CPU optimization
3. Deploy post-processing service with CPU optimization
4. Configure service-to-service authentication

### Phase 3: Storage and Orchestration
1. Create Cloud Storage buckets for input, models, and output
2. Deploy Cloud Workflows pipeline with comprehensive error handling
3. Configure Eventarc triggers for automatic pipeline execution
4. Set up IAM roles and service accounts

### Phase 4: Monitoring and Validation
1. Configure Cloud Monitoring dashboards
2. Set up logging and alerting
3. Validate end-to-end pipeline functionality
4. Test automatic scaling and GPU utilization

## Testing the Deployment

### Manual Testing

1. **Upload a test file**:
   ```bash
   echo "This is a positive sentiment test message." > test-input.txt
   gsutil cp test-input.txt gs://your-input-bucket/
   ```

2. **Monitor workflow execution**:
   ```bash
   gcloud workflows executions list \
       --workflow=your-workflow-name \
       --location=${REGION}
   ```

3. **Check results**:
   ```bash
   gsutil ls gs://your-output-bucket/
   ```

### Automated Testing

The deployment includes health check endpoints:

- Preprocessing service: `https://your-preprocess-url/health`
- GPU inference service: `https://your-gpu-service-url/health`
- Post-processing service: `https://your-postprocess-url/health`

### Performance Testing

Monitor GPU utilization and scaling:

```bash
# Check service metrics
gcloud run services describe your-gpu-service \
    --region=${REGION} \
    --format="table(spec.template.spec.template.spec.containers[0].resources)"

# View workflow execution details
gcloud workflows executions describe EXECUTION_ID \
    --workflow=your-workflow-name \
    --location=${REGION}
```

## Monitoring and Observability

### Cloud Monitoring Integration

The deployment automatically configures:

- GPU utilization metrics
- Request latency tracking
- Error rate monitoring
- Cost tracking and optimization alerts

### Logging Configuration

- Structured logging for all services
- Workflow execution logs
- Error tracking and alerting
- Performance metrics collection

### Custom Dashboards

Access pre-configured dashboards for:

- Pipeline execution status
- GPU resource utilization
- Cost optimization metrics
- Service performance analytics

## Cost Optimization

### GPU Resource Management

- **Cold Start Optimization**: Services scale to zero when idle
- **GPU Billing**: Pay-per-second GPU usage with no minimum charges
- **Automatic Scaling**: Dynamic scaling based on demand
- **Resource Limits**: Configured maximum instances to control costs

### Storage Optimization

- **Lifecycle Policies**: Automatic cleanup of temporary files
- **Storage Classes**: Optimized storage class selection
- **Data Retention**: Configurable retention policies

### Monitoring Costs

```bash
# View current project costs
gcloud billing budgets list

# Monitor specific service costs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=your-service"
```

## Security Considerations

### IAM Security

- **Least Privilege**: Minimal required permissions for each service
- **Service Accounts**: Dedicated service accounts for each component
- **Cross-Service Authentication**: Proper service-to-service authentication
- **External Access**: Controlled external access with appropriate security

### Network Security

- **VPC Configuration**: Proper network isolation
- **HTTPS Only**: All services configured for HTTPS
- **Internal Communication**: Secure internal service communication

### Data Security

- **Encryption**: Data encrypted at rest and in transit
- **Access Controls**: Proper bucket and object access controls
- **Audit Logging**: Comprehensive audit trail for all operations

## Troubleshooting

### Common Issues

1. **GPU Quota Exceeded**:
   ```bash
   gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"
   ```

2. **Service Authentication Errors**:
   ```bash
   gcloud iam service-accounts get-iam-policy SERVICE_ACCOUNT_EMAIL
   ```

3. **Container Build Failures**:
   ```bash
   gcloud builds log BUILD_ID
   ```

4. **Workflow Execution Errors**:
   ```bash
   gcloud workflows executions describe EXECUTION_ID \
       --workflow=WORKFLOW_NAME \
       --location=${REGION}
   ```

### Debug Commands

```bash
# Check service logs
gcloud logs read "resource.type=cloud_run_revision"

# Monitor workflow executions
gcloud workflows executions list --workflow=WORKFLOW_NAME --location=${REGION}

# Check Eventarc triggers
gcloud eventarc triggers list --location=${REGION}

# Validate service endpoints
curl -X GET "https://your-service-url/health"
```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete deployment-name \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run the destroy script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify Cloud Run services are deleted
gcloud run services list --region=${REGION}

# Verify workflows are deleted
gcloud workflows list --location=${REGION}

# Verify storage buckets are deleted
gsutil ls -p ${PROJECT_ID}

# Verify container images are deleted
gcloud container images list
```

## Customization

### Extending the Pipeline

1. **Custom Models**: Replace the default model with your own trained models
2. **Additional Services**: Add new processing steps to the workflow
3. **Different GPU Types**: Modify GPU configuration for different workloads
4. **Multi-Region**: Deploy across multiple regions for global availability

### Configuration Examples

#### High-Performance Configuration

```hcl
# terraform/terraform.tfvars
gpu_type = "nvidia-l4"
gpu_memory = "32Gi"
gpu_cpu = "8"
max_instances = 50
timeout_seconds = 600
```

#### Cost-Optimized Configuration

```hcl
# terraform/terraform.tfvars
gpu_memory = "8Gi"
gpu_cpu = "2"
max_instances = 5
timeout_seconds = 120
```

#### Development Configuration

```hcl
# terraform/terraform.tfvars
service_prefix = "dev-ml-pipeline"
max_instances = 2
timeout_seconds = 60
```

## Support and Resources

### Documentation Links

- [Cloud Run GPU Documentation](https://cloud.google.com/run/docs/configuring/services/gpu)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Eventarc Documentation](https://cloud.google.com/eventarc/docs)
- [Cloud Storage Documentation](https://cloud.google.com/storage/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [GitHub - Google Cloud Samples](https://github.com/GoogleCloudPlatform)

### Support Channels

- Google Cloud Support (for enterprise customers)
- Community forums and discussions
- GitHub Issues for code-related problems

## License

This infrastructure code is provided under the same license as the parent recipe repository.

## Contributing

When contributing improvements to this infrastructure code:

1. Test all changes thoroughly
2. Update documentation accordingly
3. Follow Google Cloud best practices
4. Ensure compatibility across all IaC implementations
5. Include cost impact analysis for changes