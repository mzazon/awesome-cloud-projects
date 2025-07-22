# Infrastructure as Code for Real-Time Multiplayer Gaming Infrastructure with Game Servers and Cloud Firestore

This directory contains Infrastructure as Code (IaC) implementations for the recipe "Real-Time Multiplayer Gaming Infrastructure with Game Servers and Cloud Firestore".

## Available Implementations

- **Infrastructure Manager**: Google Cloud's native infrastructure as code (YAML)
- **Terraform**: Multi-cloud infrastructure as code
- **Scripts**: Bash deployment and cleanup scripts

## Prerequisites

- Google Cloud CLI (gcloud) installed and configured
- Docker installed for containerizing applications
- kubectl installed for Kubernetes management
- Helm installed for Agones deployment
- Appropriate Google Cloud permissions:
  - Game Servers API access
  - Kubernetes Engine Admin
  - Cloud Run Admin
  - Firestore Admin
  - Compute Network Admin
  - Service Account Admin
- Estimated cost: $50-100/month for development environment

> **Note**: Game Servers API requires special access approval. Request access through Google Cloud Console before deployment.

## Quick Start

### Using Infrastructure Manager (Recommended)

```bash
# Clone repository and navigate to infrastructure-manager directory
cd infrastructure-manager/

# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Create deployment
gcloud infra-manager deployments create gaming-infrastructure \
    --location=${REGION} \
    --source=main.yaml \
    --input-values="project_id=${PROJECT_ID},region=${REGION}"

# Monitor deployment status
gcloud infra-manager deployments describe gaming-infrastructure \
    --location=${REGION}
```

### Using Terraform

```bash
# Navigate to terraform directory
cd terraform/

# Initialize Terraform
terraform init

# Review and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Plan deployment
terraform plan

# Apply infrastructure
terraform apply

# View outputs
terraform output
```

### Using Bash Scripts

```bash
# Set required environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ZONE="us-central1-a"

# Make scripts executable
chmod +x scripts/deploy.sh scripts/destroy.sh

# Deploy infrastructure
./scripts/deploy.sh

# Check deployment status
./scripts/status.sh
```

## Architecture Components

This infrastructure deploys:

- **Google Kubernetes Engine (GKE)** cluster with Agones for game server management
- **Cloud Firestore** database for real-time state synchronization
- **Cloud Run** service for matchmaking and session management
- **Cloud Load Balancing** for global traffic distribution
- **Game Server Fleet** using Agones for dedicated server instances
- **IAM roles and policies** for secure service communication
- **Monitoring and logging** configuration for operational visibility

## Configuration Options

### Infrastructure Manager Variables

- `project_id`: Google Cloud project ID
- `region`: Primary deployment region (default: us-central1)
- `zone`: Primary deployment zone (default: us-central1-a)
- `cluster_name`: GKE cluster name (default: game-cluster)
- `node_count`: Initial node count (default: 3)
- `machine_type`: GKE node machine type (default: e2-standard-4)
- `firestore_location`: Firestore database location (default: us-central1)

### Terraform Variables

- `project_id`: Google Cloud project ID (required)
- `region`: Primary deployment region (default: us-central1)
- `zone`: Primary deployment zone (default: us-central1-a)
- `cluster_name`: GKE cluster name (default: game-cluster)
- `min_nodes`: Minimum nodes in cluster (default: 1)
- `max_nodes`: Maximum nodes in cluster (default: 10)
- `machine_type`: Node machine type (default: e2-standard-4)
- `game_server_replicas`: Initial game server replicas (default: 2)
- `matchmaking_cpu`: Cloud Run CPU allocation (default: 1000m)
- `matchmaking_memory`: Cloud Run memory allocation (default: 512Mi)

### Script Environment Variables

Required:
- `PROJECT_ID`: Google Cloud project ID
- `REGION`: Primary deployment region
- `ZONE`: Primary deployment zone

Optional:
- `CLUSTER_NAME`: GKE cluster name (default: game-cluster)
- `MACHINE_TYPE`: Node machine type (default: e2-standard-4)
- `NODE_COUNT`: Initial node count (default: 3)

## Post-Deployment Setup

### 1. Verify Game Server Fleet

```bash
# Check fleet status
kubectl get fleet simple-game-server-fleet -o wide

# List game servers
kubectl get gameservers -l "agones.dev/fleet=simple-game-server-fleet"
```

### 2. Test Matchmaking Service

```bash
# Get Cloud Run service URL
MATCHMAKING_URL=$(gcloud run services describe matchmaking-api \
    --platform managed \
    --region ${REGION} \
    --format 'value(status.url)')

# Test matchmaking endpoint
curl -X POST ${MATCHMAKING_URL}/matchmake \
    -H "Content-Type: application/json" \
    -d '{"playerId": "test-player", "gameMode": "battle-royale"}'
```

### 3. Monitor Infrastructure

```bash
# View Cloud Run logs
gcloud logs read --service=matchmaking-api --limit=50

# Monitor GKE cluster
kubectl top nodes
kubectl top pods --all-namespaces

# Check Firestore collections
gcloud firestore query --collection=games --limit=5
```

## Customization

### Game Server Configuration

Modify game server settings in the respective IaC files:

- Container image and resources
- Port configurations
- Health check settings
- Fleet scaling policies

### Firestore Schema

Customize database collections and security rules:

- Game session structure
- Player profile fields
- Real-time listener configurations
- Security rule granularity

### Load Balancer Settings

Adjust global distribution settings:

- Backend service configuration
- Health check parameters
- CDN and caching policies
- SSL certificate management

## Monitoring and Troubleshooting

### Common Issues

1. **Game Servers API Access**: Ensure API access is approved for your project
2. **GKE Cluster Creation**: Verify compute quotas and regional availability
3. **Agones Installation**: Check Helm repository access and version compatibility
4. **Firestore Permissions**: Validate service account permissions for database access

### Health Checks

```bash
# Check all services status
./scripts/health-check.sh

# Validate connectivity
./scripts/connectivity-test.sh

# Performance testing
./scripts/load-test.sh
```

### Logs and Metrics

```bash
# View deployment logs
gcloud logging read "resource.type=gke_cluster" --limit=100

# Monitor game server metrics
kubectl logs -l app=agones-controller -n agones-system

# Check load balancer health
gcloud compute backend-services get-health game-backend --global
```

## Cleanup

### Using Infrastructure Manager

```bash
# Delete deployment
gcloud infra-manager deployments delete gaming-infrastructure \
    --location=${REGION} \
    --quiet

# Verify cleanup
gcloud infra-manager deployments list --location=${REGION}
```

### Using Terraform

```bash
cd terraform/

# Destroy infrastructure
terraform destroy

# Clean up state files
rm -f terraform.tfstate*
rm -rf .terraform/
```

### Using Bash Scripts

```bash
# Run cleanup script
./scripts/destroy.sh

# Verify all resources removed
./scripts/verify-cleanup.sh
```

## Security Considerations

- **IAM Permissions**: All services use least-privilege access principles
- **Network Security**: GKE cluster uses private nodes with authorized networks
- **Firestore Security**: Database rules restrict access to authenticated users
- **Container Security**: Game server images should be scanned for vulnerabilities
- **API Security**: Cloud Run services include authentication and rate limiting

## Cost Optimization

- **Cluster Autoscaling**: GKE automatically scales based on demand
- **Preemptible Nodes**: Consider using preemptible instances for cost savings
- **Game Server Scaling**: Agones manages server lifecycle to minimize idle resources
- **Cloud Run Pricing**: Pay-per-request model scales with actual usage
- **Firestore Optimization**: Monitor read/write operations and optimize queries

## Support and Troubleshooting

### Documentation References

- [Google Kubernetes Engine Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Agones Game Server Documentation](https://agones.dev/site/docs/)
- [Cloud Firestore Documentation](https://cloud.google.com/firestore/docs)
- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Game Servers API Documentation](https://cloud.google.com/game-servers/docs)

### Community Resources

- [Agones Slack Community](https://agones.dev/site/docs/guides/slack/)
- [Google Cloud Gaming Solutions](https://cloud.google.com/solutions/games)
- [GKE Community Forums](https://groups.google.com/g/google-containers)

### Getting Help

For issues with this infrastructure code:

1. Check the troubleshooting section above
2. Review Google Cloud status page for service incidents
3. Consult the original recipe documentation
4. Search community forums for similar issues
5. Contact Google Cloud support for platform-specific problems

## Development and Testing

### Local Development

```bash
# Set up local development environment
./scripts/dev-setup.sh

# Run local tests
./scripts/run-tests.sh

# Validate configurations
./scripts/validate-config.sh
```

### CI/CD Integration

The infrastructure supports integration with popular CI/CD platforms:

- GitHub Actions workflows
- Google Cloud Build pipelines
- GitLab CI/CD
- Jenkins pipelines

Example workflow files are available in the `.github/workflows/` directory.

## Version Information

- **Infrastructure Manager**: Compatible with latest API version
- **Terraform**: Requires version 1.0+
- **Google Cloud Provider**: Version 4.0+
- **Kubernetes Provider**: Version 2.0+
- **Agones**: Version 1.38.0+
- **Recipe Version**: 1.0

## Contributing

When modifying this infrastructure:

1. Test changes in a development environment
2. Update documentation for any new variables or outputs
3. Validate security implications of modifications
4. Ensure backward compatibility where possible
5. Update version information in relevant files

---

**Note**: This infrastructure code is generated from the original recipe. For the complete implementation guide and step-by-step instructions, refer to the recipe documentation.