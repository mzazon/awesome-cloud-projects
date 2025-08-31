#!/bin/bash

# deploy.sh - gRPC Microservices with VPC Lattice and CloudWatch Deployment Script
# This script deploys a complete gRPC microservices architecture using VPC Lattice
# for service mesh capabilities and CloudWatch for comprehensive monitoring.

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables for cleanup
VPC_ID=""
SUBNET_ID=""
SG_ID=""
SERVICE_NETWORK_ID=""
VPC_ASSOCIATION_ID=""
USER_TG_ID=""
ORDER_TG_ID=""
INVENTORY_TG_ID=""
USER_INSTANCE_ID=""
ORDER_INSTANCE_ID=""
INVENTORY_INSTANCE_ID=""
USER_SERVICE_ID=""
ORDER_SERVICE_ID=""
INVENTORY_SERVICE_ID=""
USER_SERVICE_ASSOC_ID=""
ORDER_SERVICE_ASSOC_ID=""
INVENTORY_SERVICE_ASSOC_ID=""
USER_LISTENER_ID=""
ORDER_LISTENER_ID=""
INVENTORY_LISTENER_ID=""
RANDOM_SUFFIX=""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_handler() {
    local line_no=$1
    log_error "An error occurred on line $line_no. Deployment failed."
    log_warning "You may need to run the cleanup script to remove partially created resources."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' or set up credentials."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local caller_info=$(aws sts get-caller-identity)
    log_info "Authenticated as: $(echo $caller_info | jq -r '.Arn // .UserId')"
    
    # Verify region is set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            log_error "AWS region not set. Please set AWS_REGION environment variable or configure default region."
            exit 1
        fi
    fi
    
    log_info "Using AWS region: $AWS_REGION"
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting will be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize environment variables
init_environment() {
    log_info "Initializing environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    
    # Save environment for cleanup script
    cat > /tmp/grpc-lattice-env-${RANDOM_SUFFIX}.sh << EOF
#!/bin/bash
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    log_success "Environment initialized"
}

# Create VPC and networking resources
create_vpc_resources() {
    log_info "Creating VPC and networking resources..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=grpc-vpc-${RANDOM_SUFFIX}},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'Vpc.VpcId' --output text)
    log_success "VPC created: ${VPC_ID}"
    
    # Enable DNS hostnames and resolution
    aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames
    aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support
    
    # Create subnet
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_ID} \
        --cidr-block 10.0.1.0/24 \
        --availability-zone $(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text) \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=grpc-subnet-${RANDOM_SUFFIX}},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'Subnet.SubnetId' --output text)
    log_success "Subnet created: ${SUBNET_ID}"
    
    # Create internet gateway for external access (if needed)
    local igw_id=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=grpc-igw-${RANDOM_SUFFIX}},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    # Attach internet gateway to VPC
    aws ec2 attach-internet-gateway --vpc-id ${VPC_ID} --internet-gateway-id ${igw_id}
    
    # Create route table and add route to internet gateway
    local rt_id=$(aws ec2 create-route-table \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=grpc-rt-${RANDOM_SUFFIX}},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route --route-table-id ${rt_id} --destination-cidr-block 0.0.0.0/0 --gateway-id ${igw_id}
    aws ec2 associate-route-table --subnet-id ${SUBNET_ID} --route-table-id ${rt_id}
    
    # Enable auto-assign public IP
    aws ec2 modify-subnet-attribute --subnet-id ${SUBNET_ID} --map-public-ip-on-launch
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name grpc-services-${RANDOM_SUFFIX} \
        --description "Security group for gRPC microservices" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=grpc-sg-${RANDOM_SUFFIX}},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'GroupId' --output text)
    log_success "Security group created: ${SG_ID}"
    
    # Configure security group rules
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 50051-50053 \
        --cidr 10.0.0.0/16 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Purpose,Value=gRPC-Traffic}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 8080 \
        --cidr 10.0.0.0/16 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Purpose,Value=Health-Check}]"
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_ID} \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Purpose,Value=SSH-Access}]"
    
    log_success "VPC and networking resources created"
}

# Create VPC Lattice service network
create_service_network() {
    log_info "Creating VPC Lattice service network..."
    
    SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "grpc-microservices-${RANDOM_SUFFIX}" \
        --auth-type AWS_IAM \
        --tags Key=Environment,Value=Production Key=Purpose,Value=gRPC-Services Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Service network created: ${SERVICE_NETWORK_ID}"
    
    # Associate VPC with service network
    VPC_ASSOCIATION_ID=$(aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --vpc-identifier ${VPC_ID} \
        --tags Key=Service,Value=gRPC-Network Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "VPC associated with service network: ${VPC_ASSOCIATION_ID}"
    
    # Wait for association to complete
    log_info "Waiting for VPC association to complete..."
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws vpc-lattice get-service-network-vpc-association \
            --service-network-vpc-association-identifier ${VPC_ASSOCIATION_ID} \
            --query 'status' --output text)
        
        if [ "$status" = "ACTIVE" ]; then
            log_success "VPC association is active"
            break
        fi
        
        log_info "VPC association status: $status (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "VPC association did not become active within expected time"
        exit 1
    fi
}

# Create target groups
create_target_groups() {
    log_info "Creating target groups for gRPC services..."
    
    # User Service target group
    USER_TG_ID=$(aws vpc-lattice create-target-group \
        --name "user-service-${RANDOM_SUFFIX}" \
        --type INSTANCE \
        --config '{
            "port": 50051,
            "protocol": "HTTP",
            "protocolVersion": "HTTP2",
            "vpcIdentifier": "'${VPC_ID}'",
            "healthCheck": {
                "enabled": true,
                "protocol": "HTTP",
                "protocolVersion": "HTTP1",
                "port": 8080,
                "path": "/health",
                "healthCheckIntervalSeconds": 30,
                "healthCheckTimeoutSeconds": 5,
                "healthyThresholdCount": 2,
                "unhealthyThresholdCount": 3,
                "matcher": {
                    "httpCode": "200"
                }
            }
        }' \
        --tags Key=Service,Value=UserService Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "User Service target group created: ${USER_TG_ID}"
    
    # Order Service target group
    ORDER_TG_ID=$(aws vpc-lattice create-target-group \
        --name "order-service-${RANDOM_SUFFIX}" \
        --type INSTANCE \
        --config '{
            "port": 50052,
            "protocol": "HTTP",
            "protocolVersion": "HTTP2",
            "vpcIdentifier": "'${VPC_ID}'",
            "healthCheck": {
                "enabled": true,
                "protocol": "HTTP",
                "protocolVersion": "HTTP1",
                "port": 8080,
                "path": "/health",
                "healthCheckIntervalSeconds": 30,
                "healthCheckTimeoutSeconds": 5,
                "healthyThresholdCount": 2,
                "unhealthyThresholdCount": 3,
                "matcher": {
                    "httpCode": "200"
                }
            }
        }' \
        --tags Key=Service,Value=OrderService Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Order Service target group created: ${ORDER_TG_ID}"
    
    # Inventory Service target group
    INVENTORY_TG_ID=$(aws vpc-lattice create-target-group \
        --name "inventory-service-${RANDOM_SUFFIX}" \
        --type INSTANCE \
        --config '{
            "port": 50053,
            "protocol": "HTTP",
            "protocolVersion": "HTTP2",
            "vpcIdentifier": "'${VPC_ID}'",
            "healthCheck": {
                "enabled": true,
                "protocol": "HTTP",
                "protocolVersion": "HTTP1",
                "port": 8080,
                "path": "/health",
                "healthCheckIntervalSeconds": 30,
                "healthCheckTimeoutSeconds": 5,
                "healthyThresholdCount": 2,
                "unhealthyThresholdCount": 3,
                "matcher": {
                    "httpCode": "200"
                }
            }
        }' \
        --tags Key=Service,Value=InventoryService Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Inventory Service target group created: ${INVENTORY_TG_ID}"
    
    log_success "All target groups created successfully"
}

# Launch EC2 instances
launch_ec2_instances() {
    log_info "Launching EC2 instances for gRPC services..."
    
    # Get latest Amazon Linux 2 AMI
    local ami_id=$(aws ec2 describe-images \
        --owners amazon \
        --filters 'Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2' \
        'Name=state,Values=available' \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    log_info "Using AMI: $ami_id"
    
    # Create user data script
    cat > /tmp/user-data-${RANDOM_SUFFIX}.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y python3 python3-pip
pip3 install grpcio grpcio-tools flask

# Create a simple gRPC health server
cat > /home/ec2-user/health_server.py << 'PYEOF'
from flask import Flask
import json
app = Flask(__name__)

@app.route('/health')
def health():
    return json.dumps({'status': 'healthy', 'service': 'grpc-service'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYEOF

# Make script executable and start health check server
chmod +x /home/ec2-user/health_server.py
nohup python3 /home/ec2-user/health_server.py > /var/log/health_server.log 2>&1 &

# Log startup completion
echo "$(date): gRPC service instance initialization completed" >> /var/log/grpc-service.log
EOF
    
    # Launch User Service instance
    USER_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${ami_id} \
        --count 1 \
        --instance-type t3.micro \
        --security-group-ids ${SG_ID} \
        --subnet-id ${SUBNET_ID} \
        --user-data file:///tmp/user-data-${RANDOM_SUFFIX}.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=user-service-${RANDOM_SUFFIX}},{Key=Service,Value=UserService},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'Instances[0].InstanceId' --output text)
    log_success "User Service instance launched: ${USER_INSTANCE_ID}"
    
    # Launch Order Service instance
    ORDER_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${ami_id} \
        --count 1 \
        --instance-type t3.micro \
        --security-group-ids ${SG_ID} \
        --subnet-id ${SUBNET_ID} \
        --user-data file:///tmp/user-data-${RANDOM_SUFFIX}.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=order-service-${RANDOM_SUFFIX}},{Key=Service,Value=OrderService},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'Instances[0].InstanceId' --output text)
    log_success "Order Service instance launched: ${ORDER_INSTANCE_ID}"
    
    # Launch Inventory Service instance
    INVENTORY_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${ami_id} \
        --count 1 \
        --instance-type t3.micro \
        --security-group-ids ${SG_ID} \
        --subnet-id ${SUBNET_ID} \
        --user-data file:///tmp/user-data-${RANDOM_SUFFIX}.sh \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=inventory-service-${RANDOM_SUFFIX}},{Key=Service,Value=InventoryService},{Key=Project,Value=gRPC-Microservices}]" \
        --query 'Instances[0].InstanceId' --output text)
    log_success "Inventory Service instance launched: ${INVENTORY_INSTANCE_ID}"
    
    # Wait for instances to be running
    log_info "Waiting for instances to be running..."
    aws ec2 wait instance-running \
        --instance-ids ${USER_INSTANCE_ID} ${ORDER_INSTANCE_ID} ${INVENTORY_INSTANCE_ID}
    log_success "All instances are running"
    
    # Additional wait for user data script to complete
    log_info "Waiting for instances to complete initialization..."
    sleep 60
}

# Register instances with target groups
register_instances() {
    log_info "Registering instances with target groups..."
    
    # Register User Service instance
    aws vpc-lattice register-targets \
        --target-group-identifier ${USER_TG_ID} \
        --targets id=${USER_INSTANCE_ID}
    log_success "User Service instance registered"
    
    # Register Order Service instance
    aws vpc-lattice register-targets \
        --target-group-identifier ${ORDER_TG_ID} \
        --targets id=${ORDER_INSTANCE_ID}
    log_success "Order Service instance registered"
    
    # Register Inventory Service instance
    aws vpc-lattice register-targets \
        --target-group-identifier ${INVENTORY_TG_ID} \
        --targets id=${INVENTORY_INSTANCE_ID}
    log_success "Inventory Service instance registered"
    
    # Wait for targets to become healthy
    log_info "Waiting for targets to become healthy (this may take 2-3 minutes)..."
    sleep 120
}

# Create VPC Lattice services
create_lattice_services() {
    log_info "Creating VPC Lattice services..."
    
    # Create User Service
    USER_SERVICE_ID=$(aws vpc-lattice create-service \
        --name "user-service-${RANDOM_SUFFIX}" \
        --auth-type AWS_IAM \
        --tags Key=Service,Value=UserService Key=Protocol,Value=gRPC Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "User Service created: ${USER_SERVICE_ID}"
    
    # Create Order Service
    ORDER_SERVICE_ID=$(aws vpc-lattice create-service \
        --name "order-service-${RANDOM_SUFFIX}" \
        --auth-type AWS_IAM \
        --tags Key=Service,Value=OrderService Key=Protocol,Value=gRPC Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Order Service created: ${ORDER_SERVICE_ID}"
    
    # Create Inventory Service
    INVENTORY_SERVICE_ID=$(aws vpc-lattice create-service \
        --name "inventory-service-${RANDOM_SUFFIX}" \
        --auth-type AWS_IAM \
        --tags Key=Service,Value=InventoryService Key=Protocol,Value=gRPC Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Inventory Service created: ${INVENTORY_SERVICE_ID}"
}

# Associate services with service network
associate_services() {
    log_info "Associating services with service network..."
    
    # Associate User Service
    USER_SERVICE_ASSOC_ID=$(aws vpc-lattice create-service-network-service-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --service-identifier ${USER_SERVICE_ID} \
        --tags Key=Service,Value=UserService Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "User Service associated: ${USER_SERVICE_ASSOC_ID}"
    
    # Associate Order Service
    ORDER_SERVICE_ASSOC_ID=$(aws vpc-lattice create-service-network-service-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --service-identifier ${ORDER_SERVICE_ID} \
        --tags Key=Service,Value=OrderService Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Order Service associated: ${ORDER_SERVICE_ASSOC_ID}"
    
    # Associate Inventory Service
    INVENTORY_SERVICE_ASSOC_ID=$(aws vpc-lattice create-service-network-service-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --service-identifier ${INVENTORY_SERVICE_ID} \
        --tags Key=Service,Value=InventoryService Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Inventory Service associated: ${INVENTORY_SERVICE_ASSOC_ID}"
}

# Create listeners
create_listeners() {
    log_info "Creating HTTP/2 listeners for gRPC services..."
    
    # Create User Service listener
    USER_LISTENER_ID=$(aws vpc-lattice create-listener \
        --service-identifier ${USER_SERVICE_ID} \
        --name "grpc-listener" \
        --protocol HTTPS \
        --port 443 \
        --default-action '{
            "forward": {
                "targetGroups": [
                    {
                        "targetGroupIdentifier": "'${USER_TG_ID}'",
                        "weight": 100
                    }
                ]
            }
        }' \
        --tags Key=Protocol,Value=gRPC Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "User Service listener created: ${USER_LISTENER_ID}"
    
    # Create Order Service listener
    ORDER_LISTENER_ID=$(aws vpc-lattice create-listener \
        --service-identifier ${ORDER_SERVICE_ID} \
        --name "grpc-listener" \
        --protocol HTTPS \
        --port 443 \
        --default-action '{
            "forward": {
                "targetGroups": [
                    {
                        "targetGroupIdentifier": "'${ORDER_TG_ID}'",
                        "weight": 100
                    }
                ]
            }
        }' \
        --tags Key=Protocol,Value=gRPC Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Order Service listener created: ${ORDER_LISTENER_ID}"
    
    # Create Inventory Service listener
    INVENTORY_LISTENER_ID=$(aws vpc-lattice create-listener \
        --service-identifier ${INVENTORY_SERVICE_ID} \
        --name "grpc-listener" \
        --protocol HTTPS \
        --port 443 \
        --default-action '{
            "forward": {
                "targetGroups": [
                    {
                        "targetGroupIdentifier": "'${INVENTORY_TG_ID}'",
                        "weight": 100
                    }
                ]
            }
        }' \
        --tags Key=Protocol,Value=gRPC Key=Project,Value=gRPC-Microservices \
        --query 'id' --output text)
    log_success "Inventory Service listener created: ${INVENTORY_LISTENER_ID}"
}

# Configure CloudWatch monitoring
configure_monitoring() {
    log_info "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name /aws/vpc-lattice/grpc-services-${RANDOM_SUFFIX} \
        --retention-in-days 7 || log_warning "Log group may already exist"
    log_success "CloudWatch log group created"
    
    # Enable access logging
    aws vpc-lattice put-access-log-subscription \
        --resource-identifier ${SERVICE_NETWORK_ID} \
        --destination-arn arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/vpc-lattice/grpc-services-${RANDOM_SUFFIX}
    log_success "Access logging enabled"
    
    # Create CloudWatch dashboard
    cat > /tmp/dashboard-${RANDOM_SUFFIX}.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/VpcLattice", "TotalRequestCount", "Service", "user-service-${RANDOM_SUFFIX}" ],
                    [ ".", ".", ".", "order-service-${RANDOM_SUFFIX}" ],
                    [ ".", ".", ".", "inventory-service-${RANDOM_SUFFIX}" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "gRPC Request Count"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/VpcLattice", "RequestTime", "Service", "user-service-${RANDOM_SUFFIX}" ],
                    [ ".", ".", ".", "order-service-${RANDOM_SUFFIX}" ],
                    [ ".", ".", ".", "inventory-service-${RANDOM_SUFFIX}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "gRPC Request Latency"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "gRPC-Microservices-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-${RANDOM_SUFFIX}.json
    log_success "CloudWatch dashboard created"
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "gRPC-UserService-HighErrorRate-${RANDOM_SUFFIX}" \
        --alarm-description "High error rate in User Service" \
        --metric-name "HTTPCode_5XX_Count" \
        --namespace "AWS/VpcLattice" \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=Service,Value=user-service-${RANDOM_SUFFIX} || log_warning "Failed to create User Service alarm"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "gRPC-OrderService-HighLatency-${RANDOM_SUFFIX}" \
        --alarm-description "High latency in Order Service" \
        --metric-name "RequestTime" \
        --namespace "AWS/VpcLattice" \
        --statistic Average \
        --period 300 \
        --threshold 1000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=Service,Value=order-service-${RANDOM_SUFFIX} || log_warning "Failed to create Order Service alarm"
    
    log_success "CloudWatch alarms configured"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/grpc-lattice-deployment-${RANDOM_SUFFIX}.json << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "resources": {
        "vpc_id": "${VPC_ID}",
        "subnet_id": "${SUBNET_ID}",
        "security_group_id": "${SG_ID}",
        "service_network_id": "${SERVICE_NETWORK_ID}",
        "vpc_association_id": "${VPC_ASSOCIATION_ID}",
        "target_groups": {
            "user_service": "${USER_TG_ID}",
            "order_service": "${ORDER_TG_ID}",
            "inventory_service": "${INVENTORY_TG_ID}"
        },
        "instances": {
            "user_service": "${USER_INSTANCE_ID}",
            "order_service": "${ORDER_INSTANCE_ID}",
            "inventory_service": "${INVENTORY_INSTANCE_ID}"
        },
        "services": {
            "user_service": "${USER_SERVICE_ID}",
            "order_service": "${ORDER_SERVICE_ID}",
            "inventory_service": "${INVENTORY_SERVICE_ID}"
        },
        "service_associations": {
            "user_service": "${USER_SERVICE_ASSOC_ID}",
            "order_service": "${ORDER_SERVICE_ASSOC_ID}",
            "inventory_service": "${INVENTORY_SERVICE_ASSOC_ID}"
        },
        "listeners": {
            "user_service": "${USER_LISTENER_ID}",
            "order_service": "${ORDER_LISTENER_ID}",
            "inventory_service": "${INVENTORY_LISTENER_ID}"
        }
    }
}
EOF
    
    log_success "Deployment information saved to /tmp/grpc-lattice-deployment-${RANDOM_SUFFIX}.json"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check service network status
    local sn_status=$(aws vpc-lattice get-service-network \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --query 'status' --output text)
    
    if [ "$sn_status" = "ACTIVE" ]; then
        log_success "Service network is active"
    else
        log_warning "Service network status: $sn_status"
    fi
    
    # Check target group health
    local healthy_targets=0
    for tg_id in ${USER_TG_ID} ${ORDER_TG_ID} ${INVENTORY_TG_ID}; do
        local health_status=$(aws vpc-lattice list-targets \
            --target-group-identifier ${tg_id} \
            --query 'items[0].status' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$health_status" = "HEALTHY" ]; then
            ((healthy_targets++))
            log_success "Target group ${tg_id}: HEALTHY"
        else
            log_warning "Target group ${tg_id}: ${health_status}"
        fi
    done
    
    # Get service endpoints
    log_info "Service endpoints:"
    for service_id in ${USER_SERVICE_ID} ${ORDER_SERVICE_ID} ${INVENTORY_SERVICE_ID}; do
        local endpoint=$(aws vpc-lattice get-service \
            --service-identifier ${service_id} \
            --query 'dnsEntry.domainName' --output text 2>/dev/null || echo "N/A")
        local service_name=$(aws vpc-lattice get-service \
            --service-identifier ${service_id} \
            --query 'name' --output text 2>/dev/null || echo "Unknown")
        log_info "  ${service_name}: https://${endpoint}"
    done
    
    log_success "Deployment validation completed"
    log_info "Healthy targets: ${healthy_targets}/3"
}

# Main deployment function
main() {
    log_info "Starting gRPC Microservices with VPC Lattice deployment..."
    log_info "Estimated deployment time: 10-15 minutes"
    log_info "Estimated cost: \$25-50 for testing (resources will be tagged for easy cleanup)"
    
    check_prerequisites
    init_environment
    create_vpc_resources
    create_service_network
    create_target_groups
    launch_ec2_instances
    register_instances
    create_lattice_services
    associate_services
    create_listeners
    configure_monitoring
    save_deployment_info
    validate_deployment
    
    # Cleanup temporary files
    rm -f /tmp/user-data-${RANDOM_SUFFIX}.sh /tmp/dashboard-${RANDOM_SUFFIX}.json
    
    log_success "🎉 Deployment completed successfully!"
    echo ""
    log_info "📋 Deployment Summary:"
    log_info "  • Deployment ID: ${RANDOM_SUFFIX}"
    log_info "  • Service Network: ${SERVICE_NETWORK_ID}"
    log_info "  • Region: ${AWS_REGION}"
    log_info "  • CloudWatch Dashboard: gRPC-Microservices-${RANDOM_SUFFIX}"
    echo ""
    log_info "🔗 Next Steps:"
    log_info "  1. View CloudWatch dashboard in AWS Console"
    log_info "  2. Test gRPC services using the service endpoints"
    log_info "  3. Monitor service health and performance"
    log_info "  4. Run ./destroy.sh when testing is complete"
    echo ""
    log_warning "💰 Cost Notice: Resources are now running and incurring charges."
    log_warning "    Run the destroy script to clean up when testing is complete."
    echo ""
    log_info "🗂️  Environment variables saved to: /tmp/grpc-lattice-env-${RANDOM_SUFFIX}.sh"
    log_info "📊 Deployment details saved to: /tmp/grpc-lattice-deployment-${RANDOM_SUFFIX}.json"
}

# Run main function
main "$@"