# Infrastructure as Code for Quantum-Safe Security Posture Management with Security Command Center and Cloud Key Management Service

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Quantum-Safe Security Posture Management with Security Command Center and Cloud Key Management Service".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Google Cloud organization with Security Command Center Enterprise tier subscription
- Cloud Identity or Google Workspace super admin permissions for organization-level policies
- Security Engineer role (`roles/securitycenter.admin`) and KMS Admin role (`roles/cloudkms.admin`)
- Appropriate billing account linked to the project
- Post-quantum cryptography features available in your region (currently in preview)

> **Note**: This advanced recipe requires organization-level permissions and Security Command Center Enterprise subscription. Estimated cost: $500-2000/month for Security Command Center Enterprise, $1-10/key/month for Cloud KMS.

## Quick Start

### Using Infrastructure Manager

```bash
# Set required environment variables
export PROJECT_ID="quantum-security-$(date +%s)"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
export REGION="us-central1"

# Create and configure project
gcloud projects create ${PROJECT_ID} \
    --name="Quantum Security Posture Management" \
    --organization=${ORGANIZATION_ID##*/}

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable securitycenter.googleapis.com
gcloud services enable cloudkms.googleapis.com
gcloud services enable cloudasset.googleapis.com

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply quantum-safe-security \
    --location=${REGION} \
    --service-account=PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --gcs-source=gs://YOUR_BUCKET/quantum-safe-config.zip
```

### Using Terraform

```bash
# Set required environment variables
export PROJECT_ID="quantum-security-$(date +%s)"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
export REGION="us-central1"

# Initialize and deploy with Terraform
cd terraform/
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "${PROJECT_ID}"
organization_id = "${ORGANIZATION_ID##*/}"
region = "${REGION}"
random_suffix = "$(openssl rand -hex 3)"
EOF

# Plan and apply
terraform plan
terraform apply -auto-approve
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="quantum-security-$(date +%s)"
export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1)
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# Monitor deployment progress
gcloud logging read "resource.type=gce_instance" --limit=50
```

## Architecture Overview

The infrastructure deployed includes:

- **Security Command Center Enterprise**: Organization-level threat detection and compliance monitoring
- **Cloud KMS with Post-Quantum Cryptography**: Quantum-resistant key management using ML-DSA-65 and SLH-DSA algorithms
- **Cloud Asset Inventory**: Cryptographic asset discovery and tracking
- **Cloud Monitoring**: Real-time quantum security metrics and alerting
- **Cloud Functions**: Automated compliance reporting and governance
- **Organization Policies**: Quantum-safe security baseline enforcement

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| project_id | Google Cloud project ID | - | Yes |
| organization_id | Google Cloud organization ID | - | Yes |
| region | Deployment region | us-central1 | No |
| keyring_name | KMS keyring name | quantum-safe-keyring | No |
| enable_monitoring | Enable quantum security monitoring | true | No |

### Terraform Variables

| Variable | Description | Type | Default | Required |
|----------|-------------|------|---------|----------|
| project_id | Google Cloud project ID | string | - | Yes |
| organization_id | Google Cloud organization ID | string | - | Yes |
| region | Deployment region | string | us-central1 | No |
| zone | Deployment zone | string | us-central1-a | No |
| random_suffix | Random suffix for resource names | string | - | Yes |
| keyring_name | KMS keyring name | string | quantum-safe-keyring | No |
| enable_enterprise_scc | Enable Security Command Center Enterprise | bool | true | No |
| enable_compliance_reporting | Enable automated compliance reporting | bool | true | No |

### Environment Variables for Scripts

```bash
export PROJECT_ID="your-project-id"                    # Required
export ORGANIZATION_ID="your-organization-id"          # Required
export REGION="us-central1"                           # Optional
export ZONE="us-central1-a"                           # Optional
export BILLING_ACCOUNT="your-billing-account-id"      # Required
export SECURITY_EMAIL="security-team@company.com"     # Optional
```

## Post-Deployment Verification

After deployment, verify the quantum-safe security infrastructure:

### 1. Check Security Command Center Status

```bash
gcloud scc organizations describe ${ORGANIZATION_ID}
```

### 2. Verify Post-Quantum Keys

```bash
# List quantum-safe keys
gcloud kms keys list \
    --location=${REGION} \
    --keyring=quantum-safe-keyring-${RANDOM_SUFFIX}

# Test ML-DSA-65 key functionality
echo "Test quantum-safe signature" | \
gcloud kms asymmetric-sign \
    --key=quantum-safe-key-${RANDOM_SUFFIX}-ml-dsa \
    --keyring=quantum-safe-keyring-${RANDOM_SUFFIX} \
    --location=${REGION} \
    --digest-algorithm=sha256 \
    --input-file=- \
    --signature-file=test-signature.sig
```

### 3. Validate Asset Inventory

```bash
# Check asset inventory feed
gcloud asset feeds describe quantum-crypto-assets \
    --organization=${ORGANIZATION_ID}

# Search for cryptographic assets
gcloud asset search-all-resources \
    --scope=organizations/${ORGANIZATION_ID} \
    --asset-types=cloudkms.googleapis.com/CryptoKey
```

### 4. Test Monitoring Dashboard

```bash
# List quantum security dashboards
gcloud monitoring dashboards list \
    --filter="displayName:Quantum Security Posture Dashboard"

# Check alert policies
gcloud alpha monitoring policies list \
    --filter="displayName:Quantum Vulnerability Detection"
```

### 5. Verify Compliance Reporting

```bash
# Test compliance report generation
curl -X GET \
    "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/quantum-compliance-report?org_id=${ORGANIZATION_ID}"

# Check scheduler job status
gcloud scheduler jobs describe quantum-compliance-scheduler \
    --location=${REGION}
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete quantum-safe-security \
    --location=${REGION} \
    --quiet

# Clean up project
gcloud projects delete ${PROJECT_ID} --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy -auto-approve

# Clean up project if needed
gcloud projects delete ${PROJECT_ID} --quiet
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh

# Verify cleanup
gcloud projects describe ${PROJECT_ID} || echo "Project successfully deleted"
```

## Security Considerations

### Post-Quantum Cryptography

- **ML-DSA-65**: NIST-standardized lattice-based digital signature algorithm resistant to quantum attacks
- **SLH-DSA-SHA2-128S**: NIST-standardized hash-based signature scheme for quantum resistance
- **Key Rotation**: Automatic 30-day rotation ensures cryptographic agility against emerging threats

### Access Control

- **Least Privilege**: IAM roles follow principle of least privilege
- **Organization Policies**: Enforce quantum-safe security baselines
- **Service Accounts**: Dedicated service accounts for automated functions

### Monitoring and Alerting

- **Real-time Detection**: Continuous monitoring for quantum vulnerabilities
- **Compliance Tracking**: Automated reporting for regulatory requirements
- **Threat Intelligence**: Integration with Security Command Center Enterprise

## Troubleshooting

### Common Issues

1. **Organization Access Denied**
   ```bash
   # Verify organization permissions
   gcloud organizations get-iam-policy ${ORGANIZATION_ID}
   ```

2. **Security Command Center Not Available**
   ```bash
   # Check SCC Enterprise subscription
   gcloud scc organizations describe ${ORGANIZATION_ID}
   ```

3. **Post-Quantum Keys Not Supported**
   ```bash
   # Verify region supports PQC
   gcloud kms locations list --filter="name:${REGION}"
   ```

4. **Asset Inventory Feed Creation Failed**
   ```bash
   # Check organization-level permissions
   gcloud asset feeds list --organization=${ORGANIZATION_ID}
   ```

### Debug Commands

```bash
# Enable debug logging
export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"

# Check API enablement
gcloud services list --enabled --project=${PROJECT_ID}

# Verify billing account linkage
gcloud billing projects describe ${PROJECT_ID}

# Test organization policies
gcloud org-policies list --organization=${ORGANIZATION_ID}
```

## Cost Optimization

### Resource Costs

- **Security Command Center Enterprise**: $500-2000/month (organization-level)
- **Cloud KMS**: $1-10/key/month + $0.03 per 10,000 operations
- **Cloud Asset Inventory**: Free for basic usage
- **Cloud Monitoring**: $0.258 per MiB ingested
- **Cloud Functions**: $0.40 per million requests

### Cost Control

```bash
# Set up budget alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT} \
    --display-name="Quantum Security Budget" \
    --budget-amount=1000USD

# Monitor resource usage
gcloud monitoring metrics list \
    --filter="metric.type:cloudkms.googleapis.com"
```

## Compliance and Governance

### NIST Standards Compliance

- **FIPS 204**: ML-DSA digital signature standard
- **FIPS 205**: SLH-DSA signature standard
- **NIST SP 800-208**: Recommendation for stateful hash-based signature schemes

### Regulatory Alignment

- **SOC 2 Type II**: Security monitoring and compliance reporting
- **ISO 27001**: Information security management
- **FedRAMP**: Federal risk and authorization management program

## Extension Opportunities

1. **Multi-Cloud Integration**: Extend to AWS Security Hub and Azure Security Center
2. **Zero-Trust Architecture**: Implement quantum-safe authentication for all services
3. **Automated Migration**: Build quantum vulnerability remediation workflows
4. **Threat Intelligence**: Integrate external quantum computing research feeds
5. **Developer Tools**: Create quantum-safe development environment templates

## Support and Documentation

- [Google Cloud KMS Post-Quantum Cryptography](https://cloud.google.com/kms/docs/post-quantum-cryptography)
- [Security Command Center Documentation](https://cloud.google.com/security-command-center/docs)
- [Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs)
- [NIST Post-Quantum Cryptography Standards](https://csrc.nist.gov/pqc-standardization)
- [Google Cloud Well-Architected Framework](https://cloud.google.com/architecture/framework/security)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support channels.