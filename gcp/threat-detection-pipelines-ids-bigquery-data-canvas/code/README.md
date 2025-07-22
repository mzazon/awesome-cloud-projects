# Infrastructure as Code for Threat Detection Pipelines with Cloud IDS and BigQuery Data Canvas

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Threat Detection Pipelines with Cloud IDS and BigQuery Data Canvas".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 400.0.0 or later)
- Google Cloud project with billing enabled
- Project Owner or Security Admin permissions for:
  - Cloud IDS
  - BigQuery
  - Cloud Functions
  - Pub/Sub
  - Compute Engine
  - VPC Service Networking
- Understanding of network security concepts and threat detection
- Estimated cost: $200-500/month (varies by traffic volume and analysis complexity)

## Quick Start

### Using Infrastructure Manager (Recommended for GCP)

```bash
# Navigate to Infrastructure Manager configuration
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the infrastructure
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/threat-detection-pipeline \
    --service-account projects/${PROJECT_ID}/serviceAccounts/infra-manager@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="."
```

### Using Terraform

```bash
# Navigate to Terraform configuration
cd terraform/

# Initialize Terraform
terraform init

# Review the planned infrastructure changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply the infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/destroy.sh

# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy the complete solution
./scripts/deploy.sh
```

## Architecture Overview

This implementation deploys a comprehensive threat detection pipeline including:

- **Cloud IDS Endpoint**: Network intrusion detection using Palo Alto Networks technology
- **VPC Network**: Custom network with private services access for secure communication
- **Packet Mirroring**: Traffic mirroring configuration for IDS analysis
- **BigQuery**: Data warehouse for threat analytics with sample datasets
- **Cloud Functions**: Serverless processing for threat data transformation and alerting
- **Pub/Sub**: Event-driven messaging for real-time threat processing
- **Test VMs**: Sample virtual machines for traffic generation and monitoring

## Configuration Options

### Infrastructure Manager Variables

Edit `infrastructure-manager/main.yaml` to customize:

```yaml
imports:
  - path: threat-detection-config.yaml
    name: config

resources:
  - name: threat-detection-pipeline
    type: threat-detection-config.yaml
    properties:
      project_id: "your-project-id"
      region: "us-central1"
      zone: "us-central1-a"
      network_name: "threat-detection-vpc"
      ids_severity: "INFORMATIONAL"
```

### Terraform Variables

Configure in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region     = "us-central1"
zone       = "us-central1-a"

# Network configuration
network_name    = "threat-detection-vpc"
subnet_name     = "threat-detection-subnet"
subnet_cidr     = "10.0.1.0/24"

# IDS configuration
ids_severity = "INFORMATIONAL"

# BigQuery configuration
dataset_location = "us-central1"

# Function configuration
function_memory    = "512MB"
function_timeout   = "120s"

# Tags for resource organization
common_tags = {
  environment = "production"
  purpose     = "threat-detection"
  managed_by  = "terraform"
}
```

### Bash Script Environment Variables

Set these variables before running scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export NETWORK_NAME="threat-detection-vpc"
export SUBNET_NAME="threat-detection-subnet"
export IDS_SEVERITY="INFORMATIONAL"
```

## Deployment Details

### Network Infrastructure

- Creates custom VPC network with private Google access
- Configures subnet with appropriate CIDR range
- Sets up private services access for Cloud IDS connectivity
- Implements packet mirroring for traffic analysis

### Security Components

- **Cloud IDS Endpoint**: Configured for comprehensive threat detection
- **IAM Roles**: Least privilege service accounts for Cloud Functions
- **Firewall Rules**: Secure network access controls
- **Encryption**: All data encrypted in transit and at rest

### Analytics Infrastructure

- **BigQuery Dataset**: Structured storage for threat detection data
- **BigQuery Data Canvas**: AI-powered visual analytics interface
- **Sample Data**: Pre-populated threat scenarios for testing
- **Views**: Aggregated threat summary views for reporting

### Processing Pipeline

- **Cloud Functions**: Serverless threat data processing and alerting
- **Pub/Sub Topics**: Reliable message queuing for event processing
- **Monitoring**: Cloud Logging integration for operational visibility

## Validation & Testing

After deployment, validate the infrastructure:

### Check Cloud IDS Status

```bash
# Verify IDS endpoint is ready
gcloud ids endpoints describe threat-detection-endpoint \
    --zone=${ZONE} \
    --format="table(name,state,severity)"
```

### Test BigQuery Analytics

```bash
# Query threat detection data
bq query --use_legacy_sql=false \
    "SELECT COUNT(*) as total_findings, severity 
     FROM \`${PROJECT_ID}.threat_detection.ids_findings\` 
     GROUP BY severity"
```

### Validate Cloud Functions

```bash
# Check function status
gcloud functions describe process-threat-finding \
    --format="table(name,status,runtime)"

# Test with sample data
gcloud pubsub topics publish threat-detection-findings \
    --message='{"finding_id":"test-001","severity":"HIGH","threat_type":"Test"}'
```

### Access BigQuery Data Canvas

1. Navigate to BigQuery in Google Cloud Console
2. Select your project and the `threat_detection` dataset
3. Click "Data Canvas" to start visual analytics
4. Use natural language queries to explore threat data

## Monitoring & Alerts

The deployment includes:

- Cloud Function execution monitoring
- Pub/Sub message processing metrics
- BigQuery query performance tracking
- Custom alerting policies for high-severity threats

Access monitoring dashboards in Google Cloud Console > Monitoring.

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/

# Delete the deployment
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/threat-detection-pipeline
```

### Using Terraform

```bash
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh
```

**Note**: Cloud IDS endpoint deletion takes 15-20 minutes to complete.

## Troubleshooting

### Common Issues

1. **Cloud IDS Endpoint Creation Fails**
   - Verify private services access is properly configured
   - Check regional availability for Cloud IDS
   - Ensure sufficient IAM permissions

2. **Packet Mirroring Configuration Issues**
   - Verify VMs have appropriate network tags
   - Check IDS endpoint service attachment
   - Validate network connectivity

3. **BigQuery Permission Errors**
   - Verify BigQuery API is enabled
   - Check service account permissions
   - Ensure dataset location matches region

4. **Cloud Function Deployment Failures**
   - Check function memory and timeout settings
   - Verify Pub/Sub topic exists
   - Validate source code dependencies

### Debugging Commands

```bash
# Check API enablement
gcloud services list --enabled --filter="name:ids.googleapis.com OR name:bigquery.googleapis.com"

# Verify network configuration
gcloud compute networks describe threat-detection-vpc

# Check service account permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# View function logs
gcloud functions logs read process-threat-finding --limit 50
```

## Security Considerations

- All communication uses private Google access where possible
- Service accounts follow least privilege principle
- BigQuery datasets include appropriate access controls
- Cloud Functions use secure runtime environments
- VPC networks implement defense in depth

## Cost Optimization

- Cloud IDS charges based on endpoint uptime and traffic volume
- BigQuery costs depend on data storage and query volume
- Cloud Functions pricing is based on execution time and memory
- Consider using BigQuery slots for predictable analytics workloads
- Monitor usage through Cloud Billing console

## Support Resources

- [Cloud IDS Documentation](https://cloud.google.com/intrusion-detection-system/docs)
- [BigQuery Data Canvas Guide](https://cloud.google.com/bigquery/docs/data-canvas)
- [Cloud Functions Best Practices](https://cloud.google.com/functions/docs/bestpractices)
- [VPC Security Best Practices](https://cloud.google.com/vpc/docs/best-practices)

For issues with this infrastructure code, refer to the original recipe documentation or Google Cloud support.