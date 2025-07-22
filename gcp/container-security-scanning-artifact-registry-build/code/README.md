# Infrastructure as Code for Container Security Scanning with Artifact Registry and Cloud Build

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Container Security Scanning with Artifact Registry and Cloud Build".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v450.0.0 or later installed and configured
- Docker installed locally for container image testing
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Artifact Registry management
  - Cloud Build operations
  - GKE cluster management
  - Binary Authorization configuration
  - KMS key management
  - Security Command Center access
- Terraform v1.0+ (if using Terraform deployment)

## Architecture Overview

This solution implements automated container security scanning and policy enforcement using:

- **Artifact Registry**: Container image storage with built-in vulnerability scanning
- **Cloud Build**: CI/CD automation with security integration
- **Binary Authorization**: Deployment policy enforcement
- **Security Command Center**: Centralized security monitoring
- **GKE**: Kubernetes cluster with security controls
- **Cloud KMS**: Cryptographic key management for image signing

## Quick Start

### Using Infrastructure Manager

```bash
# Enable required APIs
gcloud services enable \
    config.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com \
    container.googleapis.com \
    binaryauthorization.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply \
    projects/PROJECT_ID/locations/us-central1/deployments/container-security \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --local-source=infrastructure-manager/
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the complete solution
./scripts/deploy.sh

# Follow the interactive prompts to configure your environment
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export REPO_NAME="secure-app-repo"
export CLUSTER_NAME="security-cluster"
```

### Terraform Variables

The Terraform implementation supports the following variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | GCP region for resources | `us-central1` | No |
| `zone` | GCP zone for GKE cluster | `us-central1-a` | No |
| `repository_name` | Artifact Registry repository name | `secure-app-repo` | No |
| `cluster_name` | GKE cluster name | `security-cluster` | No |
| `node_count` | Number of GKE nodes | `2` | No |
| `machine_type` | GKE node machine type | `e2-medium` | No |
| `disk_size_gb` | GKE node disk size | `30` | No |

Create a `terraform.tfvars` file:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"
```

## Deployment Process

### Infrastructure Manager Deployment

1. **Prepare the deployment configuration**:
   ```bash
   # Update the configuration with your project details
   sed -i 's/PROJECT_ID/your-actual-project-id/g' infrastructure-manager/main.yaml
   ```

2. **Create the deployment**:
   ```bash
   gcloud infra-manager deployments apply \
       projects/your-project-id/locations/us-central1/deployments/container-security \
       --service-account=your-service-account@your-project-id.iam.gserviceaccount.com \
       --local-source=infrastructure-manager/
   ```

3. **Monitor deployment progress**:
   ```bash
   gcloud infra-manager deployments describe \
       projects/your-project-id/locations/us-central1/deployments/container-security
   ```

### Terraform Deployment

1. **Configure authentication**:
   ```bash
   gcloud auth application-default login
   ```

2. **Initialize and deploy**:
   ```bash
   cd terraform/
   terraform init
   terraform plan -var="project_id=your-project-id"
   terraform apply -var="project_id=your-project-id"
   ```

3. **Verify outputs**:
   ```bash
   terraform output
   ```

### Bash Script Deployment

1. **Run the deployment script**:
   ```bash
   ./scripts/deploy.sh
   ```

2. **Follow the interactive prompts** to:
   - Set project ID and region
   - Configure resource names
   - Enable required APIs
   - Deploy all infrastructure components

## Testing the Deployment

### Verify Artifact Registry

```bash
# List repositories
gcloud artifacts repositories list --location=$REGION

# Verify vulnerability scanning is enabled
gcloud artifacts repositories describe $REPO_NAME --location=$REGION
```

### Test Container Scanning

```bash
# Build and push a test image
docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/test-app:latest .
docker push $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/test-app:latest

# Check vulnerability scan results
gcloud artifacts docker images list-vulnerabilities \
    $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/test-app:latest
```

### Verify Binary Authorization

```bash
# Check policy configuration
gcloud container binauthz policy export

# Test deployment to GKE cluster
kubectl create deployment test-app \
    --image=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/test-app:latest
```

### Cloud Build Pipeline Test

```bash
# Trigger a Cloud Build
gcloud builds submit --config=cloudbuild.yaml

# Monitor build progress
gcloud builds list --limit=5
```

## Security Features

### Vulnerability Scanning

- **Automatic scanning**: All pushed images are automatically scanned
- **Continuous monitoring**: Images are rescanned when new vulnerabilities are discovered
- **Policy enforcement**: Deployment blocked for critical vulnerabilities
- **Integration**: Results visible in Security Command Center

### Binary Authorization

- **Cryptographic verification**: Images must be digitally signed
- **Policy enforcement**: Unauthorized images cannot be deployed
- **Attestation**: Security compliance is cryptographically verified
- **Audit logging**: All policy decisions are logged

### Access Controls

- **Service accounts**: Least privilege access for automation
- **IAM policies**: Granular permissions for different roles
- **KMS integration**: Secure key management for signing operations
- **Network security**: Private GKE cluster with authorized networks

## Monitoring and Maintenance

### Security Command Center

Monitor security findings:

```bash
# List vulnerability findings
gcloud scc findings list \
    --organization=$ORGANIZATION_ID \
    --filter="category='VULNERABILITY'"

# Monitor Binary Authorization violations
gcloud logging read \
    'protoPayload.serviceName="binaryauthorization.googleapis.com"'
```

### Build Pipeline Monitoring

```bash
# Monitor Cloud Build history
gcloud builds list --filter="status=FAILURE" --limit=10

# View build logs
gcloud builds log BUILD_ID
```

### Cost Management

```bash
# Monitor Artifact Registry storage costs
gcloud artifacts repositories describe $REPO_NAME \
    --location=$REGION \
    --format="value(sizeBytes)"

# Monitor GKE cluster costs
gcloud container clusters describe $CLUSTER_NAME \
    --zone=$ZONE \
    --format="value(currentNodeCount,currentMasterVersion)"
```

## Troubleshooting

### Common Issues

1. **API not enabled**: Ensure all required APIs are enabled
   ```bash
   gcloud services list --enabled
   ```

2. **Insufficient permissions**: Verify IAM roles
   ```bash
   gcloud projects get-iam-policy $PROJECT_ID
   ```

3. **Binary Authorization blocking deployments**: Check policy and attestations
   ```bash
   gcloud container binauthz policy export
   gcloud container binauthz attestors list
   ```

4. **Vulnerability scan timeout**: Large images may take time to scan
   ```bash
   gcloud artifacts docker images describe IMAGE_URL --show-package-vulnerability
   ```

### Support Resources

- [Google Cloud Build Documentation](https://cloud.google.com/build/docs)
- [Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [Binary Authorization Documentation](https://cloud.google.com/binary-authorization/docs)
- [GKE Security Best Practices](https://cloud.google.com/kubernetes-engine/docs/how-to/hardening-your-cluster)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete \
    projects/your-project-id/locations/us-central1/deployments/container-security
```

### Using Terraform

```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Confirm deletion of all resources when prompted
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud artifacts repositories list --location=$REGION
gcloud container clusters list --zone=$ZONE
gcloud container binauthz attestors list
gcloud kms keyrings list --location=$REGION
```

## Customization

### Extending Security Policies

- Modify Binary Authorization policies for different environments
- Add custom vulnerability severity thresholds
- Implement custom attestation requirements
- Configure environment-specific security controls

### CI/CD Integration

- Integrate with GitHub Actions or GitLab CI
- Add automated testing stages
- Implement progressive deployment strategies
- Configure notification systems for security violations

### Advanced Monitoring

- Set up custom security dashboards
- Configure alerting for policy violations
- Implement automated incident response
- Add compliance reporting workflows

## Cost Optimization

- Use preemptible GKE nodes for development environments
- Implement image lifecycle policies in Artifact Registry
- Configure appropriate resource quotas
- Monitor and optimize container image sizes
- Use regional persistent disks for cost efficiency

## Compliance and Governance

This infrastructure supports various compliance frameworks:

- **SOC 2**: Automated security controls and audit logging
- **PCI DSS**: Secure container deployment and vulnerability management
- **GDPR**: Data encryption and access controls
- **HIPAA**: Secure healthcare data processing (with additional configuration)

## Support

For issues with this infrastructure code, refer to:

1. The original recipe documentation
2. Google Cloud provider documentation
3. Terraform Google Cloud provider documentation
4. Community support forums and GitHub issues

For enterprise support, consider Google Cloud Professional Services or certified partners.