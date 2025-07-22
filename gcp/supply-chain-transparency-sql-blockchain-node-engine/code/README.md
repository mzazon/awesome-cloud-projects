# Infrastructure as Code for Supply Chain Transparency with Cloud SQL and Blockchain Node Engine

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Supply Chain Transparency with Cloud SQL and Blockchain Node Engine".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code platform
- **Terraform**: Multi-cloud infrastructure as code using Google Cloud provider
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) v400.0.0 or later installed and configured
- Active Google Cloud project with billing enabled
- Node.js 18+ and npm installed for Cloud Functions development
- Appropriate IAM permissions for:
  - Cloud SQL instances and databases
  - Blockchain Node Engine (requires allowlisting)
  - Cloud Functions deployment
  - Pub/Sub topics and subscriptions
  - Cloud KMS key management
  - IAM service account management
- Estimated cost: $150-300/month for production workload

> **Note**: Blockchain Node Engine requires allowlisting for access. Request access through the [Google Cloud Console](https://cloud.google.com/blockchain-node-engine) before beginning deployment.

## Quick Start

### Using Infrastructure Manager

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Configure gcloud
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}

# Deploy infrastructure
cd infrastructure-manager/
gcloud infra-manager deployments apply projects/${PROJECT_ID}/locations/${REGION}/deployments/supply-chain-deployment \
    --service-account=projects/${PROJECT_ID}/serviceAccounts/terraform@${PROJECT_ID}.iam.gserviceaccount.com \
    --local-source="."
```

### Using Terraform

```bash
# Set your project and region
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Initialize and deploy
cd terraform/
terraform init
terraform plan -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
terraform apply -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Make scripts executable and deploy
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Architecture Overview

This solution creates a comprehensive supply chain transparency system with the following components:

### Core Infrastructure
- **Cloud SQL PostgreSQL**: Manages operational supply chain data including products, suppliers, and transactions
- **Blockchain Node Engine**: Provides immutable verification records using Ethereum mainnet
- **Cloud KMS**: Secures blockchain operations with enterprise-grade encryption

### Event Processing
- **Pub/Sub Topics**: Handles real-time supply chain events and blockchain verification requests
- **Cloud Functions**: Processes supply chain events and manages database/blockchain interactions
- **API Gateway**: Provides secure endpoints for supply chain partner data ingestion

### Security & Access
- **IAM Service Accounts**: Implements least-privilege access controls
- **VPC Security**: Network isolation and secure communication channels

## Configuration Options

### Infrastructure Manager Variables

The Infrastructure Manager deployment can be customized by modifying the variables in `infrastructure-manager/main.yaml`:

- `project_id`: Your Google Cloud project ID
- `region`: Deployment region (default: us-central1)
- `db_tier`: Cloud SQL instance tier (default: db-custom-2-8192)
- `blockchain_network`: Blockchain network type (default: MAINNET)
- `node_type`: Blockchain node type (default: FULL)

### Terraform Variables

Customize the deployment by setting variables in `terraform/terraform.tfvars`:

```hcl
project_id = "your-project-id"
region = "us-central1"
zone = "us-central1-a"
db_instance_tier = "db-custom-2-8192"
blockchain_node_type = "FULL"
blockchain_network = "MAINNET"
```

### Bash Script Configuration

Set environment variables before running the scripts:

```bash
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"
export DB_TIER="db-custom-2-8192"
```

## Post-Deployment Steps

After successful deployment, complete these additional setup steps:

1. **Database Schema Initialization**:
   ```bash
   # Connect to Cloud SQL and create schema
   gcloud sql connect [INSTANCE_NAME] --user=supply_chain_user --database=supply_chain
   ```

2. **Test API Endpoint**:
   ```bash
   # Get Cloud Function URL
   INGESTION_URL=$(gcloud functions describe supplyChainIngestion --format="value(httpsTrigger.url)")
   
   # Test with sample data
   curl -X POST ${INGESTION_URL} \
       -H "Content-Type: application/json" \
       -d '{"product_id": 1001, "supplier_id": 2001, "transaction_type": "MANUFACTURE", "quantity": 100, "location": "Factory A"}'
   ```

3. **Verify Blockchain Node**:
   ```bash
   # Check node status
   gcloud blockchain-node-engine nodes list --location=${REGION}
   ```

## Monitoring and Observability

The deployed infrastructure includes built-in monitoring capabilities:

- **Cloud SQL Monitoring**: Database performance and connection metrics
- **Cloud Functions Monitoring**: Function execution metrics and error rates
- **Pub/Sub Monitoring**: Message throughput and processing latency
- **Blockchain Node Monitoring**: Node synchronization and health status

Access monitoring dashboards through the Google Cloud Console or set up custom alerting policies.

## Security Considerations

This implementation follows Google Cloud security best practices:

- **Encryption**: All data encrypted at rest and in transit
- **IAM**: Least-privilege access controls with dedicated service accounts
- **Network Security**: VPC isolation and private connectivity
- **Key Management**: Enterprise-grade encryption key management through Cloud KMS
- **Audit Logging**: Comprehensive audit trails for all operations

## Troubleshooting

### Common Issues

1. **Blockchain Node Engine Access**: Ensure your project is allowlisted for Blockchain Node Engine
2. **Cloud SQL Connection**: Verify network connectivity and authentication
3. **Cloud Functions Deployment**: Check IAM permissions and runtime dependencies
4. **API Gateway**: Validate function triggers and HTTP configurations

### Debug Commands

```bash
# Check service status
gcloud services list --enabled

# Verify IAM permissions
gcloud projects get-iam-policy ${PROJECT_ID}

# Check Cloud Function logs
gcloud functions logs read processSupplyChainEvent --limit=50

# Monitor Pub/Sub metrics
gcloud pubsub topics list
gcloud pubsub subscriptions list
```

## Cleanup

### Using Infrastructure Manager

```bash
cd infrastructure-manager/
gcloud infra-manager deployments delete projects/${PROJECT_ID}/locations/${REGION}/deployments/supply-chain-deployment
```

### Using Terraform

```bash
cd terraform/
terraform destroy -var="project_id=${PROJECT_ID}" -var="region=${REGION}"
```

### Using Bash Scripts

```bash
chmod +x scripts/destroy.sh
./scripts/destroy.sh
```

> **Warning**: Cleanup operations will permanently delete all deployed resources and data. Ensure you have backed up any important data before proceeding.

## Cost Optimization

To optimize costs for development or testing environments:

1. **Cloud SQL**: Use smaller instance tiers (db-f1-micro or db-g1-small)
2. **Blockchain Node**: Consider using testnet instead of mainnet
3. **Cloud Functions**: Implement timeout optimizations and memory tuning
4. **Pub/Sub**: Use pull subscriptions for batch processing where possible

## Extension Ideas

Consider these enhancements to extend the solution:

1. **Multi-Region Deployment**: Deploy across multiple regions for global availability
2. **AI Integration**: Add Vertex AI for fraud detection and anomaly analysis
3. **IoT Integration**: Connect IoT Core for real-time sensor data
4. **Consumer Portal**: Build customer-facing verification applications
5. **Smart Contracts**: Implement automated business logic with smart contracts

## Support and Documentation

- [Google Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Blockchain Node Engine Documentation](https://cloud.google.com/blockchain-node-engine/docs)
- [Cloud Functions Documentation](https://cloud.google.com/functions/docs)
- [Pub/Sub Documentation](https://cloud.google.com/pubsub/docs)
- [Infrastructure Manager Documentation](https://cloud.google.com/infrastructure-manager/docs)
- [Terraform Google Cloud Provider](https://registry.terraform.io/providers/hashicorp/google/latest)

For issues with this infrastructure code, refer to the original recipe documentation or the provider's documentation.