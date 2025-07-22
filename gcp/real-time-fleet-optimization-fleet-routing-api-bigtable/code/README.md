# Infrastructure as Code for Real-Time Fleet Optimization with Cloud Fleet Routing API and Cloud Bigtable

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Fleet Optimization with Cloud Fleet Routing API and Cloud Bigtable".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured with authentication
- Terraform installed (version 1.0 or later) for Terraform deployment
- Appropriate IAM permissions for resource creation:
  - Cloud Bigtable Admin
  - Cloud Functions Admin  
  - Pub/Sub Admin
  - Optimization AI Admin
  - Project IAM Admin
  - Service Account Admin
- Estimated cost: $50-100 for running this infrastructure (includes Bigtable cluster, Cloud Functions, Pub/Sub, and Optimization API calls)

## Architecture Overview

This infrastructure deploys:

- **Cloud Bigtable Instance**: High-performance NoSQL database for storing historical traffic patterns with autoscaling
- **Bigtable Table**: Optimized schema for time-series traffic data with column families for different metrics
- **Pub/Sub Topics**: Event streaming for real-time fleet events and traffic updates
- **Cloud Functions**: Serverless event processing for real-time data ingestion and route optimization triggers
- **Service Accounts**: Properly configured IAM roles for secure service-to-service communication
- **APIs**: Required Google Cloud APIs including Optimization AI for fleet routing calculations

## Quick Start

### Using Infrastructure Manager

```bash
# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# Create deployment from Infrastructure Manager YAML
gcloud infra-manager deployments create fleet-optimization-deployment \
    --location=us-central1 \
    --config=infrastructure-manager/main.yaml \
    --input-values project_id=$(gcloud config get-value project),region=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=$(gcloud config get-value project)" \
               -var="region=us-central1"

# Apply infrastructure
terraform apply -var="project_id=$(gcloud config get-value project)" \
                -var="region=us-central1"
```

### Using Bash Scripts

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Configuration Options

### Terraform Variables

The following variables can be customized in `terraform/terraform.tfvars` or passed via command line:

- `project_id` (string): Google Cloud project ID
- `region` (string): Primary region for resources (default: "us-central1")
- `zone` (string): Specific zone for zonal resources (default: "us-central1-a")
- `bigtable_min_nodes` (number): Minimum Bigtable cluster nodes (default: 1)
- `bigtable_max_nodes` (number): Maximum Bigtable cluster nodes (default: 10)
- `function_memory` (string): Cloud Function memory allocation (default: "512Mi")
- `function_timeout` (number): Cloud Function timeout in seconds (default: 60)
- `environment` (string): Environment name for resource tagging (default: "dev")

### Infrastructure Manager Variables

Variables are defined in the `infrastructure-manager/main.yaml` file and can be overridden using `--input-values`:

```bash
gcloud infra-manager deployments create fleet-optimization \
    --location=us-central1 \
    --config=infrastructure-manager/main.yaml \
    --input-values project_id=your-project,region=us-west2,environment=prod
```

## Security Configuration

The infrastructure implements security best practices:

- **Service Accounts**: Dedicated service accounts with minimal required permissions
- **IAM Roles**: Principle of least privilege for all service-to-service communication
- **VPC Integration**: Cloud Functions can optionally use VPC connectors for private networking
- **API Security**: Cloud Fleet Routing API access controlled through service account authentication
- **Encryption**: Data encrypted at rest in Cloud Bigtable and in transit for all API calls

## Monitoring and Observability

The deployment includes observability features:

- **Cloud Logging**: Centralized logging for all Cloud Functions
- **Cloud Monitoring**: Metrics for Bigtable performance, function execution, and Pub/Sub throughput
- **Error Reporting**: Automatic error detection and alerting for function failures
- **Trace Integration**: Request tracing across the optimization pipeline

## Post-Deployment Steps

After successful deployment:

1. **Verify Services**: Check that all APIs are enabled and services are running
2. **Test Pub/Sub**: Send test messages to validate event processing
3. **Validate Bigtable**: Confirm table schema and autoscaling configuration
4. **Test Optimization**: Run sample fleet routing requests
5. **Configure Monitoring**: Set up alerts for key metrics

### Testing the Deployment

```bash
# Test Pub/Sub message processing
gcloud pubsub topics publish fleet-events-topic \
    --message='{"road_segment":"test_segment","traffic_speed":45,"volume":150}'

# Query Bigtable for processed data
cbt -project=$(gcloud config get-value project) -instance=fleet-data-instance \
    read traffic_patterns count=5

# Check Cloud Function logs
gcloud functions logs read route-optimizer-function --limit=10
```

## Customization

### Adding New Traffic Data Sources

To integrate additional traffic data sources:

1. Modify the Pub/Sub topic configuration to accept new message schemas
2. Update Cloud Function code to process different data formats
3. Adjust Bigtable table schema for additional column families
4. Configure new service accounts and IAM permissions as needed

### Scaling Considerations

For production workloads:

- **Bigtable**: Increase cluster size and enable regional replication for high availability
- **Cloud Functions**: Configure concurrent execution limits and VPC connectivity
- **Pub/Sub**: Enable message ordering and dead letter queues for reliability
- **Optimization API**: Monitor quota usage and request quota increases if needed

## Cleanup

### Using Infrastructure Manager

```bash
gcloud infra-manager deployments delete fleet-optimization-deployment \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=$(gcloud config get-value project)" \
                  -var="region=us-central1"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **API Not Enabled**: Ensure all required APIs are enabled in your project
   ```bash
   gcloud services enable optimization.googleapis.com bigtable.googleapis.com \
                          pubsub.googleapis.com cloudfunctions.googleapis.com
   ```

2. **IAM Permissions**: Verify your account has necessary permissions
   ```bash
   gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
       --member="user:$(gcloud config get-value account)" \
       --role="roles/editor"
   ```

3. **Bigtable Cluster Creation**: Large clusters may take 10-15 minutes to provision
4. **Function Deployment**: Ensure source code packaging and dependencies are correct
5. **Quota Limits**: Check and request quota increases for Optimization API if needed

### Logs and Debugging

```bash
# Check Infrastructure Manager deployment status
gcloud infra-manager deployments describe fleet-optimization-deployment \
    --location=us-central1

# View Terraform state
terraform show

# Check function logs for errors
gcloud functions logs read route-optimizer-function --limit=50

# Monitor Bigtable metrics
gcloud bigtable instances describe fleet-data-instance
```

## Cost Optimization

To minimize costs:

- **Bigtable**: Use autoscaling and set appropriate min/max nodes
- **Cloud Functions**: Optimize memory allocation and timeout settings
- **Pub/Sub**: Configure message retention policies
- **Monitoring**: Set up budget alerts for cost tracking

## Support

- [Google Cloud Fleet Routing API Documentation](https://cloud.google.com/optimization/docs/routing)
- [Cloud Bigtable Documentation](https://cloud.google.com/bigtable/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.