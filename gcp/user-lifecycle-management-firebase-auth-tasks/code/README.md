# Infrastructure as Code for User Lifecycle Management with Firebase Authentication and Cloud Tasks

This directory contains Infrastructure as Code (IaC) implementations for the recipe "User Lifecycle Management with Firebase Authentication and Cloud Tasks".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Firebase CLI installed (`npm install -g firebase-tools`)
- Terraform installed (version >= 1.0) if using Terraform implementation
- Node.js and npm installed for Firebase Functions deployment
- Appropriate Google Cloud permissions for:
  - Firebase project administration
  - Cloud SQL instance creation and management
  - Cloud Tasks queue management
  - Cloud Scheduler job management
  - Cloud Run service deployment
  - IAM role management
  - App Engine application creation
- Estimated cost: $10-20/month for moderate usage (Cloud SQL db-f1-micro, Cloud Tasks, Firebase Auth)

## Quick Start

### Using Infrastructure Manager

```bash
# Navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set your project ID
export PROJECT_ID="your-project-id"

# Create deployment
gcloud infra-manager deployments create user-lifecycle-deployment \
    --location=us-central1 \
    --source-blueprint=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=us-central1"

# Monitor deployment status
gcloud infra-manager deployments describe user-lifecycle-deployment \
    --location=us-central1
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project details

# Plan deployment
terraform plan

# Apply infrastructure
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

# Verify deployment
./scripts/verify.sh
```

## Architecture Overview

This solution deploys a complete user lifecycle management system with the following components:

### Core Infrastructure
- **Firebase Authentication**: User identity and authentication management
- **Cloud SQL PostgreSQL**: User analytics and engagement data storage
- **Cloud Tasks**: Asynchronous background task processing
- **Cloud Scheduler**: Automated workflow triggers
- **Cloud Run**: Serverless worker service for task processing
- **App Engine**: Required for Cloud Tasks queue management

### Analytics Schema
- User engagement tracking with lifecycle stages
- Activity event logging and analysis
- Automated action tracking and reporting
- Performance indexes for query optimization

### Automation Workflows
- Real-time authentication event processing
- Daily engagement analysis
- Weekly retention campaign checks
- Monthly lifecycle reviews

## Configuration Options

### Infrastructure Manager Variables

| Variable | Description | Default |
|----------|-------------|---------|
| project_id | Google Cloud Project ID | Required |
| region | Deployment region | us-central1 |
| db_instance_name | Cloud SQL instance name | user-analytics-${random} |
| db_password | Database password | Auto-generated |
| task_queue_name | Cloud Tasks queue name | user-lifecycle-queue |
| worker_service_name | Cloud Run service name | lifecycle-worker |

### Terraform Variables

| Variable | Description | Type | Default |
|----------|-------------|------|---------|
| project_id | Google Cloud Project ID | string | Required |
| region | Primary deployment region | string | us-central1 |
| zone | Primary deployment zone | string | us-central1-a |
| db_tier | Cloud SQL instance tier | string | db-f1-micro |
| db_storage_size | Database storage in GB | number | 10 |
| worker_cpu | Cloud Run CPU allocation | string | 1 |
| worker_memory | Cloud Run memory allocation | string | 512Mi |
| enable_firebase_auth | Enable Firebase Authentication | bool | true |
| environment | Environment name (dev/staging/prod) | string | dev |

### Environment-Specific Configurations

#### Development Environment
- Minimal resource sizing (db-f1-micro)
- Reduced retention periods
- Debug logging enabled
- Cost-optimized configurations

#### Production Environment
- High-availability Cloud SQL setup
- Enhanced monitoring and alerting
- Backup and disaster recovery
- Performance-optimized configurations

## Post-Deployment Setup

### 1. Initialize Firebase Authentication

```bash
# Authenticate with Firebase
firebase login

# Enable Authentication providers
firebase auth:import users.json --project=${PROJECT_ID}

# Configure authentication triggers
cd firebase-functions/
firebase deploy --only functions --project=${PROJECT_ID}
```

### 2. Configure Database Schema

```bash
# Connect to Cloud SQL instance
gcloud sql connect ${DB_INSTANCE_NAME} --user=postgres

# Run schema setup (automatically handled by deployment scripts)
\i database/schema.sql
```

### 3. Verify System Components

```bash
# Check Cloud Run service status
gcloud run services list --region=${REGION}

# Verify Cloud Tasks queue
gcloud tasks queues list --location=${REGION}

# Test scheduled jobs
gcloud scheduler jobs list --location=${REGION}
```

## Monitoring and Observability

### Cloud Monitoring Dashboards

The deployment includes pre-configured monitoring for:
- User authentication rates and patterns
- Database performance metrics
- Task queue processing rates
- Cloud Run service health
- Scheduled job execution status

### Logging

Structured logging is implemented across all components:
- Authentication events in Cloud Logging
- Database query performance logs
- Task processing success/failure logs
- Worker service application logs

### Alerting Policies

Automated alerts for:
- Database connection failures
- Task queue backlog buildup
- Cloud Run service errors
- Authentication anomalies

## Troubleshooting

### Common Issues

#### Cloud SQL Connection Issues
```bash
# Check instance status
gcloud sql instances describe ${DB_INSTANCE_NAME}

# Verify network connectivity
gcloud sql connect ${DB_INSTANCE_NAME} --user=postgres
```

#### Cloud Tasks Queue Problems
```bash
# Check queue configuration
gcloud tasks queues describe ${TASK_QUEUE_NAME} --location=${REGION}

# View recent tasks
gcloud tasks list --queue=${TASK_QUEUE_NAME} --location=${REGION}
```

#### Firebase Authentication Setup
```bash
# Verify Firebase project setup
firebase projects:list

# Check authentication configuration
gcloud firebase products:list --project=${PROJECT_ID}
```

#### Cloud Run Service Issues
```bash
# Check service logs
gcloud logs read "resource.type=cloud_run_revision" \
    --filter="resource.labels.service_name=${WORKER_SERVICE_NAME}" \
    --limit=50

# Verify service configuration
gcloud run services describe ${WORKER_SERVICE_NAME} --region=${REGION}
```

### Performance Optimization

#### Database Performance
- Monitor slow query logs
- Optimize indexing for common queries
- Consider read replicas for high-traffic scenarios
- Implement connection pooling

#### Task Processing
- Monitor queue depth and processing rates
- Adjust Cloud Run concurrency settings
- Implement batch processing for efficiency
- Use Cloud Tasks retry configurations

## Security Considerations

### IAM and Access Control
- Least privilege service account permissions
- Network security with VPC and firewall rules
- Encrypted connections between services
- Secure secret management with Secret Manager

### Data Protection
- Database encryption at rest and in transit
- User data anonymization for analytics
- GDPR compliance for user data handling
- Audit logging for data access

### Authentication Security
- Multi-factor authentication support
- Session management and timeout policies
- Rate limiting for authentication attempts
- Security monitoring and anomaly detection

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete user-lifecycle-deployment \
    --location=us-central1 \
    --delete-policy=DELETE
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Destroy infrastructure
terraform destroy

# Confirm resource removal
terraform show
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify resource removal
./scripts/verify-cleanup.sh
```

### Manual Cleanup (if needed)

```bash
# Remove Firebase Functions
firebase functions:delete --project=${PROJECT_ID} --force

# Delete remaining Cloud SQL backups
gcloud sql backups list --instance=${DB_INSTANCE_NAME}

# Clean up Cloud Storage buckets
gsutil rm -r gs://${PROJECT_ID}-lifecycle-*
```

## Customization

### Adding Custom Analytics

Extend the user analytics schema by modifying:
- `database/schema.sql` for new tables
- `worker-service/analytics.js` for processing logic
- `terraform/variables.tf` for new configuration options

### Integrating Additional Services

The architecture supports easy integration with:
- BigQuery for advanced analytics
- Pub/Sub for event streaming
- Cloud Functions for additional triggers
- Vertex AI for ML-powered insights

### Custom Retention Campaigns

Modify the worker service to implement:
- Email campaign integration
- Push notification services
- SMS messaging workflows
- Custom engagement scoring algorithms

## Cost Optimization

### Resource Sizing Recommendations

#### Development/Testing
- Cloud SQL: db-f1-micro instance
- Cloud Run: 1 CPU, 512Mi memory
- Minimal scheduled job frequency

#### Production
- Cloud SQL: db-g1-small or higher
- Cloud Run: 2+ CPUs, 1Gi+ memory
- High-availability configurations

### Cost Monitoring

```bash
# Set up billing alerts
gcloud alpha billing budgets create \
    --billing-account=${BILLING_ACCOUNT_ID} \
    --display-name="User Lifecycle Budget" \
    --budget-amount=50USD

# Monitor resource usage
gcloud logging read "resource.type=cloud_sql_database" \
    --format="table(timestamp,severity,textPayload)"
```

## Support

### Documentation References
- [Firebase Authentication Documentation](https://firebase.google.com/docs/auth)
- [Cloud SQL for PostgreSQL](https://cloud.google.com/sql/docs/postgres)
- [Cloud Tasks Documentation](https://cloud.google.com/tasks/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Infrastructure Manager Guide](https://cloud.google.com/infrastructure-manager/docs)

### Community Resources
- [Google Cloud Community](https://cloud.google.com/community)
- [Firebase Community](https://firebase.google.com/community)
- [Stack Overflow - Google Cloud](https://stackoverflow.com/questions/tagged/google-cloud-platform)

### Professional Support
- [Google Cloud Support Plans](https://cloud.google.com/support)
- [Firebase Support](https://firebase.google.com/support)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.