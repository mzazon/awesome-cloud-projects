# Infrastructure as Code for Multi-Environment Application Deployment with Cloud Deploy and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Environment Application Deployment with Cloud Deploy and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Git installed for repository management
- Docker installed for container image building (if running locally)
- Appropriate Google Cloud permissions:
  - Project Editor or Owner role
  - Cloud Deploy Admin role
  - Cloud Build Editor role
  - Kubernetes Engine Admin role
  - Service Account Admin role
  - Storage Admin role
- kubectl installed for Kubernetes cluster management
- Estimated cost: $10-20 for GKE clusters during testing period

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-env-cicd \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file=terraform.tfvars

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-env-cicd
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# Set project_id, region, and other customizable parameters

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Create GKE clusters for dev, staging, and prod environments
# 2. Set up Cloud Deploy pipeline configuration
# 3. Create Cloud Build triggers and service accounts
# 4. Deploy sample application across all environments
# 5. Configure progressive delivery pipeline
```

## Architecture Overview

This implementation creates a complete multi-environment CI/CD pipeline with:

### Infrastructure Components

- **3 GKE Autopilot Clusters**: Separate clusters for development, staging, and production
- **Cloud Deploy Pipeline**: Progressive delivery pipeline with approval gates
- **Cloud Build Configuration**: Automated container building and deployment
- **Cloud Storage Bucket**: Artifact storage for build outputs
- **Service Accounts**: Properly configured IAM for Cloud Deploy and Cloud Build
- **Sample Application**: Node.js web application with Kubernetes manifests

### Deployment Flow

1. **Source Code Changes** → Cloud Build Trigger
2. **Build Process** → Container image creation and push to Registry
3. **Cloud Deploy Release** → Automated deployment to development
4. **Manual Approval** → Promotion to staging environment
5. **Canary Deployment** → Gradual rollout to production with verification

## Environment-Specific Configurations

### Development Environment
- **Cluster**: Single-node Autopilot cluster
- **Application**: 1 replica with minimal resource requests
- **Deployment**: Automatic deployment on every build
- **Access**: LoadBalancer service for testing

### Staging Environment
- **Cluster**: Multi-node Autopilot cluster
- **Application**: 2 replicas with standard resource allocation
- **Deployment**: Manual approval required for promotion
- **Verification**: Automated testing before production promotion

### Production Environment
- **Cluster**: Multi-node Autopilot cluster with production-grade configuration
- **Application**: 3 replicas with optimized resource allocation
- **Deployment**: Canary deployment strategy (25% → 50% → 100%)
- **Monitoring**: Full observability with Cloud Logging and Monitoring

## Customization

### Terraform Variables

Edit `terraform/terraform.tfvars` to customize:

```hcl
# Project and region settings
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Application settings
app_name          = "sample-webapp"
pipeline_name     = "sample-app-pipeline"
container_image   = "gcr.io/your-project/sample-webapp"

# Cluster configuration
cluster_node_count = 3
cluster_machine_type = "e2-medium"

# Environment-specific settings
dev_replica_count     = 1
staging_replica_count = 2
prod_replica_count    = 3

# Resource allocation
dev_cpu_request    = "50m"
dev_memory_request = "128Mi"
prod_cpu_request   = "200m"
prod_memory_request = "256Mi"
```

### Infrastructure Manager Configuration

Edit `infrastructure-manager/terraform.tfvars` to customize deployment parameters:

```yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
app_name: "sample-webapp"
pipeline_name: "sample-app-pipeline"
enable_monitoring: true
enable_logging: true
```

### Environment Variables for Scripts

The bash scripts use these environment variables:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional customization
export APP_NAME="sample-webapp"
export PIPELINE_NAME="sample-app-pipeline"
export CLUSTER_PREFIX="deploy-demo"
```

## Post-Deployment Verification

### Check Cluster Status

```bash
# List all clusters
gcloud container clusters list --region=${REGION}

# Get cluster credentials
gcloud container clusters get-credentials ${CLUSTER_PREFIX}-dev --region=${REGION}
gcloud container clusters get-credentials ${CLUSTER_PREFIX}-staging --region=${REGION}
gcloud container clusters get-credentials ${CLUSTER_PREFIX}-prod --region=${REGION}
```

### Verify Cloud Deploy Pipeline

```bash
# Check pipeline status
gcloud deploy delivery-pipelines describe ${PIPELINE_NAME} --region=${REGION}

# List deployment targets
gcloud deploy targets list --region=${REGION}

# Monitor recent releases
gcloud deploy releases list --delivery-pipeline=${PIPELINE_NAME} --region=${REGION}
```

### Test Application Endpoints

```bash
# Get service endpoints for each environment
kubectl config use-context gke_${PROJECT_ID}_${REGION}_${CLUSTER_PREFIX}-dev
kubectl get services

kubectl config use-context gke_${PROJECT_ID}_${REGION}_${CLUSTER_PREFIX}-staging
kubectl get services

kubectl config use-context gke_${PROJECT_ID}_${REGION}_${CLUSTER_PREFIX}-prod
kubectl get services
```

## Monitoring and Observability

### Cloud Logging

View deployment logs:
```bash
# Cloud Deploy logs
gcloud logging read "resource.type=cloud_deploy_release" --limit=50

# Cloud Build logs
gcloud logging read "resource.type=build" --limit=50
```

### Cloud Monitoring

Monitor key metrics:
- Deployment success rate
- Application response time
- Cluster resource utilization
- Pipeline execution duration

### Alerting

Set up alerts for:
- Failed deployments
- High error rates
- Resource exhaustion
- Pipeline approval timeout

## Troubleshooting

### Common Issues

1. **Permission Errors**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   
   # Verify service account permissions
   gcloud iam service-accounts describe clouddeploy-sa@${PROJECT_ID}.iam.gserviceaccount.com
   ```

2. **Cluster Connection Issues**
   ```bash
   # Refresh cluster credentials
   gcloud container clusters get-credentials CLUSTER_NAME --region=${REGION}
   
   # Check cluster status
   gcloud container clusters describe CLUSTER_NAME --region=${REGION}
   ```

3. **Pipeline Failures**
   ```bash
   # Check pipeline logs
   gcloud deploy releases describe RELEASE_NAME --delivery-pipeline=${PIPELINE_NAME} --region=${REGION}
   
   # Review rollout details
   gcloud deploy rollouts describe ROLLOUT_NAME --delivery-pipeline=${PIPELINE_NAME} --region=${REGION}
   ```

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify resource quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# Check build history
gcloud builds list --limit=10

# Monitor resource usage
kubectl top nodes
kubectl top pods
```

## Security Considerations

### Service Account Permissions

- **Cloud Deploy SA**: Minimal permissions for deployment operations
- **Cloud Build SA**: Limited to build and release creation
- **GKE Node SA**: Default Compute Engine service account with minimal permissions

### Network Security

- **Private GKE Clusters**: Consider enabling private clusters for production
- **Authorized Networks**: Restrict API server access to specific IP ranges
- **Network Policies**: Implement Kubernetes network policies for pod-to-pod communication

### Container Security

- **Image Scanning**: Enable vulnerability scanning in Container Registry
- **Binary Authorization**: Consider implementing binary authorization policies
- **Pod Security Standards**: Apply appropriate pod security standards

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-env-cicd

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Deploy pipeline and targets
# 2. Remove all GKE clusters
# 3. Clean up Cloud Build resources
# 4. Delete service accounts
# 5. Remove storage buckets
# 6. Optionally delete the entire project
```

### Manual Cleanup (if needed)

```bash
# Delete clusters
gcloud container clusters delete ${CLUSTER_PREFIX}-dev --region=${REGION} --quiet
gcloud container clusters delete ${CLUSTER_PREFIX}-staging --region=${REGION} --quiet
gcloud container clusters delete ${CLUSTER_PREFIX}-prod --region=${REGION} --quiet

# Delete Cloud Deploy resources
gcloud deploy delivery-pipelines delete ${PIPELINE_NAME} --region=${REGION} --quiet

# Delete service accounts
gcloud iam service-accounts delete clouddeploy-sa@${PROJECT_ID}.iam.gserviceaccount.com --quiet

# Delete storage bucket
gsutil -m rm -r gs://${PROJECT_ID}-build-artifacts
```

## Cost Optimization

### Resource Sizing

- **Development**: Use minimal resources for cost savings
- **Staging**: Mirror production sizing for accurate testing
- **Production**: Right-size based on actual workload requirements

### Cluster Management

- **Autopilot**: Leverages Google's optimized resource allocation
- **Preemptible Nodes**: Consider for non-production environments
- **Cluster Autoscaling**: Enable for dynamic resource allocation

### Monitoring Costs

```bash
# View current costs
gcloud billing budgets list --billing-account=BILLING_ACCOUNT_ID

# Set up budget alerts
gcloud billing budgets create --billing-account=BILLING_ACCOUNT_ID \
    --display-name="CI/CD Pipeline Budget" \
    --budget-amount=100USD
```

## Extensions and Enhancements

### Advanced Features

1. **Multi-Region Deployment**: Extend to multiple regions for disaster recovery
2. **Istio Service Mesh**: Add service mesh for advanced traffic management
3. **GitOps Integration**: Implement ArgoCD or Flux for GitOps workflows
4. **Advanced Monitoring**: Add Prometheus and Grafana for detailed metrics
5. **Security Scanning**: Integrate Twistlock or similar for container security

### Integration Options

- **External Secrets**: Integrate with Secret Manager for external secrets
- **Config Management**: Use Config Connector for declarative resource management
- **Policy Management**: Implement Policy Controller for compliance
- **Backup Solutions**: Add Velero for cluster backup and restore

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for solution context
2. **Google Cloud Documentation**: [Cloud Deploy](https://cloud.google.com/deploy/docs), [Cloud Build](https://cloud.google.com/build/docs), [GKE](https://cloud.google.com/kubernetes-engine/docs)
3. **Terraform Documentation**: [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community), [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)

## Version History

- **v1.0**: Initial implementation with basic CI/CD pipeline
- **v1.1**: Added environment-specific configurations and canary deployments
- **v1.2**: Enhanced monitoring and security configurations
- **v1.3**: Added Infrastructure Manager support and improved documentation