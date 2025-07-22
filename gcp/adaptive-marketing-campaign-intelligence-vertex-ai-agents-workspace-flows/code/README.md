# Infrastructure as Code for Adaptive Marketing Campaign Intelligence with Vertex AI Agents and Google Workspace Flows

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Adaptive Marketing Campaign Intelligence with Vertex AI Agents and Google Workspace Flows".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud SDK (gcloud) installed and configured
- Google Cloud Project with billing enabled
- Google Workspace account with administrator privileges for Flows configuration
- Appropriate IAM permissions for:
  - Vertex AI services
  - BigQuery administration
  - Cloud Storage administration
  - Gmail API access
  - Google Sheets API access
  - Google Workspace Flows management
- Terraform installed (version >= 1.0) for Terraform implementation
- Basic understanding of AI/ML concepts and marketing automation workflows

### Required APIs

The following APIs must be enabled in your Google Cloud project:
- AI Platform API (`aiplatform.googleapis.com`)
- BigQuery API (`bigquery.googleapis.com`)
- Gmail API (`gmail.googleapis.com`)
- Google Sheets API (`sheets.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)

### Estimated Costs

- **Development/Testing**: $150-300/month
- **Production**: $500-1,500/month (depending on data volume and AI usage)

Cost components include:
- Vertex AI Agents compute and API calls
- BigQuery storage and query processing
- Cloud Storage for data processing
- Google Workspace Flows execution
- Data transfer and networking

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"

# Create deployment
gcloud infra-manager deployments create marketing-intelligence-deployment \
    --location=us-central1 \
    --source=. \
    --input-values=project_id=${PROJECT_ID}

# Monitor deployment progress
gcloud infra-manager deployments describe marketing-intelligence-deployment \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize terraform.tfvars.example
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply
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

# Monitor deployment progress
# Follow the script output for status updates
```

## Post-Deployment Configuration

After deploying the infrastructure, complete these additional setup steps:

### 1. Configure Google Workspace Flows

```bash
# Authenticate with Workspace
gcloud auth application-default login --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/gmail.modify,https://www.googleapis.com/auth/spreadsheets

# Deploy workflow configurations (automated in scripts)
gcloud workspace flows deploy --config=workflows/campaign-alert-flow.json
gcloud workspace flows deploy --config=workflows/segmentation-workflow.json
```

### 2. Load Sample Data (Optional)

```bash
# Load sample marketing data for testing
bq load --source_format=CSV \
    ${PROJECT_ID}:marketing_data.campaign_performance \
    sample_data/campaign_performance.csv \
    campaign_id:STRING,campaign_name:STRING,channel:STRING,start_date:DATE,end_date:DATE,impressions:INTEGER,clicks:INTEGER,conversions:INTEGER,spend:FLOAT,revenue:FLOAT,ctr:FLOAT,conversion_rate:FLOAT,roas:FLOAT,audience_segment:STRING,geo_location:STRING,device_type:STRING,timestamp:TIMESTAMP
```

### 3. Verify AI Agent Deployment

```bash
# List deployed agents
gcloud ai agents list --region=${REGION}

# Test agent with sample query
gcloud ai agents query campaign-intelligence-agent \
    --region=${REGION} \
    --query="Analyze recent campaign performance trends"
```

## Validation & Testing

### Infrastructure Validation

```bash
# Verify BigQuery dataset creation
bq ls --project_id=${PROJECT_ID}

# Check Cloud Storage bucket
gsutil ls -p ${PROJECT_ID}

# Verify Vertex AI Agent deployment
gcloud ai agents list --region=${REGION}

# Test Workspace Flows deployment
gcloud workspace flows list --project=${PROJECT_ID}
```

### Functional Testing

```bash
# Run end-to-end test
cd scripts/
./test_deployment.sh

# Expected outputs:
# ✅ BigQuery dataset accessible
# ✅ AI Agent responding to queries
# ✅ Workspace Flows executing successfully
# ✅ Sample predictions generated
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete marketing-intelligence-deployment \
    --location=us-central1

# Confirm deletion
gcloud infra-manager deployments list --location=us-central1
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm when prompted
# Review resources to be destroyed before confirming
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
# Script will remove resources in proper order
```

### Manual Cleanup (if needed)

```bash
# Delete Google Workspace Flows
gcloud workspace flows delete campaign-performance-alerts
gcloud workspace flows delete dynamic-customer-segmentation
gcloud workspace flows delete real-time-dashboard-updates

# Delete Vertex AI components
gcloud ai agents delete campaign-intelligence-agent --region=${REGION}
gcloud ai gems delete brand-voice-analyzer --region=${REGION}
gcloud ai gems delete campaign-optimizer --region=${REGION}

# Delete BigQuery dataset
bq rm -r -f ${PROJECT_ID}:marketing_data

# Delete Cloud Storage bucket
gsutil -m rm -r gs://marketing-intelligence-${PROJECT_ID}
```

## Customization

### Key Configuration Variables

#### Infrastructure Manager (`main.yaml`)
- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `dataset_name`: BigQuery dataset name
- `agent_name`: Vertex AI agent identifier
- `bucket_name`: Cloud Storage bucket name

#### Terraform (`variables.tf`)
- `project_id`: Google Cloud project ID
- `region`: Deployment region
- `zone`: Deployment zone
- `dataset_location`: BigQuery dataset location
- `enable_apis`: List of APIs to enable
- `labels`: Resource labels for organization

#### Environment Variables (Bash Scripts)
```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export DATASET_NAME="marketing_data_custom"
export AGENT_NAME="custom-agent-name"
```

### Advanced Customization

#### Adding Custom Gems
```bash
# Create additional AI agent capabilities
cat > custom-gem.json << EOF
{
  "name": "custom-marketing-gem",
  "description": "Specialized marketing capability",
  "instructions": ["Custom instructions here"],
  "knowledge_sources": ["custom_data.csv"]
}
EOF

gcloud ai gems create custom-marketing-gem \
    --region=${REGION} \
    --config=custom-gem.json
```

#### Extending Workflows
```bash
# Add new workflow configurations
cat > custom-workflow.json << EOF
{
  "flow_name": "custom-marketing-workflow",
  "description": "Custom marketing automation",
  "trigger": {"type": "scheduled", "frequency": "daily"},
  "steps": [/* Custom workflow steps */]
}
EOF

gcloud workspace flows deploy \
    --config=custom-workflow.json
```

## Architecture Overview

The deployed infrastructure includes:

### Core Components
- **BigQuery Dataset**: Central data warehouse for marketing intelligence
- **Vertex AI Agent**: Intelligent analysis and decision-making engine
- **Custom Gems**: Specialized AI capabilities for marketing tasks
- **Cloud Storage**: Data processing and temporary storage
- **Google Workspace Flows**: Workflow orchestration and automation

### Data Flow
1. Marketing data ingested into BigQuery
2. Vertex AI Agent analyzes patterns and generates insights
3. Custom Gems provide specialized domain expertise
4. Workspace Flows orchestrate automated responses
5. Actions executed across Gmail, Sheets, and external systems

### Security Features
- IAM-based access control
- Encrypted data at rest and in transit
- API key management through Secret Manager
- Audit logging for all operations

## Monitoring and Observability

### Cloud Monitoring Dashboards
```bash
# Create custom dashboard for monitoring
gcloud monitoring dashboards create \
    --config-from-file=monitoring/marketing-intelligence-dashboard.json
```

### Key Metrics to Monitor
- AI Agent query response times
- BigQuery query performance
- Workflow execution success rates
- Data processing volumes
- Cost tracking and optimization

### Alerting
```bash
# Set up alerts for critical thresholds
gcloud alpha monitoring policies create \
    --policy-from-file=monitoring/alert-policies.yaml
```

## Troubleshooting

### Common Issues

#### Authentication Errors
```bash
# Re-authenticate with required scopes
gcloud auth login --enable-gdrive-access
gcloud auth application-default login
```

#### API Enablement Issues
```bash
# Manually enable required APIs
gcloud services enable aiplatform.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable gmail.googleapis.com
```

#### Workspace Flows Access
```bash
# Verify Workspace admin permissions
gcloud workspace flows test-permissions
```

### Log Analysis
```bash
# View deployment logs
gcloud logging read "resource.type=cloud_function" --limit=50

# Monitor AI Agent activity
gcloud logging read "resource.type=aiplatform.googleapis.com/agent" --limit=20
```

## Security Considerations

### IAM Best Practices
- Use principle of least privilege for service accounts
- Regular review of access permissions
- Enable audit logging for all sensitive operations

### Data Protection
- Enable BigQuery encryption with customer-managed keys
- Configure VPC Service Controls for enhanced security
- Implement data loss prevention policies

### API Security
- Use OAuth 2.0 for Workspace API access
- Implement rate limiting and quota management
- Regular rotation of API keys and credentials

## Performance Optimization

### BigQuery Optimization
- Partition tables by date for better query performance
- Use clustering for frequently filtered columns
- Implement appropriate data retention policies

### AI Agent Performance
- Monitor token usage and optimize prompt engineering
- Use batch processing for large-scale analysis
- Implement caching for frequently requested insights

### Cost Optimization
- Set up budget alerts and spending limits
- Use spot instances for non-critical workloads
- Implement data lifecycle management policies

## Support and Documentation

### Additional Resources
- [Google Cloud AI Agent Ecosystem](https://cloud.google.com/vertex-ai/docs/ai-agent-ecosystem-overview)
- [Google Workspace Flows Documentation](https://workspace.google.com/blog/product-announcements/new-ai-drives-business-results)
- [Vertex AI Platform Capabilities](https://cloud.google.com/vertex-ai)
- [BigQuery ML for Marketing Analytics](https://cloud.google.com/bigquery/docs/bigqueryml-intro)

### Getting Help
- For infrastructure issues: Check Google Cloud Status and Support
- For recipe-specific questions: Refer to the original recipe documentation
- For Workspace Flows: Contact Google Workspace Support

### Contributing
To contribute improvements to this infrastructure code:
1. Test changes in a development environment
2. Follow Google Cloud infrastructure best practices
3. Update documentation for any configuration changes
4. Submit changes through appropriate review process

## Version Information

- **Recipe Version**: 1.0
- **Infrastructure Manager**: Compatible with latest GCP version
- **Terraform**: Requires >= 1.0, Google provider >= 4.0
- **Google Cloud SDK**: Requires latest stable version
- **Last Updated**: 2025-07-12

## License

This infrastructure code is provided as-is for educational and demonstration purposes. Ensure compliance with your organization's policies and Google Cloud terms of service before deploying in production environments.