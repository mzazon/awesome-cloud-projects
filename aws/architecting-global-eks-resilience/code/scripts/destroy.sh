#!/bin/bash

# Multi-Cluster EKS Deployments with Cross-Region Networking - Cleanup Script
# This script removes all resources created by the deployment script in the correct order

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    echo "Cleanup failed. Some resources may still exist."
    exit 1
}

# Load environment variables
load_environment() {
    if [[ -f /tmp/eks-multi-cluster-env.sh ]]; then
        log "Loading environment variables from /tmp/eks-multi-cluster-env.sh..."
        source /tmp/eks-multi-cluster-env.sh
        log_success "Environment variables loaded"
    else
        log_warning "Environment file not found. Attempting to discover resources..."
        discover_resources
    fi
}

# Discover existing resources if environment file is missing
discover_resources() {
    log "Attempting to discover existing multi-cluster resources..."
    
    # Set default regions if not provided
    export PRIMARY_REGION=${PRIMARY_REGION:-us-east-1}
    export SECONDARY_REGION=${SECONDARY_REGION:-us-west-2}
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find EKS clusters with our naming pattern
    PRIMARY_CLUSTERS=$(aws eks list-clusters --region ${PRIMARY_REGION} --query 'clusters[?contains(@, `eks-primary-`)]' --output text)
    SECONDARY_CLUSTERS=$(aws eks list-clusters --region ${SECONDARY_REGION} --query 'clusters[?contains(@, `eks-secondary-`)]' --output text)
    
    if [[ -n "$PRIMARY_CLUSTERS" ]]; then
        export PRIMARY_CLUSTER_NAME=$(echo $PRIMARY_CLUSTERS | head -n1)
        export RANDOM_SUFFIX=$(echo $PRIMARY_CLUSTER_NAME | sed 's/eks-primary-//')
        log "Found primary cluster: $PRIMARY_CLUSTER_NAME"
    else
        log_warning "No primary EKS clusters found with expected naming pattern"
    fi
    
    if [[ -n "$SECONDARY_CLUSTERS" ]]; then
        export SECONDARY_CLUSTER_NAME=$(echo $SECONDARY_CLUSTERS | head -n1)
        log "Found secondary cluster: $SECONDARY_CLUSTER_NAME"
    else
        log_warning "No secondary EKS clusters found with expected naming pattern"
    fi
    
    # Set other resource names based on suffix
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        export VPC_PRIMARY_NAME="vpc-primary-${RANDOM_SUFFIX}"
        export VPC_SECONDARY_NAME="vpc-secondary-${RANDOM_SUFFIX}"
        export TGW_PRIMARY_NAME="tgw-primary-${RANDOM_SUFFIX}"
        export TGW_SECONDARY_NAME="tgw-secondary-${RANDOM_SUFFIX}"
        export SERVICE_NETWORK_NAME="multi-cluster-service-network-${RANDOM_SUFFIX}"
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    log_warning "This will DELETE all multi-cluster EKS resources including:"
    echo "  - EKS clusters and node groups"
    echo "  - VPCs and all networking components"
    echo "  - Transit Gateways and peering connections"
    echo "  - VPC Lattice service networks"
    echo "  - NAT Gateways and Elastic IPs"
    echo "  - IAM roles and policies"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log "Force delete enabled, proceeding without confirmation..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Destruction cancelled."
        exit 0
    fi
}

# Delete Kubernetes applications and VPC Lattice resources
delete_applications_and_vpc_lattice() {
    log "Deleting applications and VPC Lattice resources..."
    
    # Delete applications from primary cluster if it exists
    if [[ -n "${PRIMARY_CLUSTER_NAME:-}" ]] && kubectl --context=primary-cluster get nodes &>/dev/null; then
        log "Deleting applications from primary cluster..."
        kubectl --context=primary-cluster delete deployment nginx-primary --ignore-not-found=true
        kubectl --context=primary-cluster delete service nginx-primary-service --ignore-not-found=true
        kubectl --context=primary-cluster delete httproute nginx-primary-route --ignore-not-found=true
        kubectl --context=primary-cluster delete gateway nginx-primary-gateway --ignore-not-found=true
        
        # Delete VPC Lattice controllers
        kubectl --context=primary-cluster delete -f \
            https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/deploy/deploy-v1.0.0.yaml \
            --ignore-not-found=true
    fi
    
    # Delete applications from secondary cluster if it exists
    if [[ -n "${SECONDARY_CLUSTER_NAME:-}" ]] && kubectl --context=secondary-cluster get nodes &>/dev/null; then
        log "Deleting applications from secondary cluster..."
        kubectl --context=secondary-cluster delete deployment nginx-secondary --ignore-not-found=true
        kubectl --context=secondary-cluster delete service nginx-secondary-service --ignore-not-found=true
        kubectl --context=secondary-cluster delete httproute nginx-secondary-route --ignore-not-found=true
        kubectl --context=secondary-cluster delete gateway nginx-secondary-gateway --ignore-not-found=true
        
        # Delete VPC Lattice controllers
        kubectl --context=secondary-cluster delete -f \
            https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/deploy/deploy-v1.0.0.yaml \
            --ignore-not-found=true
    fi
    
    # Delete VPC Lattice Service Network
    if [[ -n "${SERVICE_NETWORK_ID:-}" ]]; then
        log "Deleting VPC Lattice Service Network associations..."
        
        # Get VPC IDs if not already set
        if [[ -n "${VPC_PRIMARY_NAME:-}" ]]; then
            PRIMARY_VPC_ID=$(aws ec2 describe-vpcs \
                --filters "Name=tag:Name,Values=${VPC_PRIMARY_NAME}" \
                --region ${PRIMARY_REGION} \
                --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
        fi
        
        if [[ -n "${VPC_SECONDARY_NAME:-}" ]]; then
            SECONDARY_VPC_ID=$(aws ec2 describe-vpcs \
                --filters "Name=tag:Name,Values=${VPC_SECONDARY_NAME}" \
                --region ${SECONDARY_REGION} \
                --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
        fi
        
        # Delete VPC associations
        if [[ -n "${PRIMARY_VPC_ID:-}" && "$PRIMARY_VPC_ID" != "None" ]]; then
            aws vpc-lattice delete-service-network-vpc-association \
                --service-network-identifier ${SERVICE_NETWORK_ID} \
                --vpc-identifier ${PRIMARY_VPC_ID} \
                --region ${PRIMARY_REGION} 2>/dev/null || true
        fi
        
        if [[ -n "${SECONDARY_VPC_ID:-}" && "$SECONDARY_VPC_ID" != "None" ]]; then
            aws vpc-lattice delete-service-network-vpc-association \
                --service-network-identifier ${SERVICE_NETWORK_ID} \
                --vpc-identifier ${SECONDARY_VPC_ID} \
                --region ${PRIMARY_REGION} 2>/dev/null || true
        fi
        
        # Delete service network
        aws vpc-lattice delete-service-network \
            --service-network-identifier ${SERVICE_NETWORK_ID} \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    elif [[ -n "${SERVICE_NETWORK_NAME:-}" ]]; then
        # Try to find service network by name
        SERVICE_NETWORK_ID=$(aws vpc-lattice list-service-networks \
            --query "items[?name=='${SERVICE_NETWORK_NAME}'].id" \
            --output text --region ${PRIMARY_REGION} 2>/dev/null || echo "")
        
        if [[ -n "$SERVICE_NETWORK_ID" && "$SERVICE_NETWORK_ID" != "None" ]]; then
            log "Found service network by name, deleting..."
            aws vpc-lattice delete-service-network \
                --service-network-identifier ${SERVICE_NETWORK_ID} \
                --region ${PRIMARY_REGION} 2>/dev/null || true
        fi
    fi
    
    log_success "Applications and VPC Lattice resources deletion initiated"
}

# Delete EKS node groups
delete_node_groups() {
    log "Deleting EKS node groups..."
    
    # Delete primary cluster node group
    if [[ -n "${PRIMARY_CLUSTER_NAME:-}" ]]; then
        log "Deleting primary cluster node group..."
        aws eks delete-nodegroup \
            --cluster-name ${PRIMARY_CLUSTER_NAME} \
            --nodegroup-name primary-nodes \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    # Delete secondary cluster node group
    if [[ -n "${SECONDARY_CLUSTER_NAME:-}" ]]; then
        log "Deleting secondary cluster node group..."
        aws eks delete-nodegroup \
            --cluster-name ${SECONDARY_CLUSTER_NAME} \
            --nodegroup-name secondary-nodes \
            --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    # Wait for node groups to be deleted
    if [[ -n "${PRIMARY_CLUSTER_NAME:-}" ]]; then
        log "Waiting for primary node group deletion..."
        aws eks wait nodegroup-deleted \
            --cluster-name ${PRIMARY_CLUSTER_NAME} \
            --nodegroup-name primary-nodes \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    if [[ -n "${SECONDARY_CLUSTER_NAME:-}" ]]; then
        log "Waiting for secondary node group deletion..."
        aws eks wait nodegroup-deleted \
            --cluster-name ${SECONDARY_CLUSTER_NAME} \
            --nodegroup-name secondary-nodes \
            --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    log_success "Node groups deleted"
}

# Delete EKS clusters
delete_eks_clusters() {
    log "Deleting EKS clusters..."
    
    # Delete primary cluster
    if [[ -n "${PRIMARY_CLUSTER_NAME:-}" ]]; then
        log "Deleting primary EKS cluster..."
        aws eks delete-cluster \
            --name ${PRIMARY_CLUSTER_NAME} \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    # Delete secondary cluster
    if [[ -n "${SECONDARY_CLUSTER_NAME:-}" ]]; then
        log "Deleting secondary EKS cluster..."
        aws eks delete-cluster \
            --name ${SECONDARY_CLUSTER_NAME} \
            --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    # Wait for clusters to be deleted
    if [[ -n "${PRIMARY_CLUSTER_NAME:-}" ]]; then
        log "Waiting for primary cluster deletion (this may take 10-15 minutes)..."
        aws eks wait cluster-deleted \
            --name ${PRIMARY_CLUSTER_NAME} \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    if [[ -n "${SECONDARY_CLUSTER_NAME:-}" ]]; then
        log "Waiting for secondary cluster deletion (this may take 10-15 minutes)..."
        aws eks wait cluster-deleted \
            --name ${SECONDARY_CLUSTER_NAME} \
            --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    log_success "EKS clusters deleted"
}

# Delete Transit Gateway peering and attachments
delete_transit_gateway_peering() {
    log "Deleting Transit Gateway peering and attachments..."
    
    # Get Transit Gateway IDs if not already set
    if [[ -n "${TGW_PRIMARY_NAME:-}" ]]; then
        PRIMARY_TGW_ID=$(aws ec2 describe-transit-gateways \
            --filters "Name=tag:Name,Values=${TGW_PRIMARY_NAME}" \
            --region ${PRIMARY_REGION} \
            --query 'TransitGateways[0].TransitGatewayId' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "${TGW_SECONDARY_NAME:-}" ]]; then
        SECONDARY_TGW_ID=$(aws ec2 describe-transit-gateways \
            --filters "Name=tag:Name,Values=${TGW_SECONDARY_NAME}" \
            --region ${SECONDARY_REGION} \
            --query 'TransitGateways[0].TransitGatewayId' --output text 2>/dev/null || echo "")
    fi
    
    # Delete Transit Gateway peering attachment
    if [[ -n "${TGW_PEERING_ID:-}" ]]; then
        aws ec2 delete-transit-gateway-peering-attachment \
            --transit-gateway-peering-attachment-id ${TGW_PEERING_ID} \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    else
        # Try to find peering attachment
        if [[ -n "${PRIMARY_TGW_ID:-}" && "$PRIMARY_TGW_ID" != "None" ]]; then
            TGW_PEERING_ID=$(aws ec2 describe-transit-gateway-peering-attachments \
                --filters "Name=transit-gateway-id,Values=${PRIMARY_TGW_ID}" \
                --region ${PRIMARY_REGION} \
                --query 'TransitGatewayPeeringAttachments[0].TransitGatewayPeeringAttachmentId' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$TGW_PEERING_ID" && "$TGW_PEERING_ID" != "None" ]]; then
                aws ec2 delete-transit-gateway-peering-attachment \
                    --transit-gateway-peering-attachment-id ${TGW_PEERING_ID} \
                    --region ${PRIMARY_REGION} 2>/dev/null || true
            fi
        fi
    fi
    
    # Delete Transit Gateway VPC attachments
    if [[ -n "${PRIMARY_TGW_ATTACHMENT_ID:-}" ]]; then
        aws ec2 delete-transit-gateway-vpc-attachment \
            --transit-gateway-vpc-attachment-id ${PRIMARY_TGW_ATTACHMENT_ID} \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    elif [[ -n "${PRIMARY_TGW_ID:-}" && "$PRIMARY_TGW_ID" != "None" ]]; then
        # Find and delete VPC attachments
        PRIMARY_TGW_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-vpc-attachments \
            --filters "Name=transit-gateway-id,Values=${PRIMARY_TGW_ID}" \
            --region ${PRIMARY_REGION} \
            --query 'TransitGatewayVpcAttachments[0].TransitGatewayVpcAttachmentId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$PRIMARY_TGW_ATTACHMENT_ID" && "$PRIMARY_TGW_ATTACHMENT_ID" != "None" ]]; then
            aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-vpc-attachment-id ${PRIMARY_TGW_ATTACHMENT_ID} \
                --region ${PRIMARY_REGION} 2>/dev/null || true
        fi
    fi
    
    if [[ -n "${SECONDARY_TGW_ATTACHMENT_ID:-}" ]]; then
        aws ec2 delete-transit-gateway-vpc-attachment \
            --transit-gateway-vpc-attachment-id ${SECONDARY_TGW_ATTACHMENT_ID} \
            --region ${SECONDARY_REGION} 2>/dev/null || true
    elif [[ -n "${SECONDARY_TGW_ID:-}" && "$SECONDARY_TGW_ID" != "None" ]]; then
        # Find and delete VPC attachments
        SECONDARY_TGW_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-vpc-attachments \
            --filters "Name=transit-gateway-id,Values=${SECONDARY_TGW_ID}" \
            --region ${SECONDARY_REGION} \
            --query 'TransitGatewayVpcAttachments[0].TransitGatewayVpcAttachmentId' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$SECONDARY_TGW_ATTACHMENT_ID" && "$SECONDARY_TGW_ATTACHMENT_ID" != "None" ]]; then
            aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-vpc-attachment-id ${SECONDARY_TGW_ATTACHMENT_ID} \
                --region ${SECONDARY_REGION} 2>/dev/null || true
        fi
    fi
    
    log_success "Transit Gateway peering and attachments deletion initiated"
}

# Delete Transit Gateways
delete_transit_gateways() {
    log "Deleting Transit Gateways..."
    
    # Wait a bit for attachments to be fully deleted
    sleep 30
    
    # Delete primary Transit Gateway
    if [[ -n "${PRIMARY_TGW_ID:-}" && "$PRIMARY_TGW_ID" != "None" ]]; then
        aws ec2 delete-transit-gateway \
            --transit-gateway-id ${PRIMARY_TGW_ID} \
            --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    # Delete secondary Transit Gateway
    if [[ -n "${SECONDARY_TGW_ID:-}" && "$SECONDARY_TGW_ID" != "None" ]]; then
        aws ec2 delete-transit-gateway \
            --transit-gateway-id ${SECONDARY_TGW_ID} \
            --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    log_success "Transit Gateways deletion initiated"
}

# Delete NAT Gateways and Elastic IPs
delete_nat_gateways() {
    log "Deleting NAT Gateways and Elastic IPs..."
    
    # Delete primary region NAT Gateways
    if [[ -n "${PRIMARY_NAT_1:-}" ]]; then
        aws ec2 delete-nat-gateway --nat-gateway-id ${PRIMARY_NAT_1} --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    if [[ -n "${PRIMARY_NAT_2:-}" ]]; then
        aws ec2 delete-nat-gateway --nat-gateway-id ${PRIMARY_NAT_2} --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    # Delete secondary region NAT Gateways
    if [[ -n "${SECONDARY_NAT_1:-}" ]]; then
        aws ec2 delete-nat-gateway --nat-gateway-id ${SECONDARY_NAT_1} --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    if [[ -n "${SECONDARY_NAT_2:-}" ]]; then
        aws ec2 delete-nat-gateway --nat-gateway-id ${SECONDARY_NAT_2} --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    # Find and delete NAT Gateways by tag if IDs not available
    delete_nat_gateways_by_tag
    
    # Wait for NAT Gateways to be deleted before releasing EIPs
    log "Waiting for NAT Gateways to be deleted..."
    sleep 60
    
    # Release Elastic IPs
    release_elastic_ips
    
    log_success "NAT Gateways and Elastic IPs deletion initiated"
}

# Delete NAT Gateways by tag
delete_nat_gateways_by_tag() {
    # Primary region
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        for nat_name in "primary-nat-1" "primary-nat-2"; do
            NAT_ID=$(aws ec2 describe-nat-gateways \
                --filters "Name=tag:Name,Values=${nat_name}" "Name=state,Values=available" \
                --region ${PRIMARY_REGION} \
                --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "")
            
            if [[ -n "$NAT_ID" && "$NAT_ID" != "None" ]]; then
                aws ec2 delete-nat-gateway --nat-gateway-id ${NAT_ID} --region ${PRIMARY_REGION} 2>/dev/null || true
            fi
        done
        
        # Secondary region
        for nat_name in "secondary-nat-1" "secondary-nat-2"; do
            NAT_ID=$(aws ec2 describe-nat-gateways \
                --filters "Name=tag:Name,Values=${nat_name}" "Name=state,Values=available" \
                --region ${SECONDARY_REGION} \
                --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "")
            
            if [[ -n "$NAT_ID" && "$NAT_ID" != "None" ]]; then
                aws ec2 delete-nat-gateway --nat-gateway-id ${NAT_ID} --region ${SECONDARY_REGION} 2>/dev/null || true
            fi
        done
    fi
}

# Release Elastic IPs
release_elastic_ips() {
    log "Releasing Elastic IPs..."
    
    # Release primary region EIPs
    if [[ -n "${PRIMARY_EIP_1:-}" ]]; then
        aws ec2 release-address --allocation-id ${PRIMARY_EIP_1} --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    if [[ -n "${PRIMARY_EIP_2:-}" ]]; then
        aws ec2 release-address --allocation-id ${PRIMARY_EIP_2} --region ${PRIMARY_REGION} 2>/dev/null || true
    fi
    
    # Release secondary region EIPs
    if [[ -n "${SECONDARY_EIP_1:-}" ]]; then
        aws ec2 release-address --allocation-id ${SECONDARY_EIP_1} --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    if [[ -n "${SECONDARY_EIP_2:-}" ]]; then
        aws ec2 release-address --allocation-id ${SECONDARY_EIP_2} --region ${SECONDARY_REGION} 2>/dev/null || true
    fi
    
    # Find and release EIPs by tag
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        for eip_name in "primary-nat-eip-1" "primary-nat-eip-2"; do
            EIP_ID=$(aws ec2 describe-addresses \
                --filters "Name=tag:Name,Values=${eip_name}" \
                --region ${PRIMARY_REGION} \
                --query 'Addresses[0].AllocationId' --output text 2>/dev/null || echo "")
            
            if [[ -n "$EIP_ID" && "$EIP_ID" != "None" ]]; then
                aws ec2 release-address --allocation-id ${EIP_ID} --region ${PRIMARY_REGION} 2>/dev/null || true
            fi
        done
        
        for eip_name in "secondary-nat-eip-1" "secondary-nat-eip-2"; do
            EIP_ID=$(aws ec2 describe-addresses \
                --filters "Name=tag:Name,Values=${eip_name}" \
                --region ${SECONDARY_REGION} \
                --query 'Addresses[0].AllocationId' --output text 2>/dev/null || echo "")
            
            if [[ -n "$EIP_ID" && "$EIP_ID" != "None" ]]; then
                aws ec2 release-address --allocation-id ${EIP_ID} --region ${SECONDARY_REGION} 2>/dev/null || true
            fi
        done
    fi
    
    log_success "Elastic IPs released"
}

# Delete VPCs and associated resources
delete_vpcs() {
    log "Deleting VPCs and associated resources..."
    
    # Get VPC IDs if not already set
    if [[ -n "${VPC_PRIMARY_NAME:-}" ]]; then
        PRIMARY_VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${VPC_PRIMARY_NAME}" \
            --region ${PRIMARY_REGION} \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "${VPC_SECONDARY_NAME:-}" ]]; then
        SECONDARY_VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${VPC_SECONDARY_NAME}" \
            --region ${SECONDARY_REGION} \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    fi
    
    # Delete primary VPC and its resources
    if [[ -n "${PRIMARY_VPC_ID:-}" && "$PRIMARY_VPC_ID" != "None" ]]; then
        delete_vpc_resources ${PRIMARY_VPC_ID} ${PRIMARY_REGION} "primary"
    fi
    
    # Delete secondary VPC and its resources
    if [[ -n "${SECONDARY_VPC_ID:-}" && "$SECONDARY_VPC_ID" != "None" ]]; then
        delete_vpc_resources ${SECONDARY_VPC_ID} ${SECONDARY_REGION} "secondary"
    fi
    
    log_success "VPCs and associated resources deletion initiated"
}

# Delete resources within a VPC
delete_vpc_resources() {
    local vpc_id=$1
    local region=$2
    local vpc_name=$3
    
    log "Deleting $vpc_name VPC resources..."
    
    # Delete Internet Gateway
    IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=${vpc_name}-igw" \
        --region ${region} \
        --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$IGW_ID" && "$IGW_ID" != "None" ]]; then
        aws ec2 detach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${vpc_id} --region ${region} 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id ${IGW_ID} --region ${region} 2>/dev/null || true
    fi
    
    # Delete custom route tables (not main route table)
    ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${vpc_id}" "Name=association.main,Values=false" \
        --region ${region} \
        --query 'RouteTables[].RouteTableId' --output text 2>/dev/null || echo "")
    
    for rt_id in $ROUTE_TABLES; do
        if [[ -n "$rt_id" && "$rt_id" != "None" ]]; then
            aws ec2 delete-route-table --route-table-id ${rt_id} --region ${region} 2>/dev/null || true
        fi
    done
    
    # Delete subnets
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --region ${region} \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    
    for subnet_id in $SUBNETS; do
        if [[ -n "$subnet_id" && "$subnet_id" != "None" ]]; then
            aws ec2 delete-subnet --subnet-id ${subnet_id} --region ${region} 2>/dev/null || true
        fi
    done
    
    # Delete security groups (except default)
    SECURITY_GROUPS=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${vpc_id}" \
        --region ${region} \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
    
    for sg_id in $SECURITY_GROUPS; do
        if [[ -n "$sg_id" && "$sg_id" != "None" ]]; then
            aws ec2 delete-security-group --group-id ${sg_id} --region ${region} 2>/dev/null || true
        fi
    done
    
    # Finally delete the VPC
    aws ec2 delete-vpc --vpc-id ${vpc_id} --region ${region} 2>/dev/null || true
    
    log_success "$vpc_name VPC resources deleted"
}

# Delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        # Delete EKS cluster role
        aws iam detach-role-policy \
            --role-name "eks-cluster-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>/dev/null || true
        
        aws iam delete-role --role-name "eks-cluster-role-${RANDOM_SUFFIX}" 2>/dev/null || true
        
        # Delete EKS node group role
        aws iam detach-role-policy \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
        
        aws iam delete-role --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" 2>/dev/null || true
    fi
    
    log_success "IAM roles deleted"
}

# Clean up kubectl contexts
cleanup_kubectl_contexts() {
    log "Cleaning up kubectl contexts..."
    
    if [[ -n "${PRIMARY_CLUSTER_NAME:-}" ]]; then
        kubectl config delete-context primary-cluster 2>/dev/null || true
    fi
    
    if [[ -n "${SECONDARY_CLUSTER_NAME:-}" ]]; then
        kubectl config delete-context secondary-cluster 2>/dev/null || true
    fi
    
    log_success "kubectl contexts cleaned up"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/eks-multi-cluster-env.sh
    
    log_success "Temporary files cleaned up"
}

# Main cleanup function
main() {
    log "Starting multi-cluster EKS cleanup..."
    
    load_environment
    confirm_destruction
    
    delete_applications_and_vpc_lattice
    delete_node_groups
    delete_eks_clusters
    delete_transit_gateway_peering
    delete_transit_gateways
    delete_nat_gateways
    delete_vpcs
    delete_iam_roles
    cleanup_kubectl_contexts
    cleanup_temp_files
    
    log_success "Multi-cluster EKS cleanup completed!"
    echo ""
    echo "All resources have been deleted. Please verify in the AWS Console that all resources are removed."
    echo "Note: Some resources may take additional time to fully delete."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --primary-region)
            export PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            export SECONDARY_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force                 Skip confirmation prompt"
            echo "  --primary-region        Primary AWS region (default: us-east-1)"
            echo "  --secondary-region      Secondary AWS region (default: us-west-2)"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"