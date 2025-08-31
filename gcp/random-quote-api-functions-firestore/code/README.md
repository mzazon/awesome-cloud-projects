# Infrastructure as Code for Random Quote API with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Random Quote API with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and authenticated
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions (create, deploy, manage)
  - Firestore (create databases, manage data)
  - Service Account management
  - API enablement (Cloud Functions API, Firestore API)
- Node.js 18+ installed for function development
- Terraform CLI installed (for Terraform deployment option)

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended infrastructure as code solution that provides native integration with Google Cloud services.

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/random-quote-api \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="infrastructure-manager/" \
    --inputs-file="infrastructure-manager/inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/random-quote-api
```

### Using Terraform

Terraform provides declarative infrastructure management with support for multiple cloud providers and extensive ecosystem of modules.

```bash
# Navigate to Terraform directory
cd terraform/

# Set required variables (create terraform.tfvars file)
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
database_id = "quotes-db"
function_name = "random-quote-api"
EOF

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide a procedural deployment approach that closely follows the original recipe steps with enhanced automation and error handling.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh

# Test the deployed API
curl -X GET "$(gcloud functions describe random-quote-api --region=${REGION} --format='value(httpsTrigger.url)')"
```

## Architecture Overview

The infrastructure provisions:

- **Cloud Functions**: Serverless HTTP function for handling API requests
- **Firestore Database**: NoSQL document database for storing quotes
- **IAM Service Accounts**: Secure identity for function execution
- **API Enablement**: Required Google Cloud APIs (Cloud Functions, Firestore)
- **Sample Data**: Pre-populated quotes collection in Firestore

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml` to customize:

```yaml
project_id: "your-project-id"
region: "us-central1"
database_id: "quotes-db"
function_name: "random-quote-api"
function_memory: "256Mi"
function_timeout: "60s"
node_version: "20"
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or use CLI flags:

```hcl
project_id = "your-project-id"
region = "us-central1"
database_id = "quotes-db"
function_name = "random-quote-api"
function_memory = 256
function_timeout = 60
node_version = "20"
enable_sample_data = true
```

### Bash Script Environment Variables

Set before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DATABASE_ID="quotes-db"
export FUNCTION_NAME="random-quote-api"
export FUNCTION_MEMORY="256MB"
export FUNCTION_TIMEOUT="60s"
```

## Testing the Deployment

After successful deployment, test the API functionality:

```bash
# Get the function URL
FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME:-random-quote-api} \
    --region=${REGION:-us-central1} \
    --format="value(httpsTrigger.url)")

# Test the random quote endpoint
curl -X GET "${FUNCTION_URL}" \
    -H "Accept: application/json" | jq '.'

# Test multiple requests to verify randomness
for i in {1..5}; do
    echo "Request $i:"
    curl -s "${FUNCTION_URL}" | jq '.quote'
    echo ""
done
```

Expected response format:
```json
{
  "id": "document-id-string",
  "quote": "The only way to do great work is to love what you do.",
  "author": "Steve Jobs",
  "category": "motivation",
  "timestamp": "2025-01-12T10:30:00.000Z"
}
```

## Monitoring and Logging

Monitor the deployed infrastructure:

```bash
# View function logs
gcloud functions logs read ${FUNCTION_NAME:-random-quote-api} \
    --region=${REGION:-us-central1} \
    --limit=20

# Check function metrics
gcloud functions describe ${FUNCTION_NAME:-random-quote-api} \
    --region=${REGION:-us-central1}

# Monitor Firestore operations
gcloud logging read "resource.type=firestore_database" \
    --project=${PROJECT_ID} \
    --limit=10
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the Infrastructure Manager deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/random-quote-api

# Verify cleanup
gcloud infra-manager deployments list --project=${PROJECT_ID}
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before destroying resources
# and provide cleanup verification
```

## Cost Optimization

This solution is designed to minimize costs through:

- **Serverless Architecture**: Pay only for actual function invocations
- **Free Tier Usage**: Both Cloud Functions and Firestore offer generous free tiers
- **Efficient Resource Sizing**: Minimal memory allocation (256MB) for lightweight workloads
- **No Always-On Resources**: Zero cost when not in use

Estimated monthly costs for light usage (< 1000 requests/month):
- Cloud Functions: $0.00 (within free tier)
- Firestore: $0.00 (within free tier)
- Total: $0.00

## Security Considerations

The infrastructure implements security best practices:

- **Least Privilege IAM**: Function service account has minimal required permissions
- **HTTPS Enforcement**: All API traffic encrypted in transit
- **No Public Database Access**: Firestore accessible only through authenticated service accounts
- **CORS Configuration**: Proper cross-origin resource sharing settings
- **Input Validation**: Function includes error handling and input sanitization

## Troubleshooting

### Common Issues

1. **Function Deployment Fails**
   ```bash
   # Check function logs
   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}
   
   # Verify API enablement
   gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com"
   ```

2. **Firestore Connection Errors**
   ```bash
   # Verify database exists
   gcloud firestore databases describe ${DATABASE_ID}
   
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Empty Quote Response**
   ```bash
   # Verify sample data was populated
   gcloud firestore export gs://${PROJECT_ID}-backup --collection-ids=quotes
   ```

### Debug Mode

Enable debug logging in bash scripts:
```bash
export DEBUG=true
./scripts/deploy.sh
```

## Customization

### Adding New Quotes

```bash
# Add quotes via CLI
gcloud firestore documents create --collection=quotes --data='{
  "text": "Your custom quote here",
  "author": "Author Name",
  "category": "inspiration"
}'
```

### Extending the API

Modify the function source code in the deployment to add new endpoints:
- GET `/quotes/category/{category}` - Filter by category
- POST `/quotes` - Add new quotes
- GET `/quotes/author/{author}` - Filter by author

### Performance Tuning

Adjust function configuration for higher traffic:
```yaml
# Infrastructure Manager
function_memory: "512Mi"
function_max_instances: 100
function_min_instances: 1
```

## Support

For issues with this infrastructure code:

1. **Recipe Documentation**: Refer to the original recipe at `../random-quote-api-functions-firestore.md`
2. **Google Cloud Documentation**: 
   - [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
   - [Firestore Documentation](https://cloud.google.com/firestore/docs)
   - [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
3. **Terraform Provider Documentation**: [Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12
- **Infrastructure Manager**: Compatible with latest Google Cloud APIs
- **Terraform**: Requires Google Provider >= 4.0
- **Node.js Runtime**: 20 (Cloud Functions supported runtime)

---

*This infrastructure code was generated automatically based on the cloud recipe specifications. For the most up-to-date deployment instructions, refer to the original recipe documentation.*