# Infrastructure as Code for Email Automation with Vertex AI Agent Builder and MCP

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Email Automation with Vertex AI Agent Builder and MCP".

## Available Implementations

- **Infrastructure Manager**: Google Cloud native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud CLI (gcloud) installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Vertex AI API
  - Cloud Functions
  - Gmail API
  - Pub/Sub
  - Secret Manager
  - Cloud Resource Manager

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager enabled
- `gcloud components install config-connector` (if using Config Connector resources)

#### Terraform
- Terraform >= 1.0 installed
- Google Cloud provider credentials configured

#### Bash Scripts
- bash shell environment
- curl and jq utilities installed
- Python 3.11+ for local development and testing

### Required APIs
The following APIs must be enabled in your Google Cloud project:
```bash
gcloud services enable aiplatform.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable gmail.googleapis.com
gcloud services enable secretmanager.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable pubsub.googleapis.com
```

## Architecture Overview

This infrastructure deploys:
- **Vertex AI Agent Builder**: AI agent for email processing and context understanding
- **Cloud Functions**: Serverless functions for webhook processing, MCP integration, response generation, and workflow orchestration
- **Pub/Sub**: Message queue for Gmail API notifications and event processing
- **IAM Service Accounts**: Secure authentication and authorization
- **Secret Manager**: Secure storage for API keys and configuration

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended approach for infrastructure as code.

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy infrastructure
gcloud infra-manager deployments create email-automation-deployment \
    --location=${REGION} \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo.git" \
    --git-source-directory="gcp/email-automation-agent-builder-mcp/code/infrastructure-manager" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe email-automation-deployment \
    --location=${REGION}
```

### Using Terraform

Terraform provides cross-cloud compatibility and extensive provider ecosystem.

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Verify deployment
terraform output
```

### Using Bash Scripts

Bash scripts provide direct CLI commands for step-by-step deployment.

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Follow prompts to configure project settings
# Script will validate prerequisites and deploy all components

# Verify deployment
./scripts/verify.sh
```

## Configuration

### Environment Variables

Set these environment variables before deployment:

```bash
export PROJECT_ID="your-project-id"           # Your Google Cloud project ID
export REGION="us-central1"                   # Deployment region
export GMAIL_USER="user@domain.com"           # Gmail user for API access (optional)
export MCP_CONFIG_PATH="./mcp-config.json"    # Path to MCP configuration (optional)
```

### Customizable Parameters

#### Infrastructure Manager Variables
- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `function_memory`: Memory allocation for Cloud Functions (default: 512Mi)
- `function_timeout`: Timeout for Cloud Functions (default: 60s)

#### Terraform Variables
- `project_id`: Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `zone`: Deployment zone (default: us-central1-a)
- `environment`: Environment name (default: development)
- `labels`: Resource labels for cost tracking and organization

### Gmail API Setup

After infrastructure deployment, configure Gmail API push notifications:

1. **Enable Gmail API** in your Google Cloud project
2. **Create OAuth 2.0 credentials** for Gmail API access
3. **Configure push notifications** to the deployed Pub/Sub topic:
   ```bash
   # Get the Pub/Sub topic name from deployment outputs
   TOPIC_NAME=$(terraform output -raw pubsub_topic_name)
   
   # Configure Gmail push notifications (requires Gmail API client)
   # This step typically requires a Gmail API client application
   ```

## Post-Deployment Configuration

### MCP Server Configuration

1. **Update MCP configuration** with your enterprise data sources:
   ```bash
   # Edit MCP configuration
   cd mcp-config/
   vim mcp-server.json
   ```

2. **Deploy MCP updates** to the integration function:
   ```bash
   # Redeploy MCP integration function with updated config
   ./scripts/update-mcp-config.sh
   ```

### Testing the Deployment

1. **Test MCP integration**:
   ```bash
   # Get function URL
   MCP_URL=$(gcloud functions describe mcp-integration --region=${REGION} --format="value(serviceConfig.uri)")
   
   # Test customer info retrieval
   curl -X POST ${MCP_URL} \
       -H "Content-Type: application/json" \
       -d '{"tool": "get_customer_info", "parameters": {"email": "test@example.com"}}'
   ```

2. **Test email workflow**:
   ```bash
   # Get workflow function URL
   WORKFLOW_URL=$(gcloud functions describe email-workflow --region=${REGION} --format="value(serviceConfig.uri)")
   
   # Test complete workflow
   curl -X POST ${WORKFLOW_URL} \
       -H "Content-Type: application/json" \
       -d '{
         "email_data": {
           "subject": "Test Support Request",
           "content": "I need help with my account",
           "sender_email": "customer@example.com",
           "timestamp": "2025-07-23T10:00:00Z"
         }
       }'
   ```

## Monitoring and Maintenance

### Cloud Logging

View function logs:
```bash
# View workflow logs
gcloud logs read "resource.type=cloud_function AND resource.labels.function_name=email-workflow" --limit=50

# View MCP integration logs
gcloud logs read "resource.type=cloud_function AND resource.labels.function_name=mcp-integration" --limit=50
```

### Performance Monitoring

Monitor function performance:
```bash
# Check function metrics
gcloud functions describe email-workflow --region=${REGION} --format="table(serviceConfig.availableMemory,serviceConfig.timeout)"

# View function execution metrics in Cloud Console
echo "Visit: https://console.cloud.google.com/functions/list?project=${PROJECT_ID}"
```

### Cost Monitoring

Track deployment costs:
```bash
# View current month costs
gcloud billing budgets list --billing-account=YOUR_BILLING_ACCOUNT

# Set up budget alerts (recommended)
gcloud billing budgets create \
    --billing-account=YOUR_BILLING_ACCOUNT \
    --display-name="Email Automation Budget" \
    --budget-amount=50USD
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete email-automation-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Confirm destruction
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Confirm when prompted
# Script will remove all deployed resources in reverse order
```

### Manual Cleanup Verification

Verify all resources are removed:
```bash
# Check Cloud Functions
gcloud functions list --regions=${REGION}

# Check Pub/Sub resources
gcloud pubsub topics list
gcloud pubsub subscriptions list

# Check IAM service accounts
gcloud iam service-accounts list --filter="email:email-automation*"

# Check for any remaining resources
gcloud resource-manager operations list --filter="operationType:delete"
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**:
   ```bash
   # Verify required APIs are enabled
   gcloud services list --enabled | grep -E "(aiplatform|cloudfunctions|gmail)"
   
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Function Deployment Failures**:
   ```bash
   # Check function logs for errors
   gcloud logs read "resource.type=cloud_function" --limit=10 --format="table(timestamp,severity,textPayload)"
   ```

3. **Pub/Sub Configuration Issues**:
   ```bash
   # Verify topic and subscription
   gcloud pubsub topics describe gmail-notifications
   gcloud pubsub subscriptions describe gmail-webhook-sub
   ```

### Debug Mode

Enable debug logging:
```bash
# Set debug environment variable
export DEBUG=true

# Redeploy functions with debug logging
./scripts/deploy.sh --debug
```

## Security Considerations

### Secrets Management

- All sensitive configuration is stored in Secret Manager
- Functions use service account authentication
- No hardcoded credentials in source code

### Network Security

- Functions use HTTPS endpoints with authentication
- Pub/Sub uses encrypted message delivery
- IAM roles follow principle of least privilege

### Data Privacy

- Email content is processed in memory only
- No persistent storage of email data
- Customer data access is logged and auditable

## Support and Documentation

### Additional Resources

- [Vertex AI Agent Builder Documentation](https://cloud.google.com/vertex-ai/docs/agent-builder)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Gmail API Documentation](https://developers.google.com/gmail/api)
- [Model Context Protocol Specification](https://modelcontextprotocol.org/)

### Getting Help

1. **Check the logs** first using the monitoring commands above
2. **Review the original recipe** for step-by-step implementation details
3. **Consult Google Cloud documentation** for service-specific issues
4. **Use Google Cloud Support** for production deployment assistance

### Cost Estimation

Expected monthly costs for moderate usage (1000 emails/month):
- Cloud Functions: $5-10
- Vertex AI Agent Builder: $15-25
- Pub/Sub: $1-3
- Secret Manager: $1-2
- **Total estimated cost: $22-40/month**

Costs may vary based on:
- Email volume and complexity
- Function execution time and memory usage
- Vertex AI model usage and calls
- Data egress and storage

For production workloads, consider implementing cost controls and monitoring through Google Cloud billing alerts and budgets.