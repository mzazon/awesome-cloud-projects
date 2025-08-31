# Infrastructure as Code for GitOps Development Workflows with Cloud Workstations and Deploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "GitOps Development Workflows with Cloud Workstations and Deploy".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Appropriate Google Cloud permissions for resource creation:
  - Project Editor or custom role with permissions for:
    - Container Engine Admin
    - Cloud Build Editor  
    - Source Repository Administrator
    - Artifact Registry Administrator
    - Cloud Workstations Admin
    - Cloud Deploy Admin
    - Service Usage Admin
- Docker installed for local development and testing
- kubectl installed for Kubernetes cluster management
- Git installed for repository operations
- Estimated cost: $50-100 for running this infrastructure (includes GKE clusters, workstations, and build minutes)

> **Note**: This infrastructure creates multiple Google Cloud resources including GKE clusters and Cloud Workstations. Monitor your usage to control costs and clean up resources when finished.

## Quick Start

### Using Infrastructure Manager

```bash
# Set required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/gitops-deployment \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo=https://source.developers.google.com/p/${PROJECT_ID}/r/infrastructure-repo \
    --git-source-directory=infrastructure-manager/
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Set required variables
export TF_VAR_project_id="your-project-id"
export TF_VAR_region="us-central1"

# Review the deployment plan
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

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh

# Access Cloud Workstation
gcloud workstations start dev-workstation \
    --config=dev-config-$(openssl rand -hex 3) \
    --cluster=dev-config-$(openssl rand -hex 3)-cluster \
    --cluster-region=${REGION} \
    --region=${REGION}
```

## Architecture Overview

This infrastructure deploys:

- **GKE Autopilot Clusters**: Staging and production Kubernetes clusters with automatic scaling and security hardening
- **Cloud Workstations**: Secure, browser-accessible development environments with pre-installed tools
- **Cloud Source Repositories**: Git repositories for application code and environment configurations
- **Artifact Registry**: Container image storage with vulnerability scanning
- **Cloud Build**: CI/CD pipelines with automated triggers
- **Cloud Deploy**: Progressive delivery pipelines with approval gates

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Google Cloud region"
    type: string
    default: "us-central1"
  machine_type:
    description: "Workstation machine type"
    type: string
    default: "e2-standard-4"
  disk_size:
    description: "Workstation persistent disk size (GB)"
    type: number
    default: 100
```

### Terraform Variables

Edit `terraform/variables.tf` or use `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Workstation configuration
workstation_machine_type = "e2-standard-4"
workstation_disk_size    = 100

# Cluster configuration
cluster_node_count = 3
cluster_machine_type = "e2-medium"

# Repository names
app_repo_name = "hello-app"
env_repo_name = "hello-env"
```

### Bash Script Variables

Edit variables at the top of `scripts/deploy.sh`:

```bash
# Default configuration
PROJECT_ID="${PROJECT_ID:-gitops-workflow-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
WORKSTATION_MACHINE_TYPE="${WORKSTATION_MACHINE_TYPE:-e2-standard-4}"
WORKSTATION_DISK_SIZE="${WORKSTATION_DISK_SIZE:-100}"
```

## Validation & Testing

After deployment, validate the infrastructure:

```bash
# Check GKE clusters
gcloud container clusters list

# Verify Cloud Workstations
gcloud workstations list \
    --region=${REGION}

# Test Artifact Registry
gcloud artifacts repositories list \
    --location=${REGION}

# Check Cloud Deploy pipelines
gcloud deploy delivery-pipelines list \
    --region=${REGION}

# Verify Cloud Build triggers
gcloud builds triggers list

# Test source repositories
gcloud source repos list
```

## GitOps Workflow Usage

### Accessing Cloud Workstation

1. Start your workstation:
   ```bash
   gcloud workstations start dev-workstation \
       --config=<CONFIG_NAME> \
       --cluster=<CLUSTER_NAME> \
       --cluster-region=${REGION} \
       --region=${REGION}
   ```

2. Access via browser or local IDE:
   ```bash
   # Get workstation URL
   gcloud workstations describe dev-workstation \
       --config=<CONFIG_NAME> \
       --cluster=<CLUSTER_NAME> \
       --cluster-region=${REGION} \
       --region=${REGION} \
       --format="value(host)"
   ```

### Making Code Changes

1. Clone application repository in workstation:
   ```bash
   gcloud source repos clone <APP_REPO_NAME>
   cd <APP_REPO_NAME>
   ```

2. Make changes and commit:
   ```bash
   # Make your changes
   git add .
   git commit -m "Your commit message"
   git push origin main
   ```

3. Monitor CI/CD pipeline:
   ```bash
   # Watch build progress
   gcloud builds list --ongoing
   
   # Check deployment status
   gcloud deploy releases list \
       --delivery-pipeline=gitops-pipeline \
       --region=${REGION}
   ```

### Promoting to Production

```bash
# Promote release to production
gcloud deploy releases promote \
    --release=<RELEASE_NAME> \
    --delivery-pipeline=gitops-pipeline \
    --region=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/gitops-deployment
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
gcloud container clusters delete <STAGING_CLUSTER> --region=${REGION} --quiet
gcloud container clusters delete <PROD_CLUSTER> --region=${REGION} --quiet

# Delete Cloud Workstations
gcloud workstations delete <WORKSTATION_NAME> \
    --config=<CONFIG_NAME> \
    --cluster=<CLUSTER_NAME> \
    --cluster-region=${REGION} \
    --region=${REGION} --quiet

# Delete workstation configuration and cluster
gcloud workstations configs delete <CONFIG_NAME> \
    --cluster=<CLUSTER_NAME> \
    --cluster-region=${REGION} --quiet

gcloud workstations clusters delete <CLUSTER_NAME> \
    --region=${REGION} --quiet

# Delete other resources
gcloud deploy delivery-pipelines delete gitops-pipeline --region=${REGION} --quiet
gcloud artifacts repositories delete <REPO_NAME> --location=${REGION} --quiet
gcloud source repos delete <APP_REPO> --quiet
gcloud source repos delete <ENV_REPO> --quiet
```

## Troubleshooting

### Common Issues

1. **Permission Errors**:
   ```bash
   # Ensure required APIs are enabled
   gcloud services enable container.googleapis.com \
       cloudbuild.googleapis.com \
       sourcerepo.googleapis.com \
       artifactregistry.googleapis.com \
       workstations.googleapis.com \
       clouddeploy.googleapis.com
   ```

2. **Workstation Access Issues**:
   ```bash
   # Check workstation status
   gcloud workstations describe <WORKSTATION_NAME> \
       --config=<CONFIG_NAME> \
       --cluster=<CLUSTER_NAME> \
       --cluster-region=${REGION} \
       --region=${REGION}
   ```

3. **Build Failures**:
   ```bash
   # Check build logs
   gcloud builds log <BUILD_ID>
   
   # List recent builds
   gcloud builds list --limit=10
   ```

4. **Deployment Issues**:
   ```bash
   # Check deployment status
   gcloud deploy rollouts list \
       --release=<RELEASE_NAME> \
       --delivery-pipeline=gitops-pipeline \
       --region=${REGION}
   ```

### Resource Quotas

Monitor resource usage to avoid quota limitations:

```bash
# Check compute quotas
gcloud compute project-info describe --format="table(quotas.metric,quotas.usage,quotas.limit)"

# Check container quotas
gcloud container clusters describe <CLUSTER_NAME> \
    --region=${REGION} \
    --format="value(currentNodeCount,initialNodeCount)"
```

## Cost Optimization

- Use preemptible instances for development workloads
- Schedule workstation shutdown during off-hours
- Implement cluster autoscaling
- Monitor Artifact Registry storage usage
- Use Cloud Build with efficient caching strategies

## Security Considerations

- All resources use IAM-based access controls
- GKE clusters are configured with Autopilot security defaults
- Workstations provide network isolation and encrypted storage
- Artifact Registry includes vulnerability scanning
- Source repositories use Google Cloud authentication

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation:
   - [Cloud Workstations](https://cloud.google.com/workstations/docs)
   - [Cloud Deploy](https://cloud.google.com/deploy/docs)
   - [GKE Autopilot](https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview)
   - [Cloud Build](https://cloud.google.com/build/docs)
3. Verify resource quotas and permissions
4. Check service status at [Google Cloud Status](https://status.cloud.google.com/)

## Next Steps

After successful deployment, consider implementing:

- Multi-environment promotion workflows
- Canary deployment strategies
- Security scanning integration
- Automated testing pipelines
- Advanced monitoring and alerting