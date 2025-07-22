# Infrastructure as Code for Multi-Environment Software Testing Pipelines with Cloud Code and Cloud Deploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Environment Software Testing Pipelines with Cloud Code and Cloud Deploy".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI v2 installed and configured (or Google Cloud Shell)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Google Kubernetes Engine (GKE) administration
  - Cloud Build and Cloud Deploy management
  - Artifact Registry administration
  - Cloud Monitoring configuration
  - Service account creation and management
- VS Code or IntelliJ IDE for Cloud Code extension (for development workflow)
- Git repository for source code management

## Cost Considerations

Estimated costs for running this infrastructure:
- **GKE Clusters**: $30-50/month for 3 clusters (dev: 2 e2-medium nodes, staging: 2 e2-medium nodes, prod: 3 e2-standard-2 nodes)
- **Cloud Build**: $0.003 per build-minute (first 120 build-minutes per day are free)
- **Artifact Registry**: $0.10/GB per month for storage
- **Cloud Deploy**: No additional charges
- **Cloud Monitoring**: Free tier available, charges apply for custom metrics

> **Cost Optimization Tip**: Consider using GKE Autopilot clusters to reduce costs and management overhead. The clusters will automatically scale to zero when not in use.

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"

# Create a deployment
gcloud infra-manager deployments create multi-env-pipeline \
    --location=${REGION} \
    --service-account=$(gcloud config get-value account) \
    --git-source-repo=https://github.com/your-org/your-repo.git \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=${PROJECT_ID},region=${REGION},zone=${ZONE}

# Monitor deployment progress
gcloud infra-manager deployments describe multi-env-pipeline \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file with your project settings
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
EOF

# Review the deployment plan
terraform plan

# Apply the infrastructure
terraform apply

# Get outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment
gcloud container clusters list --filter="name~'pipeline-'"
gcloud deploy delivery-pipelines list --region=${REGION}
```

## Post-Deployment Setup

After deploying the infrastructure, complete these steps to activate the full pipeline:

### 1. Install Cloud Code IDE Extension

Install the Cloud Code extension in your preferred IDE:
- **VS Code**: Install "Cloud Code" extension from the marketplace
- **IntelliJ**: Install "Cloud Code" plugin from JetBrains marketplace

### 2. Configure Application Source Code

```bash
# Clone or create your application repository
git clone https://github.com/your-org/your-app.git
cd your-app

# Copy sample configuration files from the recipe
cp ../sample-app-config/* .

# Customize skaffold.yaml with your project details
sed -i "s/PROJECT_ID/${PROJECT_ID}/g" skaffold.yaml
sed -i "s/REGION/${REGION}/g" skaffold.yaml
```

### 3. Test the Pipeline

```bash
# Trigger a build and deployment
gcloud builds submit --config=cloudbuild.yaml

# Monitor Cloud Deploy releases
gcloud deploy releases list \
    --delivery-pipeline=pipeline-${RANDOM_SUFFIX} \
    --region=${REGION}

# Check application status in development environment
gcloud container clusters get-credentials pipeline-${RANDOM_SUFFIX}-dev --zone=${ZONE}
kubectl get deployments,services,pods -l app=sample-app
```

## Configuration

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud project ID | Current project | Yes |
| `REGION` | Primary region for resources | `us-central1` | Yes |
| `ZONE` | Zone for GKE clusters | `us-central1-a` | Yes |
| `CLUSTER_PREFIX` | Prefix for cluster names | `pipeline-<random>` | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| `project_id` | Google Cloud project ID | string | n/a | yes |
| `region` | Primary region for resources | string | `us-central1` | no |
| `zone` | Zone for GKE clusters | string | `us-central1-a` | no |
| `cluster_prefix` | Prefix for resource naming | string | `pipeline` | no |
| `node_machine_type_dev` | Machine type for dev/staging nodes | string | `e2-medium` | no |
| `node_machine_type_prod` | Machine type for production nodes | string | `e2-standard-2` | no |
| `enable_network_policy` | Enable network policy on production cluster | bool | `true` | no |

## Pipeline Architecture

The deployed infrastructure creates:

1. **GKE Clusters**: Three separate clusters for dev, staging, and production environments
2. **Artifact Registry**: Container image repository with vulnerability scanning
3. **Cloud Deploy Pipeline**: Progressive delivery pipeline with quality gates
4. **Cloud Build Configuration**: Automated build and test pipeline
5. **Cloud Monitoring**: Dashboard and alerting for pipeline observability
6. **IAM Roles**: Service accounts with appropriate permissions

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check GKE clusters
gcloud container clusters list --format="table(name,status,location,currentNodeCount)"

# Verify Cloud Deploy pipeline
gcloud deploy delivery-pipelines list --region=${REGION}

# Check Artifact Registry
gcloud artifacts repositories list --location=${REGION}

# Validate monitoring dashboard
gcloud monitoring dashboards list --filter="displayName~'Pipeline'"
```

### Test Application Deployment

```bash
# Deploy sample application
cd sample-app/
gcloud builds submit --config=cloudbuild.yaml

# Monitor deployment progression
watch -n 10 'gcloud deploy releases list --delivery-pipeline=pipeline-* --region=${REGION} --limit=1'

# Verify application endpoints
kubectl get services -l app=sample-app --all-namespaces
```

## Customization

### Environment-Specific Configurations

To customize environments, modify the Skaffold profiles in `skaffold.yaml`:

```yaml
profiles:
- name: dev
  patches:
  - op: replace
    path: /spec/replicas
    value: 1
- name: staging
  patches:
  - op: replace
    path: /spec/replicas
    value: 2
- name: prod
  patches:
  - op: replace
    path: /spec/replicas
    value: 3
  - op: add
    path: /spec/template/spec/containers/0/resources
    value:
      requests:
        memory: "128Mi"
        cpu: "100m"
      limits:
        memory: "256Mi"
        cpu: "200m"
```

### Adding Quality Gates

Enhance the Cloud Deploy pipeline with verification jobs:

```yaml
# Add to clouddeploy/pipeline.yaml
serialPipeline:
  stages:
  - targetId: dev
    profiles: [dev]
    strategy:
      standard:
        verify: true
        predeploy:
          actions: ["run-unit-tests"]
        postdeploy:
          actions: ["run-integration-tests"]
```

### Custom Monitoring

Add custom metrics and alerts by modifying the monitoring configuration:

```bash
# Create custom alert policy
gcloud alpha monitoring policies create --policy-from-file=custom-alerts.yaml
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete multi-env-pipeline \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up local state (optional)
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud container clusters list --filter="name~'pipeline-'"
gcloud deploy delivery-pipelines list --region=${REGION}
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure your service account has the required IAM roles
2. **Resource Quotas**: Check GKE and Compute Engine quotas in your project
3. **API Not Enabled**: Verify all required APIs are enabled
4. **Network Connectivity**: Ensure proper firewall rules for GKE clusters

### Debug Commands

```bash
# Check Cloud Build logs
gcloud builds list --limit=10
gcloud builds log BUILD_ID

# Verify Cloud Deploy status
gcloud deploy releases describe RELEASE_NAME \
    --delivery-pipeline=PIPELINE_NAME \
    --region=${REGION}

# Debug GKE cluster issues
gcloud container clusters describe CLUSTER_NAME --zone=${ZONE}
kubectl get events --sort-by=.metadata.creationTimestamp
```

### Support Resources

- [Google Cloud Deploy Documentation](https://cloud.google.com/deploy/docs)
- [GKE Troubleshooting Guide](https://cloud.google.com/kubernetes-engine/docs/troubleshooting)
- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Cloud Code Documentation](https://cloud.google.com/code/docs)

## Best Practices

1. **Security**: Use workload identity for secure pod-to-service authentication
2. **Cost Optimization**: Implement cluster autoscaling and use preemptible nodes for development
3. **Monitoring**: Set up comprehensive alerting for pipeline failures and performance issues
4. **Backup**: Regularly backup cluster configurations and persistent volumes
5. **Updates**: Keep GKE clusters and node pools updated with automatic upgrades enabled

## Contributing

To extend or modify this infrastructure:

1. Fork the repository
2. Create a feature branch
3. Test changes in a development project
4. Submit a pull request with detailed description

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's official documentation.