# Infrastructure as Code for Streamlining Multi-Environment Application Deployment with Cloud Deploy and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Streamlining Multi-Environment Application Deployment with Cloud Deploy and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Docker installed for local container building
- kubectl command-line tool installed
- Appropriate Google Cloud permissions:
  - Project Editor or custom role with:
    - Compute Engine Admin
    - Kubernetes Engine Admin
    - Cloud Deploy Admin
    - Cloud Build Admin
    - Artifact Registry Admin
    - Storage Admin
- Billing enabled on your Google Cloud project
- APIs enabled:
  - Compute Engine API
  - Kubernetes Engine API
  - Cloud Deploy API
  - Cloud Build API
  - Artifact Registry API
  - Cloud Resource Manager API

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create a deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/DEPLOYMENT_NAME \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo=https://github.com/YOUR_REPO \
    --git-source-directory=. \
    --git-source-ref=main
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply

# Confirm deployment when prompted
# Type 'yes' to proceed
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Architecture Overview

This infrastructure deploys:

- **3 GKE Clusters**: Development, staging, and production environments
- **Artifact Registry**: Container image storage with vulnerability scanning
- **Cloud Deploy Pipeline**: Automated deployment pipeline with approval gates
- **Cloud Build**: CI/CD automation for container building and releases
- **Cloud Storage**: Deployment artifacts and pipeline state storage
- **IAM Roles**: Proper service account permissions for automated deployments

## Configuration

### Environment Variables

Set these variables before deployment:

```bash
# Project configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Resource naming (optional - will be generated if not set)
export CLUSTER_DEV="dev-cluster"
export CLUSTER_STAGE="staging-cluster"
export CLUSTER_PROD="prod-cluster"
export REPO_NAME="app-repo"
export PIPELINE_NAME="app-pipeline"
export BUCKET_NAME="deploy-artifacts-bucket"
```

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

- `project_id`: Your Google Cloud project ID
- `region`: Google Cloud region for resources
- `zone`: Google Cloud zone for GKE clusters
- `cluster_machine_type_dev`: Machine type for development cluster nodes
- `cluster_machine_type_staging`: Machine type for staging cluster nodes
- `cluster_machine_type_prod`: Machine type for production cluster nodes
- `dev_node_count`: Number of nodes in development cluster
- `staging_node_count`: Number of nodes in staging cluster
- `prod_node_count`: Number of nodes in production cluster

### Infrastructure Manager Variables

Customize deployment in `infrastructure-manager/main.yaml`:

- Project ID and region settings
- GKE cluster configurations
- Pipeline approval requirements
- Resource naming conventions

## Deployment Process

### 1. Initial Setup

The infrastructure creates:
- GKE clusters for each environment (dev, staging, prod)
- Artifact Registry repository for container images
- Cloud Deploy delivery pipeline with promotion stages
- Cloud Storage bucket for artifacts
- Required IAM service accounts and permissions

### 2. Application Deployment

After infrastructure setup:
1. Build and push container images to Artifact Registry
2. Create Cloud Deploy releases
3. Deploy automatically to development
4. Promote through staging to production (with approval gates)

### 3. Pipeline Stages

- **Development**: Automatic deployment, 2 nodes, e2-standard-2
- **Staging**: Automatic deployment, 2 nodes, e2-standard-2
- **Production**: Requires approval, 3 nodes, e2-standard-4

## Validation

### Verify Infrastructure

```bash
# Check GKE clusters
gcloud container clusters list

# Verify Cloud Deploy pipeline
gcloud deploy delivery-pipelines list --region=$REGION

# Check Artifact Registry
gcloud artifacts repositories list --location=$REGION

# Verify Cloud Storage bucket
gsutil ls -b gs://your-bucket-name
```

### Test Application Deployment

```bash
# Get cluster credentials
gcloud container clusters get-credentials $CLUSTER_DEV --zone=$ZONE

# Check application deployment
kubectl get deployments,services,pods

# Test application endpoint
kubectl get service sample-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## Monitoring and Observability

The infrastructure includes:

- **Cloud Monitoring**: Automatic metrics collection for GKE clusters
- **Cloud Logging**: Centralized logging for all components
- **Cloud Deploy Monitoring**: Pipeline execution tracking
- **Artifact Registry Scanning**: Container vulnerability scanning

Access monitoring through:
- Google Cloud Console > Monitoring
- Google Cloud Console > Cloud Deploy
- Google Cloud Console > Artifact Registry

## Cost Optimization

### Estimated Costs

- **Development Environment**: ~$100-150/month
- **Staging Environment**: ~$100-150/month
- **Production Environment**: ~$200-300/month
- **Storage and Networking**: ~$20-50/month

### Cost-Saving Features

- **Preemptible Nodes**: Enabled for dev/staging environments
- **Cluster Autoscaling**: Automatically adjusts node count
- **Artifact Registry**: Lifecycle policies for image cleanup
- **Resource Labels**: Cost tracking and allocation

## Security Features

### Implemented Security Controls

- **Workload Identity**: Secure GKE to Google Cloud service integration
- **Private GKE Clusters**: Nodes without public IP addresses
- **Network Policies**: Pod-to-pod communication restrictions
- **RBAC**: Role-based access control for Kubernetes resources
- **Binary Authorization**: Container image verification (configurable)
- **Artifact Registry Scanning**: Vulnerability scanning for images

### Security Best Practices

- All clusters use Google Cloud managed SSL certificates
- Service accounts follow principle of least privilege
- Network traffic is encrypted in transit
- Container images are scanned for vulnerabilities
- Audit logging is enabled for all components

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled
2. **Insufficient Permissions**: Verify service account has required roles
3. **Resource Quotas**: Check project quotas for GKE nodes and IP addresses
4. **Network Connectivity**: Verify VPC and firewall configurations

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify permissions
gcloud projects get-iam-policy $PROJECT_ID

# Check resource quotas
gcloud compute project-info describe --project=$PROJECT_ID

# Debug GKE cluster issues
gcloud container clusters describe $CLUSTER_NAME --zone=$ZONE
```

## Cleanup

### Using Terraform

```bash
cd terraform/
terraform destroy
# Confirm destruction when prompted
```

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/DEPLOYMENT_NAME
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
# Follow prompts to confirm resource deletion
```

### Manual Cleanup

If automated cleanup fails:

```bash
# Delete Cloud Deploy resources
gcloud deploy delivery-pipelines delete $PIPELINE_NAME --region=$REGION

# Delete GKE clusters
gcloud container clusters delete $CLUSTER_DEV --zone=$ZONE
gcloud container clusters delete $CLUSTER_STAGE --zone=$ZONE
gcloud container clusters delete $CLUSTER_PROD --zone=$ZONE

# Delete Artifact Registry
gcloud artifacts repositories delete $REPO_NAME --location=$REGION

# Delete Cloud Storage bucket
gsutil rm -r gs://$BUCKET_NAME
```

## Customization

### Environment-Specific Configurations

Modify cluster configurations in the respective IaC files:

- **Node counts**: Adjust based on expected workload
- **Machine types**: Change based on resource requirements
- **Regions/Zones**: Deploy closer to your users
- **Approval requirements**: Modify pipeline approval gates

### Application Integration

To integrate your own application:

1. Replace the sample application code with your application
2. Update Dockerfile and container configuration
3. Modify Kubernetes manifests for your application requirements
4. Update Skaffold configuration for your build process
5. Adjust resource requests and limits based on your application needs

### Pipeline Customization

Modify the Cloud Deploy pipeline configuration:

- Add additional environments (QA, UAT, etc.)
- Configure different approval requirements
- Integrate with external approval systems
- Add custom deployment strategies (canary, blue-green)

## Advanced Features

### Canary Deployments

Enable canary deployments by modifying the Cloud Deploy configuration:

```yaml
# Add to clouddeploy.yaml
canaryDeployment:
  percentages: [25, 50, 75]
  verify: true
```

### Multi-Region Deployment

Extend the infrastructure to multiple regions:

1. Duplicate cluster resources in additional regions
2. Configure global load balancing
3. Update pipeline to deploy across regions
4. Implement cross-region monitoring

### Integration with CI/CD

Connect with external CI/CD systems:

- GitHub Actions integration
- GitLab CI/CD pipelines
- Jenkins integration
- Custom webhook triggers

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../streamlining-multi-environment-application-deployment-with-cloud-deploy-and-cloud-build.md)
2. Review [Google Cloud Deploy documentation](https://cloud.google.com/deploy/docs)
3. Consult [Google Cloud Build documentation](https://cloud.google.com/build/docs)
4. Visit [GKE documentation](https://cloud.google.com/kubernetes-engine/docs)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Update documentation for any configuration changes
3. Verify compatibility with the original recipe
4. Submit changes with appropriate testing evidence

## License

This infrastructure code is provided under the same license as the original recipe repository.