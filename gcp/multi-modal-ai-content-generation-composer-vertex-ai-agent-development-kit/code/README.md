# Infrastructure as Code for Multi-Modal AI Content Generation with Cloud Composer and Vertex AI Agent Development Kit

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Modal AI Content Generation with Cloud Composer and Vertex AI Agent Development Kit".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) v451.0.0+ installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Composer (Composer Admin)
  - Vertex AI (Vertex AI Admin)
  - Cloud Storage (Storage Admin)
  - Cloud Run (Cloud Run Admin)
  - Cloud Build (Cloud Build Editor)
  - IAM (IAM Admin for service account creation)
- Python 3.9+ for local development and testing
- Terraform v1.6+ (if using Terraform implementation)
- Understanding of Apache Airflow and multi-agent AI systems

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/content-pipeline \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/content-pipeline-iac" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/content-pipeline
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Cloud Storage bucket
# 3. Deploy Cloud Composer environment
# 4. Install Agent Development Kit dependencies
# 5. Deploy content generation DAG
# 6. Build and deploy Cloud Run API service
# 7. Configure ADK agents for production
```

## Architecture Overview

This infrastructure deploys:

- **Cloud Composer Environment**: Apache Airflow orchestration with 3 nodes (n1-standard-2)
- **Vertex AI Agent Development Kit**: Multi-agent system for content generation
- **Cloud Storage**: Content repository with versioning enabled
- **Cloud Run Service**: Serverless API for content generation requests
- **IAM Service Accounts**: Least-privilege access for all components
- **Monitoring**: Observability for agent performance and pipeline health

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
    required: true
  
  region:
    description: "Deployment region"
    type: string
    default: "us-central1"
  
  composer_node_count:
    description: "Number of Composer nodes"
    type: integer
    default: 3
  
  composer_machine_type:
    description: "Machine type for Composer nodes"
    type: string
    default: "n1-standard-2"
  
  storage_class:
    description: "Storage class for content bucket"
    type: string
    default: "STANDARD"
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or use `-var` flags:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"

# Optional customizations
composer_node_count = 3
composer_machine_type = "n1-standard-2"
cloud_run_cpu = 2
cloud_run_memory = "2Gi"
cloud_run_max_instances = 10

# Agent configuration
enable_agent_monitoring = true
agent_min_replicas = 1
agent_max_replicas = 5
```

### Script Configuration

Edit environment variables in `scripts/deploy.sh`:

```bash
# Core configuration
PROJECT_ID="your-project-id"
REGION="us-central1"
ZONE="us-central1-a"

# Resource naming
COMPOSER_ENV_NAME="multi-modal-content-pipeline"
CLOUD_RUN_SERVICE="content-api"

# Composer configuration
COMPOSER_NODE_COUNT=3
COMPOSER_MACHINE_TYPE="n1-standard-2"
COMPOSER_DISK_SIZE="50GB"

# ADK agent configuration
ENABLE_AGENT_MONITORING=true
AGENT_MIN_REPLICAS=1
AGENT_MAX_REPLICAS=5
```

## Testing the Deployment

### 1. Verify Cloud Composer Environment

```bash
# Check Composer environment status
gcloud composer environments describe ${COMPOSER_ENV_NAME} \
    --location ${REGION} \
    --format="table(state,config.nodeCount,config.softwareConfig.imageVersion)"

# Access Airflow UI
AIRFLOW_URI=$(gcloud composer environments describe \
    ${COMPOSER_ENV_NAME} --location ${REGION} \
    --format="value(config.airflowUri)")

echo "Airflow UI: ${AIRFLOW_URI}"
```

### 2. Test Content Generation API

```bash
# Get Cloud Run service URL
CONTENT_API_URL=$(gcloud run services describe content-api-${RANDOM_SUFFIX} \
    --region ${REGION} \
    --format="value(status.url)")

# Test content generation endpoint
curl -X POST ${CONTENT_API_URL}/generate-content \
    -H "Content-Type: application/json" \
    -d '{
      "target_audience": "tech professionals",
      "content_type": "blog_post_with_visuals",
      "brand_guidelines": {
        "tone": "professional",
        "style": "informative",
        "color_palette": "blue_and_white"
      },
      "topic": "AI automation in business processes"
    }'

# Check API health
curl ${CONTENT_API_URL}/health
```

### 3. Monitor Agent Performance

```bash
# List deployed agents
gcloud ai agents list --region ${REGION} \
    --format="table(name,state,createTime)"

# Check content storage
gsutil ls -r gs://${STORAGE_BUCKET}/content/
```

## Cost Estimation

Estimated monthly costs for this infrastructure:

- **Cloud Composer**: $150-300 (3 n1-standard-2 nodes)
- **Vertex AI**: $50-200 (depending on usage)
- **Cloud Storage**: $5-20 (depending on content volume)
- **Cloud Run**: $0-50 (pay-per-request)
- **Cloud Build**: $0-10 (minimal usage)

**Total estimated cost**: $205-580/month

> **Note**: Costs vary significantly based on usage patterns. Monitor billing and set up budget alerts.

## Monitoring and Observability

### Built-in Monitoring

The infrastructure includes:

- **Cloud Composer Monitoring**: Airflow task success/failure rates
- **Vertex AI Agent Metrics**: Response times, success rates, resource usage
- **Cloud Run Metrics**: Request latency, error rates, instance utilization
- **Storage Metrics**: Bucket usage, access patterns

### Access Monitoring Dashboards

```bash
# Cloud Composer monitoring
echo "Composer monitoring: https://console.cloud.google.com/composer/environments/detail/${REGION}/${COMPOSER_ENV_NAME}"

# Vertex AI monitoring
echo "Vertex AI monitoring: https://console.cloud.google.com/vertex-ai/agents"

# Cloud Run monitoring
echo "Cloud Run monitoring: https://console.cloud.google.com/run/detail/${REGION}/content-api-${RANDOM_SUFFIX}"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/content-pipeline \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Clean up Terraform state
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Run service
# 2. Remove container images
# 3. Delete Cloud Composer environment
# 4. Remove storage bucket and contents
# 5. Undeploy ADK agents
# 6. Clean up IAM service accounts
```

### Manual Cleanup Verification

```bash
# Verify Cloud Composer deletion
gcloud composer environments list --locations=${REGION}

# Verify Cloud Run services deleted
gcloud run services list --region=${REGION}

# Verify storage buckets deleted
gsutil ls -p ${PROJECT_ID}

# Verify Vertex AI agents removed
gcloud ai agents list --region=${REGION}
```

## Troubleshooting

### Common Issues

1. **Composer Environment Creation Fails**:
   ```bash
   # Check API enablement
   gcloud services list --enabled --filter="name:composer.googleapis.com"
   
   # Verify IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **ADK Agent Deployment Fails**:
   ```bash
   # Check Vertex AI API status
   gcloud services list --enabled --filter="name:aiplatform.googleapis.com"
   
   # Review agent logs
   gcloud logging read "resource.type=vertex_ai_agent" --limit=50
   ```

3. **Cloud Run Deployment Issues**:
   ```bash
   # Check build logs
   gcloud builds list --limit=5
   
   # Review Cloud Run logs
   gcloud run services logs read content-api-${RANDOM_SUFFIX} --region=${REGION}
   ```

### Support Resources

- [Cloud Composer Documentation](https://cloud.google.com/composer/docs)
- [Vertex AI Agent Development Kit](https://cloud.google.com/vertex-ai/docs/adk)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Security Considerations

### IAM Best Practices

- All service accounts follow least-privilege principle
- Cross-service access uses service account impersonation
- No service account keys stored in code

### Network Security

- Cloud Composer uses private IP ranges
- Cloud Run services use IAM authentication
- Storage buckets have uniform bucket-level access

### Data Protection

- Content stored with encryption at rest
- Agent sessions use ephemeral storage
- Sensitive configuration uses Secret Manager

## Customization

### Adding New Agent Types

1. Update the agent configuration in `agent_config.yaml`
2. Modify the Airflow DAG to include new agent tasks
3. Redeploy using your chosen IaC method

### Scaling Configuration

```bash
# Update Composer node count
gcloud composer environments update ${COMPOSER_ENV_NAME} \
    --location ${REGION} \
    --update-pypi-packages-from-file requirements.txt \
    --node-count 5

# Scale Cloud Run instances
gcloud run services update content-api-${RANDOM_SUFFIX} \
    --region ${REGION} \
    --max-instances 20
```

### Integration with External Systems

- Modify the Cloud Run API to integrate with external content management systems
- Add webhook notifications for content generation completion
- Integrate with Google Analytics for content performance tracking

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud service status pages
3. Consult provider documentation links above
4. Review logs using Cloud Logging

For recipe-specific questions, refer to the main recipe file: `multi-modal-ai-content-generation-composer-vertex-ai-agent-development-kit.md`