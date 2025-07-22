#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cr from 'aws-cdk-lib/custom-resources';
import { CfnDataset, CfnRuleset, CfnJob } from 'aws-cdk-lib/aws-databrew';

/**
 * Properties for the DataQualityPipelineStack
 */
export interface DataQualityPipelineStackProps extends cdk.StackProps {
  /**
   * Environment suffix for unique resource naming
   * @default - Random suffix generated
   */
  readonly environmentSuffix?: string;
  
  /**
   * Email address for notifications
   * @default - No email notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Maximum capacity for DataBrew jobs
   * @default 5
   */
  readonly maxDataBrewCapacity?: number;
  
  /**
   * Timeout for DataBrew jobs in minutes
   * @default 120
   */
  readonly dataBrewTimeoutMinutes?: number;
}

/**
 * AWS CDK Stack for Automated Data Quality Pipelines
 * 
 * This stack creates a comprehensive data quality pipeline using:
 * - AWS Glue DataBrew for data profiling and quality assessment
 * - Amazon EventBridge for event-driven automation
 * - AWS Lambda for processing validation events
 * - Amazon S3 for data storage and quality reports
 * - Amazon SNS for notifications
 */
export class DataQualityPipelineStack extends cdk.Stack {
  // Core infrastructure components
  public readonly dataBucket: s3.Bucket;
  public readonly reportsBucket: s3.Bucket;
  public readonly quarantineBucket: s3.Bucket;
  public readonly notificationTopic: sns.Topic;
  
  // DataBrew components
  public readonly dataBrewServiceRole: iam.Role;
  public readonly dataset: CfnDataset;
  public readonly ruleset: CfnRuleset;
  public readonly profileJob: CfnJob;
  
  // Event processing components
  public readonly eventProcessorFunction: lambda.Function;
  public readonly eventRule: events.Rule;
  
  constructor(scope: Construct, id: string, props: DataQualityPipelineStackProps = {}) {
    super(scope, id, props);
    
    // Generate unique suffix for resource naming
    const suffix = props.environmentSuffix || this.generateRandomSuffix();
    
    // Create S3 buckets for data storage
    this.dataBucket = this.createDataBucket(suffix);
    this.reportsBucket = this.createReportsBucket(suffix);
    this.quarantineBucket = this.createQuarantineBucket(suffix);
    
    // Create SNS topic for notifications
    this.notificationTopic = this.createNotificationTopic(suffix, props.notificationEmail);
    
    // Create IAM roles
    this.dataBrewServiceRole = this.createDataBrewServiceRole(suffix);
    
    // Create DataBrew components
    this.dataset = this.createDataBrewDataset(suffix);
    this.ruleset = this.createDataQualityRuleset(suffix);
    this.profileJob = this.createDataBrewProfileJob(suffix, props);
    
    // Create event processing components
    this.eventProcessorFunction = this.createEventProcessorLambda(suffix);
    this.eventRule = this.createEventBridgeRule(suffix);
    
    // Create stack outputs
    this.createStackOutputs();
    
    // Apply tags to all resources
    this.applyTags();
  }
  
  /**
   * Generate a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
  
  /**
   * Create S3 bucket for raw data storage
   */
  private createDataBucket(suffix: string): s3.Bucket {
    return new s3.Bucket(this, 'DataBucket', {
      bucketName: `data-quality-pipeline-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'ArchiveOldData',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ]
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });
  }
  
  /**
   * Create S3 bucket for quality reports
   */
  private createReportsBucket(suffix: string): s3.Bucket {
    return new s3.Bucket(this, 'ReportsBucket', {
      bucketName: `quality-reports-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: cdk.Duration.days(365)
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });
  }
  
  /**
   * Create S3 bucket for quarantined data
   */
  private createQuarantineBucket(suffix: string): s3.Bucket {
    return new s3.Bucket(this, 'QuarantineBucket', {
      bucketName: `quarantine-data-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });
  }
  
  /**
   * Create SNS topic for notifications
   */
  private createNotificationTopic(suffix: string, email?: string): sns.Topic {
    const topic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `data-quality-notifications-${suffix}`,
      displayName: 'Data Quality Pipeline Notifications'
    });
    
    // Add email subscription if provided
    if (email) {
      topic.addSubscription(new subscriptions.EmailSubscription(email));
    }
    
    return topic;
  }
  
  /**
   * Create IAM role for DataBrew service
   */
  private createDataBrewServiceRole(suffix: string): iam.Role {
    const role = new iam.Role(this, 'DataBrewServiceRole', {
      roleName: `DataBrewServiceRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('databrew.amazonaws.com'),
      description: 'Service role for AWS Glue DataBrew operations'
    });
    
    // Attach managed policy for DataBrew
    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueDataBrewServiceRole')
    );
    
    // Grant specific permissions for S3 buckets
    this.dataBucket.grantRead(role);
    this.reportsBucket.grantReadWrite(role);
    
    return role;
  }
  
  /**
   * Create DataBrew dataset
   */
  private createDataBrewDataset(suffix: string): CfnDataset {
    return new CfnDataset(this, 'CustomerDataset', {
      name: `customer-data-${suffix}`,
      format: 'CSV',
      formatOptions: {
        csv: {
          delimiter: ',',
          headerRow: true
        }
      },
      input: {
        s3InputDefinition: {
          bucket: this.dataBucket.bucketName,
          key: 'raw-data/customer-data.csv'
        }
      },
      tags: [
        { key: 'Environment', value: 'Development' },
        { key: 'Purpose', value: 'DataQuality' }
      ]
    });
  }
  
  /**
   * Create data quality ruleset
   */
  private createDataQualityRuleset(suffix: string): CfnRuleset {
    return new CfnRuleset(this, 'DataQualityRuleset', {
      name: `customer-quality-rules-${suffix}`,
      targetArn: this.dataset.attrResourceArn,
      rules: [
        {
          name: 'EmailFormatValidation',
          checkExpression: ':col1 matches "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"',
          substitutionMap: {
            ':col1': '`email`'
          },
          threshold: {
            value: 90.0,
            type: 'GREATER_THAN_OR_EQUAL',
            unit: 'PERCENTAGE'
          }
        },
        {
          name: 'AgeRangeValidation',
          checkExpression: ':col1 between :val1 and :val2',
          substitutionMap: {
            ':col1': '`age`',
            ':val1': '0',
            ':val2': '120'
          },
          threshold: {
            value: 95.0,
            type: 'GREATER_THAN_OR_EQUAL',
            unit: 'PERCENTAGE'
          }
        },
        {
          name: 'PurchaseAmountNotNull',
          checkExpression: ':col1 is not null',
          substitutionMap: {
            ':col1': '`purchase_amount`'
          },
          threshold: {
            value: 90.0,
            type: 'GREATER_THAN_OR_EQUAL',
            unit: 'PERCENTAGE'
          }
        }
      ],
      tags: [
        { key: 'Environment', value: 'Development' },
        { key: 'Purpose', value: 'DataQuality' }
      ]
    });
  }
  
  /**
   * Create DataBrew profile job
   */
  private createDataBrewProfileJob(suffix: string, props: DataQualityPipelineStackProps): CfnJob {
    return new CfnJob(this, 'QualityAssessmentJob', {
      name: `quality-assessment-job-${suffix}`,
      type: 'PROFILE',
      datasetName: this.dataset.name!,
      roleArn: this.dataBrewServiceRole.roleArn,
      outputLocation: {
        bucket: this.reportsBucket.bucketName,
        key: 'quality-reports/'
      },
      validationConfigurations: [
        {
          rulesetArn: this.ruleset.attrResourceArn,
          validationMode: 'CHECK_ALL'
        }
      ],
      jobSample: {
        mode: 'FULL_DATASET'
      },
      profileConfiguration: {
        datasetStatisticsConfiguration: {
          includedStatistics: [
            'COMPLETENESS',
            'VALIDITY',
            'UNIQUENESS',
            'CORRELATION'
          ]
        }
      },
      maxCapacity: props.maxDataBrewCapacity || 5,
      timeout: props.dataBrewTimeoutMinutes || 120,
      tags: [
        { key: 'Environment', value: 'Development' },
        { key: 'Purpose', value: 'DataQuality' }
      ]
    });
  }
  
  /**
   * Create Lambda function for event processing
   */
  private createEventProcessorLambda(suffix: string): lambda.Function {
    const lambdaFunction = new lambda.Function(this, 'EventProcessorFunction', {
      functionName: `DataQualityProcessor-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    print(f"Received event: {json.dumps(event, default=str)}")
    
    # Extract DataBrew validation result details
    detail = event.get('detail', {})
    validation_state = detail.get('validationState')
    dataset_name = detail.get('datasetName')
    job_name = detail.get('jobName')
    ruleset_name = detail.get('rulesetName')
    
    if validation_state == 'FAILED':
        # Initialize AWS clients
        sns = boto3.client('sns')
        s3 = boto3.client('s3')
        
        # Send notification
        message = f"""
Data Quality Alert - Validation Failed

Dataset: {dataset_name}
Job: {job_name}
Ruleset: {ruleset_name}
Timestamp: {datetime.now().isoformat()}

Action Required: Review data quality report and investigate source data issues.
"""
        
        # Publish to SNS
        topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if topic_arn:
            sns.publish(
                TopicArn=topic_arn,
                Subject='Data Quality Validation Failed',
                Message=message
            )
        
        # Log the failure for CloudWatch
        print(f"Data quality validation failed for dataset: {dataset_name}")
        
        # TODO: Add quarantine logic for failed data
        # quarantine_bucket = os.environ.get('QUARANTINE_BUCKET')
        # if quarantine_bucket:
        #     # Move failed data to quarantine bucket
        #     pass
        
    elif validation_state == 'SUCCEEDED':
        print(f"Data quality validation succeeded for dataset: {dataset_name}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed validation result: {validation_state}')
    }
      `),
      timeout: cdk.Duration.seconds(60),
      environment: {
        'SNS_TOPIC_ARN': this.notificationTopic.topicArn,
        'QUARANTINE_BUCKET': this.quarantineBucket.bucketName
      },
      logRetention: logs.RetentionDays.ONE_WEEK
    });
    
    // Grant permissions for SNS and S3
    this.notificationTopic.grantPublish(lambdaFunction);
    this.quarantineBucket.grantReadWrite(lambdaFunction);
    this.dataBucket.grantRead(lambdaFunction);
    
    return lambdaFunction;
  }
  
  /**
   * Create EventBridge rule for DataBrew validation events
   */
  private createEventBridgeRule(suffix: string): events.Rule {
    const rule = new events.Rule(this, 'DataBrewValidationRule', {
      ruleName: `DataBrewValidationRule-${suffix}`,
      description: 'Route DataBrew validation events to Lambda',
      eventPattern: {
        source: ['aws.databrew'],
        detailType: ['DataBrew Ruleset Validation Result'],
        detail: {
          validationState: ['FAILED', 'SUCCEEDED']
        }
      },
      enabled: true
    });
    
    // Add Lambda function as target
    rule.addTarget(new targets.LambdaFunction(this.eventProcessorFunction));
    
    return rule;
  }
  
  /**
   * Create stack outputs
   */
  private createStackOutputs(): void {
    new cdk.CfnOutput(this, 'DataBucketName', {
      description: 'Name of the S3 bucket for raw data',
      value: this.dataBucket.bucketName,
      exportName: `${this.stackName}-DataBucketName`
    });
    
    new cdk.CfnOutput(this, 'ReportsBucketName', {
      description: 'Name of the S3 bucket for quality reports',
      value: this.reportsBucket.bucketName,
      exportName: `${this.stackName}-ReportsBucketName`
    });
    
    new cdk.CfnOutput(this, 'QuarantineBucketName', {
      description: 'Name of the S3 bucket for quarantined data',
      value: this.quarantineBucket.bucketName,
      exportName: `${this.stackName}-QuarantineBucketName`
    });
    
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      description: 'ARN of the SNS topic for notifications',
      value: this.notificationTopic.topicArn,
      exportName: `${this.stackName}-NotificationTopicArn`
    });
    
    new cdk.CfnOutput(this, 'DatasetName', {
      description: 'Name of the DataBrew dataset',
      value: this.dataset.name!,
      exportName: `${this.stackName}-DatasetName`
    });
    
    new cdk.CfnOutput(this, 'RulesetName', {
      description: 'Name of the DataBrew ruleset',
      value: this.ruleset.name!,
      exportName: `${this.stackName}-RulesetName`
    });
    
    new cdk.CfnOutput(this, 'ProfileJobName', {
      description: 'Name of the DataBrew profile job',
      value: this.profileJob.name!,
      exportName: `${this.stackName}-ProfileJobName`
    });
    
    new cdk.CfnOutput(this, 'EventProcessorFunctionName', {
      description: 'Name of the event processor Lambda function',
      value: this.eventProcessorFunction.functionName,
      exportName: `${this.stackName}-EventProcessorFunctionName`
    });
  }
  
  /**
   * Apply tags to all resources in the stack
   */
  private applyTags(): void {
    cdk.Tags.of(this).add('Project', 'DataQualityPipeline');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Purpose', 'DataQuality');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Create the main stack
new DataQualityPipelineStack(app, 'DataQualityPipelineStack', {
  description: 'Automated Data Quality Pipeline with AWS Glue DataBrew and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  // Optional: Customize stack properties
  environmentSuffix: process.env.ENVIRONMENT_SUFFIX,
  notificationEmail: process.env.NOTIFICATION_EMAIL,
  maxDataBrewCapacity: process.env.MAX_DATABREW_CAPACITY ? 
    parseInt(process.env.MAX_DATABREW_CAPACITY) : undefined,
  dataBrewTimeoutMinutes: process.env.DATABREW_TIMEOUT_MINUTES ? 
    parseInt(process.env.DATABREW_TIMEOUT_MINUTES) : undefined,
  
  // Stack configuration
  stackName: process.env.STACK_NAME || 'DataQualityPipelineStack',
  terminationProtection: false,
  
  // Tags applied to all resources
  tags: {
    Application: 'DataQualityPipeline',
    CostCenter: 'DataEngineering',
    Owner: 'DataTeam'
  }
});

// Enable stack tracing for debugging
if (process.env.CDK_DEBUG === 'true') {
  app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
}

// Synthesize the CDK app
app.synth();