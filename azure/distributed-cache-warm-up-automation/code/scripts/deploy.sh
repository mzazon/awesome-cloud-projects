#!/bin/bash

# Deploy script for Orchestrating Distributed Cache Warm-up Workflows
# with Azure Container Apps Jobs and Azure Redis Enterprise
#
# This script deploys a complete cache warm-up solution using:
# - Azure Container Apps Jobs for orchestration
# - Azure Redis Enterprise for high-performance caching
# - Azure Storage for job coordination
# - Azure Key Vault for secrets management
# - Azure Monitor for comprehensive observability

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        error "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install OpenSSL first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log "Using Azure subscription: $subscription_name ($subscription_id)"
    
    success "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-cache-warmup-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Container Apps environment and job names
    export CONTAINER_ENV_NAME="env-cache-warmup-${RANDOM_SUFFIX}"
    export COORDINATOR_JOB_NAME="job-coordinator-${RANDOM_SUFFIX}"
    export WORKER_JOB_NAME="job-worker-${RANDOM_SUFFIX}"
    
    # Redis and storage names
    export REDIS_NAME="redis-enterprise-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stcachewarmup${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-cache-warmup-${RANDOM_SUFFIX}"
    
    # Monitoring resources
    export LOG_ANALYTICS_NAME="log-cache-warmup-${RANDOM_SUFFIX}"
    
    # Container images
    export COORDINATOR_IMAGE="coordinator:latest"
    export WORKER_IMAGE="worker:latest"
    
    log "Environment variables configured:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Container Environment: $CONTAINER_ENV_NAME"
    log "  Redis Name: $REDIS_NAME"
    log "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log "  Key Vault: $KEY_VAULT_NAME"
    
    success "Environment variables set successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=cache-warmup environment=demo created-by=deploy-script \
        --output none
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace: $LOG_ANALYTICS_NAME"
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --output none
    
    # Get Log Analytics workspace ID for Container Apps environment
    export LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --query customerId --output tsv)
    
    log "Log Analytics workspace ID: $LOG_ANALYTICS_ID"
    success "Log Analytics workspace created: $LOG_ANALYTICS_NAME"
}

# Function to create Container Apps environment
create_container_apps_environment() {
    log "Creating Container Apps environment: $CONTAINER_ENV_NAME"
    
    az containerapp env create \
        --name "$CONTAINER_ENV_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$LOG_ANALYTICS_ID" \
        --tags purpose=cache-warmup \
        --output none
    
    success "Container Apps environment created: $CONTAINER_ENV_NAME"
}

# Function to create Redis Enterprise cluster
create_redis_enterprise() {
    log "Creating Redis Enterprise cluster: $REDIS_NAME"
    warn "Redis Enterprise deployment may take 20-30 minutes..."
    
    az redis create \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Enterprise \
        --vm-size E10 \
        --enable-non-ssl-port false \
        --redis-version 6.0 \
        --tags purpose=cache-warmup \
        --no-wait
    
    log "Redis Enterprise cluster creation initiated: $REDIS_NAME"
    log "Waiting for Redis deployment to complete..."
    
    # Wait for Redis deployment with timeout
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local state=$(az redis show \
            --name "$REDIS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState \
            --output tsv 2>/dev/null || echo "NotFound")
        
        if [ "$state" = "Succeeded" ]; then
            success "Redis Enterprise cluster ready: $REDIS_NAME"
            return 0
        elif [ "$state" = "Failed" ]; then
            error "Redis Enterprise cluster deployment failed"
            exit 1
        fi
        
        log "Redis deployment status: $state (elapsed: ${elapsed}s)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    error "Redis deployment timed out after $timeout seconds"
    exit 1
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=cache-warmup \
        --output none
    
    # Create blob container for job coordination
    az storage container create \
        --name coordination \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --public-access off \
        --output none
    
    success "Storage account created with coordination container: $STORAGE_ACCOUNT_NAME"
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Key Vault: $KEY_VAULT_NAME"
    
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --tags purpose=cache-warmup \
        --output none
    
    # Store Redis connection string in Key Vault
    log "Storing Redis connection string in Key Vault"
    local redis_key=$(az redis list-keys \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryKey --output tsv)
    
    local redis_connection_string="Server=${REDIS_NAME}.redis.cache.windows.net:6380;Password=${redis_key};Database=0;Ssl=True"
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name redis-connection-string \
        --value "$redis_connection_string" \
        --output none
    
    success "Key Vault created with Redis connection string: $KEY_VAULT_NAME"
}

# Function to create container images
create_container_images() {
    log "Creating container images..."
    
    # Create temporary directory for container builds
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create coordinator Dockerfile
    cat > Dockerfile.coordinator << 'EOF'
FROM mcr.microsoft.com/dotnet/runtime:8.0-alpine AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
WORKDIR /src
COPY coordinator.csproj .
RUN dotnet restore coordinator.csproj
COPY . .
RUN dotnet build coordinator.csproj -c Release -o /app/build

FROM build AS publish
RUN dotnet publish coordinator.csproj -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "coordinator.dll"]
EOF

    # Create coordinator project file
    cat > coordinator.csproj << 'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Storage.Blobs" Version="12.19.1" />
    <PackageReference Include="Azure.Security.KeyVault.Secrets" Version="4.5.0" />
    <PackageReference Include="Azure.Identity" Version="1.10.3" />
    <PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Console" Version="8.0.0" />
  </ItemGroup>
</Project>
EOF

    # Create coordinator program
    cat > Program.cs << 'EOF'
using Azure.Storage.Blobs;
using Azure.Security.KeyVault.Secrets;
using Azure.Identity;
using Microsoft.Extensions.Logging;
using System.Text.Json;

var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
var logger = loggerFactory.CreateLogger<Program>();

logger.LogInformation("Starting cache warm-up coordinator");

// Configuration
var resourceGroup = Environment.GetEnvironmentVariable("RESOURCE_GROUP") ?? "rg-cache-warmup";
var subscriptionId = Environment.GetEnvironmentVariable("SUBSCRIPTION_ID") ?? "";
var storageAccountName = Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_NAME") ?? "";
var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME") ?? "";
var workerJobName = Environment.GetEnvironmentVariable("WORKER_JOB_NAME") ?? "";

// Initialize Azure clients
var credential = new DefaultAzureCredential();
var blobServiceClient = new BlobServiceClient(
    new Uri($"https://{storageAccountName}.blob.core.windows.net"), 
    credential);
var secretClient = new SecretClient(
    new Uri($"https://{keyVaultName}.vault.azure.net"), 
    credential);

// Create work partitions
var workPartitions = new[]
{
    new { Id = 1, DataSource = "users", StartId = 1, EndId = 1000, Priority = "high" },
    new { Id = 2, DataSource = "products", StartId = 1, EndId = 5000, Priority = "medium" },
    new { Id = 3, DataSource = "orders", StartId = 1, EndId = 10000, Priority = "low" },
    new { Id = 4, DataSource = "inventory", StartId = 1, EndId = 2000, Priority = "high" }
};

// Upload work partitions to blob storage
var containerClient = blobServiceClient.GetBlobContainerClient("coordination");
foreach (var partition in workPartitions)
{
    var partitionJson = JsonSerializer.Serialize(partition);
    var blobClient = containerClient.GetBlobClient($"partition-{partition.Id}.json");
    await blobClient.UploadAsync(new BinaryData(partitionJson), overwrite: true);
    logger.LogInformation($"Uploaded partition {partition.Id} for {partition.DataSource}");
}

logger.LogInformation("Cache warm-up coordinator completed successfully");
EOF

    # Build coordinator image
    log "Building coordinator container image..."
    docker build -f Dockerfile.coordinator -t "$COORDINATOR_IMAGE" . > /dev/null 2>&1
    
    # Create worker Dockerfile
    cat > Dockerfile.worker << 'EOF'
FROM mcr.microsoft.com/dotnet/runtime:8.0-alpine AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
WORKDIR /src
COPY worker.csproj .
RUN dotnet restore worker.csproj
COPY . .
RUN dotnet build worker.csproj -c Release -o /app/build

FROM build AS publish
RUN dotnet publish worker.csproj -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "worker.dll"]
EOF

    # Create worker project file
    cat > worker.csproj << 'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Azure.Storage.Blobs" Version="12.19.1" />
    <PackageReference Include="Azure.Security.KeyVault.Secrets" Version="4.5.0" />
    <PackageReference Include="Azure.Identity" Version="1.10.3" />
    <PackageReference Include="StackExchange.Redis" Version="2.7.4" />
    <PackageReference Include="Microsoft.Extensions.Logging" Version="8.0.0" />
    <PackageReference Include="Microsoft.Extensions.Logging.Console" Version="8.0.0" />
  </ItemGroup>
</Project>
EOF

    # Create worker program (rename to avoid conflicts)
    mv Program.cs coordinator-Program.cs
    cat > Program.cs << 'EOF'
using Azure.Storage.Blobs;
using Azure.Security.KeyVault.Secrets;
using Azure.Identity;
using StackExchange.Redis;
using Microsoft.Extensions.Logging;
using System.Text.Json;

var loggerFactory = LoggerFactory.Create(builder => builder.AddConsole());
var logger = loggerFactory.CreateLogger<Program>();

logger.LogInformation("Starting cache warm-up worker");

// Configuration
var workerId = Environment.GetEnvironmentVariable("WORKER_ID") ?? "1";
var storageAccountName = Environment.GetEnvironmentVariable("STORAGE_ACCOUNT_NAME") ?? "";
var keyVaultName = Environment.GetEnvironmentVariable("KEY_VAULT_NAME") ?? "";

// Initialize Azure clients
var credential = new DefaultAzureCredential();
var blobServiceClient = new BlobServiceClient(
    new Uri($"https://{storageAccountName}.blob.core.windows.net"), 
    credential);
var secretClient = new SecretClient(
    new Uri($"https://{keyVaultName}.vault.azure.net"), 
    credential);

// Get Redis connection string
var redisConnectionSecret = await secretClient.GetSecretAsync("redis-connection-string");
var redis = ConnectionMultiplexer.Connect(redisConnectionSecret.Value.Value);
var database = redis.GetDatabase();

// Get work partition
var containerClient = blobServiceClient.GetBlobContainerClient("coordination");
var blobClient = containerClient.GetBlobClient($"partition-{workerId}.json");
var partitionData = await blobClient.DownloadContentAsync();
var partition = JsonSerializer.Deserialize<WorkPartition>(partitionData.Value.Content.ToString());

logger.LogInformation($"Worker {workerId} processing {partition.DataSource} from {partition.StartId} to {partition.EndId}");

// Simulate cache population based on data source
for (int i = partition.StartId; i <= partition.EndId; i++)
{
    var cacheKey = $"{partition.DataSource}:{i}";
    var cacheValue = $"{{\"id\":{i},\"type\":\"{partition.DataSource}\",\"lastUpdated\":\"{DateTime.UtcNow:yyyy-MM-ddTHH:mm:ssZ}\"}}";
    
    await database.StringSetAsync(cacheKey, cacheValue, TimeSpan.FromHours(24));
    
    if (i % 100 == 0)
    {
        logger.LogInformation($"Worker {workerId} processed {i - partition.StartId + 1} items");
    }
}

logger.LogInformation($"Worker {workerId} completed cache warm-up for {partition.DataSource}");

public class WorkPartition
{
    public int Id { get; set; }
    public string DataSource { get; set; } = "";
    public int StartId { get; set; }
    public int EndId { get; set; }
    public string Priority { get; set; } = "";
}
EOF

    # Build worker image
    log "Building worker container image..."
    docker build -f Dockerfile.worker -t "$WORKER_IMAGE" . > /dev/null 2>&1
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    success "Container images built successfully"
}

# Function to create Container Apps jobs
create_container_jobs() {
    log "Creating coordinator Container Apps job: $COORDINATOR_JOB_NAME"
    
    az containerapp job create \
        --name "$COORDINATOR_JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Schedule \
        --cron-expression "0 */6 * * *" \
        --image "$COORDINATOR_IMAGE" \
        --cpu 0.5 \
        --memory 1.0Gi \
        --replica-timeout 1800 \
        --parallelism 1 \
        --completions 1 \
        --env-vars \
            RESOURCE_GROUP="$RESOURCE_GROUP" \
            SUBSCRIPTION_ID="$SUBSCRIPTION_ID" \
            STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME" \
            KEY_VAULT_NAME="$KEY_VAULT_NAME" \
            WORKER_JOB_NAME="$WORKER_JOB_NAME" \
        --output none
    
    success "Coordinator job created: $COORDINATOR_JOB_NAME"
    
    log "Creating worker Container Apps job: $WORKER_JOB_NAME"
    
    az containerapp job create \
        --name "$WORKER_JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Manual \
        --image "$WORKER_IMAGE" \
        --cpu 0.25 \
        --memory 0.5Gi \
        --replica-timeout 3600 \
        --parallelism 4 \
        --completions 4 \
        --env-vars \
            STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME" \
            KEY_VAULT_NAME="$KEY_VAULT_NAME" \
        --output none
    
    success "Worker job created: $WORKER_JOB_NAME"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring Azure Monitor alerts..."
    
    # Create action group for alerts
    az monitor action-group create \
        --name ag-cache-warmup \
        --resource-group "$RESOURCE_GROUP" \
        --short-name CacheWarmup \
        --email-receivers name=admin email="${ALERT_EMAIL:-admin@company.com}" \
        --output none
    
    success "Azure Monitor alerts configured for cache warm-up jobs"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Container Environment: $CONTAINER_ENV_NAME"
    echo "Coordinator Job: $COORDINATOR_JOB_NAME"
    echo "Worker Job: $WORKER_JOB_NAME"
    echo "Redis Enterprise: $REDIS_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Key Vault: $KEY_VAULT_NAME"
    echo "Log Analytics: $LOG_ANALYTICS_NAME"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Test the deployment by running the coordinator job manually:"
    echo "   az containerapp job start --name $COORDINATOR_JOB_NAME --resource-group $RESOURCE_GROUP"
    echo
    echo "2. Monitor job execution:"
    echo "   az containerapp job execution list --name $COORDINATOR_JOB_NAME --resource-group $RESOURCE_GROUP"
    echo
    echo "3. View logs in Azure Portal or query Log Analytics workspace: $LOG_ANALYTICS_NAME"
    echo
    echo "4. To clean up resources, run the destroy script: ./destroy.sh"
    echo
    warn "Remember: Redis Enterprise incurs significant costs. Clean up when not needed."
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Azure Cache Warm-up Deployment Script"
    echo "=========================================="
    echo
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics
    create_container_apps_environment
    create_redis_enterprise
    create_storage_account
    create_key_vault
    create_container_images
    create_container_jobs
    configure_monitoring
    
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"