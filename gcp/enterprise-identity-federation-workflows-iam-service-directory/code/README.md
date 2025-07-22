# Infrastructure as Code for Enterprise Identity Federation Workflows with Cloud IAM and Service Directory

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Enterprise Identity Federation Workflows with Cloud IAM and Service Directory".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured (or Cloud Shell)
- Appropriate IAM permissions for resource creation:
  - Owner or Security Admin role
  - IAM Workload Identity Pool Admin
  - Service Directory Admin
  - Secret Manager Admin
  - Cloud Functions Admin
- External identity provider (OIDC or SAML) for testing federation
- Basic understanding of identity federation concepts and OAuth 2.0

## Project Configuration

Before deploying, set up your environment:

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Configure gcloud
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Enable required APIs
gcloud services enable iamcredentials.googleapis.com
gcloud services enable sts.googleapis.com
gcloud services enable servicedirectory.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable dns.googleapis.com
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for managing infrastructure as code with native integration and state management.

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/enterprise-identity-federation \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars" \
    --labels="environment=production,recipe=identity-federation"

# Check deployment status
gcloud infra-manager deployments describe \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/enterprise-identity-federation
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem support.

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the execution plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI control with step-by-step deployment visibility.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Check deployment status
gcloud iam workload-identity-pools list --location=global
gcloud service-directory namespaces list --location=${REGION}
```

## Configuration Options

### Terraform Variables

The Terraform implementation supports the following variables (defined in `terraform/variables.tf`):

- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `environment`: Environment label (default: production)
- `workload_identity_pool_id`: Custom pool ID (auto-generated if not specified)
- `external_idp_issuer`: External identity provider issuer URL
- `allowed_audiences`: List of allowed audiences for token exchange
- `service_account_roles`: List of IAM roles for the federation service account

### Infrastructure Manager Inputs

Configure deployment through `infrastructure-manager/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
environment = "production"
external_idp_issuer = "https://token.actions.githubusercontent.com"
allowed_audiences = ["sts.googleapis.com"]
```

## Deployed Resources

This infrastructure creates the following Google Cloud resources:

### Identity Federation
- Workload Identity Pool for enterprise federation
- OIDC provider configuration with attribute mapping
- Service accounts with federated access permissions
- IAM bindings for workload identity impersonation

### Service Discovery
- Service Directory namespace for enterprise services
- Service registrations with metadata annotations
- DNS zone for service discovery integration
- Cloud DNS records for service resolution

### Automation & Security
- Cloud Function for automated identity provisioning
- Secret Manager secrets for configuration storage
- IAM roles and policies for least-privilege access
- Cloud Function source code and deployment

### Estimated Costs

- Service Directory: ~$0.50/month per service
- Cloud Functions: ~$0.40/month per 1M invocations
- Secret Manager: ~$0.06/month per secret version
- Cloud DNS: ~$0.50/month per zone
- Workload Identity Federation: No additional charges

## Validation

After deployment, validate the infrastructure:

```bash
# Check Workload Identity Pool
gcloud iam workload-identity-pools describe ${WI_POOL_ID} \
    --location=global \
    --format="table(name,state,displayName)"

# Verify Service Directory services
gcloud service-directory services list \
    --namespace=${NAMESPACE_NAME} \
    --location=${REGION}

# Test Cloud Function
FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
    --format="value(httpsTrigger.url)")

curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{"identity": "test@example.com", "service": "user-management"}'

# Validate DNS resolution
nslookup user-mgmt.services.${PROJECT_ID}.internal
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    projects/${PROJECT_ID}/locations/${REGION}/deployments/enterprise-identity-federation \
    --delete-policy="DELETE"

# Verify cleanup
gcloud infra-manager deployments list \
    --location=${REGION}
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

## Customization

### Extending Identity Providers

To add additional identity providers, modify the Terraform configuration:

```hcl
# Add SAML provider
resource "google_iam_workload_identity_pool_provider" "saml_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.enterprise_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "saml-provider"
  
  saml {
    issuer_uri = "https://your-saml-provider.com"
  }
  
  attribute_mapping = {
    "google.subject" = "assertion.sub"
    "attribute.department" = "assertion.department"
  }
}
```

### Adding Service Registrations

Register additional services in Service Directory:

```hcl
resource "google_service_directory_service" "additional_service" {
  service_id = "additional-service"
  namespace  = google_service_directory_namespace.enterprise_namespace.id
  
  metadata = {
    version     = "v1"
    environment = var.environment
    team        = "platform"
  }
}
```

### Custom Cloud Function Logic

Modify the Cloud Function in `scripts/deploy.sh` or add custom provisioning logic:

```python
# Enhanced provisioning with external API integration
def provision_identity(request):
    # Add custom business logic
    # Integrate with external systems
    # Implement approval workflows
    pass
```

## Security Considerations

### Best Practices Implemented

- **Least Privilege Access**: Service accounts have minimal required permissions
- **Workload Identity Federation**: Eliminates long-lived service account keys
- **Secret Management**: Sensitive configuration stored in Secret Manager
- **Audit Logging**: All operations logged via Cloud Audit Logs
- **Network Security**: Private DNS zones and internal service communication

### Additional Security Enhancements

1. **Conditional Access**: Implement CEL expressions for advanced access control
2. **VPC Service Controls**: Add perimeter protection for sensitive resources
3. **Binary Authorization**: Secure container image deployment for Cloud Functions
4. **Private Google Access**: Ensure secure connectivity without external IPs

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled before deployment
2. **IAM Permissions**: Verify deployment service account has sufficient permissions
3. **DNS Resolution**: Check VPC network configuration for private DNS zones
4. **Function Deployment**: Verify Cloud Build API is enabled for function deployment

### Debug Commands

```bash
# Check API status
gcloud services list --enabled --filter="name:(iam|servicedirectory|secretmanager)"

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check function logs
gcloud functions logs read ${FUNCTION_NAME} --limit=50

# Test service discovery
gcloud service-directory services resolve ${SERVICE_NAME} \
    --namespace=${NAMESPACE_NAME} \
    --location=${REGION}
```

## Support

For issues with this infrastructure code:

1. Check the [original recipe documentation](../enterprise-identity-federation-workflows-iam-service-directory.md)
2. Review [Google Cloud IAM documentation](https://cloud.google.com/iam/docs/workload-identity-federation)
3. Consult [Service Directory documentation](https://cloud.google.com/service-directory/docs)
4. Review [Cloud Functions documentation](https://cloud.google.com/functions/docs)

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update variable descriptions and validation
3. Maintain security best practices
4. Update this README with new configuration options
5. Validate all deployment methods work correctly

## Version History

- v1.0: Initial implementation with Workload Identity Federation and Service Directory
- Infrastructure Manager, Terraform, and Bash script implementations
- Support for OIDC providers and automated provisioning workflows