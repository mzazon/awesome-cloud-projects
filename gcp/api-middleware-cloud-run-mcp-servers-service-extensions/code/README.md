# Infrastructure as Code for API Middleware with Cloud Run MCP Servers and Service Extensions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "API Middleware with Cloud Run MCP Servers and Service Extensions".

## Overview

This recipe demonstrates building intelligent API middleware using Model Context Protocol (MCP) servers deployed on Cloud Run that integrates with Service Extensions and Vertex AI. The solution creates dynamic, context-aware API processing that can analyze, route, and enhance requests using AI-powered decision making.

## Architecture Components

- **3 MCP Servers**: Content Analyzer, Request Router, and Response Enhancer
- **Cloud Run Services**: Serverless hosting for all MCP components
- **Cloud Endpoints**: API gateway with Service Extensions integration
- **Vertex AI Integration**: AI-powered content analysis and enhancement
- **Intelligent Middleware**: Orchestration service coordinating MCP servers

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Appropriate IAM permissions for:
  - Cloud Run Admin
  - Service Usage Admin
  - Cloud Endpoints Admin
  - Vertex AI User
  - Cloud Build Editor
  - Artifact Registry Admin

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Deployment Manager permissions

#### Terraform
- Terraform installed (version 1.6.0 or later)
- Google Cloud provider configured

#### Bash Scripts
- Docker installed (for container builds)
- Python 3.10+ (for local testing)

### Cost Considerations
- Estimated cost: $15-30 per day for testing
- Includes Cloud Run, Vertex AI, Cloud Endpoints, and Cloud Build usage
- Costs scale with request volume and AI processing

## Quick Start

### Using Infrastructure Manager

```bash
# Set up environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable infrastructuremanager.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable endpoints.googleapis.com

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/$PROJECT_ID/locations/$REGION/deployments/mcp-middleware \
    --config-file infrastructure-manager/main.yaml \
    --input-values project_id=$PROJECT_ID,region=$REGION
```

### Using Terraform

```bash
# Initialize Terraform
cd terraform/
terraform init

# Review the planned changes
terraform plan -var="project_id=your-project-id" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=your-project-id" -var="region=us-central1"

# Get important outputs
terraform output middleware_endpoint_url
terraform output mcp_servers_urls
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh

# The script will output the endpoint URLs when deployment completes
```

## Configuration Options

### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PROJECT_ID` | Google Cloud Project ID | - | Yes |
| `REGION` | Deployment region | `us-central1` | No |
| `ZONE` | Deployment zone | `us-central1-a` | No |
| `MCP_SERVICE_PREFIX` | Prefix for MCP service names | `mcp-server-[random]` | No |
| `MIDDLEWARE_SERVICE` | Main middleware service name | `api-middleware-[random]` | No |
| `ENDPOINTS_CONFIG` | Cloud Endpoints config name | `endpoints-config-[random]` | No |

### Customizable Parameters

#### Infrastructure Manager Variables
- `project_id`: Google Cloud Project ID
- `region`: Deployment region
- `memory_limit`: Memory allocation for Cloud Run services
- `cpu_limit`: CPU allocation for Cloud Run services
- `max_instances`: Maximum number of instances per service

#### Terraform Variables
All variables are defined in `terraform/variables.tf` with descriptions and validation:

```hcl
variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "Region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "memory_limit" {
  description = "Memory limit for Cloud Run services"
  type        = string
  default     = "512Mi"
}
```

## Testing the Deployment

### Health Check Validation

```bash
# Test MCP server health endpoints (replace URLs with actual deployed URLs)
curl -X GET "https://mcp-server-content-analyzer-[hash]-uc.a.run.app/health"
curl -X GET "https://mcp-server-request-router-[hash]-uc.a.run.app/health"
curl -X GET "https://mcp-server-response-enhancer-[hash]-uc.a.run.app/health"

# Test main middleware health
curl -X GET "https://api-middleware-[hash]-uc.a.run.app/health"
```

### API Functionality Testing

```bash
# Get the endpoint URL from deployment outputs
ENDPOINT_URL=$(terraform output -raw middleware_endpoint_url)
# or from Infrastructure Manager/bash script outputs

# Test GET request processing
curl -X GET "$ENDPOINT_URL/api/test?query=sample" \
     -H "Content-Type: application/json"

# Test POST request with AI analysis
curl -X POST "$ENDPOINT_URL/api/analyze" \
     -H "Content-Type: application/json" \
     -d '{"message": "Complex request requiring intelligent processing", "priority": "high"}'
```

### Expected Response Format

Successful responses should include:
- Original request processing results
- AI analysis metadata (sentiment, complexity, routing recommendations)
- Applied enhancements and performance metrics
- MCP server processing chain information

## Monitoring and Observability

### Cloud Console Resources

After deployment, monitor these resources in Google Cloud Console:

1. **Cloud Run Services**:
   - Content Analyzer MCP Server
   - Request Router MCP Server  
   - Response Enhancer MCP Server
   - Main API Middleware Service

2. **Cloud Endpoints**:
   - API Gateway configuration
   - Request metrics and latency

3. **Cloud Logging**:
   - Application logs from all services
   - Error tracking and debugging

4. **Cloud Monitoring**:
   - Service performance metrics
   - Custom dashboards for MCP processing

### Key Metrics to Monitor

- Request latency through the complete MCP processing pipeline
- Error rates for individual MCP servers
- Vertex AI API usage and costs
- Cloud Run instance scaling patterns
- API gateway request patterns

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/$PROJECT_ID/locations/$REGION/deployments/mcp-middleware

# Disable APIs if no longer needed
gcloud services disable infrastructuremanager.googleapis.com --force
```

### Using Terraform

```bash
# Destroy all resources
cd terraform/
terraform destroy -var="project_id=your-project-id" -var="region=us-central1"

# Clean up state files (optional)
rm -rf .terraform terraform.tfstate*
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script includes confirmation prompts for safety
# It will remove all Cloud Run services, endpoints, and configurations
```

### Manual Cleanup Verification

After automated cleanup, verify these resources are removed:

```bash
# Check for remaining Cloud Run services
gcloud run services list --region=$REGION

# Check for Cloud Endpoints services
gcloud endpoints services list

# Check for any remaining container images
gcloud container images list
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**:
   ```bash
   # Ensure gcloud is configured correctly
   gcloud auth application-default login
   gcloud config set project your-project-id
   ```

2. **API Not Enabled Errors**:
   ```bash
   # Enable all required APIs
   gcloud services enable run.googleapis.com aiplatform.googleapis.com endpoints.googleapis.com
   ```

3. **Permission Denied Errors**:
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy your-project-id
   ```

4. **Container Build Failures**:
   ```bash
   # Check Cloud Build logs
   gcloud builds list --limit=10
   ```

### Service-Specific Debugging

#### MCP Server Issues
- Check Cloud Run service logs: `gcloud run services logs read [service-name] --region=$REGION`
- Verify environment variables are set correctly
- Test individual MCP endpoints directly

#### Middleware Orchestration Issues  
- Verify all MCP server URLs are accessible
- Check network connectivity between services
- Review middleware service logs for integration errors

#### Vertex AI Integration Issues
- Confirm Vertex AI API is enabled and accessible
- Check service account permissions for AI Platform
- Verify region availability for Vertex AI services

## Development and Customization

### Local Development Setup

```bash
# Clone or create the MCP server applications locally
mkdir -p mcp-middleware/{content-analyzer,request-router,response-enhancer}

# Install Python dependencies for local testing
cd mcp-middleware/content-analyzer
pip install -r requirements.txt

# Run locally for development
export PROJECT_ID=your-project-id
export REGION=us-central1
python main.py
```

### Extending the Solution

1. **Additional MCP Servers**: Add new MCP servers by creating similar FastAPI applications
2. **Enhanced AI Processing**: Integrate additional Vertex AI models or services
3. **Custom Routing Logic**: Modify request router logic for specific business rules
4. **Advanced Monitoring**: Add custom metrics and alerting for business-specific KPIs

### Code Structure

```
code/
├── infrastructure-manager/
│   └── main.yaml                 # Infrastructure Manager configuration
├── terraform/
│   ├── main.tf                   # Main Terraform configuration
│   ├── variables.tf              # Input variables
│   ├── outputs.tf                # Output values
│   └── versions.tf               # Provider versions
├── scripts/
│   ├── deploy.sh                 # Automated deployment script
│   └── destroy.sh                # Cleanup script
└── README.md                     # This file
```

## Security Considerations

### Implemented Security Measures

- **Cloud Run Security**: All services use managed HTTPS endpoints
- **IAM Integration**: Proper service account configurations
- **API Gateway Security**: Cloud Endpoints provides managed security
- **Container Security**: Base images use official Python slim images

### Additional Security Recommendations

1. **Enable Cloud Run Authentication**: Remove `--allow-unauthenticated` for production
2. **Implement API Keys**: Use Cloud Endpoints API key management
3. **Network Security**: Consider VPC connectors for private backend communication
4. **Monitoring**: Enable Cloud Security Command Center integration

## Performance Optimization

### Scaling Configuration

- **Cloud Run Concurrency**: Configured for optimal request handling
- **Memory Allocation**: Sized appropriately for AI processing workloads
- **Instance Limits**: Prevents runaway scaling costs

### Cost Optimization Tips

1. **Request Caching**: Implement caching for frequently analyzed content
2. **Regional Deployment**: Deploy in regions closest to your users
3. **Resource Limits**: Set appropriate CPU and memory limits
4. **Monitoring**: Use Cloud Monitoring to track and optimize costs

## Support and Resources

### Documentation Links

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Endpoints Documentation](https://cloud.google.com/endpoints/docs)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

### Getting Help

1. **Google Cloud Support**: For infrastructure and service issues
2. **Community Forums**: Stack Overflow with `google-cloud-platform` tag
3. **GitHub Issues**: For recipe-specific problems
4. **Google Cloud Documentation**: Comprehensive guides and tutorials

---

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation. The complete recipe with step-by-step implementation details is available in the parent directory.