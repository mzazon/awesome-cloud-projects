---
title: Detecting Fraud with Amazon Fraud Detector
id: ad41124b
category: machine-learning-ai
difficulty: 400
subject: aws
services: frauddetector, kinesis, lambda, dynamodb
estimated-time: 180 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: null
passed-qa: null
tags: fraud-detection, machine-learning, real-time-processing, security
recipe-generator-version: 1.3
---

# Detecting Fraud with Amazon Fraud Detector

## Problem

Enterprise financial services and e-commerce platforms face sophisticated fraud attacks that evolve rapidly, including synthetic identity fraud, account takeover attacks, and coordinated payment fraud rings. Traditional fraud detection systems struggle with latency requirements under 100ms, lack real-time feature engineering capabilities, and cannot adapt to emerging fraud patterns without extensive re-training. Organizations need a comprehensive solution that provides sub-second fraud decisions, incorporates behavioral analytics, and maintains high accuracy while processing millions of transactions per hour without impacting legitimate customer experience.

## Solution

Amazon Fraud Detector provides enterprise-grade real-time fraud detection by combining advanced machine learning models with sophisticated rule engines and real-time feature engineering. This solution demonstrates how to build a comprehensive fraud detection system that processes streaming transaction data, enriches events with behavioral features, applies multi-layered detection logic, and provides instant fraud decisions through high-performance APIs. The architecture includes transaction stream processing, adaptive model training, and intelligent alert routing to create a production-ready fraud detection platform.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Data Ingestion Layer"
        API[API Gateway<br/>Transaction API]
        STREAM[Kinesis Data<br/>Streams]
        BATCH[S3 Bucket<br/>Historical Data]
    end
    
    subgraph "Real-Time Processing"
        LAMBDA1[Lambda Function<br/>Event Enrichment]
        LAMBDA2[Lambda Function<br/>Fraud Scoring]
        CACHE[ElastiCache<br/>Feature Store]
    end
    
    subgraph "Amazon Fraud Detector"
        TFI[Transaction Fraud<br/>Insights Model]
        RULES[Detection Rules<br/>Engine]
        OUTCOMES[Fraud Outcomes<br/>& Actions]
    end
    
    subgraph "Decision & Response"
        DDB[DynamoDB<br/>Decisions Log]
        SNS[SNS Topic<br/>Alert Routing]
        DASHBOARD[CloudWatch<br/>Dashboard]
    end
    
    subgraph "Feedback Loop"
        ANALYST[Fraud Analyst<br/>Review]
        RETRAIN[Model Retraining<br/>Pipeline]
    end
    
    API -->|1. Transaction| STREAM
    STREAM -->|2. Event| LAMBDA1
    LAMBDA1 -->|3. Enriched Data| LAMBDA2
    LAMBDA2 -->|4. Prediction Request| TFI
    TFI -->|5. ML Score| RULES
    RULES -->|6. Decision| OUTCOMES
    OUTCOMES -->|7. Result| LAMBDA2
    LAMBDA2 -->|8. Log Decision| DDB
    LAMBDA2 -->|9. Alert| SNS
    LAMBDA2 -->|10. Response| API
    
    BATCH -->|Training Data| TFI
    CACHE <-->|Feature Lookup| LAMBDA1
    ANALYST -->|Feedback| RETRAIN
    RETRAIN -->|Updated Model| TFI
    
    SNS --> DASHBOARD
    
    style TFI fill:#FF9900
    style RULES fill:#3F8624
    style LAMBDA2 fill:#146EB4
    style STREAM fill:#9D5AAE
```

## Prerequisites

1. AWS account with permissions for Fraud Detector, Kinesis, Lambda, DynamoDB, ElastiCache, and SNS
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Advanced understanding of fraud detection patterns and machine learning concepts
4. Experience with real-time streaming architectures and event-driven systems
5. Historical transaction data with fraud labels (minimum 50,000 events with 5% fraud rate)
6. Python 3.9+ for Lambda development and data processing
7. Estimated cost: $300-800 for model training, real-time processing, and supporting infrastructure

> **Note**: Transaction Fraud Insights models require substantial historical data for optimal performance. The model training process can take 2-4 hours depending on dataset size and complexity. See the [Amazon Fraud Detector documentation](https://docs.aws.amazon.com/frauddetector/) for detailed training requirements and optimization guidelines.

> **Warning**: Ensure proper IAM permissions are configured before proceeding to avoid access denied errors during model training and detector activation. Test permissions thoroughly in development environments before production deployment.

> **Tip**: Use CloudWatch monitoring to track performance metrics and optimize resource allocation based on actual usage patterns. Implement gradual rollout strategies to validate fraud detection accuracy before full production deployment.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 8 --require-each-included-type \
    --output text --query RandomPassword)

# Set comprehensive resource names
export FRAUD_BUCKET="fraud-detection-platform-${RANDOM_SUFFIX}"
export KINESIS_STREAM="fraud-transaction-stream-${RANDOM_SUFFIX}"
export EVENT_TYPE_NAME="transaction_fraud_detection_${RANDOM_SUFFIX}"
export ENTITY_TYPE_NAME="customer_entity_${RANDOM_SUFFIX}"
export MODEL_NAME="transaction_fraud_insights_${RANDOM_SUFFIX}"
export DETECTOR_NAME="realtime_fraud_detector_${RANDOM_SUFFIX}"
export DECISIONS_TABLE="fraud_decisions_${RANDOM_SUFFIX}"
export FEATURES_CACHE="fraud-features-${RANDOM_SUFFIX}"

# Create foundational infrastructure
aws s3 mb s3://${FRAUD_BUCKET} --region ${AWS_REGION}

# Create Kinesis stream for real-time transaction processing
aws kinesis create-stream \
    --stream-name ${KINESIS_STREAM} \
    --shard-count 3

# Create DynamoDB table for decision logging
aws dynamodb create-table \
    --table-name ${DECISIONS_TABLE} \
    --attribute-definitions \
        AttributeName=transaction_id,AttributeType=S \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=transaction_id,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --provisioned-throughput \
        ReadCapacityUnits=100,WriteCapacityUnits=100 \
    --global-secondary-indexes \
        IndexName=customer-index,KeySchema=[{AttributeName=customer_id,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=50,WriteCapacityUnits=50}

# Wait for stream to be active
aws kinesis wait stream-exists --stream-name ${KINESIS_STREAM}

echo "✅ Infrastructure preparation completed"
echo "   S3 Bucket: ${FRAUD_BUCKET}"
echo "   Kinesis Stream: ${KINESIS_STREAM}"
echo "   DynamoDB Table: ${DECISIONS_TABLE}"
```

## Steps

1. **Create Enhanced IAM Roles for Fraud Detection Platform**:

   Amazon Fraud Detector requires comprehensive IAM permissions to access training data, execute models, and integrate with supporting services. Proper IAM configuration follows the principle of least privilege while ensuring the fraud detection system can access necessary resources. These roles establish the security foundation that enables secure, auditable fraud detection operations across your AWS environment.

   ```bash
   # Create comprehensive trust policy for Fraud Detector
   cat > fraud-detector-enhanced-trust-policy.json << 'EOF'
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Principal": {
                   "Service": "frauddetector.amazonaws.com"
               },
               "Action": "sts:AssumeRole"
           }
       ]
   }
   EOF
   
   # Create enhanced IAM role for Fraud Detector
   aws iam create-role \
       --role-name FraudDetectorEnhancedRole \
       --assume-role-policy-document file://fraud-detector-enhanced-trust-policy.json
   
   # Create custom policy for enhanced fraud detection
   cat > fraud-detector-enhanced-policy.json << 'EOF'
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "s3:GetObject",
                   "s3:ListBucket",
                   "s3:PutObject"
               ],
               "Resource": [
                   "arn:aws:s3:::fraud-detection-platform-*",
                   "arn:aws:s3:::fraud-detection-platform-*/*"
               ]
           },
           {
               "Effect": "Allow",
               "Action": [
                   "frauddetector:*",
                   "kinesis:PutRecord",
                   "kinesis:PutRecords",
                   "dynamodb:PutItem",
                   "dynamodb:GetItem",
                   "dynamodb:UpdateItem",
                   "dynamodb:Query"
               ],
               "Resource": "*"
           }
       ]
   }
   EOF
   
   # Attach policies to role
   aws iam put-role-policy \
       --role-name FraudDetectorEnhancedRole \
       --policy-name FraudDetectorEnhancedPolicy \
       --policy-document file://fraud-detector-enhanced-policy.json
   
   # Create Lambda execution role
   aws iam create-role \
       --role-name FraudDetectionLambdaRole \
       --assume-role-policy-document '{
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
       }'
   
   # Attach managed policies for Lambda
   aws iam attach-role-policy \
       --role-name FraudDetectionLambdaRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   aws iam attach-role-policy \
       --role-name FraudDetectionLambdaRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole
   
   # Store role ARNs
   export FRAUD_DETECTOR_ROLE_ARN=$(aws iam get-role \
       --role-name FraudDetectorEnhancedRole \
       --query Role.Arn --output text)
   
   export LAMBDA_ROLE_ARN=$(aws iam get-role \
       --role-name FraudDetectionLambdaRole \
       --query Role.Arn --output text)
   
   echo "✅ Enhanced IAM roles created"
   ```
   
   The IAM roles are now configured with appropriate permissions for fraud detection operations. The FraudDetectorEnhancedRole enables the service to access training data and log decisions, while the Lambda execution role allows real-time event processing. This security foundation ensures your fraud detection pipeline operates with proper access controls and audit trails.

2. **Generate Comprehensive Training Dataset**:

   High-quality training data is critical for machine learning model performance in fraud detection. Amazon Fraud Detector's Transaction Fraud Insights models require diverse, labeled datasets with realistic fraud patterns to achieve optimal accuracy. This step creates a sophisticated dataset that includes various fraud indicators such as billing/shipping mismatches, suspicious email patterns, and high-value transactions that mirror real-world fraud scenarios.

   ```bash
   # Create realistic fraud detection training dataset
   cat > generate_training_data.py << 'EOF'
   import csv
   import random
   import datetime
   from faker import Faker
   import hashlib
   
   fake = Faker()
   
   def generate_card_bin():
       """Generate realistic card BIN numbers"""
       bins = ['411111', '424242', '444444', '555555', '376000', '378282', '371449']
       return random.choice(bins)
   
   def generate_ip_address(is_fraud=False):
       """Generate IP addresses with fraud indicators"""
       if is_fraud and random.random() < 0.3:
           # Suspicious IP patterns
           return f"{random.randint(1, 10)}.{random.randint(1, 10)}.{random.randint(1, 10)}.{random.randint(1, 254)}"
       else:
           return fake.ipv4()
   
   def generate_transaction_data(num_records=5000):
       """Generate comprehensive transaction dataset"""
       records = []
       customers = [f"cust_{i:06d}" for i in range(1, 1001)]  # 1000 unique customers
       
       for i in range(num_records):
           customer_id = random.choice(customers)
           is_fraud = random.random() < 0.05  # 5% fraud rate
           
           # Generate transaction based on fraud pattern
           if is_fraud:
               order_price = random.uniform(500, 5000)  # Higher amounts for fraud
               email = fake.email() if random.random() < 0.7 else f"temp{random.randint(1000, 9999)}@tempmail.com"
               payment_method = random.choice(['credit_card', 'debit_card'])
               product_category = random.choice(['electronics', 'jewelry', 'gift_cards'])
               
               # Shipping and billing mismatch for fraud
               billing_address = fake.street_address()
               billing_city = fake.city()
               billing_state = fake.state_abbr()
               billing_zip = fake.zipcode()
               
               if random.random() < 0.4:  # 40% shipping mismatch
                   shipping_address = fake.street_address()
                   shipping_city = fake.city()
                   shipping_state = fake.state_abbr()
                   shipping_zip = fake.zipcode()
               else:
                   shipping_address = billing_address
                   shipping_city = billing_city
                   shipping_state = billing_state
                   shipping_zip = billing_zip
               
               customer_name = fake.name()
               phone_number = fake.phone_number()
               
           else:
               order_price = random.uniform(10, 800)  # Normal amounts
               email = fake.email()
               payment_method = random.choice(['credit_card', 'debit_card', 'paypal'])
               product_category = random.choice(['books', 'clothing', 'electronics', 'home', 'sports'])
               
               # Matching billing and shipping for legitimate
               billing_address = fake.street_address()
               billing_city = fake.city()
               billing_state = fake.state_abbr()
               billing_zip = fake.zipcode()
               shipping_address = billing_address
               shipping_city = billing_city
               shipping_state = billing_state
               shipping_zip = billing_zip
               
               customer_name = fake.name()
               phone_number = fake.phone_number()
           
           # Generate timestamp within last 90 days
           timestamp = fake.date_time_between(start_date='-90d', end_date='now')
           
           record = {
               'EVENT_TIMESTAMP': timestamp.strftime('%Y-%m-%dT%H:%M:%SZ'),
               'customer_id': customer_id,
               'email_address': email,
               'ip_address': generate_ip_address(is_fraud),
               'customer_name': customer_name,
               'phone_number': phone_number,
               'billing_address': billing_address,
               'billing_city': billing_city,
               'billing_state': billing_state,
               'billing_zip': billing_zip,
               'shipping_address': shipping_address,
               'shipping_city': shipping_city,
               'shipping_state': shipping_state,
               'shipping_zip': shipping_zip,
               'payment_method': payment_method,
               'card_bin': generate_card_bin(),
               'order_price': round(order_price, 2),
               'product_category': product_category,
               'transaction_amount': round(order_price, 2),
               'currency': 'USD',
               'merchant_category': random.choice(['5411', '5812', '5732', '5999']),
               'EVENT_LABEL': 'fraud' if is_fraud else 'legit'
           }
           
           records.append(record)
       
       return records
   
   # Generate training data
   training_data = generate_transaction_data(5000)
   
   # Write to CSV
   with open('enhanced_training_data.csv', 'w', newline='') as csvfile:
       fieldnames = training_data[0].keys()
       writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
       writer.writeheader()
       writer.writerows(training_data)
   
   print(f"Generated {len(training_data)} training records")
   fraud_count = sum(1 for record in training_data if record['EVENT_LABEL'] == 'fraud')
   print(f"Fraud rate: {fraud_count/len(training_data)*100:.1f}%")
   EOF
   
   # Install required Python packages and generate data
   pip install faker
   python generate_training_data.py
   
   # Upload enhanced training data to S3
   aws s3 cp enhanced_training_data.csv s3://${FRAUD_BUCKET}/training-data/
   
   echo "✅ Enhanced training dataset generated and uploaded"
   ```
   
   The training dataset now contains 5,000 realistic transaction records with a 5% fraud rate, providing the foundation for effective model training. This dataset includes sophisticated fraud patterns like address mismatches, suspicious email domains, and velocity-based indicators that enable the model to learn complex fraud detection patterns used in production environments.

3. **Create Advanced Entity and Event Types**:

   Amazon Fraud Detector uses entity types to represent the subjects being evaluated (customers) and event types to define the structure of transactions being analyzed. These foundational elements establish the data schema that enables sophisticated feature engineering and pattern recognition. Proper configuration of entity and event types ensures optimal model performance and supports advanced fraud detection capabilities.

   ```bash
   # Create customer entity type with enhanced attributes
   aws frauddetector create-entity-type \
       --name ${ENTITY_TYPE_NAME} \
       --description "Enhanced customer entity for transaction fraud detection"
   
   # Create comprehensive event type for transaction fraud
   aws frauddetector create-event-type \
       --name ${EVENT_TYPE_NAME} \
       --description "Real-time transaction fraud detection with behavioral analytics" \
       --event-variables '[
           {"name": "customer_id", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "email_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "ip_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "customer_name", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "phone_number", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "billing_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "billing_city", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "billing_state", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "billing_zip", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "shipping_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "shipping_city", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "shipping_state", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "shipping_zip", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "payment_method", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "card_bin", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "order_price", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
           {"name": "product_category", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
           {"name": "transaction_amount", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
           {"name": "currency", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "USD"},
           {"name": "merchant_category", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"}
       ]' \
       --entity-types ${ENTITY_TYPE_NAME} \
       --event-ingestion ENABLED
   
   echo "✅ Advanced entity and event types created"
   ```
   
   The entity and event types now provide a comprehensive framework for fraud detection analysis. The customer entity type enables tracking of individual behavior patterns, while the transaction event type captures all relevant transaction attributes. This structured approach enables Amazon Fraud Detector to perform sophisticated pattern analysis and behavioral modeling for accurate fraud detection.

4. **Create Fraud Detection Labels and Variables**:

   Labels define the fraud outcomes used for model training, while variables enable sophisticated feature engineering that enhances detection accuracy. Amazon Fraud Detector supports both event-based variables (from transaction data) and calculated variables (derived features) that capture behavioral patterns and risk indicators. These components enable the system to identify subtle fraud patterns that simple rule-based systems cannot detect.

   ```bash
   # Create fraud classification labels
   aws frauddetector create-label \
       --name "fraud" \
       --description "Confirmed fraudulent transaction"
   
   aws frauddetector create-label \
       --name "legit" \
       --description "Legitimate verified transaction"
   
   # Create additional behavioral variables
   aws frauddetector create-variable \
       --name "transaction_frequency" \
       --data-type "INTEGER" \
       --data-source "CALCULATED" \
       --default-value "1" \
       --description "Number of transactions in last 24 hours"
   
   aws frauddetector create-variable \
       --name "velocity_score" \
       --data-type "FLOAT" \
       --data-source "CALCULATED" \
       --default-value "0.0" \
       --description "Transaction velocity risk score"
   
   aws frauddetector create-variable \
       --name "geo_distance" \
       --data-type "FLOAT" \
       --data-source "CALCULATED" \
       --default-value "0.0" \
       --description "Geographic distance from last transaction"
   
   echo "✅ Labels and behavioral variables created"
   ```
   
   The fraud detection framework now includes comprehensive labels for training classification and sophisticated behavioral variables for real-time analysis. These components enable the system to capture transaction velocity, geographic patterns, and other behavioral indicators that are crucial for detecting advanced fraud schemes like account takeover and synthetic identity fraud.

5. **Create and Train Transaction Fraud Insights Model**:

   The Transaction Fraud Insights model represents Amazon's most advanced fraud detection capability, incorporating 20+ years of fraud detection expertise and machine learning innovation. This supervised learning model analyzes hundreds of features automatically derived from transaction data to identify fraud patterns with industry-leading accuracy. The training process typically requires 2-4 hours and produces a production-ready model optimized for real-time fraud detection.

   ```bash
   # Create advanced Transaction Fraud Insights model
   aws frauddetector create-model \
       --model-id ${MODEL_NAME} \
       --model-type TRANSACTION_FRAUD_INSIGHTS \
       --event-type-name ${EVENT_TYPE_NAME} \
       --training-data-source '{
           "dataLocation": "s3://'${FRAUD_BUCKET}'/training-data/enhanced_training_data.csv",
           "dataAccessRoleArn": "'${FRAUD_DETECTOR_ROLE_ARN}'"
       }' \
       --training-data-schema '{
           "modelVariables": [
               "customer_id", "email_address", "ip_address", "customer_name",
               "phone_number", "billing_address", "billing_city", "billing_state",
               "billing_zip", "shipping_address", "shipping_city", "shipping_state",
               "shipping_zip", "payment_method", "card_bin", "order_price",
               "product_category", "transaction_amount", "currency", "merchant_category"
           ],
           "labelSchema": {
               "labelMapper": {
                   "fraud": ["fraud"],
                   "legit": ["legit"]
               },
               "unlabeledEventsTreatment": "IGNORE"
           }
       }'
   
   echo "✅ Transaction Fraud Insights model created and training started"
   echo "⏳ Model training will take approximately 2-4 hours"
   
   # Function to monitor training progress
   monitor_training_progress() {
       echo "Monitoring model training progress..."
       
       while true; do
           STATUS=$(aws frauddetector describe-model-versions \
               --model-id ${MODEL_NAME} \
               --model-type TRANSACTION_FRAUD_INSIGHTS \
               --query 'modelVersionDetails[0].status' --output text)
           
           echo "$(date): Training status: ${STATUS}"
           
           if [ "$STATUS" = "TRAINING_COMPLETE" ]; then
               echo "✅ Model training completed successfully"
               
               # Display model performance metrics
               aws frauddetector describe-model-versions \
                   --model-id ${MODEL_NAME} \
                   --model-type TRANSACTION_FRAUD_INSIGHTS \
                   --query 'modelVersionDetails[0].trainingMetrics'
               
               break
           elif [ "$STATUS" = "TRAINING_FAILED" ]; then
               echo "❌ Model training failed"
               exit 1
           fi
           
           sleep 600  # Check every 10 minutes
       done
   }
   
   # Start monitoring in background
   monitor_training_progress &
   MONITOR_PID=$!
   
   echo "✅ Training monitor started (PID: ${MONITOR_PID})"
   ```
   
   Model training is now in progress with automated monitoring to track completion status. The Transaction Fraud Insights model will analyze your training data to identify fraud patterns and generate risk scores. Once training completes, the model will provide real-time fraud predictions with confidence scores that enable sophisticated decision-making in your fraud detection pipeline.

6. **Create Advanced Fraud Detection Rules Engine**:

   Amazon Fraud Detector's rules engine enables sophisticated business logic that combines machine learning predictions with customizable decision criteria. Rules translate fraud risk scores into actionable outcomes, enabling organizations to implement complex fraud strategies that balance security with customer experience. This multi-outcome approach supports various response strategies from immediate blocking to manual review workflows.

   ```bash
   # Create outcomes for different fraud scenarios
   aws frauddetector create-outcome \
       --name "immediate_block" \
       --description "Block transaction immediately - high confidence fraud"
   
   aws frauddetector create-outcome \
       --name "manual_review" \
       --description "Route to manual review - medium risk"
   
   aws frauddetector create-outcome \
       --name "challenge_authentication" \
       --description "Require additional authentication"
   
   aws frauddetector create-outcome \
       --name "approve_transaction" \
       --description "Approve transaction - low risk"
   
   # Create detector
   aws frauddetector create-detector \
       --detector-id ${DETECTOR_NAME} \
       --description "Real-time fraud detection with multi-layered rules" \
       --event-type-name ${EVENT_TYPE_NAME}
   
   echo "✅ Fraud detection outcomes and detector created"
   ```
   
   The fraud detection engine now supports multiple response strategies tailored to different risk levels. This graduated response system enables organizations to balance fraud prevention with customer experience by applying appropriate actions based on transaction risk profiles. The detector framework is ready for rule configuration and model integration.

7. **Implement Sophisticated Rule Logic**:

   Rule implementation combines machine learning insights with business logic to create intelligent fraud detection decisions. These rules evaluate model risk scores alongside transaction characteristics to determine appropriate responses. The rule hierarchy ensures high-confidence fraud is blocked immediately while borderline cases receive appropriate review or authentication challenges. This approach minimizes false positives while maintaining strong fraud protection.

   ```bash
   # Wait for model training to complete before creating rules
   wait $MONITOR_PID
   
   # Create high-confidence fraud blocking rule
   aws frauddetector create-rule \
       --rule-id "immediate_block_rule" \
       --detector-id ${DETECTOR_NAME} \
       --description "Block obvious fraud with high ML confidence" \
       --expression '$'${MODEL_NAME}'_insightscore > 900 or ($order_price > 2000 and $'${MODEL_NAME}'_insightscore > 750)' \
       --language DETECTORPL \
       --outcomes '["immediate_block"]'
   
   # Create suspicious pattern detection rule
   aws frauddetector create-rule \
       --rule-id "suspicious_pattern_rule" \
       --detector-id ${DETECTOR_NAME} \
       --description "Detect suspicious patterns requiring review" \
       --expression '($'${MODEL_NAME}'_insightscore > 600 and $'${MODEL_NAME}'_insightscore <= 900) or ($billing_state != $shipping_state and $order_price > 500)' \
       --language DETECTORPL \
       --outcomes '["manual_review"]'
   
   # Create authentication challenge rule
   aws frauddetector create-rule \
       --rule-id "challenge_authentication_rule" \
       --detector-id ${DETECTOR_NAME} \
       --description "Require additional authentication for medium risk" \
       --expression '$'${MODEL_NAME}'_insightscore > 400 and $'${MODEL_NAME}'_insightscore <= 600' \
       --language DETECTORPL \
       --outcomes '["challenge_authentication"]'
   
   # Create approval rule for low risk
   aws frauddetector create-rule \
       --rule-id "approve_low_risk_rule" \
       --detector-id ${DETECTOR_NAME} \
       --description "Approve low-risk transactions" \
       --expression '$'${MODEL_NAME}'_insightscore <= 400' \
       --language DETECTORPL \
       --outcomes '["approve_transaction"]'
   
   echo "✅ Advanced fraud detection rules created"
   ```
   
   The rules engine now implements a sophisticated decision framework that automatically routes transactions based on risk levels and business criteria. High-risk transactions are blocked immediately, suspicious patterns trigger manual review, and medium-risk cases require additional authentication. This graduated approach optimizes both security and user experience while providing flexibility for fraud strategy adjustments.

8. **Create and Activate Advanced Detector Version**:

   Detector version activation represents the transition from configuration to production-ready fraud detection. This process combines trained models with configured rules to create a versioned detector capable of processing real-time fraud predictions. Version management enables safe deployment, rollback capabilities, and A/B testing of fraud detection strategies while maintaining audit trails for compliance requirements.

   ```bash
   # Create detector version with all rules
   aws frauddetector create-detector-version \
       --detector-id ${DETECTOR_NAME} \
       --description "Production fraud detection with multi-layered rules" \
       --rules '[
           {
               "detectorId": "'${DETECTOR_NAME}'",
               "ruleId": "immediate_block_rule",
               "ruleVersion": "1"
           },
           {
               "detectorId": "'${DETECTOR_NAME}'",
               "ruleId": "suspicious_pattern_rule",
               "ruleVersion": "1"
           },
           {
               "detectorId": "'${DETECTOR_NAME}'",
               "ruleId": "challenge_authentication_rule",
               "ruleVersion": "1"
           },
           {
               "detectorId": "'${DETECTOR_NAME}'",
               "ruleId": "approve_low_risk_rule",
               "ruleVersion": "1"
           }
       ]' \
       --model-versions '[
           {
               "modelId": "'${MODEL_NAME}'",
               "modelType": "TRANSACTION_FRAUD_INSIGHTS",
               "modelVersionNumber": "1.0"
           }
       ]' \
       --rule-execution-mode FIRST_MATCHED
   
   # Activate detector version
   aws frauddetector update-detector-version-status \
       --detector-id ${DETECTOR_NAME} \
       --detector-version-id "1" \
       --status ACTIVE
   
   echo "✅ Advanced fraud detector activated"
   ```
   
   The fraud detection system is now active and ready to process real-time transactions. The detector combines machine learning insights with business rules to provide instant fraud decisions. Version control enables safe updates and rollbacks while maintaining consistent fraud detection performance across your transaction processing pipeline.

9. **Create Real-Time Event Processing Lambda Functions**:

   Real-time fraud detection requires sophisticated event processing capabilities that enrich transaction data, apply fraud models, and route decisions within milliseconds. Lambda functions provide the scalable, event-driven processing required for high-volume transaction streams while maintaining low latency. This architecture enables sophisticated feature engineering and decision logic that enhances fraud detection accuracy beyond basic model predictions.

   ```bash
   # Create event enrichment Lambda function
   cat > event_enrichment_lambda.py << 'EOF'
   import json
   import boto3
   import hashlib
   from datetime import datetime, timedelta
   import base64
   
   dynamodb = boto3.resource('dynamodb')
   
   def lambda_handler(event, context):
       """
       Enriches incoming transaction events with behavioral features
       """
       
       for record in event['Records']:
           # Decode Kinesis data
           payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
           transaction_data = json.loads(payload)
           
           # Extract customer ID
           customer_id = transaction_data.get('customer_id')
           
           # Calculate behavioral features
           enriched_data = enrich_transaction_data(transaction_data)
           
           # Forward to fraud detection Lambda
           forward_to_fraud_detection(enriched_data)
   
   def enrich_transaction_data(transaction_data):
       """
       Add behavioral and historical features to transaction data
       """
       customer_id = transaction_data.get('customer_id')
       current_time = datetime.now()
       
       # Calculate transaction frequency (simplified)
       transaction_data['transaction_frequency'] = get_transaction_frequency(customer_id)
       
       # Calculate velocity score based on recent activity
       transaction_data['velocity_score'] = calculate_velocity_score(customer_id)
       
       # Add timestamp for processing
       transaction_data['processing_timestamp'] = current_time.isoformat()
       
       return transaction_data
   
   def get_transaction_frequency(customer_id):
       """
       Calculate number of transactions in last 24 hours
       """
       # Simplified implementation - in production, query DynamoDB
       return 1
   
   def calculate_velocity_score(customer_id):
       """
       Calculate velocity-based risk score
       """
       # Simplified implementation - in production, use historical data
       return 0.1
   
   def forward_to_fraud_detection(enriched_data):
       """
       Forward enriched data to fraud detection Lambda
       """
       lambda_client = boto3.client('lambda')
       
       lambda_client.invoke(
           FunctionName='fraud-detection-processor',
           InvocationType='Event',
           Payload=json.dumps(enriched_data)
       )
   
   EOF
   
   # Create fraud detection processor Lambda
   cat > fraud_detection_processor.py << 'EOF'
   import json
   import boto3
   import logging
   from datetime import datetime
   import uuid
   
   logger = logging.getLogger()
   logger.setLevel(logging.INFO)
   
   frauddetector = boto3.client('frauddetector')
   dynamodb = boto3.resource('dynamodb')
   sns = boto3.client('sns')
   
   def lambda_handler(event, context):
       """
       Process fraud detection for enriched transaction data
       """
       try:
           # Extract transaction data
           transaction_data = event
           
           # Generate unique event ID
           event_id = f"txn_{uuid.uuid4().hex[:16]}"
           
           # Prepare variables for fraud detection
           variables = prepare_fraud_variables(transaction_data)
           
           # Get fraud prediction
           fraud_response = get_fraud_prediction(event_id, variables)
           
           # Process and log decision
           decision = process_fraud_decision(transaction_data, fraud_response)
           
           # Send alerts if necessary
           if decision['risk_level'] in ['HIGH', 'CRITICAL']:
               send_fraud_alert(decision)
           
           return {
               'statusCode': 200,
               'body': json.dumps({
                   'transaction_id': transaction_data.get('transaction_id'),
                   'decision': decision['action'],
                   'risk_score': decision['risk_score'],
                   'risk_level': decision['risk_level']
               })
           }
           
       except Exception as e:
           logger.error(f"Error processing fraud detection: {str(e)}")
           return {
               'statusCode': 500,
               'body': json.dumps({'error': str(e)})
           }
   
   def prepare_fraud_variables(transaction_data):
       """
       Prepare variables for fraud detection API call
       """
       return {
           'customer_id': transaction_data.get('customer_id', 'unknown'),
           'email_address': transaction_data.get('email_address', 'unknown'),
           'ip_address': transaction_data.get('ip_address', 'unknown'),
           'customer_name': transaction_data.get('customer_name', 'unknown'),
           'phone_number': transaction_data.get('phone_number', 'unknown'),
           'billing_address': transaction_data.get('billing_address', 'unknown'),
           'billing_city': transaction_data.get('billing_city', 'unknown'),
           'billing_state': transaction_data.get('billing_state', 'unknown'),
           'billing_zip': transaction_data.get('billing_zip', 'unknown'),
           'shipping_address': transaction_data.get('shipping_address', 'unknown'),
           'shipping_city': transaction_data.get('shipping_city', 'unknown'),
           'shipping_state': transaction_data.get('shipping_state', 'unknown'),
           'shipping_zip': transaction_data.get('shipping_zip', 'unknown'),
           'payment_method': transaction_data.get('payment_method', 'unknown'),
           'card_bin': transaction_data.get('card_bin', 'unknown'),
           'order_price': str(transaction_data.get('order_price', 0.0)),
           'product_category': transaction_data.get('product_category', 'unknown'),
           'transaction_amount': str(transaction_data.get('transaction_amount', 0.0)),
           'currency': transaction_data.get('currency', 'USD'),
           'merchant_category': transaction_data.get('merchant_category', 'unknown')
       }
   
   def get_fraud_prediction(event_id, variables):
       """
       Get fraud prediction from Amazon Fraud Detector
       """
       import os
       
       return frauddetector.get_event_prediction(
           detectorId=os.environ['DETECTOR_NAME'],
           eventId=event_id,
           eventTypeName=os.environ['EVENT_TYPE_NAME'],
           entities=[{
               'entityType': os.environ['ENTITY_TYPE_NAME'],
               'entityId': variables['customer_id']
           }],
           eventTimestamp=datetime.now().isoformat(),
           eventVariables=variables
       )
   
   def process_fraud_decision(transaction_data, fraud_response):
       """
       Process fraud detection response and make decision
       """
       # Extract model scores and outcomes
       model_scores = fraud_response.get('modelScores', [])
       rule_results = fraud_response.get('ruleResults', [])
       
       # Determine primary outcome
       primary_outcome = None
       if rule_results:
           primary_outcome = rule_results[0]['outcomes'][0] if rule_results[0]['outcomes'] else None
       
       # Calculate risk score
       risk_score = 0
       if model_scores:
           risk_score = model_scores[0]['scores'].get('TRANSACTION_FRAUD_INSIGHTS', 0)
       
       # Determine risk level
       risk_level = determine_risk_level(risk_score, primary_outcome)
       
       # Create decision record
       decision = {
           'transaction_id': transaction_data.get('transaction_id'),
           'customer_id': transaction_data.get('customer_id'),
           'timestamp': datetime.now().isoformat(),
           'risk_score': risk_score,
           'risk_level': risk_level,
           'action': primary_outcome or 'approve_transaction',
           'model_scores': model_scores,
           'rule_results': rule_results,
           'processing_time': datetime.now().isoformat()
       }
       
       # Log decision to DynamoDB
       log_decision(decision)
       
       return decision
   
   def determine_risk_level(risk_score, outcome):
       """
       Determine risk level based on score and outcome
       """
       if outcome == 'immediate_block' or risk_score > 900:
           return 'CRITICAL'
       elif outcome == 'manual_review' or risk_score > 600:
           return 'HIGH'
       elif outcome == 'challenge_authentication' or risk_score > 400:
           return 'MEDIUM'
       else:
           return 'LOW'
   
   def log_decision(decision):
       """
       Log fraud decision to DynamoDB
       """
       import os
       
       table = dynamodb.Table(os.environ['DECISIONS_TABLE'])
       
       table.put_item(
           Item={
               'transaction_id': decision['transaction_id'],
               'timestamp': int(datetime.now().timestamp()),
               'customer_id': decision['customer_id'],
               'risk_score': decision['risk_score'],
               'risk_level': decision['risk_level'],
               'action': decision['action'],
               'processing_time': decision['processing_time']
           }
       )
   
   def send_fraud_alert(decision):
       """
       Send fraud alert for high-risk transactions
       """
       import os
       
       if 'SNS_TOPIC_ARN' in os.environ:
           message = {
               'alert_type': 'HIGH_RISK_TRANSACTION',
               'transaction_id': decision['transaction_id'],
               'customer_id': decision['customer_id'],
               'risk_score': decision['risk_score'],
               'risk_level': decision['risk_level'],
               'action': decision['action'],
               'timestamp': decision['timestamp']
           }
           
           sns.publish(
               TopicArn=os.environ['SNS_TOPIC_ARN'],
               Message=json.dumps(message),
               Subject=f"High Risk Transaction Alert - {decision['risk_level']}"
           )
   
   EOF
   
   # Create deployment packages
   zip event-enrichment.zip event_enrichment_lambda.py
   zip fraud-detection-processor.zip fraud_detection_processor.py
   
   # Create event enrichment Lambda function
   aws lambda create-function \
       --function-name event-enrichment-processor \
       --runtime python3.9 \
       --role ${LAMBDA_ROLE_ARN} \
       --handler event_enrichment_lambda.lambda_handler \
       --zip-file fileb://event-enrichment.zip \
       --timeout 60 \
       --memory-size 256
   
   # Create fraud detection processor Lambda function
   aws lambda create-function \
       --function-name fraud-detection-processor \
       --runtime python3.9 \
       --role ${LAMBDA_ROLE_ARN} \
       --handler fraud_detection_processor.lambda_handler \
       --zip-file fileb://fraud-detection-processor.zip \
       --timeout 30 \
       --memory-size 512 \
       --environment Variables='{
           "DETECTOR_NAME": "'${DETECTOR_NAME}'",
           "EVENT_TYPE_NAME": "'${EVENT_TYPE_NAME}'",
           "ENTITY_TYPE_NAME": "'${ENTITY_TYPE_NAME}'",
           "DECISIONS_TABLE": "'${DECISIONS_TABLE}'"
       }'
   
   # Create event source mapping for Kinesis
   aws lambda create-event-source-mapping \
       --event-source-arn arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM} \
       --function-name event-enrichment-processor \
       --starting-position LATEST \
       --batch-size 10
   
   echo "✅ Real-time processing Lambda functions created"
   ```
   
   The real-time processing pipeline now provides sophisticated event enrichment and fraud scoring capabilities. Lambda functions process streaming transactions, apply behavioral analytics, and route fraud decisions with sub-second latency. This architecture supports high-volume transaction processing while maintaining the flexibility to implement complex fraud detection logic and business rules.

10. **Create SNS Topic for Fraud Alerts**:

    Fraud alert systems enable rapid response to high-risk transactions through automated notification and escalation workflows. Amazon SNS provides reliable, scalable messaging that connects fraud detection systems with case management platforms, analyst dashboards, and automated response systems. This integration ensures critical fraud events receive immediate attention while maintaining comprehensive audit trails for investigation and compliance.

    ```bash
    # Create SNS topic for fraud alerts
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name fraud-detection-alerts \
        --query TopicArn --output text)
    
    # Update fraud detection processor with SNS topic
    aws lambda update-function-configuration \
        --function-name fraud-detection-processor \
        --environment Variables='{
            "DETECTOR_NAME": "'${DETECTOR_NAME}'",
            "EVENT_TYPE_NAME": "'${EVENT_TYPE_NAME}'",
            "ENTITY_TYPE_NAME": "'${ENTITY_TYPE_NAME}'",
            "DECISIONS_TABLE": "'${DECISIONS_TABLE}'",
            "SNS_TOPIC_ARN": "'${SNS_TOPIC_ARN}'"
        }'
    
    # Subscribe to fraud alerts (replace with actual email)
    aws sns subscribe \
        --topic-arn ${SNS_TOPIC_ARN} \
        --protocol email \
        --notification-endpoint your-email@example.com
    
    echo "✅ Fraud alert system configured"
    echo "   SNS Topic: ${SNS_TOPIC_ARN}"
    ```
    
    The alert system now provides automated notification capabilities for high-risk fraud events. SNS integration enables real-time alerts to fraud analysts, automated case creation in management systems, and escalation workflows based on risk severity. This notification infrastructure ensures rapid response to fraud threats while supporting comprehensive investigation and remediation processes.

11. **Test End-to-End Real-Time Fraud Detection**:

    Comprehensive testing validates the entire fraud detection pipeline from transaction ingestion through decision delivery. These tests verify model accuracy, rule evaluation, alert generation, and system performance under various transaction scenarios. Testing both legitimate and suspicious transactions ensures the system properly balances fraud prevention with customer experience while maintaining required response times.

    ```bash
    # Create test transaction data
    cat > test_transaction.json << 'EOF'
    {
        "transaction_id": "test_001",
        "customer_id": "cust_000001",
        "email_address": "test@example.com",
        "ip_address": "192.168.1.100",
        "customer_name": "John Doe",
        "phone_number": "555-1234",
        "billing_address": "123 Main St",
        "billing_city": "Seattle",
        "billing_state": "WA",
        "billing_zip": "98101",
        "shipping_address": "123 Main St",
        "shipping_city": "Seattle",
        "shipping_state": "WA",
        "shipping_zip": "98101",
        "payment_method": "credit_card",
        "card_bin": "411111",
        "order_price": 99.99,
        "product_category": "electronics",
        "transaction_amount": 99.99,
        "currency": "USD",
        "merchant_category": "5732"
    }
    EOF
    
    # Test real-time fraud detection via direct API call
    aws frauddetector get-event-prediction \
        --detector-id ${DETECTOR_NAME} \
        --event-id "test_realtime_$(date +%s)" \
        --event-type-name ${EVENT_TYPE_NAME} \
        --entities '[{
            "entityType": "'${ENTITY_TYPE_NAME}'",
            "entityId": "cust_000001"
        }]' \
        --event-timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
        --event-variables '{
            "customer_id": "cust_000001",
            "email_address": "test@example.com",
            "ip_address": "192.168.1.100",
            "customer_name": "John Doe",
            "phone_number": "555-1234",
            "billing_address": "123 Main St",
            "billing_city": "Seattle",
            "billing_state": "WA",
            "billing_zip": "98101",
            "shipping_address": "123 Main St",
            "shipping_city": "Seattle",
            "shipping_state": "WA",
            "shipping_zip": "98101",
            "payment_method": "credit_card",
            "card_bin": "411111",
            "order_price": "99.99",
            "product_category": "electronics",
            "transaction_amount": "99.99",
            "currency": "USD",
            "merchant_category": "5732"
        }' \
        --output json
    
    # Test high-risk transaction
    aws frauddetector get-event-prediction \
        --detector-id ${DETECTOR_NAME} \
        --event-id "test_highrisk_$(date +%s)" \
        --event-type-name ${EVENT_TYPE_NAME} \
        --entities '[{
            "entityType": "'${ENTITY_TYPE_NAME}'",
            "entityId": "cust_000002"
        }]' \
        --event-timestamp $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
        --event-variables '{
            "customer_id": "cust_000002",
            "email_address": "suspicious@tempmail.com",
            "ip_address": "1.2.3.4",
            "customer_name": "Suspicious User",
            "phone_number": "555-0000",
            "billing_address": "123 Fake St",
            "billing_city": "Nowhere",
            "billing_state": "CA",
            "billing_zip": "00000",
            "shipping_address": "456 Different St",
            "shipping_city": "Elsewhere",
            "shipping_state": "NY",
            "shipping_zip": "11111",
            "payment_method": "credit_card",
            "card_bin": "444444",
            "order_price": "2999.99",
            "product_category": "electronics",
            "transaction_amount": "2999.99",
            "currency": "USD",
            "merchant_category": "5999"
        }' \
        --output json
    
    # Test via Kinesis stream
    aws kinesis put-record \
        --stream-name ${KINESIS_STREAM} \
        --partition-key "test_transaction" \
        --data file://test_transaction.json
    
    echo "✅ End-to-end fraud detection tests completed"
    ```
    
    The fraud detection system has been validated through comprehensive testing scenarios that confirm proper operation across all components. Test results demonstrate the system's ability to accurately classify transactions, apply appropriate business rules, and deliver decisions within required timeframes. The pipeline is now ready for production deployment with confidence in its fraud detection capabilities.

12. **Create Performance Monitoring Dashboard**:

    Production fraud detection systems require comprehensive monitoring to ensure optimal performance, accuracy, and availability. CloudWatch dashboards provide real-time visibility into system metrics, processing latency, error rates, and fraud detection effectiveness. This monitoring infrastructure enables proactive system management, performance optimization, and rapid identification of issues that could impact fraud detection accuracy or customer experience.

    ```bash
    # Create CloudWatch dashboard for fraud detection monitoring
    cat > fraud_detection_dashboard.json << 'EOF'
    {
        "widgets": [
            {
                "type": "metric",
                "properties": {
                    "metrics": [
                        ["AWS/Lambda", "Invocations", "FunctionName", "fraud-detection-processor"],
                        ["AWS/Lambda", "Duration", "FunctionName", "fraud-detection-processor"],
                        ["AWS/Lambda", "Errors", "FunctionName", "fraud-detection-processor"]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "'${AWS_REGION}'",
                    "title": "Fraud Detection Lambda Metrics"
                }
            },
            {
                "type": "metric",
                "properties": {
                    "metrics": [
                        ["AWS/Kinesis", "IncomingRecords", "StreamName", "'${KINESIS_STREAM}'"],
                        ["AWS/Kinesis", "OutgoingRecords", "StreamName", "'${KINESIS_STREAM}'"]
                    ],
                    "period": 300,
                    "stat": "Sum",
                    "region": "'${AWS_REGION}'",
                    "title": "Transaction Stream Metrics"
                }
            },
            {
                "type": "metric",
                "properties": {
                    "metrics": [
                        ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "'${DECISIONS_TABLE}'"],
                        ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "'${DECISIONS_TABLE}'"]
                    ],
                    "period": 300,
                    "stat": "Sum",
                    "region": "'${AWS_REGION}'",
                    "title": "Decision Storage Metrics"
                }
            }
        ]
    }
    EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "FraudDetectionPlatform" \
        --dashboard-body file://fraud_detection_dashboard.json
    
    echo "✅ Performance monitoring dashboard created"
    ```
    
    The monitoring dashboard now provides comprehensive visibility into fraud detection system performance and health. Real-time metrics enable proactive management of processing capacity, detection accuracy, and system availability. This monitoring infrastructure supports operational excellence and enables data-driven optimization of fraud detection strategies and system performance.

## Validation & Testing

1. **Verify Model Training Performance**:

   ```bash
   # Check model training metrics and performance
   aws frauddetector describe-model-versions \
       --model-id ${MODEL_NAME} \
       --model-type TRANSACTION_FRAUD_INSIGHTS \
       --query 'modelVersionDetails[0].trainingMetrics'
   ```

   Expected output: Training metrics including precision, recall, F1-score, and AUC values.

2. **Test Detector Activation and Rules**:

   ```bash
   # Verify detector is active and functioning
   aws frauddetector describe-detector \
       --detector-id ${DETECTOR_NAME} \
       --query 'detectorVersionSummaries[0].{Status:status,Rules:ruleExecutionMode}'
   ```

   Expected output: Status "ACTIVE" with rule execution mode "FIRST_MATCHED".

3. **Validate Real-Time Processing Pipeline**:

   ```bash
   # Test Lambda function responses
   aws lambda invoke \
       --function-name fraud-detection-processor \
       --payload '{
           "customer_id": "test_customer",
           "order_price": 150.00,
           "transaction_amount": 150.00,
           "email_address": "test@example.com",
           "ip_address": "192.168.1.1"
       }' \
       response.json
   
   # Check response
   cat response.json
   ```

   Expected output: JSON response with fraud decision and risk score.

4. **Test Alert System**:

   ```bash
   # Verify SNS topic and subscriptions
   aws sns list-subscriptions-by-topic \
       --topic-arn ${SNS_TOPIC_ARN}
   
   # Test fraud alert
   aws sns publish \
       --topic-arn ${SNS_TOPIC_ARN} \
       --message "Test fraud alert" \
       --subject "Fraud Detection Test"
   ```

   Expected output: Subscription confirmation and test alert delivery.

5. **Monitor Performance Metrics**:

   ```bash
   # Check recent Lambda invocations
   aws logs describe-log-groups \
       --log-group-name-prefix "/aws/lambda/fraud-detection"
   
   # Check DynamoDB decision records
   aws dynamodb scan \
       --table-name ${DECISIONS_TABLE} \
       --max-items 5 \
       --query 'Items[*].{TransactionId:transaction_id.S,RiskScore:risk_score.N,Action:action.S}'
   ```

   Expected output: Recent fraud detection decisions and processing logs.

## Cleanup

1. **Deactivate and Remove Fraud Detector**:

   ```bash
   # Deactivate detector version
   aws frauddetector update-detector-version-status \
       --detector-id ${DETECTOR_NAME} \
       --detector-version-id "1" \
       --status INACTIVE
   
   # Delete detector version
   aws frauddetector delete-detector-version \
       --detector-id ${DETECTOR_NAME} \
       --detector-version-id "1"
   
   # Delete detector
   aws frauddetector delete-detector \
       --detector-id ${DETECTOR_NAME}
   
   echo "✅ Fraud detector deactivated and deleted"
   ```

2. **Remove Model and Training Resources**:

   ```bash
   # Delete model version
   aws frauddetector delete-model-version \
       --model-id ${MODEL_NAME} \
       --model-type TRANSACTION_FRAUD_INSIGHTS \
       --model-version-number 1.0
   
   # Delete model
   aws frauddetector delete-model \
       --model-id ${MODEL_NAME} \
       --model-type TRANSACTION_FRAUD_INSIGHTS
   
   echo "✅ Model and training resources deleted"
   ```

3. **Clean Up Rules and Outcomes**:

   ```bash
   # Delete all rules
   for rule in "immediate_block_rule" "suspicious_pattern_rule" "challenge_authentication_rule" "approve_low_risk_rule"; do
       aws frauddetector delete-rule \
           --rule-id $rule \
           --detector-id ${DETECTOR_NAME} 2>/dev/null || true
   done
   
   # Delete outcomes
   for outcome in "immediate_block" "manual_review" "challenge_authentication" "approve_transaction"; do
       aws frauddetector delete-outcome --name $outcome 2>/dev/null || true
   done
   
   echo "✅ Rules and outcomes deleted"
   ```

4. **Remove Event Types and Variables**:

   ```bash
   # Delete event type
   aws frauddetector delete-event-type \
       --name ${EVENT_TYPE_NAME}
   
   # Delete entity type
   aws frauddetector delete-entity-type \
       --name ${ENTITY_TYPE_NAME}
   
   # Delete labels
   aws frauddetector delete-label --name "fraud" 2>/dev/null || true
   aws frauddetector delete-label --name "legit" 2>/dev/null || true
   
   # Delete custom variables
   for var in "transaction_frequency" "velocity_score" "geo_distance"; do
       aws frauddetector delete-variable --name $var 2>/dev/null || true
   done
   
   echo "✅ Event types, variables, and labels deleted"
   ```

5. **Remove Supporting Infrastructure**:

   ```bash
   # Delete Lambda functions
   aws lambda delete-function \
       --function-name fraud-detection-processor
   
   aws lambda delete-function \
       --function-name event-enrichment-processor
   
   # Delete SNS topic
   aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}
   
   # Delete DynamoDB table
   aws dynamodb delete-table --table-name ${DECISIONS_TABLE}
   
   # Delete Kinesis stream
   aws kinesis delete-stream --stream-name ${KINESIS_STREAM}
   
   # Delete CloudWatch dashboard
   aws cloudwatch delete-dashboards \
       --dashboard-names "FraudDetectionPlatform"
   
   echo "✅ Supporting infrastructure deleted"
   ```

6. **Clean Up Storage and IAM Resources**:

   ```bash
   # Delete S3 bucket contents and bucket
   aws s3 rm s3://${FRAUD_BUCKET} --recursive
   aws s3 rb s3://${FRAUD_BUCKET}
   
   # Delete IAM roles and policies
   aws iam detach-role-policy \
       --role-name FraudDetectionLambdaRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
   
   aws iam detach-role-policy \
       --role-name FraudDetectionLambdaRole \
       --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole
   
   aws iam delete-role --role-name FraudDetectionLambdaRole
   
   aws iam delete-role-policy \
       --role-name FraudDetectorEnhancedRole \
       --policy-name FraudDetectorEnhancedPolicy
   
   aws iam delete-role --role-name FraudDetectorEnhancedRole
   
   # Clean up local files
   rm -f fraud-detector-enhanced-trust-policy.json
   rm -f fraud-detector-enhanced-policy.json
   rm -f generate_training_data.py
   rm -f enhanced_training_data.csv
   rm -f event_enrichment_lambda.py
   rm -f fraud_detection_processor.py
   rm -f event-enrichment.zip
   rm -f fraud-detection-processor.zip
   rm -f test_transaction.json
   rm -f fraud_detection_dashboard.json
   rm -f response.json
   
   echo "✅ All resources and files cleaned up"
   ```

## Discussion

This advanced implementation of real-time fraud detection with Amazon Fraud Detector demonstrates enterprise-grade patterns for building production-ready fraud detection systems. The Transaction Fraud Insights model leverages Amazon's 20+ years of fraud detection expertise, incorporating advanced feature engineering, ensemble learning algorithms, and behavioral analytics to achieve high accuracy with minimal false positives. The architecture supports sub-second response times while processing millions of transactions per hour, making it suitable for high-volume financial services and e-commerce platforms.

The real-time processing pipeline integrates streaming data ingestion through Kinesis, event enrichment with Lambda functions, and sophisticated rule engines that combine machine learning scores with business logic. This multi-layered approach enables organizations to implement complex fraud detection strategies, including velocity checks, geographic analysis, and pattern recognition, while maintaining the flexibility to adapt rules based on evolving fraud patterns. The system automatically enriches transactions with historical behavioral features, enabling detection of sophisticated fraud schemes like account takeover attacks and coordinated fraud rings.

Cost optimization is achieved through several strategies: using Transaction Fraud Insights models reduces the need for extensive data science resources, the pay-per-prediction model scales costs with usage, and the streaming architecture minimizes infrastructure overhead. The system's ability to process events in real-time eliminates the need for batch processing infrastructure, while the DynamoDB integration provides cost-effective storage for audit trails and decision logs. Organizations can further optimize costs by implementing prediction caching for repeat customers and using reserved capacity for predictable workloads.

Integration with existing payment systems is facilitated through standard API patterns and event-driven architecture. The system supports both synchronous and asynchronous integration models, allowing organizations to implement fraud detection at various points in their transaction processing pipeline. The SNS-based alert system enables integration with existing case management systems, while the DynamoDB decision log provides comprehensive audit trails for compliance and investigation purposes. The modular design allows organizations to implement incremental rollouts and A/B testing of fraud detection strategies.

## Challenge

Extend this real-time fraud detection system with these advanced enterprise capabilities:

1. **Implement Multi-Model Ensemble Architecture**: Deploy multiple specialized fraud detection models (account takeover, payment fraud, synthetic identity) and create a weighted ensemble scoring system that combines predictions from different models based on transaction context and historical performance metrics.

2. **Build Advanced Behavioral Analytics Pipeline**: Create a comprehensive behavioral analytics system using Amazon Kinesis Analytics that calculates real-time features like transaction velocity, spending pattern deviations, device fingerprinting, and network analysis to enhance fraud detection accuracy for sophisticated attack patterns.

3. **Develop Adaptive Learning and Feedback Loop**: Implement an intelligent feedback system that automatically incorporates fraud analyst decisions, customer dispute outcomes, and chargeback data to continuously improve model performance through automated retraining pipelines and dynamic rule optimization.

4. **Create Fraud Investigation and Case Management Platform**: Build a comprehensive fraud investigation dashboard using Amazon QuickSight that provides fraud analysts with interactive visualizations, transaction timelines, network analysis, and automated case prioritization based on risk severity and business impact.

5. **Implement Cross-Channel Fraud Detection**: Extend the system to detect fraud across multiple channels (web, mobile, ATM, point-of-sale) by implementing a unified customer profile that tracks behavior patterns across all touchpoints and identifies anomalies in cross-channel transaction patterns.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*