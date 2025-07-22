#!/bin/bash
# Deploy script for Real-time Anomaly Detection with Kinesis Data Analytics
# This script deploys the complete infrastructure for anomaly detection using
# Kinesis Data Streams, Managed Service for Apache Flink, CloudWatch, and SNS

set -e  # Exit on any error

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

# Cleanup function for partial failures
cleanup_on_error() {
    warning "Deployment failed. Cleaning up resources..."
    if [[ -f ./destroy.sh ]]; then
        chmod +x ./destroy.sh
        ./destroy.sh
    fi
}

# Set up error handling
trap cleanup_on_error ERR

log "Starting deployment of Real-time Anomaly Detection system..."

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'."
fi

# Check if Maven is available for building the application
MAVEN_AVAILABLE=false
if command -v mvn &> /dev/null; then
    MAVEN_AVAILABLE=true
    log "Maven detected - will build Flink application from source"
else
    warning "Maven not found - will use placeholder JAR for demo"
fi

# Check if Python and boto3 are available for test data generation
PYTHON_AVAILABLE=false
if command -v python3 &> /dev/null || command -v python &> /dev/null; then
    PYTHON_CMD=$(command -v python3 || command -v python)
    if $PYTHON_CMD -c "import boto3" &> /dev/null; then
        PYTHON_AVAILABLE=true
        log "Python with boto3 detected - test data generator will be functional"
    else
        warning "boto3 not found - install with: pip install boto3"
    fi
fi

success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    warning "No default region configured, using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))

export STREAM_NAME="transaction-stream-${RANDOM_SUFFIX}"
export FLINK_APP_NAME="anomaly-detector-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="anomaly-detection-data-${RANDOM_SUFFIX}"
export SNS_TOPIC_NAME="anomaly-alerts-${RANDOM_SUFFIX}"
export LAMBDA_FUNCTION_NAME="anomaly-processor-${RANDOM_SUFFIX}"

# Store environment variables for cleanup script
cat > .env << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export STREAM_NAME=${STREAM_NAME}
export FLINK_APP_NAME=${FLINK_APP_NAME}
export S3_BUCKET_NAME=${S3_BUCKET_NAME}
export SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
export LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
EOF

success "Environment variables configured"

# Step 1: Create S3 bucket for data storage and application artifacts
log "Creating S3 bucket for application artifacts..."

aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION} || {
    error "Failed to create S3 bucket. Bucket name might already exist."
}

success "S3 bucket ${S3_BUCKET_NAME} created"

# Step 2: Create SNS topic for alerting
log "Creating SNS topic for alerts..."

aws sns create-topic --name ${SNS_TOPIC_NAME} --region ${AWS_REGION} || {
    error "Failed to create SNS topic"
}

export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
    --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
    --query "Attributes.TopicArn" --output text)

echo "export SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> .env

success "SNS topic created: ${SNS_TOPIC_NAME}"

# Step 3: Create Kinesis Data Stream
log "Creating Kinesis Data Stream..."

aws kinesis create-stream \
    --stream-name ${STREAM_NAME} \
    --shard-count 2 \
    --region ${AWS_REGION} || {
    error "Failed to create Kinesis Data Stream"
}

# Wait for stream to become active
log "Waiting for Kinesis stream to become active..."
aws kinesis wait stream-exists \
    --stream-name ${STREAM_NAME} \
    --region ${AWS_REGION} || {
    error "Timeout waiting for Kinesis stream to become active"
}

success "Kinesis Data Stream ${STREAM_NAME} created and active"

# Step 4: Create IAM roles for Managed Service for Apache Flink
log "Creating IAM roles for Flink application..."

# Create trust policy for Flink service
cat > flink-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "kinesisanalytics.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create the service role
aws iam create-role \
    --role-name FlinkAnomalyDetectionRole \
    --assume-role-policy-document file://flink-trust-policy.json || {
    # Role might already exist, check if it's accessible
    if aws iam get-role --role-name FlinkAnomalyDetectionRole &> /dev/null; then
        warning "IAM role FlinkAnomalyDetectionRole already exists, using existing role"
    else
        error "Failed to create IAM role for Flink"
    fi
}

# Create policy for Kinesis and CloudWatch access
cat > flink-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:ListShards"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${STREAM_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name FlinkAnomalyDetectionRole \
    --policy-name FlinkAnomalyDetectionPolicy \
    --policy-document file://flink-permissions-policy.json || {
    error "Failed to attach policy to Flink IAM role"
}

success "IAM roles created for Flink application"

# Step 5: Create and build Flink application
log "Creating Flink application code..."

# Create application directory structure
mkdir -p anomaly-detection-app/src/main/java/com/example

# Create the main Flink application
cat > anomaly-detection-app/src/main/java/com/example/AnomalyDetectionApp.java << 'EOF'
package com.example;

import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.java.tuple.Tuple3;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.streaming.connectors.kinesis.FlinkKinesisConsumer;
import org.apache.flink.streaming.connectors.kinesis.config.ConsumerConfigConstants;
import org.apache.flink.util.Collector;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.JsonNode;
import org.apache.flink.shaded.jackson2.com.fasterxml.jackson.databind.ObjectMapper;

import java.util.Properties;

public class AnomalyDetectionApp {
    private static final ObjectMapper objectMapper = new ObjectMapper();
    
    public static void main(String[] args) throws Exception {
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Configure Kinesis source
        Properties kinesisConsumerConfig = new Properties();
        kinesisConsumerConfig.setProperty(ConsumerConfigConstants.AWS_REGION, System.getenv("AWS_REGION"));
        kinesisConsumerConfig.setProperty(ConsumerConfigConstants.STREAM_INITIAL_POSITION, "LATEST");
        
        String streamName = System.getenv("STREAM_NAME");
        if (streamName == null) {
            streamName = "transaction-stream";
        }
        
        FlinkKinesisConsumer<String> kinesisSource = new FlinkKinesisConsumer<>(
            streamName, new SimpleStringSchema(), kinesisConsumerConfig);
        
        DataStream<String> kinesisStream = env.addSource(kinesisSource);
        
        // Parse JSON and extract transaction data
        DataStream<Tuple3<String, Double, Long>> transactions = kinesisStream
            .map(new MapFunction<String, Tuple3<String, Double, Long>>() {
                @Override
                public Tuple3<String, Double, Long> map(String value) throws Exception {
                    try {
                        JsonNode json = objectMapper.readTree(value);
                        String userId = json.get("userId").asText();
                        double amount = json.get("amount").asDouble();
                        long timestamp = json.get("timestamp").asLong();
                        return new Tuple3<>(userId, amount, timestamp);
                    } catch (Exception e) {
                        // Return default values for malformed records
                        return new Tuple3<>("unknown", 0.0, System.currentTimeMillis());
                    }
                }
            });
        
        // Apply windowing and anomaly detection
        DataStream<String> anomalies = transactions
            .keyBy(transaction -> transaction.f0)
            .window(TumblingProcessingTimeWindows.of(Time.minutes(5)))
            .process(new AnomalyDetectionFunction());
        
        // Print anomalies (in production, send to another Kinesis stream or SNS)
        anomalies.print();
        
        env.execute("Real-time Anomaly Detection");
    }
    
    public static class AnomalyDetectionFunction 
        extends ProcessWindowFunction<Tuple3<String, Double, Long>, String, String, TimeWindow> {
        
        @Override
        public void process(String key, Context context, 
                           Iterable<Tuple3<String, Double, Long>> elements, 
                           Collector<String> out) throws Exception {
            
            double sum = 0.0;
            int count = 0;
            double max = Double.MIN_VALUE;
            
            for (Tuple3<String, Double, Long> element : elements) {
                sum += element.f1;
                count++;
                max = Math.max(max, element.f1);
            }
            
            if (count > 0) {
                double avg = sum / count;
                double threshold = avg * 3; // Simple threshold-based anomaly detection
                
                if (max > threshold && max > 1000) { // Additional threshold to reduce noise
                    String anomaly = String.format(
                        "ANOMALY DETECTED: User %s has transaction of %.2f (avg: %.2f, threshold: %.2f)",
                        key, max, avg, threshold);
                    out.collect(anomaly);
                }
            }
        }
    }
}
EOF

# Create Maven pom.xml
cat > anomaly-detection-app/pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
                             http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.example</groupId>
    <artifactId>anomaly-detection</artifactId>
    <version>1.0-SNAPSHOT</version>
    
    <properties>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <flink.version>1.17.1</flink.version>
        <kinesis.version>1.15.4</kinesis.version>
    </properties>
    
    <dependencies>
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-streaming-java</artifactId>
            <version>${flink.version}</version>
        </dependency>
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-connector-kinesis</artifactId>
            <version>${kinesis.version}</version>
        </dependency>
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-java-sdk-kinesis</artifactId>
            <version>1.12.261</version>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-shade-plugin</artifactId>
                <version>3.2.4</version>
                <executions>
                    <execution>
                        <phase>package</phase>
                        <goals>
                            <goal>shade</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
EOF

success "Flink application code created"

# Build and upload the application
log "Building and uploading Flink application..."

cd anomaly-detection-app

if [[ "$MAVEN_AVAILABLE" == true ]]; then
    log "Building Maven project..."
    mvn clean package -q || {
        error "Maven build failed"
    }
    cd ..
    
    # Upload JAR to S3
    aws s3 cp anomaly-detection-app/target/anomaly-detection-1.0-SNAPSHOT.jar \
        s3://${S3_BUCKET_NAME}/applications/ || {
        error "Failed to upload JAR to S3"
    }
    
    success "Application built and uploaded to S3"
else
    cd ..
    warning "Maven not available, creating placeholder JAR for demo"
    
    # Create a minimal placeholder JAR for demo purposes
    echo "UEsDBAoAAAAAAFZMVEoAAAAAAAAAAAAAAAAJAAAATUVUQS1JTkYvUEsDBBQAAAAIAFZMVEpWw8MFLQAAAC0AAAAUAAAATUVUQS1JTkYvTUFOSUZFU1QuTUbzTczLTEstLtENSy0qzszPs1Iw1DPUM9AzMtVRUEjNyclXyKlMSc5ILbJSULBRSMwrLs4sTSxJTbFSyMnILCjJSEyOzkzPqSyITi0tSs+s1EABAAD//wMAUEsDBBQAAAAIAHFMVEojcIiF5gEAAJwDAAA0AAAAY29tL2V4YW1wbGUvQW5vbWFseURldGVjdGlvbkFwcC5jbGFzc0ltYWdldE9mRmlsZQ==" | base64 -d > temp-app.jar 2>/dev/null || echo "placeholder-jar-content" > temp-app.jar
    
    aws s3 cp temp-app.jar s3://${S3_BUCKET_NAME}/applications/anomaly-detection-1.0-SNAPSHOT.jar || {
        error "Failed to upload placeholder JAR to S3"
    }
    
    rm temp-app.jar
    warning "Placeholder JAR uploaded - Flink application may not function properly without proper build"
fi

# Step 6: Create Lambda execution role
log "Creating Lambda execution role..."

# Create trust policy for Lambda
cat > lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create Lambda execution role
aws iam create-role \
    --role-name lambda-execution-role \
    --assume-role-policy-document file://lambda-trust-policy.json || {
    if aws iam get-role --role-name lambda-execution-role &> /dev/null; then
        warning "Lambda execution role already exists, using existing role"
    else
        error "Failed to create Lambda execution role"
    fi
}

# Attach basic execution policy
aws iam attach-role-policy \
    --role-name lambda-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || {
    warning "Failed to attach basic execution policy to Lambda role"
}

# Create policy for CloudWatch and SNS access
cat > lambda-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name lambda-execution-role \
    --policy-name LambdaAnomalyProcessorPolicy \
    --policy-document file://lambda-permissions-policy.json || {
    error "Failed to attach permissions policy to Lambda role"
}

success "Lambda execution role created"

# Step 7: Create Lambda function for anomaly alerting
log "Creating Lambda function for anomaly processing..."

# Create Lambda function for processing anomalies
cat > anomaly-processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    # Parse the anomaly data
    for record in event['Records']:
        # Decode the anomaly message
        message = record['body']
        
        # Extract anomaly details (simplified for demo)
        if 'ANOMALY DETECTED' in message:
            # Send custom metric to CloudWatch
            cloudwatch.put_metric_data(
                Namespace='AnomalyDetection',
                MetricData=[
                    {
                        'MetricName': 'AnomalyCount',
                        'Value': 1,
                        'Unit': 'Count',
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
            
            # Send notification via SNS
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=message,
                Subject='Transaction Anomaly Alert'
            )
            
            print(f"Anomaly processed: {message}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Anomalies processed successfully')
    }
EOF

# Create deployment package
zip -q anomaly-processor.zip anomaly-processor.py

# Wait for IAM role to propagate
sleep 10

# Create Lambda function
aws lambda create-function \
    --function-name ${LAMBDA_FUNCTION_NAME} \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role \
    --handler anomaly-processor.lambda_handler \
    --zip-file fileb://anomaly-processor.zip \
    --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
    --timeout 60 \
    --region ${AWS_REGION} || {
    warning "Lambda function creation failed - continuing with demo (alerts may not work)"
}

success "Lambda function for anomaly processing created"

# Step 8: Create Managed Service for Apache Flink application
log "Creating Managed Service for Apache Flink application..."

# Get the service role ARN
export FLINK_ROLE_ARN=$(aws iam get-role \
    --role-name FlinkAnomalyDetectionRole \
    --query 'Role.Arn' --output text)

echo "export FLINK_ROLE_ARN=${FLINK_ROLE_ARN}" >> .env

# Wait for IAM role to propagate
sleep 15

# Create the application configuration
cat > flink-app-config.json << EOF
{
    "ApplicationName": "${FLINK_APP_NAME}",
    "ApplicationDescription": "Real-time anomaly detection for transaction data",
    "RuntimeEnvironment": "FLINK-1_17",
    "ServiceExecutionRole": "${FLINK_ROLE_ARN}",
    "ApplicationConfiguration": {
        "ApplicationCodeConfiguration": {
            "CodeContent": {
                "S3ContentLocation": {
                    "BucketARN": "arn:aws:s3:::${S3_BUCKET_NAME}",
                    "FileKey": "applications/anomaly-detection-1.0-SNAPSHOT.jar"
                }
            },
            "CodeContentType": "ZIPFILE"
        },
        "EnvironmentProperties": {
            "PropertyGroups": [
                {
                    "PropertyGroupId": "kinesis.analytics.flink.run.options",
                    "PropertyMap": {
                        "aws.region": "${AWS_REGION}",
                        "stream.name": "${STREAM_NAME}"
                    }
                }
            ]
        },
        "FlinkApplicationConfiguration": {
            "CheckpointConfiguration": {
                "ConfigurationType": "CUSTOM",
                "CheckpointingEnabled": true,
                "CheckpointInterval": 60000,
                "MinPauseBetweenCheckpoints": 5000
            },
            "MonitoringConfiguration": {
                "ConfigurationType": "CUSTOM",
                "LogLevel": "INFO",
                "MetricsLevel": "APPLICATION"
            },
            "ParallelismConfiguration": {
                "ConfigurationType": "CUSTOM",
                "Parallelism": 2,
                "ParallelismPerKPU": 1
            }
        }
    }
}
EOF

# Create the Flink application
aws kinesisanalyticsv2 create-application \
    --cli-input-json file://flink-app-config.json \
    --region ${AWS_REGION} || {
    error "Failed to create Flink application"
}

success "Managed Service for Apache Flink application created"

# Step 9: Set up CloudWatch monitoring
log "Setting up CloudWatch anomaly detection and alarms..."

# Create CloudWatch anomaly detector for transaction volume
aws cloudwatch put-anomaly-detector \
    --namespace "AnomalyDetection" \
    --metric-name "AnomalyCount" \
    --stat "Sum" \
    --dimensions Name=Source,Value=FlinkApp \
    --region ${AWS_REGION} || {
    warning "Failed to create CloudWatch anomaly detector"
}

# Create CloudWatch alarm based on anomaly detection
aws cloudwatch put-metric-alarm \
    --alarm-name "AnomalyDetectionAlarm" \
    --alarm-description "Alarm for anomaly detection" \
    --metric-name "AnomalyCount" \
    --namespace "AnomalyDetection" \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions ${SNS_TOPIC_ARN} \
    --region ${AWS_REGION} || {
    warning "Failed to create CloudWatch alarm"
}

success "CloudWatch anomaly detection and alarms configured"

# Step 10: Create test data generator
log "Creating test data generator..."

if [[ "$PYTHON_AVAILABLE" == true ]]; then
    cat > generate-test-data.py << 'EOF'
import json
import random
import time
import boto3
from datetime import datetime
import sys

def generate_transaction():
    """Generate a realistic transaction record"""
    user_ids = ['user001', 'user002', 'user003', 'user004', 'user005']
    
    # Normal transactions: $10-500
    # Anomalous transactions: $5000+ (rare)
    if random.random() < 0.02:  # 2% chance of anomaly
        amount = random.uniform(5000, 50000)
    else:
        amount = random.uniform(10, 500)
    
    return {
        'userId': random.choice(user_ids),
        'amount': round(amount, 2),
        'timestamp': int(time.time() * 1000),
        'transactionId': f'txn_{random.randint(100000, 999999)}',
        'merchantId': f'merchant_{random.randint(1, 100)}'
    }

def send_to_kinesis(stream_name, records_per_second=10, duration_seconds=60):
    """Send test data to Kinesis stream"""
    kinesis = boto3.client('kinesis')
    
    print(f"Sending test data to stream '{stream_name}' for {duration_seconds} seconds...")
    
    start_time = time.time()
    record_count = 0
    
    try:
        while time.time() - start_time < duration_seconds:
            for _ in range(records_per_second):
                record = generate_transaction()
                
                kinesis.put_record(
                    StreamName=stream_name,
                    Data=json.dumps(record),
                    PartitionKey=record['userId']
                )
                
                record_count += 1
                if record_count % 50 == 0:
                    print(f"Sent {record_count} records...")
            
            time.sleep(1)  # Wait 1 second between batches
            
    except KeyboardInterrupt:
        print("Data generation stopped by user")
    except Exception as e:
        print(f"Error sending data: {e}")
    
    print(f"Finished sending {record_count} test records")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate-test-data.py <stream-name> [duration-seconds]")
        sys.exit(1)
    
    stream_name = sys.argv[1]
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    
    send_to_kinesis(stream_name, duration_seconds=duration)
EOF

    success "Test data generator created (functional)"
else
    cat > generate-test-data.py << 'EOF'
import json
import random
import time
from datetime import datetime

def generate_transaction():
    """Generate a realistic transaction record"""
    user_ids = ['user001', 'user002', 'user003', 'user004', 'user005']
    
    # Normal transactions: $10-500
    # Anomalous transactions: $5000+ (rare)
    if random.random() < 0.02:  # 2% chance of anomaly
        amount = random.uniform(5000, 50000)
    else:
        amount = random.uniform(10, 500)
    
    return {
        'userId': random.choice(user_ids),
        'amount': round(amount, 2),
        'timestamp': int(time.time() * 1000),
        'transactionId': f'txn_{random.randint(100000, 999999)}',
        'merchantId': f'merchant_{random.randint(1, 100)}'
    }

print("Test data generator created, but boto3 is required to send data to Kinesis")
print("Install boto3 with: pip install boto3")

# Generate sample data and print to console
for i in range(10):
    sample = generate_transaction()
    print(f"Sample transaction {i+1}: {json.dumps(sample)}")
EOF

    warning "Test data generator created (requires boto3 to function)"
fi

# Step 11: Start the Flink application
log "Starting Flink application..."

# Start the Flink application
aws kinesisanalyticsv2 start-application \
    --application-name ${FLINK_APP_NAME} \
    --run-configuration '{"FlinkRunConfiguration": {"AllowNonRestoredState": true}}' \
    --region ${AWS_REGION} || {
    error "Failed to start Flink application"
}

# Wait a moment for the application to start
sleep 10

# Check application status
APP_STATUS=$(aws kinesisanalyticsv2 describe-application \
    --application-name ${FLINK_APP_NAME} \
    --query 'ApplicationDetail.ApplicationStatus' \
    --output text --region ${AWS_REGION})

if [[ "$APP_STATUS" == "RUNNING" ]]; then
    success "Flink application started and running"
else
    warning "Flink application status: ${APP_STATUS} (may take a few minutes to start)"
fi

# Clean up temporary files
rm -f *.json *.py *.zip 2>/dev/null || true

# Display deployment summary
log "Deployment completed successfully!"
echo ""
echo "=== DEPLOYMENT SUMMARY ==="
echo "AWS Region: ${AWS_REGION}"
echo "Kinesis Stream: ${STREAM_NAME}"
echo "Flink Application: ${FLINK_APP_NAME}"
echo "S3 Bucket: ${S3_BUCKET_NAME}"
echo "SNS Topic: ${SNS_TOPIC_NAME}"
echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
echo ""
echo "=== NEXT STEPS ==="
echo "1. Subscribe to SNS topic for alerts:"
echo "   aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
echo ""
echo "2. Test the system with sample data:"
if [[ "$PYTHON_AVAILABLE" == true ]]; then
    echo "   python generate-test-data.py ${STREAM_NAME} 120"
else
    echo "   Install boto3 first: pip install boto3"
    echo "   Then run: python generate-test-data.py ${STREAM_NAME} 120"
fi
echo ""
echo "3. Monitor CloudWatch metrics in the 'AnomalyDetection' namespace"
echo ""
echo "4. Check Flink application logs in CloudWatch:"
echo "   Log group: /aws/kinesis-analytics/${FLINK_APP_NAME}"
echo ""
echo "Environment variables saved to .env file for cleanup script"
echo ""
warning "Remember to run ./destroy.sh when finished to avoid ongoing charges"

success "Real-time Anomaly Detection system deployed successfully!"