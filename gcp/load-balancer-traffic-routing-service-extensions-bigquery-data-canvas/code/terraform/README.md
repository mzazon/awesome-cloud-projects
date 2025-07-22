# Terraform Infrastructure for GCP Load Balancer Traffic Routing with Service Extensions

This directory contains Terraform Infrastructure as Code (IaC) for deploying an intelligent traffic routing system using Google Cloud Platform services including Application Load Balancer, Service Extensions, BigQuery Data Canvas, and Cloud Run.

## Architecture Overview

The solution creates an intelligent traffic routing system that:

- **Application Load Balancer**: Global load balancer with intelligent routing capabilities
- **Service Extensions**: Custom traffic processing logic for real-time routing decisions
- **Cloud Run Services**: Three serverless backend services with different performance characteristics
- **BigQuery Analytics**: Data warehouse for traffic metrics and routing decisions
- **Cloud Function**: AI-powered traffic routing logic with BigQuery integration
- **Cloud Workflows**: Automated analytics processing and insights generation
- **BigQuery Data Canvas**: Natural language interface for traffic analytics

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK**: Install and configure the `gcloud` CLI
   ```bash
   curl https://sdk.cloud.google.com | bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform**: Install Terraform v1.5 or later
   ```bash
   # On macOS with Homebrew
   brew install terraform
   
   # On Ubuntu/Debian
   wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com releases main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   ```

3. **Google Cloud Project**: A GCP project with billing enabled

4. **Required Permissions**: Your user account or service account must have the following IAM roles:
   - `roles/compute.admin`
   - `roles/run.admin`
   - `roles/bigquery.admin`
   - `roles/cloudfunctions.admin`
   - `roles/workflows.admin`
   - `roles/serviceusage.serviceUsageAdmin`
   - `roles/iam.serviceAccountAdmin`
   - `roles/logging.admin`

## Quick Start

### 1. Clone and Navigate

```bash
cd gcp/load-balancer-traffic-routing-service-extensions-bigquery-data-canvas/code/terraform/
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Configure Variables

Create a `terraform.tfvars` file to customize your deployment:

```hcl
# Required variables
project_id = "your-gcp-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Optional customizations
resource_name_prefix = "intelligent-routing"
environment         = "dev"

# Cloud Run service configuration
cloud_run_services = {
  service_a = {
    image         = "gcr.io/cloudrun/hello"
    memory        = "512Mi"
    cpu           = "1000m"
    max_instances = 10
    env_vars = {
      SERVICE_TYPE   = "fast"
      RESPONSE_DELAY = "100"
    }
  }
  service_b = {
    image         = "gcr.io/cloudrun/hello"
    memory        = "1Gi"
    cpu           = "1000m"
    max_instances = 10
    env_vars = {
      SERVICE_TYPE   = "standard"
      RESPONSE_DELAY = "500"
    }
  }
  service_c = {
    image         = "gcr.io/cloudrun/hello"
    memory        = "2Gi"
    cpu           = "2000m"
    max_instances = 5
    env_vars = {
      SERVICE_TYPE   = "intensive"
      RESPONSE_DELAY = "1000"
    }
  }
}

# BigQuery configuration
bigquery_dataset_config = {
  location                    = "US"
  default_table_expiration_ms = 86400000  # 1 day
  delete_contents_on_destroy  = true
  description                 = "Traffic analytics for intelligent routing"
}
```

### 4. Plan the Deployment

```bash
terraform plan -var-file="terraform.tfvars"
```

### 5. Deploy the Infrastructure

```bash
terraform apply -var-file="terraform.tfvars"
```

The deployment typically takes 10-15 minutes to complete.

### 6. Verify Deployment

After successful deployment, Terraform will output important information including:

- Load balancer IP address
- Cloud Run service URLs
- BigQuery dataset and table URLs
- Traffic router function URL
- Testing commands

## Testing the Solution

### Basic Connectivity Test

```bash
# Get the load balancer IP from Terraform outputs
LB_IP=$(terraform output -raw load_balancer_ip)

# Test basic connectivity
curl -s -o /dev/null -w "Status: %{http_code}, Time: %{time_total}s\n" \
  http://$LB_IP/
```

### Test Intelligent Routing Paths

```bash
# Test different routing paths
for path in "/api/fast/test" "/api/standard/process" "/api/intensive/compute"; do
  echo "Testing path: $path"
  for i in {1..5}; do
    curl -s -w "Path: $path, Status: %{http_code}, Time: %{time_total}s\n" \
      -o /dev/null \
      "http://$LB_IP$path"
  done
  echo "---"
done
```

### Generate Traffic for Analytics

```bash
# Generate sample traffic for analytics
for i in {1..50}; do
  curl -s -o /dev/null "http://$LB_IP/api/fast/test"
  curl -s -o /dev/null "http://$LB_IP/api/standard/process"
  curl -s -o /dev/null "http://$LB_IP/api/intensive/compute"
  sleep 1
done
```

### Execute Analytics Workflow

```bash
# Get workflow name from Terraform outputs
WORKFLOW_NAME=$(terraform output -json analytics_workflow | jq -r '.name')
REGION=$(terraform output -raw region)

# Execute the analytics workflow
gcloud workflows execute $WORKFLOW_NAME --location=$REGION

# Check workflow execution results
gcloud workflows executions list \
  --workflow=$WORKFLOW_NAME \
  --location=$REGION \
  --limit=1
```

## BigQuery Data Canvas Usage

Access BigQuery Data Canvas for natural language analytics:

1. **Navigate to BigQuery Console**:
   ```bash
   echo "https://console.cloud.google.com/bigquery?project=$(terraform output -raw project_id)"
   ```

2. **Select the Analytics Dataset**:
   - Find the dataset created by Terraform (check outputs for exact name)
   - Click on the dataset to explore tables

3. **Use Natural Language Queries**:
   - "Show me the slowest services in the last hour"
   - "Which routing decisions had the highest confidence scores?"
   - "What are the traffic patterns by time of day?"
   - "How many requests failed in the last 30 minutes?"

4. **Access Tables Directly**:
   - `lb_metrics`: Load balancer performance metrics
   - `routing_decisions`: AI routing decisions and reasoning

## Monitoring and Observability

### Cloud Monitoring Dashboards

View application performance and routing metrics in Cloud Monitoring:

```bash
echo "https://console.cloud.google.com/monitoring?project=$(terraform output -raw project_id)"
```

### Cloud Logging

View detailed logs from all components:

```bash
# View load balancer logs
gcloud logging read "resource.type=http_load_balancer" --limit=50

# View Cloud Function logs
FUNCTION_NAME=$(terraform output -json traffic_router_function | jq -r '.name')
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=$FUNCTION_NAME" --limit=50

# View Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision" --limit=50
```

### Service Extensions Monitoring

Monitor Service Extensions performance:

```bash
# Check Service Extensions status
EXTENSION_NAME=$(terraform output -json service_extension | jq -r '.name')
gcloud service-extensions extensions describe $EXTENSION_NAME --location=$REGION
```

## Customization Options

### Modifying Cloud Run Services

To customize the Cloud Run services, update the `cloud_run_services` variable in your `terraform.tfvars`:

```hcl
cloud_run_services = {
  service_a = {
    image         = "gcr.io/your-project/custom-image:latest"
    memory        = "1Gi"
    cpu           = "2000m"
    max_instances = 20
    env_vars = {
      CUSTOM_VAR = "value"
    }
  }
  # ... other services
}
```

### Adjusting Load Balancer Configuration

Customize health checks and SSL settings:

```hcl
load_balancer_config = {
  enable_https                     = true
  ssl_certificate_domains          = ["yourdomain.com", "www.yourdomain.com"]
  health_check_path               = "/health"
  health_check_interval           = 30
  health_check_timeout            = 10
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 3
}
```

### BigQuery Configuration

Adjust BigQuery settings for your data retention needs:

```hcl
bigquery_dataset_config = {
  location                    = "US"
  default_table_expiration_ms = 604800000  # 7 days
  delete_contents_on_destroy  = false
  description                 = "Production traffic analytics"
}
```

## Cost Optimization

### Estimated Costs

Monthly costs for this solution (approximate):

- **Application Load Balancer**: $18-25
- **Cloud Run**: $10-50 (depending on usage)
- **BigQuery**: $5-20 (depending on data volume)
- **Cloud Functions**: $5-15
- **Cloud Storage**: $1-5
- **Total Estimated**: $40-115/month

### Cost Optimization Tips

1. **Adjust Cloud Run Resources**: Right-size memory and CPU allocations
2. **BigQuery Partitioning**: Use table partitioning for large datasets
3. **Function Optimization**: Optimize Cloud Function memory allocation
4. **Data Retention**: Set appropriate table expiration times
5. **Regional Resources**: Use regional deployments closer to users

## Troubleshooting

### Common Issues

#### 1. API Enable Errors
```bash
# Manually enable required APIs
gcloud services enable compute.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable bigquery.googleapis.com
gcloud services enable serviceextensions.googleapis.com
```

#### 2. Service Extensions Not Available
Service Extensions are in Preview. Ensure your project has access:
```bash
gcloud alpha service-extensions extensions list --location=$REGION
```

#### 3. BigQuery Permission Errors
Verify IAM permissions:
```bash
gcloud projects get-iam-policy $(terraform output -raw project_id)
```

#### 4. Cloud Function Deployment Issues
Check function logs:
```bash
gcloud functions logs read $FUNCTION_NAME --region=$REGION
```

### Debug Commands

```bash
# Check Terraform state
terraform show

# Validate configuration
terraform validate

# Check specific resource status
terraform state show google_compute_global_forwarding_rule.default

# Force refresh state
terraform refresh -var-file="terraform.tfvars"
```

## Security Considerations

### IAM and Access Control

- Service accounts follow least privilege principle
- Cloud Run services use dedicated service accounts
- BigQuery access is controlled through IAM roles
- Function-to-function communication uses service accounts

### Network Security

- Load balancer supports HTTPS termination
- Internal service communication is encrypted
- VPC integration available for additional security
- Health checks use secure endpoints

### Data Protection

- BigQuery data is encrypted at rest and in transit
- Cloud Logging data retention policies applied
- Function environment variables are secure
- Service Extensions use secure callouts

## Cleanup

### Destroy Infrastructure

To remove all created resources:

```bash
terraform destroy -var-file="terraform.tfvars" -auto-approve
```

### Manual Cleanup (if needed)

Some resources may require manual cleanup:

```bash
# Remove any remaining BigQuery data
bq rm -rf --dataset $(terraform output -raw project_id):$(terraform output -json bigquery_dataset | jq -r '.dataset_id')

# Clean up Cloud Storage artifacts
gsutil rm -r gs://$(terraform output -json traffic_router_function | jq -r '.name')-source-*

# Verify all resources are removed
gcloud compute forwarding-rules list
gcloud run services list
gcloud functions list
```

## Support and Contributing

### Getting Help

1. **Google Cloud Documentation**: [Service Extensions](https://cloud.google.com/service-extensions/docs)
2. **Terraform Google Provider**: [Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
3. **BigQuery Data Canvas**: [User Guide](https://cloud.google.com/bigquery/docs/data-canvas)

### Best Practices

- Use version control for your Terraform configurations
- Test changes in a development environment first
- Monitor costs regularly using Cloud Billing
- Review security settings periodically
- Keep Terraform providers updated

### Version Information

- **Terraform Version**: >= 1.5
- **Google Provider**: ~> 5.0
- **Google Beta Provider**: ~> 5.0

This infrastructure code follows Google Cloud best practices and is designed for production use with appropriate monitoring, security, and cost optimization considerations.