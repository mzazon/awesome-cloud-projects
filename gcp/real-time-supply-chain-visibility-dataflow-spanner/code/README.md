# Infrastructure as Code for Real-Time Supply Chain Visibility with Cloud Dataflow and Cloud Spanner

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Supply Chain Visibility with Cloud Dataflow and Cloud Spanner".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Appropriate Google Cloud permissions:
  - Dataflow Admin
  - Spanner Admin
  - Pub/Sub Admin
  - BigQuery Admin
  - Storage Admin
  - Service Account Admin
  - IAM Admin
- Python 3.7+ (for Dataflow pipeline deployment)
- Terraform 1.5+ (for Terraform implementation)
- Estimated cost: $150-200 for running this infrastructure

## Quick Start

### Using Infrastructure Manager (Google Cloud)

```bash
# Create a deployment using Infrastructure Manager
gcloud infra-manager deployments create supply-chain-deployment \
    --location=us-central1 \
    --source=infrastructure-manager/main.yaml \
    --input-values=project_id=YOUR_PROJECT_ID,region=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
./scripts/deploy.sh
```

## Infrastructure Components

This recipe deploys the following Google Cloud resources:

### Core Infrastructure
- **Cloud Spanner**: Regional instance with supply chain database and tables
- **Cloud Dataflow**: Streaming pipeline for real-time event processing
- **Cloud Pub/Sub**: Topic and subscription for event ingestion
- **BigQuery**: Dataset and tables for analytics and reporting
- **Cloud Storage**: Bucket for Dataflow staging and temporary files

### Supporting Services
- **IAM Service Accounts**: For Dataflow pipeline execution
- **IAM Roles and Policies**: Least privilege access control
- **Firewall Rules**: Network security configuration (if applicable)

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
# Project and region configuration
project_id: "your-project-id"
region: "us-central1"

# Spanner configuration
spanner_instance_name: "supply-chain-instance"
spanner_node_count: 1
spanner_processing_units: 100

# Dataflow configuration
dataflow_max_workers: 5
dataflow_num_workers: 2
dataflow_machine_type: "n1-standard-2"

# Resource naming
resource_suffix: "prod"
```

### Terraform Variables

Configure variables in `terraform/terraform.tfvars`:

```hcl
# Required variables
project_id = "your-project-id"
region     = "us-central1"

# Optional customizations
spanner_instance_config = "regional-us-central1"
spanner_node_count      = 1
dataflow_max_workers    = 5
dataflow_num_workers    = 2
bigquery_location       = "US"
storage_location        = "US-CENTRAL1"

# Resource naming
environment = "prod"
resource_suffix = "v1"
```

### Bash Script Variables

Set environment variables before running scripts:

```bash
# Required variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Optional customizations
export SPANNER_NODE_COUNT="1"
export DATAFLOW_MAX_WORKERS="5"
export DATAFLOW_NUM_WORKERS="2"
export ENVIRONMENT="prod"
```

## Deployment Process

### Phase 1: Core Infrastructure
1. Creates Cloud Spanner instance and database
2. Sets up Pub/Sub topic and subscription
3. Creates BigQuery dataset and tables
4. Provisions Cloud Storage bucket

### Phase 2: Database Schema
1. Creates supply chain tables in Spanner:
   - `Shipments` table for tracking shipment data
   - `Inventory` table for stock management
   - `Events` table for audit logging

### Phase 3: Streaming Pipeline
1. Deploys Dataflow pipeline code
2. Configures streaming job with proper scaling
3. Sets up data flow from Pub/Sub to Spanner and BigQuery

### Phase 4: Security and Monitoring
1. Creates IAM service accounts with least privilege
2. Configures resource-level permissions
3. Sets up basic monitoring and alerting

## Validation and Testing

After deployment, verify the infrastructure:

```bash
# Check Spanner instance
gcloud spanner instances list

# Verify database schema
gcloud spanner databases list --instance=INSTANCE_NAME

# Check Dataflow job status
gcloud dataflow jobs list --region=REGION

# Test Pub/Sub connectivity
gcloud pubsub topics list

# Verify BigQuery dataset
bq ls
```

## Monitoring and Maintenance

### Key Metrics to Monitor
- **Dataflow Pipeline**: Throughput, latency, error rates
- **Spanner Database**: CPU utilization, storage usage, query performance
- **Pub/Sub**: Message backlog, processing rate
- **BigQuery**: Query performance, storage costs

### Scaling Considerations
- **Spanner**: Increase nodes for higher throughput
- **Dataflow**: Adjust max_workers for peak load handling
- **Pub/Sub**: Monitor subscription backlog and adjust processing

### Cost Optimization
- **Spanner**: Consider processing units vs. nodes based on workload
- **Dataflow**: Use preemptible instances for cost savings
- **BigQuery**: Implement table partitioning and clustering
- **Storage**: Configure lifecycle policies for temporary files

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete supply-chain-deployment \
    --location=us-central1 \
    --delete-policy=DELETE
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=YOUR_PROJECT_ID" -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

## Troubleshooting

### Common Issues

1. **Dataflow Pipeline Fails to Start**
   - Check service account permissions
   - Verify Pub/Sub subscription exists
   - Ensure Spanner database is accessible

2. **Spanner Connection Errors**
   - Verify instance is running
   - Check database schema creation
   - Validate IAM permissions

3. **BigQuery Write Failures**
   - Check dataset permissions
   - Verify table schema compatibility
   - Review streaming insert quotas

4. **High Costs**
   - Monitor Spanner CPU usage
   - Check Dataflow worker scaling
   - Review BigQuery storage and query costs

### Debugging Commands

```bash
# Check Dataflow job logs
gcloud dataflow jobs show JOB_ID --region=REGION

# Monitor Spanner metrics
gcloud spanner operations list --instance=INSTANCE_NAME

# Review BigQuery job history
bq ls -j --max_results=10
```

## Security Considerations

### IAM Best Practices
- Service accounts use least privilege principle
- Regular rotation of service account keys
- Monitoring of IAM policy changes

### Data Protection
- Encryption at rest enabled for all storage
- Encryption in transit for all data flows
- VPC configurations for network isolation

### Access Control
- Principle of least privilege for all resources
- Regular audit of permissions and access logs
- Multi-factor authentication for administrative access

## Performance Optimization

### Spanner Optimization
- Hotspotting prevention through proper key design
- Query optimization using execution plans
- Appropriate indexing strategy

### Dataflow Optimization
- Proper windowing for streaming aggregations
- Efficient data serialization formats
- Batch sizing for BigQuery writes

### BigQuery Optimization
- Partitioning and clustering strategies
- Query optimization techniques
- Cost control through slot reservations

## Support and Documentation

### Additional Resources
- [Cloud Spanner Documentation](https://cloud.google.com/spanner/docs)
- [Dataflow Documentation](https://cloud.google.com/dataflow/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [BigQuery Documentation](https://cloud.google.com/bigquery/docs)

### Getting Help
- Review the original recipe documentation for architectural details
- Check Google Cloud Support for infrastructure issues
- Consult the Google Cloud Architecture Center for best practices

## Customization Examples

### Adding New Event Types
Modify the Dataflow pipeline to handle additional logistics events:

```python
# Add new event types to the pipeline
new_event_types = ['customs_clearance', 'warehouse_receipt', 'quality_inspection']
```

### Scaling for Production
Update configuration for production workloads:

```yaml
# Production scaling configuration
spanner_node_count: 3
dataflow_max_workers: 20
dataflow_num_workers: 5
```

### Multi-Region Deployment
Configure for global supply chain operations:

```yaml
# Multi-region configuration
spanner_instance_config: "nam-eur-asia1"
bigquery_location: "US"
additional_regions: ["europe-west1", "asia-southeast1"]
```

---

For issues with this infrastructure code, refer to the original recipe documentation or the Google Cloud provider documentation.