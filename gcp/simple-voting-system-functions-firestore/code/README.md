# Infrastructure as Code for Simple Voting System with Cloud Functions and Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Simple Voting System with Cloud Functions and Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Cloud Functions deployment
  - Firestore database creation
  - Service account management
  - API enablement
- Node.js 20+ for local development (if modifying function code)

## Architecture Overview

This solution deploys:
- Cloud Functions (2nd generation) for HTTP endpoints
- Firestore database in Native mode
- Required APIs (Cloud Functions, Firestore, Cloud Build)
- IAM service accounts with least privilege access

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create voting-system-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --gcs-source="gs://your-config-bucket/infrastructure-manager/" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe voting-system-deployment \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will output function URLs for testing
```

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `function_memory`: Memory allocation for functions (default: "256Mi")
- `function_timeout`: Function timeout in seconds (default: 60)
- `firestore_location_id`: Firestore location (default: uses region)

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Deployment region (default: "us-central1")
- `function_memory`: Memory for Cloud Functions (default: 256)
- `function_timeout`: Timeout for functions (default: 60)
- `environment`: Environment label (default: "dev")

### Bash Script Environment Variables

- `PROJECT_ID`: Google Cloud project ID (required)
- `REGION`: Deployment region (default: "us-central1")
- `FUNCTION_NAME`: Base name for functions (auto-generated if not set)

## Testing the Deployment

After successful deployment, test the voting system:

```bash
# Get function URLs (from terraform output or script output)
SUBMIT_URL="https://your-region-your-project.cloudfunctions.net/vote-submit"
RESULTS_URL="https://your-region-your-project.cloudfunctions.net/vote-results"

# Submit a test vote
curl -X POST ${SUBMIT_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "topicId": "test-topic",
      "option": "option-a",
      "userId": "test-user-123"
    }'

# Get voting results
curl "${RESULTS_URL}?topicId=test-topic"

# Test duplicate vote prevention
curl -X POST ${SUBMIT_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "topicId": "test-topic",
      "option": "option-b", 
      "userId": "test-user-123"
    }'
```

## Outputs

All implementations provide the following outputs:

- `vote_submit_function_url`: URL for vote submission endpoint
- `vote_results_function_url`: URL for results retrieval endpoint
- `firestore_database_name`: Name of the created Firestore database
- `project_id`: Google Cloud project ID used
- `region`: Deployment region

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete voting-system-deployment \
    --location=${REGION} \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# Note: Firestore database deletion requires manual confirmation
# Follow the prompts to complete cleanup
```

## Security Considerations

This implementation follows Google Cloud security best practices:

- **IAM**: Functions use service accounts with minimal required permissions
- **HTTPS**: All function endpoints use HTTPS by default
- **CORS**: Configured to allow cross-origin requests for web integration
- **Input Validation**: Functions validate all incoming parameters
- **Data Protection**: Firestore provides encryption at rest and in transit

For production deployments, consider:

- Implementing authentication (Firebase Auth integration)
- Adding rate limiting to prevent abuse
- Setting up Cloud Armor for DDoS protection
- Enabling audit logging for compliance
- Using VPC Service Controls for additional security

## Cost Optimization

The serverless architecture provides automatic cost optimization:

- **Pay-per-use**: Functions only charge for actual invocations
- **Auto-scaling**: Scales to zero when not in use
- **Firestore**: Charges based on operations and storage
- **Free tier**: Both services include generous free usage quotas

Expected costs for typical usage:
- **Development/Testing**: $0-2 USD/month
- **Small production**: $5-20 USD/month  
- **Medium production**: $20-100 USD/month

## Monitoring and Observability

Access built-in monitoring through Google Cloud Console:

```bash
# View function logs
gcloud functions logs read vote-submit --region=${REGION}
gcloud functions logs read vote-results --region=${REGION}

# View function metrics
gcloud functions describe vote-submit --region=${REGION}
```

Key metrics to monitor:
- Function invocation count and duration
- Error rates and types
- Firestore read/write operations
- Database storage usage

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure proper IAM roles are assigned
2. **Function Not Found**: Verify functions deployed successfully
3. **CORS Errors**: Check function CORS configuration
4. **Firestore Errors**: Confirm database is in Native mode

### Debug Commands

```bash
# Check function status
gcloud functions list --filter="name:vote-" --format="table(name,status,trigger.httpsTrigger.url)"

# View function details
gcloud functions describe vote-submit --region=${REGION}

# Check Firestore database
gcloud firestore databases list

# Verify enabled APIs
gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com OR name:firestore.googleapis.com"
```

## Customization

### Adding New Vote Topics

The system supports multiple voting topics. Create new topics by:

1. Using different `topicId` values in vote submissions
2. The system automatically creates collections as needed
3. Results are isolated by topic ID

### Extending Functionality

Consider these enhancements:

- **Real-time Updates**: Add Firestore listeners for live results
- **User Authentication**: Integrate Firebase Auth
- **Analytics**: Connect to BigQuery for advanced reporting
- **Admin Interface**: Build management dashboard
- **Mobile App**: Create Flutter or React Native client

## Development

### Local Development

```bash
# Install Functions Framework
npm install -g @google-cloud/functions-framework

# Run function locally
functions-framework --target=submitVote --port=8080

# Test locally
curl -X POST http://localhost:8080 \
    -H "Content-Type: application/json" \
    -d '{"topicId":"local-test","option":"test-option","userId":"dev-user"}'
```

### Code Structure

```
code/
├── infrastructure-manager/
│   └── main.yaml           # Infrastructure Manager configuration
├── terraform/
│   ├── main.tf            # Main Terraform configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   └── versions.tf        # Provider versions
├── scripts/
│   ├── deploy.sh          # Deployment script
│   └── destroy.sh         # Cleanup script
├── functions/
│   ├── index.js           # Function source code
│   └── package.json       # Node.js dependencies
└── README.md              # This file
```

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud Functions documentation
3. Consult Firestore documentation
4. Visit Google Cloud support resources

## Version Information

- **Recipe Version**: 1.1
- **Last Updated**: 2025-07-12  
- **Terraform Google Provider**: ~> 5.0
- **Infrastructure Manager**: Latest stable
- **Node.js Runtime**: 20

---

*This infrastructure code implements the complete "Simple Voting System with Cloud Functions and Firestore" recipe using Google Cloud best practices and security standards.*