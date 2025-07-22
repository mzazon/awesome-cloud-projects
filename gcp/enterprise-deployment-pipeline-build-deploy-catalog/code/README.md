# Infrastructure as Code for Enterprise Deployment Pipeline Management with Cloud Build, Cloud Deploy, and Service Catalog

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Enterprise Deployment Pipeline Management with Cloud Build, Cloud Deploy, and Service Catalog".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with appropriate permissions for:
  - Cloud Build API
  - Cloud Deploy API
  - Service Catalog API
  - Google Kubernetes Engine API
  - Artifact Registry API
  - Cloud Source Repositories API
  - Container Registry API
  - IAM Service Account management
- Docker installed (for local testing)
- kubectl installed for Kubernetes cluster management
- Appropriate IAM permissions for resource creation and management

## Architecture Overview

This solution deploys:
- Multi-environment GKE clusters (development, staging, production)
- Artifact Registry repository for container images
- Cloud Source Repositories for code and pipeline templates
- Cloud Deploy delivery pipeline with progressive deployment stages
- Cloud Build triggers and pipeline templates
- IAM service accounts with appropriate permissions
- Sample application and Kubernetes manifests

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    --location=${REGION} \
    --file=main.yaml \
    --deployment-id=enterprise-pipeline-deployment \
    --service-account="your-service-account@${PROJECT_ID}.iam.gserviceaccount.com"

# Monitor deployment status
gcloud infra-manager deployments describe \
    enterprise-pipeline-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan the deployment
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
export ZONE="us-central1-a"

# Deploy the infrastructure
./scripts/deploy.sh

# Monitor the deployment
gcloud container clusters list
gcloud deploy delivery-pipelines list --region=${REGION}
```

## Configuration Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `project_id` | Google Cloud project ID | `my-enterprise-project` |
| `region` | Primary region for resources | `us-central1` |
| `zone` | Primary zone for resources | `us-central1-a` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name_prefix` | Prefix for GKE cluster names | `enterprise-gke` |
| `repo_name` | Artifact Registry repository name | `enterprise-apps` |
| `enable_network_policy` | Enable network policies on GKE clusters | `true` |
| `enable_shielded_nodes` | Enable shielded nodes on production cluster | `true` |
| `node_machine_type` | Machine type for GKE nodes | `e2-standard-4` |

## Post-Deployment Steps

After the infrastructure is deployed, complete these steps to activate the pipeline:

1. **Clone Source Repositories**:
   ```bash
   # Clone pipeline templates repository
   gcloud source repos clone pipeline-templates
   
   # Clone sample application repository  
   gcloud source repos clone sample-app
   ```

2. **Add Pipeline Templates**:
   ```bash
   cd pipeline-templates
   # Copy your Cloud Build and Cloud Deploy configurations
   # Commit and push the templates
   git add .
   git commit -m "Add enterprise pipeline templates"
   git push origin main
   ```

3. **Deploy Sample Application**:
   ```bash
   cd ../sample-app
   # Add your application code and Kubernetes manifests
   # Commit and push to trigger the pipeline
   git add .
   git commit -m "Initial application deployment"
   git push origin main
   ```

4. **Configure Build Triggers**:
   ```bash
   # Create build trigger for sample application
   gcloud builds triggers create cloud-source-repositories \
       --repo=sample-app \
       --branch-pattern="main" \
       --build-config=cloudbuild.yaml \
       --description="Enterprise deployment pipeline trigger"
   ```

## Validation

### Verify Infrastructure Deployment

1. **Check GKE Clusters**:
   ```bash
   gcloud container clusters list --format="table(name,status,location)"
   ```

2. **Verify Artifact Registry**:
   ```bash
   gcloud artifacts repositories list --format="table(name,format,location)"
   ```

3. **Check Cloud Deploy Pipeline**:
   ```bash
   gcloud deploy delivery-pipelines list --region=${REGION}
   ```

4. **Verify Source Repositories**:
   ```bash
   gcloud source repos list
   ```

### Test Application Deployment

1. **Trigger Pipeline Execution**:
   ```bash
   # Make a code change to trigger the pipeline
   cd sample-app
   echo "// Pipeline test" >> app.js
   git add app.js
   git commit -m "Test pipeline execution"
   git push origin main
   ```

2. **Monitor Build Progress**:
   ```bash
   gcloud builds list --ongoing --format="table(id,status,source.repoSource.repoName)"
   ```

3. **Check Application Status**:
   ```bash
   # Get credentials for development cluster
   gcloud container clusters get-credentials enterprise-gke-dev --region=${REGION}
   
   # Check application deployment
   kubectl get deployments,services,pods -l app=sample-app
   ```

## Monitoring and Observability

### Cloud Build Monitoring

- View build history: [Cloud Build Console](https://console.cloud.google.com/cloud-build/builds)
- Monitor build logs and metrics
- Set up build notifications

### Cloud Deploy Monitoring

- View deployment pipelines: [Cloud Deploy Console](https://console.cloud.google.com/deploy/delivery-pipelines)
- Monitor deployment progress and approvals
- Review deployment history and rollbacks

### GKE Monitoring

- Monitor cluster health via Google Cloud Console
- Use Cloud Monitoring for application metrics
- Set up alerting for cluster and application issues

## Security Considerations

### IAM Best Practices

- Service accounts follow least privilege principle
- Build service account has minimal required permissions
- Cluster access is properly configured with RBAC

### Network Security

- GKE clusters use private nodes by default
- Network policies are enabled for micro-segmentation
- VPC-native networking with IP aliasing

### Container Security

- Artifact Registry provides vulnerability scanning
- Production clusters use shielded nodes
- Container images are scanned before deployment

## Cost Optimization

### Resource Scaling

- Development and staging clusters can be scaled down during off-hours
- Use GKE Autopilot for automatic resource optimization
- Implement cluster autoscaling for variable workloads

### Monitoring Costs

```bash
# View current resource costs
gcloud billing budgets list --billing-account=${BILLING_ACCOUNT_ID}

# Set up cost alerts
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="Enterprise Pipeline Budget" \
    --budget-amount=1000USD
```

## Troubleshooting

### Common Issues

1. **Build Failures**:
   - Check Cloud Build logs in Google Cloud Console
   - Verify service account permissions
   - Ensure Artifact Registry repository exists

2. **Deployment Failures**:
   - Check Cloud Deploy pipeline logs
   - Verify GKE cluster connectivity
   - Confirm Kubernetes manifests are valid

3. **Authentication Issues**:
   - Verify gcloud authentication: `gcloud auth list`
   - Check project configuration: `gcloud config list`
   - Ensure APIs are enabled: `gcloud services list --enabled`

### Debug Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:cloudbuild OR name:clouddeploy OR name:container"

# Verify service account permissions
gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:cloudbuild-deploy*"

# Test cluster connectivity
gcloud container clusters get-credentials enterprise-gke-dev --region=${REGION}
kubectl cluster-info
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    enterprise-pipeline-deployment \
    --location=${REGION} \
    --delete-policy=DELETE

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
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

```bash
# Delete GKE clusters
gcloud container clusters delete enterprise-gke-dev --region=${REGION} --quiet
gcloud container clusters delete enterprise-gke-staging --region=${REGION} --quiet
gcloud container clusters delete enterprise-gke-prod --region=${REGION} --quiet

# Delete Cloud Deploy pipeline
gcloud deploy delivery-pipelines delete enterprise-pipeline --region=${REGION} --quiet

# Delete Artifact Registry repository
gcloud artifacts repositories delete enterprise-apps --location=${REGION} --quiet

# Delete source repositories
gcloud source repos delete pipeline-templates --quiet
gcloud source repos delete sample-app --quiet

# Delete service accounts
gcloud iam service-accounts delete cloudbuild-deploy@${PROJECT_ID}.iam.gserviceaccount.com --quiet
```

## Customization

### Environment-Specific Configurations

Modify the infrastructure for different environments:

1. **Development Environment**:
   - Smaller node pools
   - Reduced replica counts
   - Relaxed security policies

2. **Production Environment**:
   - Multi-zone clusters
   - Enhanced monitoring
   - Stricter security controls

### Pipeline Customization

1. **Add Security Scanning**:
   - Integrate vulnerability scanning in Cloud Build
   - Add policy enforcement checks
   - Implement compliance validation

2. **Multi-Region Deployment**:
   - Extend Cloud Deploy pipeline to multiple regions
   - Configure cross-region artifact replication
   - Implement global load balancing

### Integration Examples

1. **Slack Notifications**:
   ```bash
   # Add to Cloud Build pipeline
   - name: 'gcr.io/cloud-builders/curl'
     args: 
     - '-X'
     - 'POST'
     - '-H'
     - 'Content-type: application/json'
     - '--data'
     - '{"text":"Build completed: ${BUILD_ID}"}'
     - '${_SLACK_WEBHOOK_URL}'
   ```

2. **Automated Testing**:
   ```bash
   # Add testing step to Cloud Build
   - name: 'gcr.io/cloud-builders/docker'
     args: ['run', '--rm', '${_IMAGE_NAME}', 'npm', 'test']
   ```

## Support and Documentation

### Additional Resources

- [Google Cloud DevOps Solutions](https://cloud.google.com/solutions/devops)
- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Cloud Deploy Best Practices](https://cloud.google.com/deploy/docs/best-practices)
- [GKE Security Best Practices](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster)
- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)

### Community Support

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow - Google Cloud Platform](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud Slack Community](https://cloud.google.com/community/slack)

### Professional Support

For production deployments, consider:
- Google Cloud Professional Services
- Google Cloud Support Plans
- Certified Google Cloud Partners

---

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud documentation for specific services.