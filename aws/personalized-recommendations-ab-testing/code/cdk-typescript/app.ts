#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy, CfnOutput } from 'aws-cdk-lib';

/**
 * Stack for implementing real-time recommendations with Amazon Personalize and A/B testing
 * 
 * This stack creates:
 * - DynamoDB tables for user profiles, items, A/B assignments, and events
 * - Lambda functions for A/B testing, recommendations, event tracking, and Personalize management
 * - API Gateway for REST endpoints
 * - S3 bucket for training data storage
 * - IAM roles with appropriate permissions
 * - Kinesis stream for real-time analytics
 * - CloudWatch dashboard for monitoring
 */
export class PersonalizeABTestingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = `personalize-ab-${uniqueSuffix}`;

    // ========================================
    // S3 Bucket for Training Data
    // ========================================
    const trainingDataBucket = new s3.Bucket(this, 'TrainingDataBucket', {
      bucketName: `${projectName}-training-data`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    });

    // ========================================
    // DynamoDB Tables
    // ========================================

    // User profiles table
    const usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: `${projectName}-users`,
      partitionKey: { name: 'UserId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Items catalog table with GSI for category lookups
    const itemsTable = new dynamodb.Table(this, 'ItemsTable', {
      tableName: `${projectName}-items`,
      partitionKey: { name: 'ItemId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add Global Secondary Index for category-based queries
    itemsTable.addGlobalSecondaryIndex({
      indexName: 'CategoryIndex',
      partitionKey: { name: 'Category', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // A/B test assignments table
    const abAssignmentsTable = new dynamodb.Table(this, 'ABAssignmentsTable', {
      tableName: `${projectName}-ab-assignments`,
      partitionKey: { name: 'UserId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'TestName', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Events table for real-time tracking
    const eventsTable = new dynamodb.Table(this, 'EventsTable', {
      tableName: `${projectName}-events`,
      partitionKey: { name: 'UserId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'Timestamp', type: dynamodb.AttributeType.NUMBER },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // ========================================
    // Kinesis Data Stream for Analytics
    // ========================================
    const analyticsStream = new kinesis.Stream(this, 'AnalyticsStream', {
      streamName: `${projectName}-analytics`,
      shardCount: 2,
      retention: Duration.days(7),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // ========================================
    // IAM Roles
    // ========================================

    // Role for Personalize service
    const personalizeRole = new iam.Role(this, 'PersonalizeRole', {
      roleName: `${projectName}-personalize-role`,
      assumedBy: new iam.ServicePrincipal('personalize.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonPersonalizeFullAccess'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject', 's3:ListBucket'],
              resources: [
                trainingDataBucket.bucketArn,
                `${trainingDataBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DynamoDBAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [
                usersTable.tableArn,
                itemsTable.tableArn,
                abAssignmentsTable.tableArn,
                eventsTable.tableArn,
                `${itemsTable.tableArn}/index/*`,
              ],
            }),
          ],
        }),
        PersonalizeAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'personalize:GetRecommendations',
                'personalize:PutEvents',
                'personalize:DescribeCampaign',
                'personalize:DescribeSolution',
                'personalize:DescribeDatasetImportJob',
                'personalize:CreateDatasetGroup',
                'personalize:CreateDataset',
                'personalize:CreateDatasetImportJob',
                'personalize:CreateSolution',
                'personalize:CreateSolutionVersion',
                'personalize:CreateCampaign',
                'personalize:CreateEventTracker',
              ],
              resources: ['*'],
            }),
          ],
        }),
        KinesisAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['kinesis:PutRecord', 'kinesis:PutRecords'],
              resources: [analyticsStream.streamArn],
            }),
          ],
        }),
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject', 's3:ListBucket'],
              resources: [
                trainingDataBucket.bucketArn,
                `${trainingDataBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // ========================================
    // Lambda Functions
    // ========================================

    // A/B Test Router Lambda
    const abTestRouterFunction = new lambda.Function(this, 'ABTestRouterFunction', {
      functionName: `${projectName}-ab-test-router`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        AB_ASSIGNMENTS_TABLE: abAssignmentsTable.tableName,
        PROJECT_NAME: projectName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import hashlib
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse request body if it's a string
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', event)
        
        user_id = body.get('user_id')
        test_name = body.get('test_name', 'default_recommendation_test')
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'user_id is required'})
            }
        
        # Get or assign A/B test variant
        variant = get_or_assign_variant(user_id, test_name)
        
        # Get recommendation model configuration for variant
        model_config = get_model_config(variant)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'user_id': user_id,
                'test_name': test_name,
                'variant': variant,
                'model_config': model_config
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_or_assign_variant(user_id, test_name):
    table = dynamodb.Table(os.environ['AB_ASSIGNMENTS_TABLE'])
    
    try:
        # Check if user already has assignment
        response = table.get_item(
            Key={'UserId': user_id, 'TestName': test_name}
        )
        
        if 'Item' in response:
            return response['Item']['Variant']
        
    except Exception:
        pass
    
    # Assign new variant using consistent hashing
    variant = assign_variant(user_id, test_name)
    
    # Store assignment
    table.put_item(
        Item={
            'UserId': user_id,
            'TestName': test_name,
            'Variant': variant,
            'AssignmentTimestamp': int(datetime.now().timestamp())
        }
    )
    
    return variant

def assign_variant(user_id, test_name):
    # Use consistent hashing for stable assignment
    hash_input = f"{user_id}-{test_name}".encode('utf-8')
    hash_value = int(hashlib.md5(hash_input).hexdigest(), 16)
    
    # Define test configuration
    test_config = {
        'default_recommendation_test': {
            'variant_a': 0.33,  # User-Personalization
            'variant_b': 0.33,  # Similar-Items  
            'variant_c': 0.34   # Popularity-Count
        }
    }
    
    config = test_config.get(test_name, test_config['default_recommendation_test'])
    
    # Determine variant based on hash
    normalized_hash = (hash_value % 10000) / 10000.0
    
    cumulative = 0
    for variant, probability in config.items():
        cumulative += probability
        if normalized_hash <= cumulative:
            return variant
    
    return 'variant_a'  # Fallback

def get_model_config(variant):
    # Configuration for each variant
    configs = {
        'variant_a': {
            'recipe': 'aws-user-personalization',
            'campaign_arn': os.environ.get('CAMPAIGN_A_ARN', ''),
            'description': 'User-Personalization Algorithm'
        },
        'variant_b': {
            'recipe': 'aws-sims',
            'campaign_arn': os.environ.get('CAMPAIGN_B_ARN', ''),
            'description': 'Item-to-Item Similarity Algorithm'
        },
        'variant_c': {
            'recipe': 'aws-popularity-count',
            'campaign_arn': os.environ.get('CAMPAIGN_C_ARN', ''),
            'description': 'Popularity-Based Algorithm'
        }
    }
    
    return configs.get(variant, configs['variant_a'])
      `),
    });

    // Recommendation Engine Lambda
    const recommendationEngineFunction = new lambda.Function(this, 'RecommendationEngineFunction', {
      functionName: `${projectName}-recommendation-engine`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(30),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        ITEMS_TABLE: itemsTable.tableName,
        EVENTS_TABLE: eventsTable.tableName,
        PROJECT_NAME: projectName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

personalize_runtime = boto3.client('personalize-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse request body if it's a string
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', event)
        
        user_id = body.get('user_id')
        model_config = body.get('model_config', {})
        num_results = body.get('num_results', 10)
        context_data = body.get('context', {})
        
        if not user_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'user_id is required'})
            }
        
        try:
            # Get recommendations from Personalize
            recommendations = get_personalize_recommendations(
                user_id, model_config, num_results, context_data
            )
            
            # Enrich recommendations with item metadata
            enriched_recommendations = enrich_recommendations(recommendations)
            
            # Track recommendation request
            track_recommendation_request(user_id, model_config, enriched_recommendations)
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user_id': user_id,
                    'recommendations': enriched_recommendations,
                    'algorithm': model_config.get('description', 'Unknown'),
                    'timestamp': datetime.now().isoformat()
                })
            }
            
        except Exception as e:
            # Fallback to popularity-based recommendations
            fallback_recommendations = get_fallback_recommendations(num_results)
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'user_id': user_id,
                    'recommendations': fallback_recommendations,
                    'algorithm': 'Fallback - Popularity Based',
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                })
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_personalize_recommendations(user_id, model_config, num_results, context_data):
    campaign_arn = model_config.get('campaign_arn')
    
    if not campaign_arn:
        raise ValueError("No campaign ARN provided")
    
    # Build request parameters
    request_params = {
        'campaignArn': campaign_arn,
        'userId': user_id,
        'numResults': num_results
    }
    
    # Add context if provided
    if context_data:
        request_params['context'] = context_data
    
    # Get recommendations from Personalize
    response = personalize_runtime.get_recommendations(**request_params)
    
    return response['itemList']

def enrich_recommendations(recommendations):
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    enriched = []
    for item in recommendations:
        item_id = item['itemId']
        
        try:
            # Get item metadata from DynamoDB
            response = items_table.get_item(Key={'ItemId': item_id})
            
            if 'Item' in response:
                item_data = response['Item']
                enriched.append({
                    'item_id': item_id,
                    'score': item.get('score', 0),
                    'category': item_data.get('Category', 'Unknown'),
                    'price': float(item_data.get('Price', 0)),
                    'brand': item_data.get('Brand', 'Unknown')
                })
            else:
                # Item not found in catalog
                enriched.append({
                    'item_id': item_id,
                    'score': item.get('score', 0),
                    'category': 'Unknown',
                    'price': 0,
                    'brand': 'Unknown'
                })
                
        except Exception as e:
            print(f"Error enriching item {item_id}: {str(e)}")
            enriched.append({
                'item_id': item_id,
                'score': item.get('score', 0),
                'error': str(e)
            })
    
    return enriched

def get_fallback_recommendations(num_results):
    # Simple fallback - return popular items by category
    items_table = dynamodb.Table(os.environ['ITEMS_TABLE'])
    
    try:
        # Scan for items (in production, use a better method)
        response = items_table.scan(Limit=num_results)
        items = response.get('Items', [])
        
        fallback = []
        for item in items:
            fallback.append({
                'item_id': item['ItemId'],
                'score': 0.5,  # Default score for fallback
                'category': item.get('Category', 'Unknown'),
                'price': float(item.get('Price', 0)),
                'brand': item.get('Brand', 'Unknown')
            })
        
        return fallback
        
    except Exception:
        return []

def track_recommendation_request(user_id, model_config, recommendations):
    # Track recommendation serving for analytics
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    try:
        events_table.put_item(
            Item={
                'UserId': user_id,
                'Timestamp': int(datetime.now().timestamp() * 1000),
                'EventType': 'recommendation_served',
                'Algorithm': model_config.get('description', 'Unknown'),
                'ItemCount': len(recommendations),
                'Items': json.dumps([r['item_id'] for r in recommendations])
            }
        )
    except Exception as e:
        print(f"Failed to track recommendation request: {str(e)}")
      `),
    });

    // Event Tracking Lambda
    const eventTrackerFunction = new lambda.Function(this, 'EventTrackerFunction', {
      functionName: `${projectName}-event-tracker`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        EVENTS_TABLE: eventsTable.tableName,
        ANALYTICS_STREAM: analyticsStream.streamName,
        PROJECT_NAME: projectName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

personalize_events = boto3.client('personalize-events')
dynamodb = boto3.resource('dynamodb')
kinesis = boto3.client('kinesis')

def lambda_handler(event, context):
    try:
        # Parse request body if it's a string
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', event)
        
        # Parse event data
        user_id = body.get('user_id')
        session_id = body.get('session_id', user_id)
        event_type = body.get('event_type')
        item_id = body.get('item_id')
        recommendation_id = body.get('recommendation_id')
        properties = body.get('properties', {})
        
        if not all([user_id, event_type]):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'user_id and event_type are required'})
            }
        
        # Store event in DynamoDB for analytics
        store_event_analytics(body)
        
        # Send event to Kinesis for real-time analytics
        send_to_kinesis(body)
        
        # Send event to Personalize (if real-time tracking is enabled)
        if os.environ.get('EVENT_TRACKER_ARN') and item_id:
            send_to_personalize(user_id, session_id, event_type, item_id, properties)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'message': 'Event tracked successfully'})
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def store_event_analytics(event):
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    # Store detailed event for analytics
    events_table.put_item(
        Item={
            'UserId': event['user_id'],
            'Timestamp': int(datetime.now().timestamp() * 1000),
            'EventType': event['event_type'],
            'ItemId': event.get('item_id', ''),
            'SessionId': event.get('session_id', ''),
            'RecommendationId': event.get('recommendation_id', ''),
            'Properties': json.dumps(event.get('properties', {}))
        }
    )

def send_to_kinesis(event):
    # Send event to Kinesis for real-time analytics
    try:
        kinesis.put_record(
            StreamName=os.environ['ANALYTICS_STREAM'],
            Data=json.dumps(event),
            PartitionKey=event['user_id']
        )
    except Exception as e:
        print(f"Failed to send event to Kinesis: {str(e)}")

def send_to_personalize(user_id, session_id, event_type, item_id, properties):
    event_tracker_arn = os.environ.get('EVENT_TRACKER_ARN')
    
    if not event_tracker_arn:
        return
    
    # Prepare event for Personalize
    personalize_event = {
        'userId': user_id,
        'sessionId': session_id,
        'eventType': event_type,
        'sentAt': datetime.now().timestamp()
    }
    
    if item_id:
        personalize_event['itemId'] = item_id
    
    if properties:
        personalize_event['properties'] = json.dumps(properties)
    
    # Send to Personalize
    try:
        personalize_events.put_events(
            trackingId=event_tracker_arn.split('/')[-1],
            userId=user_id,
            sessionId=session_id,
            eventList=[personalize_event]
        )
    except Exception as e:
        print(f"Failed to send event to Personalize: {str(e)}")
      `),
    });

    // Personalize Management Lambda
    const personalizeManagerFunction = new lambda.Function(this, 'PersonalizeManagerFunction', {
      functionName: `${projectName}-personalize-manager`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(60),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        PROJECT_NAME: projectName,
        PERSONALIZE_ROLE_ARN: personalizeRole.roleArn,
        TRAINING_DATA_BUCKET: trainingDataBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

personalize = boto3.client('personalize')

def lambda_handler(event, context):
    action = event.get('action')
    
    try:
        if action == 'create_dataset_group':
            return create_dataset_group(event)
        elif action == 'import_data':
            return import_data(event)
        elif action == 'create_solution':
            return create_solution(event)
        elif action == 'create_campaign':
            return create_campaign(event)
        elif action == 'check_status':
            return check_status(event)
        else:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def create_dataset_group(event):
    dataset_group_name = event.get('dataset_group_name', f"{os.environ['PROJECT_NAME']}-dataset-group")
    
    response = personalize.create_dataset_group(
        name=dataset_group_name,
        domain='ECOMMERCE'  # or VIDEO_ON_DEMAND
    )
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'dataset_group_arn': response['datasetGroupArn']
        })
    }

def import_data(event):
    dataset_arn = event['dataset_arn']
    job_name = event['job_name']
    s3_data_source = event['s3_data_source']
    role_arn = event.get('role_arn', os.environ['PERSONALIZE_ROLE_ARN'])
    
    response = personalize.create_dataset_import_job(
        jobName=job_name,
        datasetArn=dataset_arn,
        dataSource={
            's3DataSource': {
                'path': s3_data_source
            }
        },
        roleArn=role_arn
    )
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'dataset_import_job_arn': response['datasetImportJobArn']
        })
    }

def create_solution(event):
    solution_name = event['solution_name']
    dataset_group_arn = event['dataset_group_arn']
    recipe_arn = event['recipe_arn']
    
    response = personalize.create_solution(
        name=solution_name,
        datasetGroupArn=dataset_group_arn,
        recipeArn=recipe_arn
    )
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'solution_arn': response['solutionArn']
        })
    }

def create_campaign(event):
    campaign_name = event['campaign_name']
    solution_version_arn = event['solution_version_arn']
    min_provisioned_tps = event.get('min_provisioned_tps', 1)
    
    response = personalize.create_campaign(
        name=campaign_name,
        solutionVersionArn=solution_version_arn,
        minProvisionedTPS=min_provisioned_tps
    )
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'campaign_arn': response['campaignArn']
        })
    }

def check_status(event):
    resource_arn = event['resource_arn']
    resource_type = event['resource_type']
    
    if resource_type == 'solution':
        response = personalize.describe_solution(solutionArn=resource_arn)
        status = response['solution']['status']
    elif resource_type == 'campaign':
        response = personalize.describe_campaign(campaignArn=resource_arn)
        status = response['campaign']['status']
    elif resource_type == 'dataset_import_job':
        response = personalize.describe_dataset_import_job(datasetImportJobArn=resource_arn)
        status = response['datasetImportJob']['status']
    else:
        raise ValueError(f"Unknown resource type: {resource_type}")
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'resource_arn': resource_arn,
            'status': status,
            'is_complete': status in ['ACTIVE', 'CREATE FAILED']
        })
    }
      `),
    });

    // Analytics Lambda for processing Kinesis events
    const analyticsFunction = new lambda.Function(this, 'AnalyticsFunction', {
      functionName: `${projectName}-analytics`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(60),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        PROJECT_NAME: projectName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    # Process Kinesis events
    for record in event['Records']:
        # Decode the data
        data = base64.b64decode(record['kinesis']['data']).decode('utf-8')
        event_data = json.loads(data)
        
        # Process the event
        process_analytics_event(event_data)
    
    return {'statusCode': 200, 'body': 'Analytics processed successfully'}

def process_analytics_event(event_data):
    # Extract metrics from event
    event_type = event_data.get('event_type')
    user_id = event_data.get('user_id')
    item_id = event_data.get('item_id')
    
    # Send custom metrics to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='PersonalizeABTesting',
            MetricData=[
                {
                    'MetricName': f'Events_{event_type}',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'EventType',
                            'Value': event_type
                        }
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Failed to send metrics to CloudWatch: {str(e)}")
      `),
    });

    // Add Kinesis trigger to analytics function
    analyticsFunction.addEventSource(
      new lambda.eventsources.KinesisEventSource(analyticsStream, {
        batchSize: 100,
        startingPosition: lambda.StartingPosition.LATEST,
      })
    );

    // ========================================
    // API Gateway
    // ========================================
    const api = new apigateway.RestApi(this, 'RecommendationAPI', {
      restApiName: `${projectName}-recommendation-api`,
      description: 'Real-time recommendation API with A/B testing',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      deployOptions: {
        stageName: 'prod',
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
    });

    // Create integrations
    const abTestIntegration = new apigateway.LambdaIntegration(abTestRouterFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    });

    const recommendationIntegration = new apigateway.LambdaIntegration(recommendationEngineFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    });

    const eventTrackingIntegration = new apigateway.LambdaIntegration(eventTrackerFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
    });

    // Create API resources and methods
    const abTestResource = api.root.addResource('ab-test');
    abTestResource.addMethod('POST', abTestIntegration, {
      authorizationType: apigateway.AuthorizationType.NONE,
    });

    const recommendationsResource = api.root.addResource('recommendations');
    recommendationsResource.addMethod('POST', recommendationIntegration, {
      authorizationType: apigateway.AuthorizationType.NONE,
    });

    const eventsResource = api.root.addResource('events');
    eventsResource.addMethod('POST', eventTrackingIntegration, {
      authorizationType: apigateway.AuthorizationType.NONE,
    });

    // ========================================
    // CloudWatch Dashboard
    // ========================================
    const dashboard = new cloudwatch.Dashboard(this, 'RecommendationDashboard', {
      dashboardName: `${projectName}-dashboard`,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'API Gateway Requests',
        left: [api.metricRequests()],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Duration',
        left: [
          abTestRouterFunction.metricDuration(),
          recommendationEngineFunction.metricDuration(),
          eventTrackerFunction.metricDuration(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'DynamoDB Read/Write Capacity',
        left: [
          usersTable.metricConsumedReadCapacityUnits(),
          itemsTable.metricConsumedReadCapacityUnits(),
          abAssignmentsTable.metricConsumedReadCapacityUnits(),
          eventsTable.metricConsumedReadCapacityUnits(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Errors',
        left: [
          abTestRouterFunction.metricErrors(),
          recommendationEngineFunction.metricErrors(),
          eventTrackerFunction.metricErrors(),
        ],
        width: 12,
      })
    );

    // ========================================
    // Step Functions for Model Training
    // ========================================
    const trainModelStateMachine = this.createTrainingWorkflow(personalizeManagerFunction, projectName);

    // ========================================
    // Outputs
    // ========================================
    new CfnOutput(this, 'APIGatewayURL', {
      value: api.url,
      description: 'API Gateway URL for recommendation service',
    });

    new CfnOutput(this, 'TrainingDataBucketName', {
      value: trainingDataBucket.bucketName,
      description: 'S3 bucket for training data',
    });

    new CfnOutput(this, 'PersonalizeRoleArn', {
      value: personalizeRole.roleArn,
      description: 'IAM role for Amazon Personalize',
    });

    new CfnOutput(this, 'AnalyticsStreamName', {
      value: analyticsStream.streamName,
      description: 'Kinesis stream for real-time analytics',
    });

    new CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${projectName}-dashboard`,
      description: 'CloudWatch dashboard URL',
    });

    new CfnOutput(this, 'TrainingWorkflowArn', {
      value: trainModelStateMachine.stateMachineArn,
      description: 'Step Functions workflow for model training',
    });
  }

  /**
   * Creates a Step Functions workflow for Personalize model training
   */
  private createTrainingWorkflow(personalizeManagerFunction: lambda.Function, projectName: string): stepfunctions.StateMachine {
    // Define the workflow steps
    const createDatasetGroup = new stepfunctionsTasks.LambdaInvoke(this, 'CreateDatasetGroup', {
      lambdaFunction: personalizeManagerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        action: 'create_dataset_group',
        dataset_group_name: `${projectName}-dataset-group`,
      }),
    });

    const waitForDatasetGroup = new stepfunctions.Wait(this, 'WaitForDatasetGroup', {
      time: stepfunctions.WaitTime.duration(Duration.seconds(30)),
    });

    const checkDatasetGroupStatus = new stepfunctionsTasks.LambdaInvoke(this, 'CheckDatasetGroupStatus', {
      lambdaFunction: personalizeManagerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        action: 'check_status',
        'resource_arn.$': '$.Payload.body.dataset_group_arn',
        resource_type: 'dataset_group',
      }),
    });

    const isDatasetGroupActive = new stepfunctions.Choice(this, 'IsDatasetGroupActive')
      .when(
        stepfunctions.Condition.stringEquals('$.Payload.body.status', 'ACTIVE'),
        new stepfunctions.Pass(this, 'DatasetGroupReady')
      )
      .otherwise(waitForDatasetGroup);

    // Connect the workflow
    createDatasetGroup.next(waitForDatasetGroup);
    waitForDatasetGroup.next(checkDatasetGroupStatus);
    checkDatasetGroupStatus.next(isDatasetGroupActive);

    // Create the state machine
    const definition = createDatasetGroup;

    return new stepfunctions.StateMachine(this, 'TrainingWorkflow', {
      stateMachineName: `${projectName}-training-workflow`,
      definition,
      timeout: Duration.hours(2),
      logs: {
        destination: new logs.LogGroup(this, 'TrainingWorkflowLogs', {
          logGroupName: `/aws/stepfunctions/${projectName}-training-workflow`,
          removalPolicy: RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
      },
    });
  }
}

// ========================================
// CDK App
// ========================================
const app = new cdk.App();

new PersonalizeABTestingStack(app, 'PersonalizeABTestingStack', {
  description: 'Real-time recommendations with Amazon Personalize and A/B testing',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'PersonalizeABTesting',
    Environment: 'Development',
    Stack: 'RecommendationSystem',
  },
});

app.synth();