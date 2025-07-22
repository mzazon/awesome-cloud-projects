# Infrastructure as Code for Climate Risk Assessment with Earth Engine and BigQuery

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Implementing Climate Risk Assessment with Earth Engine and BigQuery".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud Provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v400.0.0 or later installed and configured
- Google Cloud project with billing enabled
- Earth Engine account registration (free at https://earthengine.google.com)
- Appropriate permissions for:
  - Earth Engine API access
  - BigQuery dataset and table creation
  - Cloud Functions deployment
  - Cloud Storage bucket creation
  - Cloud Monitoring metrics creation
  - IAM role management

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Create deployment using Google Cloud's native IaC
gcloud infra-manager deployments apply projects/PROJECT_ID/locations/REGION/deployments/climate-risk-deployment \
    --service-account SERVICE_ACCOUNT_EMAIL \
    --local-source "." \
    --inputs-file inputs.yaml
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Deploy infrastructure
terraform apply

# Confirm deployment
terraform show
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy all resources
./scripts/deploy.sh

# Verify deployment
./scripts/validate.sh
```

## Architecture Overview

This infrastructure creates a complete climate risk assessment system including:

- **Earth Engine Integration**: Cloud Functions for satellite data processing
- **BigQuery Analytics**: Datasets, tables, and views for climate risk analysis
- **Cloud Storage**: Intermediate data storage and processing artifacts
- **Cloud Monitoring**: Custom metrics and alerting for risk monitoring
- **IAM Security**: Least-privilege service accounts and roles

## Cost Considerations

Estimated monthly costs for this infrastructure:

- BigQuery: $25-50 for data analysis and storage
- Cloud Functions: $10-20 for processing satellite data
- Cloud Storage: $5-10 for intermediate data storage
- Cloud Monitoring: $5-10 for custom metrics
- Earth Engine: Free for research use, commercial licensing may apply

**Total Estimated Cost**: $45-90 per month (varies by usage patterns)

## Configuration Options

### Infrastructure Manager Configuration

The `inputs.yaml` file allows customization of:

```yaml
# Project and region settings
project_id: "your-project-id"
region: "us-central1"

# Resource naming
resource_suffix: "prod"
dataset_location: "US"

# Processing parameters
climate_analysis_region: [-125, 25, -66, 49]  # Continental US bounds
analysis_start_date: "2020-01-01"
analysis_end_date: "2023-12-31"

# Monitoring settings
risk_threshold_percentage: 25.0
alert_email: "your-email@domain.com"
```

### Terraform Variables

Configure the deployment through `terraform.tfvars`:

```hcl
# Required variables
project_id = "your-project-id"
region     = "us-central1"

# Optional customization
resource_suffix = "dev"
dataset_location = "US"
function_memory = 2048
function_timeout = 540

# Climate analysis parameters
climate_bounds = [-125, 25, -66, 49]
start_date = "2020-01-01"
end_date = "2023-12-31"

# Monitoring configuration
high_risk_threshold = 25.0
notification_email = "alerts@your-domain.com"
```

## Resource Details

### BigQuery Resources

- **Dataset**: `climate_risk_SUFFIX` - Main dataset for climate data
- **Tables**:
  - `climate_indicators` - Raw satellite data indicators
  - `climate_extremes` - Processed extreme weather events
  - `risk_assessments` - Final risk scores and recommendations
- **Views**:
  - `climate_risk_analysis` - Comprehensive risk analysis
  - `risk_dashboard_summary` - Dashboard support queries

### Cloud Functions

- **climate-processor**: Processes Earth Engine satellite data
- **climate-monitor**: Monitors risk levels and generates alerts

### Cloud Storage

- **climate-data-bucket**: Stores intermediate processing data and artifacts

### IAM Roles

- **Earth Engine Service Account**: Limited permissions for satellite data access
- **BigQuery Data Editor**: Permissions for climate data processing
- **Cloud Functions Runtime**: Execution permissions for processing functions

## Validation & Testing

After deployment, verify the infrastructure:

```bash
# Check BigQuery dataset
bq ls --project_id YOUR_PROJECT_ID

# Verify Cloud Functions
gcloud functions list --region YOUR_REGION

# Test climate data processing
curl -X POST FUNCTION_URL \
    -H "Content-Type: application/json" \
    -d '{"region_bounds": [-104, 37, -94, 41], "dataset_id": "climate_risk_SUFFIX"}'

# Query risk analysis results
bq query --use_legacy_sql=false \
    "SELECT risk_category, COUNT(*) as locations FROM \`PROJECT_ID.climate_risk_SUFFIX.climate_risk_analysis\` GROUP BY risk_category"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete projects/PROJECT_ID/locations/REGION/deployments/climate-risk-deployment
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy

# Confirm cleanup
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify cleanup completed
./scripts/validate-cleanup.sh
```

## Monitoring and Alerting

The infrastructure includes monitoring for:

- **Climate Risk Metrics**: Percentage of high-risk locations
- **Data Processing Health**: Function execution success rates
- **BigQuery Performance**: Query execution times and costs
- **Earth Engine Usage**: API request volumes and quotas

Configure alerts in Cloud Monitoring console or through the provided alerting policies.

## Security Considerations

This infrastructure implements security best practices:

- **Service Account Isolation**: Separate service accounts for different functions
- **IAM Least Privilege**: Minimal permissions for each component
- **Network Security**: VPC controls for function execution
- **Data Encryption**: Encryption at rest and in transit for all data
- **Audit Logging**: Comprehensive logging for all resource access

## Troubleshooting

### Common Issues

1. **Earth Engine Authentication**: Ensure service account has Earth Engine access
2. **BigQuery Permissions**: Verify dataset creation permissions
3. **Function Timeouts**: Increase memory/timeout for large regions
4. **API Quotas**: Monitor Earth Engine and BigQuery API limits

### Debug Commands

```bash
# Check function logs
gcloud functions logs read FUNCTION_NAME --region REGION

# Verify BigQuery job status
bq ls -j --max_results 10

# Test Earth Engine connectivity
gcloud auth application-default login
python -c "import ee; ee.Initialize(); print('Earth Engine connected')"
```

## Extension Opportunities

Enhance this infrastructure by:

1. **Adding Real-time Alerts**: Integrate with Cloud Pub/Sub for immediate notifications
2. **Implementing ML Models**: Use BigQuery ML for predictive risk modeling
3. **Creating Dashboards**: Deploy Looker Studio dashboards for visualization
4. **Adding Data Sources**: Integrate additional satellite datasets and ground stations
5. **Scaling Analysis**: Expand to global or multi-regional analysis

## Support

For issues with this infrastructure code:

1. Review the original recipe documentation
2. Check Google Cloud documentation for specific services
3. Verify Earth Engine API limits and quotas
4. Consult BigQuery best practices for geospatial analysis

## Version Information

- **Infrastructure Manager**: Uses latest Google Cloud resource types
- **Terraform**: Compatible with Google Cloud Provider v4.0+
- **Earth Engine**: Supports Earth Engine Python API v0.1.360+
- **BigQuery**: Optimized for BigQuery Standard SQL and ML features

## License

This infrastructure code is provided under the same license as the original recipe documentation.