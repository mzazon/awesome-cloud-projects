#!/bin/bash

# Deploy script for Amazon Neptune Graph Database and Recommendation Engine
# Recipe: Graph-Based Recommendation Engine

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Amazon Neptune cluster for graph database recommendation engine.

Options:
    -h, --help          Show this help message
    -r, --region        AWS region (default: from AWS CLI config)
    -d, --dry-run       Show what would be deployed without creating resources
    --cluster-id        Custom Neptune cluster identifier
    --skip-data         Skip sample data loading
    --ec2-ami           Custom EC2 AMI ID (default: Amazon Linux 2)

Examples:
    $0                          # Deploy with default settings
    $0 --region us-west-2       # Deploy in specific region
    $0 --dry-run                # Preview deployment
    $0 --skip-data              # Deploy without sample data

EOF
}

# Default values
DRY_RUN=false
SKIP_DATA=false
CUSTOM_CLUSTER_ID=""
CUSTOM_AMI=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --cluster-id)
            CUSTOM_CLUSTER_ID="$2"
            shift 2
            ;;
        --skip-data)
            SKIP_DATA=true
            shift
            ;;
        --ec2-ami)
            CUSTOM_AMI="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure'."
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing via package manager..."
        if command -v yum &> /dev/null; then
            sudo yum install -y jq || error "Failed to install jq"
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq || error "Failed to install jq"
        else
            error "Please install jq manually: https://github.com/jqlang/jq"
        fi
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Use --region flag or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Resource names
    export NEPTUNE_CLUSTER_ID=${CUSTOM_CLUSTER_ID:-"neptune-recommendations-${RANDOM_SUFFIX}"}
    export VPC_NAME="neptune-vpc-${RANDOM_SUFFIX}"
    export SUBNET_GROUP_NAME="neptune-subnet-group-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="neptune-sg-${RANDOM_SUFFIX}"
    export EC2_KEY_PAIR_NAME="neptune-keypair-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="neptune-sample-data-${RANDOM_SUFFIX}"
    
    # Get latest Amazon Linux 2 AMI if not provided
    if [[ -z "$CUSTOM_AMI" ]]; then
        AMAZON_LINUX_AMI=$(aws ec2 describe-images \
            --owners amazon \
            --filters 'Name=name,Values=amzn2-ami-hvm-*' \
                      'Name=architecture,Values=x86_64' \
                      'Name=state,Values=available' \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text)
        export EC2_AMI_ID=${AMAZON_LINUX_AMI}
    else
        export EC2_AMI_ID=${CUSTOM_AMI}
    fi
    
    log "Environment variables configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  Neptune Cluster ID: ${NEPTUNE_CLUSTER_ID}"
    log "  VPC Name: ${VPC_NAME}"
    log "  S3 Bucket: ${S3_BUCKET_NAME}"
    log "  EC2 AMI: ${EC2_AMI_ID}"
}

# Dry run function
dry_run_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No resources will be created"
        echo ""
        echo "Would create the following resources:"
        echo "  • VPC: ${VPC_NAME}"
        echo "  • Neptune Cluster: ${NEPTUNE_CLUSTER_ID}"
        echo "  • Neptune Instances: Primary + 1 Read Replica"
        echo "  • EC2 Instance: t3.medium (Gremlin client)"
        echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
        echo "  • Security Groups, Subnets, Route Tables"
        echo ""
        echo "Estimated cost: $12-25/hour for Neptune + $0.10/hour for EC2"
        echo ""
        echo "Run without --dry-run to deploy these resources."
        exit 0
    fi
}

# Create VPC and networking
create_networking() {
    log "Creating VPC and networking infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags --resources ${VPC_ID} \
        --tags Key=Name,Value=${VPC_NAME}
    
    # Create Internet Gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID}
    
    export VPC_ID IGW_ID
    success "VPC and Internet Gateway created: ${VPC_ID}"
}

# Create subnets
create_subnets() {
    log "Creating subnets in multiple Availability Zones..."
    
    # Get available AZs
    AZ1=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[0].ZoneName' --output text)
    AZ2=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[1].ZoneName' --output text)
    AZ3=$(aws ec2 describe-availability-zones \
        --query 'AvailabilityZones[2].ZoneName' --output text)
    
    # Create private subnets for Neptune
    SUBNET1_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} --cidr-block 10.0.1.0/24 \
        --availability-zone ${AZ1} \
        --query 'Subnet.SubnetId' --output text)
    
    SUBNET2_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} --cidr-block 10.0.2.0/24 \
        --availability-zone ${AZ2} \
        --query 'Subnet.SubnetId' --output text)
    
    SUBNET3_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} --cidr-block 10.0.3.0/24 \
        --availability-zone ${AZ3} \
        --query 'Subnet.SubnetId' --output text)
    
    # Create public subnet for EC2 instance
    PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} --cidr-block 10.0.10.0/24 \
        --availability-zone ${AZ1} \
        --query 'Subnet.SubnetId' --output text)
    
    export SUBNET1_ID SUBNET2_ID SUBNET3_ID PUBLIC_SUBNET_ID
    success "Subnets created in multiple AZs"
}

# Configure route tables and security groups
configure_security() {
    log "Configuring route tables and security groups..."
    
    # Create route table for public subnet
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id ${VPC_ID} \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route --route-table-id ${ROUTE_TABLE_ID} \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id ${IGW_ID}
    
    aws ec2 associate-route-table \
        --route-table-id ${ROUTE_TABLE_ID} \
        --subnet-id ${PUBLIC_SUBNET_ID}
    
    # Create security group for Neptune
    NEPTUNE_SG_ID=$(aws ec2 create-security-group \
        --group-name ${SECURITY_GROUP_NAME} \
        --description "Security group for Neptune cluster" \
        --vpc-id ${VPC_ID} \
        --query 'GroupId' --output text)
    
    # Allow Neptune port access from within VPC
    aws ec2 authorize-security-group-ingress \
        --group-id ${NEPTUNE_SG_ID} \
        --protocol tcp --port 8182 \
        --source-group ${NEPTUNE_SG_ID}
    
    # Allow SSH access to EC2
    aws ec2 authorize-security-group-ingress \
        --group-id ${NEPTUNE_SG_ID} \
        --protocol tcp --port 22 \
        --cidr 0.0.0.0/0
    
    export ROUTE_TABLE_ID NEPTUNE_SG_ID
    success "Route tables and security groups configured"
}

# Create S3 bucket for sample data
create_s3_bucket() {
    log "Creating S3 bucket for sample data..."
    
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://${S3_BUCKET_NAME}
    else
        aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    success "S3 bucket created: ${S3_BUCKET_NAME}"
}

# Create Neptune subnet group
create_neptune_subnet_group() {
    log "Creating Neptune subnet group..."
    
    aws neptune create-db-subnet-group \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --db-subnet-group-description "Subnet group for Neptune cluster" \
        --subnet-ids ${SUBNET1_ID} ${SUBNET2_ID} ${SUBNET3_ID} \
        --tags Key=Name,Value=${SUBNET_GROUP_NAME}
    
    success "Neptune subnet group created: ${SUBNET_GROUP_NAME}"
}

# Create Neptune cluster
create_neptune_cluster() {
    log "Creating Neptune cluster (this may take 10-15 minutes)..."
    
    aws neptune create-db-cluster \
        --db-cluster-identifier ${NEPTUNE_CLUSTER_ID} \
        --engine neptune \
        --engine-version 1.3.2.0 \
        --master-username neptuneadmin \
        --master-user-password TempPassword123! \
        --db-subnet-group-name ${SUBNET_GROUP_NAME} \
        --vpc-security-group-ids ${NEPTUNE_SG_ID} \
        --storage-encrypted \
        --backup-retention-period 7 \
        --preferred-backup-window "03:00-04:00" \
        --preferred-maintenance-window "sun:04:00-sun:05:00" \
        --tags Key=Name,Value=${NEPTUNE_CLUSTER_ID}
    
    log "Waiting for Neptune cluster to be available..."
    aws neptune wait db-cluster-available \
        --db-cluster-identifier ${NEPTUNE_CLUSTER_ID}
    
    success "Neptune cluster is available"
}

# Create Neptune instances
create_neptune_instances() {
    log "Creating Neptune primary and replica instances..."
    
    # Create primary instance
    aws neptune create-db-instance \
        --db-instance-identifier ${NEPTUNE_CLUSTER_ID}-primary \
        --db-instance-class db.r5.large \
        --engine neptune \
        --db-cluster-identifier ${NEPTUNE_CLUSTER_ID} \
        --publicly-accessible false \
        --tags Key=Name,Value=${NEPTUNE_CLUSTER_ID}-primary
    
    # Create replica instance
    aws neptune create-db-instance \
        --db-instance-identifier ${NEPTUNE_CLUSTER_ID}-replica-1 \
        --db-instance-class db.r5.large \
        --engine neptune \
        --db-cluster-identifier ${NEPTUNE_CLUSTER_ID} \
        --publicly-accessible false \
        --tags Key=Name,Value=${NEPTUNE_CLUSTER_ID}-replica-1
    
    log "Waiting for Neptune instances to be available..."
    aws neptune wait db-instance-available \
        --db-instance-identifier ${NEPTUNE_CLUSTER_ID}-primary &
    
    aws neptune wait db-instance-available \
        --db-instance-identifier ${NEPTUNE_CLUSTER_ID}-replica-1 &
    
    wait  # Wait for both background processes
    
    success "Neptune instances created and available"
}

# Create EC2 key pair and instance
create_ec2_instance() {
    log "Creating EC2 instance for Gremlin client..."
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name ${EC2_KEY_PAIR_NAME} \
        --query 'KeyMaterial' --output text > ${EC2_KEY_PAIR_NAME}.pem
    
    chmod 400 ${EC2_KEY_PAIR_NAME}.pem
    
    # Create user data script
    cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip git
pip3 install gremlinpython boto3
EOF
    
    # Launch EC2 instance
    EC2_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${EC2_AMI_ID} \
        --instance-type t3.medium \
        --key-name ${EC2_KEY_PAIR_NAME} \
        --security-group-ids ${NEPTUNE_SG_ID} \
        --subnet-id ${PUBLIC_SUBNET_ID} \
        --associate-public-ip-address \
        --user-data file://user-data.sh \
        --tag-specifications \
        'ResourceType=instance,Tags=[{Key=Name,Value=neptune-client}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    # Wait for instance to be running
    log "Waiting for EC2 instance to be running..."
    aws ec2 wait instance-running --instance-ids ${EC2_INSTANCE_ID}
    
    # Get public IP
    EC2_PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids ${EC2_INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    export EC2_INSTANCE_ID EC2_PUBLIC_IP
    success "EC2 instance created: ${EC2_INSTANCE_ID}"
    
    # Clean up user data script
    rm -f user-data.sh
}

# Get Neptune endpoints
get_neptune_endpoints() {
    log "Getting Neptune cluster endpoints..."
    
    NEPTUNE_ENDPOINT=$(aws neptune describe-db-clusters \
        --db-cluster-identifier ${NEPTUNE_CLUSTER_ID} \
        --query 'DBClusters[0].Endpoint' --output text)
    
    NEPTUNE_READ_ENDPOINT=$(aws neptune describe-db-clusters \
        --db-cluster-identifier ${NEPTUNE_CLUSTER_ID} \
        --query 'DBClusters[0].ReaderEndpoint' --output text)
    
    export NEPTUNE_ENDPOINT NEPTUNE_READ_ENDPOINT
    success "Neptune endpoints retrieved"
}

# Create sample data
create_sample_data() {
    if [[ "$SKIP_DATA" == "true" ]]; then
        warning "Skipping sample data creation"
        return
    fi
    
    log "Creating and uploading sample data..."
    
    # Create sample data files
    cat > sample-users.csv << 'EOF'
id,name,age,city,interests
user1,Alice,28,Seattle,books;technology;travel
user2,Bob,35,Portland,sports;music;cooking
user3,Carol,42,Vancouver,art;books;photography
user4,David,31,San Francisco,technology;gaming;fitness
user5,Eve,26,Los Angeles,fashion;travel;music
EOF
    
    cat > sample-products.csv << 'EOF'
id,name,category,price,brand,tags
prod1,Laptop,Electronics,999.99,TechCorp,technology;work;portable
prod2,Running Shoes,Sports,129.99,SportsBrand,fitness;running;comfort
prod3,Camera,Electronics,599.99,PhotoPro,photography;hobby;travel
prod4,Cookbook,Books,29.99,FoodPress,cooking;recipes;kitchen
prod5,Headphones,Electronics,199.99,AudioMax,music;technology;wireless
EOF
    
    cat > sample-purchases.csv << 'EOF'
user_id,product_id,quantity,purchase_date,rating
user1,prod1,1,2024-01-15,5
user1,prod3,1,2024-01-20,4
user2,prod2,1,2024-01-18,5
user2,prod4,2,2024-01-25,4
user3,prod3,1,2024-01-22,5
user3,prod4,1,2024-01-28,3
user4,prod1,1,2024-01-30,4
user4,prod5,1,2024-02-02,5
user5,prod5,1,2024-02-05,4
EOF
    
    # Upload to S3
    aws s3 cp sample-users.csv s3://${S3_BUCKET_NAME}/
    aws s3 cp sample-products.csv s3://${S3_BUCKET_NAME}/
    aws s3 cp sample-purchases.csv s3://${S3_BUCKET_NAME}/
    
    # Create Gremlin data loading script
    cat > load-data.groovy << 'EOF'
// Clear existing data
g.V().drop().iterate()

// Create user vertices
g.addV('user').property('id', 'user1').property('name', 'Alice').property('age', 28).property('city', 'Seattle').next()
g.addV('user').property('id', 'user2').property('name', 'Bob').property('age', 35).property('city', 'Portland').next()
g.addV('user').property('id', 'user3').property('name', 'Carol').property('age', 42).property('city', 'Vancouver').next()
g.addV('user').property('id', 'user4').property('name', 'David').property('age', 31).property('city', 'San Francisco').next()
g.addV('user').property('id', 'user5').property('name', 'Eve').property('age', 26).property('city', 'Los Angeles').next()

// Create product vertices
g.addV('product').property('id', 'prod1').property('name', 'Laptop').property('category', 'Electronics').property('price', 999.99).next()
g.addV('product').property('id', 'prod2').property('name', 'Running Shoes').property('category', 'Sports').property('price', 129.99).next()
g.addV('product').property('id', 'prod3').property('name', 'Camera').property('category', 'Electronics').property('price', 599.99).next()
g.addV('product').property('id', 'prod4').property('name', 'Cookbook').property('category', 'Books').property('price', 29.99).next()
g.addV('product').property('id', 'prod5').property('name', 'Headphones').property('category', 'Electronics').property('price', 199.99).next()

// Create purchase relationships
g.V().has('user', 'id', 'user1').as('u').V().has('product', 'id', 'prod1').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-15').next()
g.V().has('user', 'id', 'user1').as('u').V().has('product', 'id', 'prod3').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-20').next()
g.V().has('user', 'id', 'user2').as('u').V().has('product', 'id', 'prod2').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-18').next()
g.V().has('user', 'id', 'user2').as('u').V().has('product', 'id', 'prod4').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-25').next()
g.V().has('user', 'id', 'user3').as('u').V().has('product', 'id', 'prod3').addE('purchased').from('u').property('rating', 5).property('date', '2024-01-22').next()
g.V().has('user', 'id', 'user3').as('u').V().has('product', 'id', 'prod4').addE('purchased').from('u').property('rating', 3).property('date', '2024-01-28').next()
g.V().has('user', 'id', 'user4').as('u').V().has('product', 'id', 'prod1').addE('purchased').from('u').property('rating', 4).property('date', '2024-01-30').next()
g.V().has('user', 'id', 'user4').as('u').V().has('product', 'id', 'prod5').addE('purchased').from('u').property('rating', 5).property('date', '2024-02-02').next()
g.V().has('user', 'id', 'user5').as('u').V().has('product', 'id', 'prod5').addE('purchased').from('u').property('rating', 4).property('date', '2024-02-05').next()

// Create category relationships
g.V().has('product', 'category', 'Electronics').as('p1').V().has('product', 'category', 'Electronics').as('p2').where(neq('p1')).addE('same_category').from('p1').to('p2').next()

println "Data loaded successfully"
EOF
    
    success "Sample data created and uploaded to S3"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > neptune-deployment-info.json << EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "${AWS_REGION}",
  "neptune_cluster_id": "${NEPTUNE_CLUSTER_ID}",
  "neptune_endpoint": "${NEPTUNE_ENDPOINT}",
  "neptune_read_endpoint": "${NEPTUNE_READ_ENDPOINT}",
  "vpc_id": "${VPC_ID}",
  "security_group_id": "${NEPTUNE_SG_ID}",
  "ec2_instance_id": "${EC2_INSTANCE_ID}",
  "ec2_public_ip": "${EC2_PUBLIC_IP}",
  "ec2_key_pair": "${EC2_KEY_PAIR_NAME}",
  "s3_bucket": "${S3_BUCKET_NAME}",
  "subnet_group": "${SUBNET_GROUP_NAME}",
  "estimated_hourly_cost": "$12-25"
}
EOF
    
    success "Deployment information saved to neptune-deployment-info.json"
}

# Print deployment summary
print_summary() {
    echo ""
    echo "======================================"
    echo "🎉 Neptune Deployment Complete!"
    echo "======================================"
    echo ""
    echo "📊 Infrastructure Created:"
    echo "  • Neptune Cluster: ${NEPTUNE_CLUSTER_ID}"
    echo "  • Write Endpoint: ${NEPTUNE_ENDPOINT}"
    echo "  • Read Endpoint: ${NEPTUNE_READ_ENDPOINT}"
    echo "  • EC2 Instance: ${EC2_INSTANCE_ID}"
    echo "  • Public IP: ${EC2_PUBLIC_IP}"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo ""
    echo "🔐 Access Information:"
    echo "  • SSH Key: ${EC2_KEY_PAIR_NAME}.pem"
    echo "  • SSH Command: ssh -i ${EC2_KEY_PAIR_NAME}.pem ec2-user@${EC2_PUBLIC_IP}"
    echo ""
    echo "💰 Estimated Costs:"
    echo "  • Neptune: $12-25/hour"
    echo "  • EC2: $0.10/hour"
    echo ""
    echo "🧪 Next Steps:"
    echo "  1. SSH to EC2 instance to test connectivity"
    echo "  2. Load sample data using the Gremlin scripts"
    echo "  3. Test recommendation algorithms"
    echo "  4. Run './destroy.sh' when finished to clean up"
    echo ""
    echo "📖 Documentation:"
    echo "  • Recipe: aws/graph-databases-recommendation-engines-amazon-neptune/"
    echo "  • Deployment Info: neptune-deployment-info.json"
    echo ""
    warning "Remember to run destroy.sh to avoid ongoing charges!"
}

# Cleanup on error
cleanup_on_error() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Run destroy.sh to clean up any created resources."
    fi
}

# Main deployment function
main() {
    echo "🚀 Starting Neptune Graph Database Deployment"
    echo "=============================================="
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    dry_run_summary
    
    log "Starting infrastructure deployment..."
    
    create_s3_bucket
    create_networking
    create_subnets
    configure_security
    create_neptune_subnet_group
    create_neptune_cluster
    create_neptune_instances
    get_neptune_endpoints
    create_ec2_instance
    create_sample_data
    save_deployment_info
    
    print_summary
}

# Run main function
main "$@"