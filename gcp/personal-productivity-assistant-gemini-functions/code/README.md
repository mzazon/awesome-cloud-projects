# Infrastructure as Code for Personal Productivity Assistant with Gemini and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Personal Productivity Assistant with Gemini and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's recommended infrastructure as code tool (YAML)
- **Terraform**: Multi-cloud infrastructure as code with Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated setup

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Active Google Cloud project with billing enabled
- Following APIs enabled in your project:
  - Cloud Functions API
  - Vertex AI API
  - Firestore API
  - Pub/Sub API
  - Cloud Scheduler API
  - Gmail API
  - Cloud Build API
- Appropriate IAM permissions for resource creation:
  - Cloud Functions Developer
  - Vertex AI User
  - Firestore User
  - Pub/Sub Admin
  - Cloud Scheduler Admin
  - Service Account Admin
- Python 3.9+ for local development and testing
- Basic understanding of OAuth 2.0 authentication flows

### Gmail API Setup

Before deploying, you'll need to set up Gmail API credentials:

1. Go to the [Google Cloud Console API Credentials page](https://console.cloud.google.com/apis/credentials)
2. Click "Create Credentials" > "OAuth client ID"
3. Choose "Desktop application" as the application type
4. Download the credentials JSON file
5. Save it as `credentials.json` in your local environment

### Cost Estimation

Estimated monthly costs for testing and development:
- Cloud Functions: $5-10 (based on execution time and memory usage)
- Vertex AI API calls: $10-15 (Gemini 2.5 Flash is cost-optimized)
- Firestore: $1-3 (document reads/writes and storage)
- Pub/Sub: $1-2 (message processing)
- Cloud Scheduler: <$1 (scheduled job executions)
- **Total estimated cost**: $15-25/month for moderate usage

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

Infrastructure Manager is Google Cloud's native IaC solution that provides state management and deployment orchestration.

```bash
# Set your project ID and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Set default project
gcloud config set project ${PROJECT_ID}

# Deploy infrastructure
gcloud infra-manager deployments apply \
    --location=${REGION} \
    --service-account="$(gcloud config get-value project)@cloudservices.gserviceaccount.com" \
    --deployment-name="productivity-assistant" \
    --template-file="infrastructure-manager/main.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe \
    --location=${REGION} \
    --deployment="productivity-assistant"
```

### Using Terraform

Terraform provides cross-cloud compatibility and advanced state management features.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan -var="project_id=your-project-id" \
                -var="region=us-central1"

# Apply the infrastructure
terraform apply -var="project_id=your-project-id" \
                 -var="region=us-central1"

# View outputs
terraform output
```

### Using Bash Scripts

For automated deployment with minimal configuration:

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
./scripts/deploy.sh

# The script will:
# 1. Enable required APIs
# 2. Create IAM service accounts
# 3. Deploy Cloud Functions
# 4. Set up Pub/Sub topics
# 5. Create Firestore database
# 6. Configure Cloud Scheduler jobs
```

## Architecture Overview

The deployed infrastructure includes:

1. **Cloud Functions**:
   - `email-processor`: HTTP function for processing emails with Gemini AI
   - `scheduled-email-processor`: Event-driven function for scheduled processing

2. **Vertex AI Integration**:
   - Gemini 2.5 Flash model for intelligent email analysis
   - Function calling capabilities for structured outputs

3. **Data Storage**:
   - Firestore database for storing analysis results and action items
   - Cloud Storage bucket for temporary file storage (if needed)

4. **Event Processing**:
   - Pub/Sub topic for asynchronous email processing
   - Cloud Scheduler for periodic email checks

5. **Security**:
   - Service accounts with least privilege access
   - OAuth 2.0 integration for Gmail API access
   - Encrypted data transmission and storage

## Configuration

### Terraform Variables

Key variables you can customize in `terraform/variables.tf`:

```hcl
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "function_memory" {
  description = "Memory allocation for Cloud Functions"
  type        = string
  default     = "1Gi"
}

variable "function_timeout" {
  description = "Timeout for Cloud Functions"
  type        = number
  default     = 300
}

variable "schedule_frequency" {
  description = "Cron schedule for email processing"
  type        = string
  default     = "*/15 * * * *"  # Every 15 minutes
}
```

### Environment Variables

The Cloud Functions use these environment variables:

- `GCP_PROJECT`: Your Google Cloud project ID
- `FUNCTION_REGION`: Deployment region
- `FIRESTORE_DATABASE`: Firestore database name (default)

## Post-Deployment Setup

### 1. Gmail API Authentication

After infrastructure deployment, set up Gmail API access:

```bash
# Get the deployed function URL
FUNCTION_URL=$(gcloud functions describe email-processor \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

echo "Function URL: ${FUNCTION_URL}"

# Test the function with sample data
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "email_id": "test-123",
        "subject": "Project Review Meeting",
        "sender": "manager@company.com",
        "body": "Please prepare quarterly reports for next week."
    }'
```

### 2. Set Up Gmail Integration

1. Install the Gmail helper locally:
```bash
cd terraform/function-source/
pip install -r requirements.txt
```

2. Run the Gmail integration helper:
```bash
python3 gmail_integration.py
# Follow the OAuth flow in your browser
```

### 3. Monitor Function Logs

```bash
# View function logs
gcloud functions logs read email-processor \
    --region=${REGION} \
    --limit=50

# Monitor in real-time
gcloud functions logs tail email-processor \
    --region=${REGION}
```

## Validation & Testing

### Test Email Processing Function

```bash
# Test with sample email data
curl -X POST ${FUNCTION_URL} \
    -H "Content-Type: application/json" \
    -d '{
        "email_id": "test-456",
        "subject": "Budget Planning Session",
        "sender": "finance@company.com",
        "body": "We need to finalize the Q2 budget by Friday. Please review the attached spreadsheet and provide your feedback."
    }'
```

Expected response includes:
- Extracted action items with priorities
- Generated email summary
- Suggested reply content

### Verify Firestore Data

```bash
# List Firestore collections
gcloud firestore collections list

# Query email analysis documents
gcloud firestore documents list \
    --collection-id=email_analysis \
    --limit=5
```

### Test Scheduled Processing

```bash
# Manually trigger scheduled job
gcloud scheduler jobs run email-processing-schedule \
    --location=${REGION}

# Check job history
gcloud scheduler jobs describe email-processing-schedule \
    --location=${REGION}
```

## Monitoring & Observability

### Cloud Monitoring Dashboard

The Terraform deployment includes a custom monitoring dashboard (`monitoring/dashboard.json`) that tracks:

- Function execution metrics
- Error rates and latency
- Vertex AI API usage
- Firestore operations
- Pub/Sub message processing

### Key Metrics to Monitor

1. **Function Performance**:
   - Execution time
   - Memory usage
   - Error rate

2. **AI Processing**:
   - Gemini API call success rate
   - Token usage and costs
   - Function calling accuracy

3. **Data Processing**:
   - Email processing volume
   - Firestore read/write operations
   - Pub/Sub message throughput

### Alerting

Set up alerts for:
```bash
# High error rates
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/error-rate-policy.yaml

# Function timeout issues
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/timeout-policy.yaml
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete \
    --location=${REGION} \
    --deployment="productivity-assistant" \
    --quiet
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" \
                   -var="region=us-central1"

# Clean up state files
rm -rf .terraform/ terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# The script will:
# 1. Delete Cloud Functions
# 2. Remove Pub/Sub topics and subscriptions
# 3. Delete Cloud Scheduler jobs
# 4. Clean up Firestore database
# 5. Remove IAM service accounts
```

### Manual Cleanup (if needed)

```bash
# Delete remaining resources
gcloud functions delete email-processor --region=${REGION} --quiet
gcloud functions delete scheduled-email-processor --region=${REGION} --quiet
gcloud pubsub topics delete email-processing-topic
gcloud scheduler jobs delete email-processing-schedule --location=${REGION} --quiet
gcloud firestore databases delete --database="(default)" --quiet
```

## Customization

### Scaling Configuration

Modify function scaling in `terraform/main.tf`:

```hcl
resource "google_cloudfunctions2_function" "email_processor" {
  # ... other configuration

  service_config {
    max_instance_count = 100
    min_instance_count = 0
    available_memory   = "1Gi"
    timeout_seconds    = 300
    
    # Add more CPU for heavy AI workloads
    available_cpu = "1"
  }
}
```

### Security Hardening

1. **Enable VPC Connector** for private network access:
```hcl
resource "google_vpc_access_connector" "connector" {
  name          = "productivity-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  region        = var.region
}
```

2. **Add IAM Conditions** for time-based access:
```hcl
resource "google_project_iam_binding" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  members = [
    "serviceAccount:${google_service_account.function_sa.email}"
  ]
  
  condition {
    title       = "business_hours_only"
    description = "Access only during business hours"
    expression  = "request.time.getHours() >= 8 && request.time.getHours() <= 18"
  }
}
```

### Performance Optimization

1. **Connection Pooling** for Firestore:
```python
# In function code
from google.cloud import firestore
import os

# Use connection pooling
@functions_framework.http
def process_email(request):
    # Reuse client across invocations
    if not hasattr(process_email, 'db_client'):
        process_email.db_client = firestore.Client()
    
    # Your processing logic here
```

2. **Caching** for frequently accessed data:
```python
from functools import lru_cache

@lru_cache(maxsize=128)
def get_user_preferences(user_id):
    # Cache user preferences
    return db.collection('preferences').document(user_id).get()
```

## Troubleshooting

### Common Issues

1. **Function Timeout**:
   - Increase timeout in configuration
   - Optimize Gemini API calls
   - Use async processing for large emails

2. **Authentication Errors**:
   - Verify service account permissions
   - Check OAuth credentials setup
   - Ensure APIs are enabled

3. **Memory Issues**:
   - Increase function memory allocation
   - Optimize data processing logic
   - Use streaming for large datasets

### Debug Commands

```bash
# Check function status
gcloud functions describe email-processor --region=${REGION}

# View detailed logs
gcloud functions logs read email-processor \
    --region=${REGION} \
    --severity=ERROR

# Test connectivity
gcloud functions call email-processor \
    --region=${REGION} \
    --data='{"test": true}'
```

## Support

For issues with this infrastructure code:

1. **Infrastructure Issues**: Check the Terraform/Infrastructure Manager documentation
2. **Function Issues**: Review Cloud Functions logs and monitoring
3. **AI Processing Issues**: Verify Vertex AI quotas and permissions
4. **Gmail Integration**: Check OAuth setup and API credentials

## Additional Resources

- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Vertex AI Gemini Documentation](https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Gmail API Documentation](https://developers.google.com/gmail/api)

## Version History

- **v1.0**: Initial implementation with Gemini 2.5 Flash
- **v1.1**: Added monitoring dashboard and alerting
- **v1.2**: Enhanced security with IAM conditions
- **v1.3**: Performance optimizations and caching