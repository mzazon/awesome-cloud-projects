# Infrastructure as Code for Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Certificate Lifecycle Management with Certificate Authority Service and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This infrastructure creates an automated certificate lifecycle management system including:
- Certificate Authority Service (Enterprise tier) with root and subordinate CAs
- Cloud Functions for certificate monitoring and renewal automation
- Cloud Scheduler for automated certificate checks
- Secret Manager for secure certificate storage
- Service accounts with appropriate IAM permissions
- Monitoring and alerting configuration

## Prerequisites

- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and configured
- Terraform >= 1.0 (for Terraform implementation)
- Appropriate permissions for:
  - Certificate Authority Service
  - Cloud Functions
  - Cloud Scheduler
  - Secret Manager
  - IAM and service account management
  - Cloud Logging and Monitoring

### Required APIs

The following APIs will be enabled automatically during deployment:
- Certificate Authority Service API (`privateca.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Secret Manager API (`secretmanager.googleapis.com`)
- Cloud Resource Manager API (`cloudresourcemanager.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Logging API (`logging.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-lifecycle \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="inputs.yaml"
```

### Using Terraform

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy with Terraform
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Configuration Options

### Infrastructure Manager Variables (inputs.yaml)

```yaml
project_id:
  description: "Google Cloud Project ID"
  value: "your-project-id"

region:
  description: "Google Cloud Region"
  value: "us-central1"

ca_pool_tier:
  description: "Certificate Authority Pool tier (ENTERPRISE or DEVOPS)"
  value: "ENTERPRISE"

root_ca_validity:
  description: "Root CA validity period"
  value: "10y"

sub_ca_validity:
  description: "Subordinate CA validity period"
  value: "5y"

renewal_threshold_days:
  description: "Days before expiration to trigger renewal"
  value: 30

monitor_schedule:
  description: "Cron schedule for certificate monitoring"
  value: "0 8 * * *"
```

### Terraform Variables

Key variables that can be customized in `terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
ca_pool_tier = "ENTERPRISE"
root_ca_validity = "10y"
sub_ca_validity = "5y"
renewal_threshold_days = 30
monitor_schedule = "0 8 * * *"

# Optional: Custom naming
ca_pool_name = "enterprise-ca-pool"
root_ca_name = "root-ca"
sub_ca_name = "sub-ca"
```

## Deployment Process

### Infrastructure Manager Deployment

1. **Prepare Configuration**:
   ```bash
   cd infrastructure-manager/
   cp inputs.yaml.example inputs.yaml
   # Edit inputs.yaml with your values
   ```

2. **Deploy Infrastructure**:
   ```bash
   gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-lifecycle \
       --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
       --local-source="." \
       --inputs-file="inputs.yaml"
   ```

3. **Monitor Deployment**:
   ```bash
   gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-lifecycle
   ```

### Terraform Deployment

1. **Initialize Terraform**:
   ```bash
   cd terraform/
   terraform init
   ```

2. **Plan Deployment**:
   ```bash
   terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
   ```

3. **Apply Configuration**:
   ```bash
   terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
   ```

4. **View Outputs**:
   ```bash
   terraform output
   ```

### Script-Based Deployment

1. **Set Environment Variables**:
   ```bash
   export PROJECT_ID="your-project-id"
   export REGION="us-central1"
   export CA_POOL_TIER="ENTERPRISE"  # or "DEVOPS" for testing
   ```

2. **Run Deployment Script**:
   ```bash
   ./scripts/deploy.sh
   ```

## Post-Deployment Verification

### Verify Certificate Authority Infrastructure

```bash
# Check CA pool status
gcloud privateca pools list --location=${REGION}

# Verify root CA
gcloud privateca roots list --pool=enterprise-ca-pool --location=${REGION}

# Check subordinate CA
gcloud privateca subordinates list --pool=enterprise-ca-pool --location=${REGION}
```

### Test Cloud Functions

```bash
# List deployed functions
gcloud functions list --region=${REGION}

# Test certificate monitoring function
MONITOR_FUNCTION_URL=$(gcloud functions describe cert-monitor --region=${REGION} --format="value(httpsTrigger.url)")
curl -X POST ${MONITOR_FUNCTION_URL} \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"source":"manual_test"}'
```

### Verify Scheduler Jobs

```bash
# List scheduler jobs
gcloud scheduler jobs list --location=${REGION}

# Check job status
gcloud scheduler jobs describe cert-check --location=${REGION}
```

## Certificate Operations

### Issue a Test Certificate

```bash
# Get renewal function URL
RENEW_FUNCTION_URL=$(gcloud functions describe cert-renew --region=${REGION} --format="value(httpsTrigger.url)")

# Issue test certificate
curl -X POST ${RENEW_FUNCTION_URL} \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d '{"common_name": "test.example.com", "validity_days": 90}'
```

### Monitor Certificate Status

```bash
# Check stored certificates in Secret Manager
gcloud secrets list --filter="name~cert-"

# View certificate details
gcloud secrets versions access latest --secret="cert-test-example-com"
```

## Monitoring and Troubleshooting

### Cloud Function Logs

```bash
# View monitor function logs
gcloud functions logs read cert-monitor --region=${REGION} --limit=50

# View renewal function logs
gcloud functions logs read cert-renew --region=${REGION} --limit=50
```

### Certificate Authority Logs

```bash
# View CA operation logs
gcloud logging read 'resource.type="privateca_certificate_authority"' --limit=20
```

### Common Issues

1. **Permission Errors**: Ensure service accounts have proper IAM roles
2. **API Not Enabled**: Verify all required APIs are enabled
3. **Function Timeout**: Increase function timeout for complex operations
4. **CA State Issues**: Ensure CAs are in ENABLED state before operations

## Security Considerations

### Service Account Permissions

The deployment creates a dedicated service account with minimal required permissions:
- `roles/privateca.certificateManager`: Certificate operations
- `roles/secretmanager.admin`: Certificate storage
- `roles/logging.logWriter`: Operational logging

### Certificate Storage

- All certificates are stored encrypted in Secret Manager
- Access is controlled through IAM policies
- Certificate versions are maintained for rollback capability

### Network Security

- Cloud Functions use HTTPS endpoints with authentication
- Internal communication uses Google Cloud's secure networking
- No sensitive data is logged or exposed

## Cost Optimization

### Enterprise vs DevOps Tier

- **Enterprise Tier**: $200/month per active CA + certificate fees
- **DevOps Tier**: $10/month per active CA (limited features)
- Choose DevOps tier for development/testing environments

### Function Optimization

- Monitor function execution metrics
- Adjust memory allocation based on usage patterns
- Use efficient algorithms for certificate processing

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/cert-lifecycle
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify CA resources are deleted
gcloud privateca pools list --location=${REGION}

# Check function cleanup
gcloud functions list --region=${REGION}

# Verify scheduler jobs removed
gcloud scheduler jobs list --location=${REGION}

# Check secret cleanup
gcloud secrets list --filter="name~cert-"
```

## Customization

### Certificate Templates

Modify certificate templates in the infrastructure code to customize:
- Key usage extensions
- Validity periods
- Subject alternative names
- Certificate policies

### Monitoring Configuration

Customize alerting policies for:
- Certificate expiration thresholds
- Function execution failures
- CA operation anomalies
- Security events

### Automation Schedules

Adjust Cloud Scheduler configurations for:
- Monitoring frequency
- Renewal timing
- Compliance checking
- Reporting schedules

## Advanced Configuration

### Multi-Region Deployment

For high availability, deploy across multiple regions:

```bash
# Deploy to multiple regions
for region in us-central1 us-east1 europe-west1; do
    terraform apply -var="project_id=${PROJECT_ID}" -var="region=${region}"
done
```

### Custom Certificate Policies

Implement organization-specific certificate policies:

```yaml
# Custom certificate template
certificate_template:
  predefined_values:
    key_usage:
      base_key_usage:
        digital_signature: true
        key_encipherment: true
    extended_key_usage:
      server_auth: true
      client_auth: true
  identity_constraints:
    cel_expression:
      expression: 'subject_alt_names.all(san, san.type == DNS)'
```

## Support and Documentation

### Google Cloud Documentation

- [Certificate Authority Service](https://cloud.google.com/certificate-authority-service/docs)
- [Cloud Functions](https://cloud.google.com/functions/docs)
- [Cloud Scheduler](https://cloud.google.com/scheduler/docs)
- [Secret Manager](https://cloud.google.com/secret-manager/docs)

### Troubleshooting

For issues with this infrastructure code:
1. Check the deployment logs
2. Verify IAM permissions
3. Ensure all required APIs are enabled
4. Review the original recipe documentation
5. Consult Google Cloud support for service-specific issues

### Community Resources

- [Google Cloud Community](https://cloud.google.com/community)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/google-cloud-platform)
- [Google Cloud GitHub Repositories](https://github.com/GoogleCloudPlatform)

## License

This infrastructure code is provided as part of the cloud recipes collection. Refer to the repository license for usage terms.