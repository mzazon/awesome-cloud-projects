#!/bin/bash

# Quality Gates CodeBuild Deployment Script
# This script deploys the complete CodeBuild quality gates infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RECIPE_NAME="code-quality-gates-codebuild"
DEPLOYMENT_TIMEOUT=3600  # 1 hour timeout

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
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Clean up any created resources
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Cleaning up S3 bucket: ${BUCKET_NAME}"
        aws s3 rm s3://${BUCKET_NAME} --recursive --quiet 2>/dev/null || true
        aws s3 rb s3://${BUCKET_NAME} --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        log "Cleaning up SNS topic: ${SNS_TOPIC_ARN}"
        aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN} --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        log "Cleaning up CodeBuild project: ${PROJECT_NAME}"
        aws codebuild delete-project --name ${PROJECT_NAME} --quiet 2>/dev/null || true
        
        log "Cleaning up IAM role: ${PROJECT_NAME}-service-role"
        aws iam detach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess --quiet 2>/dev/null || true
        aws iam detach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --quiet 2>/dev/null || true
        aws iam detach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy --quiet 2>/dev/null || true
        aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy --quiet 2>/dev/null || true
        aws iam delete-role --role-name ${PROJECT_NAME}-service-role --quiet 2>/dev/null || true
    fi
    
    log "Cleaning up Systems Manager parameters..."
    aws ssm delete-parameters --names "/quality-gates/coverage-threshold" "/quality-gates/sonar-quality-gate" "/quality-gates/security-threshold" --quiet 2>/dev/null || true
    
    log "Cleaning up temporary files..."
    rm -f trust-policy.json quality-gate-policy.json codebuild-project.json quality-dashboard.json 2>/dev/null || true
    
    log_warning "Cleanup completed. Some resources may require manual removal."
}

# Set up error trap
trap cleanup_on_error ERR

# Display banner
echo -e "${BLUE}"
echo "========================================"
echo "  CodeBuild Quality Gates Deployment   "
echo "========================================"
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install it first."
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS CLI is not configured. Please run 'aws configure' first."
fi

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed. Some features may not work properly."
    log_warning "Install jq for better JSON parsing: https://stedolan.github.io/jq/download/"
fi

# Get AWS account information
log "Getting AWS account information..."
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    log_warning "No default region configured. Using us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log "AWS Account ID: ${AWS_ACCOUNT_ID}"
log "AWS Region: ${AWS_REGION}"

# Generate unique identifiers
log "Generating unique identifiers..."
if command -v aws &> /dev/null && aws secretsmanager get-random-password --exclude-punctuation --exclude-uppercase --password-length 6 --require-each-included-type --output text --query RandomPassword &> /dev/null; then
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password --exclude-punctuation --exclude-uppercase --password-length 6 --require-each-included-type --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
else
    RANDOM_SUFFIX=$(date +%s | tail -c 6)
fi

export PROJECT_NAME="quality-gates-demo-${RANDOM_SUFFIX}"
export BUCKET_NAME="codebuild-quality-gates-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
export SNS_TOPIC_NAME="quality-gate-notifications-${RANDOM_SUFFIX}"

log "Project Name: ${PROJECT_NAME}"
log "S3 Bucket: ${BUCKET_NAME}"
log "SNS Topic: ${SNS_TOPIC_NAME}"

# Validate prerequisites
log "Validating AWS permissions..."

# Check S3 permissions
if ! aws s3 ls >/dev/null 2>&1; then
    error_exit "Insufficient S3 permissions. Please ensure you have S3 access."
fi

# Check CodeBuild permissions
if ! aws codebuild list-projects >/dev/null 2>&1; then
    error_exit "Insufficient CodeBuild permissions. Please ensure you have CodeBuild access."
fi

# Check SNS permissions
if ! aws sns list-topics >/dev/null 2>&1; then
    error_exit "Insufficient SNS permissions. Please ensure you have SNS access."
fi

# Check IAM permissions
if ! aws iam list-roles >/dev/null 2>&1; then
    error_exit "Insufficient IAM permissions. Please ensure you have IAM access."
fi

# Check Systems Manager permissions
if ! aws ssm describe-parameters >/dev/null 2>&1; then
    error_exit "Insufficient Systems Manager permissions. Please ensure you have SSM access."
fi

log_success "Prerequisites validation completed"

# Create S3 bucket for build artifacts
log "Creating S3 bucket for build artifacts..."
if aws s3 ls s3://${BUCKET_NAME} 2>/dev/null; then
    log_warning "S3 bucket ${BUCKET_NAME} already exists"
else
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    log_success "Created S3 bucket: ${BUCKET_NAME}"
fi

# Enable versioning on the bucket
log "Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled
log_success "Enabled versioning on S3 bucket"

# Create SNS topic for notifications
log "Creating SNS topic for quality gate notifications..."
SNS_TOPIC_ARN=$(aws sns create-topic --name ${SNS_TOPIC_NAME} --query TopicArn --output text)
export SNS_TOPIC_ARN
log_success "Created SNS topic: ${SNS_TOPIC_ARN}"

# Optionally subscribe email (prompt user)
read -p "Enter email address for quality gate notifications (or press Enter to skip): " EMAIL_ADDRESS
if [[ -n "$EMAIL_ADDRESS" ]]; then
    log "Subscribing email to SNS topic..."
    aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint ${EMAIL_ADDRESS}
    log_success "Subscribed ${EMAIL_ADDRESS} to quality gate notifications"
    log_warning "Please check your email and confirm the subscription"
fi

# Store quality gate configuration in Systems Manager
log "Storing quality gate configuration in Systems Manager..."
aws ssm put-parameter --name "/quality-gates/coverage-threshold" --value "80" --type "String" --description "Minimum code coverage percentage" --overwrite
aws ssm put-parameter --name "/quality-gates/sonar-quality-gate" --value "ERROR" --type "String" --description "SonarQube quality gate status threshold" --overwrite
aws ssm put-parameter --name "/quality-gates/security-threshold" --value "HIGH" --type "String" --description "Maximum security vulnerability level" --overwrite
log_success "Stored quality gate parameters in Systems Manager"

# Create IAM service role for CodeBuild
log "Creating IAM service role for CodeBuild..."

# Create trust policy
cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codebuild.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create IAM role
if aws iam get-role --role-name ${PROJECT_NAME}-service-role >/dev/null 2>&1; then
    log_warning "IAM role ${PROJECT_NAME}-service-role already exists"
else
    aws iam create-role --role-name ${PROJECT_NAME}-service-role --assume-role-policy-document file://trust-policy.json
    log_success "Created IAM role: ${PROJECT_NAME}-service-role"
fi

# Wait for role to be available
log "Waiting for IAM role to be available..."
sleep 10

# Attach managed policies
log "Attaching managed policies to IAM role..."
aws iam attach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
aws iam attach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create custom policy for additional permissions
cat > quality-gate-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameter",
                "ssm:GetParameters",
                "sns:Publish",
                "codebuild:BatchGetBuilds"
            ],
            "Resource": "*"
        }
    ]
}
EOF

# Create and attach custom policy
if aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy >/dev/null 2>&1; then
    log_warning "Custom policy already exists"
else
    aws iam create-policy --policy-name ${PROJECT_NAME}-quality-gate-policy --policy-document file://quality-gate-policy.json
    log_success "Created custom IAM policy"
fi

aws iam attach-role-policy --role-name ${PROJECT_NAME}-service-role --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-quality-gate-policy
log_success "Attached custom policy to IAM role"

# Create buildspec.yml
log "Creating buildspec.yml for quality gates..."
cat > buildspec.yml << 'EOF'
version: 0.2

env:
  parameter-store:
    COVERAGE_THRESHOLD: /quality-gates/coverage-threshold
    SONAR_QUALITY_GATE: /quality-gates/sonar-quality-gate
    SECURITY_THRESHOLD: /quality-gates/security-threshold
  variables:
    MAVEN_OPTS: "-Dmaven.repo.local=.m2/repository"

phases:
  install:
    runtime-versions:
      java: corretto21
    commands:
      - echo "Installing dependencies and tools..."
      - apt-get update && apt-get install -y curl unzip
      - curl -sSL https://github.com/SonarSource/sonar-scanner-cli/releases/download/4.8.0.2856/sonar-scanner-cli-4.8.0.2856-linux.zip -o sonar-scanner.zip
      - unzip sonar-scanner.zip
      - export PATH=$PATH:$(pwd)/sonar-scanner-4.8.0.2856-linux/bin
      - curl -sSL https://github.com/jeremylong/DependencyCheck/releases/download/v8.4.0/dependency-check-8.4.0-release.zip -o dependency-check.zip
      - unzip dependency-check.zip
      - chmod +x dependency-check/bin/dependency-check.sh

  pre_build:
    commands:
      - echo "Validating build environment..."
      - java -version
      - mvn -version
      - echo "Build started on $(date)"

  build:
    commands:
      - echo "=== PHASE 1: Compile and Unit Tests ==="
      - mvn clean compile test
      - echo "✅ Unit tests completed"
      
      - echo "=== PHASE 2: Code Coverage Analysis ==="
      - mvn jacoco:report
      - COVERAGE=$(grep -o 'Total[^%]*%' target/site/jacoco/index.html | grep -o '[0-9]*' | head -1)
      - echo "Code coverage: ${COVERAGE}%"
      - |
        if [ "${COVERAGE:-0}" -lt "${COVERAGE_THRESHOLD}" ]; then
          echo "❌ QUALITY GATE FAILED: Coverage ${COVERAGE}% below threshold ${COVERAGE_THRESHOLD}%"
          aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message "Quality Gate Failed: Coverage ${COVERAGE}% below threshold ${COVERAGE_THRESHOLD}%" --subject "Quality Gate Failure"
          exit 1
        fi
      - echo "✅ Code coverage check passed"
      
      - echo "=== PHASE 3: Static Code Analysis ==="
      - mvn sonar:sonar -Dsonar.projectKey=quality-gates-demo -Dsonar.host.url=https://sonarcloud.io -Dsonar.token=${SONAR_TOKEN}
      - echo "✅ SonarQube analysis completed"
      
      - echo "=== PHASE 4: Security Scanning ==="
      - ./dependency-check/bin/dependency-check.sh --project "Quality Gates Demo" --scan . --format JSON --out ./security-report.json
      - |
        HIGH_VULNS=$(jq '.dependencies[].vulnerabilities[]? | select(.severity == "HIGH") | length' security-report.json 2>/dev/null | wc -l)
        if [ "${HIGH_VULNS}" -gt 0 ]; then
          echo "❌ QUALITY GATE FAILED: Found ${HIGH_VULNS} HIGH severity vulnerabilities"
          aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message "Quality Gate Failed: ${HIGH_VULNS} HIGH severity vulnerabilities found" --subject "Security Gate Failure"
          exit 1
        fi
      - echo "✅ Security scan passed"
      
      - echo "=== PHASE 5: Integration Tests ==="
      - mvn verify
      - echo "✅ Integration tests completed"
      
      - echo "=== PHASE 6: Quality Gate Summary ==="
      - echo "All quality gates passed successfully!"
      - aws sns publish --topic-arn ${SNS_TOPIC_ARN} --message "Quality Gate Success: All checks passed for build ${CODEBUILD_BUILD_ID}" --subject "Quality Gate Success"

  post_build:
    commands:
      - echo "=== Generating Quality Reports ==="
      - mkdir -p quality-reports
      - cp -r target/site/jacoco quality-reports/coverage-report
      - cp security-report.json quality-reports/
      - echo "Build completed on $(date)"

artifacts:
  files:
    - target/*.jar
    - quality-reports/**/*
  name: quality-gates-artifacts

reports:
  jacoco-reports:
    files:
      - target/site/jacoco/jacoco.xml
    file-format: JACOCOXML
  junit-reports:
    files:
      - target/surefire-reports/*.xml
    file-format: JUNITXML

cache:
  paths:
    - .m2/repository/**/*
EOF

# Create sample Java application
log "Creating sample Java application..."
mkdir -p src/main/java/com/example/qualitygates
mkdir -p src/test/java/com/example/qualitygates

# Create pom.xml
cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 
                           http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <groupId>com.example</groupId>
    <artifactId>quality-gates-demo</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>
    
    <name>Quality Gates Demo</name>
    <description>Demo project for implementing quality gates</description>
    
    <properties>
        <maven.compiler.source>21</maven.compiler.source>
        <maven.compiler.target>21</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <sonar.organization>your-sonar-org</sonar.organization>
        <sonar.host.url>https://sonarcloud.io</sonar.host.url>
        <sonar.coverage.jacoco.xmlReportPaths>target/site/jacoco/jacoco.xml</sonar.coverage.jacoco.xmlReportPaths>
    </properties>
    
    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.9.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
    
    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.0.0-M9</version>
            </plugin>
            
            <plugin>
                <groupId>org.jacoco</groupId>
                <artifactId>jacoco-maven-plugin</artifactId>
                <version>0.8.8</version>
                <executions>
                    <execution>
                        <goals>
                            <goal>prepare-agent</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>report</id>
                        <phase>test</phase>
                        <goals>
                            <goal>report</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
            
            <plugin>
                <groupId>org.sonarsource.scanner.maven</groupId>
                <artifactId>sonar-maven-plugin</artifactId>
                <version>3.9.1.2184</version>
            </plugin>
        </plugins>
    </build>
</project>
EOF

# Create Java source files
cat > src/main/java/com/example/qualitygates/Calculator.java << 'EOF'
package com.example.qualitygates;

/**
 * A simple calculator class to demonstrate quality gates
 */
public class Calculator {
    
    /**
     * Adds two numbers
     * @param a first number
     * @param b second number
     * @return sum of a and b
     */
    public int add(int a, int b) {
        return a + b;
    }
    
    /**
     * Subtracts two numbers
     * @param a first number
     * @param b second number
     * @return difference of a and b
     */
    public int subtract(int a, int b) {
        return a - b;
    }
    
    /**
     * Multiplies two numbers
     * @param a first number
     * @param b second number
     * @return product of a and b
     */
    public int multiply(int a, int b) {
        return a * b;
    }
    
    /**
     * Divides two numbers
     * @param a dividend
     * @param b divisor
     * @return quotient
     * @throws IllegalArgumentException if divisor is zero
     */
    public double divide(int a, int b) {
        if (b == 0) {
            throw new IllegalArgumentException("Division by zero");
        }
        return (double) a / b;
    }
}
EOF

# Create test files
cat > src/test/java/com/example/qualitygates/CalculatorTest.java << 'EOF'
package com.example.qualitygates;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Test class for Calculator to achieve high code coverage
 */
public class CalculatorTest {
    
    private Calculator calculator;
    
    @BeforeEach
    void setUp() {
        calculator = new Calculator();
    }
    
    @Test
    void testAdd() {
        assertEquals(5, calculator.add(2, 3));
        assertEquals(0, calculator.add(-1, 1));
        assertEquals(-5, calculator.add(-2, -3));
    }
    
    @Test
    void testSubtract() {
        assertEquals(1, calculator.subtract(3, 2));
        assertEquals(-2, calculator.subtract(-1, 1));
        assertEquals(1, calculator.subtract(-2, -3));
    }
    
    @Test
    void testMultiply() {
        assertEquals(6, calculator.multiply(2, 3));
        assertEquals(0, calculator.multiply(0, 5));
        assertEquals(6, calculator.multiply(-2, -3));
    }
    
    @Test
    void testDivide() {
        assertEquals(2.0, calculator.divide(6, 3));
        assertEquals(-2.0, calculator.divide(-6, 3));
        assertEquals(0.5, calculator.divide(1, 2));
    }
    
    @Test
    void testDivideByZero() {
        assertThrows(IllegalArgumentException.class, () -> {
            calculator.divide(5, 0);
        });
    }
}
EOF

log_success "Created sample Java application with comprehensive tests"

# Upload source code to S3
log "Uploading source code to S3..."
zip -r source-code.zip . -x "*.git*" "target/*" "*.log"
aws s3 cp source-code.zip s3://${BUCKET_NAME}/source/
log_success "Uploaded source code to S3"

# Create CodeBuild project
log "Creating CodeBuild project..."
cat > codebuild-project.json << EOF
{
    "name": "${PROJECT_NAME}",
    "description": "Quality Gates Demo with CodeBuild",
    "source": {
        "type": "S3",
        "location": "${BUCKET_NAME}/source/source-code.zip"
    },
    "artifacts": {
        "type": "S3",
        "location": "${BUCKET_NAME}/artifacts"
    },
    "environment": {
        "type": "LINUX_CONTAINER",
        "image": "aws/codebuild/amazonlinux2-x86_64-standard:4.0",
        "computeType": "BUILD_GENERAL1_MEDIUM",
        "environmentVariables": [
            {
                "name": "SNS_TOPIC_ARN",
                "value": "${SNS_TOPIC_ARN}"
            }
        ]
    },
    "serviceRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-service-role",
    "timeoutInMinutes": 60,
    "queuedTimeoutInMinutes": 480,
    "cache": {
        "type": "S3",
        "location": "${BUCKET_NAME}/cache"
    }
}
EOF

if aws codebuild describe-projects --names ${PROJECT_NAME} >/dev/null 2>&1; then
    log_warning "CodeBuild project ${PROJECT_NAME} already exists"
else
    aws codebuild create-project --cli-input-json file://codebuild-project.json
    log_success "Created CodeBuild project: ${PROJECT_NAME}"
fi

# Create CloudWatch dashboard
log "Creating CloudWatch dashboard for quality gate monitoring..."
cat > quality-dashboard.json << EOF
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
                    [ "AWS/CodeBuild", "Builds", "ProjectName", "${PROJECT_NAME}" ],
                    [ ".", "Duration", ".", "." ],
                    [ ".", "FailedBuilds", ".", "." ],
                    [ ".", "SucceededBuilds", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "CodeBuild Quality Gate Metrics"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/codebuild/${PROJECT_NAME}' | fields @timestamp, @message\n| filter @message like /QUALITY GATE/\n| sort @timestamp desc\n| limit 20",
                "region": "${AWS_REGION}",
                "title": "Quality Gate Events"
            }
        }
    ]
}
EOF

aws cloudwatch put-dashboard --dashboard-name "Quality-Gates-${PROJECT_NAME}" --dashboard-body file://quality-dashboard.json
log_success "Created CloudWatch dashboard for quality gate monitoring"

# Test deployment by starting a build
log "Starting initial build to test quality gates..."
BUILD_ID=$(aws codebuild start-build --project-name ${PROJECT_NAME} --query 'build.id' --output text)
log "Started build: ${BUILD_ID}"

# Monitor build for a few minutes
log "Monitoring build progress (timeout: 5 minutes)..."
TIMEOUT=300  # 5 minutes
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    BUILD_STATUS=$(aws codebuild batch-get-builds --ids ${BUILD_ID} --query 'builds[0].buildStatus' --output text)
    
    if [ "$BUILD_STATUS" = "SUCCEEDED" ]; then
        log_success "Build completed successfully - All quality gates passed!"
        break
    elif [ "$BUILD_STATUS" = "FAILED" ]; then
        log_error "Build failed - Quality gates not met"
        log "Check CloudWatch logs for details: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/%2Faws%2Fcodebuild%2F${PROJECT_NAME}"
        break
    elif [ "$BUILD_STATUS" = "IN_PROGRESS" ]; then
        log "Build in progress... (${ELAPSED}s elapsed)"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    else
        log "Build status: $BUILD_STATUS"
        sleep 30
        ELAPSED=$((ELAPSED + 30))
    fi
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_warning "Build monitoring timed out after 5 minutes"
    log "Build may still be running. Check the AWS console for details."
fi

# Clean up temporary files
log "Cleaning up temporary files..."
rm -f trust-policy.json quality-gate-policy.json codebuild-project.json quality-dashboard.json
rm -f buildspec.yml pom.xml source-code.zip
rm -rf src target .m2 2>/dev/null || true

# Display deployment summary
echo -e "${GREEN}"
echo "========================================"
echo "     Deployment Summary"
echo "========================================"
echo -e "${NC}"
echo "✅ S3 Bucket: ${BUCKET_NAME}"
echo "✅ SNS Topic: ${SNS_TOPIC_ARN}"
echo "✅ CodeBuild Project: ${PROJECT_NAME}"
echo "✅ IAM Role: ${PROJECT_NAME}-service-role"
echo "✅ CloudWatch Dashboard: Quality-Gates-${PROJECT_NAME}"
echo "✅ Systems Manager Parameters: /quality-gates/*"
echo ""
echo "🔗 Console Links:"
echo "   CodeBuild: https://console.aws.amazon.com/codesuite/codebuild/projects/${PROJECT_NAME}/history"
echo "   CloudWatch: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=Quality-Gates-${PROJECT_NAME}"
echo "   S3 Bucket: https://s3.console.aws.amazon.com/s3/buckets/${BUCKET_NAME}"
echo ""
echo "📝 Next Steps:"
echo "   1. Configure SonarQube token in CodeBuild environment variables"
echo "   2. Start builds using: aws codebuild start-build --project-name ${PROJECT_NAME}"
echo "   3. Monitor quality gates in CloudWatch dashboard"
echo "   4. Customize quality thresholds in Systems Manager parameters"
echo ""
echo "🧹 Cleanup:"
echo "   Run ./scripts/destroy.sh to remove all resources"

log_success "Quality Gates CodeBuild deployment completed successfully!"

# Save deployment info for cleanup script
cat > deployment-info.env << EOF
# Quality Gates CodeBuild Deployment Information
# Generated on $(date)
export PROJECT_NAME="${PROJECT_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export DASHBOARD_NAME="Quality-Gates-${PROJECT_NAME}"
export BUILD_ID="${BUILD_ID}"
EOF

log_success "Deployment information saved to deployment-info.env"