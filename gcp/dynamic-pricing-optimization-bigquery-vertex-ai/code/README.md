# Infrastructure as Code for Dynamic Pricing Optimization using BigQuery and Vertex AI

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Dynamic Pricing Optimization using BigQuery and Vertex AI".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- Owner/Editor permissions on the project
- Google Cloud CLI (gcloud) installed and configured
- Basic knowledge of SQL, machine learning concepts, and pricing strategies

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Google Cloud CLI with Infrastructure Manager API enabled
- `gcloud infra-manager` commands available

#### Terraform
- Terraform CLI (>= 1.5.0) installed
- Google Cloud Provider for Terraform
- Service account with appropriate permissions

#### Bash Scripts
- Bash shell environment
- `gsutil`, `bq`, and other Google Cloud CLI tools
- `curl` and `jq` for API testing

### Required APIs
The following Google Cloud APIs must be enabled:
- BigQuery API (`bigquery.googleapis.com`)
- Vertex AI API (`aiplatform.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Scheduler API (`cloudscheduler.googleapis.com`)
- Cloud Storage API (`storage.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Artifact Registry API (`artifactregistry.googleapis.com`)

### Estimated Costs
- BigQuery: $20-35 for queries and storage
- Vertex AI: $15-25 for training and predictions
- Cloud Functions: $5-10 for executions
- Cloud Storage: $2-5 for data storage
- **Total estimated cost: $42-75** for the complete solution

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com \
    config.googleapis.com \
    infra-manager.googleapis.com

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/pricing-optimization \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/${PROJECT_ID}/locations/${REGION}/deployments/pricing-optimization
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply infrastructure
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Test the deployment
./scripts/test.sh

# View deployment status
gcloud functions list --regions=${REGION}
bq ls ${PROJECT_ID}:pricing_optimization
```

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/inputs.yaml`:

```yaml
project_id: "your-project-id"
region: "us-central1"
dataset_name: "pricing_optimization"
model_name: "pricing_model"
function_memory: "512Mi"
function_timeout: "60s"
scheduler_frequency: "0 */6 * * *"  # Every 6 hours
enable_monitoring: true
```

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass via command line:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
dataset_name = "pricing_optimization"
model_name = "pricing_model"
bucket_name_suffix = "unique-suffix"
function_memory = "512Mi"
function_timeout = "60s"
scheduler_frequency = "0 */6 * * *"
enable_monitoring = true
tags = {
  environment = "production"
  team = "data-science"
  cost-center = "analytics"
}
```

### Bash Script Configuration

Edit environment variables in `scripts/config.sh`:

```bash
# Project Configuration
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Resource Configuration
export DATASET_NAME="pricing_optimization"
export MODEL_NAME="pricing_model"
export FUNCTION_MEMORY="512Mi"
export FUNCTION_TIMEOUT="60s"
export SCHEDULER_FREQUENCY="0 */6 * * *"

# Feature Flags
export ENABLE_MONITORING="true"
export LOAD_SAMPLE_DATA="true"
export CREATE_DASHBOARD="true"
```

## Deployment Architecture

The infrastructure creates the following resources:

### Data Layer
- **BigQuery Dataset**: Central data warehouse for pricing data
- **BigQuery Tables**: Sales history, competitor pricing, and analytics tables
- **BigQuery ML Model**: Linear regression model for pricing predictions
- **Cloud Storage Bucket**: Storage for training data and model artifacts

### Machine Learning Layer
- **Vertex AI Custom Training Job**: Advanced pricing model using Random Forest
- **Vertex AI Model Registry**: Model versioning and lifecycle management
- **Vertex AI Endpoints**: Production model serving infrastructure

### Application Layer
- **Cloud Functions**: Serverless pricing optimization API
- **Cloud Scheduler**: Automated pricing update jobs
- **Cloud Run** (optional): Alternative container-based deployment

### Monitoring & Operations
- **Cloud Monitoring Dashboard**: Pricing system performance metrics
- **Cloud Logging**: Centralized log aggregation
- **Error Reporting**: Automated error detection and alerting
- **Cloud Trace**: Distributed tracing for performance optimization

## Testing and Validation

### Post-Deployment Testing

```bash
# Test BigQuery ML model
bq query --use_legacy_sql=false \
  "SELECT * FROM ML.EVALUATE(MODEL \`${PROJECT_ID}.pricing_optimization.pricing_prediction_model\`)"

# Test Cloud Function
FUNCTION_URL=$(gcloud functions describe pricing-optimizer \
  --region=${REGION} --format="value(httpsTrigger.url)")

curl -X POST ${FUNCTION_URL} \
  -H "Content-Type: application/json" \
  -d '{"product_id": "PROD001"}' | jq '.'

# Test Vertex AI training job
gcloud ai custom-jobs list --region=${REGION}

# Test Cloud Scheduler
gcloud scheduler jobs list --location=${REGION}
```

### Performance Benchmarks

Expected performance metrics:
- **BigQuery ML Model**: R² score > 0.7, training time < 5 minutes
- **Cloud Function**: Response time < 2 seconds, 99.9% availability
- **Vertex AI Training**: Training completion < 15 minutes
- **Pricing Updates**: Complete product catalog processing < 30 minutes

## Monitoring and Alerts

### Key Metrics to Monitor

1. **Model Performance**:
   - Prediction accuracy (R² score)
   - Model drift detection
   - Training job success rate

2. **System Performance**:
   - Cloud Function execution time
   - BigQuery query performance
   - API response times

3. **Business Metrics**:
   - Price change frequency
   - Revenue impact
   - Competitive positioning

### Setting Up Alerts

```bash
# Create alerting policy for function errors
gcloud alpha monitoring policies create \
  --policy-from-file=monitoring/function-error-policy.yaml

# Create uptime check for pricing API
gcloud monitoring uptime create-uptime-check \
  --display-name="Pricing API Uptime Check" \
  --http-check-path="/health" \
  --hostname=${FUNCTION_URL}
```

## Troubleshooting

### Common Issues

1. **BigQuery ML Model Training Fails**:
   ```bash
   # Check dataset permissions
   bq show ${PROJECT_ID}:pricing_optimization
   
   # Verify training data format
   bq head -n 10 ${PROJECT_ID}:pricing_optimization.sales_history
   ```

2. **Cloud Function Deployment Errors**:
   ```bash
   # Check function logs
   gcloud functions logs read pricing-optimizer --region=${REGION}
   
   # Verify service account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

3. **Vertex AI Training Job Issues**:
   ```bash
   # Check training job details
   gcloud ai custom-jobs describe JOB_ID --region=${REGION}
   
   # Review training logs
   gcloud logging read "resource.type=aiplatform_job"
   ```

### Performance Optimization

1. **BigQuery Optimization**:
   - Partition tables by date for better query performance
   - Use clustering on frequently filtered columns
   - Implement incremental model training

2. **Cloud Function Optimization**:
   - Increase memory allocation for complex calculations
   - Implement connection pooling for BigQuery
   - Use caching for frequently accessed data

3. **Cost Optimization**:
   - Use BigQuery slots for predictable workloads
   - Implement Vertex AI Batch predictions for bulk processing
   - Schedule training jobs during off-peak hours

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/pricing-optimization

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Clean up state files
rm terraform.tfstate terraform.tfstate.backup
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup
gcloud functions list --regions=${REGION}
bq ls ${PROJECT_ID}:pricing_optimization 2>/dev/null || echo "Dataset deleted"
gsutil ls gs://${BUCKET_NAME} 2>/dev/null || echo "Bucket deleted"
```

### Manual Cleanup Verification

```bash
# Check remaining resources
echo "Checking Cloud Functions..."
gcloud functions list --regions=${REGION}

echo "Checking BigQuery datasets..."
bq ls --project_id=${PROJECT_ID}

echo "Checking Cloud Storage buckets..."
gsutil ls -p ${PROJECT_ID}

echo "Checking Vertex AI resources..."
gcloud ai models list --region=${REGION}

echo "Checking Cloud Scheduler jobs..."
gcloud scheduler jobs list --location=${REGION}
```

## Advanced Configuration

### Multi-Environment Setup

For production deployments, consider:

1. **Separate Projects**: Use different projects for dev/staging/prod
2. **Environment-Specific Configuration**: Adjust model parameters per environment
3. **CI/CD Integration**: Automate deployments using Cloud Build
4. **Security Hardening**: Implement VPC Service Controls and Private Google Access

### High Availability Configuration

```bash
# Multi-region deployment
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"

# Deploy to multiple regions
./scripts/deploy.sh --region=${PRIMARY_REGION}
./scripts/deploy.sh --region=${SECONDARY_REGION}
```

### Integration with External Systems

1. **ERP Integration**: Connect with existing ERP systems for inventory data
2. **E-commerce Platform**: Integrate with Shopify, Magento, or custom platforms
3. **Competitor API**: Automate competitor price collection
4. **Business Intelligence**: Connect with Looker or Data Studio for visualization

## Security Considerations

### IAM Best Practices

```bash
# Create dedicated service account
gcloud iam service-accounts create pricing-optimization-sa \
  --display-name="Pricing Optimization Service Account"

# Grant minimal required permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:pricing-optimization-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor"
```

### Data Protection

1. **Encryption**: All data encrypted at rest and in transit
2. **Access Controls**: Implement row-level security in BigQuery
3. **Audit Logging**: Enable Cloud Audit Logs for compliance
4. **Data Residency**: Configure appropriate data locations

## Support and Resources

### Documentation Links

- [BigQuery ML Documentation](https://cloud.google.com/bigquery-ml/docs)
- [Vertex AI Documentation](https://cloud.google.com/vertex-ai/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

### Community Resources

- [Google Cloud Pricing Optimization Solutions](https://cloud.google.com/solutions/retail/pricing-optimization)
- [ML-Powered Retail Solutions](https://cloud.google.com/solutions/retail)
- [BigQuery ML Community](https://cloud.google.com/bigquery-ml/docs/tutorials)

### Getting Help

For issues with this infrastructure code:
1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Consult the troubleshooting section above
4. Review logs using Cloud Logging
5. Contact Google Cloud Support for platform issues

---

**Note**: This infrastructure implements a production-ready dynamic pricing optimization solution. Always test in a development environment before deploying to production, and ensure compliance with your organization's data governance and security policies.