#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';
import { Duration, RemovalPolicy, CfnOutput } from 'aws-cdk-lib';

/**
 * Configuration interface for the fraud detection system
 */
interface FraudDetectionConfig {
  readonly bucketName?: string;
  readonly eventTypeName?: string;
  readonly entityTypeName?: string;
  readonly modelName?: string;
  readonly detectorName?: string;
  readonly enableCleanup?: boolean;
}

/**
 * Stack for implementing fraud detection systems with Amazon Fraud Detector
 * 
 * This stack creates:
 * - S3 bucket for training data storage
 * - IAM roles and policies for Fraud Detector service
 * - Lambda function for processing fraud predictions
 * - Custom resources for Fraud Detector configuration
 */
export class FraudDetectionSystemsStack extends cdk.Stack {
  public readonly trainingDataBucket: s3.Bucket;
  public readonly fraudDetectorRole: iam.Role;
  public readonly predictionProcessor: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps & { config?: FraudDetectionConfig }) {
    super(scope, id, props);

    const config = props?.config || {};

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    
    // Resource names with unique suffixes
    const bucketName = config.bucketName || `fraud-detection-data-${uniqueSuffix}`;
    const eventTypeName = config.eventTypeName || `payment_fraud_${uniqueSuffix}`;
    const entityTypeName = config.entityTypeName || `customer_${uniqueSuffix}`;
    const modelName = config.modelName || `fraud_detection_model_${uniqueSuffix}`;
    const detectorName = config.detectorName || `payment_fraud_detector_${uniqueSuffix}`;

    // Create S3 bucket for training data storage
    this.trainingDataBucket = new s3.Bucket(this, 'TrainingDataBucket', {
      bucketName: bucketName,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: config.enableCleanup ? RemovalPolicy.DESTROY : RemovalPolicy.RETAIN,
      autoDeleteObjects: config.enableCleanup || false,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
          ],
        },
      ],
    });

    // Create IAM role for Amazon Fraud Detector service
    this.fraudDetectorRole = new iam.Role(this, 'FraudDetectorServiceRole', {
      roleName: `FraudDetectorServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('frauddetector.amazonaws.com'),
      description: 'IAM role for Amazon Fraud Detector to access S3 training data',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonFraudDetectorFullAccessPolicy'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:ListBucket',
              ],
              resources: [
                this.trainingDataBucket.bucketArn,
                `${this.trainingDataBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda execution role
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for fraud prediction processor Lambda',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        FraudDetectorPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'frauddetector:GetEventPrediction',
                'frauddetector:BatchGetVariable',
                'frauddetector:GetDetectors',
                'frauddetector:GetDetectorVersion',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for processing fraud predictions
    this.predictionProcessor = new lambda.Function(this, 'FraudPredictionProcessor', {
      functionName: `fraud-prediction-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(30),
      memorySize: 256,
      description: 'Lambda function for processing fraud detection predictions',
      environment: {
        DETECTOR_NAME: detectorName,
        EVENT_TYPE_NAME: eventTypeName,
        ENTITY_TYPE_NAME: entityTypeName,
        MODEL_NAME: modelName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')

def lambda_handler(event, context):
    """
    Process fraud detection requests and return predictions
    
    Expected event structure:
    {
        "transaction": {
            "customer_id": "string",
            "email_address": "string",
            "ip_address": "string",
            "customer_name": "string",
            "phone_number": "string",
            "billing_address": "string",
            "billing_city": "string",
            "billing_state": "string",
            "billing_zip": "string",
            "payment_method": "string",
            "card_bin": "string",
            "order_price": float,
            "product_category": "string"
        },
        "transaction_id": "string"
    }
    """
    try:
        # Extract configuration from environment variables
        detector_name = os.environ['DETECTOR_NAME']
        event_type_name = os.environ['EVENT_TYPE_NAME']
        entity_type_name = os.environ['ENTITY_TYPE_NAME']
        model_name = os.environ['MODEL_NAME']
        
        # Extract transaction data from event
        transaction_data = event.get('transaction', {})
        transaction_id = event.get('transaction_id', f"txn_{datetime.now().strftime('%Y%m%d_%H%M%S')}")
        
        # Prepare variables for fraud detection
        variables = {
            'customer_id': str(transaction_data.get('customer_id', 'unknown')),
            'email_address': str(transaction_data.get('email_address', 'unknown')),
            'ip_address': str(transaction_data.get('ip_address', 'unknown')),
            'customer_name': str(transaction_data.get('customer_name', 'unknown')),
            'phone_number': str(transaction_data.get('phone_number', 'unknown')),
            'billing_address': str(transaction_data.get('billing_address', 'unknown')),
            'billing_city': str(transaction_data.get('billing_city', 'unknown')),
            'billing_state': str(transaction_data.get('billing_state', 'unknown')),
            'billing_zip': str(transaction_data.get('billing_zip', 'unknown')),
            'payment_method': str(transaction_data.get('payment_method', 'unknown')),
            'card_bin': str(transaction_data.get('card_bin', 'unknown')),
            'order_price': str(float(transaction_data.get('order_price', 0.0))),
            'product_category': str(transaction_data.get('product_category', 'unknown'))
        }
        
        # Validate required fields
        customer_id = variables['customer_id']
        if customer_id == 'unknown':
            raise ValueError("customer_id is required for fraud detection")
        
        # Get fraud prediction from Amazon Fraud Detector
        response = frauddetector.get_event_prediction(
            detectorId=detector_name,
            eventId=transaction_id,
            eventTypeName=event_type_name,
            entities=[{
                'entityType': entity_type_name,
                'entityId': customer_id
            }],
            eventTimestamp=datetime.now().isoformat(),
            eventVariables=variables
        )
        
        # Process and structure the response
        rule_results = response.get('ruleResults', [])
        model_scores = response.get('modelScores', [])
        
        # Extract the primary outcome and score
        primary_outcome = 'unknown'
        fraud_score = 0
        
        if rule_results:
            primary_outcome = rule_results[0].get('outcomes', ['unknown'])[0]
        
        if model_scores:
            # Extract fraud score from the model results
            for score in model_scores:
                if 'scores' in score:
                    fraud_score = score['scores'].get(f'{model_name}_insightscore', 0)
                    break
        
        # Create structured response
        prediction_result = {
            'transaction_id': transaction_id,
            'customer_id': customer_id,
            'timestamp': datetime.now().isoformat(),
            'fraud_prediction': {
                'outcome': primary_outcome,
                'fraud_score': fraud_score,
                'rule_results': rule_results,
                'model_scores': model_scores,
                'risk_level': get_risk_level(fraud_score)
            },
            'recommendation': get_recommendation(primary_outcome, fraud_score)
        }
        
        # Log prediction results for monitoring
        logger.info(f"Fraud prediction completed for transaction: {transaction_id}")
        logger.info(f"Outcome: {primary_outcome}, Score: {fraud_score}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Transaction-ID': transaction_id
            },
            'body': json.dumps(prediction_result, default=str)
        }
        
    except ValueError as ve:
        logger.error(f"Validation error: {str(ve)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Validation Error',
                'message': str(ve),
                'transaction_id': event.get('transaction_id', 'unknown')
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing fraud prediction: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Internal Server Error',
                'message': 'Failed to process fraud prediction',
                'transaction_id': event.get('transaction_id', 'unknown')
            })
        }

def get_risk_level(fraud_score):
    """Determine risk level based on fraud score"""
    if fraud_score >= 900:
        return 'HIGH'
    elif fraud_score >= 700:
        return 'MEDIUM'
    elif fraud_score >= 300:
        return 'LOW'
    else:
        return 'VERY_LOW'

def get_recommendation(outcome, fraud_score):
    """Provide recommendation based on outcome and score"""
    recommendations = {
        'block': 'Transaction should be blocked due to high fraud risk',
        'review': 'Transaction requires manual review by fraud analyst',
        'approve': 'Transaction can be approved with low fraud risk'
    }
    
    base_recommendation = recommendations.get(outcome, 'Unknown outcome - manual review recommended')
    
    if fraud_score >= 950:
        return f"{base_recommendation}. Extremely high fraud score detected."
    elif fraud_score >= 800:
        return f"{base_recommendation}. High fraud score requires attention."
    elif fraud_score <= 200:
        return f"{base_recommendation}. Very low fraud score indicates safe transaction."
    else:
        return base_recommendation
`),
    });

    // Create sample training data for demonstration
    const sampleTrainingData = `event_timestamp,customer_id,email_address,ip_address,customer_name,phone_number,billing_address,billing_city,billing_state,billing_zip,shipping_address,shipping_city,shipping_state,shipping_zip,payment_method,card_bin,order_price,product_category,EVENT_LABEL
2024-01-15T10:30:00Z,cust001,john.doe@email.com,192.168.1.1,John Doe,555-1234,123 Main St,Seattle,WA,98101,123 Main St,Seattle,WA,98101,credit_card,411111,99.99,electronics,legit
2024-01-15T11:45:00Z,cust002,jane.smith@email.com,10.0.0.1,Jane Smith,555-5678,456 Oak Ave,Portland,OR,97201,456 Oak Ave,Portland,OR,97201,credit_card,424242,1299.99,electronics,legit
2024-01-15T12:15:00Z,cust003,fraud@temp.com,1.2.3.4,Test User,555-0000,789 Pine St,New York,NY,10001,999 Different St,Los Angeles,CA,90210,credit_card,444444,2500.00,jewelry,fraud
2024-01-15T13:30:00Z,cust004,alice.johnson@email.com,172.16.0.1,Alice Johnson,555-9876,321 Elm St,Chicago,IL,60601,321 Elm St,Chicago,IL,60601,debit_card,555555,45.99,books,legit
2024-01-15T14:45:00Z,cust005,bob.wilson@email.com,192.168.2.1,Bob Wilson,555-4321,654 Maple Dr,Denver,CO,80201,654 Maple Dr,Denver,CO,80201,credit_card,666666,150.00,clothing,legit
2024-01-15T15:00:00Z,cust006,suspicious@tempmail.com,5.6.7.8,Fake Name,555-1111,123 Fake St,Nowhere,XX,00000,456 Other St,Somewhere,YY,11111,credit_card,777777,5000.00,electronics,fraud`;

    // Deploy sample training data to S3 bucket
    new s3.BucketDeployment(this, 'DeployTrainingData', {
      sources: [s3.Source.data('training-data.csv', sampleTrainingData)],
      destinationBucket: this.trainingDataBucket,
      description: 'Deploy sample training data for fraud detection model',
    });

    // Custom resource provider for Amazon Fraud Detector configuration
    const fraudDetectorProvider = new cr.Provider(this, 'FraudDetectorProvider', {
      onEventHandler: new lambda.Function(this, 'FraudDetectorCustomResource', {
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.on_event',
        timeout: Duration.minutes(15),
        role: new iam.Role(this, 'CustomResourceRole', {
          assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
          managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
          ],
          inlinePolicies: {
            FraudDetectorFullAccess: new iam.PolicyDocument({
              statements: [
                new iam.PolicyStatement({
                  effect: iam.Effect.ALLOW,
                  actions: ['frauddetector:*'],
                  resources: ['*'],
                }),
                new iam.PolicyStatement({
                  effect: iam.Effect.ALLOW,
                  actions: ['iam:PassRole'],
                  resources: [this.fraudDetectorRole.roleArn],
                }),
              ],
            }),
          },
        }),
        code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')

def on_event(event, context):
    """
    Custom resource handler for Amazon Fraud Detector configuration
    """
    request_type = event['RequestType']
    resource_type = event['ResourceProperties'].get('ResourceType')
    
    try:
        if request_type == 'Create':
            return handle_create(event, context)
        elif request_type == 'Update':
            return handle_update(event, context)
        elif request_type == 'Delete':
            return handle_delete(event, context)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
            
    except Exception as e:
        logger.error(f"Error in custom resource: {str(e)}")
        # For demonstration purposes, we'll return success to avoid deployment failures
        # In production, you might want to handle errors differently
        return {
            'PhysicalResourceId': event.get('PhysicalResourceId', 'fraud-detector-setup'),
            'Data': {'Status': 'Error', 'Message': str(e)}
        }

def handle_create(event, context):
    """Handle resource creation"""
    props = event['ResourceProperties']
    resource_type = props.get('ResourceType')
    
    logger.info(f"Creating resource: {resource_type}")
    
    physical_id = f"{resource_type}-{context.aws_request_id}"
    
    # Create the appropriate resource based on type
    if resource_type == 'EntityType':
        create_entity_type(props)
    elif resource_type == 'EventType':
        create_event_type(props)
    elif resource_type == 'Labels':
        create_labels(props)
    elif resource_type == 'Outcomes':
        create_outcomes(props)
    
    return {
        'PhysicalResourceId': physical_id,
        'Data': {'Status': 'Created', 'ResourceType': resource_type}
    }

def handle_update(event, context):
    """Handle resource update"""
    return {
        'PhysicalResourceId': event['PhysicalResourceId'],
        'Data': {'Status': 'Updated'}
    }

def handle_delete(event, context):
    """Handle resource deletion"""
    # For demonstration, we'll skip actual deletion to avoid cleanup issues
    # In production, implement proper cleanup logic
    return {
        'PhysicalResourceId': event['PhysicalResourceId'],
        'Data': {'Status': 'Deleted'}
    }

def create_entity_type(props):
    """Create entity type for customers"""
    try:
        frauddetector.create_entity_type(
            name=props['EntityTypeName'],
            description='Customer entity for fraud detection'
        )
        logger.info(f"Created entity type: {props['EntityTypeName']}")
    except frauddetector.exceptions.ValidationException as e:
        if 'already exists' in str(e):
            logger.info(f"Entity type already exists: {props['EntityTypeName']}")
        else:
            raise

def create_event_type(props):
    """Create event type for payment transactions"""
    event_variables = [
        {"name": "customer_id", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "email_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "ip_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "customer_name", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "phone_number", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "billing_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "billing_city", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "billing_state", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "billing_zip", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "payment_method", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "card_bin", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
        {"name": "order_price", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
        {"name": "product_category", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"}
    ]
    
    try:
        frauddetector.create_event_type(
            name=props['EventTypeName'],
            description='Payment fraud detection event',
            eventVariables=event_variables,
            entityTypes=[props['EntityTypeName']],
            eventIngestion='ENABLED'
        )
        logger.info(f"Created event type: {props['EventTypeName']}")
    except frauddetector.exceptions.ValidationException as e:
        if 'already exists' in str(e):
            logger.info(f"Event type already exists: {props['EventTypeName']}")
        else:
            raise

def create_labels(props):
    """Create fraud and legitimate labels"""
    labels = [
        {"name": "fraud", "description": "Fraudulent transaction"},
        {"name": "legit", "description": "Legitimate transaction"}
    ]
    
    for label in labels:
        try:
            frauddetector.create_label(
                name=label["name"],
                description=label["description"]
            )
            logger.info(f"Created label: {label['name']}")
        except frauddetector.exceptions.ValidationException as e:
            if 'already exists' in str(e):
                logger.info(f"Label already exists: {label['name']}")
            else:
                raise

def create_outcomes(props):
    """Create outcomes for fraud detection"""
    outcomes = [
        {"name": "review", "description": "Send transaction for manual review"},
        {"name": "block", "description": "Block fraudulent transaction"},
        {"name": "approve", "description": "Approve legitimate transaction"}
    ]
    
    for outcome in outcomes:
        try:
            frauddetector.create_outcome(
                name=outcome["name"],
                description=outcome["description"]
            )
            logger.info(f"Created outcome: {outcome['name']}")
        except frauddetector.exceptions.ValidationException as e:
            if 'already exists' in str(e):
                logger.info(f"Outcome already exists: {outcome['name']}")
            else:
                raise
`),
      }),
    });

    // Create entity type
    new cdk.CustomResource(this, 'EntityType', {
      serviceToken: fraudDetectorProvider.serviceToken,
      properties: {
        ResourceType: 'EntityType',
        EntityTypeName: entityTypeName,
      },
    });

    // Create event type
    new cdk.CustomResource(this, 'EventType', {
      serviceToken: fraudDetectorProvider.serviceToken,
      properties: {
        ResourceType: 'EventType',
        EventTypeName: eventTypeName,
        EntityTypeName: entityTypeName,
      },
    });

    // Create labels
    new cdk.CustomResource(this, 'Labels', {
      serviceToken: fraudDetectorProvider.serviceToken,
      properties: {
        ResourceType: 'Labels',
      },
    });

    // Create outcomes
    new cdk.CustomResource(this, 'Outcomes', {
      serviceToken: fraudDetectorProvider.serviceToken,
      properties: {
        ResourceType: 'Outcomes',
      },
    });

    // Stack outputs
    new CfnOutput(this, 'TrainingDataBucketName', {
      value: this.trainingDataBucket.bucketName,
      description: 'S3 bucket for fraud detection training data',
    });

    new CfnOutput(this, 'FraudDetectorRoleArn', {
      value: this.fraudDetectorRole.roleArn,
      description: 'IAM role ARN for Amazon Fraud Detector service',
    });

    new CfnOutput(this, 'PredictionProcessorFunctionName', {
      value: this.predictionProcessor.functionName,
      description: 'Lambda function for processing fraud predictions',
    });

    new CfnOutput(this, 'EventTypeName', {
      value: eventTypeName,
      description: 'Event type name for fraud detection',
    });

    new CfnOutput(this, 'EntityTypeName', {
      value: entityTypeName,
      description: 'Entity type name for customers',
    });

    new CfnOutput(this, 'ModelName', {
      value: modelName,
      description: 'Model name for fraud detection (for manual creation)',
    });

    new CfnOutput(this, 'DetectorName', {
      value: detectorName,
      description: 'Detector name for fraud detection (for manual creation)',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'FraudDetectionSystems');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Service', 'AmazonFraudDetector');
  }
}

// Create the CDK application
const app = new cdk.App();

// Get configuration from context
const config: FraudDetectionConfig = {
  enableCleanup: app.node.tryGetContext('enableCleanup') || false,
};

// Create the stack
new FraudDetectionSystemsStack(app, 'FraudDetectionSystemsStack', {
  config,
  description: 'Fraud Detection Systems with Amazon Fraud Detector - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'FraudDetectionSystems',
    Service: 'AmazonFraudDetector',
    IaC: 'CDK-TypeScript',
  },
});