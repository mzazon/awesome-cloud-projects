# Infrastructure as Code for Sustainability Compliance Automation with Carbon Footprint and Functions

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Sustainability Compliance Automation with Carbon Footprint and Functions".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (`gcloud`) installed and configured
- Project with billing enabled and Carbon Footprint access
- IAM permissions: Billing Account Viewer, BigQuery Admin, Cloud Functions Admin, Cloud Scheduler Admin
- For Terraform: Terraform CLI installed (version 1.0+)
- For Infrastructure Manager: Cloud Resource Manager API enabled

## Quick Start

### Using Infrastructure Manager (GCP)

```bash
# Enable required APIs
gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable config.googleapis.com

# Create deployment
gcloud infra-manager deployments create sustainability-compliance \
    --location=us-central1 \
    --source-blueprint=infrastructure-manager/main.yaml \
    --input-values project_id=$(gcloud config get-value project),region=us-central1
```

### Using Terraform

```bash
cd terraform/

# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"

# Apply the configuration
terraform apply \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# The script will prompt for project ID and region
# Or set environment variables:
# export PROJECT_ID="your-project-id"
# export REGION="us-central1"
# ./scripts/deploy.sh
```

## Architecture Overview

This infrastructure creates:

- **BigQuery Dataset**: For storing carbon footprint data and analytics
- **Cloud Functions**: Three functions for data processing, report generation, and alerts
- **Cloud Scheduler**: Automated job scheduling for sustainability workflows
- **Data Transfer Service**: Carbon footprint data export configuration
- **Cloud Storage**: ESG report storage bucket
- **IAM Roles**: Appropriate service account permissions

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment accepts these input values:

- `project_id`: GCP project ID (required)
- `region`: Deployment region (default: us-central1)
- `random_suffix`: Unique suffix for resources (auto-generated if not provided)
- `dataset_location`: BigQuery dataset location (default: US)
- `monthly_threshold`: Carbon emissions alert threshold in kg CO2e (default: 1000)
- `growth_threshold`: Growth rate alert threshold as decimal (default: 0.15)

### Terraform Variables

Edit `terraform/terraform.tfvars` or pass variables via command line:

```bash
# Example terraform.tfvars
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
dataset_location = "US"
monthly_emissions_threshold = 1000
growth_rate_threshold = 0.15
```

### Bash Script Variables

The deploy script supports these environment variables:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export DATASET_LOCATION="US"
export MONTHLY_THRESHOLD="1000"
export GROWTH_THRESHOLD="0.15"
```

## Validation

After deployment, verify the infrastructure:

```bash
# Check BigQuery dataset
bq ls --format="table(datasetId,location)" ${PROJECT_ID}

# Verify Cloud Functions
gcloud functions list --regions=${REGION}

# Check Cloud Scheduler jobs
gcloud scheduler jobs list

# Test a function endpoint
curl -X POST "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/carbon-alerts-${RANDOM_SUFFIX}" \
     -H "Content-Type: application/json" \
     -d '{"test": true}'
```

## Monitoring and Logs

Monitor your sustainability compliance system:

```bash
# View function logs
gcloud functions logs read process-carbon-data --region=${REGION}
gcloud functions logs read generate-esg-report --region=${REGION}
gcloud functions logs read carbon-alerts --region=${REGION}

# Check scheduler job executions
gcloud scheduler jobs describe process-carbon-data

# Monitor BigQuery job history
bq ls -j --max_results=10
```

## Carbon Footprint Data Access

The Carbon Footprint API requires:

1. **Billing Account Access**: Service account needs `roles/billing.viewer`
2. **Data Availability**: Carbon data has a 1-month delay
3. **Export Schedule**: Data exports automatically on the 15th of each month
4. **Covered Services**: Only covered Google Cloud services generate emissions data

## ESG Reporting

Generated reports include:

- **Monthly Trends**: Time-series emissions data with moving averages
- **Service Breakdown**: Emissions by Google Cloud service with percentages
- **Scope Analysis**: Scope 1, 2 (location and market-based), and 3 emissions
- **Growth Analysis**: Month-over-month emission changes
- **Compliance Metadata**: GHG Protocol methodology and reporting periods

Reports are stored in Cloud Storage with naming pattern: `esg-report-YYYY-MM-DD.json`

## Alerts and Thresholds

The system monitors for:

- **Threshold Exceeded**: Monthly emissions above configured limit
- **High Growth**: Month-over-month growth exceeding percentage threshold
- **Data Anomalies**: Unusual patterns in emissions data

Alert types:
- `THRESHOLD_EXCEEDED`: Monthly emissions > threshold
- `HIGH_GROWTH`: Growth rate > configured percentage
- `NORMAL`: No alerts triggered

## Cost Optimization

To minimize costs:

1. **Function Memory**: Adjust memory allocation based on data volume
2. **Scheduler Frequency**: Optimize job schedules for your reporting needs
3. **BigQuery Storage**: Use table expiration for historical data
4. **Cloud Storage**: Configure lifecycle policies for report retention

Estimated monthly costs:
- BigQuery: $2-5 (storage and queries)
- Cloud Functions: $1-3 (invocations and compute)
- Cloud Scheduler: $0.10-0.50 (job executions)
- Cloud Storage: $0.50-2 (report storage)

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete sustainability-compliance \
    --location=us-central1 \
    --quiet
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=$(gcloud config get-value project)" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh

# The script will prompt for confirmation before deleting resources
```

## Troubleshooting

### Common Issues

1. **Carbon Footprint Access Denied**
   ```bash
   # Verify billing account permissions
   gcloud projects get-iam-policy ${PROJECT_ID}
   ```

2. **Function Deployment Fails**
   ```bash
   # Check API enablement
   gcloud services list --enabled | grep functions
   ```

3. **Data Transfer Setup Issues**
   ```bash
   # Verify BigQuery Data Transfer API
   gcloud services enable bigquerydatatransfer.googleapis.com
   ```

4. **Scheduler Job Failures**
   ```bash
   # Check job logs
   gcloud scheduler jobs describe carbon-alerts-check
   ```

### Debug Commands

```bash
# Enable debug logging for gcloud
export CLOUDSDK_CORE_VERBOSITY=debug

# Test function locally (requires Functions Framework)
cd carbon-processing-function/
functions-framework --target=process_carbon_data --debug

# Validate Terraform configuration
cd terraform/
terraform validate
terraform fmt -check
```

## Security Considerations

This infrastructure implements:

- **Least Privilege IAM**: Functions use minimal required permissions
- **VPC Connector**: Optional private networking for functions
- **Encryption**: Data encrypted at rest and in transit
- **Access Controls**: BigQuery dataset and Cloud Storage bucket access restrictions
- **Audit Logging**: Cloud Audit Logs enabled for compliance tracking

## Compliance and Governance

The solution supports:

- **GHG Protocol Compliance**: Standard scope 1, 2, and 3 emissions tracking
- **Audit Trails**: Complete data lineage and processing logs
- **Data Retention**: Configurable retention policies for compliance requirements
- **Access Logs**: Comprehensive logging of data access and modifications
- **Regulatory Reporting**: Standardized ESG report formats for various frameworks

## Support and Documentation

- **Recipe Documentation**: Refer to the original recipe markdown file
- **Google Cloud Carbon Footprint**: [Official Documentation](https://cloud.google.com/carbon-footprint/docs)
- **BigQuery Best Practices**: [Performance and Cost Optimization](https://cloud.google.com/bigquery/docs/best-practices-performance)
- **Cloud Functions**: [Development and Deployment Guide](https://cloud.google.com/functions/docs)
- **Infrastructure Manager**: [Getting Started Guide](https://cloud.google.com/infrastructure-manager/docs)

## Contributing

To modify this infrastructure:

1. Update the appropriate IaC files (Infrastructure Manager, Terraform, or scripts)
2. Test changes in a development environment
3. Validate against the original recipe requirements
4. Update this README with any new configuration options

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support resources.