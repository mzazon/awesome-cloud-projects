# Infrastructure as Code for Persistent AI Customer Support with Agent Engine Memory

This directory contains Terraform Infrastructure as Code (IaC) implementation for the recipe "Persistent AI Customer Support with Agent Engine Memory" on Google Cloud Platform.

## Architecture Overview

This solution deploys an intelligent customer support system that combines:
- **Vertex AI Gemini** for natural language generation and understanding
- **Firestore** for persistent conversation memory storage
- **Cloud Functions** for serverless orchestration and API endpoints
- **Cloud Storage** for function source code storage
- **IAM and Security** for proper access controls

## Infrastructure Components

### Core Services
- **Firestore Database**: Native mode database for storing conversation history and customer context
- **Cloud Functions**: Two serverless functions for memory retrieval and AI chat processing
- **Vertex AI**: Gemini model integration for generating contextual responses
- **Cloud Storage**: Bucket for storing function source code archives

### Supporting Infrastructure
- **Service Accounts**: Dedicated service account with least-privilege IAM roles
- **API Enablement**: Required Google Cloud APIs automatically enabled
- **Firestore Indexes**: Optimized indexes for efficient conversation queries
- **Monitoring**: Optional Cloud Monitoring and alerting configuration
- **VPC Connector**: Optional VPC connectivity for enhanced security

## Prerequisites

1. **Google Cloud Project**: Active GCP project with billing enabled
2. **Terraform**: Version 1.0 or later
3. **Google Cloud CLI**: Latest version, authenticated with appropriate permissions
4. **Required Permissions**: Project Editor or specific IAM roles:
   - `roles/resourcemanager.projectIamAdmin`
   - `roles/cloudfunctions.admin`
   - `roles/storage.admin`
   - `roles/firestore.admin`
   - `roles/serviceusage.serviceUsageAdmin`

## Quick Start

### 1. Clone and Navigate

```bash
cd gcp/persistent-customer-support-agentcore-memory/code/terraform
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"

# Optional customizations
environment     = "dev"
resource_prefix = "ai-support"

# Function configurations
memory_retrieval_function_config = {
  memory_mb       = 256
  timeout_seconds = 60
  max_instances   = 100
}

chat_function_config = {
  memory_mb       = 512
  timeout_seconds = 300
  max_instances   = 100
}

# Security settings (change for production)
allow_unauthenticated = true
create_service_account = true

# Labels for resource management
labels = {
  project     = "ai-customer-support"
  environment = "development"
  managed_by  = "terraform"
  owner       = "your-team"
}
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

### 6. Verify Deployment

```bash
# Check deployed functions
terraform output testing_endpoints

# Test memory retrieval function
curl -X POST $(terraform output -raw ai_chat_function | jq -r '.url') \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "test-123", "message": "Hello, I need help!"}'
```

## Configuration Options

### Function Configuration

Customize Cloud Function settings:

```hcl
memory_retrieval_function_config = {
  memory_mb        = 256          # Memory allocation (128-8192)
  timeout_seconds  = 60           # Execution timeout (1-540)
  max_instances    = 100          # Maximum concurrent instances
  min_instances    = 0            # Minimum warm instances
  available_cpu    = "1"          # CPU allocation
  ingress_settings = "ALLOW_ALL"  # Network ingress settings
}

chat_function_config = {
  memory_mb        = 512          # Higher memory for AI processing
  timeout_seconds  = 300          # Longer timeout for AI generation
  max_instances    = 100          # Concurrent request handling
  min_instances    = 0            # Cost optimization
}
```

### Vertex AI Configuration

Customize AI model behavior:

```hcl
vertex_ai_config = {
  model_name        = "gemini-1.5-flash"  # Gemini model variant
  max_output_tokens = 1024                # Response length limit
  temperature       = 0.7                 # Creativity level (0.0-1.0)
  top_p            = 0.8                  # Nucleus sampling
}
```

### Security Configuration

Production security settings:

```hcl
# Production security
allow_unauthenticated = false
create_service_account = true
enable_vpc_connector = true

vpc_connector_config = {
  name          = "ai-support-connector"
  ip_cidr_range = "10.8.0.0/28"
  network       = "projects/your-project/global/networks/your-vpc"
}
```

### Monitoring Configuration

Enable comprehensive monitoring:

```hcl
enable_monitoring = true

# Monitoring alerts will be configured for:
# - Function execution errors
# - High latency responses
# - Firestore operation failures
# - Vertex AI quota limits
```

## Outputs

After deployment, Terraform provides comprehensive outputs:

```bash
# View all outputs
terraform output

# Specific output examples
terraform output memory_retrieval_function  # Function details
terraform output ai_chat_function          # Chat function details
terraform output firestore_database_name   # Database information
terraform output testing_endpoints         # Test commands
terraform output validation_commands       # Verification commands
```

## Testing the Deployment

### 1. Test Memory Retrieval Function

```bash
MEMORY_URL=$(terraform output -raw memory_retrieval_function | jq -r '.url')
curl -X POST $MEMORY_URL \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "test-customer-001"}'
```

### 2. Test AI Chat Function

```bash
CHAT_URL=$(terraform output -raw ai_chat_function | jq -r '.url')
curl -X POST $CHAT_URL \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "test-customer-001", "message": "I need help with my order"}'
```

### 3. Test Conversation Memory

```bash
# Send follow-up message to test memory persistence
curl -X POST $CHAT_URL \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "test-customer-001", "message": "Can you help me with that order issue I mentioned?"}'
```

### 4. Verify Firestore Data

```bash
# Check Firestore collections
gcloud firestore collections list --project=$(terraform output -raw project_id)

# Query conversations
gcloud alpha firestore query \
  --collection-path=conversations \
  --limit=5 \
  --project=$(terraform output -raw project_id)
```

## Production Considerations

### Security Hardening

1. **Disable Unauthenticated Access**:
   ```hcl
   allow_unauthenticated = false
   ```

2. **Enable VPC Connector**:
   ```hcl
   enable_vpc_connector = true
   ```

3. **Use Custom Networks**:
   ```hcl
   vpc_connector_config = {
     network = "projects/your-project/global/networks/custom-vpc"
   }
   ```

### Performance Optimization

1. **Scale Configuration**:
   ```hcl
   chat_function_config = {
     memory_mb     = 1024
     min_instances = 5     # Keep warm instances
     max_instances = 500   # Handle traffic spikes
   }
   ```

2. **Firestore Optimization**:
   - Additional indexes for complex queries
   - Regional database for better latency
   - Backup and disaster recovery setup

### Cost Management

1. **Monitor Usage**:
   ```bash
   # Enable cost monitoring
   enable_monitoring = true
   ```

2. **Set Resource Limits**:
   ```hcl
   chat_function_config = {
     max_instances = 50    # Limit concurrent functions
     timeout_seconds = 120 # Shorter timeout for cost control
   }
   ```

3. **Review Outputs**:
   ```bash
   terraform output cost_optimization
   ```

## Troubleshooting

### Common Issues

1. **API Not Enabled**:
   ```bash
   # Check enabled APIs
   gcloud services list --enabled --project=YOUR_PROJECT_ID
   ```

2. **Insufficient Permissions**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy YOUR_PROJECT_ID
   ```

3. **Function Deployment Failures**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --project=YOUR_PROJECT_ID --limit=10
   ```

4. **Firestore Connection Issues**:
   ```bash
   # Verify Firestore database
   gcloud firestore databases describe --database="(default)" --project=YOUR_PROJECT_ID
   ```

### Debug Commands

```bash
# View Terraform state
terraform show

# Check resource status
terraform refresh

# View detailed logs
export TF_LOG=DEBUG
terraform apply
```

## Cleanup

### Complete Infrastructure Removal

```bash
# Destroy all resources
terraform destroy

# Confirm resource deletion
terraform show
```

### Manual Cleanup (if needed)

```bash
# Delete functions
gcloud functions delete FUNCTION_NAME --region=REGION --project=PROJECT_ID

# Delete Firestore database
gcloud firestore databases delete --database="(default)" --project=PROJECT_ID

# Delete storage bucket
gsutil rm -r gs://BUCKET_NAME
```

## Extending the Solution

### Add Sentiment Analysis

```hcl
# Enable Natural Language API
resource "google_project_service" "natural_language" {
  service = "language.googleapis.com"
  project = var.project_id
}

# Update function environment variables
environment_variables = {
  ENABLE_SENTIMENT_ANALYSIS = "true"
}
```

### Add Translation Support

```hcl
# Enable Translation API
resource "google_project_service" "translate" {
  service = "translate.googleapis.com"
  project = var.project_id
}
```

### Add BigQuery Analytics

```hcl
# Create BigQuery dataset for conversation analytics
resource "google_bigquery_dataset" "conversation_analytics" {
  dataset_id = "conversation_analytics"
  project    = var.project_id
  location   = var.region
}
```

## Support and Documentation

- **Recipe Documentation**: See the parent recipe markdown file
- **Terraform Documentation**: [terraform.io](https://terraform.io)
- **Google Cloud Documentation**: [cloud.google.com/docs](https://cloud.google.com/docs)
- **Vertex AI Documentation**: [cloud.google.com/vertex-ai/docs](https://cloud.google.com/vertex-ai/docs)
- **Firestore Documentation**: [cloud.google.com/firestore/docs](https://cloud.google.com/firestore/docs)

## License

This infrastructure code is part of the cloud recipes collection and follows the same licensing terms as the parent project.