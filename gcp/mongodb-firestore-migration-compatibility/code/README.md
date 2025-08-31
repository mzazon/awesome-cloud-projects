# Infrastructure as Code for MongoDB to Firestore Migration with API Compatibility

This directory contains Infrastructure as Code (IaC) implementations for the recipe "MongoDB to Firestore Migration with API Compatibility".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 450.0.0 or later)
- Python 3.9+ development environment for local testing
- Appropriate Google Cloud permissions for resource creation:
  - Firestore Admin
  - Cloud Functions Admin
  - Cloud Build Editor
  - Secret Manager Admin
  - Service Account Admin
- Source MongoDB database with read access credentials
- Estimated cost: $15-25 for tutorial resources (delete after completion)

## Quick Start

### Using Infrastructure Manager (Recommended)

Infrastructure Manager is Google Cloud's managed infrastructure as code service that provides state management and drift detection.

```bash
# Navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create mongodb-migration-deployment \
    --location=us-central1 \
    --source=. \
    --input-values=project_id=YOUR_PROJECT_ID,region=us-central1

# Monitor deployment progress
gcloud infra-manager deployments describe mongodb-migration-deployment \
    --location=us-central1

# Get deployment outputs
gcloud infra-manager deployments describe mongodb-migration-deployment \
    --location=us-central1 \
    --format="value(outputs)"
```

### Using Terraform

```bash
# Navigate to the terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan \
    -var="project_id=YOUR_PROJECT_ID" \
    -var="region=us-central1"

# Apply the configuration
terraform apply \
    -var="project_id=YOUR_PROJECT_ID" \
    -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

The bash scripts provide a simple deployment option that mirrors the original recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export MONGODB_CONNECTION_STRING="mongodb://username:password@host:port/database"

# Deploy the infrastructure
./scripts/deploy.sh

# The script will output the API URLs and deployment status
```

## Configuration

### Environment Variables

All implementations support these configuration variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region for resources | `us-central1` | No |
| `mongodb_connection_string` | MongoDB connection string for migration | - | Yes* |
| `migration_function_memory` | Memory allocation for migration function | `512Mi` | No |
| `api_function_memory` | Memory allocation for API function | `256Mi` | No |
| `migration_timeout` | Timeout for migration function | `540s` | No |

*Required for bash script deployment. Infrastructure Manager and Terraform will prompt for the connection string during deployment.

### Customization Options

#### Firestore Configuration
- Database region (must match other resources)
- Database name (defaults to "(default)")

#### Cloud Functions Configuration
- Runtime version (defaults to Python 3.12)
- Memory allocation
- Timeout settings
- Environment variables

#### Security Configuration
- Secret Manager secret names
- IAM roles and permissions
- Function authentication settings

## Deployment Architecture

The infrastructure creates the following resources:

1. **Firestore Database**: Native mode NoSQL database
2. **Secret Manager Secret**: Secure storage for MongoDB credentials
3. **Migration Function**: Serverless function for data migration
4. **Compatibility API Function**: MongoDB-compatible REST API
5. **IAM Roles**: Service accounts and permissions
6. **Cloud Build Configuration**: Automated migration pipeline

## Post-Deployment Steps

After successful deployment, complete these steps:

1. **Store MongoDB Credentials** (if not done during deployment):
   ```bash
   echo "mongodb://username:password@host:port/database" | \
       gcloud secrets create mongodb-connection-string --data-file=-
   ```

2. **Test the Migration Function**:
   ```bash
   # Get migration function URL
   MIGRATION_URL=$(gcloud functions describe migrate-mongodb-collection \
       --format="value(serviceConfig.uri)")
   
   # Test with sample collection
   curl -X POST "${MIGRATION_URL}" \
       -H "Content-Type: application/json" \
       -d '{"collection": "test_collection", "batch_size": 10}'
   ```

3. **Test the Compatibility API**:
   ```bash
   # Get API function URL
   API_URL=$(gcloud functions describe mongo-compatibility-api \
       --format="value(serviceConfig.uri)")
   
   # Test document insertion
   curl -X POST "${API_URL}" \
       -H "Content-Type: application/json" \
       -d '{"collection": "test_users", "documents": {"name": "Test User"}}'
   ```

4. **Execute Migration Pipeline**:
   ```bash
   # Run the Cloud Build migration pipeline
   gcloud builds submit --config cloudbuild.yaml
   ```

## Validation and Testing

### Verify Resource Creation

```bash
# Check Firestore database
gcloud firestore databases list

# Verify Cloud Functions
gcloud functions list --filter="name:migrate-mongodb-collection OR name:mongo-compatibility-api"

# Check Secret Manager
gcloud secrets list --filter="name:mongodb-connection-string"

# Verify IAM permissions
gcloud projects get-iam-policy $PROJECT_ID
```

### Test Migration Functionality

```bash
# Test migration function
MIGRATION_URL=$(terraform output -raw migration_function_url)
curl -X POST "${MIGRATION_URL}" \
    -H "Content-Type: application/json" \
    -d '{"collection": "users", "batch_size": 100}'

# Test compatibility API
API_URL=$(terraform output -raw compatibility_api_url)
curl -X GET "${API_URL}?collection=users&limit=5"
```

### Monitor Deployment

```bash
# Check Cloud Function logs
gcloud functions logs read migrate-mongodb-collection --limit=50

# Monitor Firestore usage
gcloud logging read "resource.type=firestore_database" --limit=20

# View Cloud Build history
gcloud builds list --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete mongodb-migration-deployment \
    --location=us-central1 \
    --delete-policy=DELETE

# Verify deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=YOUR_PROJECT_ID" \
    -var="region=us-central1"

# Clean up state files
rm terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

### Manual Cleanup

If automated cleanup fails, manually remove resources:

```bash
# Delete Cloud Functions
gcloud functions delete migrate-mongodb-collection --quiet
gcloud functions delete mongo-compatibility-api --quiet

# Delete secrets
gcloud secrets delete mongodb-connection-string --quiet

# Delete Firestore data (optional - keep if migrating real data)
# Note: This requires custom script as there's no CLI command

# Clean up local files
rm -rf migration-function compatibility-api cloudbuild.yaml
```

## Troubleshooting

### Common Issues

1. **Firestore Database Creation Failed**:
   - Ensure the project doesn't have Datastore enabled in the same region
   - Check project quotas and billing account
   - Verify the region supports Firestore in Native mode

2. **Cloud Function Deployment Failed**:
   - Check that required APIs are enabled
   - Verify IAM permissions for the service account
   - Review function logs for detailed error messages

3. **Secret Manager Access Denied**:
   - Ensure the Cloud Functions service account has Secret Manager access
   - Verify the secret exists and is in the correct project
   - Check IAM policy bindings

4. **Migration Function Timeout**:
   - Increase function timeout in configuration
   - Reduce batch size for large collections
   - Consider splitting large collections into smaller migration jobs

### Debugging Commands

```bash
# Check API enablement
gcloud services list --enabled

# Verify IAM policies
gcloud projects get-iam-policy $PROJECT_ID

# Check Cloud Function details
gcloud functions describe migrate-mongodb-collection

# View detailed logs
gcloud logging read "resource.type=cloud_function" --limit=50

# Test network connectivity
gcloud compute ssh test-instance --command="curl -I https://firestore.googleapis.com"
```

### Support Resources

- [Google Cloud Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [MongoDB Migration Best Practices](https://cloud.google.com/architecture/migrating-mongodb-to-firestore)

## Cost Optimization

### Resource Sizing Recommendations

- **Migration Function**: Use 512Mi memory for typical workloads, increase to 1Gi for large collections
- **API Function**: Use 256Mi memory for development, consider 512Mi for production workloads
- **Function Timeout**: Set based on largest collection size, typically 540s for migration

### Cost Monitoring

```bash
# Enable billing export
gcloud billing accounts list
gcloud billing projects link $PROJECT_ID --billing-account=BILLING_ACCOUNT_ID

# Monitor function invocations
gcloud logging read "resource.type=cloud_function" --format="value(timestamp,severity)"

# Check Firestore usage
gcloud logging read "resource.type=firestore_database" --format="value(operation.first,operation.last)"
```

## Security Considerations

### Best Practices Implemented

1. **Credential Management**: MongoDB credentials stored in Secret Manager with encryption
2. **Least Privilege**: IAM roles follow principle of least privilege
3. **Network Security**: Functions use Google's secure network infrastructure
4. **Audit Logging**: All operations logged to Cloud Logging

### Additional Security Measures

```bash
# Enable audit logging
gcloud logging sinks create audit-sink \
    bigquery.googleapis.com/projects/$PROJECT_ID/datasets/audit_logs \
    --log-filter="protoPayload.serviceName=firestore.googleapis.com"

# Set up VPC connector (optional for enhanced security)
gcloud compute networks vpc-access connectors create mongodb-connector \
    --region=$REGION \
    --subnet=default \
    --subnet-project=$PROJECT_ID
```

## Integration Examples

### Application Integration

See the `application-integration.py` file created during deployment for examples of integrating your application with the compatibility API.

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
name: Deploy MongoDB Migration
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: google-github-actions/setup-gcloud@v1
    - name: Deploy Infrastructure
      run: |
        cd terraform/
        terraform init
        terraform apply -auto-approve
```

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud's documentation.