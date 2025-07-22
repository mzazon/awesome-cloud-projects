#!/bin/bash

# Deploy script for SNS-SQS Message Fan-out Recipe
# This script implements the message fan-out pattern using SNS and multiple SQS queues

set -e  # Exit on any error

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required permissions by testing a simple operation
    if ! aws sns list-topics &> /dev/null; then
        error "Insufficient permissions for SNS operations."
        exit 1
    fi
    
    if ! aws sqs list-queues &> /dev/null; then
        error "Insufficient permissions for SQS operations."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Resource names
    export TOPIC_NAME="order-events-${RANDOM_SUFFIX}"
    export INVENTORY_QUEUE_NAME="inventory-processing-${RANDOM_SUFFIX}"
    export PAYMENT_QUEUE_NAME="payment-processing-${RANDOM_SUFFIX}"
    export SHIPPING_QUEUE_NAME="shipping-notifications-${RANDOM_SUFFIX}"
    export ANALYTICS_QUEUE_NAME="analytics-reporting-${RANDOM_SUFFIX}"
    export SNS_ROLE_NAME="sns-sqs-fanout-role-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup
    cat > /tmp/sns-fanout-env.sh << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export TOPIC_NAME="${TOPIC_NAME}"
export INVENTORY_QUEUE_NAME="${INVENTORY_QUEUE_NAME}"
export PAYMENT_QUEUE_NAME="${PAYMENT_QUEUE_NAME}"
export SHIPPING_QUEUE_NAME="${SHIPPING_QUEUE_NAME}"
export ANALYTICS_QUEUE_NAME="${ANALYTICS_QUEUE_NAME}"
export SNS_ROLE_NAME="${SNS_ROLE_NAME}"
EOF
    
    log "Environment variables configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "  Random Suffix: ${RANDOM_SUFFIX}"
    log "  Topic Name: ${TOPIC_NAME}"
    
    success "Environment setup completed"
}

# Function to create IAM role for SNS
create_iam_role() {
    log "Creating IAM role for SNS to SQS delivery..."
    
    # Create IAM role
    aws iam create-role \
        --role-name "${SNS_ROLE_NAME}" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "sns.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' > /dev/null 2>&1
    
    export SNS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${SNS_ROLE_NAME}"
    echo "export SNS_ROLE_ARN=\"${SNS_ROLE_ARN}\"" >> /tmp/sns-fanout-env.sh
    
    success "IAM role created: ${SNS_ROLE_ARN}"
}

# Function to create dead letter queues
create_dead_letter_queues() {
    log "Creating dead letter queues..."
    
    # Create DLQ for inventory processing
    aws sqs create-queue \
        --queue-name "inventory-dlq-${RANDOM_SUFFIX}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "60"
        }' > /dev/null
    
    export INVENTORY_DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "inventory-dlq-${RANDOM_SUFFIX}" \
        --query QueueUrl --output text)
    
    # Create DLQ for payment processing
    aws sqs create-queue \
        --queue-name "payment-dlq-${RANDOM_SUFFIX}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "60"
        }' > /dev/null
    
    export PAYMENT_DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "payment-dlq-${RANDOM_SUFFIX}" \
        --query QueueUrl --output text)
    
    # Create DLQ for shipping notifications
    aws sqs create-queue \
        --queue-name "shipping-dlq-${RANDOM_SUFFIX}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "60"
        }' > /dev/null
    
    export SHIPPING_DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "shipping-dlq-${RANDOM_SUFFIX}" \
        --query QueueUrl --output text)
    
    # Create DLQ for analytics reporting
    aws sqs create-queue \
        --queue-name "analytics-dlq-${RANDOM_SUFFIX}" \
        --attributes '{
            "MessageRetentionPeriod": "1209600",
            "VisibilityTimeoutSeconds": "60"
        }' > /dev/null
    
    export ANALYTICS_DLQ_URL=$(aws sqs get-queue-url \
        --queue-name "analytics-dlq-${RANDOM_SUFFIX}" \
        --query QueueUrl --output text)
    
    # Save DLQ URLs to environment file
    cat >> /tmp/sns-fanout-env.sh << EOF
export INVENTORY_DLQ_URL="${INVENTORY_DLQ_URL}"
export PAYMENT_DLQ_URL="${PAYMENT_DLQ_URL}"
export SHIPPING_DLQ_URL="${SHIPPING_DLQ_URL}"
export ANALYTICS_DLQ_URL="${ANALYTICS_DLQ_URL}"
EOF
    
    success "Dead letter queues created"
}

# Function to create primary SQS queues
create_primary_queues() {
    log "Creating primary SQS queues with DLQ configuration..."
    
    # Get DLQ ARNs
    export INVENTORY_DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url $INVENTORY_DLQ_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export PAYMENT_DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url $PAYMENT_DLQ_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export SHIPPING_DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url $SHIPPING_DLQ_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export ANALYTICS_DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url $ANALYTICS_DLQ_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    # Create inventory processing queue
    aws sqs create-queue \
        --queue-name $INVENTORY_QUEUE_NAME \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$INVENTORY_DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' > /dev/null
    
    export INVENTORY_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name $INVENTORY_QUEUE_NAME \
        --query QueueUrl --output text)
    
    # Create payment processing queue
    aws sqs create-queue \
        --queue-name $PAYMENT_QUEUE_NAME \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$PAYMENT_DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' > /dev/null
    
    export PAYMENT_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name $PAYMENT_QUEUE_NAME \
        --query QueueUrl --output text)
    
    # Create shipping notifications queue
    aws sqs create-queue \
        --queue-name $SHIPPING_QUEUE_NAME \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$SHIPPING_DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' > /dev/null
    
    export SHIPPING_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name $SHIPPING_QUEUE_NAME \
        --query QueueUrl --output text)
    
    # Create analytics reporting queue
    aws sqs create-queue \
        --queue-name $ANALYTICS_QUEUE_NAME \
        --attributes '{
            "VisibilityTimeoutSeconds": "300",
            "MessageRetentionPeriod": "1209600",
            "RedrivePolicy": "{\"deadLetterTargetArn\":\"'$ANALYTICS_DLQ_ARN'\",\"maxReceiveCount\":3}"
        }' > /dev/null
    
    export ANALYTICS_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name $ANALYTICS_QUEUE_NAME \
        --query QueueUrl --output text)
    
    # Save queue URLs to environment file
    cat >> /tmp/sns-fanout-env.sh << EOF
export INVENTORY_QUEUE_URL="${INVENTORY_QUEUE_URL}"
export PAYMENT_QUEUE_URL="${PAYMENT_QUEUE_URL}"
export SHIPPING_QUEUE_URL="${SHIPPING_QUEUE_URL}"
export ANALYTICS_QUEUE_URL="${ANALYTICS_QUEUE_URL}"
EOF
    
    success "Primary SQS queues created"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for order events..."
    
    # Create SNS topic
    aws sns create-topic --name $TOPIC_NAME > /dev/null
    
    export TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${TOPIC_NAME}" \
        --query Attributes.TopicArn --output text)
    
    # Configure delivery policy
    aws sns set-topic-attributes \
        --topic-arn $TOPIC_ARN \
        --attribute-name DeliveryPolicy \
        --attribute-value '{
            "http": {
                "defaultHealthyRetryPolicy": {
                    "numRetries": 3,
                    "numNoDelayRetries": 0,
                    "minDelayTarget": 20,
                    "maxDelayTarget": 20,
                    "numMinDelayRetries": 0,
                    "numMaxDelayRetries": 0,
                    "backoffFunction": "linear"
                }
            }
        }' > /dev/null
    
    # Save topic ARN to environment file
    echo "export TOPIC_ARN=\"${TOPIC_ARN}\"" >> /tmp/sns-fanout-env.sh
    
    success "SNS topic created: ${TOPIC_ARN}"
}

# Function to configure queue policies
configure_queue_policies() {
    log "Configuring SQS queue policies for SNS access..."
    
    # Get queue ARNs
    export INVENTORY_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url $INVENTORY_QUEUE_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export PAYMENT_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url $PAYMENT_QUEUE_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export SHIPPING_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url $SHIPPING_QUEUE_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    export ANALYTICS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url $ANALYTICS_QUEUE_URL \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    # Configure access policy for inventory queue
    aws sqs set-queue-attributes \
        --queue-url $INVENTORY_QUEUE_URL \
        --attributes Policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "sqs:SendMessage",
                    "Resource": "'$INVENTORY_QUEUE_ARN'",
                    "Condition": {
                        "ArnEquals": {
                            "aws:SourceArn": "'$TOPIC_ARN'"
                        }
                    }
                }
            ]
        }' > /dev/null
    
    # Configure access policy for payment queue
    aws sqs set-queue-attributes \
        --queue-url $PAYMENT_QUEUE_URL \
        --attributes Policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "sqs:SendMessage",
                    "Resource": "'$PAYMENT_QUEUE_ARN'",
                    "Condition": {
                        "ArnEquals": {
                            "aws:SourceArn": "'$TOPIC_ARN'"
                        }
                    }
                }
            ]
        }' > /dev/null
    
    # Configure access policy for shipping queue
    aws sqs set-queue-attributes \
        --queue-url $SHIPPING_QUEUE_URL \
        --attributes Policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "sqs:SendMessage",
                    "Resource": "'$SHIPPING_QUEUE_ARN'",
                    "Condition": {
                        "ArnEquals": {
                            "aws:SourceArn": "'$TOPIC_ARN'"
                        }
                    }
                }
            ]
        }' > /dev/null
    
    # Configure access policy for analytics queue
    aws sqs set-queue-attributes \
        --queue-url $ANALYTICS_QUEUE_URL \
        --attributes Policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "sqs:SendMessage",
                    "Resource": "'$ANALYTICS_QUEUE_ARN'",
                    "Condition": {
                        "ArnEquals": {
                            "aws:SourceArn": "'$TOPIC_ARN'"
                        }
                    }
                }
            ]
        }' > /dev/null
    
    success "SQS queue policies configured"
}

# Function to create SNS subscriptions
create_sns_subscriptions() {
    log "Creating SNS subscriptions with message filtering..."
    
    # Subscribe inventory queue with filter
    aws sns subscribe \
        --topic-arn $TOPIC_ARN \
        --protocol sqs \
        --notification-endpoint $INVENTORY_QUEUE_ARN \
        --attributes FilterPolicy='{
            "eventType": ["inventory_update", "stock_check"],
            "priority": ["high", "medium"]
        }' > /dev/null
    
    # Subscribe payment queue with filter
    aws sns subscribe \
        --topic-arn $TOPIC_ARN \
        --protocol sqs \
        --notification-endpoint $PAYMENT_QUEUE_ARN \
        --attributes FilterPolicy='{
            "eventType": ["payment_request", "payment_confirmation"],
            "priority": ["high"]
        }' > /dev/null
    
    # Subscribe shipping queue with filter
    aws sns subscribe \
        --topic-arn $TOPIC_ARN \
        --protocol sqs \
        --notification-endpoint $SHIPPING_QUEUE_ARN \
        --attributes FilterPolicy='{
            "eventType": ["shipping_notification", "delivery_update"],
            "priority": ["high", "medium", "low"]
        }' > /dev/null
    
    # Subscribe analytics queue (no filter)
    aws sns subscribe \
        --topic-arn $TOPIC_ARN \
        --protocol sqs \
        --notification-endpoint $ANALYTICS_QUEUE_ARN > /dev/null
    
    success "SNS subscriptions created with message filtering"
}

# Function to configure CloudWatch monitoring
configure_monitoring() {
    log "Configuring CloudWatch alarms and monitoring..."
    
    # Create alarm for inventory queue depth
    aws cloudwatch put-metric-alarm \
        --alarm-name "inventory-queue-depth-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor inventory queue depth" \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Average \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 100 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=QueueName,Value=$INVENTORY_QUEUE_NAME > /dev/null
    
    # Create alarm for payment queue depth
    aws cloudwatch put-metric-alarm \
        --alarm-name "payment-queue-depth-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor payment queue depth" \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Average \
        --period 300 \
        --evaluation-periods 2 \
        --threshold 50 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=QueueName,Value=$PAYMENT_QUEUE_NAME > /dev/null
    
    # Create alarm for SNS failed deliveries
    aws cloudwatch put-metric-alarm \
        --alarm-name "sns-failed-deliveries-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor SNS failed deliveries" \
        --metric-name NumberOfNotificationsFailed \
        --namespace AWS/SNS \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 1 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=TopicName,Value=$TOPIC_NAME > /dev/null
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "sns-fanout-dashboard-${RANDOM_SUFFIX}" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", "'$TOPIC_NAME'"],
                            ["AWS/SNS", "NumberOfNotificationsFailed", "TopicName", "'$TOPIC_NAME'"]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'$AWS_REGION'",
                        "title": "SNS Message Publishing"
                    }
                },
                {
                    "type": "metric",
                    "properties": {
                        "metrics": [
                            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", "'$INVENTORY_QUEUE_NAME'"],
                            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", "'$PAYMENT_QUEUE_NAME'"],
                            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", "'$SHIPPING_QUEUE_NAME'"],
                            ["AWS/SQS", "ApproximateNumberOfVisibleMessages", "QueueName", "'$ANALYTICS_QUEUE_NAME'"]
                        ],
                        "period": 300,
                        "stat": "Average",
                        "region": "'$AWS_REGION'",
                        "title": "SQS Queue Depths"
                    }
                }
            ]
        }' > /dev/null
    
    success "CloudWatch monitoring configured"
}

# Function to test the deployment
test_deployment() {
    log "Testing message fan-out deployment..."
    
    # Publish test messages
    aws sns publish \
        --topic-arn $TOPIC_ARN \
        --message '{
            "orderId": "test-order-12345",
            "customerId": "test-customer-789",
            "productId": "test-product-abc",
            "quantity": 2,
            "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
        }' \
        --message-attributes '{
            "eventType": {
                "DataType": "String",
                "StringValue": "inventory_update"
            },
            "priority": {
                "DataType": "String",
                "StringValue": "high"
            }
        }' > /dev/null
    
    # Wait for message propagation
    sleep 15
    
    # Check queue depths
    INVENTORY_MSGS=$(aws sqs get-queue-attributes \
        --queue-url $INVENTORY_QUEUE_URL \
        --attribute-names ApproximateNumberOfMessages \
        --query Attributes.ApproximateNumberOfMessages --output text)
    
    ANALYTICS_MSGS=$(aws sqs get-queue-attributes \
        --queue-url $ANALYTICS_QUEUE_URL \
        --attribute-names ApproximateNumberOfMessages \
        --query Attributes.ApproximateNumberOfMessages --output text)
    
    if [ "$INVENTORY_MSGS" -gt 0 ] && [ "$ANALYTICS_MSGS" -gt 0 ]; then
        success "Message fan-out test passed - messages delivered to filtered queues"
    else
        warning "Message fan-out test inconclusive - check queue depths manually"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "======================================"
    echo "SNS Topic ARN: ${TOPIC_ARN}"
    echo "Inventory Queue URL: ${INVENTORY_QUEUE_URL}"
    echo "Payment Queue URL: ${PAYMENT_QUEUE_URL}"
    echo "Shipping Queue URL: ${SHIPPING_QUEUE_URL}"
    echo "Analytics Queue URL: ${ANALYTICS_QUEUE_URL}"
    echo "======================================"
    echo "CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=sns-fanout-dashboard-${RANDOM_SUFFIX}"
    echo "======================================"
    echo "Environment variables saved to: /tmp/sns-fanout-env.sh"
    echo "Use 'source /tmp/sns-fanout-env.sh' to reload environment for cleanup"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "SNS-SQS Message Fan-out Deployment Script"
    echo "=========================================="
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_dead_letter_queues
    create_primary_queues
    create_sns_topic
    configure_queue_policies
    create_sns_subscriptions
    configure_monitoring
    test_deployment
    display_summary
    
    success "Deployment completed successfully!"
    echo "Use the destroy.sh script to clean up resources when done."
}

# Handle script interruption
trap 'error "Deployment interrupted. You may need to clean up resources manually."; exit 1' INT

# Run main function
main "$@"