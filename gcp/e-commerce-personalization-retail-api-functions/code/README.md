# Infrastructure as Code for E-commerce Personalization with Retail API and Cloud Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "E-commerce Personalization with Retail API and Cloud Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Architecture Overview

This solution creates an intelligent e-commerce personalization engine that combines:

- **Vertex AI Search for Commerce (Retail API)**: Machine learning-powered product recommendations
- **Cloud Functions**: Serverless functions for catalog sync, user event tracking, and recommendation serving
- **Cloud Firestore**: NoSQL database for user profile storage
- **Cloud Storage**: Object storage for product catalog data
- **IAM**: Identity and access management for secure service integration

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate permissions for:
  - Cloud Functions (Cloud Functions Admin)
  - Retail API (Retail API Admin)
  - Cloud Storage (Storage Admin)
  - Cloud Firestore (Datastore Owner)
  - IAM (Service Account Admin)
- Node.js 20.x (for local development and testing)
- Terraform 1.5+ (if using Terraform implementation)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's native infrastructure as code service that provides a managed way to deploy and manage resources.

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to the Infrastructure Manager directory
cd infrastructure-manager/

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/ecommerce-personalization \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="main.yaml"
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with state tracking and change planning.

```bash
# Navigate to the Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan

# Apply the infrastructure
terraform apply
```

### Using Bash Scripts

The bash scripts provide a simple, automated deployment approach that mirrors the original recipe steps.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh

# Follow the prompts to configure your deployment
```

## Configuration

### Infrastructure Manager Configuration

The Infrastructure Manager deployment uses a YAML configuration file with the following customizable parameters:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `bucket_name`: Cloud Storage bucket name for product catalogs
- `firestore_location`: Firestore database location

### Terraform Configuration

Customize the deployment by modifying `terraform/variables.tf` or creating a `terraform.tfvars` file:

```hcl
# terraform.tfvars
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional: Custom bucket name (will be auto-generated if not provided)
bucket_name = "your-custom-bucket-name"

# Optional: Firestore location
firestore_location = "us-central1"
```

### Bash Script Configuration

The bash scripts use environment variables for configuration:

```bash
# Required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Optional: Custom bucket name
export BUCKET_NAME="your-custom-bucket-name"
```

## Testing the Deployment

After deployment, you can test the e-commerce personalization system:

### 1. Load Sample Product Data

```bash
# Get the catalog sync function URL
CATALOG_FUNCTION_URL=$(gcloud functions describe catalog-sync \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

# Load sample products
curl -X POST ${CATALOG_FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "products": [
            {
                "id": "product_001",
                "title": "Wireless Bluetooth Headphones",
                "categories": ["Electronics", "Audio", "Headphones"],
                "price": 99.99,
                "currencyCode": "USD",
                "availability": "IN_STOCK"
            }
        ]
    }'
```

### 2. Track User Events

```bash
# Get the user events function URL
EVENTS_FUNCTION_URL=$(gcloud functions describe track-user-events \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

# Track a user event
curl -X POST ${EVENTS_FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "userId": "user_123",
        "eventType": "detail-page-view",
        "productId": "product_001"
    }'
```

### 3. Get Recommendations

```bash
# Get the recommendations function URL
RECOMMENDATIONS_FUNCTION_URL=$(gcloud functions describe get-recommendations \
    --region=${REGION} \
    --format="value(serviceConfig.uri)")

# Get personalized recommendations
curl -X POST ${RECOMMENDATIONS_FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "userId": "user_123",
        "pageType": "home-page"
    }' | jq '.'
```

## Monitoring and Observability

### Cloud Functions Monitoring

```bash
# View function logs
gcloud functions logs read catalog-sync --region=${REGION} --limit=50

# Monitor function metrics
gcloud functions describe catalog-sync --region=${REGION} \
    --format="value(serviceConfig.availableMemoryMb,serviceConfig.timeoutSeconds)"
```

### Retail API Monitoring

```bash
# List products in the catalog
gcloud retail products list \
    --catalog="projects/${PROJECT_ID}/locations/global/catalogs/default_catalog" \
    --branch="default_branch" \
    --limit=10
```

### Firestore Data Verification

```bash
# Export user profiles to Cloud Storage for analysis
gcloud firestore export gs://${BUCKET_NAME}/firestore-export \
    --collection-ids=user_profiles
```

## Cost Optimization

### Estimated Monthly Costs

- **Cloud Functions**: $0.40 per 1M requests + $0.0000025 per GB-second
- **Retail API**: $0.75 per 1,000 prediction requests
- **Cloud Firestore**: $0.18 per 100K document reads
- **Cloud Storage**: $0.020 per GB stored

### Cost Optimization Tips

1. **Function Memory**: Adjust Cloud Function memory allocation based on usage patterns
2. **Retail API**: Use batch operations for catalog updates to reduce API calls
3. **Firestore**: Optimize queries and implement proper indexing
4. **Storage**: Use lifecycle policies to automatically delete old data

## Security Considerations

### IAM Best Practices

- Each Cloud Function uses a dedicated service account with minimal permissions
- Cross-service authentication uses workload identity
- No hardcoded credentials in function code

### Data Protection

- All data is encrypted at rest and in transit
- User data in Firestore follows data minimization principles
- Recommendation data includes privacy-preserving techniques

### Network Security

- Cloud Functions are deployed with private connectivity options
- VPC connectors can be configured for additional network isolation
- Cloud Storage buckets use uniform bucket-level access

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**
   ```bash
   # Check function deployment status
   gcloud functions describe FUNCTION_NAME --region=${REGION}
   
   # View deployment logs
   gcloud functions logs read FUNCTION_NAME --region=${REGION}
   ```

2. **Retail API Errors**
   ```bash
   # Verify API is enabled
   gcloud services list --enabled --filter="retail.googleapis.com"
   
   # Check catalog status
   gcloud retail products list --catalog="projects/${PROJECT_ID}/locations/global/catalogs/default_catalog"
   ```

3. **Firestore Connection Issues**
   ```bash
   # Verify Firestore is initialized
   gcloud firestore databases describe --database="(default)"
   ```

### Debug Mode

Enable debug logging in Cloud Functions:

```bash
# Update function with debug environment variable
gcloud functions deploy FUNCTION_NAME \
    --region=${REGION} \
    --set-env-vars="DEBUG=true"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/ecommerce-personalization
```

### Using Terraform

```bash
# Navigate to the Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm destruction when prompted
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Follow the prompts to confirm resource deletion
```

### Manual Cleanup Verification

```bash
# Verify all resources are deleted
gcloud functions list --regions=${REGION}
gcloud retail products list --catalog="projects/${PROJECT_ID}/locations/global/catalogs/default_catalog"
gsutil ls gs://${BUCKET_NAME}
gcloud firestore databases list
```

## Development and Customization

### Local Development

To modify the Cloud Functions locally:

1. **Install dependencies**:
   ```bash
   cd terraform/function-templates/
   npm install @google-cloud/retail @google-cloud/firestore @google-cloud/storage
   ```

2. **Test functions locally**:
   ```bash
   # Use the Functions Framework for local testing
   npm install -g @google-cloud/functions-framework
   functions-framework --target=syncCatalog --source=. --port=8080
   ```

3. **Deploy updated functions**:
   ```bash
   # Redeploy with Terraform
   cd ../
   terraform apply
   ```

### Extending the Solution

1. **Add new recommendation models**: Modify the Retail API configuration in `main.tf`
2. **Implement A/B testing**: Add Cloud Functions for experiment management
3. **Add analytics**: Integrate BigQuery for advanced analytics
4. **Scale globally**: Deploy across multiple regions using Terraform modules

## API Reference

### Catalog Sync Function

**Endpoint**: `POST /sync-catalog`

**Request Body**:
```json
{
  "products": [
    {
      "id": "string",
      "title": "string",
      "categories": ["string"],
      "price": number,
      "currencyCode": "string",
      "availability": "IN_STOCK|OUT_OF_STOCK"
    }
  ]
}
```

### User Events Function

**Endpoint**: `POST /track-event`

**Request Body**:
```json
{
  "userId": "string",
  "eventType": "detail-page-view|add-to-cart|purchase|search",
  "productId": "string",
  "searchQuery": "string",
  "quantity": number
}
```

### Recommendations Function

**Endpoint**: `POST /get-recommendations`

**Request Body**:
```json
{
  "userId": "string",
  "pageType": "home-page|category-page|product-page",
  "productId": "string",
  "filter": "string"
}
```

## Support and Documentation

- [Original Recipe Documentation](../e-commerce-personalization-retail-api-functions.md)
- [Google Cloud Retail API Documentation](https://cloud.google.com/retail/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

## License

This infrastructure code is provided under the same license as the original recipe.