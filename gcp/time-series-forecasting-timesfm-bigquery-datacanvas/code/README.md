# Infrastructure as Code for Time Series Forecasting with TimesFM and BigQuery DataCanvas

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Time Series Forecasting with TimesFM and BigQuery DataCanvas".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Active Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - BigQuery Admin
  - Vertex AI User
  - Cloud Functions Admin
  - Cloud Scheduler Admin
  - Pub/Sub Admin
  - Cloud Storage Admin
  - Service Account Token Creator
- Basic understanding of time series data and financial analytics
- Estimated cost: $20-50 for complete deployment and testing

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create timesfm-forecasting \
    --location=us-central1 \
    --source=. \
    --input-values="project_id=$(gcloud config get-value project),region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe timesfm-forecasting \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Create terraform.tfvars file
cat > terraform.tfvars << EOF
project_id = "your-project-id"
region     = "us-central1"
EOF

# Plan deployment
terraform plan

# Apply configuration
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

# Follow the script prompts for configuration
```

## Architecture Overview

This infrastructure deploys a complete time series forecasting solution including:

- **BigQuery Dataset**: Dedicated dataset for financial time series data storage
- **BigQuery Tables**: Optimized tables for stock prices and forecast results
- **BigQuery Views**: Analytics-ready views for DataCanvas integration
- **Cloud Function**: Serverless data processing and forecast triggering
- **Cloud Scheduler**: Automated daily forecasting jobs
- **Pub/Sub Topics**: Event-driven data processing workflows
- **Vertex AI Integration**: TimesFM model deployment and management
- **Cloud Monitoring**: Performance tracking and alerting
- **IAM Roles**: Least-privilege service account configurations

## Configuration

### Infrastructure Manager Variables

Edit the input values in your deployment command or create a `variables.yaml` file:

```yaml
project_id: "your-project-id"
region: "us-central1"
dataset_name: "financial_forecasting"
function_memory: "512MB"
scheduler_timezone: "America/New_York"
forecast_symbols: ["AAPL", "GOOGL", "MSFT"]
```

### Terraform Variables

Customize `terraform.tfvars`:

```hcl
project_id          = "your-project-id"
region              = "us-central1"
dataset_name        = "financial_forecasting"
function_memory     = 512
scheduler_timezone  = "America/New_York"
forecast_horizon    = 7
confidence_level    = 0.95
forecast_symbols    = ["AAPL", "GOOGL", "MSFT"]

# Optional: Custom naming
resource_prefix     = "timesfm"
environment         = "production"

# Optional: Advanced configuration
enable_monitoring   = true
enable_alerting     = true
data_retention_days = 365
```

### Bash Script Configuration

Set environment variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export DATASET_NAME="financial_forecasting"
export ENVIRONMENT="production"

# Optional customizations
export FORECAST_HORIZON="7"
export CONFIDENCE_LEVEL="0.95"
export SCHEDULER_TIMEZONE="America/New_York"
```

## Post-Deployment Setup

### 1. BigQuery DataCanvas Workspace

After infrastructure deployment, set up DataCanvas workspace:

```bash
# Navigate to BigQuery Studio in Google Cloud Console
# Create new DataCanvas workspace
# Connect to the deployed dataset: ${project_id}.${dataset_name}
```

### 2. Load Sample Data

```bash
# The deployment includes sample financial data
# Verify data loading:
bq query --use_legacy_sql=false "
SELECT COUNT(*) as record_count, 
       MIN(date) as earliest_date,
       MAX(date) as latest_date
FROM \`${PROJECT_ID}.${DATASET_NAME}.stock_prices\`"
```

### 3. Test TimesFM Forecasting

```bash
# Generate initial forecasts
bq query --use_legacy_sql=false "
SELECT COUNT(*) as forecast_count,
       MIN(forecast_timestamp) as earliest_forecast,
       MAX(forecast_timestamp) as latest_forecast  
FROM \`${PROJECT_ID}.${DATASET_NAME}.timesfm_forecasts\`"
```

### 4. Verify Cloud Function

```bash
# Get function URL
FUNCTION_URL=$(gcloud functions describe forecast-processor \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

# Test with sample data
curl -X POST ${FUNCTION_URL} \
     -H "Content-Type: application/json" \
     -d '{
       "symbol": "TSLA",
       "date": "2024-01-15", 
       "close_price": 219.16,
       "volume": 42850000,
       "market_cap": 695000000000
     }'
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

The deployment creates custom dashboards for:

- Forecast accuracy metrics
- Data pipeline health
- Function execution metrics
- BigQuery query performance

Access dashboards:

```bash
# List available dashboards
gcloud monitoring dashboards list

# View forecast accuracy dashboard
echo "Navigate to Cloud Monitoring > Dashboards > TimesFM Forecast Accuracy"
```

### Alerting Policies

Automated alerting for:

- Forecast accuracy degradation (>15% error rate)
- Cloud Function failures
- BigQuery job failures
- Data freshness issues

### Log Analysis

```bash
# View Cloud Function logs
gcloud functions logs read forecast-processor --region=${REGION}

# View BigQuery audit logs
gcloud logging read "resource.type=bigquery_resource" --limit=50
```

## DataCanvas Usage Examples

After setting up the DataCanvas workspace, try these natural language queries:

### Basic Analytics
- "Show me the stock prices for AAPL over the last month"
- "What is the average forecast accuracy for all stocks?"
- "Which stock has the highest volatility?"

### Advanced Analysis
- "Compare actual vs predicted prices for GOOGL in the last week"
- "Show me stocks where forecasts are consistently outside confidence intervals"
- "Create a chart showing 7-day and 30-day moving averages for AAPL"

### Forecast Insights
- "What is the forecast for AAPL for the next 7 days?"
- "Show me the confidence intervals for all current forecasts"
- "Which forecasts have the highest uncertainty?"

## Troubleshooting

### Common Issues

1. **BigQuery Permission Errors**
   ```bash
   # Grant necessary permissions
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/bigquery.admin"
   ```

2. **Cloud Function Deployment Failures**
   ```bash
   # Check function status
   gcloud functions describe forecast-processor --region=${REGION}
   
   # View function logs
   gcloud functions logs read forecast-processor --region=${REGION}
   ```

3. **TimesFM Model Access Issues**
   ```bash
   # Verify Vertex AI API is enabled
   gcloud services list --enabled | grep aiplatform
   
   # Check model access permissions
   gcloud projects add-iam-policy-binding ${PROJECT_ID} \
       --member="user:your-email@domain.com" \
       --role="roles/aiplatform.user"
   ```

4. **Scheduler Job Failures**
   ```bash
   # Check scheduler job status
   gcloud scheduler jobs describe daily-forecast --location=${REGION}
   
   # View execution logs
   gcloud scheduler jobs run daily-forecast --location=${REGION}
   ```

### Performance Optimization

1. **BigQuery Query Optimization**
   - Use partitioned tables for time-based queries
   - Leverage clustering on symbol columns
   - Monitor slot usage and query costs

2. **Cloud Function Optimization**
   - Adjust memory allocation based on data volume
   - Implement connection pooling for BigQuery
   - Use concurrent processing for multiple symbols

3. **Forecast Accuracy Tuning**
   - Experiment with different forecast horizons
   - Adjust confidence levels based on business requirements
   - Consider ensemble forecasting for critical assets

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete timesfm-forecasting \
    --location=us-central1 \
    --delete-policy=DELETE
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm with 'yes' when prompted
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts to confirm resource deletion
```

### Manual Cleanup Verification

After running automated cleanup, verify complete removal:

```bash
# Check BigQuery datasets
bq ls

# Check Cloud Functions
gcloud functions list --regions=${REGION}

# Check Cloud Scheduler jobs
gcloud scheduler jobs list --locations=${REGION}

# Check service accounts
gcloud iam service-accounts list
```

## Security Considerations

### IAM Best Practices

- Service accounts use least-privilege permissions
- Function execution uses dedicated service account
- BigQuery access restricted to specific datasets
- Vertex AI access limited to required operations

### Data Protection

- BigQuery tables use customer-managed encryption keys (optional)
- Function environment variables encrypted at rest
- Audit logging enabled for all resource access
- VPC Service Controls recommended for production

### Network Security

- Cloud Functions use secure HTTPS endpoints
- BigQuery connections use private Google access
- Pub/Sub topics use IAM-based access control
- Cloud Scheduler uses service account authentication

## Cost Optimization

### Resource Sizing

- Cloud Function memory optimized for typical workloads
- BigQuery storage uses intelligent tiering
- Vertex AI resources scale based on demand
- Cloud Scheduler minimizes execution frequency

### Cost Monitoring

```bash
# Set up billing alerts
gcloud billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="TimesFM Forecasting Budget" \
    --budget-amount=100USD

# Monitor BigQuery costs
bq query --use_legacy_sql=false "
SELECT
  job_id,
  total_bytes_processed,
  total_slot_ms,
  ROUND(total_bytes_processed/1024/1024/1024, 2) as gb_processed
FROM \`${PROJECT_ID}.region-${REGION}\`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY total_bytes_processed DESC
LIMIT 10"
```

## Advanced Features

### Multi-Asset Portfolio Forecasting

Extend the solution for portfolio-level analysis:

```bash
# Add correlation analysis view
bq query --use_legacy_sql=false "
CREATE VIEW \`${PROJECT_ID}.${DATASET_NAME}.correlation_analysis\` AS
SELECT * FROM ML.CORR(
  SELECT symbol, date, close_price
  FROM \`${PROJECT_ID}.${DATASET_NAME}.stock_prices\`
  WHERE date >= DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH)
)"
```

### Real-time Market Data Integration

Connect external market data feeds:

```bash
# Create Pub/Sub topic for real-time data
gcloud pubsub topics create market-data-feed

# Configure Cloud Function trigger
gcloud functions deploy market-data-processor \
    --trigger-topic=market-data-feed \
    --runtime=python311
```

### Model Performance Analytics

Track forecast accuracy over time:

```bash
# Create performance tracking view
bq query --use_legacy_sql=false "
CREATE VIEW \`${PROJECT_ID}.${DATASET_NAME}.model_performance\` AS
SELECT 
  DATE_TRUNC(date, WEEK) as week,
  symbol,
  AVG(percentage_error) as avg_weekly_error,
  STDDEV(percentage_error) as error_volatility,
  COUNT(*) as forecast_count
FROM \`${PROJECT_ID}.${DATASET_NAME}.forecast_analytics\`
WHERE actual_value IS NOT NULL
GROUP BY week, symbol
ORDER BY week DESC, avg_weekly_error ASC"
```

## Support and Documentation

### Additional Resources

- [TimesFM Model Documentation](https://cloud.google.com/bigquery/docs/timesfm-model)
- [BigQuery DataCanvas Guide](https://cloud.google.com/bigquery/docs/data-canvas)
- [Vertex AI Integration Patterns](https://cloud.google.com/vertex-ai/docs/start/introduction-unified-platform)
- [Google Research TimesFM Paper](https://research.google/blog/a-decoder-only-foundation-model-for-time-series-forecasting/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Consult the original recipe documentation
4. Contact your cloud administrator for organization-specific policies

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment
2. Follow Google Cloud best practices
3. Update documentation for any modifications
4. Validate security configurations

---

**Note**: This infrastructure deploys a production-ready time series forecasting solution. Customize the configuration based on your specific business requirements, compliance needs, and cost constraints.