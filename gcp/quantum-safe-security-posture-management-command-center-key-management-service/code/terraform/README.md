# Quantum-Safe Security Posture Management - Terraform Infrastructure

This Terraform configuration deploys a comprehensive quantum-safe security posture management solution on Google Cloud Platform, implementing post-quantum cryptography and automated compliance monitoring to protect against future quantum computing threats.

## 🛡️ Architecture Overview

The infrastructure implements a quantum-resistant security framework that includes:

- **Post-Quantum Cryptography**: NIST-approved ML-DSA-65 and SLH-DSA-SHA2-128S algorithms
- **Security Command Center Integration**: Centralized threat detection and compliance monitoring
- **Cloud Asset Inventory**: Automated cryptographic asset discovery and tracking
- **Compliance Automation**: Quarterly quantum readiness assessments and reporting
- **Monitoring & Alerting**: Real-time quantum vulnerability detection and notifications
- **Organization Policies**: Quantum-safe security governance and enforcement

## 📋 Prerequisites

### Required Permissions

Your Google Cloud user or service account needs the following roles:

- `roles/orgpolicy.policyAdmin` - Organization Policy Administrator
- `roles/securitycenter.admin` - Security Center Admin
- `roles/cloudkms.admin` - Cloud KMS Admin
- `roles/cloudasset.viewer` - Cloud Asset Viewer
- `roles/monitoring.editor` - Monitoring Editor
- `roles/logging.admin` - Logging Admin
- `roles/pubsub.editor` - Pub/Sub Editor
- `roles/storage.admin` - Storage Admin
- `roles/cloudfunctions.developer` - Cloud Functions Developer
- `roles/cloudscheduler.admin` - Cloud Scheduler Admin
- `roles/iam.serviceAccountAdmin` - Service Account Admin
- `roles/resourcemanager.projectIamAdmin` - Project IAM Admin
- `roles/billing.projectManager` - Billing Project Manager

### Required Tools

- **Terraform** >= 1.5.0
- **Google Cloud CLI** (`gcloud`) configured with appropriate credentials
- **Security Command Center Enterprise** subscription (organization-level)

### Regional Requirements

Post-quantum cryptography features are available in limited regions. Recommended regions:

- `us-central1` (Iowa) - Recommended for North America
- `us-east1` (South Carolina)
- `europe-west1` (Belgium) - Recommended for Europe
- `asia-east1` (Taiwan) - Recommended for Asia Pacific

## 🚀 Quick Start

### 1. Clone and Configure

```bash
# Navigate to the Terraform directory
cd gcp/quantum-safe-security-posture-management-command-center-key-management-service/code/terraform/

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your specific configuration
nano terraform.tfvars
```

### 2. Required Variables

Edit `terraform.tfvars` and provide these required values:

```hcl
# Organization and billing configuration
organization_id = "123456789012"  # Your GCP organization ID
billing_account = "123ABC-456DEF-789GHI"  # Your billing account ID
notification_email = "security-team@your-company.com"  # Alert email

# Project configuration
project_id = "quantum-security-prod-001"  # Globally unique project ID
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform and download providers
terraform init

# Review the planned infrastructure changes
terraform plan

# Deploy the quantum security infrastructure
terraform apply
```

### 4. Verify Deployment

```bash
# Check KMS keys
gcloud kms keys list --location=us-central1 --keyring=quantum-safe-keyring-prod --project=YOUR_PROJECT_ID

# Test post-quantum signing
echo "test message" | gcloud kms asymmetric-sign \
  --key=quantum-safe-key-prod-ml-dsa \
  --keyring=quantum-safe-keyring-prod \
  --location=us-central1 \
  --digest-algorithm=sha256 \
  --input-file=- \
  --project=YOUR_PROJECT_ID

# Check asset inventory feed
gcloud asset feeds describe quantum-crypto-assets --organization=YOUR_ORG_ID

# View monitoring dashboard
# Access: https://console.cloud.google.com/monitoring/dashboards
```

## 🔧 Configuration Options

### Post-Quantum Algorithms

Configure quantum-resistant cryptographic algorithms:

```hcl
pq_algorithms = {
  ml_dsa  = "PQ_SIGN_ML_DSA_65"         # Lattice-based (default)
  slh_dsa = "PQ_SIGN_SLH_DSA_SHA2_128S" # Hash-based (default)
}

# Alternative configurations:
# ml_dsa  = "PQ_SIGN_ML_DSA_87"         # Higher security level
# slh_dsa = "PQ_SIGN_SLH_DSA_SHA2_192S" # Higher security level
```

### Key Rotation Settings

Configure automatic key rotation for cryptographic agility:

```hcl
# Rotation periods (in seconds)
kms_key_rotation_period = "2592000s"  # 30 days (default)
# kms_key_rotation_period = "604800s"   # 7 days (high security)
# kms_key_rotation_period = "7776000s"  # 90 days (standard)
```

### Compliance Scheduling

Configure automated compliance report generation:

```hcl
compliance_schedule = "0 9 1 */3 *"  # Quarterly at 9 AM UTC (default)
# compliance_schedule = "0 9 * * 1"    # Weekly on Mondays
# compliance_schedule = "0 9 1 * *"    # Monthly on 1st day
```

### Asset Tracking Scope

Customize which asset types to monitor for quantum vulnerabilities:

```hcl
asset_types_to_track = [
  "cloudkms.googleapis.com/CryptoKey",
  "cloudkms.googleapis.com/KeyRing",
  "compute.googleapis.com/Disk",
  "compute.googleapis.com/Instance",
  "storage.googleapis.com/Bucket",
  "sql.googleapis.com/DatabaseInstance"
]
```

## 📊 Monitoring and Compliance

### Quantum Security Dashboard

The deployment creates a comprehensive monitoring dashboard accessible at:
```
https://console.cloud.google.com/monitoring/dashboards/custom/DASHBOARD_ID?project=PROJECT_ID
```

**Dashboard Metrics:**
- Post-quantum key usage and adoption rates
- Quantum vulnerability alerts and trends
- Cryptographic asset inventory changes
- Key rotation compliance status

### Automated Compliance Reports

Compliance reports are automatically generated and include:

- **Quantum Readiness Score**: 0-100 scale based on post-quantum adoption
- **Asset Analysis**: Breakdown of quantum-safe vs. vulnerable cryptographic keys
- **Security Findings**: Integration with Security Command Center alerts
- **Recommendations**: Prioritized action items for quantum security improvement

Reports are stored in Cloud Storage and accessible via the Cloud Function endpoint.

### Alert Policies

The infrastructure includes alert policies for:

- **Quantum Vulnerabilities**: Immediate alerts when vulnerable algorithms are detected
- **Key Rotation Compliance**: Notifications when key rotation is overdue
- **Asset Changes**: Real-time notifications of cryptographic asset modifications
- **Compliance Violations**: Alerts for organization policy violations

## 🔒 Security Features

### Organization Policies

The deployment enforces quantum-safe security policies:

```hcl
# OS Login requirement for enhanced access control
enforce_os_login = true

# Disable service account key creation to improve security posture
disable_service_account_keys = true

# Restrict cryptographic algorithms to quantum-safe only
# Automatically enforced through organization policy
```

### IAM and Access Control

- **Least Privilege Access**: Service accounts with minimal required permissions
- **Automated Role Management**: IAM bindings for secure inter-service communication
- **Audit Logging**: Comprehensive logging of all security-related operations

### Data Protection

- **Encryption at Rest**: All storage encrypted with post-quantum cryptographic keys
- **Encryption in Transit**: TLS encryption for all communications
- **Key Rotation**: Automated rotation with configurable periods
- **Backup and Recovery**: Versioned storage with lifecycle management

## 💰 Cost Optimization

### Estimated Monthly Costs

| Service | Estimated Cost (USD) |
|---------|---------------------|
| Security Command Center Enterprise | $500-2000 (org-level) |
| Cloud KMS (2 keys) | $2-20 |
| Cloud Functions | $1-10 |
| Cloud Storage | $10-50 |
| Cloud Monitoring | $20-100 |
| **Total Estimated** | **$533-2180** |

### Cost Management Features

- **Budget Alerts**: Configurable budget thresholds with email notifications
- **Lifecycle Policies**: Automatic data archival to reduce storage costs
- **Resource Optimization**: Right-sized resources based on actual usage
- **Cost Tracking**: Comprehensive labeling for cost attribution

## 🛠️ Maintenance and Operations

### Regular Maintenance Tasks

1. **Monthly**: Review quantum readiness scores and compliance reports
2. **Quarterly**: Assess and update post-quantum algorithm configurations
3. **Annually**: Review and update organization policies and security controls

### Monitoring Best Practices

- Monitor key rotation compliance and address any missed rotations
- Review security findings and prioritize high-severity quantum vulnerabilities
- Track post-quantum adoption rates across the organization
- Maintain up-to-date documentation of cryptographic asset inventory

### Backup and Disaster Recovery

- **State File Backups**: Use remote state backends with versioning
- **Configuration Backups**: Maintain infrastructure as code in version control
- **Key Recovery**: Follow Google Cloud KMS key recovery procedures
- **Documentation**: Keep deployment and configuration documentation current

## 🔧 Troubleshooting

### Common Issues

**Issue**: `Error creating KMS key: Post-quantum algorithms not available`
**Solution**: Ensure your selected region supports post-quantum cryptography features

**Issue**: `Organization policy constraint not found`
**Solution**: Verify Security Command Center Enterprise subscription is active

**Issue**: `Insufficient permissions for Cloud Asset Inventory`
**Solution**: Ensure service account has `roles/cloudasset.viewer` at organization level

**Issue**: `Cloud Function deployment timeout`
**Solution**: Check function source code and dependencies, consider increasing memory allocation

### Debug Mode

Enable debug logging for troubleshooting:

```hcl
enable_debug_logging = true
```

### Support Resources

- [Google Cloud KMS Post-Quantum Cryptography Documentation](https://cloud.google.com/kms/docs/post-quantum-cryptography)
- [Security Command Center Best Practices](https://cloud.google.com/security-command-center/docs/best-practices)
- [Cloud Asset Inventory Documentation](https://cloud.google.com/asset-inventory/docs)
- [NIST Post-Quantum Cryptography Standards](https://csrc.nist.gov/pqc-standardization)

## 🔄 Upgrade and Migration

### Terraform Provider Upgrades

```bash
# Update provider versions in versions.tf
# Run terraform init with upgrade flag
terraform init -upgrade

# Review planned changes
terraform plan

# Apply updates
terraform apply
```

### Post-Quantum Algorithm Updates

When new NIST-approved algorithms become available:

1. Update `pq_algorithms` variable in `terraform.tfvars`
2. Run `terraform plan` to review changes
3. Apply updates during maintenance window
4. Verify new keys are created with updated algorithms

## 📚 Additional Resources

### Documentation

- [Quantum-Safe Security Recipe](../../../quantum-safe-security-posture-management-command-center-key-management-service.md)
- [Google Cloud Security Best Practices](https://cloud.google.com/security/best-practices)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Training and Certification

- [Google Cloud Security Engineer Certification](https://cloud.google.com/certification/cloud-security-engineer)
- [NIST Post-Quantum Cryptography Education](https://www.nist.gov/pqc-education)
- [Quantum-Safe Security Training Programs](https://quantum-safe.org/)

## 📝 License

This Terraform configuration is provided under the Apache 2.0 License. See the recipe documentation for complete licensing information.

## 🤝 Contributing

For improvements or bug fixes, please refer to the main recipe repository contribution guidelines.

---

**⚠️ Security Notice**: This infrastructure handles cryptographic keys and security policies. Always review changes carefully and follow your organization's change management procedures before deploying to production environments.