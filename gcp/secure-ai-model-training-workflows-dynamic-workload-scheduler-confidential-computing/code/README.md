# Infrastructure as Code for Secure AI Model Training Workflows with Dynamic Workload Scheduler and Confidential Computing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure AI Model Training Workflows with Dynamic Workload Scheduler and Confidential Computing".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 450.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions:
  - Compute Admin
  - Vertex AI User
  - Cloud KMS Admin
  - Service Account Admin
  - Storage Admin
  - Confidential Computing Admin
- Access to GPU/TPU quota in your target region
- Understanding of enterprise security compliance requirements

> **Warning**: This solution uses premium TPU/GPU resources that can incur significant charges ($150-300 for training workloads). Monitor usage closely and implement cost controls.

## Architecture Overview

This solution deploys:

- **Confidential Computing Environment**: SEV-enabled VMs with GPU acceleration
- **Dynamic Workload Scheduler**: Resource reservations for cost-optimized AI training
- **Vertex AI Integration**: Secure training job orchestration
- **Cloud KMS**: Customer-managed encryption keys for data protection
- **Encrypted Storage**: Cloud Storage with CMEK for training data
- **Monitoring & Compliance**: Attestation services and audit logging

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-ai-training \
    --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
    --git-source-repo="https://source.developers.google.com/p/${PROJECT_ID}/r/secure-ai-training" \
    --git-source-directory="infrastructure-manager" \
    --input-values="project_id=${PROJECT_ID},region=${REGION},zone=${ZONE}"
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="zone=${ZONE}"

# Apply the configuration
terraform apply \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="zone=${ZONE}"
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
```

## Configuration Options

### Core Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region | `us-central1` | Yes |
| `zone` | Google Cloud zone | `us-central1-a` | Yes |
| `service_account_name` | AI training service account name | `ai-training-sa` | No |
| `bucket_name_suffix` | Unique suffix for storage bucket | `random` | No |
| `keyring_name_suffix` | Unique suffix for KMS keyring | `random` | No |

### Advanced Configuration

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `machine_type` | Confidential VM machine type | `a2-highgpu-1g` | No |
| `accelerator_type` | GPU accelerator type | `nvidia-tesla-a100` | No |
| `accelerator_count` | Number of GPU accelerators | `1` | No |
| `boot_disk_size` | Boot disk size in GB | `100` | No |
| `enable_monitoring` | Enable advanced monitoring | `true` | No |
| `key_rotation_period` | KMS key rotation period | `30d` | No |

## Security Features

### Confidential Computing

- **Trusted Execution Environment (TEE)**: All training occurs within hardware-protected environments
- **Memory Encryption**: AMD SEV encryption protects data in memory
- **Attestation**: Cryptographic proof of TEE integrity
- **Isolation**: Protection from privileged access and side-channel attacks

### Data Protection

- **Customer-Managed Encryption Keys (CMEK)**: Full control over encryption keys
- **Automatic Key Rotation**: 30-day rotation for enhanced security
- **Encrypted Storage**: All training data encrypted at rest
- **Secure Key Access**: Fine-grained IAM controls for key usage

### Compliance & Auditing

- **Cloud Audit Logs**: Comprehensive activity logging
- **Security Monitoring**: Real-time attestation failure detection
- **Access Controls**: Least privilege IAM implementation
- **Compliance Reports**: Automated compliance validation

## Cost Optimization

### Dynamic Workload Scheduler Benefits

- **Flex Start Mode**: Up to 70% cost reduction on GPU resources
- **Calendar Mode**: Predictable capacity planning
- **Resource Optimization**: Intelligent allocation across TPU/GPU fleets
- **Automatic Scaling**: Dynamic resource adjustment based on demand

### Cost Management Recommendations

1. **Set Budget Alerts**: Configure Cloud Billing budgets for training workloads
2. **Monitor Usage**: Use Cloud Monitoring to track resource utilization
3. **Optimize Scheduling**: Use Flex Start mode for non-urgent training jobs
4. **Resource Cleanup**: Implement automatic cleanup policies for temporary resources

## Validation & Testing

### Post-Deployment Verification

1. **Verify Confidential Computing**:
   ```bash
   # Check confidential compute status
   gcloud compute instances describe confidential-training-vm \
       --zone=${ZONE} \
       --format="value(confidentialInstanceConfig.enableConfidentialCompute)"
   ```

2. **Test Encryption Keys**:
   ```bash
   # Verify KMS key accessibility
   gcloud kms keys describe training-data-key \
       --location=${REGION} \
       --keyring=ai-training-keyring \
       --format="value(primary.state)"
   ```

3. **Validate GPU Access**:
   ```bash
   # Check GPU availability in confidential environment
   gcloud compute ssh confidential-training-vm \
       --zone=${ZONE} \
       --command="nvidia-smi --query-gpu=name,memory.total --format=csv"
   ```

### Security Validation

1. **Attestation Verification**: Confirm TEE integrity through attestation services
2. **Encryption Validation**: Verify all data is encrypted with CMEK
3. **Access Control Testing**: Validate IAM permissions and service account access
4. **Audit Log Review**: Check that all activities are properly logged

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/secure-ai-training
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy the infrastructure
terraform destroy \
    -var="project_id=${PROJECT_ID}" \
    -var="region=${REGION}" \
    -var="zone=${ZONE}"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

- Confidential Computing VMs
- GPU reservations
- KMS keys (scheduled for destruction)
- Encrypted storage buckets
- Service accounts
- Monitoring policies

## Troubleshooting

### Common Issues

1. **GPU Quota Exceeded**:
   - Request increased GPU quota in target region
   - Consider alternative regions with available capacity

2. **Confidential Computing Not Available**:
   - Verify region supports confidential computing
   - Check that SEV is enabled in project settings

3. **KMS Permission Errors**:
   - Ensure service account has `cloudkms.cryptoKeyEncrypterDecrypter` role
   - Verify KMS API is enabled

4. **Training Job Failures**:
   - Check Vertex AI logs for detailed error messages
   - Verify training data accessibility from confidential environment

### Performance Optimization

1. **Memory Optimization**: Adjust VM memory for large model training
2. **Storage Performance**: Use SSD persistent disks for faster I/O
3. **Network Optimization**: Configure VPC for optimal data transfer
4. **GPU Utilization**: Monitor GPU utilization and adjust batch sizes

## Support Resources

- [Google Cloud Confidential Computing Documentation](https://cloud.google.com/confidential-computing/docs)
- [Dynamic Workload Scheduler Guide](https://cloud.google.com/ai-hypercomputer/docs)
- [Vertex AI Custom Training Documentation](https://cloud.google.com/vertex-ai/docs/training/custom-training)
- [Cloud KMS Best Practices](https://cloud.google.com/kms/docs/best-practices)
- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)

## Advanced Features

### Multi-Region Deployment

Extend the solution across multiple regions for enhanced availability and compliance:

```bash
# Deploy additional regions
terraform apply -var="region=europe-west1" -target=module.europe_deployment
terraform apply -var="region=asia-northeast1" -target=module.asia_deployment
```

### Custom Training Images

Build custom container images with your ML frameworks:

```bash
# Build and deploy custom training image
gcloud builds submit --tag gcr.io/${PROJECT_ID}/secure-training:latest ./training-image/
```

### Federated Learning Setup

Configure multi-party federated learning with confidential computing:

```bash
# Deploy federated learning coordinator
terraform apply -var="enable_federated_learning=true"
```

## Compliance Certifications

This solution supports compliance with:

- **SOC 2 Type II**: Through Google Cloud's SOC 2 certification
- **ISO 27001**: Via Google Cloud's ISO 27001 compliance
- **HIPAA**: Confidential computing meets HIPAA security requirements
- **GDPR**: Data protection through encryption and access controls
- **FedRAMP**: Available in FedRAMP authorized regions

For specific compliance requirements, consult with Google Cloud compliance teams and your security organization.