# Infrastructure as Code for Deploying GPU-Accelerated Multi-Agent AI Systems with Cloud Run and Vertex AI Agent Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Deploying GPU-Accelerated Multi-Agent AI Systems with Cloud Run and Vertex AI Agent Engine".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code with official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for manual deployment

## Architecture Overview

This solution deploys a sophisticated multi-agent AI system that includes:

- **GPU-Accelerated Agents**: Vision, Language, and Reasoning agents using Cloud Run with NVIDIA L4 GPUs
- **Master Orchestrator**: Vertex AI Agent Engine for intelligent task coordination
- **Tool Agent**: Utility agent for external integrations (CPU-only)
- **Shared Services**: Cloud Memorystore Redis for state management and Pub/Sub for messaging
- **Monitoring**: Cloud Monitoring, Logging, and Trace for comprehensive observability

## Prerequisites

### General Requirements

- Google Cloud Project with billing enabled
- Google Cloud CLI (`gcloud`) installed and configured
- Appropriate IAM permissions for:
  - Cloud Run Admin
  - Vertex AI User
  - Redis Admin
  - Pub/Sub Admin
  - Artifact Registry Admin
  - Cloud Build Editor
  - Monitoring Admin
  - Service Account Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Cloud Resource Manager API enabled

#### Terraform
- Terraform >= 1.5.0 installed
- Google Cloud provider >= 5.0.0

#### Bash Scripts
- Docker installed (for container builds)
- `curl` and `jq` utilities for testing

### Cost Considerations

Estimated daily costs (varies by usage):
- GPU-enabled Cloud Run instances: $50-150/day
- Cloud Memorystore Redis: $5-15/day
- Pub/Sub and other services: $5-10/day
- **Total estimated cost: $60-175/day**

> **Warning**: GPU instances incur significant costs. Monitor usage and clean up resources when not needed.

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for deploying and managing infrastructure at scale.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/multi-agent-ai \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo=REPO_URL \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=PROJECT_ID,region=REGION

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/multi-agent-ai
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Test the deployment (optional)
./scripts/test_deployment.sh
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
inputs:
  - name: project_id
    description: "GCP Project ID"
    type: string
    required: true
  
  - name: region
    description: "GCP Region for deployment"
    type: string
    default: "us-central1"
  
  - name: redis_memory_size_gb
    description: "Redis instance memory size"
    type: number
    default: 1
  
  - name: gpu_type
    description: "GPU type for Cloud Run services"
    type: string
    default: "nvidia-l4"
```

### Terraform Variables

Customize deployment by modifying `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Redis configuration
redis_memory_size_gb = 1
redis_tier          = "BASIC"

# Cloud Run configuration
gpu_type           = "nvidia-l4"
max_gpu_instances  = 10
min_gpu_instances  = 0

# Container configuration
container_cpu    = "4"
container_memory = "16Gi"

# Naming
resource_suffix = ""  # Optional suffix for resource names
```

### Bash Script Environment Variables

Set these variables before running deployment scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export REDIS_MEMORY_SIZE="1"
export GPU_TYPE="nvidia-l4"
export MAX_INSTANCES="10"
export CONTAINER_MEMORY="16Gi"
export CONTAINER_CPU="4"
```

## Deployment Validation

### Verify Infrastructure Deployment

```bash
# Check Cloud Run services
gcloud run services list --platform=managed --region=$REGION

# Verify Redis instance
gcloud redis instances list --region=$REGION

# Check Pub/Sub topics
gcloud pubsub topics list

# Verify Artifact Registry
gcloud artifacts repositories list --location=$REGION
```

### Test Agent Endpoints

```bash
# Get service URLs
VISION_URL=$(gcloud run services describe vision-agent-* --platform=managed --region=$REGION --format="value(status.url)")
LANGUAGE_URL=$(gcloud run services describe language-agent-* --platform=managed --region=$REGION --format="value(status.url)")
REASONING_URL=$(gcloud run services describe reasoning-agent-* --platform=managed --region=$REGION --format="value(status.url)")

# Test health endpoints
curl "${VISION_URL}/health"
curl "${LANGUAGE_URL}/health" 
curl "${REASONING_URL}/health"
```

### Monitor GPU Utilization

```bash
# View recent logs with GPU usage
gcloud logging read 'resource.type="cloud_run_revision" jsonPayload.gpu_used=true' \
    --limit=20 \
    --format="table(timestamp,jsonPayload.processing_time,jsonPayload.gpu_used)"
```

## Performance Testing

### Load Testing Script

```bash
# Test concurrent requests to vision agent
for i in {1..10}; do
  curl -X POST "${VISION_URL}/analyze" \
       -H "Content-Type: application/json" \
       -d '{"test_image": "data'$i'"}' &
done
wait

echo "Load test completed - check Cloud Monitoring for performance metrics"
```

### Monitoring Dashboard

Access the custom monitoring dashboard:

```bash
# Get monitoring dashboard URL
echo "https://console.cloud.google.com/monitoring/dashboards/custom/multi-agent-ai-system?project=${PROJECT_ID}"
```

## Troubleshooting

### Common Issues

1. **GPU Quota Exceeded**
   ```bash
   # Check current GPU quotas
   gcloud compute project-info describe --format="yaml(quotas)"
   
   # Request quota increase if needed
   # Visit: https://console.cloud.google.com/iam-admin/quotas
   ```

2. **Container Build Failures**
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=10
   
   # View specific build logs
   gcloud builds log BUILD_ID
   ```

3. **Service Deployment Issues**
   ```bash
   # Check Cloud Run service logs
   gcloud run services logs read SERVICE_NAME --region=$REGION --limit=50
   ```

4. **Redis Connection Problems**
   ```bash
   # Verify Redis instance status
   gcloud redis instances describe INSTANCE_NAME --region=$REGION
   
   # Check firewall rules for Redis access
   gcloud compute firewall-rules list --filter="name~redis"
   ```

### Performance Optimization

1. **GPU Cold Start Reduction**
   - Set minimum instances > 0 for frequently used agents
   - Use Cloud Scheduler to send periodic health checks

2. **Cost Optimization**
   - Monitor GPU utilization and adjust instance limits
   - Use CPU-only instances for non-ML tasks
   - Implement request routing to minimize GPU usage

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/multi-agent-ai

# Verify cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification
gcloud run services list --platform=managed --region=$REGION
gcloud redis instances list --region=$REGION
```

### Manual Cleanup (if needed)

```bash
# Force delete remaining resources
gcloud run services delete --all --region=$REGION --quiet
gcloud redis instances delete --all --region=$REGION --quiet
gcloud pubsub topics delete $(gcloud pubsub topics list --format="value(name)") --quiet
gcloud artifacts repositories delete agent-images --location=$REGION --quiet

# Clean up IAM bindings (review before running)
# gcloud projects remove-iam-policy-binding $PROJECT_ID --member="serviceAccount:SERVICE_ACCOUNT" --role="roles/run.admin"
```

## Security Considerations

### IAM Best Practices

- Use least privilege principle for service accounts
- Enable audit logging for all services
- Regularly review and rotate service account keys
- Use Workload Identity for secure access patterns

### Network Security

- Configure VPC Service Controls for additional isolation
- Use private Google Access for secure communication
- Implement proper firewall rules for Redis access
- Enable Private Service Connect where applicable

### Data Protection

- Enable encryption at rest for all services
- Use Secret Manager for sensitive configuration
- Implement proper data classification and handling
- Enable Cloud DLP for sensitive data scanning

## Advanced Features

### Multi-Region Deployment

To deploy across multiple regions for high availability:

```bash
# Deploy to additional regions
export BACKUP_REGION="us-east1"
terraform apply -var="project_id=$PROJECT_ID" -var="region=$BACKUP_REGION"
```

### CI/CD Integration

Example Cloud Build configuration for automated deployment:

```yaml
# cloudbuild.yaml
steps:
  - name: 'hashicorp/terraform:latest'
    entrypoint: 'sh'
    args:
      - '-c'
      - |
        cd terraform/
        terraform init
        terraform plan -var="project_id=$PROJECT_ID"
        terraform apply -auto-approve -var="project_id=$PROJECT_ID"
```

### Custom Agent Development

To add new specialized agents:

1. Create new container in the `agents/` directory
2. Update Terraform/Infrastructure Manager configuration
3. Add monitoring and alerting rules
4. Update the master orchestrator logic

## Cost Management

### Daily Cost Monitoring

```bash
# Set up billing alerts
gcloud billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Multi-Agent AI Budget" \
    --budget-amount=100USD

# Monitor current spending
gcloud billing projects list
```

### Resource Optimization

- Use sustained use discounts for long-running workloads
- Implement auto-scaling based on queue depth
- Schedule non-critical agents to run during off-peak hours
- Regular review of resource utilization metrics

## Support and Documentation

### Additional Resources

- [Cloud Run GPU Documentation](https://cloud.google.com/run/docs/configuring/services/gpu)
- [Vertex AI Agent Engine Guide](https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/overview)
- [Cloud Memorystore Redis Documentation](https://cloud.google.com/memorystore/docs/redis)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Refer to the original recipe documentation
4. Contact Google Cloud Support for platform issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any new features
3. Follow Google Cloud best practices
4. Include appropriate monitoring and alerting

---

**Note**: This infrastructure deploys production-ready resources that will incur charges. Always monitor costs and clean up resources when not needed.