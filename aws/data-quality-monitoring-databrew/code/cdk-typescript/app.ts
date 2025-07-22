#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Stack, StackProps, RemovalPolicy, Duration } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as databrew from 'aws-cdk-lib/aws-databrew';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaNodejs from 'aws-cdk-lib/aws-lambda-nodejs';

/**
 * Properties for the DataQualityMonitoringStack
 */
export interface DataQualityMonitoringStackProps extends StackProps {
  /**
   * Email address to receive data quality alerts
   */
  readonly notificationEmail?: string;
  
  /**
   * Environment name for resource naming
   */
  readonly environment?: string;
  
  /**
   * Whether to create sample data
   */
  readonly createSampleData?: boolean;
}

/**
 * AWS CDK Stack for implementing data quality monitoring with AWS Glue DataBrew
 * 
 * This stack creates:
 * - S3 buckets for raw data and profile results
 * - IAM roles and policies for DataBrew
 * - DataBrew dataset, ruleset, and profile job
 * - SNS topic for notifications
 * - EventBridge rule for automation
 * - Lambda function for custom processing
 */
export class DataQualityMonitoringStack extends Stack {
  /**
   * S3 bucket for storing raw data
   */
  public readonly rawDataBucket: s3.Bucket;
  
  /**
   * S3 bucket for storing DataBrew profile results
   */
  public readonly resultsBucket: s3.Bucket;
  
  /**
   * SNS topic for data quality alerts
   */
  public readonly alertTopic: sns.Topic;
  
  /**
   * DataBrew dataset
   */
  public readonly dataset: databrew.CfnDataset;
  
  /**
   * DataBrew profile job
   */
  public readonly profileJob: databrew.CfnJob;

  constructor(scope: Construct, id: string, props: DataQualityMonitoringStackProps = {}) {
    super(scope, id, props);

    const environment = props.environment || 'dev';
    const createSampleData = props.createSampleData !== false;

    // Create S3 bucket for raw data
    this.rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `databrew-raw-data-${environment}-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
        },
      ],
    });

    // Create S3 bucket for DataBrew results
    this.resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `databrew-results-${environment}-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldResults',
          enabled: true,
          expiration: Duration.days(90),
        },
      ],
    });

    // Create IAM role for DataBrew
    const dataBrewRole = new iam.Role(this, 'DataBrewServiceRole', {
      roleName: `DataBrewServiceRole-${environment}-${this.region}`,
      assumedBy: new iam.ServicePrincipal('databrew.amazonaws.com'),
      description: 'Service role for AWS Glue DataBrew operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueDataBrewServiceRole'),
      ],
    });

    // Add custom policy for S3 bucket access
    dataBrewRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'S3BucketAccess',
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
        ],
        resources: [
          this.rawDataBucket.bucketArn,
          `${this.rawDataBucket.bucketArn}/*`,
          this.resultsBucket.bucketArn,
          `${this.resultsBucket.bucketArn}/*`,
        ],
      })
    );

    // Add CloudWatch Logs permissions
    dataBrewRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'CloudWatchLogsAccess',
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws/databrew/*`],
      })
    );

    // Create SNS topic for alerts
    this.alertTopic = new sns.Topic(this, 'DataQualityAlertTopic', {
      topicName: `data-quality-alerts-${environment}`,
      displayName: 'Data Quality Monitoring Alerts',
      description: 'SNS topic for data quality validation alerts',
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.alertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create DataBrew dataset
    this.dataset = new databrew.CfnDataset(this, 'CustomerDataset', {
      name: `customer-data-${environment}`,
      format: 'CSV',
      formatOptions: {
        csv: {
          delimiter: ',',
          headerRow: true,
        },
      },
      input: {
        s3InputDefinition: {
          bucket: this.rawDataBucket.bucketName,
          key: 'raw-data/',
        },
      },
    });

    // Create data quality ruleset
    const ruleset = new databrew.CfnRuleset(this, 'DataQualityRuleset', {
      name: `customer-quality-rules-${environment}`,
      description: 'Data quality rules for customer data validation',
      targetArn: `arn:aws:databrew:${this.region}:${this.account}:dataset/${this.dataset.name}`,
      rules: [
        {
          name: 'customer_id_not_null',
          checkExpression: 'COLUMN_COMPLETENESS(customer_id) > 0.95',
          substitutionMap: {},
          disabled: false,
        },
        {
          name: 'email_format_valid',
          checkExpression: 'COLUMN_DATA_TYPE(email) = "STRING" AND COLUMN_MATCHES_REGEX(email, "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$") > 0.8',
          substitutionMap: {},
          disabled: false,
        },
        {
          name: 'age_range_valid',
          checkExpression: 'COLUMN_MIN(age) >= 0 AND COLUMN_MAX(age) <= 120',
          substitutionMap: {},
          disabled: false,
        },
        {
          name: 'balance_positive',
          checkExpression: 'COLUMN_MIN(account_balance) >= 0',
          substitutionMap: {},
          disabled: false,
        },
        {
          name: 'registration_date_valid',
          checkExpression: 'COLUMN_DATA_TYPE(registration_date) = "DATE"',
          substitutionMap: {},
          disabled: false,
        },
      ],
    });

    // Ensure ruleset is created after dataset
    ruleset.addDependsOn(this.dataset);

    // Create CloudWatch Log Group for DataBrew
    const logGroup = new logs.LogGroup(this, 'DataBrewLogGroup', {
      logGroupName: `/aws/databrew/jobs/${environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create DataBrew profile job
    this.profileJob = new databrew.CfnJob(this, 'CustomerProfileJob', {
      name: `customer-profile-job-${environment}`,
      type: 'PROFILE',
      datasetName: this.dataset.name,
      roleArn: dataBrewRole.roleArn,
      logSubscription: 'ENABLE',
      maxCapacity: 5,
      maxRetries: 1,
      timeout: 2880, // 48 hours
      outputLocation: {
        bucket: this.resultsBucket.bucketName,
        key: 'profile-results/',
      },
      profileConfiguration: {
        datasetStatisticsConfiguration: {
          includedStatistics: ['ALL'],
        },
        profileColumns: [
          {
            name: '*',
            statisticsConfiguration: {
              includedStatistics: ['ALL'],
            },
          },
        ],
      },
      validationConfigurations: [
        {
          rulesetArn: `arn:aws:databrew:${this.region}:${this.account}:ruleset/${ruleset.name}`,
          validationMode: 'CHECK_ALL',
        },
      ],
    });

    // Ensure profile job is created after dataset and ruleset
    this.profileJob.addDependsOn(this.dataset);
    this.profileJob.addDependsOn(ruleset);

    // Create Lambda function for processing DataBrew events
    const eventProcessorFunction = new lambdaNodejs.NodejsFunction(this, 'DataBrewEventProcessor', {
      functionName: `databrew-event-processor-${environment}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'handler',
      timeout: Duration.minutes(5),
      memorySize: 256,
      description: 'Processes DataBrew validation events and sends notifications',
      environment: {
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
        ENVIRONMENT: environment,
      },
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const sns = new AWS.SNS();

        exports.handler = async (event) => {
          console.log('Received event:', JSON.stringify(event, null, 2));
          
          try {
            for (const record of event.Records) {
              const detail = JSON.parse(record.body);
              
              if (detail.source === 'aws.databrew' && detail['detail-type'] === 'DataBrew Ruleset Validation Result') {
                const { datasetName, rulesetName, validationState, validationReportLocation } = detail.detail;
                
                if (validationState === 'FAILED') {
                  const message = \`Data quality validation FAILED for dataset: \${datasetName}, ruleset: \${rulesetName}. Status: \${validationState}. Report: \${validationReportLocation || 'N/A'}\`;
                  
                  await sns.publish({
                    TopicArn: process.env.SNS_TOPIC_ARN,
                    Message: message,
                    Subject: \`Data Quality Alert - \${process.env.ENVIRONMENT}\`,
                  }).promise();
                  
                  console.log('Alert sent for failed validation');
                }
              }
            }
            
            return { statusCode: 200, body: 'Event processed successfully' };
          } catch (error) {
            console.error('Error processing event:', error);
            throw error;
          }
        };
      `),
    });

    // Grant Lambda function permission to publish to SNS
    this.alertTopic.grantPublish(eventProcessorFunction);

    // Create EventBridge rule for DataBrew events
    const dataBrewRule = new events.Rule(this, 'DataBrewValidationRule', {
      ruleName: `databrew-validation-${environment}`,
      description: 'Captures DataBrew validation events',
      eventPattern: {
        source: ['aws.databrew'],
        detailType: ['DataBrew Ruleset Validation Result'],
        detail: {
          validationState: ['FAILED'],
        },
      },
    });

    // Add SNS topic as target for EventBridge rule
    dataBrewRule.addTarget(
      new eventsTargets.SnsTopic(this.alertTopic, {
        message: events.RuleTargetInput.fromObject({
          alert: 'Data quality validation failed',
          dataset: events.EventField.fromPath('$.detail.datasetName'),
          ruleset: events.EventField.fromPath('$.detail.rulesetName'),
          state: events.EventField.fromPath('$.detail.validationState'),
          report: events.EventField.fromPath('$.detail.validationReportLocation'),
          timestamp: events.EventField.fromPath('$.time'),
        }),
      })
    );

    // Create sample data if requested
    if (createSampleData) {
      this.createSampleData();
    }

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'DataQualityMonitoring');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // Output important resource information
    new cdk.CfnOutput(this, 'RawDataBucketName', {
      value: this.rawDataBucket.bucketName,
      description: 'Name of the S3 bucket for raw data',
      exportName: `${this.stackName}-RawDataBucket`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: this.resultsBucket.bucketName,
      description: 'Name of the S3 bucket for DataBrew results',
      exportName: `${this.stackName}-ResultsBucket`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for data quality alerts',
      exportName: `${this.stackName}-AlertTopic`,
    });

    new cdk.CfnOutput(this, 'DatasetName', {
      value: this.dataset.name!,
      description: 'Name of the DataBrew dataset',
      exportName: `${this.stackName}-Dataset`,
    });

    new cdk.CfnOutput(this, 'ProfileJobName', {
      value: this.profileJob.name!,
      description: 'Name of the DataBrew profile job',
      exportName: `${this.stackName}-ProfileJob`,
    });

    new cdk.CfnOutput(this, 'DataBrewRoleArn', {
      value: dataBrewRole.roleArn,
      description: 'ARN of the DataBrew service role',
      exportName: `${this.stackName}-DataBrewRole`,
    });
  }

  /**
   * Creates sample customer data for testing
   */
  private createSampleData(): void {
    // Create a custom resource to deploy sample data
    const sampleDataDeployment = new cdk.CustomResource(this, 'SampleDataDeployment', {
      serviceToken: new lambda.Function(this, 'SampleDataDeploymentFunction', {
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.handler',
        timeout: Duration.minutes(5),
        code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse
import io
import csv

def handler(event, context):
    try:
        s3 = boto3.client('s3')
        bucket_name = event['ResourceProperties']['BucketName']
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            # Sample customer data
            sample_data = [
                ['customer_id', 'name', 'email', 'age', 'registration_date', 'account_balance'],
                ['1', 'John Smith', 'john.smith@example.com', '25', '2023-01-15', '1500.00'],
                ['2', 'Jane Doe', 'jane.doe@example.com', '32', '2023-02-20', '2300.50'],
                ['3', 'Bob Johnson', '', '28', '2023-03-10', '750.25'],
                ['4', 'Alice Brown', 'alice.brown@example.com', '45', '2023-04-05', '3200.75'],
                ['5', 'Charlie Wilson', 'charlie.wilson@example.com', '-5', '2023-05-12', '1800.00'],
                ['6', 'Diana Lee', 'diana.lee@example.com', '67', 'invalid-date', '2500.00'],
                ['7', 'Frank Miller', 'frank.miller@example.com', '33', '2023-07-18', ''],
                ['8', 'Grace Taylor', 'grace.taylor@example.com', '29', '2023-08-25', '1200.50'],
                ['9', 'Henry Davis', 'henry.davis@example.com', '41', '2023-09-30', '1750.25'],
                ['10', 'Ivy Chen', 'ivy.chen@example.com', '38', '2023-10-15', '2100.00']
            ]
            
            # Create CSV content
            csv_content = io.StringIO()
            writer = csv.writer(csv_content)
            writer.writerows(sample_data)
            
            # Upload to S3
            s3.put_object(
                Bucket=bucket_name,
                Key='raw-data/customer_data.csv',
                Body=csv_content.getvalue(),
                ContentType='text/csv'
            )
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'Message': 'Sample data created successfully'
            })
        else:
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {
            'Error': str(e)
        })
        `),
      }).functionArn,
      properties: {
        BucketName: this.rawDataBucket.bucketName,
      },
    });

    // Grant the Lambda function permission to write to S3
    this.rawDataBucket.grantWrite(
      iam.Role.fromRoleArn(this, 'SampleDataRole', 
        sampleDataDeployment.getAtt('ServiceToken').toString()
      )
    );
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from context or environment
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const createSampleData = app.node.tryGetContext('createSampleData') !== 'false';

// Create the stack
new DataQualityMonitoringStack(app, 'DataQualityMonitoringStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environment,
  notificationEmail,
  createSampleData,
  description: 'AWS Glue DataBrew data quality monitoring solution',
  tags: {
    Project: 'DataQualityMonitoring',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();