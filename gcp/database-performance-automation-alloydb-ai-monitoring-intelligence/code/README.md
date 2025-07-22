# Infrastructure as Code for Automating Database Performance with AlloyDB AI and Cloud Monitoring Intelligence

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Automating Database Performance with AlloyDB AI and Cloud Monitoring Intelligence".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using official Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for step-by-step resource creation

## Architecture Overview

This solution deploys an intelligent database performance optimization system that combines:

- AlloyDB AI cluster with vector capabilities for advanced PostgreSQL workloads
- Cloud Monitoring integration for comprehensive performance metrics collection
- Vertex AI models for AI-driven performance analysis and optimization recommendations
- Cloud Functions for automated remediation and optimization implementation
- Cloud Scheduler for orchestrated performance monitoring cycles
- Vector search capabilities for pattern-based performance optimization

## Prerequisites

### General Requirements

- Google Cloud project with billing enabled
- gcloud CLI v450.0.0 or higher installed and configured
- Appropriate IAM permissions for resource creation
- Basic understanding of AlloyDB, Cloud Monitoring, and Vertex AI concepts
- PostgreSQL database administration knowledge

### Required APIs

The following APIs must be enabled in your Google Cloud project:

```bash
gcloud services enable alloydb.googleapis.com
gcloud services enable compute.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable aiplatform.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudscheduler.googleapis.com
gcloud services enable servicenetworking.googleapis.com
```

### Cost Considerations

Estimated costs for this deployment:
- AlloyDB cluster: $50-100 (primary instance with 4 vCPUs, 16GB RAM)
- Vertex AI usage: $10-20 (model training and predictions)
- Cloud Functions: $5-10 (automated optimization executions)
- Cloud Monitoring: $5-15 (custom metrics and dashboards)
- Network egress: $5-10 (depending on usage patterns)

**Total estimated monthly cost: $75-155**

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

1. Set up environment variables:

   ```bash
   export PROJECT_ID=$(gcloud config get-value project)
   export REGION="us-central1"
   
   # Generate unique suffix for resource names
   RANDOM_SUFFIX=$(openssl rand -hex 3)
   export DEPLOYMENT_NAME="alloydb-perf-${RANDOM_SUFFIX}"
   ```

2. Deploy the infrastructure:

   ```bash
   cd infrastructure-manager/
   
   # Create deployment
   gcloud infra-manager deployments apply ${DEPLOYMENT_NAME} \
       --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
       --location=${REGION} \
       --file=main.yaml \
       --inputs="project_id=${PROJECT_ID},region=${REGION},random_suffix=${RANDOM_SUFFIX}"
   ```

3. Monitor deployment progress:

   ```bash
   gcloud infra-manager deployments describe ${DEPLOYMENT_NAME} \
       --location=${REGION}
   ```

### Using Terraform

1. Initialize and configure Terraform:

   ```bash
   cd terraform/
   
   # Initialize Terraform
   terraform init
   
   # Copy and customize variables
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your specific values
   ```

2. Plan and apply the infrastructure:

   ```bash
   # Review planned changes
   terraform plan
   
   # Apply the infrastructure
   terraform apply
   ```

3. Access outputs:

   ```bash
   # View important connection information
   terraform output
   ```

### Using Bash Scripts

1. Set up environment variables:

   ```bash
   export PROJECT_ID=$(gcloud config get-value project)
   export REGION="us-central1"
   export ZONE="us-central1-a"
   
   # Generate unique suffix
   RANDOM_SUFFIX=$(openssl rand -hex 3)
   export CLUSTER_NAME="alloydb-perf-cluster-${RANDOM_SUFFIX}"
   ```

2. Run the deployment script:

   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

   The script will:
   - Enable required APIs
   - Create VPC network and private service connection
   - Deploy AlloyDB AI cluster with vector capabilities
   - Configure Cloud Monitoring metrics and alerting
   - Set up Vertex AI model for performance analysis
   - Deploy Cloud Functions for automated optimization
   - Configure Cloud Scheduler for regular monitoring
   - Create performance analytics dashboard

## Post-Deployment Setup

### 1. Configure Vector Search for Performance Analysis

Connect to your AlloyDB instance and run the vector search setup:

```bash
# Get AlloyDB connection details
ALLOYDB_IP=$(gcloud alloydb instances describe ${INSTANCE_NAME} \
    --cluster=${CLUSTER_NAME} \
    --region=${REGION} \
    --format="value(ipAddress)")

# Connect and run setup script (setup_vector_search.sql is generated during deployment)
psql -h ${ALLOYDB_IP} -U postgres -d postgres -f setup_vector_search.sql
```

### 2. Access Performance Dashboard

Navigate to the Cloud Monitoring dashboard:

```bash
echo "Dashboard URL: https://console.cloud.google.com/monitoring/dashboards"
```

### 3. Verify Automated Functions

Test the performance optimization function:

```bash
# Trigger a test optimization
gcloud pubsub topics publish alloydb-performance-events \
    --message='{"action":"test_optimization","cluster":"'${CLUSTER_NAME}'"}'

# Check function logs
gcloud functions logs read alloydb-performance-optimizer \
    --gen2 \
    --region=${REGION} \
    --limit=10
```

## Configuration Options

### AlloyDB Configuration

The deployment creates an AlloyDB cluster with the following specifications:
- **Instance type**: PRIMARY with 4 vCPUs and 16GB RAM
- **Availability**: Zonal deployment in us-central1-a
- **AI features**: Vector search enabled with ScaNN indexing
- **Network**: Private VPC with dedicated service connection

### Monitoring Configuration

- **Metrics collection**: Comprehensive AlloyDB performance metrics
- **Custom metrics**: AI-generated performance scores and optimization actions
- **Alerting**: Automated alerts for performance anomalies
- **Dashboard**: Real-time performance visualization

### AI/ML Configuration

- **Vertex AI**: AutoML tabular model for performance prediction
- **Model type**: Regression model for performance score prediction
- **Training budget**: 1000 milli-node hours for initial training
- **Prediction endpoint**: Deployed for real-time optimization recommendations

## Customization

### Variables Configuration

Edit the following files to customize your deployment:

#### Terraform Variables (`terraform/terraform.tfvars`)

```hcl
# Project configuration
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# AlloyDB configuration
alloydb_cpu_count    = 4
alloydb_memory_size  = "16GB"
alloydb_availability = "ZONAL"

# Monitoring configuration
enable_custom_dashboards = true
alert_notification_email = "admin@yourcompany.com"

# AI/ML configuration
vertex_ai_region = "us-central1"
model_training_budget = 1000
```

#### Infrastructure Manager Variables

Modify the inputs section in your deployment command:

```bash
--inputs="project_id=${PROJECT_ID},region=${REGION},alloydb_cpu_count=8,alloydb_memory_size=32GB"
```

### Advanced Configuration

#### Performance Optimization Tuning

Modify Cloud Functions environment variables:

```bash
# Update function configuration
gcloud functions deploy alloydb-performance-optimizer \
    --gen2 \
    --set-env-vars="OPTIMIZATION_THRESHOLD=0.8,MAX_OPTIMIZATIONS_PER_CYCLE=5"
```

#### Monitoring Frequency

Adjust Cloud Scheduler timing:

```bash
# Update scheduler for more frequent analysis (every 5 minutes)
gcloud scheduler jobs update pubsub performance-analyzer \
    --schedule="*/5 * * * *"
```

#### Vector Search Parameters

Customize vector search configuration in the SQL setup:

```sql
-- Adjust vector index parameters for your workload
CREATE INDEX ON performance_embeddings 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 200);  -- Increase for larger datasets
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **AlloyDB Performance Metrics**:
   - Query latency and throughput
   - CPU and memory utilization
   - Connection pool status
   - Buffer hit ratios

2. **AI Model Performance**:
   - Prediction accuracy scores
   - Model inference latency
   - Optimization recommendation effectiveness

3. **Automation Health**:
   - Cloud Functions execution success rate
   - Scheduler job completion status
   - Alert response times

### Accessing Logs

```bash
# AlloyDB logs
gcloud logging read "resource.type=alloydb_database" --limit=50

# Cloud Functions logs
gcloud functions logs read alloydb-performance-optimizer --gen2 --region=${REGION}

# Cloud Scheduler logs
gcloud logging read "resource.type=cloud_scheduler_job" --limit=20
```

### Performance Validation

Run the validation commands from the original recipe to ensure proper functioning:

```bash
# Test AlloyDB connectivity
gcloud alloydb clusters describe ${CLUSTER_NAME} --region=${REGION}

# Verify monitoring metrics
gcloud monitoring metrics list --filter="metric.type:alloydb"

# Test AI model endpoint
gcloud ai models list --region=${REGION} --filter="displayName:alloydb-performance-model"
```

## Troubleshooting

### Common Issues

1. **VPC Service Connection Failures**:
   - Ensure servicenetworking.googleapis.com API is enabled
   - Verify IP range allocation doesn't conflict with existing networks
   - Check IAM permissions for Service Networking Admin role

2. **AlloyDB Cluster Creation Timeouts**:
   - AlloyDB cluster creation can take 15-20 minutes
   - Monitor cluster status with: `gcloud alloydb operations list`
   - Ensure sufficient quota for AlloyDB resources in your region

3. **Cloud Functions Deployment Errors**:
   - Verify Cloud Functions API is enabled
   - Check source code dependencies in requirements.txt
   - Ensure proper IAM roles for Cloud Functions service account

4. **Vertex AI Model Training Failures**:
   - Verify sufficient quota for Vertex AI training
   - Check dataset format and column specifications
   - Monitor training job status in Vertex AI console

### Getting Help

- Check the [AlloyDB documentation](https://cloud.google.com/alloydb/docs)
- Review [Cloud Monitoring troubleshooting](https://cloud.google.com/monitoring/support/troubleshooting)
- Consult [Vertex AI debugging guide](https://cloud.google.com/vertex-ai/docs/general/troubleshooting)
- Access [Cloud Functions troubleshooting](https://cloud.google.com/functions/docs/troubleshooting)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete ${DEPLOYMENT_NAME} \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy

# Verify cleanup
terraform show
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

The cleanup process removes resources in the following order:
1. Cloud Scheduler jobs
2. Cloud Functions and Pub/Sub topics
3. Vertex AI models and datasets
4. AlloyDB instances and clusters
5. VPC networks and private service connections

### Manual Cleanup Verification

After running cleanup scripts, verify resource removal:

```bash
# Check for remaining AlloyDB resources
gcloud alloydb clusters list --region=${REGION}

# Verify Cloud Functions cleanup
gcloud functions list --region=${REGION}

# Check VPC networks
gcloud compute networks list --filter="name~alloydb-perf"

# Verify Vertex AI resources
gcloud ai models list --region=${REGION}
```

## Security Considerations

This deployment implements several security best practices:

- **Network Isolation**: AlloyDB clusters deployed in private VPC with no external access
- **IAM Least Privilege**: Service accounts configured with minimal required permissions
- **Encryption**: All data encrypted at rest and in transit using Google-managed keys
- **API Security**: Cloud Functions secured with proper authentication and authorization
- **Monitoring**: Comprehensive audit logging enabled for all resource access

### Additional Security Hardening

For production deployments, consider:

1. **Custom Service Accounts**: Create dedicated service accounts for each component
2. **VPC Security**: Implement firewall rules and private Google access
3. **Secret Management**: Use Secret Manager for sensitive configuration
4. **Audit Logging**: Enable detailed audit logs for compliance requirements
5. **Network Security**: Implement Cloud NAT for secure outbound connectivity

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation for detailed implementation guidance
2. Check Google Cloud Status page for service availability
3. Consult provider documentation for specific service configurations
4. Review Cloud Console for detailed error messages and recommendations

## Contributing

When modifying this infrastructure code:

1. Test changes in a development environment first
2. Follow Google Cloud best practices for resource naming and tagging
3. Update documentation to reflect any configuration changes
4. Validate security implications of modifications
5. Test both deployment and cleanup procedures