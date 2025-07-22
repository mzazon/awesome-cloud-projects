#!/bin/bash

# =============================================================================
# AWS ElastiCache Database Query Caching - Deployment Script
# =============================================================================
# This script deploys a complete ElastiCache Redis caching solution with RDS
# database for testing query caching patterns and performance optimization.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for ElastiCache, RDS, EC2, and VPC
# - Default VPC available in the target region
#
# Usage: ./deploy.sh [--region REGION] [--dry-run]
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Global Variables
# =============================================================================

# Script metadata
SCRIPT_NAME="ElastiCache Database Caching Deployment"
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# Default configuration
DEFAULT_REGION="us-east-1"
AWS_REGION="${AWS_REGION:-$DEFAULT_REGION}"
DRY_RUN=false
VERBOSE=false

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') - $1"
}

print_banner() {
    echo "============================================================================="
    echo "  $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "  Deployment started: $DEPLOYMENT_START_TIME"
    echo "  AWS Region: $AWS_REGION"
    echo "============================================================================="
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --region REGION     AWS region to deploy resources (default: $DEFAULT_REGION)
    --dry-run          Show what would be deployed without creating resources
    --verbose          Enable verbose logging
    --help             Show this help message

EXAMPLES:
    $0                          # Deploy with default settings
    $0 --region us-west-2       # Deploy to specific region
    $0 --dry-run                # Preview deployment
    $0 --verbose --region eu-west-1  # Verbose deployment in EU

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first"
        exit 1
    fi
    
    # Check redis-cli availability
    if ! command -v redis-cli &> /dev/null; then
        log_warning "redis-cli not found. Cache testing will be limited"
    fi
    
    # Verify region
    if ! aws ec2 describe-regions --region-names "$AWS_REGION" &> /dev/null; then
        log_error "Invalid AWS region: $AWS_REGION"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Store the original exit code
    local exit_code=$?
    
    # Source the destroy script if it exists
    if [[ -f "$(dirname "$0")/destroy.sh" ]]; then
        log_info "Running cleanup script..."
        bash "$(dirname "$0")/destroy.sh" --force --cleanup-partial
    fi
    
    exit $exit_code
}

# =============================================================================
# AWS Resource Functions
# =============================================================================

generate_unique_suffix() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "dry-run-suffix"
        return
    fi
    
    local suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    echo "$suffix"
}

setup_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique identifiers
    local random_suffix=$(generate_unique_suffix)
    
    # Export all required environment variables
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CACHE_CLUSTER_ID="cache-cluster-${random_suffix}"
    export DB_INSTANCE_ID="database-${random_suffix}"
    export SUBNET_GROUP_NAME="cache-subnet-group-${random_suffix}"
    export PARAMETER_GROUP_NAME="cache-params-${random_suffix}"
    export SECURITY_GROUP_NAME="cache-security-group-${random_suffix}"
    
    # Get VPC information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$VPC_ID" == "None" || -z "$VPC_ID" ]]; then
        log_error "No default VPC found in region $AWS_REGION"
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --region "$AWS_REGION" \
        --query 'Subnets[*].SubnetId' --output text)
    
    # Save environment variables for cleanup script
    cat > /tmp/elasticache-deployment-vars.env << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export CACHE_CLUSTER_ID="$CACHE_CLUSTER_ID"
export DB_INSTANCE_ID="$DB_INSTANCE_ID"
export SUBNET_GROUP_NAME="$SUBNET_GROUP_NAME"
export PARAMETER_GROUP_NAME="$PARAMETER_GROUP_NAME"
export SECURITY_GROUP_NAME="$SECURITY_GROUP_NAME"
export VPC_ID="$VPC_ID"
export SUBNET_IDS="$SUBNET_IDS"
EOF
    
    log_success "Environment variables configured"
    log_info "VPC ID: $VPC_ID"
    log_info "Cache Cluster ID: $CACHE_CLUSTER_ID"
    log_info "Database Instance ID: $DB_INSTANCE_ID"
}

create_security_groups() {
    log_info "Creating security groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create security group: $SECURITY_GROUP_NAME"
        return
    fi
    
    # Create security group for ElastiCache
    local sg_id=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "Security group for ElastiCache Redis cluster" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' --output text)
    
    export CACHE_SG_ID="$sg_id"
    echo "export CACHE_SG_ID=\"$sg_id\"" >> /tmp/elasticache-deployment-vars.env
    
    # Get VPC CIDR for security group rules
    local vpc_cidr=$(aws ec2 describe-vpcs \
        --vpc-ids "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].CidrBlock' --output text)
    
    # Allow Redis access from VPC CIDR
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 6379 \
        --cidr "$vpc_cidr" \
        --region "$AWS_REGION"
    
    # Allow MySQL access from VPC CIDR
    aws ec2 authorize-security-group-ingress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 3306 \
        --cidr "$vpc_cidr" \
        --region "$AWS_REGION"
    
    log_success "Security group created: $sg_id"
}

create_cache_subnet_group() {
    log_info "Creating cache subnet group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create cache subnet group: $SUBNET_GROUP_NAME"
        return
    fi
    
    aws elasticache create-cache-subnet-group \
        --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
        --cache-subnet-group-description "Subnet group for Redis cache" \
        --subnet-ids $SUBNET_IDS \
        --region "$AWS_REGION"
    
    log_success "Cache subnet group created: $SUBNET_GROUP_NAME"
}

create_cache_parameter_group() {
    log_info "Creating cache parameter group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create cache parameter group: $PARAMETER_GROUP_NAME"
        return
    fi
    
    # Create parameter group for Redis optimization
    aws elasticache create-cache-parameter-group \
        --cache-parameter-group-family "redis7.x" \
        --cache-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --description "Custom parameters for database caching" \
        --region "$AWS_REGION"
    
    # Configure maxmemory policy for LRU eviction
    aws elasticache modify-cache-parameter-group \
        --cache-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --parameter-name-values \
        "ParameterName=maxmemory-policy,ParameterValue=allkeys-lru" \
        --region "$AWS_REGION"
    
    log_success "Cache parameter group created: $PARAMETER_GROUP_NAME"
}

create_elasticache_cluster() {
    log_info "Creating ElastiCache Redis replication group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create Redis replication group: $CACHE_CLUSTER_ID"
        return
    fi
    
    # Create Redis replication group with automatic failover
    aws elasticache create-replication-group \
        --replication-group-id "$CACHE_CLUSTER_ID" \
        --replication-group-description "Redis cluster for database caching" \
        --engine redis \
        --cache-node-type cache.t3.micro \
        --num-cache-clusters 2 \
        --automatic-failover-enabled \
        --multi-az-enabled \
        --cache-parameter-group-name "$PARAMETER_GROUP_NAME" \
        --cache-subnet-group-name "$SUBNET_GROUP_NAME" \
        --security-group-ids "$CACHE_SG_ID" \
        --port 6379 \
        --region "$AWS_REGION"
    
    log_success "Redis replication group creation initiated"
}

wait_for_cache_cluster() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would wait for cache cluster to become available"
        return
    fi
    
    log_info "Waiting for Redis cluster to become available (this may take 5-10 minutes)..."
    
    # Wait for cluster to be available with timeout
    local timeout=900  # 15 minutes
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for Redis cluster to become available"
            exit 1
        fi
        
        local status=$(aws elasticache describe-replication-groups \
            --replication-group-id "$CACHE_CLUSTER_ID" \
            --region "$AWS_REGION" \
            --query 'ReplicationGroups[0].Status' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$status" == "available" ]]; then
            break
        elif [[ "$status" == "failed" || "$status" == "deleting" ]]; then
            log_error "Redis cluster creation failed with status: $status"
            exit 1
        fi
        
        log_info "Redis cluster status: $status (waiting...)"
        sleep 30
    done
    
    # Get cluster endpoint
    export REDIS_ENDPOINT=$(aws elasticache describe-replication-groups \
        --replication-group-id "$CACHE_CLUSTER_ID" \
        --region "$AWS_REGION" \
        --query 'ReplicationGroups[0].RedisEndpoint.Address' \
        --output text)
    
    echo "export REDIS_ENDPOINT=\"$REDIS_ENDPOINT\"" >> /tmp/elasticache-deployment-vars.env
    
    log_success "Redis cluster available at: $REDIS_ENDPOINT"
}

create_rds_database() {
    log_info "Creating RDS database for testing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create RDS database: $DB_INSTANCE_ID"
        return
    fi
    
    # Create DB subnet group
    aws rds create-db-subnet-group \
        --db-subnet-group-name "db-subnet-group-${CACHE_CLUSTER_ID##*-}" \
        --db-subnet-group-description "Subnet group for test database" \
        --subnet-ids $SUBNET_IDS \
        --region "$AWS_REGION"
    
    # Create MySQL database instance
    aws rds create-db-instance \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --master-username admin \
        --master-user-password TempPassword123 \
        --allocated-storage 20 \
        --db-subnet-group-name "db-subnet-group-${CACHE_CLUSTER_ID##*-}" \
        --vpc-security-group-ids "$CACHE_SG_ID" \
        --backup-retention-period 0 \
        --no-multi-az \
        --publicly-accessible \
        --region "$AWS_REGION"
    
    # Save DB subnet group name for cleanup
    echo "export DB_SUBNET_GROUP_NAME=\"db-subnet-group-${CACHE_CLUSTER_ID##*-}\"" >> /tmp/elasticache-deployment-vars.env
    
    log_success "RDS database creation initiated"
}

wait_for_rds_database() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would wait for RDS database to become available"
        return
    fi
    
    log_info "Waiting for RDS database to become available (this may take 5-10 minutes)..."
    
    # Wait for RDS to be available with timeout
    local timeout=900  # 15 minutes
    local start_time=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for RDS database to become available"
            exit 1
        fi
        
        local status=$(aws rds describe-db-instances \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --region "$AWS_REGION" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "not-found")
        
        if [[ "$status" == "available" ]]; then
            break
        elif [[ "$status" == "failed" || "$status" == "deleting" ]]; then
            log_error "RDS database creation failed with status: $status"
            exit 1
        fi
        
        log_info "RDS database status: $status (waiting...)"
        sleep 30
    done
    
    # Get RDS endpoint
    export DB_ENDPOINT=$(aws rds describe-db-instances \
        --db-instance-identifier "$DB_INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)
    
    echo "export DB_ENDPOINT=\"$DB_ENDPOINT\"" >> /tmp/elasticache-deployment-vars.env
    
    log_success "RDS database available at: $DB_ENDPOINT"
}

test_connectivity() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test connectivity to Redis and RDS"
        return
    fi
    
    log_info "Testing connectivity to deployed resources..."
    
    # Test Redis connectivity if redis-cli is available
    if command -v redis-cli &> /dev/null; then
        log_info "Testing Redis connectivity..."
        if redis-cli -h "$REDIS_ENDPOINT" ping | grep -q "PONG"; then
            log_success "Redis connectivity test passed"
        else
            log_warning "Redis connectivity test failed"
        fi
        
        # Test basic cache operations
        redis-cli -h "$REDIS_ENDPOINT" SET "deployment:test" "success" EX 60
        local test_value=$(redis-cli -h "$REDIS_ENDPOINT" GET "deployment:test")
        
        if [[ "$test_value" == "success" ]]; then
            log_success "Redis cache operations test passed"
        else
            log_warning "Redis cache operations test failed"
        fi
    else
        log_warning "redis-cli not available, skipping Redis connectivity test"
    fi
    
    log_success "Connectivity tests completed"
}

create_demo_script() {
    log_info "Creating cache demonstration script..."
    
    local script_path="$(dirname "$0")/../cache_demo.py"
    
    cat > "$script_path" << 'EOF'
#!/usr/bin/env python3
"""
ElastiCache Redis Cache-Aside Pattern Demonstration

This script demonstrates the cache-aside pattern for database query caching
using Redis and MySQL. It shows performance improvements achieved through
intelligent caching strategies.

Usage:
    python3 cache_demo.py [--redis-host HOST] [--mysql-host HOST]

Requirements:
    pip3 install redis pymysql
"""

import redis
import pymysql
import json
import time
import sys
import os
import argparse

def parse_arguments():
    parser = argparse.ArgumentParser(description='ElastiCache Cache-Aside Demo')
    parser.add_argument('--redis-host', default=os.environ.get('REDIS_ENDPOINT', 'localhost'),
                        help='Redis host endpoint')
    parser.add_argument('--mysql-host', default=os.environ.get('DB_ENDPOINT', 'localhost'),
                        help='MySQL host endpoint')
    parser.add_argument('--mysql-user', default='admin',
                        help='MySQL username')
    parser.add_argument('--mysql-password', default='TempPassword123',
                        help='MySQL password')
    parser.add_argument('--mysql-db', default='testdb',
                        help='MySQL database name')
    return parser.parse_args()

def main():
    args = parse_arguments()
    
    print("ElastiCache Redis Cache-Aside Pattern Demonstration")
    print("=" * 50)
    print(f"Redis Host: {args.redis_host}")
    print(f"MySQL Host: {args.mysql_host}")
    print()
    
    try:
        # Initialize Redis connection
        redis_client = redis.Redis(host=args.redis_host, port=6379, decode_responses=True)
        
        # Test Redis connectivity
        print("Testing Redis connectivity...")
        redis_client.ping()
        print("✅ Redis connection successful")
        
        # Demonstrate cache operations
        print("\nDemonstrating cache operations:")
        
        # Cache write operation
        start_time = time.time()
        redis_client.setex("demo:product:123", 300, json.dumps({
            "id": 123,
            "name": "Sample Product",
            "price": 29.99,
            "description": "This is a sample product for cache demonstration"
        }))
        write_time = time.time() - start_time
        print(f"✅ Cache write completed in {write_time:.4f} seconds")
        
        # Cache read operation
        start_time = time.time()
        cached_data = redis_client.get("demo:product:123")
        read_time = time.time() - start_time
        
        if cached_data:
            product = json.loads(cached_data)
            print(f"✅ Cache read completed in {read_time:.4f} seconds")
            print(f"   Retrieved product: {product['name']} (${product['price']})")
        
        # Cache statistics
        info = redis_client.info('stats')
        print(f"\nCache Statistics:")
        print(f"  Connected clients: {info.get('connected_clients', 'N/A')}")
        print(f"  Total commands processed: {info.get('total_commands_processed', 'N/A')}")
        print(f"  Keyspace hits: {info.get('keyspace_hits', 'N/A')}")
        print(f"  Keyspace misses: {info.get('keyspace_misses', 'N/A')}")
        
        # Cache eviction policy
        config = redis_client.config_get('maxmemory-policy')
        print(f"  Memory eviction policy: {config.get('maxmemory-policy', 'N/A')}")
        
        print("\n✅ Cache demonstration completed successfully!")
        
    except redis.ConnectionError:
        print("❌ Failed to connect to Redis. Please check the endpoint and connectivity.")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error during demonstration: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "$script_path"
    log_success "Cache demonstration script created at: $script_path"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Main deployment flow
    print_banner
    check_prerequisites
    setup_environment_variables
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN MODE: No resources will be created"
    fi
    
    # Deploy infrastructure components
    create_security_groups
    create_cache_subnet_group
    create_cache_parameter_group
    create_elasticache_cluster
    wait_for_cache_cluster
    create_rds_database
    wait_for_rds_database
    test_connectivity
    create_demo_script
    
    # Final success message
    log_success "Deployment completed successfully!"
    echo
    echo "============================================================================="
    echo "  DEPLOYMENT SUMMARY"
    echo "============================================================================="
    echo "  Redis Cluster ID: $CACHE_CLUSTER_ID"
    echo "  Redis Endpoint: ${REDIS_ENDPOINT:-'(pending)'}"
    echo "  RDS Instance ID: $DB_INSTANCE_ID"
    echo "  RDS Endpoint: ${DB_ENDPOINT:-'(pending)'}"
    echo "  Security Group ID: ${CACHE_SG_ID:-'(pending)'}"
    echo "  Region: $AWS_REGION"
    echo
    echo "  Environment variables saved to: /tmp/elasticache-deployment-vars.env"
    echo "  Cache demo script: $(dirname "$0")/../cache_demo.py"
    echo
    echo "  Next Steps:"
    echo "    1. Source environment variables: source /tmp/elasticache-deployment-vars.env"
    echo "    2. Run cache demo: python3 $(dirname "$0")/../cache_demo.py"
    echo "    3. Clean up when done: ./destroy.sh"
    echo "============================================================================="
}

# Execute main function
main "$@"