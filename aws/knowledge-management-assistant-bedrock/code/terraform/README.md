# Knowledge Management Assistant with Bedrock Agents - Terraform Infrastructure

This Terraform configuration deploys a complete knowledge management solution using Amazon Bedrock Agents, Knowledge Bases, S3, Lambda, and API Gateway.

## Architecture Overview

The solution creates:
- **S3 Bucket**: Secure document storage with encryption and versioning
- **OpenSearch Serverless**: Vector storage for document embeddings
- **Bedrock Knowledge Base**: Managed RAG capabilities with Titan embeddings
- **Bedrock Agent**: Claude 3.5 Sonnet-powered conversational interface
- **Lambda Function**: API proxy with enhanced error handling
- **API Gateway**: REST endpoint with CORS support
- **IAM Roles**: Least-privilege security configurations
- **CloudWatch**: Monitoring and logging

## Prerequisites

1. **AWS Account Setup**:
   - AWS CLI installed and configured
   - Appropriate IAM permissions for resource creation
   - Access to Amazon Bedrock models (Claude and Titan)

2. **Terraform Requirements**:
   - Terraform >= 1.5.0
   - AWS Provider ~> 5.0

3. **Bedrock Model Access**:
   ```bash
   # Enable model access in your AWS region
   aws bedrock list-foundation-models --region us-east-1
   ```

## Quick Start

### 1. Initialize Terraform

```bash
# Clone the repository and navigate to terraform directory
cd aws/knowledge-management-assistant-bedrock/code/terraform/

# Initialize Terraform
terraform init
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Basic Configuration
aws_region      = "us-east-1"
project_name    = "my-knowledge-assistant"
environment     = "dev"

# Customize resource names
bucket_prefix           = "my-knowledge-docs"
knowledge_base_name     = "my-enterprise-kb"
agent_name             = "my-knowledge-assistant"
lambda_function_name   = "my-bedrock-proxy"
api_name              = "my-knowledge-api"

# Optional: Customize agent behavior
agent_instruction = "You are a helpful assistant for my company..."

# Optional: Enable cost optimization
enable_cost_optimization = true
s3_storage_class        = "INTELLIGENT_TIERING"

# Tags
common_tags = {
  Project     = "knowledge-management"
  Environment = "development"
  Owner       = "devops-team"
  CostCenter  = "engineering"
}
```

### 3. Plan and Deploy

```bash
# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 4. Test the Deployment

After deployment, use the output values to test:

```bash
# Get the API endpoint from outputs
API_ENDPOINT=$(terraform output -raw api_endpoint_query_url)

# Test the knowledge management API
curl -X POST $API_ENDPOINT \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is our company remote work policy?",
    "sessionId": "test-session-1"
  }'
```

## Configuration Options

### Core Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | "us-east-1" | AWS region for deployment |
| `project_name` | "knowledge-management-assistant" | Project name for resources |
| `environment` | "dev" | Environment (dev/staging/prod) |

### Bedrock Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `foundation_model` | "anthropic.claude-3-5-sonnet-20241022-v2:0" | Foundation model for agent |
| `embedding_model` | "amazon.titan-embed-text-v2:0" | Embedding model for knowledge base |
| `max_tokens` | 300 | Maximum tokens per chunk |
| `overlap_percentage` | 20 | Chunk overlap percentage |

### Lambda Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `lambda_runtime` | "python3.12" | Lambda runtime version |
| `lambda_timeout` | 30 | Function timeout in seconds |
| `lambda_memory_size` | 256 | Memory allocation in MB |

### Security Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_encryption_at_rest` | true | Enable encryption for all services |
| `enable_cors` | true | Enable CORS for API Gateway |
| `cors_allowed_origins` | ["*"] | Allowed CORS origins |

## Advanced Configuration

### Multi-Environment Setup

Use Terraform workspaces for multiple environments:

```bash
# Create and switch to production workspace
terraform workspace new prod
terraform workspace select prod

# Use environment-specific variables
terraform apply -var-file="prod.tfvars"
```

### Custom Agent Instructions

Modify the agent behavior by customizing the instruction:

```hcl
agent_instruction = <<EOF
You are a specialized assistant for ACME Corporation. 
Focus on providing information about:
- Company policies and procedures
- Technical documentation
- HR guidelines

Always maintain a professional tone and cite sources.
If information is not available, direct users to contact support@acme.com.
EOF
```

### Cost Optimization

Enable cost optimization features:

```hcl
enable_cost_optimization = true
s3_storage_class         = "INTELLIGENT_TIERING"
lambda_memory_size       = 128  # Reduce for lower costs
api_log_retention_days   = 7    # Reduce log retention
```

## Monitoring and Troubleshooting

### CloudWatch Logs

Monitor the deployment through CloudWatch:

```bash
# View Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# View API Gateway logs
aws logs tail $(terraform output -raw api_gateway_log_group_name) --follow
```

### Knowledge Base Status

Check the knowledge base ingestion status:

```bash
# Get knowledge base and data source IDs
KB_ID=$(terraform output -raw knowledge_base_id)
DS_ID=$(terraform output -raw data_source_id)

# Check ingestion jobs
aws bedrock-agent list-ingestion-jobs \
  --knowledge-base-id $KB_ID \
  --data-source-id $DS_ID \
  --max-results 5
```

### Common Issues

1. **Bedrock Model Access**: Ensure you have enabled access to Claude and Titan models in your region
2. **IAM Permissions**: Verify your AWS credentials have sufficient permissions
3. **Region Support**: Bedrock Agents are available in limited regions
4. **Ingestion Delays**: Knowledge base ingestion can take several minutes

## Security Considerations

### Production Deployment

For production environments, consider:

1. **State Management**:
   ```hcl
   # Configure S3 backend in versions.tf
   backend "s3" {
     bucket  = "your-terraform-state-bucket"
     key     = "knowledge-management/terraform.tfstate"
     region  = "us-east-1"
     encrypt = true
   }
   ```

2. **IAM Restrictions**:
   - Use least-privilege IAM policies
   - Implement resource-based policies
   - Enable CloudTrail logging

3. **Network Security**:
   - Configure VPC endpoints for private access
   - Implement API Gateway resource policies
   - Use WAF for additional protection

4. **Data Protection**:
   - Enable bucket notifications for audit trails
   - Implement lifecycle policies for document retention
   - Use KMS customer-managed keys for encryption

## Cost Estimation

Estimated monthly costs (us-east-1):

| Service | Usage | Cost |
|---------|-------|------|
| S3 Storage | 1GB documents | ~$0.02 |
| OpenSearch Serverless | 0.5 OCU | ~$86.40 |
| Lambda | 10K invocations | ~$0.20 |
| API Gateway | 10K requests | ~$0.035 |
| Bedrock Agent | 1K queries | ~$3.00 |
| CloudWatch | Logs/Metrics | ~$5.00 |
| **Total** | | **~$95/month** |

*Costs vary by usage and region. See AWS pricing for exact rates.*

## Cleanup

To destroy all resources:

```bash
# Destroy the infrastructure
terraform destroy

# Clean up Terraform state (optional)
rm -rf .terraform terraform.tfstate*
```

## Support and Contributing

- Review the [original recipe documentation](../../../knowledge-management-assistant-bedrock.md)
- Check AWS documentation for Bedrock Agents and Knowledge Bases
- Report issues through your organization's support channels

## Version History

- **v1.0**: Initial Terraform implementation
- Support for AWS Provider v5.x
- Compatible with Terraform 1.5+