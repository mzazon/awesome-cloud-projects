# Infrastructure as Code for Development Lifecycle Automation with Cloud Composer and Datastream

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Development Lifecycle Automation with Cloud Composer and Datastream".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code service (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured (version 450.0.0 or later)
- Appropriate Google Cloud Project with billing enabled
- Required IAM permissions:
  - Cloud Composer Admin
  - Datastream Admin  
  - Artifact Registry Admin
  - Cloud Workflows Admin
  - Cloud SQL Admin
  - Storage Admin
  - Binary Authorization Admin
  - Project Editor (or equivalent granular permissions)
- Basic knowledge of Apache Airflow, Python, and CI/CD concepts
- Understanding of database change data capture (CDC) concepts

## Architecture Overview

This solution creates an intelligent development lifecycle automation system that:

- **Orchestrates CI/CD pipelines** using Cloud Composer 3 with Apache Airflow 3
- **Captures database changes** in real-time using Datastream
- **Performs security scanning** through Artifact Registry vulnerability scanning
- **Enforces compliance policies** via Cloud Workflows and Binary Authorization
- **Provides observability** through monitoring DAGs and Cloud Operations

Key components include:
- Cloud Composer 3 environment with Apache Airflow 3
- Datastream for real-time change data capture
- Cloud SQL PostgreSQL development database
- Artifact Registry with vulnerability scanning
- Cloud Workflows for compliance validation
- Binary Authorization for security policy enforcement
- Cloud Storage for workflow assets and data

## Quick Start

### Using Infrastructure Manager

```bash
# Clone or navigate to the infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create intelligent-devops-deployment \
    --location=${REGION} \
    --deployment-config=main.yaml \
    --input-values=project_id=${PROJECT_ID},region=${REGION}

# Monitor deployment progress
gcloud infra-manager deployments describe intelligent-devops-deployment \
    --location=${REGION}

# Wait for deployment completion (15-20 minutes)
gcloud infra-manager deployments wait intelligent-devops-deployment \
    --location=${REGION} \
    --timeout=1800
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review planned changes
terraform plan \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Apply infrastructure
terraform apply \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Terraform will prompt for confirmation - type 'yes' to proceed
# Deployment typically takes 15-20 minutes
```

### Using Bash Scripts

```bash
# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Run deployment script
./scripts/deploy.sh

# Follow interactive prompts for configuration
# Script will create all required resources and configurations
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | Google Cloud Project ID | - | Yes |
| `region` | Google Cloud region for resources | `us-central1` | No |
| `zone` | Google Cloud zone for Compute resources | `us-central1-a` | No |
| `composer_env_name` | Cloud Composer environment name | `intelligent-devops` | No |
| `datastream_name` | Datastream configuration name | `schema-changes-stream` | No |
| `enable_monitoring` | Enable advanced monitoring and alerting | `true` | No |
| `security_scanning` | Enable container vulnerability scanning | `true` | No |
| `compliance_enforcement` | Enable Binary Authorization policies | `true` | No |

### Environment-Specific Configurations

#### Development Environment
```bash
# Minimal configuration for development/testing
terraform apply \
    -var="project_id=dev-project-123" \
    -var="composer_node_count=3" \
    -var="composer_disk_size=30" \
    -var="db_tier=db-f1-micro"
```

#### Production Environment
```bash
# Enhanced configuration for production workloads
terraform apply \
    -var="project_id=prod-project-456" \
    -var="composer_node_count=5" \
    -var="composer_disk_size=100" \
    -var="db_tier=db-n1-standard-2" \
    -var="enable_high_availability=true"
```

## Post-Deployment Setup

### 1. Access Cloud Composer Airflow UI

```bash
# Get Airflow web UI URL
AIRFLOW_URI=$(gcloud composer environments describe intelligent-devops \
    --location=${REGION} \
    --format="value(config.airflowUri)")

echo "Access Airflow UI at: ${AIRFLOW_URI}"
```

### 2. Upload Sample DAGs

```bash
# Get Composer bucket for DAG uploads
COMPOSER_BUCKET=$(gcloud composer environments describe intelligent-devops \
    --location=${REGION} \
    --format="value(config.dagGcsPrefix)" | sed 's|/dags||')

# Upload provided sample DAGs
gsutil cp terraform/dags/*.py ${COMPOSER_BUCKET}/dags/
```

### 3. Configure Database Schema

```bash
# Connect to development database
gcloud sql connect dev-database-instance --user=postgres

# Create sample schema for testing
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

# Exit database connection
\q
```

### 4. Test Change Detection

```bash
# Make a schema change to trigger automation
gcloud sql connect dev-database-instance --user=postgres

# Add a new column (this will trigger Datastream)
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;

# Exit and monitor Datastream processing
\q

# Check Datastream capture
gsutil ls gs://your-bucket-name/datastream/
```

## Monitoring and Observability

### Access Monitoring Dashboards

```bash
# View Cloud Composer environment status
gcloud composer environments describe intelligent-devops \
    --location=${REGION} \
    --format="table(name,state,config.softwareConfig.imageVersion)"

# Monitor Datastream processing
gcloud datastream streams describe schema-changes-stream \
    --location=${REGION} \
    --format="value(state)"

# Check workflow executions
gcloud workflows executions list \
    --workflow=intelligent-deployment-workflow \
    --location=${REGION}
```

### Key Metrics to Monitor

- **DAG Success Rate**: Monitor Airflow DAG execution success/failure rates
- **Security Scan Results**: Track vulnerability findings in Artifact Registry
- **Deployment Frequency**: Monitor automated deployment triggers
- **Compliance Violations**: Track policy enforcement outcomes
- **Change Detection Latency**: Monitor Datastream processing delays

## Troubleshooting

### Common Issues

#### Cloud Composer Environment Creation Fails
```bash
# Check quota limits
gcloud compute project-info describe \
    --format="table(quotas.metric,quotas.limit,quotas.usage)"

# Verify required APIs are enabled
gcloud services list --enabled --filter="name:composer"
```

#### Datastream Connection Issues
```bash
# Verify database connectivity
gcloud sql instances describe your-db-instance \
    --format="value(ipAddresses[0].ipAddress)"

# Check firewall rules
gcloud compute firewall-rules list \
    --filter="direction:INGRESS AND allowed.ports:5432"
```

#### DAG Import Errors
```bash
# Check DAG syntax
python -m py_compile path/to/your_dag.py

# Verify Composer environment variables
gcloud composer environments describe intelligent-devops \
    --location=${REGION} \
    --format="value(config.softwareConfig.envVariables)"
```

### Debug Commands

```bash
# Enable detailed logging for Terraform
export TF_LOG=DEBUG
terraform apply

# Check Cloud Composer logs
gcloud logging read "resource.type=gce_instance AND \
    resource.labels.instance_id:composer" \
    --limit=50 \
    --format="table(timestamp,severity,textPayload)"

# Monitor Datastream errors
gcloud logging read "resource.type=datastream_stream" \
    --limit=20 \
    --format="table(timestamp,severity,jsonPayload.message)"
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete Infrastructure Manager deployment
gcloud infra-manager deployments delete intelligent-devops-deployment \
    --location=${REGION} \
    --quiet

# Verify deletion
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy all resources
terraform destroy \
    -var="project_id=your-project-id" \
    -var="region=us-central1"

# Confirm destruction when prompted
# Type 'yes' to proceed with resource deletion
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Follow prompts for confirmation
# Script will remove all created resources in proper order
```

### Manual Cleanup (if automated cleanup fails)

```bash
# Delete Cloud Composer environment
gcloud composer environments delete intelligent-devops \
    --location=${REGION} \
    --quiet

# Delete Datastream resources
gcloud datastream streams delete schema-changes-stream \
    --location=${REGION} \
    --quiet

# Delete Cloud SQL instance
gcloud sql instances delete dev-database-instance \
    --quiet

# Delete Artifact Registry repository
gcloud artifacts repositories delete secure-containers \
    --location=${REGION} \
    --quiet

# Delete Cloud Storage bucket
gsutil -m rm -r gs://your-bucket-name

# Delete Cloud Workflows
gcloud workflows delete intelligent-deployment-workflow \
    --location=${REGION} \
    --quiet
```

## Cost Optimization

### Expected Costs

| Component | Estimated Monthly Cost (USD) |
|-----------|----------------------------|
| Cloud Composer 3 (3 nodes) | $150-200 |
| Cloud SQL (db-f1-micro) | $7-15 |
| Datastream processing | $10-50 |
| Cloud Storage | $5-15 |
| Artifact Registry | $5-10 |
| **Total** | **$177-290** |

### Cost Reduction Tips

```bash
# Use smaller Composer environment for development
terraform apply -var="composer_node_count=1" -var="composer_disk_size=20"

# Schedule Composer environment shutdown for non-production
# (Note: This requires custom automation)

# Use Cloud SQL scheduled backups instead of continuous replication
gcloud sql instances patch your-instance \
    --backup-start-time=03:00 \
    --backup-location=${REGION}

# Implement lifecycle policies for Cloud Storage
gsutil lifecycle set lifecycle-config.json gs://your-bucket-name
```

## Security Considerations

### Implemented Security Measures

- **IAM Least Privilege**: Service accounts with minimal required permissions
- **Network Security**: Private IP addresses for database and Composer nodes
- **Encryption**: Data encrypted at rest and in transit
- **Vulnerability Scanning**: Automatic container image scanning
- **Policy Enforcement**: Binary Authorization policies prevent insecure deployments
- **Audit Logging**: Comprehensive audit trails for all operations

### Additional Security Recommendations

```bash
# Enable additional audit logging
gcloud logging sinks create composer-audit-sink \
    bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/audit_logs \
    --log-filter="protoPayload.serviceName=composer.googleapis.com"

# Configure VPC firewall rules for additional protection
gcloud compute firewall-rules create composer-restricted-access \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:443 \
    --source-ranges=10.0.0.0/8 \
    --target-tags=composer-worker

# Enable Cloud Security Command Center notifications
gcloud alpha scc notifications create composer-security-alerts \
    --organization=${ORG_ID} \
    --pubsub-topic=projects/${PROJECT_ID}/topics/security-alerts
```

## Advanced Configuration

### Custom DAG Development

```python
# Example custom DAG for additional automation
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

def custom_automation_task(**context):
    """Add your custom automation logic here"""
    print("Executing custom automation task")
    return "success"

dag = DAG(
    'custom_intelligent_automation',
    default_args={
        'owner': 'platform-team',
        'start_date': datetime(2024, 1, 1),
        'retries': 1
    },
    schedule_interval=timedelta(hours=6),
    catchup=False
)

custom_task = PythonOperator(
    task_id='custom_automation',
    python_callable=custom_automation_task,
    dag=dag
)
```

### Integration with External Systems

```bash
# Configure webhook notifications
gcloud composer environments update intelligent-devops \
    --location=${REGION} \
    --update-env-variables=WEBHOOK_URL=https://your-system.example.com/webhook

# Set up external database connections
gcloud composer environments update intelligent-devops \
    --location=${REGION} \
    --update-env-variables=EXTERNAL_DB_HOST=external-db.example.com,EXTERNAL_DB_PORT=5432
```

## Support and Documentation

### Additional Resources

- [Cloud Composer 3 Documentation](https://cloud.google.com/composer/docs/composer-3)
- [Datastream Documentation](https://cloud.google.com/datastream/docs)
- [Artifact Registry Security Scanning](https://cloud.google.com/artifact-analysis/docs/container-scanning-overview)
- [Cloud Workflows Documentation](https://cloud.google.com/workflows/docs)
- [Apache Airflow 3 Documentation](https://airflow.apache.org/docs/)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud documentation for specific services
3. Consult the original recipe documentation
4. Check Google Cloud Status page for service interruptions
5. Contact Google Cloud Support for infrastructure issues

### Contributing

To improve this infrastructure code:

1. Test changes in a development environment first
2. Follow Google Cloud best practices
3. Update documentation for any configuration changes
4. Validate security implications of modifications
5. Ensure backward compatibility when possible