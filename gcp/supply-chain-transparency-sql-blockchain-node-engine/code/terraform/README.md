# Supply Chain Transparency Infrastructure - Terraform

This directory contains Terraform Infrastructure as Code (IaC) for deploying a complete supply chain transparency system on Google Cloud Platform. The infrastructure combines Cloud SQL for operational data storage with Blockchain Node Engine for immutable verification records.

## Architecture Overview

The deployed infrastructure includes:

- **Cloud SQL PostgreSQL**: Stores operational supply chain data with encryption and backups
- **Blockchain Node Engine**: Provides immutable verification using Ethereum blockchain
- **Cloud Functions**: Serverless processing for events and API endpoints
- **Pub/Sub**: Event-driven messaging for real-time supply chain processing
- **Cloud KMS**: Customer-managed encryption keys for enhanced security
- **VPC Network**: Private networking with secure communication between services
- **Cloud Storage**: Function source code and log storage
- **IAM & Security**: Service accounts with least-privilege access controls

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **Google Cloud SDK** installed and configured:
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL
   
   # Authenticate and set project
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

2. **Terraform** installed (version >= 1.0):
   ```bash
   # Install Terraform (macOS)
   brew install terraform
   
   # Install Terraform (Linux)
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **Google Cloud Project** with billing enabled

4. **Required IAM Permissions**:
   - Cloud SQL Admin
   - Compute Network Admin
   - Security Admin
   - Cloud Functions Developer
   - Pub/Sub Admin
   - Cloud KMS Admin
   - Secret Manager Admin
   - Storage Admin
   - Service Account Admin

5. **API Access**: Request access to Blockchain Node Engine through the [Google Cloud Console](https://cloud.google.com/blockchain-node-engine)

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd gcp/supply-chain-transparency-sql-blockchain-node-engine/code/terraform/
```

### 2. Configure Variables
```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit variables file with your configuration
vim terraform.tfvars
```

**Required variables to set:**
- `project_id`: Your Google Cloud project ID
- `region`: Preferred GCP region (e.g., "us-central1")
- `environment`: Environment name (e.g., "dev", "staging", "prod")

### 3. Initialize Terraform
```bash
# Initialize Terraform and download providers
terraform init
```

### 4. Plan Deployment
```bash
# Review what will be created
terraform plan
```

### 5. Deploy Infrastructure
```bash
# Deploy all resources
terraform apply

# Or deploy with auto-approval (use with caution)
terraform apply -auto-approve
```

### 6. Verify Deployment
```bash
# Check deployment status
terraform show

# View outputs
terraform output
```

## Configuration Guide

### Environment-Specific Configurations

#### Development Environment
```hcl
environment              = "dev"
db_instance_tier        = "db-f1-micro"
db_high_availability    = false
blockchain_network      = "GOERLI"
function_max_instances  = 10
log_retention_days      = 7
```

#### Staging Environment
```hcl
environment              = "staging"
db_instance_tier        = "db-custom-1-4096"
db_high_availability    = false
blockchain_network      = "GOERLI"
function_max_instances  = 50
log_retention_days      = 14
```

#### Production Environment
```hcl
environment              = "prod"
db_instance_tier        = "db-custom-4-16384"
db_high_availability    = true
blockchain_network      = "MAINNET"
function_max_instances  = 1000
log_retention_days      = 90
enable_ssl_enforcement  = true
```

### Security Configuration

#### Database Security
- **Encryption**: All data encrypted with customer-managed KMS keys
- **Network Isolation**: Database accessible only through private VPC
- **SSL Enforcement**: Optional SSL enforcement for connections
- **Access Control**: IAM-based authentication and authorization

#### Network Security
- **Private VPC**: Isolated network environment
- **Cloud NAT**: Controlled outbound internet access
- **VPC Connector**: Secure Cloud Functions to VPC connectivity
- **Firewall Rules**: Restrictive access controls

### Monitoring and Logging

#### Cloud Monitoring
- Database performance metrics
- Function execution metrics
- Network and security metrics
- Custom supply chain KPIs

#### Cloud Logging
- Centralized log aggregation
- Structured logging for analysis
- Log retention policies
- Alert-based notifications

## Usage Examples

### Testing the API Endpoint
```bash
# Get the API endpoint URL
API_URL=$(terraform output -raw api_ingestion_function_url)

# Test with sample supply chain event
curl -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 1001,
    "supplier_id": 2001,
    "transaction_type": "MANUFACTURE",
    "quantity": 100,
    "location": "Factory A - Shanghai",
    "batch_number": "BATCH-2024-001",
    "quality_score": 95
  }'
```

### Connecting to the Database
```bash
# Get database connection details
DB_INSTANCE=$(terraform output -raw database_instance_connection_name)
DB_USER=$(terraform output -raw database_user)

# Connect using Cloud SQL Proxy
gcloud sql connect $DB_INSTANCE --user=$DB_USER
```

### Accessing Secret Manager
```bash
# Get database password from Secret Manager
SECRET_NAME=$(terraform output -raw database_password_secret_name)
gcloud secrets versions access latest --secret=$SECRET_NAME
```

## Advanced Configuration

### Custom Domain and SSL
```hcl
# Add custom domain configuration
custom_domain = "api.your-company.com"
ssl_certificate = "projects/PROJECT_ID/global/sslCertificates/your-cert"
```

### Multi-Region Setup
```hcl
# Configure read replicas
db_read_replicas = [
  {
    name     = "read-replica-us-east1"
    region   = "us-east1"
    tier     = "db-custom-2-8192"
  }
]
```

### Enhanced Monitoring
```hcl
# Additional monitoring configuration
alerting_email = "alerts@your-company.com"
uptime_check_enabled = true
custom_metrics_enabled = true
```

## Cost Optimization

### Development Environment
- Use smaller instance types: `db-f1-micro`
- Disable high availability
- Use testnet for blockchain: `GOERLI`
- Reduce function concurrency
- Shorter log retention

### Production Optimizations
- Right-size database instances based on usage
- Enable Cloud SQL automated scaling
- Use committed use discounts
- Implement lifecycle policies for storage
- Monitor and optimize function memory allocation

### Estimated Monthly Costs
- **Development**: $50-100/month
- **Staging**: $150-300/month
- **Production**: $500-1500/month

*Costs vary based on usage patterns, data volume, and selected tiers.*

## Troubleshooting

### Common Issues

#### API Access Issues
```bash
# Check if APIs are enabled
gcloud services list --enabled --filter="name:(sqladmin.googleapis.com OR blockchainnodeengine.googleapis.com)"

# Enable required APIs
terraform apply -target=google_project_service.required_apis
```

#### Database Connection Issues
```bash
# Check Cloud SQL instance status
gcloud sql instances describe INSTANCE_NAME

# Test VPC connectivity
gcloud compute ssh test-vm --zone=ZONE --command="nc -zv DB_PRIVATE_IP 5432"
```

#### Function Deployment Issues
```bash
# Check function logs
gcloud functions logs read FUNCTION_NAME --limit=50

# Verify VPC connector
gcloud compute networks vpc-access connectors list
```

#### Blockchain Node Issues
```bash
# Check node status
gcloud blockchain-node-engine nodes describe NODE_NAME --location=REGION

# Verify node connectivity
curl -X POST NODE_ENDPOINT -H "Content-Type: application/json" -d '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}'
```

### Recovery Procedures

#### Database Recovery
```bash
# List available backups
gcloud sql backups list --instance=INSTANCE_NAME

# Restore from backup
gcloud sql backups restore BACKUP_ID --restore-instance=INSTANCE_NAME
```

#### State Recovery
```bash
# Import existing resources
terraform import google_sql_database_instance.supply_chain_db projects/PROJECT_ID/instances/INSTANCE_NAME

# Refresh state
terraform refresh
```

## Cleanup

### Destroy All Resources
```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy

# Force destroy (use with extreme caution)
terraform destroy -auto-approve
```

### Selective Cleanup
```bash
# Destroy specific resources
terraform destroy -target=google_sql_database_instance.supply_chain_db

# Remove from state without destroying
terraform state rm google_sql_database_instance.supply_chain_db
```

## Security Best Practices

1. **Never commit terraform.tfvars** to version control
2. **Use separate state files** for different environments
3. **Enable state file encryption** in Cloud Storage backend
4. **Regularly rotate KMS keys** and service account keys
5. **Monitor access logs** and set up alerting
6. **Use least-privilege IAM** roles for all service accounts
7. **Enable audit logging** for all critical resources
8. **Implement backup and disaster recovery** procedures

## Contributing

When making changes to this infrastructure:

1. **Test in development** environment first
2. **Use Terraform plan** to review changes
3. **Document breaking changes** in commit messages
4. **Update variable descriptions** and examples
5. **Validate with terraform validate** and linting tools
6. **Update cost estimates** if resource changes affect pricing

## Support

For issues and questions:

- **Infrastructure Issues**: Check Terraform logs and Google Cloud Console
- **Application Issues**: Review Cloud Function logs and database logs
- **Performance Issues**: Monitor Cloud Monitoring dashboards
- **Security Issues**: Review Cloud Security Command Center alerts

## Additional Resources

- [Google Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Blockchain Node Engine Documentation](https://cloud.google.com/blockchain-node-engine/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Terraform Google Provider Documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Supply Chain Transparency Best Practices](https://cloud.google.com/architecture/supply-chain-transparency)