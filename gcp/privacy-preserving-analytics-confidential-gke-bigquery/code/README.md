# Infrastructure as Code for Privacy-Preserving Analytics with Confidential GKE and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Privacy-Preserving Analytics with Confidential GKE and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Owner or Editor permissions on the target project
- Terraform installed (version 1.5.0 or later) for Terraform deployment
- kubectl installed for Kubernetes cluster management
- Basic understanding of Kubernetes, BigQuery, and machine learning concepts

## Cost Considerations

This implementation creates premium resources including:
- Confidential GKE nodes with hardware encryption
- BigQuery datasets with customer-managed encryption
- Cloud KMS encryption keys
- Cloud Storage buckets with CMEK encryption
- Vertex AI training jobs

**Estimated cost**: $75-150 for full deployment (monitor usage and clean up promptly after testing)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

1. **Set up environment variables**:
   ```bash
   export PROJECT_ID="your-gcp-project-id"
   export REGION="us-central1"
   export DEPLOYMENT_NAME="privacy-analytics-$(date +%s)"
   ```

2. **Deploy the infrastructure**:
   ```bash
   # Create deployment
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
       --service-account=${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com \
       --git-source-repo="https://github.com/your-org/your-repo" \
       --git-source-directory="gcp/privacy-preserving-analytics-confidential-gke-bigquery/code/infrastructure-manager" \
       --git-source-ref="main"
   ```

3. **Monitor deployment**:
   ```bash
   # Check deployment status
   gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME}
   ```

### Using Terraform

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   terraform init
   ```

2. **Configure variables**:
   ```bash
   # Copy and edit the terraform.tfvars file
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your project details
   ```

3. **Plan and apply**:
   ```bash
   # Review planned changes
   terraform plan
   
   # Apply infrastructure
   terraform apply
   ```

4. **Get outputs**:
   ```bash
   # View important resource information
   terraform output
   ```

### Using Bash Scripts

1. **Set environment variables**:
   ```bash
   export PROJECT_ID="your-gcp-project-id"
   export REGION="us-central1"
   export ZONE="us-central1-a"
   ```

2. **Deploy infrastructure**:
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

3. **Monitor deployment**:
   ```bash
   # Follow the script output for deployment progress
   # Script will provide status updates and resource URLs
   ```

## Configuration Options

### Infrastructure Manager Variables

Edit the `infrastructure-manager/main.yaml` file to customize:

- `project_id`: Your GCP project ID
- `region`: Deployment region (default: us-central1)
- `cluster_machine_type`: Confidential GKE node machine type (default: n2d-standard-4)
- `cluster_node_count`: Number of nodes in the cluster (default: 2)
- `dataset_location`: BigQuery dataset location (default: US)

### Terraform Variables

Configure `terraform/terraform.tfvars`:

```hcl
project_id                = "your-gcp-project-id"
region                   = "us-central1"
zone                     = "us-central1-a"
cluster_name             = "confidential-cluster"
cluster_machine_type     = "n2d-standard-4"
cluster_node_count       = 2
dataset_name             = "sensitive_analytics"
bucket_name              = "privacy-analytics-bucket"
keyring_name             = "analytics-keyring"
key_name                 = "analytics-key"
enable_vertex_ai         = true
enable_monitoring        = true
```

### Script Configuration

Set these environment variables before running bash scripts:

```bash
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1" 
export ZONE="us-central1-a"
export CLUSTER_NAME="confidential-cluster"
export DATASET_NAME="sensitive_analytics"
export BUCKET_NAME="privacy-analytics-bucket"
export KEYRING_NAME="analytics-keyring"
export KEY_NAME="analytics-key"
```

## Deployment Components

This infrastructure creates:

### Security & Encryption
- **Cloud KMS Key Ring**: Centralized key management for encryption
- **Customer-Managed Encryption Key**: Dedicated key for data protection
- **IAM Service Accounts**: Least-privilege service accounts for applications

### Confidential Computing
- **Confidential GKE Cluster**: Kubernetes cluster with AMD SEV encryption
- **Confidential Node Pool**: Worker nodes with hardware-based memory encryption
- **Pod Security Policies**: Secure container runtime configurations

### Data Analytics
- **BigQuery Dataset**: Encrypted data warehouse with CMEK protection
- **BigQuery Tables**: Sample healthcare data with privacy controls
- **Analytics Views**: Privacy-preserving aggregation views

### Machine Learning
- **Cloud Storage Bucket**: Encrypted storage for ML training data
- **Vertex AI Service Account**: Secure ML training pipeline access
- **Training Job Configuration**: Privacy-preserving ML model training

### Applications
- **Privacy Analytics App**: Containerized data processing application
- **Monitoring Dashboard**: Cloud Monitoring integration for observability

## Validation Steps

After deployment, validate the infrastructure:

### 1. Verify Confidential Computing
```bash
# Check confidential nodes
kubectl get nodes -o jsonpath='{.items[*].metadata.labels}' | grep confidential

# Verify application deployment
kubectl get deployments -n default
kubectl logs deployment/privacy-analytics-app
```

### 2. Test BigQuery Encryption
```bash
# Verify CMEK configuration
bq show --format=prettyjson ${PROJECT_ID}:${DATASET_NAME} | jq '.defaultEncryptionConfiguration'

# Test privacy-preserving queries
bq query --use_legacy_sql=false "SELECT * FROM \`${PROJECT_ID}.${DATASET_NAME}.privacy_analytics_summary\` LIMIT 5"
```

### 3. Validate KMS Configuration
```bash
# Check encryption keys
gcloud kms keys list --location=${REGION} --keyring=${KEYRING_NAME}

# Verify key usage
gcloud kms keys describe ${KEY_NAME} --location=${REGION} --keyring=${KEYRING_NAME}
```

### 4. Test ML Pipeline
```bash
# Check Vertex AI jobs
gcloud ai custom-jobs list --region=${REGION}

# Verify encrypted storage
gsutil ls -L gs://${BUCKET_NAME}/ | grep -i kms
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/${DEPLOYMENT_NAME} \
    --delete-policy=DELETE
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Security Considerations

### Data Protection
- All data is encrypted at rest using customer-managed encryption keys
- Data processing occurs in hardware-encrypted memory (AMD SEV)
- Network traffic is encrypted in transit with TLS
- BigQuery implements column-level security and privacy controls

### Access Control
- Service accounts follow principle of least privilege
- IAM policies restrict access to encryption keys
- Kubernetes RBAC controls application permissions
- VPC-native networking provides network isolation

### Compliance Features
- Cloud Audit Logs track all administrative actions
- Cloud Monitoring provides security event visibility
- Confidential Computing provides hardware attestation
- Privacy-preserving analytics support GDPR/HIPAA requirements

## Troubleshooting

### Common Issues

1. **Confidential Computing Not Available**:
   ```bash
   # Check region/zone support for confidential computing
   gcloud compute machine-types list --filter="name~n2d" --zones=${ZONE}
   ```

2. **KMS Key Access Denied**:
   ```bash
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID} --flatten="bindings[].members" --format="table(bindings.role)"
   ```

3. **BigQuery CMEK Errors**:
   ```bash
   # Check BigQuery service account KMS permissions
   gcloud projects get-iam-policy ${PROJECT_ID} --filter="bindings.members:service-*@gcp-sa-bigquery.iam.gserviceaccount.com"
   ```

4. **GKE Cluster Creation Failed**:
   ```bash
   # Check quota and API enablement
   gcloud compute project-info describe --format="table(quotas[].metric,quotas[].limit,quotas[].usage)"
   ```

### Logs and Monitoring

- **GKE Logs**: `gcloud logging read "resource.type=gke_cluster"`
- **BigQuery Audit**: `gcloud logging read "protoPayload.serviceName=bigquery.googleapis.com"`
- **KMS Operations**: `gcloud logging read "protoPayload.serviceName=cloudkms.googleapis.com"`
- **Vertex AI Jobs**: `gcloud ai custom-jobs list --region=${REGION}`

## Performance Optimization

### Confidential Computing
- Monitor 5-10% performance overhead from hardware encryption
- Scale node pools based on workload requirements
- Use appropriate machine types for confidential workloads

### BigQuery Analytics
- Optimize query performance with proper table partitioning
- Use clustering for frequently accessed columns
- Monitor slot utilization and query performance

### ML Training
- Use appropriate compute resources for Vertex AI training
- Implement data pipeline optimization for encrypted data
- Monitor training job performance and costs

## Support and Documentation

### Google Cloud Documentation
- [Confidential GKE Nodes](https://cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes)
- [BigQuery Customer-Managed Encryption](https://cloud.google.com/bigquery/docs/customer-managed-encryption)
- [Cloud KMS Encryption](https://cloud.google.com/kms/docs/envelope-encryption)
- [Vertex AI Security](https://cloud.google.com/vertex-ai/docs/general/encryption)

### Additional Resources
- [Google Cloud Confidential Computing](https://cloud.google.com/confidential-computing)
- [Privacy-Preserving Analytics Best Practices](https://cloud.google.com/bigquery/docs/best-practices-privacy)
- [Differential Privacy in BigQuery](https://cloud.google.com/bigquery/docs/reference/standard-sql/differential_privacy_functions)

### Getting Help
- For infrastructure issues: Open a support case with Google Cloud Support
- For recipe-specific questions: Refer to the original recipe documentation
- For security concerns: Contact Google Cloud Security team through support channels

## Version History

- **v1.0**: Initial implementation with basic confidential computing
- **v1.1**: Added privacy-preserving analytics and ML training capabilities
- **Current**: Enhanced security controls and monitoring integration