# Infrastructure as Code for Real-Time Inventory Intelligence with Google Distributed Cloud Edge and Cloud Vision

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Inventory Intelligence with Google Distributed Cloud Edge and Cloud Vision".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts for automated resource management

## Prerequisites

### General Requirements
- Google Cloud account with billing enabled
- Google Distributed Cloud Edge hardware deployment at retail location
- gcloud CLI installed and configured (version 400.0.0 or later)
- Appropriate IAM permissions for resource creation

### Tool-Specific Prerequisites

#### Infrastructure Manager
- Infrastructure Manager API enabled
- Deployment Manager API enabled
- Compute Engine API enabled

#### Terraform
- Terraform CLI installed (version 1.0 or later)
- Google Cloud provider plugin
- Service account with required permissions

#### Bash Scripts
- curl and jq utilities installed
- kubectl CLI for Kubernetes management
- gsutil for Cloud Storage operations

### Required Permissions
- Cloud SQL Admin
- Vision API Admin
- Storage Admin
- Kubernetes Engine Admin
- Monitoring Admin
- IAM Security Admin
- Service Account Admin

### Estimated Costs
- **Edge Hardware**: $150-300 per location per month
- **Cloud Services**: $50-100 per location per month
- **Storage and Processing**: $25-50 per location per month

> **Note**: Google Distributed Cloud Edge requires physical hardware deployment and may take 2-4 weeks for initial setup. Contact Google Cloud sales for hardware provisioning and installation coordination.

## Quick Start

### Using Infrastructure Manager
```bash
# Set project and enable APIs
export PROJECT_ID="your-project-id"
gcloud config set project ${PROJECT_ID}

# Enable required APIs
gcloud services enable config.googleapis.com
gcloud services enable cloudbuild.googleapis.com

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/us-central1/deployments/inventory-intelligence \
    --service-account="projects/${PROJECT_ID}/serviceAccounts/deployment-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
    --local-source="." \
    --inputs-file="terraform.tfvars"
```

### Using Terraform
```bash
# Initialize Terraform
cd terraform/
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your specific values

# Plan deployment
terraform plan

# Deploy infrastructure
terraform apply

# Verify deployment
terraform output
```

### Using Bash Scripts
```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Deploy infrastructure
./scripts/deploy.sh

# Verify deployment status
./scripts/validate.sh
```

## Architecture Overview

This solution deploys:

1. **Cloud SQL PostgreSQL Database**: Central inventory data storage with automated backups
2. **Cloud Storage Bucket**: Image storage with lifecycle policies for cost optimization
3. **Cloud Vision API Configuration**: Product recognition and inventory analysis
4. **IAM Service Accounts**: Secure authentication for edge processing workloads
5. **Kubernetes Deployment**: Edge processing application for Google Distributed Cloud Edge
6. **Cloud Monitoring**: Real-time dashboards and alerting for inventory levels
7. **Cloud Functions**: Automated processing triggers and alert handlers

## Configuration

### Environment Variables

```bash
# Core project settings
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Database configuration
export DB_INSTANCE_NAME="inventory-db"
export DB_PASSWORD="your-secure-password"

# Storage configuration
export BUCKET_NAME="inventory-images-bucket"

# Edge cluster settings
export CLUSTER_NAME="inventory-edge-cluster"
export EDGE_LOCATION="your-retail-location"

# Monitoring settings
export ALERT_EMAIL="inventory-alerts@yourcompany.com"
```

### Customization Options

#### Database Configuration
- **Instance Size**: Modify `db_tier` in terraform.tfvars (db-f1-micro to db-n1-highmem-96)
- **Storage**: Adjust `db_storage_size` for data requirements
- **Backup Schedule**: Configure `backup_start_time` for optimal timing

#### Edge Processing
- **Replica Count**: Scale processing pods based on camera feeds
- **Resource Limits**: Adjust CPU and memory based on processing requirements
- **Image Processing Frequency**: Configure capture intervals

#### Monitoring and Alerts
- **Threshold Values**: Customize inventory alert thresholds
- **Notification Channels**: Add Slack, SMS, or webhook integrations
- **Dashboard Metrics**: Modify monitoring dashboards for specific KPIs

## Deployment Process

### 1. Pre-deployment Validation
The deployment scripts validate:
- Google Cloud CLI authentication
- Required API enablement
- IAM permissions
- Resource quotas

### 2. Infrastructure Provisioning
Resources are created in dependency order:
1. Service accounts and IAM bindings
2. Cloud SQL database instance
3. Cloud Storage bucket with policies
4. Cloud Vision API configuration
5. Kubernetes resources for edge deployment
6. Monitoring dashboards and alerts

### 3. Post-deployment Configuration
After infrastructure creation:
- Verify database connectivity
- Test Vision API integration
- Deploy edge processing application
- Configure monitoring thresholds
- Validate end-to-end functionality

## Validation & Testing

### Infrastructure Validation
```bash
# Verify Cloud SQL instance
gcloud sql instances describe ${DB_INSTANCE_NAME}

# Check storage bucket
gsutil ls -b gs://${BUCKET_NAME}

# Validate Vision API setup
gcloud ml vision product-sets list --location=${REGION}

# Test monitoring setup
gcloud monitoring dashboards list
```

### Application Testing
```bash
# Verify edge deployment
kubectl get pods -l app=inventory-processor

# Test image processing pipeline
gsutil cp test-image.jpg gs://${BUCKET_NAME}/test/
gcloud ml vision detect-objects gs://${BUCKET_NAME}/test/test-image.jpg

# Check monitoring metrics
gcloud monitoring metrics list --filter="metric.type:custom.googleapis.com/inventory"
```

### Performance Testing
```bash
# Load test image processing
for i in {1..10}; do
    gsutil cp test-shelf-${i}.jpg gs://${BUCKET_NAME}/load-test/
done

# Monitor processing latency
kubectl logs -l app=inventory-processor -f
```

## Cleanup

### Using Infrastructure Manager
```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/us-central1/deployments/inventory-intelligence
```

### Using Terraform
```bash
cd terraform/
terraform destroy
```

### Using Bash Scripts
```bash
./scripts/destroy.sh
```

### Manual Cleanup (if needed)
```bash
# Remove Kubernetes resources
kubectl delete deployment inventory-processor
kubectl delete service inventory-processor

# Delete Cloud SQL instance
gcloud sql instances delete ${DB_INSTANCE_NAME}

# Remove storage bucket
gsutil -m rm -r gs://${BUCKET_NAME}

# Clean up Vision API resources
gcloud ml vision product-sets delete retail_inventory_set --location=${REGION}

# Remove IAM service accounts
gcloud iam service-accounts delete inventory-edge-processor@${PROJECT_ID}.iam.gserviceaccount.com
```

## Troubleshooting

### Common Issues

#### Edge Deployment Failures
- **Symptom**: Pods failing to start
- **Solution**: Check service account permissions and cluster connectivity
```bash
kubectl describe pod -l app=inventory-processor
kubectl logs -l app=inventory-processor
```

#### Vision API Errors
- **Symptom**: Product detection failures
- **Solution**: Verify API quotas and product set configuration
```bash
gcloud ml vision operations list --location=${REGION}
gcloud quota list --service=vision.googleapis.com
```

#### Database Connection Issues
- **Symptom**: Cloud SQL proxy connection failures
- **Solution**: Check IAM permissions and network configuration
```bash
gcloud sql instances describe ${DB_INSTANCE_NAME}
gcloud sql operations list --instance=${DB_INSTANCE_NAME}
```

#### Monitoring Alert Issues
- **Symptom**: Alerts not triggering
- **Solution**: Verify notification channels and metric collection
```bash
gcloud alpha monitoring policies list
gcloud monitoring metrics list
```

### Debug Commands

```bash
# Enable debug logging
export GOOGLE_CLOUD_DEBUG=true

# Check resource quotas
gcloud compute project-info describe --project=${PROJECT_ID}

# Verify API enablement
gcloud services list --enabled

# Test authentication
gcloud auth list
gcloud config list
```

## Security Considerations

### IAM Best Practices
- Service accounts use least privilege principle
- Regular rotation of service account keys
- Audit logs enabled for all resources

### Network Security
- Private Google Access enabled for edge clusters
- VPC firewall rules restrict access to necessary ports
- TLS encryption for all data in transit

### Data Protection
- Cloud SQL encrypted at rest with customer-managed keys
- Storage bucket configured with uniform bucket-level access
- Vision API data processing follows Google Cloud privacy policies

## Performance Optimization

### Edge Processing
- **CPU Optimization**: Use appropriate instance types for computer vision workloads
- **Memory Management**: Configure pod memory limits based on image processing requirements
- **Network Optimization**: Implement local caching to reduce cloud API calls

### Database Performance
- **Connection Pooling**: Configure Cloud SQL proxy for efficient connection management
- **Indexing**: Create appropriate indexes for inventory query patterns
- **Read Replicas**: Deploy read replicas for high-traffic scenarios

### Cost Optimization
- **Storage Classes**: Use appropriate Cloud Storage classes for different data access patterns
- **Preemptible Instances**: Consider preemptible GKE nodes for non-critical workloads
- **Resource Scheduling**: Implement automatic scaling based on business hours

## Monitoring and Maintenance

### Health Checks
- Kubernetes liveness and readiness probes
- Cloud SQL connection monitoring
- Vision API quota and error rate tracking

### Backup and Recovery
- Automated Cloud SQL backups with point-in-time recovery
- Cross-region replication for critical data
- Disaster recovery procedures documented

### Updates and Patching
- Regular GKE cluster updates
- Container image security scanning
- Dependency vulnerability monitoring

## Support

### Documentation Resources
- [Google Distributed Cloud Edge Documentation](https://cloud.google.com/distributed-cloud/edge/latest/docs)
- [Cloud Vision API Product Search](https://cloud.google.com/vision/docs/retail-product-search)
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)

### Getting Help
- For infrastructure issues: Check Google Cloud Status page
- For application issues: Review application logs and monitoring dashboards
- For Vision API issues: Check API quotas and product set configuration

### Contributing
- Report issues through your organization's support channels
- Submit enhancement requests with business justification
- Follow change management procedures for production deployments

## Version Information

- **Recipe Version**: 1.0
- **Infrastructure Manager**: Latest stable
- **Terraform Google Provider**: ~> 4.0
- **Kubernetes**: 1.24+
- **Last Updated**: 2025-07-12