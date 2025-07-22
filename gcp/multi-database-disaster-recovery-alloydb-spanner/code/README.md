# Infrastructure as Code for Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Multi-Database Disaster Recovery with AlloyDB and Cloud Spanner".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code solution (YAML)
- **Terraform**: Multi-cloud infrastructure as code using the official Google Cloud provider
- **Bash Scripts**: Automated deployment and cleanup scripts

## Prerequisites

### General Requirements
- Google Cloud Project with billing enabled
- Appropriate quotas for multi-region database deployments
- Network connectivity requirements for cross-region replication

### Required Permissions
- AlloyDB Admin (`roles/alloydb.admin`)
- Spanner Admin (`roles/spanner.admin`)
- Storage Admin (`roles/storage.admin`)
- Cloud Scheduler Admin (`roles/cloudscheduler.admin`)
- Cloud Functions Developer (`roles/cloudfunctions.developer`)
- Service Account Admin (`roles/iam.serviceAccountAdmin`)
- Project IAM Admin (`roles/resourcemanager.projectIamAdmin`)

### Tool-Specific Prerequisites

#### Infrastructure Manager
```bash
# Install Google Cloud CLI
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Enable Infrastructure Manager API
gcloud services enable config.googleapis.com
```

#### Terraform
```bash
# Install Terraform (version 1.5+)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify installation
terraform version
```

#### Bash Scripts
```bash
# Install Google Cloud CLI if not already installed
# Ensure proper authentication
gcloud auth application-default login
```

## Quick Start

### Using Infrastructure Manager

Infrastructure Manager is Google Cloud's recommended IaC solution that provides native integration with Google Cloud services.

```bash
# Navigate to Infrastructure Manager directory
cd infrastructure-manager/

# Create deployment using Infrastructure Manager
gcloud infra-manager deployments apply projects/YOUR_PROJECT_ID/locations/us-central1/deployments/dr-database-deployment \
    --service-account=YOUR_SERVICE_ACCOUNT@YOUR_PROJECT.iam.gserviceaccount.com \
    --local-source="." \
    --inputs-file="inputs.yaml"

# Monitor deployment status
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/dr-database-deployment

# View deployment outputs
gcloud infra-manager deployments describe projects/YOUR_PROJECT_ID/locations/us-central1/deployments/dr-database-deployment \
    --format="value(latestRevision.outputs)"
```

### Using Terraform

Terraform provides a declarative approach to infrastructure management with excellent state management and planning capabilities.

```bash
# Navigate to Terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review the planned changes
terraform plan -var="project_id=YOUR_PROJECT_ID"

# Apply the infrastructure
terraform apply -var="project_id=YOUR_PROJECT_ID"

# View outputs
terraform output
```

### Using Bash Scripts

Bash scripts provide a simple, imperative approach for quick deployments and learning purposes.

```bash
# Navigate to scripts directory
cd scripts/

# Make scripts executable
chmod +x deploy.sh destroy.sh

# Set required environment variables
export PROJECT_ID="your-gcp-project-id"
export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"

# Deploy infrastructure
./deploy.sh

# View deployment status
gcloud alloydb clusters list --format="table(name,state,location)"
gcloud spanner instances list --format="table(name,config,state)"
```

## Architecture Overview

This infrastructure deploys a comprehensive disaster recovery solution featuring:

### Core Components
- **AlloyDB Primary Cluster**: High-performance PostgreSQL cluster in primary region
- **AlloyDB Secondary Cluster**: Cross-region read replicas for disaster recovery
- **Cloud Spanner Multi-Region Instance**: Globally distributed database for critical data
- **Cross-Region Storage Buckets**: Backup storage with automated replication
- **Cloud Functions**: Serverless backup orchestration and coordination
- **Cloud Scheduler**: Automated backup scheduling and validation

### Network Architecture
- **Multi-Region VPC**: Secure network spanning primary and secondary regions
- **Private Service Connect**: Secure database connectivity
- **Cross-Region Connectivity**: Automated backup and replication workflows

### Monitoring & Automation
- **Cloud Monitoring Dashboards**: Real-time visibility into database health
- **Alerting Policies**: Proactive notification of potential issues
- **Automated Backup Orchestration**: Coordinated backup across database systems
- **Disaster Recovery Automation**: Streamlined failover procedures

## Configuration Options

### Resource Sizing

The infrastructure can be customized for different workload requirements:

#### Development/Testing
```yaml
# Smaller resource allocation for cost optimization
alloydb_cpu_count: 2
alloydb_memory_gb: 8
spanner_node_count: 1
backup_retention_days: 7
```

#### Production
```yaml
# Production-ready configuration with high availability
alloydb_cpu_count: 4
alloydb_memory_gb: 16
spanner_node_count: 3
backup_retention_days: 30
enable_high_availability: true
```

#### Enterprise
```yaml
# Enterprise-scale with maximum performance and durability
alloydb_cpu_count: 8
alloydb_memory_gb: 32
spanner_node_count: 5
backup_retention_days: 90
enable_cross_region_backup: true
multi_region_storage: true
```

### Regional Configuration

Customize regions based on your geographic requirements:

```yaml
# North America focus
primary_region: "us-central1"
secondary_region: "us-east1"
spanner_config: "nam-eur-asia1"

# Europe focus
primary_region: "europe-west1"
secondary_region: "europe-west4"
spanner_config: "eur3"

# Asia Pacific focus
primary_region: "asia-southeast1"
secondary_region: "asia-northeast1"
spanner_config: "asia1"
```

## Cost Management

### Estimated Monthly Costs

| Component | Development | Production | Enterprise |
|-----------|-------------|------------|------------|
| AlloyDB Primary | $200-400 | $800-1,200 | $1,500-2,500 |
| AlloyDB Secondary | $100-200 | $400-600 | $750-1,250 |
| Cloud Spanner | $150-300 | $600-900 | $1,200-2,000 |
| Cloud Storage | $20-50 | $100-200 | $300-500 |
| Cloud Functions | $5-15 | $25-50 | $75-150 |
| **Total** | **$475-965** | **$1,925-2,950** | **$3,825-6,400** |

### Cost Optimization Strategies

1. **Scheduled Scaling**: Use Cloud Scheduler to scale down non-production resources during off-hours
2. **Storage Lifecycle Policies**: Automatically transition older backups to cheaper storage classes
3. **Regional Optimization**: Choose regions based on latency requirements and pricing
4. **Reserved Capacity**: Consider committed use discounts for predictable workloads

## Security Considerations

### Encryption
- **Data at Rest**: All databases use Google-managed encryption keys by default
- **Data in Transit**: TLS 1.2+ encryption for all network communications
- **Backup Encryption**: Cross-region backup replication maintains encryption

### Access Control
- **Identity and Access Management**: Fine-grained IAM policies for database access
- **Private Service Connect**: Secure network connectivity without public IPs
- **Service Account Security**: Minimal privilege service accounts for automation

### Compliance
- **Audit Logging**: Comprehensive logging for compliance and forensic analysis
- **Data Governance**: Configurable data retention and deletion policies
- **Network Security**: VPC-native security with private Google Access

## Monitoring and Alerting

### Key Metrics
- **Database Health**: Connection counts, query performance, replication lag
- **Backup Success**: Backup completion rates and validation results
- **Storage Utilization**: Storage consumption and growth trends
- **Network Performance**: Cross-region latency and bandwidth utilization

### Alert Policies
- **Database Availability**: Immediate alerts for database connectivity issues
- **Backup Failures**: Notifications for failed backup operations
- **Resource Exhaustion**: Proactive alerts for storage and compute limits
- **Security Events**: Monitoring for unusual access patterns

## Disaster Recovery Procedures

### Automated Failover
The infrastructure includes automated failover capabilities:

```bash
# Trigger automated failover (emergency use only)
gcloud scheduler jobs run disaster-recovery-failover-job \
    --location=${PRIMARY_REGION}

# Monitor failover status
gcloud functions logs read disaster-recovery-orchestrator \
    --region=${PRIMARY_REGION} \
    --limit=50
```

### Manual Recovery Steps
For planned maintenance or controlled failover scenarios:

1. **Verify Backup Status**: Ensure recent backups are available
2. **Promote Secondary**: Promote read replicas to primary instances
3. **Update Application Configuration**: Redirect traffic to recovery region
4. **Validate Data Integrity**: Confirm data consistency across systems
5. **Monitor Performance**: Ensure acceptable performance in recovery mode

## Troubleshooting

### Common Issues

#### AlloyDB Connection Issues
```bash
# Verify cluster status
gcloud alloydb clusters describe CLUSTER_ID --region=REGION

# Check network connectivity
gcloud compute networks describe alloydb-dr-network

# Review connection logs
gcloud logging read 'resource.type="alloydb_cluster"' --limit=50
```

#### Cloud Spanner Performance
```bash
# Monitor instance metrics
gcloud spanner instances describe INSTANCE_ID

# Check query performance
gcloud spanner databases execute-sql DATABASE_ID \
    --instance=INSTANCE_ID \
    --sql="SELECT * FROM INFORMATION_SCHEMA.LOCK_STATS"
```

#### Backup Failures
```bash
# Check function execution logs
gcloud functions logs read disaster-recovery-orchestrator \
    --region=REGION --limit=20

# Verify storage bucket access
gsutil ls -L gs://BACKUP_BUCKET_NAME/

# Test backup creation manually
gcloud alloydb backups create BACKUP_ID \
    --cluster=CLUSTER_ID --region=REGION
```

## Validation and Testing

### Infrastructure Validation
```bash
# Verify all resources are created
gcloud alloydb clusters list
gcloud spanner instances list
gcloud storage buckets list
gcloud scheduler jobs list --location=REGION

# Test database connectivity
gcloud alloydb instances describe INSTANCE_ID \
    --cluster=CLUSTER_ID --region=REGION \
    --format="value(ipAddress)"

# Validate backup functionality
gcloud functions call disaster-recovery-orchestrator \
    --region=REGION --data='{"action":"test"}'
```

### Disaster Recovery Testing
```bash
# Execute backup validation
gcloud scheduler jobs run disaster-recovery-validation-job \
    --location=REGION

# Test cross-region connectivity
gcloud compute instances create test-vm \
    --zone=SECONDARY_ZONE \
    --subnet=alloydb-secondary-subnet

# Validate monitoring alerts
gcloud alpha monitoring policies list \
    --filter="displayName:AlloyDB Cluster Availability Alert"
```

## Cleanup

### Using Infrastructure Manager
```bash
# Delete deployment
gcloud infra-manager deployments delete projects/YOUR_PROJECT_ID/locations/us-central1/deployments/dr-database-deployment

# Verify resource cleanup
gcloud infra-manager deployments list
```

### Using Terraform
```bash
cd terraform/
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

### Using Bash Scripts
```bash
cd scripts/
./destroy.sh
```

### Manual Cleanup Verification
```bash
# Verify all resources are removed
gcloud alloydb clusters list
gcloud spanner instances list
gcloud storage buckets list --filter="name:backup-*"
gcloud functions list --regions=us-central1,us-east1
gcloud scheduler jobs list --location=us-central1

# Clean up any remaining resources
gcloud projects delete YOUR_PROJECT_ID  # Only if using a dedicated project
```

## Customization

### Extending the Solution

1. **Additional Regions**: Modify configuration files to include more regions
2. **Custom Backup Policies**: Enhance Cloud Functions for specific backup requirements
3. **Application Integration**: Add application-specific health checks and failover logic
4. **Compliance Features**: Implement additional auditing and data governance controls

### Environment-Specific Configurations

Create separate variable files for different environments:

```bash
# terraform/environments/dev.tfvars
project_id = "dev-project-id"
alloydb_cpu_count = 2
spanner_node_count = 1
backup_retention_days = 7

# terraform/environments/prod.tfvars
project_id = "prod-project-id"
alloydb_cpu_count = 4
spanner_node_count = 3
backup_retention_days = 30
```

Deploy with environment-specific settings:
```bash
terraform apply -var-file="environments/prod.tfvars"
```

## Support and Resources

### Documentation References
- [AlloyDB Documentation](https://cloud.google.com/alloydb/docs)
- [Cloud Spanner Documentation](https://cloud.google.com/spanner/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)

### Best Practices
- [Google Cloud Architecture Framework](https://cloud.google.com/architecture/framework)
- [Database Disaster Recovery Guide](https://cloud.google.com/architecture/disaster-recovery)
- [Multi-Region Architecture Patterns](https://cloud.google.com/architecture/multi-region-patterns)

### Community Support
- [Google Cloud Community](https://cloud.google.com/community)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation. For production deployments, consider engaging with Google Cloud Professional Services for architecture review and optimization recommendations.