# Infrastructure as Code for Code Quality Gates with Cloud Build Triggers and Cloud Deploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Quality Gates with Cloud Build Triggers and Cloud Deploy".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (version 400.0.0 or later)
- Active Google Cloud project with billing enabled
- Required APIs enabled (automatically handled by IaC implementations):
  - Cloud Build API
  - Cloud Deploy API
  - Cloud Source Repositories API
  - Binary Authorization API
  - Google Kubernetes Engine API
  - Artifact Registry API
  - Cloud Resource Manager API
- Git command line tool installed
- kubectl installed for Kubernetes cluster management
- Appropriate IAM permissions:
  - Cloud Build Editor
  - Cloud Deploy Developer
  - Kubernetes Engine Admin
  - Source Repository Administrator
  - Binary Authorization Attestor Viewer
  - Service Account User

## Architecture Overview

This solution implements an automated CI/CD pipeline with comprehensive code quality gates:

- **Source Control**: Cloud Source Repositories for secure Git hosting
- **CI/CD Pipeline**: Cloud Build Triggers with automated testing, linting, and security scanning
- **Progressive Deployment**: Cloud Deploy with canary deployments and approval gates
- **Container Security**: Binary Authorization for verified container deployments
- **Target Infrastructure**: Google Kubernetes Engine cluster with multi-environment support

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/code-quality-pipeline \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --local-source="." \
    --inputs-file="terraform.tfvars"

# Monitor deployment
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/code-quality-pipeline
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Configuration Options

### Infrastructure Manager Variables

Key configuration options in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
cluster_name_suffix = "unique-suffix"
enable_binary_auth = true
node_count = 3
machine_type = "e2-standard-2"
```

### Terraform Variables

Customize deployment by editing `terraform.tfvars.example`:

```hcl
# Project Configuration
project_id = "your-gcp-project-id"
region = "us-central1"
zone = "us-central1-a"

# Cluster Configuration
cluster_name = "quality-gates-cluster"
node_count = 3
machine_type = "e2-standard-2"
disk_size_gb = 30

# Pipeline Configuration
repository_name = "sample-app"
pipeline_name = "quality-pipeline"
trigger_branch = "main"

# Security Configuration
enable_network_policy = true
enable_shielded_nodes = true
enable_workload_identity = true
```

### Environment Variables for Scripts

Set these environment variables before running bash scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER_NAME="quality-gates-cluster"
export REPOSITORY_NAME="sample-app"
export PIPELINE_NAME="quality-pipeline"
```

## Deployment Process

### Infrastructure Manager Deployment

1. **Prepare Configuration**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Enable Required APIs**:
   ```bash
   gcloud services enable config.googleapis.com
   gcloud services enable cloudbuild.googleapis.com
   gcloud services enable container.googleapis.com
   ```

3. **Deploy Resources**:
   ```bash
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/code-quality-pipeline \
       --service-account=${PROJECT_NUMBER}-compute@developer.gserviceaccount.com \
       --local-source="." \
       --inputs-file="terraform.tfvars"
   ```

### Terraform Deployment

1. **Initialize and Plan**:
   ```bash
   cd terraform/
   terraform init
   terraform plan -var-file="terraform.tfvars"
   ```

2. **Apply Configuration**:
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```

3. **Verify Deployment**:
   ```bash
   terraform output cluster_endpoint
   terraform output repository_clone_url
   ```

### Script-based Deployment

1. **Set Environment Variables**:
   ```bash
   source scripts/env.sh
   ```

2. **Deploy Infrastructure**:
   ```bash
   ./scripts/deploy.sh
   ```

3. **Configure Pipeline**:
   ```bash
   ./scripts/configure-pipeline.sh
   ```

## Post-Deployment Configuration

### Setting Up the Sample Application

After infrastructure deployment, set up the sample application:

1. **Clone the Repository**:
   ```bash
   gcloud source repos clone ${REPOSITORY_NAME} --project=${PROJECT_ID}
   cd ${REPOSITORY_NAME}
   ```

2. **Add Sample Application Files**:
   ```bash
   # Copy application files from the recipe
   cp -r ../sample-app/* .
   git add .
   git commit -m "Add sample application with quality gates"
   git push origin main
   ```

3. **Monitor Build Trigger**:
   ```bash
   gcloud builds list --filter="source.repoSource.repoName:${REPOSITORY_NAME}"
   ```

### Configuring Cloud Deploy Pipeline

1. **Verify Pipeline Creation**:
   ```bash
   gcloud deploy delivery-pipelines list --region=${REGION}
   ```

2. **Create First Release**:
   ```bash
   gcloud deploy releases create release-001 \
       --delivery-pipeline=${PIPELINE_NAME} \
       --region=${REGION} \
       --source=.
   ```

3. **Monitor Deployment Progress**:
   ```bash
   gcloud deploy rollouts list \
       --delivery-pipeline=${PIPELINE_NAME} \
       --region=${REGION}
   ```

## Validation and Testing

### Verify Infrastructure Components

1. **Check GKE Cluster**:
   ```bash
   gcloud container clusters list
   gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}
   kubectl get nodes
   ```

2. **Verify Source Repository**:
   ```bash
   gcloud source repos list
   ```

3. **Check Build Triggers**:
   ```bash
   gcloud builds triggers list
   ```

4. **Validate Cloud Deploy Pipeline**:
   ```bash
   gcloud deploy delivery-pipelines describe ${PIPELINE_NAME} --region=${REGION}
   ```

### Test Quality Gates

1. **Trigger Build Pipeline**:
   ```bash
   # Make a code change and push
   echo "console.log('Testing quality gates');" >> app.js
   git add app.js
   git commit -m "Test quality gates"
   git push origin main
   ```

2. **Monitor Build Progress**:
   ```bash
   gcloud builds list --limit=1 --format="table(id,status,createTime)"
   ```

3. **Check Quality Gate Results**:
   ```bash
   BUILD_ID=$(gcloud builds list --limit=1 --format="value(id)")
   gcloud builds log ${BUILD_ID}
   ```

### Verify Security Configuration

1. **Check Binary Authorization Policy**:
   ```bash
   gcloud container binauthz policy export
   ```

2. **Verify Container Scanning**:
   ```bash
   gcloud container images scan-results list \
       --repository=gcr.io/${PROJECT_ID}/sample-app
   ```

## Troubleshooting

### Common Issues

1. **API Not Enabled Error**:
   ```bash
   gcloud services enable [API_NAME]
   ```

2. **Insufficient Permissions**:
   ```bash
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/[REQUIRED_ROLE]"
   ```

3. **Build Trigger Not Firing**:
   ```bash
   # Check trigger configuration
   gcloud builds triggers describe ${TRIGGER_ID}
   
   # Manually run trigger
   gcloud builds triggers run ${TRIGGER_ID} --branch=main
   ```

4. **Cloud Deploy Permission Issues**:
   ```bash
   # Check service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} \
       --flatten="bindings[].members" \
       --filter="bindings.members:*cloudbuild*"
   ```

### Debugging Commands

1. **Check Resource Status**:
   ```bash
   # GKE cluster status
   gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE}
   
   # Build history
   gcloud builds list --filter="source.repoSource.repoName:${REPOSITORY_NAME}"
   
   # Deploy pipeline status
   gcloud deploy delivery-pipelines list --region=${REGION}
   ```

2. **View Logs**:
   ```bash
   # Build logs
   gcloud builds log ${BUILD_ID}
   
   # GKE logs
   kubectl logs -n development -l app=code-quality-app
   ```

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/code-quality-pipeline
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var-file="terraform.tfvars"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)

1. **Delete GKE Cluster**:
   ```bash
   gcloud container clusters delete ${CLUSTER_NAME} --zone=${ZONE} --quiet
   ```

2. **Delete Source Repository**:
   ```bash
   gcloud source repos delete ${REPOSITORY_NAME} --quiet
   ```

3. **Delete Container Images**:
   ```bash
   gcloud container images delete gcr.io/${PROJECT_ID}/sample-app --force-delete-tags --quiet
   ```

4. **Delete Build Triggers**:
   ```bash
   gcloud builds triggers delete ${TRIGGER_ID} --quiet
   ```

5. **Delete Cloud Deploy Pipeline**:
   ```bash
   gcloud deploy delivery-pipelines delete ${PIPELINE_NAME} --region=${REGION} --quiet
   ```

## Cost Optimization

### Resource Sizing Recommendations

- **Development**: Use `e2-micro` or `e2-small` instances (1-2 nodes)
- **Staging**: Use `e2-standard-2` instances (2-3 nodes)
- **Production**: Use `e2-standard-4` or higher based on workload requirements

### Cost Monitoring

```bash
# Check current costs
gcloud billing budgets list

# Monitor resource usage
gcloud compute instances list --format="table(name,machineType,status,zone)"
```

## Security Best Practices

### Network Security

- VPC-native networking enabled
- Network policies configured
- Private cluster with authorized networks

### Container Security

- Binary Authorization enforced
- Container vulnerability scanning enabled
- Workload Identity configured
- Non-root container execution

### Access Control

- Least privilege IAM roles
- Service account impersonation
- Audit logging enabled

## Monitoring and Observability

### Built-in Monitoring

```bash
# View cluster monitoring
gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} \
    --format="value(monitoringService,loggingService)"

# Check build metrics
gcloud builds list --format="table(id,status,duration,createTime)"
```

### Custom Dashboards

Access pre-configured dashboards:
- Cloud Build Pipeline Metrics
- GKE Cluster Health
- Application Performance Monitoring
- Security Scanning Results

## Support and Documentation

- [Google Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Google Cloud Deploy Documentation](https://cloud.google.com/deploy/docs)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Binary Authorization Documentation](https://cloud.google.com/binary-authorization/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable descriptions and defaults
3. Validate with `terraform plan` or Infrastructure Manager preview
4. Update this README with any new configuration options
5. Follow Google Cloud security best practices

## Version History

- **v1.0**: Initial implementation with Cloud Build, Cloud Deploy, and GKE
- **v1.1**: Added Binary Authorization and security scanning
- **v1.2**: Enhanced monitoring and multi-environment support
- **v1.3**: Added Infrastructure Manager support and improved documentation