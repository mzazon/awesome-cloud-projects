# Infrastructure as Code for Software Supply Chain Security with Binary Authorization and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Software Supply Chain Security with Binary Authorization and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Required API access and appropriate IAM permissions:
  - Binary Authorization API
  - Cloud Build API
  - Cloud KMS API
  - Artifact Registry API
  - Container Analysis API
  - Google Kubernetes Engine API
- Basic understanding of container security and CI/CD pipelines
- Estimated cost: $10-15 for Cloud Build, storage, and KMS operations

## Quick Start

### Using Infrastructure Manager
```bash
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/binauthz-security \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo=https://github.com/your-org/your-repo.git \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main \
    --input-values=project_id=PROJECT_ID,region=REGION

# Check deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/binauthz-security
```

### Using Terraform
```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=PROJECT_ID" -var="region=REGION"

# Apply the infrastructure
terraform apply -var="project_id=PROJECT_ID" -var="region=REGION"

# View outputs
terraform output
```

### Using Bash Scripts
```bash
# Set required environment variables
export PROJECT_ID=your-project-id
export REGION=us-central1

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the script prompts and verify deployment
```

## Architecture Overview

This infrastructure creates a comprehensive software supply chain security solution including:

- **Artifact Registry**: Secure container image repository with vulnerability scanning
- **Cloud KMS**: Cryptographic key management for attestation signing
- **Binary Authorization**: Policy enforcement service with attestor configuration
- **Google Kubernetes Engine**: Container orchestration with Binary Authorization enabled
- **Cloud Build**: CI/CD pipeline with security scanning and attestation generation
- **IAM Configuration**: Least privilege access controls for all components

## Configuration Options

### Infrastructure Manager Variables
- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `zone`: Compute zone for GKE cluster (default: us-central1-a)
- `cluster_name`: GKE cluster name (default: secure-cluster)
- `enable_vulnerability_scanning`: Enable Artifact Registry vulnerability scanning (default: true)

### Terraform Variables
- `project_id`: Google Cloud project ID (required)
- `region`: Primary deployment region (default: us-central1)
- `zone`: Compute zone for GKE cluster (default: us-central1-a)
- `cluster_name`: GKE cluster name (default: secure-cluster)
- `repository_name`: Artifact Registry repository name (default: secure-images)
- `attestor_name`: Binary Authorization attestor name (auto-generated with suffix)
- `keyring_name`: Cloud KMS keyring name (auto-generated with suffix)
- `key_name`: Cloud KMS key name (auto-generated with suffix)

### Script Environment Variables
Set these variables before running deployment scripts:
```bash
export PROJECT_ID=your-project-id
export REGION=us-central1
export ZONE=us-central1-a
export CLUSTER_NAME=secure-cluster
export REPO_NAME=secure-images
```

## Security Features

### Binary Authorization Policy
- Enforces cryptographic attestation verification for all deployments
- Blocks unauthorized container images at runtime
- Allows Google-managed base images for system components
- Provides comprehensive audit logging

### Cloud KMS Integration
- Hardware security module (HSM) backed key management
- Asymmetric RSA signing keys for attestation verification
- Automatic key rotation capabilities
- Fine-grained IAM access controls

### Vulnerability Scanning
- Automated container image vulnerability analysis
- Integration with Container Analysis API
- Continuous monitoring of image security status
- Policy enforcement based on vulnerability severity

## Post-Deployment Steps

After infrastructure deployment, complete these steps to activate the security pipeline:

1. **Configure Docker Authentication**:
   ```bash
   gcloud auth configure-docker ${REGION}-docker.pkg.dev
   ```

2. **Create Sample Application** (optional):
   ```bash
   # The infrastructure creates the foundation
   # Use the recipe steps to create and deploy applications
   ```

3. **Verify Policy Enforcement**:
   ```bash
   # Check Binary Authorization policy
   gcloud container binauthz policy export
   
   # Verify attestor configuration
   gcloud container binauthz attestors list
   ```

## Monitoring and Validation

### Check Infrastructure Status
```bash
# Verify Artifact Registry
gcloud artifacts repositories list --location=${REGION}

# Check KMS keyring and keys
gcloud kms keyrings list --location=${REGION}
gcloud kms keys list --keyring=KEYRING_NAME --location=${REGION}

# Verify GKE cluster
gcloud container clusters list

# Check Binary Authorization configuration
gcloud container binauthz policy export
gcloud container binauthz attestors list
```

### Test Security Enforcement
```bash
# Attempt to deploy unauthorized image (should fail)
kubectl create deployment test-unauthorized --image=nginx:latest

# Check for policy violation events
kubectl get events --sort-by=.metadata.creationTimestamp
```

## Cleanup

### Using Infrastructure Manager
```bash
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/binauthz-security
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_id=PROJECT_ID" -var="region=REGION"
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

**Note**: Cloud KMS keys have a mandatory retention period and cannot be immediately deleted. The cleanup process will disable keys and schedule them for deletion after the retention period expires.

## Customization

### Extending the Solution
- **Multi-Stage Attestation**: Configure multiple attestors for different pipeline stages
- **Custom Policies**: Implement more granular Binary Authorization policies
- **Cross-Project Deployment**: Adapt for multi-project architectures
- **Advanced Monitoring**: Add Cloud Monitoring dashboards and alerts

### Security Hardening
- **Private GKE Cluster**: Enable private cluster configuration
- **VPC-Native Networking**: Configure advanced networking security
- **Workload Identity**: Implement fine-grained pod-level authentication
- **Pod Security Standards**: Apply Kubernetes security policies

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in the target project
2. **Insufficient Permissions**: Verify the deployment service account has necessary IAM roles
3. **Resource Quotas**: Check project quotas for GKE, Cloud Build, and KMS resources
4. **Region Availability**: Confirm all services are available in the selected region

### Debug Commands
```bash
# Check API enablement
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy PROJECT_ID

# Check resource quotas
gcloud compute project-info describe --project=PROJECT_ID

# View Cloud Build logs
gcloud builds list --limit=10
```

## Cost Considerations

### Resource Costs
- **GKE Cluster**: ~$70/month for e2-medium nodes (1-3 nodes)
- **Cloud Build**: $0.003/build-minute after free tier
- **Artifact Registry**: $0.10/GB storage + network egress
- **Cloud KMS**: $0.06/key/month + $0.03/10k operations
- **Binary Authorization**: No additional charges

### Cost Optimization
- Use preemptible GKE nodes for development environments
- Implement image cleanup policies in Artifact Registry
- Monitor Cloud Build usage and optimize build times
- Use regional persistent disks for cost efficiency

## Support

For issues with this infrastructure code:
1. Refer to the original recipe documentation
2. Check Google Cloud provider documentation
3. Review Terraform Google Cloud provider docs
4. Consult Google Cloud support for service-specific issues

## Additional Resources

- [Binary Authorization Documentation](https://cloud.google.com/binary-authorization/docs)
- [Cloud Build Security Guide](https://cloud.google.com/build/docs/securing-builds)
- [Artifact Registry Security](https://cloud.google.com/artifact-registry/docs/analysis)
- [GKE Security Best Practices](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster)
- [Cloud KMS Key Management](https://cloud.google.com/kms/docs/key-management)