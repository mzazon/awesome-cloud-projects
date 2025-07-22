#!/bin/bash

# Real-time Analytics Dashboard Deployment Script
# This script deploys Kinesis Data Streams, Managed Service for Apache Flink,
# S3 buckets, and prepares QuickSight integration for real-time analytics

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check required permissions
check_permissions() {
    log_info "Checking AWS permissions..."
    
    # Check if user has required permissions for each service
    local services=("kinesis" "kinesisanalyticsv2" "s3" "iam" "logs")
    for service in "${services[@]}"; do
        if ! aws ${service} help >/dev/null 2>&1; then
            log_warning "Cannot access ${service} service - permissions may be insufficient"
        fi
    done
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "jq" "python3")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check AWS configuration
    check_aws_config
    
    # Check permissions
    check_permissions
    
    log_success "Prerequisites validation completed"
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix using AWS CLI
    if ! RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null); then
        # Fallback to date-based suffix if secretsmanager fails
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
        log_warning "Using date-based suffix instead of random password"
    fi
    
    export STREAM_NAME="analytics-stream-${RANDOM_SUFFIX}"
    export FLINK_APP_NAME="analytics-app-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="analytics-results-${RANDOM_SUFFIX}"
    export FLINK_CODE_BUCKET="flink-code-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="FlinkAnalyticsRole-${RANDOM_SUFFIX}"
    
    log_info "Generated resource names with suffix: ${RANDOM_SUFFIX}"
    log_info "Stream: ${STREAM_NAME}"
    log_info "Flink App: ${FLINK_APP_NAME}"
    log_info "S3 Buckets: ${S3_BUCKET_NAME}, ${FLINK_CODE_BUCKET}"
    log_info "IAM Role: ${IAM_ROLE_NAME}"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Function to create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    # Create results bucket
    if aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_success "Created S3 bucket: ${S3_BUCKET_NAME}"
    else
        log_error "Failed to create S3 bucket: ${S3_BUCKET_NAME}"
        exit 1
    fi
    
    # Create Flink code bucket
    if aws s3 mb "s3://${FLINK_CODE_BUCKET}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_success "Created S3 bucket: ${FLINK_CODE_BUCKET}"
    else
        log_error "Failed to create S3 bucket: ${FLINK_CODE_BUCKET}"
        exit 1
    fi
}

# Function to create Kinesis Data Stream
create_kinesis_stream() {
    log_info "Creating Kinesis Data Stream..."
    
    if aws kinesis create-stream \
        --stream-name "${STREAM_NAME}" \
        --shard-count 2 \
        --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_success "Created Kinesis Data Stream: ${STREAM_NAME}"
    else
        log_error "Failed to create Kinesis Data Stream"
        exit 1
    fi
    
    # Wait for stream to become active
    log_info "Waiting for stream to become active..."
    if aws kinesis wait stream-exists \
        --stream-name "${STREAM_NAME}" \
        --region "${AWS_REGION}"; then
        log_success "Kinesis stream is now active"
    else
        log_error "Timeout waiting for stream to become active"
        exit 1
    fi
    
    # Get stream ARN
    export STREAM_ARN=$(aws kinesis describe-stream \
        --stream-name "${STREAM_NAME}" \
        --query 'StreamDescription.StreamARN' \
        --output text)
    log_info "Stream ARN: ${STREAM_ARN}"
}

# Function to create IAM role for Flink
create_iam_role() {
    log_info "Creating IAM role for Flink..."
    
    # Create trust policy
    cat > /tmp/flink-trust-policy.json << EOF
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
    
    # Create IAM role
    if aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/flink-trust-policy.json >/dev/null 2>&1; then
        log_success "Created IAM role: ${IAM_ROLE_NAME}"
    else
        log_error "Failed to create IAM role"
        exit 1
    fi
    
    # Create permissions policy
    cat > /tmp/flink-permissions-policy.json << EOF
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
            "Resource": "${STREAM_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}/*",
                "arn:aws:s3:::${FLINK_CODE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${FLINK_CODE_BUCKET}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach permissions policy
    if aws iam put-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name FlinkAnalyticsPolicy \
        --policy-document file:///tmp/flink-permissions-policy.json >/dev/null 2>&1; then
        log_success "Attached permissions policy to IAM role"
    else
        log_error "Failed to attach permissions policy"
        exit 1
    fi
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    log_info "Role ARN: ${ROLE_ARN}"
    
    # Clean up temporary files
    rm -f /tmp/flink-trust-policy.json /tmp/flink-permissions-policy.json
}

# Function to create Flink application structure
create_flink_application() {
    log_info "Creating Flink application structure..."
    
    # Create application directory
    mkdir -p flink-analytics-app/src/main/java/com/example
    
    # Create POM file
    cat > flink-analytics-app/pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>com.example</groupId>
    <artifactId>flink-analytics-app</artifactId>
    <version>1.0</version>
    <packaging>jar</packaging>
    
    <properties>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <flink.version>1.18.0</flink.version>
        <kda.version>2.0</kda.version>
    </properties>
    
    <dependencies>
        <dependency>
            <groupId>com.amazonaws</groupId>
            <artifactId>aws-kinesisanalytics-runtime</artifactId>
            <version>${kda.version}</version>
        </dependency>
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-streaming-java</artifactId>
            <version>${flink.version}</version>
        </dependency>
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-connector-kinesis</artifactId>
            <version>4.2.0-1.18</version>
        </dependency>
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-connector-files</artifactId>
            <version>${flink.version}</version>
        </dependency>
        <dependency>
            <groupId>org.apache.flink</groupId>
            <artifactId>flink-json</artifactId>
            <version>${flink.version}</version>
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
    
    # Create Java application class
    cat > flink-analytics-app/src/main/java/com/example/StreamingAnalyticsJob.java << 'EOF'
package com.example;

import com.amazonaws.services.kinesisanalytics.runtime.KinesisAnalyticsRuntime;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.connector.file.sink.FileSink;
import org.apache.flink.core.fs.Path;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.streaming.connectors.kinesis.FlinkKinesisConsumer;
import org.apache.flink.streaming.connectors.kinesis.config.ConsumerConfigConstants;

import java.util.Map;
import java.util.Properties;

public class StreamingAnalyticsJob {
    
    public static void main(String[] args) throws Exception {
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        
        // Get application properties from Kinesis Analytics runtime
        Map<String, Properties> applicationProperties = KinesisAnalyticsRuntime.getApplicationProperties();
        Properties inputProperties = applicationProperties.get("kinesis.analytics.flink.run.options");
        
        String inputStreamName = inputProperties.getProperty("input.stream.name");
        String region = inputProperties.getProperty("aws.region");
        String s3Path = inputProperties.getProperty("s3.path");
        
        // Configure Kinesis consumer with appropriate settings
        Properties kinesisConsumerConfig = new Properties();
        kinesisConsumerConfig.setProperty(ConsumerConfigConstants.AWS_REGION, region);
        kinesisConsumerConfig.setProperty(ConsumerConfigConstants.STREAM_INITIAL_POSITION, "LATEST");
        
        // Create Kinesis source for reading streaming data
        FlinkKinesisConsumer<String> kinesisSource = new FlinkKinesisConsumer<>(
            inputStreamName,
            new SimpleStringSchema(),
            kinesisConsumerConfig
        );
        
        DataStream<String> inputStream = env.addSource(kinesisSource);
        
        // Process stream: count events per minute using tumbling windows
        DataStream<Tuple2<String, Integer>> analytics = inputStream
            .map(value -> new Tuple2<>("event_count", 1))
            .returns(Types.TUPLE(Types.STRING, Types.INT))
            .keyBy(value -> value.f0)
            .window(TumblingProcessingTimeWindows.of(Time.minutes(1)))
            .sum(1);
        
        // Write aggregated results to S3 for QuickSight consumption
        analytics
            .map(tuple -> String.format("{\"timestamp\":\"%d\",\"metric\":\"%s\",\"value\":%d}", 
                System.currentTimeMillis(), tuple.f0, tuple.f1))
            .sinkTo(FileSink.forRowFormat(new Path(s3Path), new SimpleStringSchema())
                .withRollingPolicy(
                    org.apache.flink.connector.file.sink.compaction.FileCompactStrategy
                        .Builder.newBuilder()
                        .enableCompactionOnCheckpoint(5)
                        .build())
                .build());
        
        env.execute("Real-time Analytics Job");
    }
}
EOF
    
    log_success "Created Flink application structure"
}

# Function to build and upload Flink application
build_flink_application() {
    log_info "Building Flink application..."
    
    # Check if Maven is installed
    if ! command_exists mvn; then
        log_warning "Maven not found, attempting to install..."
        if command_exists yum; then
            sudo yum install -y maven
        elif command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y maven
        elif command_exists brew; then
            brew install maven
        else
            log_error "Cannot install Maven automatically. Please install Maven manually."
            exit 1
        fi
    fi
    
    # Build the application
    cd flink-analytics-app
    if mvn clean package -q; then
        log_success "Built Flink application successfully"
    else
        log_error "Failed to build Flink application"
        exit 1
    fi
    
    # Upload JAR to S3
    if aws s3 cp target/flink-analytics-app-1.0.jar \
        "s3://${FLINK_CODE_BUCKET}/flink-analytics-app-1.0.jar"; then
        log_success "Uploaded Flink application to S3"
    else
        log_error "Failed to upload Flink application to S3"
        exit 1
    fi
    
    cd ..
}

# Function to create and start Flink application
deploy_flink_application() {
    log_info "Creating Managed Service for Apache Flink application..."
    
    # Create application configuration
    cat > /tmp/flink-app-config.json << EOF
{
    "ApplicationName": "${FLINK_APP_NAME}",
    "ApplicationDescription": "Real-time analytics application",
    "RuntimeEnvironment": "FLINK-1_18",
    "ServiceExecutionRole": "${ROLE_ARN}",
    "ApplicationConfiguration": {
        "ApplicationCodeConfiguration": {
            "CodeContent": {
                "S3ContentLocation": {
                    "BucketARN": "arn:aws:s3:::${FLINK_CODE_BUCKET}",
                    "FileKey": "flink-analytics-app-1.0.jar"
                }
            },
            "CodeContentType": "ZIPFILE"
        },
        "EnvironmentProperties": {
            "PropertyGroups": [
                {
                    "PropertyGroupId": "kinesis.analytics.flink.run.options",
                    "PropertyMap": {
                        "input.stream.name": "${STREAM_NAME}",
                        "aws.region": "${AWS_REGION}",
                        "s3.path": "s3://${S3_BUCKET_NAME}/analytics-results/"
                    }
                }
            ]
        },
        "FlinkApplicationConfiguration": {
            "CheckpointConfiguration": {
                "ConfigurationType": "DEFAULT"
            },
            "MonitoringConfiguration": {
                "ConfigurationType": "DEFAULT",
                "LogLevel": "INFO",
                "MetricsLevel": "APPLICATION"
            },
            "ParallelismConfiguration": {
                "ConfigurationType": "DEFAULT",
                "Parallelism": 1,
                "ParallelismPerKPU": 1,
                "AutoScalingEnabled": true
            }
        }
    }
}
EOF
    
    # Create Flink application
    if aws kinesisanalyticsv2 create-application \
        --cli-input-json file:///tmp/flink-app-config.json >/dev/null 2>&1; then
        log_success "Created Flink application: ${FLINK_APP_NAME}"
    else
        log_error "Failed to create Flink application"
        exit 1
    fi
    
    # Start the application
    log_info "Starting Flink application..."
    if aws kinesisanalyticsv2 start-application \
        --application-name "${FLINK_APP_NAME}" \
        --run-configuration '{
            "FlinkRunConfiguration": {
                "AllowNonRestoredState": true
            }
        }' >/dev/null 2>&1; then
        log_success "Started Flink application"
    else
        log_error "Failed to start Flink application"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f /tmp/flink-app-config.json
}

# Function to create sample data generator
create_data_generator() {
    log_info "Creating sample data generator..."
    
    cat > generate_sample_data.py << 'EOF'
import json
import time
import random
import boto3
import os
from datetime import datetime

def generate_sample_events():
    kinesis = boto3.client('kinesis')
    stream_name = os.environ['STREAM_NAME']
    
    event_types = ['page_view', 'button_click', 'form_submit', 'purchase']
    
    for i in range(100):
        event = {
            'timestamp': datetime.now().isoformat(),
            'event_type': random.choice(event_types),
            'user_id': f'user_{random.randint(1, 1000)}',
            'value': random.randint(1, 100)
        }
        
        kinesis.put_record(
            StreamName=stream_name,
            Data=json.dumps(event),
            PartitionKey=event['user_id']
        )
        
        if i % 10 == 0:
            print(f"Sent {i+1} events")
        
        time.sleep(0.1)

if __name__ == '__main__':
    generate_sample_events()
EOF
    
    log_success "Created sample data generator"
}

# Function to create QuickSight manifest
create_quicksight_manifest() {
    log_info "Creating QuickSight manifest..."
    
    cat > /tmp/quicksight-manifest.json << EOF
{
    "fileLocations": [
        {
            "URIPrefixes": [
                "s3://${S3_BUCKET_NAME}/analytics-results/"
            ]
        }
    ],
    "globalUploadSettings": {
        "format": "JSON"
    }
}
EOF
    
    # Upload manifest to S3
    if aws s3 cp /tmp/quicksight-manifest.json \
        "s3://${S3_BUCKET_NAME}/quicksight-manifest.json"; then
        log_success "Created and uploaded QuickSight manifest"
    else
        log_error "Failed to upload QuickSight manifest"
        exit 1
    fi
    
    rm -f /tmp/quicksight-manifest.json
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > deployment-state.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "random_suffix": "${RANDOM_SUFFIX}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources": {
        "kinesis_stream": "${STREAM_NAME}",
        "flink_application": "${FLINK_APP_NAME}",
        "s3_bucket_results": "${S3_BUCKET_NAME}",
        "s3_bucket_code": "${FLINK_CODE_BUCKET}",
        "iam_role": "${IAM_ROLE_NAME}",
        "stream_arn": "${STREAM_ARN}",
        "role_arn": "${ROLE_ARN}"
    }
}
EOF
    
    log_success "Deployment state saved to deployment-state.json"
}

# Function to run deployment
run_deployment() {
    log_info "Starting deployment of Real-time Analytics Dashboard..."
    
    validate_prerequisites
    setup_environment
    generate_resource_names
    create_s3_buckets
    create_kinesis_stream
    create_iam_role
    
    # Wait for IAM role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    create_flink_application
    build_flink_application
    deploy_flink_application
    
    # Wait for Flink application to start
    log_info "Waiting for Flink application to initialize..."
    sleep 30
    
    create_data_generator
    create_quicksight_manifest
    save_deployment_state
    
    log_success "Deployment completed successfully!"
    echo
    log_info "Next steps:"
    echo "1. Generate sample data: STREAM_NAME=${STREAM_NAME} python3 generate_sample_data.py"
    echo "2. Set up QuickSight dashboard using manifest: s3://${S3_BUCKET_NAME}/quicksight-manifest.json"
    echo "3. Monitor Flink application logs in CloudWatch"
    echo "4. Clean up resources using: ./destroy.sh"
}

# Main execution
main() {
    echo "=========================================="
    echo "Real-time Analytics Dashboard Deployment"
    echo "=========================================="
    echo
    
    if [ "$#" -eq 1 ] && [ "$1" = "--dry-run" ]; then
        log_info "Dry run mode - validation only"
        validate_prerequisites
        setup_environment
        generate_resource_names
        log_success "Dry run completed - no resources created"
        exit 0
    fi
    
    # Confirm deployment
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
    
    run_deployment
}

# Script entry point
main "$@"