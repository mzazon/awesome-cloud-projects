#!/bin/bash

# Azure Advanced Network Segmentation with Service Mesh and DNS Private Zones - Deployment Script
# This script deploys the complete infrastructure for advanced network segmentation
# using Azure Kubernetes Service with Istio service mesh and Azure DNS Private Zones

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp] INFO: $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] WARN: $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] ERROR: $message${NC}"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[$timestamp] DEBUG: $message${NC}"
            fi
            ;;
    esac
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check logs above for details."
    exit 1
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    echo -e "${BLUE}Progress: [$current/$total] $message${NC}"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log "WARN" "Deployment failed. Cleaning up partial resources..."
    # Note: This is a basic cleanup. Full cleanup should use destroy.sh
    if [[ -n "${RESOURCE_GROUP:-}" ]] && az group exists --name "${RESOURCE_GROUP}" --output table 2>/dev/null | grep -q "True"; then
        log "INFO" "Cleaning up resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
    fi
}

# Trap to handle script interruption
trap cleanup_on_error ERR INT TERM

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed. Please install it from https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    fi
    
    # Check if openssl is installed (for random generation)
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not installed. Please install it."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    log "INFO" "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Please log in to Azure using 'az login'"
    fi
    
    # Check kubectl version
    local kubectl_version=$(kubectl version --client --short 2>/dev/null || echo "Unknown")
    log "INFO" "kubectl version: $kubectl_version"
    
    log "INFO" "Prerequisites check completed successfully"
}

# Function to validate environment variables
validate_environment() {
    log "INFO" "Validating environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-advanced-network-segmentation}"
    export LOCATION="${LOCATION:-eastus}"
    export AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-service-mesh-cluster}"
    export DNS_ZONE_NAME="${DNS_ZONE_NAME:-company.internal}"
    export APP_GATEWAY_NAME="${APP_GATEWAY_NAME:-agw-service-mesh}"
    export VNET_NAME="${VNET_NAME:-vnet-service-mesh}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-log-advanced-networking}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    export STORAGE_ACCOUNT_NAME="stadvnet${RANDOM_SUFFIX}"
    
    log "INFO" "Environment variables validated:"
    log "INFO" "  Resource Group: ${RESOURCE_GROUP}"
    log "INFO" "  Location: ${LOCATION}"
    log "INFO" "  AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "INFO" "  DNS Zone: ${DNS_ZONE_NAME}"
    log "INFO" "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Function to create resource group
create_resource_group() {
    show_progress 1 11 "Creating resource group..."
    
    if az group exists --name "${RESOURCE_GROUP}" --output table 2>/dev/null | grep -q "True"; then
        log "WARN" "Resource group ${RESOURCE_GROUP} already exists"
    else
        log "INFO" "Creating resource group: ${RESOURCE_GROUP}"
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=advanced-networking environment=production \
            --output table
    fi
    
    log "INFO" "Resource group created successfully"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    show_progress 2 11 "Creating Log Analytics workspace..."
    
    log "INFO" "Creating Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --output table
    
    export LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query id --output tsv)
    
    log "INFO" "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
}

# Function to create virtual network infrastructure
create_virtual_network() {
    show_progress 3 11 "Creating virtual network infrastructure..."
    
    # Create virtual network
    log "INFO" "Creating virtual network: ${VNET_NAME}"
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${VNET_NAME}" \
        --address-prefixes 10.0.0.0/16 \
        --location "${LOCATION}" \
        --output table
    
    # Create subnet for AKS cluster
    log "INFO" "Creating AKS subnet"
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name aks-subnet \
        --address-prefixes 10.0.1.0/24 \
        --output table
    
    # Create subnet for Application Gateway
    log "INFO" "Creating Application Gateway subnet"
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name appgw-subnet \
        --address-prefixes 10.0.2.0/24 \
        --output table
    
    # Create subnet for private endpoints
    log "INFO" "Creating private endpoints subnet"
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name private-endpoints-subnet \
        --address-prefixes 10.0.3.0/24 \
        --output table
    
    log "INFO" "Virtual network infrastructure created successfully"
}

# Function to create AKS cluster with Istio
create_aks_cluster() {
    show_progress 4 11 "Creating AKS cluster with Istio service mesh..."
    
    # Get subnet ID for AKS cluster
    local aks_subnet_id=$(az network vnet subnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name aks-subnet \
        --query id --output tsv)
    
    log "INFO" "Creating AKS cluster: ${AKS_CLUSTER_NAME}"
    az aks create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AKS_CLUSTER_NAME}" \
        --location "${LOCATION}" \
        --node-count 3 \
        --node-vm-size Standard_D4s_v3 \
        --vnet-subnet-id "${aks_subnet_id}" \
        --enable-addons monitoring \
        --workspace-resource-id "${LOG_ANALYTICS_ID}" \
        --enable-managed-identity \
        --enable-cluster-autoscaler \
        --min-count 2 \
        --max-count 10 \
        --kubernetes-version 1.28.0 \
        --output table
    
    log "INFO" "Enabling Istio service mesh addon"
    az aks mesh enable \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AKS_CLUSTER_NAME}" \
        --output table
    
    log "INFO" "AKS cluster created with Istio service mesh"
}

# Function to configure kubectl and verify Istio
configure_kubectl() {
    show_progress 5 11 "Configuring kubectl and verifying Istio..."
    
    log "INFO" "Configuring kubectl for AKS cluster"
    az aks get-credentials \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AKS_CLUSTER_NAME}" \
        --overwrite-existing
    
    log "INFO" "Waiting for Istio system to be ready..."
    kubectl wait --for=condition=ready pods --all -n aks-istio-system --timeout=300s
    
    log "INFO" "Verifying Istio installation"
    kubectl get pods -n aks-istio-system
    
    log "INFO" "kubectl configured and Istio verified successfully"
}

# Function to create DNS private zone
create_dns_private_zone() {
    show_progress 6 11 "Creating Azure DNS private zone..."
    
    log "INFO" "Creating private DNS zone: ${DNS_ZONE_NAME}"
    az network private-dns zone create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${DNS_ZONE_NAME}" \
        --output table
    
    log "INFO" "Linking private DNS zone to virtual network"
    az network private-dns link vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --name vnet-link \
        --virtual-network "${VNET_NAME}" \
        --registration-enabled false \
        --output table
    
    # Create DNS record sets
    log "INFO" "Creating DNS record sets"
    az network private-dns record-set a create \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --name frontend-service \
        --output table
    
    az network private-dns record-set a create \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --name backend-service \
        --output table
    
    az network private-dns record-set a create \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --name database-service \
        --output table
    
    log "INFO" "DNS private zone created successfully"
}

# Function to create application namespaces
create_app_namespaces() {
    show_progress 7 11 "Creating application namespaces with network policies..."
    
    log "INFO" "Creating application namespaces"
    kubectl create namespace frontend --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -
    
    log "INFO" "Enabling Istio sidecar injection"
    kubectl label namespace frontend istio-injection=enabled --overwrite
    kubectl label namespace backend istio-injection=enabled --overwrite
    kubectl label namespace database istio-injection=enabled --overwrite
    
    log "INFO" "Creating network policies for namespace isolation"
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: frontend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: backend
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: database
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
    
    log "INFO" "Application namespaces created with network policies"
}

# Function to deploy microservices
deploy_microservices() {
    show_progress 8 11 "Deploying sample microservices..."
    
    log "INFO" "Deploying frontend service"
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-service
  namespace: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      containers:
      - name: frontend
        image: nginx:1.21
        ports:
        - containerPort: 80
        env:
        - name: BACKEND_URL
          value: "http://backend-service.${DNS_ZONE_NAME}"
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: frontend
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
EOF
    
    log "INFO" "Deploying backend service"
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-service
  namespace: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
        version: v1
    spec:
      containers:
      - name: backend
        image: httpd:2.4
        ports:
        - containerPort: 80
        env:
        - name: DATABASE_URL
          value: "http://database-service.${DNS_ZONE_NAME}"
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: backend
spec:
  selector:
    app: backend
  ports:
  - port: 80
    targetPort: 80
EOF
    
    log "INFO" "Deploying database service"
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-service
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
        version: v1
    spec:
      containers:
      - name: database
        image: postgres:13
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: "appdb"
        - name: POSTGRES_USER
          value: "appuser"
        - name: POSTGRES_PASSWORD
          value: "apppassword"
---
apiVersion: v1
kind: Service
metadata:
  name: database-service
  namespace: database
spec:
  selector:
    app: database
  ports:
  - port: 5432
    targetPort: 5432
EOF
    
    log "INFO" "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pods --all -n frontend --timeout=300s
    kubectl wait --for=condition=ready pods --all -n backend --timeout=300s
    kubectl wait --for=condition=ready pods --all -n database --timeout=300s
    
    log "INFO" "Sample microservices deployed successfully"
}

# Function to configure Istio policies
configure_istio_policies() {
    show_progress 9 11 "Configuring Istio traffic management and security policies..."
    
    log "INFO" "Creating Istio authorization policies"
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: frontend-policy
  namespace: frontend
spec:
  selector:
    matchLabels:
      app: frontend
  rules:
  - from:
    - source:
        namespaces: ["istio-system"]
  - to:
    - operation:
        methods: ["GET", "POST"]
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: backend-policy
  namespace: backend
spec:
  selector:
    matchLabels:
      app: backend
  rules:
  - from:
    - source:
        namespaces: ["frontend"]
  - to:
    - operation:
        methods: ["GET", "POST"]
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: database-policy
  namespace: database
spec:
  selector:
    matchLabels:
      app: database
  rules:
  - from:
    - source:
        namespaces: ["backend"]
  - to:
    - operation:
        methods: ["GET", "POST"]
EOF
    
    log "INFO" "Creating destination rules for traffic management"
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: frontend-destination
  namespace: frontend
spec:
  host: frontend-service
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: backend-destination
  namespace: backend
spec:
  host: backend-service
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: database-destination
  namespace: database
spec:
  host: database-service
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF
    
    log "INFO" "Istio policies configured successfully"
}

# Function to create Application Gateway
create_application_gateway() {
    show_progress 10 11 "Creating Azure Application Gateway..."
    
    log "INFO" "Creating public IP for Application Gateway"
    az network public-ip create \
        --resource-group "${RESOURCE_GROUP}" \
        --name appgw-public-ip \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --output table
    
    log "INFO" "Creating Application Gateway with WAF"
    az network application-gateway create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${APP_GATEWAY_NAME}" \
        --location "${LOCATION}" \
        --vnet-name "${VNET_NAME}" \
        --subnet appgw-subnet \
        --capacity 2 \
        --sku WAF_v2 \
        --public-ip-address appgw-public-ip \
        --priority 1000 \
        --output table
    
    log "INFO" "Waiting for Istio ingress gateway to be ready..."
    kubectl wait --for=condition=ready pods -l app=istio-ingressgateway -n aks-istio-system --timeout=300s
    
    # Get Istio ingress gateway service IP
    local max_attempts=30
    local attempt=1
    local istio_ingress_ip=""
    
    while [[ $attempt -le $max_attempts ]]; do
        istio_ingress_ip=$(kubectl get service istio-ingressgateway \
            -n aks-istio-system \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        
        if [[ -n "$istio_ingress_ip" ]]; then
            log "INFO" "Istio ingress gateway IP: $istio_ingress_ip"
            break
        fi
        
        log "INFO" "Waiting for Istio ingress gateway IP... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ -z "$istio_ingress_ip" ]]; then
        error_exit "Failed to get Istio ingress gateway IP after $max_attempts attempts"
    fi
    
    log "INFO" "Configuring backend pool for Istio ingress gateway"
    az network application-gateway address-pool create \
        --resource-group "${RESOURCE_GROUP}" \
        --gateway-name "${APP_GATEWAY_NAME}" \
        --name istio-backend-pool \
        --servers "$istio_ingress_ip" \
        --output table
    
    log "INFO" "Application Gateway created successfully"
}

# Function to configure DNS and Istio Gateway
configure_dns_and_gateway() {
    show_progress 11 11 "Configuring DNS resolution and Istio Gateway..."
    
    log "INFO" "Getting service cluster IPs"
    local frontend_ip=$(kubectl get service frontend-service -n frontend -o jsonpath='{.spec.clusterIP}')
    local backend_ip=$(kubectl get service backend-service -n backend -o jsonpath='{.spec.clusterIP}')
    local database_ip=$(kubectl get service database-service -n database -o jsonpath='{.spec.clusterIP}')
    
    log "INFO" "Updating DNS records with service IPs"
    az network private-dns record-set a add-record \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --record-set-name frontend-service \
        --ipv4-address "$frontend_ip" \
        --output table
    
    az network private-dns record-set a add-record \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --record-set-name backend-service \
        --ipv4-address "$backend_ip" \
        --output table
    
    az network private-dns record-set a add-record \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${DNS_ZONE_NAME}" \
        --record-set-name database-service \
        --ipv4-address "$database_ip" \
        --output table
    
    log "INFO" "Configuring CoreDNS for private zone resolution"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  company.server: |
    ${DNS_ZONE_NAME}:53 {
      errors
      cache 30
      forward . 168.63.129.16
    }
EOF
    
    kubectl rollout restart deployment coredns -n kube-system
    
    log "INFO" "Creating Istio Gateway for external access"
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: frontend-gateway
  namespace: frontend
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend-virtualservice
  namespace: frontend
spec:
  hosts:
  - "*"
  gateways:
  - frontend-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: frontend-service
        port:
          number: 80
EOF
    
    log "INFO" "DNS and Istio Gateway configured successfully"
}

# Function to enable monitoring
enable_monitoring() {
    log "INFO" "Enabling comprehensive monitoring and observability..."
    
    log "INFO" "Deploying Istio telemetry components"
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml || true
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml || true
    
    log "INFO" "Configuring Azure Monitor integration"
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: container-azm-ms-agentconfig
  namespace: kube-system
data:
  schema-version: v1
  config-version: ver1
  log-data-collection-settings: |
    [log_collection_settings]
      [log_collection_settings.stdout]
        enabled = true
        exclude_namespaces = ["kube-system"]
      [log_collection_settings.stderr]
        enabled = true
        exclude_namespaces = ["kube-system"]
      [log_collection_settings.env_var]
        enabled = true
      [log_collection_settings.enrich_container_logs]
        enabled = true
  prometheus-data-collection-settings: |
    [prometheus_data_collection_settings.cluster]
      interval = "1m"
      monitor_kubernetes_pods = true
      monitor_kubernetes_pods_namespaces = ["istio-system", "frontend", "backend", "database"]
EOF
    
    log "INFO" "Creating Azure Monitor alerts"
    az monitor metrics alert create \
        --name "High Service Mesh Latency" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${LOG_ANALYTICS_ID}" \
        --condition "avg log_analytics_workspace_latency > 1000" \
        --description "Alert when service mesh latency exceeds 1 second" \
        --output table || true
    
    log "INFO" "Monitoring enabled successfully"
}

# Function to perform deployment validation
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    log "INFO" "Checking pod status across all namespaces"
    kubectl get pods --all-namespaces
    
    log "INFO" "Checking Istio configuration"
    kubectl get gateway,virtualservice,destinationrule,authorizationpolicy --all-namespaces
    
    log "INFO" "Checking DNS resolution"
    kubectl run test-dns --image=busybox --rm -i --restart=Never -- nslookup frontend-service.company.internal || true
    
    log "INFO" "Getting Application Gateway public IP"
    local appgw_ip=$(az network public-ip show \
        --resource-group "${RESOURCE_GROUP}" \
        --name appgw-public-ip \
        --query ipAddress --output tsv)
    
    log "INFO" "Application Gateway public IP: $appgw_ip"
    log "INFO" "Test external access: curl -s http://$appgw_ip"
    
    log "INFO" "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "INFO" "Deployment Summary:"
    log "INFO" "=================="
    log "INFO" "Resource Group: ${RESOURCE_GROUP}"
    log "INFO" "AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "INFO" "DNS Zone: ${DNS_ZONE_NAME}"
    log "INFO" "Application Gateway: ${APP_GATEWAY_NAME}"
    
    local appgw_ip=$(az network public-ip show \
        --resource-group "${RESOURCE_GROUP}" \
        --name appgw-public-ip \
        --query ipAddress --output tsv 2>/dev/null || echo "Not available")
    
    log "INFO" "Application Gateway IP: $appgw_ip"
    log "INFO" ""
    log "INFO" "Next Steps:"
    log "INFO" "1. Test external access: curl -s http://$appgw_ip"
    log "INFO" "2. Access Kiali dashboard: kubectl port-forward -n istio-system svc/kiali 20001:20001"
    log "INFO" "3. Access Grafana dashboard: kubectl port-forward -n istio-system svc/grafana 3000:3000"
    log "INFO" "4. Monitor logs: kubectl logs -f deployment/frontend-service -n frontend"
    log "INFO" ""
    log "INFO" "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "INFO" "Starting Azure Advanced Network Segmentation deployment..."
    log "INFO" "================================================================"
    
    # Set script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --resource-group NAME    Resource group name (default: rg-advanced-network-segmentation)"
                echo "  --location LOCATION      Azure region (default: eastus)"
                echo "  --debug                  Enable debug logging"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    validate_environment
    create_resource_group
    create_log_analytics
    create_virtual_network
    create_aks_cluster
    configure_kubectl
    create_dns_private_zone
    create_app_namespaces
    deploy_microservices
    configure_istio_policies
    create_application_gateway
    configure_dns_and_gateway
    enable_monitoring
    validate_deployment
    display_summary
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Total deployment time: $SECONDS seconds"
}

# Run main function
main "$@"