# Infrastructure as Code for Secure Traffic Processing with Service Extensions and Confidential Computing

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Secure Traffic Processing with Service Extensions and Confidential Computing".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### Google Cloud Setup
- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Compute Engine (create/manage VMs, instance groups, health checks)
  - Cloud KMS (create/manage key rings and keys)
  - Cloud Storage (create/manage buckets)
  - Network Services (create/manage load balancers, Service Extensions)
  - IAM (create/manage service accounts and policy bindings)

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager API enabled
- `gcloud infra-manager` commands available

#### Terraform
- Terraform >= 1.0 installed
- Google Cloud provider >= 4.0
- Service Account with appropriate permissions or Application Default Credentials configured

#### Bash Scripts
- `bash` shell (version 4.0+)
- `jq` for JSON processing
- `openssl` for generating random values

### Estimated Costs
- Confidential VM (n2d-standard-4): ~$120-150/month
- Application Load Balancer: ~$18-25/month
- Cloud KMS operations: ~$1-3/month
- Cloud Storage: ~$20-30/month (depending on usage)

> **Note**: Confidential Computing requires specific machine types (N2D) and is available in select regions. Verify availability in your target region before deployment.

## Quick Start

### Using Infrastructure Manager

```bash
# Enable required APIs
gcloud services enable inframanager.googleapis.com

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/secure-traffic-processing \
    --service-account=SERVICE_ACCOUNT_EMAIL \
    --git-source-repo=REPO_URL \
    --git-source-directory=infrastructure-manager/ \
    --git-source-ref=main
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
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
./scripts/deploy.sh --status
```

## Configuration

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
substitutions:
  _PROJECT_ID: "your-project-id"
  _REGION: "us-central1"
  _ZONE: "us-central1-a"
  _VM_MACHINE_TYPE: "n2d-standard-4"
  _STORAGE_CLASS: "STANDARD"
```

### Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
vm_machine_type = "n2d-standard-4"
storage_class   = "STANDARD"
enable_deletion_protection = false

# Networking
allowed_source_ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

# Tags for resource organization
labels = {
  environment = "production"
  team        = "security"
  cost-center = "engineering"
}
```

### Bash Script Environment Variables

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export VM_MACHINE_TYPE="n2d-standard-4"
export ENABLE_DELETION_PROTECTION="false"
```

## Architecture Components

The IaC implementations deploy the following resources:

### Core Security Infrastructure
- **Cloud KMS Key Ring**: Centralized cryptographic key management
- **Encryption Keys**: Customer-managed encryption keys (CMEK) for data protection
- **Service Account**: Dedicated identity for Confidential VM with minimal permissions

### Confidential Computing
- **Confidential VM**: N2D instance with AMD SEV-SNP technology
- **Instance Group**: Unmanaged instance group for load balancer integration
- **Health Check**: gRPC health monitoring for traffic processor service

### Network Security
- **Firewall Rules**: Restrictive ingress rules for traffic processor communication
- **Backend Service**: Global backend service for Confidential VM integration
- **Load Balancer**: Application Load Balancer with HTTPS termination

### Storage and Analytics
- **Cloud Storage Bucket**: CMEK-encrypted storage for processed traffic data
- **Lifecycle Policies**: Automated data tiering and retention management

## Validation

After deployment, verify the infrastructure:

### Check Confidential Computing
```bash
# Verify Confidential VM is running with TEE protection
gcloud compute instances describe $(terraform output -raw vm_name) \
    --zone=$(terraform output -raw zone) \
    --format="value(confidentialInstanceConfig)"
```

### Test KMS Encryption
```bash
# Test encryption/decryption functionality
echo "test-data" | gcloud kms encrypt \
    --key=$(terraform output -raw kms_key_name) \
    --keyring=$(terraform output -raw kms_keyring_name) \
    --location=$(terraform output -raw region) \
    --plaintext-file=- \
    --ciphertext-file=/tmp/test.enc

gcloud kms decrypt \
    --key=$(terraform output -raw kms_key_name) \
    --keyring=$(terraform output -raw kms_keyring_name) \
    --location=$(terraform output -raw region) \
    --ciphertext-file=/tmp/test.enc \
    --plaintext-file=-
```

### Verify Load Balancer
```bash
# Check load balancer status
LB_IP=$(terraform output -raw load_balancer_ip)
curl -k -v https://${LB_IP} -H "Host: secure-traffic.example.com" --connect-timeout 10
```

## Cleanup

### Using Infrastructure Manager
```bash
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/secure-traffic-processing
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

> **Warning**: The cleanup process will permanently delete all resources including encrypted data. Ensure you have backups of any important data before proceeding.

## Security Considerations

### Key Management
- KMS keys have a minimum 24-hour deletion protection period
- Consider key rotation policies for long-term deployments
- Monitor key usage through Cloud Audit Logs

### Network Security
- Firewall rules restrict access to Confidential VM processing port
- Load balancer uses HTTPS with TLS termination
- Consider VPC Service Controls for additional network isolation

### Confidential Computing
- Attestation verification ensures code runs in genuine TEE
- Memory encryption protects data during processing
- Secure boot validates VM integrity

### Data Protection
- CMEK encryption for all stored data
- Automatic data lifecycle management
- Comprehensive audit logging

## Troubleshooting

### Common Issues

#### Confidential VM Deployment Failures
```bash
# Check available machine types in region
gcloud compute machine-types list --filter="zone:$ZONE AND name~'n2d.*'"

# Verify Confidential Computing availability
gcloud compute zones describe $ZONE --format="value(availableCpuPlatforms[])"
```

#### KMS Permission Errors
```bash
# Verify service account permissions
gcloud projects get-iam-policy $PROJECT_ID \
    --filter="bindings.members~'serviceAccount:confidential-processor@$PROJECT_ID.iam.gserviceaccount.com'"
```

#### Load Balancer Connectivity Issues
```bash
# Check backend service health
gcloud compute backend-services get-health $(terraform output -raw backend_service_name) --global

# Verify firewall rules
gcloud compute firewall-rules list --filter="name~'.*traffic.*'"
```

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Terraform
export TF_LOG=DEBUG
terraform apply

# Bash scripts
./scripts/deploy.sh --debug
```

## Advanced Configuration

### Multi-Region Deployment

For production environments, consider deploying across multiple regions:

```hcl
# terraform/terraform.tfvars
regions = ["us-central1", "us-east1", "europe-west1"]
enable_cross_region_replication = true
```

### Enhanced Security

Additional security hardening options:

```hcl
# terraform/terraform.tfvars
enable_vpc_service_controls = true
enable_private_google_access = true
enable_binary_authorization = true
kms_key_rotation_period = "90d"
```

### Performance Optimization

For high-throughput workloads:

```hcl
# terraform/terraform.tfvars
vm_machine_type = "n2d-highmem-8"
backend_service_timeout = "30s"
enable_cdn = true
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

The deployment creates monitoring dashboards for:
- Confidential VM health and performance
- KMS key usage and latency
- Load balancer request patterns
- Storage access patterns

### Alerting Policies

Configure alerts for:
- Confidential VM attestation failures
- KMS key access errors
- Load balancer health check failures
- Unusual traffic patterns

### Audit Logging

Enable comprehensive audit logging:
```bash
# View recent KMS operations
gcloud logging read "protoPayload.serviceName=cloudkms.googleapis.com" --limit=50

# Monitor Confidential VM activities
gcloud logging read "resource.type=gce_instance AND resource.labels.instance_name~'confidential-processor.*'" --limit=50
```

## Support and Documentation

### Official Documentation
- [Google Cloud Confidential Computing](https://cloud.google.com/confidential-computing/docs)
- [Service Extensions Overview](https://cloud.google.com/service-extensions/docs/overview)
- [Cloud KMS Documentation](https://cloud.google.com/kms/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Best Practices
- [Confidential Computing Best Practices](https://cloud.google.com/confidential-computing/docs/best-practices)
- [Cloud KMS Best Practices](https://cloud.google.com/kms/docs/key-management-service)
- [Load Balancer Security](https://cloud.google.com/load-balancing/docs/https/security-best-practices)

### Community Resources
- [Google Cloud Architecture Center](https://cloud.google.com/architecture)
- [Terraform Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or create an issue in the repository.