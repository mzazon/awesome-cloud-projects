# Infrastructure as Code for Developing Browser-Based AI Applications with Cloud Shell Editor and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Developing Browser-Based AI Applications with Cloud Shell Editor and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI installed and configured (`gcloud` version 400.0.0 or later)
- Active Google Cloud project with billing enabled
- Appropriate permissions for resource creation:
  - Cloud Build Editor
  - Cloud Run Admin
  - Vertex AI Administrator
  - Artifact Registry Administrator
  - Secret Manager Admin
  - Service Account Admin
- Web browser with internet access for Cloud Shell Editor

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Cloud Resource Manager API enabled
- Deployment manager service account configured

#### Terraform
- Terraform CLI installed (version 1.0 or later)
- Google Cloud provider plugin (automatically downloaded during init)

## Architecture Overview

This infrastructure deploys:
- Cloud Shell Editor development environment (managed service)
- Vertex AI models and endpoints for AI processing
- Cloud Build triggers for automated CI/CD
- Cloud Run service for serverless hosting
- Artifact Registry for container storage
- IAM roles and service accounts for secure access

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

1. **Initialize deployment**:
   ```bash
   cd infrastructure-manager/
   
   # Set required variables
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export SERVICE_NAME="ai-chat-assistant"
   
   # Create deployment
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-app-deployment \
       --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
       --local-source="." \
       --inputs-file="variables.yaml"
   ```

2. **Monitor deployment progress**:
   ```bash
   gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-app-deployment
   ```

### Using Terraform

1. **Initialize and plan deployment**:
   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Create terraform.tfvars file
   cat > terraform.tfvars << EOF
   project_id = "your-project-id"
   region = "us-central1"
   service_name = "ai-chat-assistant"
   enable_apis = true
   EOF
   
   # Plan deployment
   terraform plan
   ```

2. **Apply infrastructure**:
   ```bash
   terraform apply
   ```

3. **Get outputs**:
   ```bash
   terraform output
   ```

### Using Bash Scripts

1. **Configure environment**:
   ```bash
   cd scripts/
   
   # Make scripts executable
   chmod +x deploy.sh destroy.sh
   
   # Set environment variables
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export SERVICE_NAME="ai-chat-assistant"
   ```

2. **Deploy infrastructure**:
   ```bash
   ./deploy.sh
   ```

   The script will:
   - Enable required Google Cloud APIs
   - Create service accounts and IAM bindings
   - Set up Artifact Registry repository
   - Configure Cloud Build triggers
   - Deploy sample application to Cloud Run
   - Configure Vertex AI model access

## Development Workflow

### Using Cloud Shell Editor

1. **Access Cloud Shell Editor**:
   - Navigate to [https://ide.cloud.google.com](https://ide.cloud.google.com)
   - Select your project
   - Open the integrated terminal

2. **Clone and develop**:
   ```bash
   # In Cloud Shell Editor terminal
   git clone https://github.com/your-repo/ai-chat-app.git
   cd ai-chat-app
   
   # Install dependencies
   pip install -r requirements.txt
   
   # Run locally for testing
   python app/main.py
   ```

3. **Deploy changes**:
   ```bash
   # Commit changes
   git add .
   git commit -m "Update AI application"
   git push origin main
   
   # Cloud Build will automatically trigger deployment
   ```

### Local Development Alternative

If you prefer local development:

```bash
# Install Google Cloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Authenticate
gcloud auth login
gcloud config set project ${PROJECT_ID}

# Clone application code
git clone https://github.com/your-repo/ai-chat-app.git
cd ai-chat-app

# Set up local environment
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run locally
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
python app/main.py
```

## Configuration

### Environment Variables

The following variables can be customized:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `SERVICE_NAME` | Cloud Run service name | `ai-chat-assistant` | No |
| `VERTEX_AI_REGION` | Vertex AI region | Same as `REGION` | No |
| `MIN_INSTANCES` | Cloud Run minimum instances | `0` | No |
| `MAX_INSTANCES` | Cloud Run maximum instances | `10` | No |
| `MEMORY_LIMIT` | Cloud Run memory limit | `1Gi` | No |
| `CPU_LIMIT` | Cloud Run CPU limit | `1` | No |

### Terraform Variables

Create a `terraform.tfvars` file with your specific values:

```hcl
project_id = "your-project-id"
region = "us-central1"
service_name = "ai-chat-assistant"

# Optional customizations
enable_apis = true
min_instances = 0
max_instances = 10
memory_limit = "1Gi"
cpu_limit = "1"

# AI Configuration
vertex_ai_models = [
  "gemini-1.5-flash",
  "gemini-1.5-pro"
]

# Monitoring
enable_monitoring = true
log_level = "INFO"

# Security
allow_unauthenticated = true  # Set to false for production
cors_origins = ["*"]          # Restrict for production
```

## Security Considerations

### Production Hardening

1. **Authentication**: Enable Identity-Aware Proxy (IAP) for production:
   ```bash
   gcloud iap web enable --resource-type=cloud-run \
       --service=${SERVICE_NAME} \
       --region=${REGION}
   ```

2. **CORS Configuration**: Restrict CORS origins in production:
   ```bash
   gcloud run services update ${SERVICE_NAME} \
       --region=${REGION} \
       --set-env-vars="CORS_ORIGINS=https://yourdomain.com"
   ```

3. **Secrets Management**: Store API keys in Secret Manager:
   ```bash
   echo -n "your-api-key" | gcloud secrets create api-key --data-file=-
   ```

### IAM Best Practices

The generated infrastructure follows least-privilege principles:
- Service accounts have minimal required permissions
- Vertex AI access is scoped to specific models
- Cloud Run service account cannot access other projects
- Build triggers use dedicated service account

## Monitoring and Troubleshooting

### View Logs

```bash
# Cloud Run logs
gcloud logs read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
    --limit=50 \
    --format="table(timestamp,textPayload)"

# Cloud Build logs
gcloud logs read "resource.type=build" \
    --limit=20 \
    --format="table(timestamp,textPayload)"

# Vertex AI logs
gcloud logs read "resource.type=aiplatform.googleapis.com/Endpoint" \
    --limit=20
```

### Common Issues

1. **API not enabled error**:
   ```bash
   gcloud services enable aiplatform.googleapis.com
   gcloud services enable run.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   ```

2. **Permission denied errors**:
   ```bash
   # Check current permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Add required roles
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/run.admin"
   ```

3. **Vertex AI quota exceeded**:
   ```bash
   # Check quotas
   gcloud compute project-info describe --project=${PROJECT_ID}
   
   # Request quota increase through Cloud Console
   ```

## Cost Optimization

### Estimated Costs

- **Cloud Shell**: Free (50 hours/week)
- **Cloud Run**: ~$0.40/million requests
- **Vertex AI**: ~$0.125/1000 requests (Gemini Flash)
- **Cloud Build**: ~$0.003/build minute
- **Artifact Registry**: ~$0.10/GB/month

### Cost Control

1. **Set up billing alerts**:
   ```bash
   # Create budget alert
   gcloud billing budgets create \
       --billing-account=YOUR_BILLING_ACCOUNT \
       --display-name="AI App Budget" \
       --budget-amount=50USD \
       --threshold-rule=percent=80
   ```

2. **Configure auto-scaling limits**:
   ```bash
   gcloud run services update ${SERVICE_NAME} \
       --region=${REGION} \
       --max-instances=5 \
       --concurrency=100
   ```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/ai-app-deployment
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy
```

### Using Bash Scripts

```bash
cd scripts/

# Run cleanup script
./destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete Cloud Run service
gcloud run services delete ${SERVICE_NAME} --region=${REGION} --quiet

# Delete container images
gcloud container images delete gcr.io/${PROJECT_ID}/${SERVICE_NAME} --force-delete-tags --quiet

# Delete service accounts
gcloud iam service-accounts delete ${SERVICE_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --quiet

# Delete secrets
gcloud secrets delete api-key --quiet

# Disable APIs (optional)
gcloud services disable aiplatform.googleapis.com
gcloud services disable run.googleapis.com
gcloud services disable cloudbuild.googleapis.com
```

## Customization

### Adding New AI Models

1. **Update Terraform configuration**:
   ```hcl
   # In terraform/variables.tf
   variable "vertex_ai_models" {
     default = [
       "gemini-1.5-flash",
       "gemini-1.5-pro",
       "text-bison@001"  # Add new model
     ]
   }
   ```

2. **Redeploy infrastructure**:
   ```bash
   terraform plan
   terraform apply
   ```

### Scaling Configuration

Modify scaling parameters in your configuration:

```yaml
# infrastructure-manager/main.yaml
resources:
  - name: cloud-run-service
    type: gcp-types/run-v1:namespaces.services
    properties:
      spec:
        template:
          metadata:
            annotations:
              autoscaling.knative.dev/minScale: "1"
              autoscaling.knative.dev/maxScale: "100"
```

## Advanced Features

### Multi-Region Deployment

For global availability, deploy to multiple regions:

```bash
# Deploy to additional regions
for region in "europe-west1" "asia-southeast1"; do
  export REGION=$region
  ./scripts/deploy.sh
done
```

### Custom Domain Setup

1. **Map custom domain**:
   ```bash
   gcloud run domain-mappings create \
       --service=${SERVICE_NAME} \
       --domain=ai.yourdomain.com \
       --region=${REGION}
   ```

2. **Configure SSL certificate**:
   ```bash
   gcloud compute ssl-certificates create ai-app-ssl \
       --domains=ai.yourdomain.com \
       --global
   ```

## Support

### Getting Help

1. **Google Cloud Support**: Use the Cloud Console support tab
2. **Community Support**: 
   - [Google Cloud Community](https://cloud.google.com/community)
   - [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)
3. **Documentation**: 
   - [Cloud Run Documentation](https://cloud.google.com/run/docs)
   - [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Contributing

To contribute improvements to this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

### License

This infrastructure code is provided under the same license as the parent recipe repository.

---

**Note**: This infrastructure code is generated based on the recipe "Developing Browser-Based AI Applications with Cloud Shell Editor and Vertex AI". For detailed implementation guidance, refer to the original recipe documentation.