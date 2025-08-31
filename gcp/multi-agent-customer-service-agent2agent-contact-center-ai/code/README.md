# Infrastructure as Code for Multi-Agent Customer Service with Agent2Agent and Contact Center AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Agent Customer Service with Agent2Agent and Contact Center AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 450.0.0 or later)
- Google Cloud project with billing enabled
- Appropriate IAM permissions for the following services:
  - Contact Center AI Platform
  - Vertex AI
  - Cloud Functions
  - Firestore
  - BigQuery
  - Dialogflow
- Terraform installed (version 1.0 or later) - for Terraform deployment
- Basic understanding of conversational AI and multi-agent systems
- Estimated cost: $15-25 USD for testing environment

### Required APIs

The following APIs will be automatically enabled during deployment:

- AI Platform API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Firestore API (`firestore.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Dialogflow API (`dialogflow.googleapis.com`)
- Contact Center AI Platform API (`contactcenteraiplatform.googleapis.com`)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy using Infrastructure Manager
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-agent-ccai \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --git-source-repo="https://github.com/your-repo/infrastructure" \
    --git-source-directory="infrastructure-manager/" \
    --git-source-ref="main" \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=your-project-id" -var="region=us-central1"
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
```

## Architecture Overview

This infrastructure deploys a multi-agent customer service system with the following components:

### Core Services
- **Contact Center AI Platform**: Omnichannel customer interface
- **Vertex AI**: AI/ML platform for agent intelligence
- **Cloud Functions**: Serverless agent logic and orchestration
- **Firestore**: Knowledge base and conversation storage

### Agent Functions
- **Agent Router**: Intelligent routing to specialized agents
- **Message Broker**: Agent2Agent protocol communication
- **Billing Agent**: Specialized billing support
- **Technical Agent**: Technical support expertise
- **Sales Agent**: Sales and product information

### Data Storage
- **Firestore Collections**:
  - `knowledge/`: Agent capabilities and domain expertise
  - `conversations/`: Session context and history
  - `routing_logs/`: Routing decisions and analytics
  - `agent_interactions/`: Individual agent responses
- **BigQuery**: Long-term analytics and reporting

## Configuration Variables

### Infrastructure Manager Variables

```yaml
# infrastructure-manager/variables.yaml
project_id: "your-project-id"
region: "us-central1"
zone: "us-central1-a"
function_memory: "256MB"
function_timeout: "60s"
broker_memory: "512MB"
broker_timeout: "120s"
```

### Terraform Variables

```hcl
# terraform/terraform.tfvars
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
function_memory        = "256MB"
function_timeout      = "60s"
broker_memory        = "512MB"
broker_timeout       = "120s"
enable_audit_logs    = true
```

## Deployment Customization

### Resource Naming

All resources are created with unique suffixes to avoid conflicts:

- Functions: `agent-{random}-{type}` (e.g., `agent-abc123-router`)
- CCAI Instance: `ccai-{random}` (e.g., `ccai-abc123`)
- Storage Bucket: `{project-id}-agent-models`

### Regional Deployment

The infrastructure supports deployment in any Google Cloud region that supports all required services. Update the `region` variable accordingly.

### Memory and Timeout Configuration

Adjust function memory and timeout based on your performance requirements:

- **Router Function**: Default 256MB, 60s timeout
- **Broker Function**: Default 512MB, 120s timeout (higher due to A2A protocol complexity)
- **Agent Functions**: Default 256MB, 60s timeout

## Validation and Testing

After deployment, validate the infrastructure:

### 1. Verify Cloud Functions

```bash
# List deployed functions
gcloud functions list --filter="name:agent-*"

# Test agent router
curl -X POST $(gcloud functions describe agent-*-router --region=${REGION} --format="value(httpsTrigger.url)") \
    -H "Content-Type: application/json" \
    -d '{"message": "I need help with billing", "session_id": "test-001"}'
```

### 2. Verify Firestore Collections

```bash
# Check knowledge base setup
gcloud firestore documents list knowledge

# Verify routing logs
gcloud firestore documents list routing_logs --limit=5
```

### 3. Test Agent2Agent Communication

```bash
# Test message broker functionality
BROKER_URL=$(gcloud functions describe agent-*-broker --region=${REGION} --format="value(httpsTrigger.url)")

curl -X POST ${BROKER_URL} \
    -H "Content-Type: application/json" \
    -d '{
      "source_agent": "billing",
      "target_agent": "technical", 
      "message": "Customer needs technical help",
      "session_id": "test-002",
      "handoff_reason": "escalation"
    }'
```

## Monitoring and Analytics

### Cloud Monitoring

Monitor function performance and errors:

```bash
# View function logs
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name:agent-*" --limit=50

# Monitor function metrics
gcloud monitoring metrics list --filter="metric.type:cloudfunctions.googleapis.com"
```

### Firestore Analytics

Query conversation analytics:

```bash
# View routing patterns
gcloud firestore documents list routing_logs --format="table(data.agent_selected,data.confidence)"

# Check agent interaction volume
gcloud firestore documents list agent_interactions --format="table(data.agent_type)" | sort | uniq -c
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/multi-agent-ccai
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

### Manual Cleanup

Some resources may require manual cleanup:

```bash
# Delete Firestore database (if created)
# Note: This must be done through the Google Cloud Console

# Remove any remaining Cloud Storage buckets
gsutil -m rm -r gs://${PROJECT_ID}-agent-models

# Verify all functions are deleted
gcloud functions list --filter="name:agent-*"
```

## Security Considerations

### IAM and Access Control

- Functions use default service accounts with minimal required permissions
- Firestore security rules enforce data access patterns
- API endpoints are configured with appropriate authentication

### Data Protection

- All data is encrypted at rest and in transit
- Conversation logs include privacy-preserving measures
- Customer data handling follows Google Cloud security best practices

### Network Security

- Functions communicate over HTTPS
- Internal service communication uses Google Cloud's secure networking
- No public endpoints expose sensitive data

## Troubleshooting

### Common Issues

1. **Function Deployment Failures**
   ```bash
   # Check function logs for errors
   gcloud logging read "resource.type=cloud_function" --limit=20
   ```

2. **API Not Enabled Errors**
   ```bash
   # Manually enable required APIs
   gcloud services enable aiplatform.googleapis.com cloudfunctions.googleapis.com firestore.googleapis.com
   ```

3. **Permission Denied Errors**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

4. **Firestore Access Issues**
   ```bash
   # Verify Firestore database exists
   gcloud firestore databases list
   ```

### Getting Help

- Review function logs: `gcloud logging read "resource.type=cloud_function"`
- Check service status: `gcloud services list --enabled`
- Validate IAM permissions: `gcloud projects get-iam-policy PROJECT_ID`
- Contact Google Cloud Support for platform-specific issues

## Performance Optimization

### Function Optimization

- Monitor cold start times and adjust memory allocation
- Implement connection pooling for Firestore access
- Use caching for frequently accessed knowledge base data

### Cost Optimization

- Monitor function invocation counts and execution time
- Adjust timeout values to prevent over-billing
- Use Cloud Monitoring to track resource utilization

## Extension Ideas

### Enhanced Features

1. **Multi-Language Support**: Add translation capabilities using Cloud Translation API
2. **Voice Integration**: Include Speech-to-Text and Text-to-Speech for voice channels
3. **Advanced Analytics**: Implement BigQuery data warehouse for conversation analytics
4. **Sentiment Analysis**: Add Cloud Natural Language API for emotion detection
5. **Proactive Support**: Implement predictive models for customer outreach

### Integration Options

- **CRM Integration**: Connect with Salesforce, HubSpot, or other CRM systems
- **Knowledge Base**: Integrate with external knowledge management systems
- **Workforce Management**: Connect with scheduling and capacity planning tools
- **Quality Assurance**: Add conversation scoring and agent performance metrics

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult the troubleshooting section above
4. Open an issue in the recipe repository

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new variables or features
3. Ensure security best practices are maintained
4. Validate all deployment methods still work

---

**Note**: This infrastructure implements Agent2Agent protocol principles for multi-agent collaboration. The system is designed for production use but should be thoroughly tested in your specific environment before deployment.