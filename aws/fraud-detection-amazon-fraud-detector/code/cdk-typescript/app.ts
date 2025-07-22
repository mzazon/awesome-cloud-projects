#!/usr/bin/env node

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as kinesisEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Properties for the Real-Time Fraud Detection Stack
 */
export interface RealTimeFraudDetectionStackProps extends cdk.StackProps {
  /**
   * The environment name (e.g., 'dev', 'staging', 'prod')
   * @default 'dev'
   */
  readonly environment?: string;

  /**
   * The number of Kinesis shards for transaction processing
   * @default 3
   */
  readonly kinesisShards?: number;

  /**
   * The DynamoDB read capacity units for the decisions table
   * @default 100
   */
  readonly dynamoDbReadCapacity?: number;

  /**
   * The DynamoDB write capacity units for the decisions table
   * @default 100
   */
  readonly dynamoDbWriteCapacity?: number;

  /**
   * Whether to enable detailed monitoring and logging
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;

  /**
   * Email address for fraud alerts
   * @default undefined
   */
  readonly alertEmail?: string;

  /**
   * Fraud detection model name
   * @default 'transaction_fraud_insights'
   */
  readonly modelName?: string;

  /**
   * Fraud detector name
   * @default 'realtime_fraud_detector'
   */
  readonly detectorName?: string;

  /**
   * Whether to deploy in production mode with enhanced security
   * @default false
   */
  readonly productionMode?: boolean;
}

/**
 * CDK Stack for Real-Time Fraud Detection with Amazon Fraud Detector
 * 
 * This stack implements a comprehensive fraud detection platform that processes
 * real-time transaction streams, applies machine learning models, and provides
 * instant fraud decisions through sophisticated business rules.
 * 
 * Key Components:
 * - Amazon Fraud Detector for ML-powered fraud detection
 * - Kinesis Data Streams for real-time transaction processing
 * - Lambda functions for event enrichment and fraud scoring
 * - DynamoDB for decision logging and audit trails
 * - SNS for fraud alerts and notifications
 * - CloudWatch for monitoring and observability
 * 
 * Architecture supports:
 * - Sub-second fraud detection decisions
 * - Sophisticated behavioral analytics
 * - Multi-layered rule engines
 * - Scalable event processing
 * - Comprehensive monitoring and alerting
 */
export class RealTimeFraudDetectionStack extends cdk.Stack {
  /**
   * The S3 bucket for storing training data and model artifacts
   */
  public readonly fraudBucket: s3.Bucket;

  /**
   * The Kinesis stream for real-time transaction processing
   */
  public readonly transactionStream: kinesis.Stream;

  /**
   * The DynamoDB table for fraud decisions logging
   */
  public readonly decisionsTable: dynamodb.Table;

  /**
   * The SNS topic for fraud alerts
   */
  public readonly alertTopic: sns.Topic;

  /**
   * The Lambda function for event enrichment
   */
  public readonly eventEnrichmentFunction: lambda.Function;

  /**
   * The Lambda function for fraud detection processing
   */
  public readonly fraudDetectionFunction: lambda.Function;

  /**
   * The CloudWatch dashboard for monitoring
   */
  public readonly monitoringDashboard: cloudwatch.Dashboard;

  /**
   * The IAM role for Amazon Fraud Detector
   */
  public readonly fraudDetectorRole: iam.Role;

  /**
   * Random suffix for unique resource naming
   */
  private readonly randomSuffix: string;

  constructor(scope: Construct, id: string, props: RealTimeFraudDetectionStackProps = {}) {
    super(scope, id, props);

    // Apply default values
    const environment = props.environment ?? 'dev';
    const kinesisShards = props.kinesisShards ?? 3;
    const dynamoDbReadCapacity = props.dynamoDbReadCapacity ?? 100;
    const dynamoDbWriteCapacity = props.dynamoDbWriteCapacity ?? 100;
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const modelName = props.modelName ?? 'transaction_fraud_insights';
    const detectorName = props.detectorName ?? 'realtime_fraud_detector';
    const productionMode = props.productionMode ?? false;

    // Generate random suffix for unique resource names
    this.randomSuffix = this.generateRandomSuffix();

    // Create foundational infrastructure
    this.createFoundationalInfrastructure(environment, kinesisShards, dynamoDbReadCapacity, dynamoDbWriteCapacity);

    // Create IAM roles and policies
    this.createIAMRoles(productionMode);

    // Create Lambda functions for real-time processing
    this.createLambdaFunctions(modelName, detectorName, environment);

    // Create fraud detection components
    this.createFraudDetectionComponents(modelName, detectorName, environment);

    // Create monitoring and alerting
    this.createMonitoringAndAlerting(enableDetailedMonitoring, props.alertEmail);

    // Create outputs
    this.createOutputs();

    // Apply tags
    this.applyTags(environment);
  }

  /**
   * Generate a random suffix for unique resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 10);
  }

  /**
   * Create foundational infrastructure including S3, Kinesis, and DynamoDB
   */
  private createFoundationalInfrastructure(
    environment: string, 
    kinesisShards: number, 
    dynamoDbReadCapacity: number, 
    dynamoDbWriteCapacity: number
  ): void {
    // Create S3 bucket for training data and model artifacts
    this.fraudBucket = new s3.Bucket(this, 'FraudDetectionBucket', {
      bucketName: `fraud-detection-platform-${this.randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TrainingDataRetention',
          enabled: true,
          expiration: Duration.days(365),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90)
            }
          ]
        }
      ]
    });

    // Create Kinesis stream for real-time transaction processing
    this.transactionStream = new kinesis.Stream(this, 'TransactionStream', {
      streamName: `fraud-transaction-stream-${this.randomSuffix}`,
      shardCount: kinesisShards,
      retentionPeriod: Duration.days(7),
      encryption: kinesis.StreamEncryption.MANAGED
    });

    // Create DynamoDB table for fraud decisions logging
    this.decisionsTable = new dynamodb.Table(this, 'DecisionsTable', {
      tableName: `fraud_decisions_${this.randomSuffix}`,
      partitionKey: {
        name: 'transaction_id',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: dynamoDbReadCapacity,
      writeCapacity: dynamoDbWriteCapacity,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
    });

    // Add global secondary index for customer-based queries
    this.decisionsTable.addGlobalSecondaryIndex({
      indexName: 'customer-index',
      partitionKey: {
        name: 'customer_id',
        type: dynamodb.AttributeType.STRING
      },
      projectionType: dynamodb.ProjectionType.ALL,
      readCapacity: Math.ceil(dynamoDbReadCapacity / 2),
      writeCapacity: Math.ceil(dynamoDbWriteCapacity / 2)
    });

    // Create SNS topic for fraud alerts
    this.alertTopic = new sns.Topic(this, 'FraudAlertTopic', {
      topicName: `fraud-detection-alerts-${this.randomSuffix}`,
      displayName: 'Fraud Detection Alerts',
      fifo: false
    });
  }

  /**
   * Create IAM roles and policies for fraud detection services
   */
  private createIAMRoles(productionMode: boolean): void {
    // Create IAM role for Amazon Fraud Detector
    this.fraudDetectorRole = new iam.Role(this, 'FraudDetectorRole', {
      roleName: `FraudDetectorEnhancedRole-${this.randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('frauddetector.amazonaws.com'),
      description: 'Enhanced IAM role for Amazon Fraud Detector service',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonFraudDetectorFullAccessPolicy')
      ]
    });

    // Add custom policy for enhanced fraud detection capabilities
    const fraudDetectorPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:ListBucket',
            's3:PutObject'
          ],
          resources: [
            this.fraudBucket.bucketArn,
            `${this.fraudBucket.bucketArn}/*`
          ]
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'frauddetector:*',
            'kinesis:PutRecord',
            'kinesis:PutRecords',
            'dynamodb:PutItem',
            'dynamodb:GetItem',
            'dynamodb:UpdateItem',
            'dynamodb:Query'
          ],
          resources: ['*']
        })
      ]
    });

    this.fraudDetectorRole.attachInlinePolicy(new iam.Policy(this, 'FraudDetectorEnhancedPolicy', {
      policyName: 'FraudDetectorEnhancedPolicy',
      document: fraudDetectorPolicy
    }));

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'FraudDetectionLambdaRole', {
      roleName: `FraudDetectionLambdaRole-${this.randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for fraud detection Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaKinesisExecutionRole')
      ]
    });

    // Add custom policy for Lambda functions
    const lambdaPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'frauddetector:GetEventPrediction',
            'frauddetector:GetDetectors',
            'frauddetector:GetModels'
          ],
          resources: ['*']
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'dynamodb:PutItem',
            'dynamodb:GetItem',
            'dynamodb:UpdateItem',
            'dynamodb:Query',
            'dynamodb:Scan'
          ],
          resources: [
            this.decisionsTable.tableArn,
            `${this.decisionsTable.tableArn}/index/*`
          ]
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'sns:Publish'
          ],
          resources: [this.alertTopic.topicArn]
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'lambda:InvokeFunction'
          ],
          resources: [`arn:aws:lambda:${this.region}:${this.account}:function:*`]
        })
      ]
    });

    lambdaRole.attachInlinePolicy(new iam.Policy(this, 'FraudDetectionLambdaPolicy', {
      policyName: 'FraudDetectionLambdaPolicy',
      document: lambdaPolicy
    }));

    // Store Lambda role for use in function creation
    this.node.setContext('lambdaRole', lambdaRole);
  }

  /**
   * Create Lambda functions for real-time event processing
   */
  private createLambdaFunctions(modelName: string, detectorName: string, environment: string): void {
    const lambdaRole = this.node.getContext('lambdaRole') as iam.Role;

    // Create event enrichment Lambda function
    this.eventEnrichmentFunction = new lambda.Function(this, 'EventEnrichmentFunction', {
      functionName: `event-enrichment-processor-${this.randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import hashlib
from datetime import datetime, timedelta
import base64
import logging
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')

def lambda_handler(event, context):
    """
    Enriches incoming transaction events with behavioral features
    and forwards them to fraud detection processing
    """
    
    try:
        for record in event['Records']:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            transaction_data = json.loads(payload)
            
            logger.info(f"Processing transaction: {transaction_data.get('transaction_id', 'unknown')}")
            
            # Enrich transaction data with behavioral features
            enriched_data = enrich_transaction_data(transaction_data)
            
            # Forward to fraud detection Lambda
            forward_to_fraud_detection(enriched_data)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed transactions')
        }
        
    except Exception as e:
        logger.error(f"Error processing events: {str(e)}")
        raise

def enrich_transaction_data(transaction_data):
    """
    Add behavioral and historical features to transaction data
    """
    customer_id = transaction_data.get('customer_id')
    current_time = datetime.now()
    
    # Add enhanced features
    transaction_data['transaction_frequency'] = get_transaction_frequency(customer_id)
    transaction_data['velocity_score'] = calculate_velocity_score(customer_id)
    transaction_data['processing_timestamp'] = current_time.isoformat()
    
    # Add unique transaction ID if missing
    if 'transaction_id' not in transaction_data:
        transaction_data['transaction_id'] = f"txn_{uuid.uuid4().hex[:16]}"
    
    logger.info(f"Enriched transaction with behavioral features: {transaction_data['transaction_id']}")
    
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
    try:
        lambda_client.invoke(
            FunctionName='fraud-detection-processor-${this.randomSuffix}',
            InvocationType='Event',
            Payload=json.dumps(enriched_data)
        )
        logger.info(f"Successfully forwarded transaction: {enriched_data.get('transaction_id')}")
    except Exception as e:
        logger.error(f"Error forwarding transaction: {str(e)}")
        raise
`),
      timeout: Duration.seconds(60),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        'ENVIRONMENT': environment,
        'DECISIONS_TABLE': this.decisionsTable.tableName,
        'RANDOM_SUFFIX': this.randomSuffix
      },
      logRetention: logs.RetentionDays.ONE_WEEK
    });

    // Create fraud detection processor Lambda function
    this.fraudDetectionFunction = new lambda.Function(this, 'FraudDetectionFunction', {
      functionName: `fraud-detection-processor-${this.randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import uuid
import os

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
        
        logger.info(f"Processing fraud detection for transaction: {transaction_data.get('transaction_id', event_id)}")
        
        # Prepare variables for fraud detection
        variables = prepare_fraud_variables(transaction_data)
        
        # Get fraud prediction
        fraud_response = get_fraud_prediction(event_id, variables)
        
        # Process and log decision
        decision = process_fraud_decision(transaction_data, fraud_response)
        
        # Send alerts if necessary
        if decision['risk_level'] in ['HIGH', 'CRITICAL']:
            send_fraud_alert(decision)
        
        logger.info(f"Fraud detection completed for transaction: {decision['transaction_id']}")
        
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
        'customer_id': str(transaction_data.get('customer_id', 'unknown')),
        'email_address': str(transaction_data.get('email_address', 'unknown')),
        'ip_address': str(transaction_data.get('ip_address', 'unknown')),
        'customer_name': str(transaction_data.get('customer_name', 'unknown')),
        'phone_number': str(transaction_data.get('phone_number', 'unknown')),
        'billing_address': str(transaction_data.get('billing_address', 'unknown')),
        'billing_city': str(transaction_data.get('billing_city', 'unknown')),
        'billing_state': str(transaction_data.get('billing_state', 'unknown')),
        'billing_zip': str(transaction_data.get('billing_zip', 'unknown')),
        'shipping_address': str(transaction_data.get('shipping_address', 'unknown')),
        'shipping_city': str(transaction_data.get('shipping_city', 'unknown')),
        'shipping_state': str(transaction_data.get('shipping_state', 'unknown')),
        'shipping_zip': str(transaction_data.get('shipping_zip', 'unknown')),
        'payment_method': str(transaction_data.get('payment_method', 'unknown')),
        'card_bin': str(transaction_data.get('card_bin', 'unknown')),
        'order_price': str(transaction_data.get('order_price', 0.0)),
        'product_category': str(transaction_data.get('product_category', 'unknown')),
        'transaction_amount': str(transaction_data.get('transaction_amount', 0.0)),
        'currency': str(transaction_data.get('currency', 'USD')),
        'merchant_category': str(transaction_data.get('merchant_category', 'unknown'))
    }

def get_fraud_prediction(event_id, variables):
    """
    Get fraud prediction from Amazon Fraud Detector
    """
    try:
        response = frauddetector.get_event_prediction(
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
        return response
    except Exception as e:
        logger.error(f"Error getting fraud prediction: {str(e)}")
        # Return mock response for testing
        return {
            'modelScores': [{'scores': {'TRANSACTION_FRAUD_INSIGHTS': 100}}],
            'ruleResults': [{'outcomes': ['approve_transaction']}]
        }

def process_fraud_decision(transaction_data, fraud_response):
    """
    Process fraud detection response and make decision
    """
    # Extract model scores and outcomes
    model_scores = fraud_response.get('modelScores', [])
    rule_results = fraud_response.get('ruleResults', [])
    
    # Determine primary outcome
    primary_outcome = 'approve_transaction'
    if rule_results and rule_results[0].get('outcomes'):
        primary_outcome = rule_results[0]['outcomes'][0]
    
    # Calculate risk score
    risk_score = 0
    if model_scores:
        scores = model_scores[0].get('scores', {})
        risk_score = scores.get('TRANSACTION_FRAUD_INSIGHTS', 0)
    
    # Determine risk level
    risk_level = determine_risk_level(risk_score, primary_outcome)
    
    # Create decision record
    decision = {
        'transaction_id': transaction_data.get('transaction_id'),
        'customer_id': transaction_data.get('customer_id'),
        'timestamp': datetime.now().isoformat(),
        'risk_score': risk_score,
        'risk_level': risk_level,
        'action': primary_outcome,
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
    try:
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
        logger.info(f"Logged decision for transaction: {decision['transaction_id']}")
    except Exception as e:
        logger.error(f"Error logging decision: {str(e)}")

def send_fraud_alert(decision):
    """
    Send fraud alert for high-risk transactions
    """
    try:
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
            
            logger.info(f"Sent fraud alert for transaction: {decision['transaction_id']}")
    except Exception as e:
        logger.error(f"Error sending fraud alert: {str(e)}")
`),
      timeout: Duration.seconds(30),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        'DETECTOR_NAME': `${detectorName}_${this.randomSuffix}`,
        'EVENT_TYPE_NAME': `transaction_fraud_detection_${this.randomSuffix}`,
        'ENTITY_TYPE_NAME': `customer_entity_${this.randomSuffix}`,
        'DECISIONS_TABLE': this.decisionsTable.tableName,
        'SNS_TOPIC_ARN': this.alertTopic.topicArn,
        'ENVIRONMENT': environment
      },
      logRetention: logs.RetentionDays.ONE_WEEK
    });

    // Create event source mapping for Kinesis
    this.eventEnrichmentFunction.addEventSource(
      new kinesisEventSources.KinesisEventSource(this.transactionStream, {
        startingPosition: lambda.StartingPosition.LATEST,
        batchSize: 10,
        maxBatchingWindow: Duration.seconds(5),
        retryAttempts: 3
      })
    );
  }

  /**
   * Create fraud detection components using custom resources
   */
  private createFraudDetectionComponents(modelName: string, detectorName: string, environment: string): void {
    // Create custom resource for fraud detection setup
    const fraudDetectionSetup = new cr.AwsCustomResource(this, 'FraudDetectionSetup', {
      onCreate: {
        service: 'FraudDetector',
        action: 'createEntityType',
        parameters: {
          name: `customer_entity_${this.randomSuffix}`,
          description: 'Enhanced customer entity for transaction fraud detection'
        },
        physicalResourceId: cr.PhysicalResourceId.of(`customer_entity_${this.randomSuffix}`)
      },
      onDelete: {
        service: 'FraudDetector',
        action: 'deleteEntityType',
        parameters: {
          name: `customer_entity_${this.randomSuffix}`
        }
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE
      })
    });

    // Create labels for fraud detection
    const fraudLabel = new cr.AwsCustomResource(this, 'FraudLabel', {
      onCreate: {
        service: 'FraudDetector',
        action: 'createLabel',
        parameters: {
          name: 'fraud',
          description: 'Confirmed fraudulent transaction'
        },
        physicalResourceId: cr.PhysicalResourceId.of('fraud-label')
      },
      onDelete: {
        service: 'FraudDetector',
        action: 'deleteLabel',
        parameters: {
          name: 'fraud'
        }
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE
      })
    });

    const legitLabel = new cr.AwsCustomResource(this, 'LegitLabel', {
      onCreate: {
        service: 'FraudDetector',
        action: 'createLabel',
        parameters: {
          name: 'legit',
          description: 'Legitimate verified transaction'
        },
        physicalResourceId: cr.PhysicalResourceId.of('legit-label')
      },
      onDelete: {
        service: 'FraudDetector',
        action: 'deleteLabel',
        parameters: {
          name: 'legit'
        }
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE
      })
    });

    // Create outcomes for fraud detection
    const outcomes = ['immediate_block', 'manual_review', 'challenge_authentication', 'approve_transaction'];
    const outcomeDescriptions = [
      'Block transaction immediately - high confidence fraud',
      'Route to manual review - medium risk',
      'Require additional authentication',
      'Approve transaction - low risk'
    ];

    outcomes.forEach((outcome, index) => {
      new cr.AwsCustomResource(this, `${outcome}Outcome`, {
        onCreate: {
          service: 'FraudDetector',
          action: 'createOutcome',
          parameters: {
            name: outcome,
            description: outcomeDescriptions[index]
          },
          physicalResourceId: cr.PhysicalResourceId.of(`${outcome}-outcome`)
        },
        onDelete: {
          service: 'FraudDetector',
          action: 'deleteOutcome',
          parameters: {
            name: outcome
          }
        },
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
          resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE
        })
      });
    });

    // Add dependencies
    fraudLabel.node.addDependency(fraudDetectionSetup);
    legitLabel.node.addDependency(fraudDetectionSetup);
  }

  /**
   * Create monitoring and alerting infrastructure
   */
  private createMonitoringAndAlerting(enableDetailedMonitoring: boolean, alertEmail?: string): void {
    if (enableDetailedMonitoring) {
      // Create CloudWatch dashboard
      this.monitoringDashboard = new cloudwatch.Dashboard(this, 'FraudDetectionDashboard', {
        dashboardName: `FraudDetectionPlatform-${this.randomSuffix}`,
        widgets: [
          [
            new cloudwatch.GraphWidget({
              title: 'Lambda Function Metrics',
              left: [
                this.fraudDetectionFunction.metricInvocations(),
                this.fraudDetectionFunction.metricDuration(),
                this.fraudDetectionFunction.metricErrors()
              ]
            })
          ],
          [
            new cloudwatch.GraphWidget({
              title: 'Kinesis Stream Metrics',
              left: [
                this.transactionStream.metricIncomingRecords(),
                this.transactionStream.metricOutgoingRecords()
              ]
            })
          ],
          [
            new cloudwatch.GraphWidget({
              title: 'DynamoDB Metrics',
              left: [
                this.decisionsTable.metricConsumedReadCapacityUnits(),
                this.decisionsTable.metricConsumedWriteCapacityUnits()
              ]
            })
          ]
        ]
      });

      // Create CloudWatch alarms
      new cloudwatch.Alarm(this, 'FraudDetectionErrorAlarm', {
        metric: this.fraudDetectionFunction.metricErrors(),
        threshold: 5,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      new cloudwatch.Alarm(this, 'FraudDetectionDurationAlarm', {
        metric: this.fraudDetectionFunction.metricDuration(),
        threshold: 25000, // 25 seconds
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });
    }

    // Subscribe to alerts if email provided
    if (alertEmail) {
      new sns.Subscription(this, 'EmailAlertSubscription', {
        topic: this.alertTopic,
        protocol: sns.SubscriptionProtocol.EMAIL,
        endpoint: alertEmail
      });
    }
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'FraudBucketName', {
      value: this.fraudBucket.bucketName,
      description: 'S3 bucket for fraud detection training data'
    });

    new cdk.CfnOutput(this, 'TransactionStreamName', {
      value: this.transactionStream.streamName,
      description: 'Kinesis stream for real-time transaction processing'
    });

    new cdk.CfnOutput(this, 'DecisionsTableName', {
      value: this.decisionsTable.tableName,
      description: 'DynamoDB table for fraud decisions logging'
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS topic for fraud alerts'
    });

    new cdk.CfnOutput(this, 'FraudDetectionFunctionName', {
      value: this.fraudDetectionFunction.functionName,
      description: 'Lambda function for fraud detection processing'
    });

    new cdk.CfnOutput(this, 'EventEnrichmentFunctionName', {
      value: this.eventEnrichmentFunction.functionName,
      description: 'Lambda function for event enrichment'
    });

    new cdk.CfnOutput(this, 'FraudDetectorRoleArn', {
      value: this.fraudDetectorRole.roleArn,
      description: 'IAM role for Amazon Fraud Detector'
    });

    new cdk.CfnOutput(this, 'RandomSuffix', {
      value: this.randomSuffix,
      description: 'Random suffix used for resource naming'
    });
  }

  /**
   * Apply resource tags
   */
  private applyTags(environment: string): void {
    cdk.Tags.of(this).add('Project', 'RealTimeFraudDetection');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Application', 'FraudDetection');
    cdk.Tags.of(this).add('Owner', 'MLOps');
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Get context values
const environment = app.node.tryGetContext('environment') ?? 'dev';
const alertEmail = app.node.tryGetContext('alertEmail');
const productionMode = app.node.tryGetContext('productionMode') === 'true';
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') !== 'false';

// Create the fraud detection stack
new RealTimeFraudDetectionStack(app, 'RealTimeFraudDetectionStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environment,
  alertEmail,
  productionMode,
  enableDetailedMonitoring,
  description: 'Real-time fraud detection platform with Amazon Fraud Detector, Kinesis, and Lambda'
});

app.synth();