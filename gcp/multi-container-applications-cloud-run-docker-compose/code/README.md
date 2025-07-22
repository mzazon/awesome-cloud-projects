# Infrastructure as Code for Deploying Multi-Container Applications with Cloud Run and Docker Compose

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Deploying Multi-Container Applications with Cloud Run and Docker Compose".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud Platform account with billing enabled
- gcloud CLI installed and configured (or use Cloud Shell)
- Docker Desktop installed locally for development and testing
- Appropriate GCP permissions for creating:
  - Cloud Run services
  - Cloud SQL instances
  - Secret Manager secrets
  - Artifact Registry repositories
  - IAM roles and bindings
- Basic knowledge of containerization and multi-container architectures
- Estimated cost: $10-30/month for development usage

## Quick Start

### Using Infrastructure Manager (Google Cloud Native)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments create multicontainer-deployment \
    --location=${REGION} \
    --source=. \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe multicontainer-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy example variables file and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Review planned changes
terraform plan

# Apply the infrastructure
terraform apply

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

# Run deployment script
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create Artifact Registry repository
# 3. Set up Cloud SQL instance
# 4. Configure Secret Manager
# 5. Build and push container images
# 6. Deploy multi-container Cloud Run service
```

## Architecture Overview

This infrastructure deploys a multi-container application on Google Cloud Run consisting of:

- **Frontend Container**: React/Vue application served by Node.js
- **Backend Container**: REST API service with database connectivity
- **Proxy Container**: Nginx reverse proxy for request routing
- **Cloud SQL Proxy**: Sidecar container for secure database connections

### Supporting Infrastructure

- **Cloud SQL**: PostgreSQL database instance
- **Secret Manager**: Secure storage for database credentials
- **Artifact Registry**: Private container image repository
- **IAM**: Service accounts and permissions for secure access

## Configuration

### Infrastructure Manager Variables

Edit the `main.yaml` file to customize:

```yaml
variables:
  project_id:
    description: "GCP Project ID"
    type: string
  region:
    description: "GCP Region for resources"
    type: string
    default: "us-central1"
  service_name:
    description: "Cloud Run service name"
    type: string
    default: "multi-container-app"
```

### Terraform Variables

Key variables in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Service configuration
service_name = "multi-container-app"
cpu_limit    = "2"
memory_limit = "4Gi"

# Database configuration
db_instance_name = "multicontainer-db"
db_tier         = "db-f1-micro"
database_name   = "appdb"
db_user         = "appuser"

# Container configuration
frontend_image = "frontend:latest"
backend_image  = "backend:latest"
proxy_image    = "proxy:latest"
```

### Bash Script Configuration

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export SERVICE_NAME="multi-container-app"
export DB_INSTANCE_NAME="multicontainer-db"
```

## Deployment Process

### Infrastructure Manager Deployment

1. **Preparation**: APIs are enabled and service accounts configured
2. **Infrastructure**: Cloud SQL, Secret Manager, and Artifact Registry created
3. **Container Build**: Application images built and pushed to registry
4. **Service Deployment**: Multi-container Cloud Run service deployed
5. **Configuration**: IAM permissions and networking configured

### Terraform Deployment

1. **Provider Setup**: Google Cloud provider initialized with authentication
2. **Resource Creation**: All infrastructure resources created in dependency order
3. **Container Registry**: Artifact Registry repository and images configured
4. **Database Setup**: Cloud SQL instance with secure credentials
5. **Service Deployment**: Cloud Run service with multi-container configuration

### Bash Script Deployment

1. **Prerequisites Check**: Verify required tools and permissions
2. **API Enablement**: Enable all required Google Cloud APIs
3. **Infrastructure Creation**: Create supporting resources step by step
4. **Image Building**: Build and push application containers
5. **Service Deployment**: Deploy multi-container Cloud Run service
6. **Validation**: Verify deployment success and connectivity

## Validation

After deployment, verify the infrastructure:

```bash
# Check Cloud Run service status
gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format="table(status.conditions[].type,status.conditions[].status)"

# Test application endpoints
SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format='value(status.url)')

# Test health endpoints
curl -s "${SERVICE_URL}/health"

# Test API functionality
curl -s "${SERVICE_URL}/api/data"

# Verify database connectivity
curl -s "${SERVICE_URL}" | grep "Multi-Container Cloud Run Application"
```

## Monitoring and Logs

### Application Logs

```bash
# View Cloud Run service logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}" \
    --limit=50 \
    --format="table(timestamp,textPayload)"

# View container-specific logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME} AND labels.container_name=backend" \
    --limit=20
```

### Performance Monitoring

```bash
# Check service metrics
gcloud run services describe ${SERVICE_NAME} \
    --region=${REGION} \
    --format="yaml" | grep -A 10 "status:"

# Monitor resource utilization
gcloud monitoring metrics list --filter="resource.type=cloud_run_revision"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete multicontainer-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify state is clean
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Run service
# 2. Remove Cloud SQL instance
# 3. Delete Secret Manager secrets
# 4. Remove Artifact Registry repository
# 5. Clean up IAM resources
```

### Manual Cleanup Verification

```bash
# Verify Cloud Run services are removed
gcloud run services list --region=${REGION}

# Verify Cloud SQL instances are removed
gcloud sql instances list

# Verify secrets are removed
gcloud secrets list

# Verify Artifact Registry repositories are removed
gcloud artifacts repositories list --location=${REGION}
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services enable run.googleapis.com
   gcloud services enable sql-component.googleapis.com
   gcloud services enable secretmanager.googleapis.com
   gcloud services enable artifactregistry.googleapis.com
   ```

2. **Insufficient Permissions**: Verify IAM roles
   ```bash
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Container Build Failures**: Check Docker configuration
   ```bash
   gcloud auth configure-docker ${REGION}-docker.pkg.dev
   ```

4. **Database Connection Issues**: Verify Cloud SQL proxy configuration
   ```bash
   gcloud sql instances describe ${DB_INSTANCE_NAME}
   ```

### Debug Commands

```bash
# Check service revision details
gcloud run revisions list --service=${SERVICE_NAME} --region=${REGION}

# Inspect container logs for specific issues
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=10

# Test database connectivity
gcloud sql connect ${DB_INSTANCE_NAME} --user=appuser --database=appdb
```

## Security Considerations

- **Secret Management**: Database credentials stored securely in Secret Manager
- **IAM**: Least privilege access implemented for all service accounts
- **Network Security**: Cloud SQL accessed only through authenticated proxy
- **Container Security**: Images scanned for vulnerabilities in Artifact Registry
- **Traffic Encryption**: All communication encrypted in transit

## Cost Optimization

- **Resource Sizing**: Configure appropriate CPU and memory limits
- **Auto-scaling**: Cloud Run scales to zero when not in use
- **Database Tier**: Use appropriate Cloud SQL tier for workload
- **Monitoring**: Set up billing alerts and budget controls

```bash
# Set billing budget alert
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Multi-Container App Budget" \
    --budget-amount=100USD \
    --threshold-percent=80
```

## Customization Examples

### Adding Additional Containers

To add more containers to the Cloud Run service, modify the configuration:

```yaml
# Infrastructure Manager example
containers:
  - name: monitoring
    image: gcr.io/google-containers/cadvisor:latest
    resources:
      limits:
        cpu: 200m
        memory: 256Mi
```

### Custom Domain Configuration

```bash
# Map custom domain to Cloud Run service
gcloud run domain-mappings create \
    --service=${SERVICE_NAME} \
    --domain=myapp.example.com \
    --region=${REGION}
```

### Environment-Specific Configurations

Create separate variable files for different environments:

```bash
# Production deployment
terraform apply -var-file="prod.tfvars"

# Staging deployment  
terraform apply -var-file="staging.tfvars"
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../multi-container-applications-cloud-run-docker-compose.md)
2. Review [Google Cloud Run documentation](https://cloud.google.com/run/docs)
3. Consult [Cloud SQL documentation](https://cloud.google.com/sql/docs)
4. Reference [Artifact Registry documentation](https://cloud.google.com/artifact-registry/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation to reflect changes
3. Validate all deployment methods still work
4. Follow Google Cloud best practices
5. Ensure security configurations remain intact

## License

This infrastructure code is provided as part of the cloud recipes collection and follows the same licensing terms as the parent repository.