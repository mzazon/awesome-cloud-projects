#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-cloudwatch-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Configuration interface for the Data Exchange stack
 */
interface DataExchangeStackProps extends cdk.StackProps {
  readonly subscriberAccountId?: string;
  readonly datasetName?: string;
  readonly notificationEmail?: string;
  readonly enableAutomatedUpdates?: boolean;
  readonly updateSchedule?: string;
}

/**
 * AWS CDK Stack for Cross-Account Data Sharing with Data Exchange
 * 
 * This stack creates:
 * - S3 bucket for data storage with versioning and encryption
 * - IAM roles for Data Exchange operations with least privilege access
 * - Lambda functions for notifications and automated data updates
 * - EventBridge rules for automated scheduling and event processing
 * - CloudWatch monitoring and alerting infrastructure
 * - Custom resources for Data Exchange dataset and data grant creation
 */
export class CrossAccountDataSharingStack extends cdk.Stack {
  public readonly providerBucket: s3.Bucket;
  public readonly dataExchangeRole: iam.Role;
  public readonly notificationFunction: lambda.Function;
  public readonly updateFunction: lambda.Function;
  public readonly datasetId: string;

  constructor(scope: Construct, id: string, props: DataExchangeStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const subscriberAccountId = props.subscriberAccountId || this.node.tryGetContext('subscriberAccountId');
    const datasetName = props.datasetName || `enterprise-analytics-data-${this.generateRandomSuffix()}`;
    const notificationEmail = props.notificationEmail || this.node.tryGetContext('notificationEmail');
    const enableAutomatedUpdates = props.enableAutomatedUpdates ?? true;
    const updateSchedule = props.updateSchedule || 'rate(24 hours)';

    // Validate required parameters
    if (!subscriberAccountId) {
      throw new Error('subscriberAccountId must be provided either as a prop or context variable');
    }

    // Create S3 bucket for data provider with security best practices
    this.providerBucket = this.createProviderBucket();

    // Create IAM role for Data Exchange operations
    this.dataExchangeRole = this.createDataExchangeRole();

    // Create SNS topic for notifications if email is provided
    const notificationTopic = notificationEmail ? this.createNotificationTopic(notificationEmail) : undefined;

    // Create Lambda function for notifications
    this.notificationFunction = this.createNotificationFunction(notificationTopic);

    // Create Lambda function for automated data updates
    this.updateFunction = this.createUpdateFunction();

    // Create EventBridge rules for automation and monitoring
    this.createEventBridgeRules(enableAutomatedUpdates, updateSchedule, datasetName);

    // Create CloudWatch monitoring and alerting
    this.createMonitoringAndAlerting(notificationTopic);

    // Create sample data in S3 bucket
    this.createSampleData();

    // Create Data Exchange dataset using custom resource
    const dataset = this.createDataExchangeDataset(datasetName);
    this.datasetId = dataset.getAttString('DataSetId');

    // Create data grant for subscriber account
    this.createDataGrant(subscriberAccountId);

    // Output important values
    this.createOutputs(datasetName, subscriberAccountId);
  }

  /**
   * Creates S3 bucket for data provider with security best practices
   */
  private createProviderBucket(): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ProviderBucket', {
      bucketName: `data-exchange-provider-${this.generateRandomSuffix()}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'intelligent-tiering',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: Duration.days(1),
            },
          ],
        },
      ],
    });

    // Add bucket notification configuration for Data Exchange events
    bucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new targets.LambdaFunction(this.updateFunction),
      { prefix: 'analytics-data/' }
    );

    return bucket;
  }

  /**
   * Creates IAM role for Data Exchange operations with least privilege
   */
  private createDataExchangeRole(): iam.Role {
    const role = new iam.Role(this, 'DataExchangeRole', {
      roleName: 'DataExchangeProviderRole',
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('dataexchange.amazonaws.com'),
        new iam.ServicePrincipal('lambda.amazonaws.com')
      ),
      description: 'IAM role for AWS Data Exchange operations and Lambda functions',
    });

    // Attach AWS managed policy for Data Exchange
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AWSDataExchangeProviderFullAccess')
    );

    // Add custom policy for S3 access
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:GetObjectVersion',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
        ],
        resources: [
          this.providerBucket.bucketArn,
          `${this.providerBucket.bucketArn}/*`,
        ],
      })
    );

    // Add Lambda execution permissions
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
    );

    return role;
  }

  /**
   * Creates SNS topic for notifications
   */
  private createNotificationTopic(email: string): sns.Topic {
    const topic = new sns.Topic(this, 'NotificationTopic', {
      topicName: 'DataExchangeNotifications',
      displayName: 'AWS Data Exchange Notifications',
    });

    // Add email subscription
    topic.addSubscription(
      new (require('aws-cdk-lib/aws-sns-subscriptions')).EmailSubscription(email)
    );

    return topic;
  }

  /**
   * Creates Lambda function for handling Data Exchange notifications
   */
  private createNotificationFunction(notificationTopic?: sns.Topic): lambda.Function {
    const func = new lambda.Function(this, 'NotificationFunction', {
      functionName: 'DataExchangeNotificationHandler',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.minutes(5),
      role: this.dataExchangeRole,
      environment: {
        SNS_TOPIC_ARN: notificationTopic?.topicArn || '',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handles AWS Data Exchange events and sends notifications
    """
    try:
        sns = boto3.client('sns')
        
        # Parse the Data Exchange event
        detail = event.get('detail', {})
        event_name = detail.get('eventName', 'Unknown')
        dataset_id = detail.get('dataSetId', 'Unknown')
        source = event.get('source', 'Unknown')
        
        # Create notification message
        message = f"""
AWS Data Exchange Event Notification:

Event: {event_name}
Source: {source}
Dataset ID: {dataset_id}
Timestamp: {event.get('time', 'Unknown')}
Account: {detail.get('userIdentity', {}).get('accountId', 'Unknown')}

Event Details:
{json.dumps(detail, indent=2)}
        """
        
        logger.info(f"Processing Data Exchange event: {event_name}")
        
        # Send notification if SNS topic is configured
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if topic_arn:
            response = sns.publish(
                TopicArn=topic_arn,
                Message=message,
                Subject=f'Data Exchange Event: {event_name}'
            )
            logger.info(f"Notification sent successfully: {response['MessageId']}")
        else:
            logger.info("No SNS topic configured, logging event only")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification processed successfully',
                'event': event_name,
                'dataset_id': dataset_id
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process notification'
            })
        }
      `),
    });

    // Grant SNS publish permissions if topic exists
    if (notificationTopic) {
      notificationTopic.grantPublish(func);
    }

    return func;
  }

  /**
   * Creates Lambda function for automated data updates
   */
  private createUpdateFunction(): lambda.Function {
    const func = new lambda.Function(this, 'UpdateFunction', {
      functionName: 'DataExchangeAutoUpdate',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.minutes(15),
      role: this.dataExchangeRole,
      environment: {
        PROVIDER_BUCKET: this.providerBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import csv
import random
from datetime import datetime, timedelta
from io import StringIO
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Generates updated sample data and creates new Data Exchange revision
    """
    try:
        dataexchange = boto3.client('dataexchange')
        s3 = boto3.client('s3')
        
        # Extract parameters from event
        dataset_id = event.get('dataset_id')
        bucket_name = event.get('bucket_name') or os.environ.get('PROVIDER_BUCKET')
        
        if not dataset_id:
            logger.error("Missing required parameter: dataset_id")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing dataset_id parameter'})
            }
        
        if not bucket_name:
            logger.error("Missing required parameter: bucket_name")
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Missing bucket_name parameter'})
            }
        
        # Generate updated sample data
        current_date = datetime.now().strftime('%Y-%m-%d')
        current_timestamp = datetime.now().isoformat()
        
        # Create updated customer analytics data
        csv_data = generate_sample_csv_data(current_date)
        json_data = generate_sample_json_data(current_date)
        
        # Upload updated data to S3
        csv_key = f'analytics-data/customer-analytics-{current_date}.csv'
        json_key = f'analytics-data/sales-summary-{current_date}.json'
        
        s3.put_object(
            Bucket=bucket_name,
            Key=csv_key,
            Body=csv_data,
            ContentType='text/csv'
        )
        
        s3.put_object(
            Bucket=bucket_name,
            Key=json_key,
            Body=json_data,
            ContentType='application/json'
        )
        
        logger.info(f"Uploaded updated data files to S3: {csv_key}, {json_key}")
        
        # Create new revision in Data Exchange
        revision_response = dataexchange.create_revision(
            DataSetId=dataset_id,
            Comment=f'Automated update - {current_timestamp}'
        )
        
        revision_id = revision_response['Id']
        logger.info(f"Created new revision: {revision_id}")
        
        # Import new assets from S3
        import_jobs = []
        
        for key in [csv_key, json_key]:
            import_job = dataexchange.create_job(
                Type='IMPORT_ASSETS_FROM_S3',
                Details={
                    'ImportAssetsFromS3JobDetails': {
                        'DataSetId': dataset_id,
                        'RevisionId': revision_id,
                        'AssetSources': [
                            {
                                'Bucket': bucket_name,
                                'Key': key
                            }
                        ]
                    }
                }
            )
            import_jobs.append(import_job['Id'])
            logger.info(f"Started import job {import_job['Id']} for {key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data update completed successfully',
                'dataset_id': dataset_id,
                'revision_id': revision_id,
                'import_jobs': import_jobs,
                'updated_files': [csv_key, json_key]
            })
        }
        
    except Exception as e:
        logger.error(f"Error updating data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to update data'
            })
        }

def generate_sample_csv_data(date_str):
    """Generate sample CSV data for customer analytics"""
    output = StringIO()
    writer = csv.writer(output)
    
    # Write header
    writer.writerow(['customer_id', 'purchase_date', 'amount', 'category', 'region'])
    
    # Generate sample rows
    categories = ['electronics', 'books', 'clothing', 'home', 'sports']
    regions = ['us-east', 'us-west', 'eu-central', 'asia-pacific']
    
    for i in range(1, 11):  # Generate 10 sample records
        customer_id = f'C{i:03d}'
        amount = f'{random.uniform(25, 500):.2f}'
        category = random.choice(categories)
        region = random.choice(regions)
        
        writer.writerow([customer_id, date_str, amount, category, region])
    
    return output.getvalue()

def generate_sample_json_data(date_str):
    """Generate sample JSON data for sales summary"""
    return json.dumps({
        'report_date': date_str,
        'total_sales': round(random.uniform(1000, 5000), 2),
        'transaction_count': random.randint(50, 200),
        'top_category': random.choice(['electronics', 'books', 'clothing']),
        'average_order_value': round(random.uniform(75, 250), 2),
        'growth_rate': round(random.uniform(-10, 25), 2)
    }, indent=2)
      `),
    });

    // Grant S3 permissions
    this.providerBucket.grantReadWrite(func);

    return func;
  }

  /**
   * Creates EventBridge rules for automation and monitoring
   */
  private createEventBridgeRules(enableAutomatedUpdates: boolean, updateSchedule: string, datasetName: string): void {
    // Create rule for Data Exchange events
    const dataExchangeEventRule = new events.Rule(this, 'DataExchangeEventRule', {
      ruleName: 'DataExchangeEventRule',
      description: 'Captures Data Exchange events for notifications',
      eventPattern: {
        source: ['aws.dataexchange'],
        detailType: ['Data Exchange Asset Import State Change'],
      },
    });

    // Add notification function as target
    dataExchangeEventRule.addTarget(new targets.LambdaFunction(this.notificationFunction));

    // Create scheduled rule for automated updates if enabled
    if (enableAutomatedUpdates) {
      const updateScheduleRule = new events.Rule(this, 'DataExchangeUpdateSchedule', {
        ruleName: 'DataExchangeAutoUpdateSchedule',
        description: 'Triggers automated data updates for Data Exchange',
        schedule: events.Schedule.expression(updateSchedule),
      });

      // Add update function as target with dataset parameters
      updateScheduleRule.addTarget(
        new targets.LambdaFunction(this.updateFunction, {
          event: events.RuleTargetInput.fromObject({
            dataset_id: this.datasetId,
            bucket_name: this.providerBucket.bucketName,
            trigger: 'scheduled',
          }),
        })
      );
    }
  }

  /**
   * Creates CloudWatch monitoring and alerting
   */
  private createMonitoringAndAlerting(notificationTopic?: sns.Topic): void {
    // Create log group for Data Exchange operations
    const logGroup = new logs.LogGroup(this, 'DataExchangeLogGroup', {
      logGroupName: '/aws/dataexchange/operations',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create CloudWatch alarms
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: 'DataExchangeLambdaErrors',
      alarmDescription: 'Alert when Lambda functions encounter errors',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Lambda',
        metricName: 'Errors',
        dimensionsMap: {
          FunctionName: this.updateFunction.functionName,
        },
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    // Add SNS action if topic exists
    if (notificationTopic) {
      lambdaErrorAlarm.addAlarmAction(
        new (require('aws-cdk-lib/aws-cloudwatch-actions')).SnsAction(notificationTopic)
      );
    }

    // Create custom metric for Data Exchange operations
    const customMetricFilter = new logs.MetricFilter(this, 'ErrorMetricFilter', {
      logGroup: logGroup,
      filterPattern: logs.FilterPattern.literal('ERROR'),
      metricNamespace: 'CustomMetrics',
      metricName: 'DataExchangeErrors',
      metricValue: '1',
    });
  }

  /**
   * Creates sample data in S3 bucket using custom resource
   */
  private createSampleData(): void {
    const sampleDataProvider = new cr.Provider(this, 'SampleDataProvider', {
      onEventHandler: new lambda.Function(this, 'SampleDataHandler', {
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.on_event',
        code: lambda.Code.fromInline(`
import json
import boto3
import csv
from io import StringIO

def on_event(event, context):
    request_type = event['RequestType']
    
    if request_type == 'Create' or request_type == 'Update':
        return create_sample_data(event)
    elif request_type == 'Delete':
        return delete_sample_data(event)

def create_sample_data(event):
    s3 = boto3.client('s3')
    bucket_name = event['ResourceProperties']['BucketName']
    
    # Create sample CSV data
    csv_data = create_sample_csv()
    s3.put_object(
        Bucket=bucket_name,
        Key='analytics-data/customer-analytics.csv',
        Body=csv_data,
        ContentType='text/csv'
    )
    
    # Create sample JSON data
    json_data = create_sample_json()
    s3.put_object(
        Bucket=bucket_name,
        Key='analytics-data/sales-summary.json',
        Body=json_data,
        ContentType='application/json'
    )
    
    return {
        'PhysicalResourceId': f'sample-data-{bucket_name}',
        'Data': {
            'CsvKey': 'analytics-data/customer-analytics.csv',
            'JsonKey': 'analytics-data/sales-summary.json'
        }
    }

def delete_sample_data(event):
    s3 = boto3.client('s3')
    bucket_name = event['ResourceProperties']['BucketName']
    
    # Delete sample files
    try:
        s3.delete_object(Bucket=bucket_name, Key='analytics-data/customer-analytics.csv')
        s3.delete_object(Bucket=bucket_name, Key='analytics-data/sales-summary.json')
    except:
        pass  # Ignore errors during cleanup
    
    return {'PhysicalResourceId': event['PhysicalResourceId']}

def create_sample_csv():
    output = StringIO()
    writer = csv.writer(output)
    writer.writerow(['customer_id', 'purchase_date', 'amount', 'category', 'region'])
    writer.writerow(['C001', '2024-01-15', '150.50', 'electronics', 'us-east'])
    writer.writerow(['C002', '2024-01-16', '89.99', 'books', 'us-west'])
    writer.writerow(['C003', '2024-01-17', '299.99', 'clothing', 'eu-central'])
    writer.writerow(['C004', '2024-01-18', '45.75', 'home', 'us-east'])
    writer.writerow(['C005', '2024-01-19', '199.99', 'electronics', 'asia-pacific'])
    return output.getvalue()

def create_sample_json():
    return json.dumps({
        'report_date': '2024-01-31',
        'total_sales': 785.72,
        'transaction_count': 5,
        'top_category': 'electronics',
        'average_order_value': 157.14
    }, indent=2)
        `),
        role: this.dataExchangeRole,
        timeout: Duration.minutes(2),
      }),
    });

    new cdk.CustomResource(this, 'SampleData', {
      serviceToken: sampleDataProvider.serviceToken,
      properties: {
        BucketName: this.providerBucket.bucketName,
      },
    });
  }

  /**
   * Creates Data Exchange dataset using custom resource
   */
  private createDataExchangeDataset(datasetName: string): cdk.CustomResource {
    const datasetProvider = new cr.Provider(this, 'DatasetProvider', {
      onEventHandler: new lambda.Function(this, 'DatasetHandler', {
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.on_event',
        code: lambda.Code.fromInline(`
import json
import boto3
import time

def on_event(event, context):
    request_type = event['RequestType']
    
    if request_type == 'Create':
        return create_dataset(event)
    elif request_type == 'Update':
        return update_dataset(event)
    elif request_type == 'Delete':
        return delete_dataset(event)

def create_dataset(event):
    dataexchange = boto3.client('dataexchange')
    s3 = boto3.client('s3')
    
    props = event['ResourceProperties']
    dataset_name = props['DatasetName']
    bucket_name = props['BucketName']
    
    # Create dataset
    dataset_response = dataexchange.create_data_set(
        AssetType='S3_SNAPSHOT',
        Description='Enterprise customer analytics data for cross-account sharing',
        Name=dataset_name,
        Tags={
            'Environment': 'Production',
            'DataType': 'Analytics',
            'CreatedBy': 'CDK'
        }
    )
    
    dataset_id = dataset_response['Id']
    
    # Create initial revision
    revision_response = dataexchange.create_revision(
        DataSetId=dataset_id,
        Comment='Initial data revision with customer analytics'
    )
    
    revision_id = revision_response['Id']
    
    # Import assets
    assets = [
        'analytics-data/customer-analytics.csv',
        'analytics-data/sales-summary.json'
    ]
    
    import_jobs = []
    for asset_key in assets:
        import_job = dataexchange.create_job(
            Type='IMPORT_ASSETS_FROM_S3',
            Details={
                'ImportAssetsFromS3JobDetails': {
                    'DataSetId': dataset_id,
                    'RevisionId': revision_id,
                    'AssetSources': [
                        {
                            'Bucket': bucket_name,
                            'Key': asset_key
                        }
                    ]
                }
            }
        )
        import_jobs.append(import_job['Id'])
    
    # Wait for import jobs to complete
    for job_id in import_jobs:
        wait_for_job_completion(dataexchange, job_id)
    
    # Finalize revision
    dataexchange.update_revision(
        DataSetId=dataset_id,
        RevisionId=revision_id,
        Finalized=True
    )
    
    return {
        'PhysicalResourceId': dataset_id,
        'Data': {
            'DataSetId': dataset_id,
            'RevisionId': revision_id,
            'ImportJobs': import_jobs
        }
    }

def update_dataset(event):
    # For updates, return the existing dataset ID
    return {
        'PhysicalResourceId': event['PhysicalResourceId'],
        'Data': {
            'DataSetId': event['PhysicalResourceId']
        }
    }

def delete_dataset(event):
    dataexchange = boto3.client('dataexchange')
    dataset_id = event['PhysicalResourceId']
    
    try:
        dataexchange.delete_data_set(DataSetId=dataset_id)
    except dataexchange.exceptions.ResourceNotFoundException:
        pass  # Dataset already deleted
    except Exception as e:
        print(f"Error deleting dataset: {e}")
        # Don't fail the deletion
    
    return {'PhysicalResourceId': dataset_id}

def wait_for_job_completion(dataexchange, job_id, max_wait_time=300):
    start_time = time.time()
    while time.time() - start_time < max_wait_time:
        job_response = dataexchange.get_job(JobId=job_id)
        state = job_response['State']
        
        if state == 'COMPLETED':
            return True
        elif state == 'ERROR':
            raise Exception(f"Import job {job_id} failed: {job_response.get('Errors', [])}")
        
        time.sleep(10)
    
    raise Exception(f"Import job {job_id} timed out after {max_wait_time} seconds")
        `),
        role: this.dataExchangeRole,
        timeout: Duration.minutes(10),
      }),
    });

    return new cdk.CustomResource(this, 'Dataset', {
      serviceToken: datasetProvider.serviceToken,
      properties: {
        DatasetName: datasetName,
        BucketName: this.providerBucket.bucketName,
      },
    });
  }

  /**
   * Creates data grant for subscriber account
   */
  private createDataGrant(subscriberAccountId: string): void {
    const dataGrantProvider = new cr.Provider(this, 'DataGrantProvider', {
      onEventHandler: new lambda.Function(this, 'DataGrantHandler', {
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.on_event',
        code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime, timedelta

def on_event(event, context):
    request_type = event['RequestType']
    
    if request_type == 'Create':
        return create_data_grant(event)
    elif request_type == 'Update':
        return update_data_grant(event)
    elif request_type == 'Delete':
        return delete_data_grant(event)

def create_data_grant(event):
    dataexchange = boto3.client('dataexchange')
    
    props = event['ResourceProperties']
    dataset_id = props['DatasetId']
    subscriber_account_id = props['SubscriberAccountId']
    
    # Calculate expiration date (1 year from now)
    expiration_date = datetime.now() + timedelta(days=365)
    
    # Create data grant
    grant_response = dataexchange.create_data_grant(
        Name=f'Analytics Data Grant for Account {subscriber_account_id}',
        Description='Cross-account data sharing grant for analytics data',
        DataSetId=dataset_id,
        RecipientAccountId=subscriber_account_id,
        EndsAt=expiration_date
    )
    
    return {
        'PhysicalResourceId': grant_response['Id'],
        'Data': {
            'DataGrantId': grant_response['Id'],
            'GrantArn': grant_response['Arn'],
            'ExpirationDate': expiration_date.isoformat()
        }
    }

def update_data_grant(event):
    # Data grants cannot be updated, return existing ID
    return {
        'PhysicalResourceId': event['PhysicalResourceId'],
        'Data': {
            'DataGrantId': event['PhysicalResourceId']
        }
    }

def delete_data_grant(event):
    dataexchange = boto3.client('dataexchange')
    grant_id = event['PhysicalResourceId']
    
    try:
        dataexchange.delete_data_grant(DataGrantId=grant_id)
    except dataexchange.exceptions.ResourceNotFoundException:
        pass  # Grant already deleted
    except Exception as e:
        print(f"Error deleting data grant: {e}")
        # Don't fail the deletion
    
    return {'PhysicalResourceId': grant_id}
        `),
        role: this.dataExchangeRole,
        timeout: Duration.minutes(5),
      }),
    });

    const dataGrant = new cdk.CustomResource(this, 'DataGrant', {
      serviceToken: dataGrantProvider.serviceToken,
      properties: {
        DatasetId: this.datasetId,
        SubscriberAccountId: subscriberAccountId,
      },
    });

    // Ensure data grant is created after dataset
    dataGrant.node.addDependency(this.createDataExchangeDataset(''));
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(datasetName: string, subscriberAccountId: string): void {
    new cdk.CfnOutput(this, 'ProviderBucketName', {
      value: this.providerBucket.bucketName,
      description: 'Name of the S3 bucket for data provider',
      exportName: `${this.stackName}-ProviderBucket`,
    });

    new cdk.CfnOutput(this, 'DataExchangeRoleArn', {
      value: this.dataExchangeRole.roleArn,
      description: 'ARN of the Data Exchange IAM role',
      exportName: `${this.stackName}-DataExchangeRole`,
    });

    new cdk.CfnOutput(this, 'DatasetName', {
      value: datasetName,
      description: 'Name of the Data Exchange dataset',
      exportName: `${this.stackName}-DatasetName`,
    });

    new cdk.CfnOutput(this, 'SubscriberAccountId', {
      value: subscriberAccountId,
      description: 'AWS Account ID of the data subscriber',
      exportName: `${this.stackName}-SubscriberAccount`,
    });

    new cdk.CfnOutput(this, 'NotificationFunctionName', {
      value: this.notificationFunction.functionName,
      description: 'Name of the notification Lambda function',
      exportName: `${this.stackName}-NotificationFunction`,
    });

    new cdk.CfnOutput(this, 'UpdateFunctionName', {
      value: this.updateFunction.functionName,
      description: 'Name of the data update Lambda function',
      exportName: `${this.stackName}-UpdateFunction`,
    });
  }

  /**
   * Generates a random suffix for resource names
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const subscriberAccountId = app.node.tryGetContext('subscriberAccountId') || process.env.SUBSCRIBER_ACCOUNT_ID;
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const datasetName = app.node.tryGetContext('datasetName') || process.env.DATASET_NAME;

// Create the stack
new CrossAccountDataSharingStack(app, 'CrossAccountDataSharingStack', {
  description: 'AWS CDK Stack for Cross-Account Data Sharing with Data Exchange (Recipe: f22b06e2)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  subscriberAccountId,
  notificationEmail,
  datasetName,
  enableAutomatedUpdates: true,
  updateSchedule: 'rate(24 hours)',
  tags: {
    Recipe: 'cross-account-data-sharing-aws-data-exchange',
    RecipeId: 'f22b06e2',
    Environment: 'Production',
    ManagedBy: 'CDK',
  },
});

// Synthesize the application
app.synth();