# Infrastructure as Code for Secure Remote Development Access with Cloud Identity-Aware Proxy and Cloud Code

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Remote Development Access with Cloud Identity-Aware Proxy and Cloud Code".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts with IAP configuration

## Prerequisites

- Google Cloud CLI installed and configured
- Appropriate Google Cloud project with billing enabled
- The following APIs enabled:
  - Identity-Aware Proxy API (`iap.googleapis.com`)
  - Compute Engine API (`compute.googleapis.com`)
  - Artifact Registry API (`artifactregistry.googleapis.com`)
  - Cloud Build API (`cloudbuild.googleapis.com`)
  - Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)
- Required IAM permissions:
  - `roles/compute.instanceAdmin`
  - `roles/iap.admin`
  - `roles/artifactregistry.admin`
  - `roles/iam.securityAdmin`
  - `roles/resourcemanager.projectIamAdmin`
- VS Code with Cloud Code extension (for development workflow)
- Estimated cost: $15-25 for development VM and storage during deployment

> **Note**: This implementation creates a zero-trust development environment with identity-based access controls. Review Google Cloud's security best practices before deployment.

## Quick Start

### Using Infrastructure Manager

```bash
# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/secure-dev-environment \
    --config-file=infrastructure-manager/main.yaml \
    --input-values="project_id=PROJECT_ID,region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe projects/PROJECT_ID/locations/REGION/deployments/secure-dev-environment
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=PROJECT_ID" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=PROJECT_ID" -var="region=us-central1"

# Verify deployment
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure with IAP configuration
./scripts/deploy.sh

# Follow OAuth consent screen setup instructions
echo "Complete OAuth consent screen setup in Cloud Console"
echo "Navigate to: https://console.cloud.google.com/apis/credentials/consent"
```

## Architecture Components

This infrastructure creates:

- **Compute Engine VM** without external IP for secure development
- **Cloud Identity-Aware Proxy (IAP)** for zero-trust access control
- **Artifact Registry** repository for secure container storage
- **Firewall rules** allowing IAP access to SSH (35.235.240.0/20)
- **IAM policies** for identity-based access control
- **OAuth 2.0 configuration** for user authentication
- **Audit logging** for security monitoring and compliance
- **Development tools** installation (Docker, Git, Node.js, Python)

## Security Features

- **Zero External IP**: Development VM has no public IP address
- **IAP Authentication**: All access requires Google account authentication
- **Context-Aware Access**: Additional security signals evaluation
- **Container Scanning**: Automatic vulnerability detection in Artifact Registry
- **Audit Logging**: Comprehensive access and activity monitoring
- **Least Privilege IAM**: Minimal required permissions for development tasks

## Post-Deployment Configuration

### 1. Complete OAuth Consent Screen Setup

```bash
# Navigate to OAuth consent screen configuration
open "https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"

# Configure required fields:
# - User Type: Internal (for organization) or External
# - Application name: Secure Development Environment
# - User support email: your-email@domain.com
# - Developer contact information: your-email@domain.com
```

### 2. Configure VS Code Cloud Code Extension

```bash
# Install Cloud Code extension
code --install-extension GoogleCloudTools.cloudcode

# Connect to development environment via IAP tunnel
gcloud compute ssh dev-vm-SUFFIX \
    --zone=${ZONE} \
    --tunnel-through-iap \
    --ssh-flag="-L 8080:localhost:8080"
```

### 3. Verify IAP SSH Access

```bash
# Test secure SSH connection through IAP
gcloud compute ssh dev-vm-SUFFIX \
    --zone=${ZONE} \
    --tunnel-through-iap \
    --command="echo 'IAP SSH connection successful'"
```

## Development Workflow

### Container Development with Artifact Registry

```bash
# Authenticate Docker with Artifact Registry
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Build and push container images
cd secure-app/
docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/secure-dev-repo/app:v1.0 .
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/secure-dev-repo/app:v1.0

# View vulnerability scan results
gcloud artifacts docker images scan ${REGION}-docker.pkg.dev/${PROJECT_ID}/secure-dev-repo/app:v1.0 \
    --location=${REGION}
```

### Remote Development Access

```bash
# Connect to development VM through IAP
gcloud compute ssh dev-vm-SUFFIX \
    --zone=${ZONE} \
    --tunnel-through-iap

# Forward ports for application testing
gcloud compute ssh dev-vm-SUFFIX \
    --zone=${ZONE} \
    --tunnel-through-iap \
    --ssh-flag="-L 8080:localhost:8080"
```

## Monitoring and Compliance

### Access Monitoring

```bash
# View IAP access logs
gcloud logging read 'protoPayload.serviceName="iap.googleapis.com"' \
    --limit=10 \
    --format="table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)"

# Monitor Compute Engine security events
gcloud logging read 'protoPayload.serviceName="compute.googleapis.com" AND protoPayload.methodName="compute.instances.start"' \
    --limit=5
```

### Security Validation

```bash
# Verify VM has no external IP
gcloud compute instances describe dev-vm-SUFFIX \
    --zone=${ZONE} \
    --format="get(networkInterfaces[0].accessConfigs)"

# Check IAM bindings
gcloud compute instances get-iam-policy dev-vm-SUFFIX \
    --zone=${ZONE} \
    --format="table(bindings.members,bindings.role)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/secure-dev-environment

# Verify resources are removed
gcloud compute instances list --filter="name~'dev-vm'"
```

### Using Terraform

```bash
cd terraform/

# Destroy all infrastructure
terraform destroy -var="project_id=PROJECT_ID" -var="region=us-central1"

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Manual verification of resource removal
gcloud compute instances list --filter="name~'dev-vm'"
gcloud artifacts repositories list --location=${REGION}
gcloud compute firewall-rules list --filter="name='allow-iap-ssh'"
```

## Troubleshooting

### Common Issues

1. **OAuth Consent Screen Not Configured**
   - Complete OAuth consent screen setup in Cloud Console
   - Ensure user type (Internal/External) matches organization requirements

2. **IAP Access Denied**
   - Verify user has `roles/iap.tunnelResourceAccessor` role
   - Check that firewall rules allow IAP source ranges (35.235.240.0/20)

3. **Container Push Failures**
   - Confirm Docker authentication: `gcloud auth configure-docker`
   - Verify Artifact Registry permissions: `roles/artifactregistry.writer`

4. **VM Connection Issues**
   - Ensure VM is running: `gcloud compute instances describe VM_NAME`
   - Verify IAP tunnel connectivity and firewall rules

### Support Resources

- [Cloud Identity-Aware Proxy Documentation](https://cloud.google.com/iap/docs)
- [Cloud Code Documentation](https://cloud.google.com/code/docs)
- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Zero Trust on Google Cloud](https://cloud.google.com/security/zero-trust)

## Customization

### Variables Configuration

Key variables that can be customized in each implementation:

- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Compute zone (default: us-central1-a)
- `vm_machine_type`: VM instance type (default: e2-standard-4)
- `boot_disk_size`: VM boot disk size (default: 50GB)
- `repository_name`: Artifact Registry repository name
- `developer_email`: Primary developer email for IAM bindings

### Security Enhancements

Consider these additional security configurations:

- **Context-Aware Access policies** for device compliance
- **VPC Service Controls** for additional data protection
- **Binary Authorization** for container deployment policies
- **Cloud Armor** for additional application protection
- **Cloud KMS** for encryption key management

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud provider documentation
3. Validate IAM permissions and API enablement
4. Review Cloud Logging for detailed error messages
5. Consult Google Cloud support for platform-specific issues

## License

This infrastructure code is provided as part of the cloud recipes collection. Refer to the repository license for usage terms.