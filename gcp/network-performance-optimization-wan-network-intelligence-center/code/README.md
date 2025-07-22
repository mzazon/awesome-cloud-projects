# Infrastructure as Code for Network Performance Optimization with Cloud WAN and Network Intelligence Center

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Network Performance Optimization with Cloud WAN and Network Intelligence Center".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI installed and configured
- Google Cloud project with billing enabled
- Appropriate IAM permissions for:
  - Network Management
  - Cloud Functions
  - Cloud Monitoring
  - Pub/Sub
  - Cloud Storage
  - Cloud Scheduler
  - Compute Engine
- Basic understanding of network concepts (routing, latency, connectivity)
- Estimated cost: $50-200/month depending on network traffic volume and monitoring frequency

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment
gcloud infra-manager deployments create network-optimization \
    --location=${REGION} \
    --source=. \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Check deployment status
gcloud infra-manager deployments describe network-optimization \
    --location=${REGION}
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

# Review the deployment plan
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"

# Apply the configuration
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy the infrastructure
./scripts/deploy.sh
```

## Architecture Overview

This IaC deploys a comprehensive network performance optimization solution including:

### Core Components

- **Cloud WAN Configuration**: Global network connectivity optimization
- **Network Intelligence Center**: AI-powered network observability and insights
- **Connectivity Tests**: Automated network path validation
- **Flow Analyzer**: VPC Flow Logs analysis for traffic optimization
- **Performance Dashboard**: Real-time network performance monitoring
- **Network Analyzer**: Automated configuration monitoring
- **Firewall Insights**: Security and performance optimization

### Automation Components

- **Cloud Functions**: Serverless network optimization logic
- **Cloud Monitoring**: Performance metrics and alerting
- **Cloud Scheduler**: Periodic optimization and health checks
- **Pub/Sub**: Event-driven automation messaging
- **Cloud Storage**: Function code and data storage

## Configuration

### Environment Variables

Set the following environment variables before deployment:

```bash
export PROJECT_ID="your-project-id"          # Google Cloud project ID
export REGION="us-central1"                  # Primary deployment region
export ZONE="us-central1-a"                  # Primary zone for resources
export ENABLE_FLOW_LOGS="true"               # Enable VPC Flow Logs (optional)
export OPTIMIZATION_SCHEDULE="*/15 * * * *"  # Cron schedule for optimization
export ALERT_EMAIL="admin@example.com"       # Email for critical alerts (optional)
```

### Customization Options

#### Terraform Variables

The Terraform implementation supports the following variables:

- `project_id`: Google Cloud project ID (required)
- `region`: Primary deployment region (default: "us-central1")
- `zone`: Primary zone (default: "us-central1-a")
- `enable_flow_logs`: Enable VPC Flow Logs for analysis (default: true)
- `optimization_schedule`: Cron schedule for periodic optimization (default: "*/15 * * * *")
- `alert_email`: Email address for critical alerts (optional)
- `function_memory`: Memory allocation for Cloud Functions (default: "256MB")
- `log_retention_days`: Log retention period in days (default: 30)

#### Infrastructure Manager Variables

The Infrastructure Manager implementation uses similar variables defined in the YAML configuration file.

## Deployment Steps

### 1. Pre-deployment Validation

```bash
# Verify authentication
gcloud auth list

# Verify project access
gcloud config get-value project

# Check required APIs (will be enabled during deployment)
gcloud services list --enabled
```

### 2. Deploy Infrastructure

Choose one of the deployment methods above based on your preference and organizational standards.

### 3. Post-deployment Verification

```bash
# Verify Network Intelligence Center connectivity tests
gcloud network-management connectivity-tests list

# Check Cloud Functions deployment
gcloud functions list --regions=${REGION}

# Verify monitoring policies
gcloud alpha monitoring policies list

# Check scheduled jobs
gcloud scheduler jobs list
```

## Testing the Deployment

### 1. Test Connectivity Tests

```bash
# Run a connectivity test
gcloud network-management connectivity-tests run regional-connectivity-test

# Check test results
gcloud network-management connectivity-tests describe regional-connectivity-test \
    --format="value(reachabilityDetails.result)"
```

### 2. Test Network Optimization Function

```bash
# Get the Pub/Sub topic name
TOPIC_NAME=$(gcloud pubsub topics list --format="value(name)" --filter="name:network-alerts")

# Publish a test message
gcloud pubsub topics publish ${TOPIC_NAME} \
    --message='{"type":"test","latency":150,"throughput":500000}'

# Check function logs
gcloud functions logs read network-optimizer --region=${REGION} --limit=10
```

### 3. Validate Flow Analysis

```bash
# Trigger flow analysis manually
FLOW_ANALYZER_URL=$(gcloud functions describe flow-analyzer \
    --region=${REGION} \
    --format="value(httpsTrigger.url)")

curl -X GET "${FLOW_ANALYZER_URL}"
```

## Monitoring and Maintenance

### Key Metrics to Monitor

- Network latency and throughput metrics
- Connectivity test success rates
- Cloud Function execution success rates
- Flow analysis optimization opportunities
- Firewall rule optimization recommendations

### Log Analysis

```bash
# View Cloud Function logs
gcloud functions logs read network-optimizer --region=${REGION}

# View scheduler job logs
gcloud logging read "resource.type=cloud_scheduler_job" --limit=50

# View network connectivity test logs
gcloud logging read "resource.type=network_management" --limit=50
```

### Performance Tuning

- Adjust Cloud Function memory allocation based on processing requirements
- Modify optimization schedules based on network change frequency
- Tune alert thresholds based on baseline performance metrics
- Customize firewall rule analysis based on security requirements

## Cleanup

### Using Infrastructure Manager

```bash
# Delete the deployment
gcloud infra-manager deployments delete network-optimization \
    --location=${REGION} \
    --quiet
```

### Using Terraform

```bash
# Navigate to Terraform directory
cd terraform/

# Destroy all resources
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Run the cleanup script
./scripts/destroy.sh
```

### Manual Cleanup Verification

```bash
# Verify Cloud Functions are deleted
gcloud functions list --regions=${REGION}

# Verify Pub/Sub resources are deleted
gcloud pubsub topics list
gcloud pubsub subscriptions list

# Verify monitoring policies are deleted
gcloud alpha monitoring policies list

# Verify scheduled jobs are deleted
gcloud scheduler jobs list

# Verify Cloud Storage buckets are deleted
gsutil ls
```

## Troubleshooting

### Common Issues

#### API Enablement Errors

```bash
# Enable required APIs manually
gcloud services enable networkmanagement.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable pubsub.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable compute.googleapis.com
```

#### IAM Permission Issues

Ensure your account has the following roles:
- Network Management Admin
- Cloud Functions Admin
- Monitoring Admin
- Pub/Sub Admin
- Storage Admin
- Cloud Scheduler Admin

#### Connectivity Test Failures

```bash
# Check VPC network configuration
gcloud compute networks list

# Verify firewall rules
gcloud compute firewall-rules list

# Check subnet configuration
gcloud compute networks subnets list
```

#### Cloud Function Deployment Issues

```bash
# Check function deployment status
gcloud functions describe network-optimizer --region=${REGION}

# View detailed deployment logs
gcloud logging read "resource.type=cloud_function" --limit=50
```

### Getting Help

- [Google Cloud WAN Documentation](https://cloud.google.com/solutions/cross-cloud-network)
- [Network Intelligence Center Documentation](https://cloud.google.com/network-intelligence-center/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)

## Security Considerations

- All Cloud Functions use least privilege IAM roles
- VPC Flow Logs are configured with appropriate sampling rates
- Firewall rules are analyzed for security optimization
- Network traffic is encrypted in transit
- Monitoring data includes security-relevant metrics

## Cost Optimization

- Cloud Functions use pay-per-execution model
- VPC Flow Logs use sampling to reduce costs
- Monitoring policies are configured with appropriate retention periods
- Storage buckets use lifecycle policies for cost management
- Scheduled jobs run at optimal intervals to balance cost and performance

## Support

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review the original recipe documentation
3. Consult Google Cloud documentation for specific services
4. Contact your Google Cloud support representative for complex issues

## Contributing

When modifying this infrastructure code:

1. Test changes in a development project first
2. Update variable documentation
3. Verify security best practices
4. Update this README with any new requirements or procedures