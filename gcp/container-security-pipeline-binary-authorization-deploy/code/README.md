# Infrastructure as Code for Container Security Pipeline with Binary Authorization and Cloud Deploy

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Security Pipeline with Binary Authorization and Cloud Deploy".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Active Google Cloud project with billing enabled
- Appropriate permissions for:
  - Container Registry/Artifact Registry
  - Google Kubernetes Engine (GKE)
  - Binary Authorization
  - Cloud Deploy
  - Cloud Build
  - Container Analysis API
- Docker installed for local image building (optional)
- kubectl installed for cluster management

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable clouddeploy.googleapis.com \
    config.googleapis.com \
    container.googleapis.com \
    artifactregistry.googleapis.com \
    binaryauthorization.googleapis.com

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply \
    --deployment-id=container-security-pipeline \
    --location=us-central1 \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --gcs-source=gs://your-bucket/infrastructure-manager/ \
    --input-values=project_id=${PROJECT_ID},region=us-central1
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id"

# Note the outputs for verification
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

# Deploy the complete pipeline
./scripts/deploy.sh

# The script will guide you through the deployment process
```

## Architecture Overview

This infrastructure creates a complete container security pipeline with:

- **Artifact Registry**: Secure container image storage with vulnerability scanning
- **Binary Authorization**: Policy-based deployment security
- **GKE Clusters**: Staging and production Kubernetes environments
- **Cloud Deploy**: Automated deployment pipeline with canary strategies
- **Cloud Build**: CI/CD pipeline with attestation generation
- **Container Analysis**: Vulnerability scanning and compliance

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

```yaml
imports:
- path: templates/gke-clusters.yaml
- path: templates/artifact-registry.yaml
- path: templates/binary-authorization.yaml
- path: templates/cloud-deploy.yaml

resources:
- name: container-security-pipeline
  type: templates/main.yaml
  properties:
    project_id: "your-project-id"
    region: "us-central1"
    zone: "us-central1-a"
    cluster_node_count: 3
    machine_type: "e2-standard-2"
    enable_network_policy: true
    enable_binary_authorization: true
```

### Terraform Variables

Create a `terraform.tfvars` file or set variables:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# GKE Configuration
staging_cluster_name = "staging-cluster"
prod_cluster_name    = "prod-cluster"
node_count          = 3
machine_type        = "e2-standard-2"

# Artifact Registry
repository_name = "secure-apps-repo"
repository_format = "DOCKER"

# Binary Authorization
attestor_name = "build-attestor"
note_name     = "build-verification-note"

# Cloud Deploy
pipeline_name = "secure-app-pipeline"
```

### Bash Script Environment Variables

Set these variables before running the deployment script:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER_VERSION="1.28"  # Optional: specific GKE version
export NODE_COUNT="3"           # Optional: number of nodes per cluster
export MACHINE_TYPE="e2-standard-2"  # Optional: machine type
```

## Deployment Process

### Phase 1: Foundation Setup
1. Enable required Google Cloud APIs
2. Create Artifact Registry repository
3. Configure Binary Authorization attestor
4. Set up cryptographic keys for attestation

### Phase 2: Kubernetes Infrastructure
1. Create staging GKE cluster with Binary Authorization
2. Create production GKE cluster with security policies
3. Configure cluster networking and node pools
4. Enable vulnerability scanning

### Phase 3: Security Pipeline
1. Configure Binary Authorization policies
2. Set up attestation requirements
3. Create security scanning workflows
4. Configure policy enforcement rules

### Phase 4: Deployment Pipeline
1. Create Cloud Deploy pipeline
2. Configure canary deployment strategy
3. Set up automated promotion rules
4. Configure rollback mechanisms

## Validation Steps

After deployment, verify the infrastructure:

```bash
# Check GKE clusters
gcloud container clusters list

# Verify Binary Authorization
gcloud container binauthz policy list

# Check Artifact Registry
gcloud artifacts repositories list

# Validate Cloud Deploy pipeline
gcloud deploy delivery-pipelines list --region=${REGION}

# Test attestor configuration
gcloud container binauthz attestors list
```

## Security Considerations

### Binary Authorization Policies
- **Staging**: Configured with DRYRUN mode for testing
- **Production**: Enforced blocking mode for security
- **Attestation**: Required cryptographic signatures for all deployments

### Network Security
- **Private clusters**: Optional configuration for enhanced security
- **Network policies**: Enabled for pod-to-pod communication control
- **Authorized networks**: Configure IP whitelist for API access

### Image Security
- **Vulnerability scanning**: Automatic scanning of all pushed images
- **Policy enforcement**: Block deployment of vulnerable images
- **Attestation verification**: Cryptographic proof of security validation

## Monitoring and Logging

The infrastructure includes monitoring for:
- **Deployment success/failure rates**
- **Security policy violations**
- **Vulnerability scan results**
- **Canary deployment metrics**

Access logs through:
```bash
# View deployment logs
gcloud logging read "resource.type=gke_cluster" --limit=50

# Check Binary Authorization audit logs
gcloud logging read "protoPayload.serviceName=binaryauthorization.googleapis.com"

# Monitor Cloud Deploy operations
gcloud logging read "resource.type=cloud_deploy_pipeline"
```

## Troubleshooting

### Common Issues

1. **Binary Authorization blocks deployment**
   ```bash
   # Check attestation status
   gcloud container binauthz attestations list --attestor=ATTESTOR_NAME
   
   # Verify policy configuration
   gcloud container binauthz policy list
   ```

2. **GKE cluster creation fails**
   ```bash
   # Check quotas
   gcloud compute project-info describe --project=${PROJECT_ID}
   
   # Verify API enablement
   gcloud services list --enabled
   ```

3. **Cloud Deploy pipeline fails**
   ```bash
   # Check pipeline status
   gcloud deploy delivery-pipelines describe PIPELINE_NAME --region=${REGION}
   
   # Review rollout details
   gcloud deploy rollouts list --delivery-pipeline=PIPELINE_NAME --region=${REGION}
   ```

### Debug Commands

```bash
# Enable debug logging
export TF_LOG=DEBUG  # For Terraform
export GOOGLE_LOG_LEVEL=debug  # For Google Cloud operations

# Check resource quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Test cluster connectivity
gcloud container clusters get-credentials CLUSTER_NAME --zone=${ZONE}
kubectl cluster-info
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete container-security-pipeline \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm resource deletion
gcloud container clusters list
gcloud artifacts repositories list
gcloud container binauthz attestors list
```

### Manual Cleanup (if needed)

```bash
# Delete GKE clusters
gcloud container clusters delete staging-cluster --zone=${ZONE} --quiet
gcloud container clusters delete prod-cluster --zone=${ZONE} --quiet

# Remove Artifact Registry
gcloud artifacts repositories delete secure-apps-repo --location=${REGION} --quiet

# Clean up Binary Authorization
gcloud container binauthz attestors delete build-attestor --quiet
gcloud container binauthz policy import /dev/stdin <<< '{"defaultAdmissionRule": {"enforcementMode": "ALWAYS_ALLOW"}}'

# Remove Cloud Deploy pipeline
gcloud deploy delivery-pipelines delete secure-app-pipeline --region=${REGION} --quiet
```

## Cost Optimization

### Resource Sizing
- **GKE clusters**: Use e2-standard-2 for cost-effective testing
- **Node pools**: Configure autoscaling for variable workloads
- **Preemptible nodes**: Consider for non-production workloads

### Monitoring Costs
```bash
# Check current costs
gcloud billing accounts list
gcloud billing projects describe ${PROJECT_ID}

# Set up budget alerts
gcloud beta billing budgets create \
    --billing-account=BILLING_ACCOUNT_ID \
    --display-name="Container Security Pipeline Budget" \
    --budget-amount=100USD
```

## Advanced Configuration

### Multi-Region Setup
Modify the configuration for multi-region deployment:

```yaml
# Infrastructure Manager
regions:
  - us-central1
  - us-east1
  - europe-west1

# Terraform
variable "regions" {
  type    = list(string)
  default = ["us-central1", "us-east1"]
}
```

### Custom Attestation Policies
Create additional attestors for enhanced security:

```bash
# Create security scan attestor
gcloud container binauthz attestors create security-scan-attestor \
    --attestation-authority-note=security-scan-note \
    --attestation-authority-note-project=${PROJECT_ID}

# Create compliance attestor
gcloud container binauthz attestors create compliance-attestor \
    --attestation-authority-note=compliance-note \
    --attestation-authority-note-project=${PROJECT_ID}
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe for architecture details
2. **Google Cloud Documentation**: [Cloud Deploy](https://cloud.google.com/deploy/docs), [Binary Authorization](https://cloud.google.com/binary-authorization/docs)
3. **Terraform Provider**: [Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
4. **Community Support**: [Google Cloud Community](https://cloud.google.com/community)

## Contributing

To contribute improvements to this infrastructure code:

1. Test changes in a development environment
2. Validate against the recipe requirements
3. Ensure compatibility with all deployment methods
4. Update documentation as needed

## License

This infrastructure code is provided as-is under the same license as the recipe collection.