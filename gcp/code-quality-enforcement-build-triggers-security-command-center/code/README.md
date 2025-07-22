# Infrastructure as Code for Code Quality Enforcement with Cloud Build Triggers and Security Command Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Code Quality Enforcement with Cloud Build Triggers and Security Command Center".

## Overview

This solution implements an intelligent code quality enforcement pipeline that combines Cloud Build Triggers for automated CI/CD, Binary Authorization for policy enforcement, and Security Command Center for centralized security monitoring. The infrastructure automatically triggers quality checks on code commits, enforces security policies at deployment time, and provides real-time visibility into compliance status across all environments.

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Components

The infrastructure deploys the following components:

- Cloud Source Repository for secure Git hosting
- Cloud Build triggers for automated CI/CD pipeline
- Binary Authorization policies and attestors for deployment security
- GKE cluster with security hardening and Binary Authorization integration
- Security Command Center configuration for compliance monitoring
- Cloud KMS key management for attestation signing
- IAM service accounts with least privilege permissions
- Container Registry for secure image storage

## Prerequisites

### Required Tools

- Google Cloud SDK (`gcloud`) installed and configured
- `kubectl` command-line tool for Kubernetes management
- `terraform` (version >= 1.0) for Terraform deployments
- Appropriate Google Cloud project with billing enabled

### Required Permissions

Your Google Cloud account must have the following IAM roles:

- `roles/owner` or equivalent permissions for:
  - Cloud Build API management
  - Binary Authorization configuration
  - GKE cluster creation and management
  - Security Command Center access
  - Cloud KMS key management
  - Service Account creation and management

### Enabled APIs

The following APIs must be enabled in your Google Cloud project:

```bash
gcloud services enable cloudbuild.googleapis.com
gcloud services enable sourcerepo.googleapis.com
gcloud services enable binaryauthorization.googleapis.com
gcloud services enable securitycenter.googleapis.com
gcloud services enable container.googleapis.com
gcloud services enable containeranalysis.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable cloudkms.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/code-quality-enforcement \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="."

# Monitor deployment progress
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/code-quality-enforcement
```

### Using Terraform

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

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
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
gcloud builds list --limit=5
gcloud container clusters list
```

## Configuration Options

### Infrastructure Manager Variables

Edit the `variables` section in `infrastructure-manager/main.yaml`:

```yaml
variables:
  project_id:
    description: "Google Cloud Project ID"
    type: string
  region:
    description: "Google Cloud region"
    type: string
    default: "us-central1"
  cluster_name:
    description: "GKE cluster name"
    type: string
    default: "quality-enforcement-cluster"
```

### Terraform Variables

Create a `terraform.tfvars` file in the `terraform/` directory:

```hcl
project_id   = "your-project-id"
region       = "us-central1"
zone         = "us-central1-a"
cluster_name = "quality-enforcement-cluster"

# Optional: Customize resource names
repo_name     = "secure-app-repo"
trigger_name  = "quality-enforcement-trigger"
attestor_name = "quality-attestor"

# Optional: Security settings
enable_binary_authorization = true
enable_shielded_nodes      = true
enable_network_policy      = true
```

### Script Environment Variables

For bash script deployment, set these environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export CLUSTER_NAME="quality-enforcement-cluster"
export REPO_NAME="secure-app-repo"
export TRIGGER_NAME="quality-enforcement-trigger"
export ATTESTOR_NAME="quality-attestor"
```

## Post-Deployment Setup

After infrastructure deployment, complete these manual steps:

### 1. Clone and Configure Source Repository

```bash
# Get repository clone URL from outputs
REPO_URL=$(terraform output -raw repository_clone_url)

# Clone repository
gcloud source repos clone ${REPO_NAME} --project=${PROJECT_ID}

# Navigate to repository and add sample application code
cd ${REPO_NAME}

# Copy sample application from recipe documentation
# (Follow steps 2-3 from the original recipe)
```

### 2. Trigger Initial Build

```bash
# Commit and push sample application
git add .
git commit -m "Initial commit: Secure application with quality enforcement"
git push origin main

# Monitor build progress
gcloud builds list --ongoing
```

### 3. Verify Security Command Center Integration

```bash
# Check Security Command Center findings
gcloud scc findings list --source=${SCC_SOURCE} \
    --format="table(name,category,state,createTime)"
```

## Validation & Testing

### Verify Infrastructure Deployment

```bash
# Check Cloud Build trigger
gcloud builds triggers list --format="table(name,status,github.name)"

# Verify GKE cluster
gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE}

# Check Binary Authorization policy
gcloud container binauthz policy get

# Verify attestor configuration
gcloud container binauthz attestors list
```

### Test Security Pipeline

```bash
# Deploy test application (should succeed with valid attestation)
kubectl apply -f k8s-deployment.yaml

# Attempt deployment without attestation (should fail)
kubectl run test-pod --image=nginx:latest --dry-run=server
```

### Monitor Security Findings

```bash
# View container vulnerability scan results
gcloud container images scan gcr.io/${PROJECT_ID}/secure-app:latest

# Check Security Command Center dashboard
open "https://console.cloud.google.com/security/command-center"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/code-quality-enforcement

# Verify cleanup
gcloud infra-manager deployments list
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource cleanup
gcloud container clusters list
gcloud builds triggers list
gcloud source repos list
```

### Manual Cleanup Steps

Some resources may require manual cleanup:

```bash
# Reset Binary Authorization policy to default
gcloud container binauthz policy import /dev/stdin << 'EOF'
defaultAdmissionRule:
  evaluationMode: ALWAYS_ALLOW
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
globalPolicyEvaluationMode: ENABLE
EOF

# Delete KMS key ring (if desired)
gcloud kms keyrings list --location=global

# Clean up Security Command Center custom sources
gcloud scc sources list
```

## Security Considerations

### IAM and Access Control

- Service accounts follow principle of least privilege
- Binary Authorization policies enforce container image security
- Cloud KMS provides secure key management for attestation signing
- GKE cluster uses Workload Identity for secure pod authentication

### Network Security

- GKE cluster enables network policies for micro-segmentation
- Shielded nodes provide runtime security monitoring
- Private cluster configuration available via variable customization

### Compliance and Monitoring

- Security Command Center provides centralized security monitoring
- Container vulnerability scanning automatically enabled
- Audit logging captures all security-related events
- Binary Authorization provides deployment-time compliance enforcement

## Troubleshooting

### Common Issues

1. **Build Pipeline Failures**
   ```bash
   # Check build logs
   gcloud builds log ${BUILD_ID}
   
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Binary Authorization Deployment Blocks**
   ```bash
   # Check attestation status
   gcloud container binauthz attestations list --attestor=${ATTESTOR_NAME}
   
   # Verify policy configuration
   gcloud container binauthz policy get
   ```

3. **GKE Cluster Access Issues**
   ```bash
   # Get cluster credentials
   gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${ZONE}
   
   # Check cluster status
   kubectl cluster-info
   ```

### Debug Commands

```bash
# Enable detailed logging
export CLOUDSDK_CORE_LOG_LEVEL=DEBUG

# Check API enablement
gcloud services list --enabled

# Verify quota limits
gcloud compute project-info describe --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

## Cost Optimization

### Resource Sizing

- GKE cluster defaults to 3 nodes for high availability
- Adjust node pool size based on workload requirements
- Use preemptible instances for development environments

### Monitoring Costs

```bash
# Check current usage and billing
gcloud billing budgets list
gcloud compute instances list --format="table(name,zone,machineType,status,scheduling.preemptible)"
```

## Support and Documentation

### Additional Resources

- [Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Binary Authorization Guide](https://cloud.google.com/binary-authorization/docs)
- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)
- [GKE Security Best Practices](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster)
- [Container Analysis Documentation](https://cloud.google.com/container-analysis/docs)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation links
3. Examine the original recipe documentation for context
4. Consult Google Cloud support for platform-specific issues

## License

This infrastructure code is provided as-is for educational and implementation purposes. Review and modify according to your organization's security and compliance requirements.