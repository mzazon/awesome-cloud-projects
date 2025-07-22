# Enterprise Identity Federation Workflows - Terraform Infrastructure

This Terraform configuration deploys a complete enterprise identity federation system using Google Cloud's Workload Identity Federation, Service Directory, Secret Manager, and Cloud Functions for automated provisioning workflows.

## Architecture Overview

The infrastructure creates:

- **Workload Identity Federation**: Keyless authentication for external workloads
- **Service Directory**: Centralized service discovery and registry
- **Cloud Functions**: Automated identity provisioning workflows
- **Secret Manager**: Secure configuration storage
- **DNS Integration**: Service discovery through DNS resolution
- **IAM Configuration**: Multi-tier access control with least privilege

## Prerequisites

1. **Google Cloud Project** with billing enabled
2. **Terraform** >= 1.5.0 installed
3. **Google Cloud SDK** configured with appropriate permissions
4. **Project Owner or Security Admin** permissions for IAM configuration

### Required APIs

The following APIs will be automatically enabled:

- Identity and Access Management (IAM) API
- Security Token Service API
- Service Directory API
- Cloud Functions API
- Secret Manager API
- Cloud Build API
- Cloud DNS API
- Cloud Resource Manager API
- Eventarc API

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository (if not already done)
cd gcp/enterprise-identity-federation-workflows-iam-service-directory/code/terraform

# Copy the example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file with your configuration
nano terraform.tfvars
```

### 2. Required Configuration

Edit `terraform.tfvars` and set these required variables:

```hcl
# Your Google Cloud Project ID
project_id = "your-project-id"

# OIDC issuer for your identity provider
oidc_issuer_uri = "https://token.actions.githubusercontent.com"

# Conditional access expression for security
oidc_attribute_condition = "assertion.repository_owner_id == \"123456789\""
```

### 3. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the configuration
terraform apply
```

### 4. Verify Deployment

```bash
# Check Workload Identity Pool
gcloud iam workload-identity-pools describe $(terraform output -raw workload_identity_pool_id) --location=global

# Check Service Directory namespace
gcloud service-directory namespaces describe $(terraform output -raw service_directory_namespace_id) --location=$(terraform output -raw service_directory_namespace_location)

# Check Cloud Function
gcloud functions describe $(terraform output -raw cloud_function_name) --region=$(terraform output -raw service_directory_namespace_location) --gen2

# Test the identity provisioning endpoint
curl -X POST $(terraform output -raw cloud_function_url) \
  -H "Content-Type: application/json" \
  -d '{
    "identity": "test-user@example.com",
    "service": "user-management",
    "access_level": "read-only"
  }'
```

## Configuration Options

### Identity Provider Integration

#### GitHub Actions
```hcl
oidc_issuer_uri = "https://token.actions.githubusercontent.com"
oidc_attribute_condition = "assertion.repository_owner_id == \"123456789\" && assertion.repository == \"your-org/your-repo\""
```

#### Azure AD
```hcl
oidc_issuer_uri = "https://sts.windows.net/your-tenant-id"
oidc_attribute_condition = "\"admin-group-id\" in assertion.groups"
oidc_allowed_audiences = ["your-azure-app-id"]
```

#### Generic OIDC Provider
```hcl
oidc_issuer_uri = "https://your-oidc-provider.com"
oidc_attribute_condition = "assertion.email.endsWith(\"@yourdomain.com\")"
```

### Service Directory Configuration

Add custom services to the enterprise registry:

```hcl
enterprise_services = {
  api-gateway = {
    description = "Enterprise API Gateway service"
    metadata = {
      version = "v2"
      tier    = "production"
      owner   = "api-team"
    }
  }
  monitoring = {
    description = "Enterprise monitoring service"
    metadata = {
      version = "v1"
      tier    = "production"
      owner   = "ops-team"
    }
  }
}
```

### Cloud Function Customization

```hcl
function_runtime       = "python311"
function_memory        = "512M"
function_timeout       = 120
function_max_instances = 50
function_min_instances = 1
```

### Security Hardening

```hcl
enable_advanced_security = true
enable_audit_logs        = true

service_account_permissions = [
  "roles/bigquery.dataViewer",
  "roles/storage.objectViewer"
]

workload_identity_conditions = {
  branch_restriction = "assertion.ref == \"refs/heads/main\""
  time_restriction   = "assertion.iat > (now - duration(\"1h\"))"
}
```

## Monitoring and Alerting

Enable comprehensive monitoring:

```hcl
enable_monitoring = true
monitoring_email  = "alerts@yourcompany.com"

alert_thresholds = {
  function_error_rate   = 0.05  # 5% error rate
  function_duration_p99 = 45000 # 45 second timeout
  secret_access_rate    = 200   # 200 requests/minute
}
```

## Usage Examples

### Federated Authentication

After deployment, external workloads can authenticate using:

```bash
# Get federation configuration
POOL_NAME=$(terraform output -raw workload_identity_pool_name)
PROVIDER_NAME=$(terraform output -raw workload_identity_provider_name)
SA_EMAIL=$(terraform output -raw federation_service_account_email)

# Exchange external token for Google Cloud access token
gcloud sts create-access-token \
  --audience="//iam.googleapis.com/${PROVIDER_NAME}" \
  --token-file=external-token.txt \
  --token-type=urn:ietf:params:oauth:token-type:id_token \
  --requested-token-type=urn:ietf:params:oauth:token-type:access_token \
  --impersonate-service-account=${SA_EMAIL}
```

### Service Discovery

Services can be discovered through DNS:

```bash
# DNS resolution examples
nslookup user-mgmt.services.${PROJECT_ID}.internal
nslookup idp.services.${PROJECT_ID}.internal
nslookup resource-mgmt.services.${PROJECT_ID}.internal
```

### Identity Provisioning

Use the Cloud Function for automated provisioning:

```bash
# Provision identity with read-only access
curl -X POST $(terraform output -raw cloud_function_url) \
  -H "Content-Type: application/json" \
  -d '{
    "identity": "user@company.com",
    "service": "user-management",
    "access_level": "read-only"
  }'

# Provision identity with admin access
curl -X POST $(terraform output -raw cloud_function_url) \
  -H "Content-Type: application/json" \
  -d '{
    "identity": "admin@company.com",
    "service": "resource-manager",
    "access_level": "admin"
  }'
```

## Security Considerations

### IAM Best Practices

1. **Least Privilege**: Service accounts are granted minimal required permissions
2. **Conditional Access**: CEL expressions enforce additional security constraints
3. **Audit Logging**: All identity federation events are logged for compliance
4. **Secret Management**: Sensitive configuration stored in Secret Manager

### Network Security

1. **Private DNS**: Service discovery uses private DNS zones
2. **Internal Ingress**: Cloud Function restricted to internal traffic
3. **VPC Controls**: Resources deployed within specified VPC networks

### Compliance Features

1. **Audit Trails**: Comprehensive logging for all provisioning activities
2. **Access Controls**: Multi-tier access levels (read-only, standard, admin)
3. **Data Residency**: Configurable regions for compliance requirements
4. **Retention Policies**: Automated lifecycle management for storage

## Troubleshooting

### Common Issues

#### Authentication Errors
```bash
# Verify application default credentials
gcloud auth application-default login

# Check project permissions
gcloud projects get-iam-policy ${PROJECT_ID}
```

#### API Enablement Issues
```bash
# Manually enable required APIs
gcloud services enable iamcredentials.googleapis.com
gcloud services enable sts.googleapis.com
gcloud services enable servicedirectory.googleapis.com
```

#### Workload Identity Federation Issues
```bash
# Test token exchange
gcloud iam workload-identity-pools describe ${POOL_ID} --location=global

# Verify provider configuration
gcloud iam workload-identity-pools providers describe ${PROVIDER_ID} \
  --workload-identity-pool=${POOL_ID} \
  --location=global
```

#### Cloud Function Issues
```bash
# Check function logs
gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

# Test function locally
cd function_source
python main.py
```

### Debugging Commands

Use the validation commands from terraform outputs:

```bash
# Get all validation commands
terraform output validation_commands

# Run specific validations
terraform output -raw validation_commands | jq -r '.check_wi_pool'
terraform output -raw validation_commands | jq -r '.check_function'
```

## Cost Optimization

### Free Tier Usage

- **Workload Identity Federation**: No additional charges
- **Service Directory**: First namespace free
- **Secret Manager**: First 6 active secret versions free
- **Cloud Functions**: 2M invocations and 400K GB-seconds free
- **Cloud DNS**: First 25 zones free

### Cost Management

```hcl
# Enable cost optimization features
enable_cost_optimization = true
preemptible_instances    = true

# Optimize function configuration
function_min_instances = 0
storage_lifecycle_age  = 30

# Enable monitoring for cost tracking
enable_monitoring = true
```

## Backup and Disaster Recovery

### State Management

Use remote state for production deployments:

```hcl
terraform {
  backend "gcs" {
    bucket                      = "your-terraform-state-bucket"
    prefix                      = "enterprise-identity-federation"
    impersonate_service_account = "terraform@your-project.iam.gserviceaccount.com"
  }
}
```

### Backup Configuration

```hcl
backup_retention_days           = 90
enable_point_in_time_recovery  = true
enable_storage_versioning      = true
```

## Advanced Configuration

### Multi-Region Deployment

```hcl
enable_multi_region = true

# Configure additional regions for replication
secret_replication_policy    = "user_managed"
secret_replication_locations = ["us-central1", "us-east1", "europe-west1"]
```

### Custom Domains

```hcl
enable_custom_domains = true

# Configure custom DNS for services
dns_zone_visibility = "public"
```

### External Integration

```hcl
enable_external_secrets = true
enable_advanced_security = true

# Integration with enterprise systems
compliance_standards = ["SOC2", "PCI-DSS", "HIPAA"]
data_residency_regions = ["us-central1", "us-east1"]
```

## Cleanup

To destroy all resources:

```bash
# Destroy infrastructure
terraform destroy

# Verify cleanup
gcloud projects list --filter="projectId:${PROJECT_ID}"
```

## Support and Contributing

### Getting Help

1. Check the [troubleshooting section](#troubleshooting)
2. Review Google Cloud documentation for specific services
3. Examine Terraform logs for detailed error information
4. Use `terraform plan` to preview changes before applying

### Best Practices

1. **Version Control**: Store Terraform configurations in version control
2. **State Management**: Use remote state backends for team collaboration
3. **Module Versioning**: Pin provider versions for consistency
4. **Testing**: Validate configurations in non-production environments
5. **Documentation**: Keep README and variable descriptions up to date

### Security Guidelines

1. **Never commit** `terraform.tfvars` files to version control
2. **Use Secret Manager** for sensitive configuration data
3. **Implement** conditional access policies for enhanced security
4. **Enable** comprehensive audit logging for compliance
5. **Review** IAM permissions regularly and apply least privilege

## Next Steps

After successful deployment:

1. Configure your external identity provider to trust the Workload Identity Pool
2. Test identity federation with sample workloads
3. Set up monitoring and alerting based on your requirements
4. Document integration procedures for your development teams
5. Implement CI/CD pipelines for automated deployments
6. Review and adjust security policies based on your organization's requirements