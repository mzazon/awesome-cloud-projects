#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sns_subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as config from 'aws-cdk-lib/aws-config';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as events_targets from 'aws-cdk-lib/aws-events-targets';
import * as resource_groups from 'aws-cdk-lib/aws-resourcegroups';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';

/**
 * Interface for tag taxonomy configuration
 */
interface TagTaxonomy {
  readonly requiredTags: Record<string, TagDefinition>;
  readonly optionalTags: Record<string, TagDefinition>;
}

interface TagDefinition {
  readonly description: string;
  readonly values: string[];
  readonly validation: string;
}

/**
 * Properties for the ResourceTaggingStrategiesStack
 */
export interface ResourceTaggingStrategiesStackProps extends cdk.StackProps {
  /**
   * Email address for tag compliance notifications
   */
  readonly notificationEmail: string;
  
  /**
   * Environment prefix for resource naming
   * @default 'cost-mgmt'
   */
  readonly environmentPrefix?: string;
  
  /**
   * Create demo resources to demonstrate tagging
   * @default true
   */
  readonly createDemoResources?: boolean;
  
  /**
   * Tag taxonomy configuration
   */
  readonly tagTaxonomy?: TagTaxonomy;
}

/**
 * AWS CDK Stack for implementing comprehensive resource tagging strategies
 * for cost management and governance. This stack creates:
 * 
 * - AWS Config for tag compliance monitoring
 * - Config Rules for required tag validation
 * - SNS notifications for compliance alerts
 * - Lambda function for automated tag remediation
 * - Resource Groups for tag-based organization
 * - Demo resources with proper tagging examples
 */
export class ResourceTaggingStrategiesStack extends cdk.Stack {
  
  /**
   * SNS topic for tag compliance notifications
   */
  public readonly notificationTopic: sns.Topic;
  
  /**
   * S3 bucket for AWS Config storage
   */
  public readonly configBucket: s3.Bucket;
  
  /**
   * Lambda function for tag remediation
   */
  public readonly remediationFunction: lambda.Function;
  
  /**
   * Default tag taxonomy for the organization
   */
  private readonly defaultTagTaxonomy: TagTaxonomy = {
    requiredTags: {
      'CostCenter': {
        description: 'Department or cost center for chargeback',
        values: ['Engineering', 'Marketing', 'Sales', 'Finance', 'Operations'],
        validation: 'Must be one of predefined cost centers'
      },
      'Environment': {
        description: 'Deployment environment',
        values: ['Production', 'Staging', 'Development', 'Testing'],
        validation: 'Must be one of four environments'
      },
      'Project': {
        description: 'Project or application name',
        values: ['*'],
        validation: 'Must be 3-50 characters, alphanumeric and hyphens only'
      },
      'Owner': {
        description: 'Resource owner email',
        values: ['*'],
        validation: 'Must be valid email format'
      }
    },
    optionalTags: {
      'Application': {
        description: 'Application component',
        values: ['web', 'api', 'database', 'cache', 'queue'],
        validation: 'Recommended for application resources'
      },
      'Backup': {
        description: 'Backup requirement',
        values: ['true', 'false'],
        validation: 'Boolean value for backup automation'
      }
    }
  };

  constructor(scope: Construct, id: string, props: ResourceTaggingStrategiesStackProps) {
    super(scope, id, props);

    const environmentPrefix = props.environmentPrefix || 'cost-mgmt';
    const tagTaxonomy = props.tagTaxonomy || this.defaultTagTaxonomy;
    
    // Apply standard tags to the stack
    this.applyStandardTags();

    // Create SNS topic for notifications
    this.notificationTopic = this.createNotificationTopic(props.notificationEmail, environmentPrefix);

    // Create S3 bucket for AWS Config
    this.configBucket = this.createConfigBucket(environmentPrefix);

    // Create and configure AWS Config
    this.setupAwsConfig();

    // Create Lambda function for tag remediation
    this.remediationFunction = this.createRemediationFunction(environmentPrefix);

    // Create Config rules for tag compliance
    this.createConfigRules(tagTaxonomy);

    // Create Resource Groups for cost allocation
    this.createResourceGroups(environmentPrefix);

    // Create demo resources if requested
    if (props.createDemoResources !== false) {
      this.createDemoResources(environmentPrefix);
    }

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Apply standard tags to all resources in the stack
   */
  private applyStandardTags(): void {
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Project', 'TaggingStrategy');
    cdk.Tags.of(this).add('Owner', 'devops@company.com');
    cdk.Tags.of(this).add('Application', 'governance');
    cdk.Tags.of(this).add('Purpose', 'CostManagement');
    cdk.Tags.of(this).add('AutoTagged', 'false');
  }

  /**
   * Create SNS topic for tag compliance notifications
   */
  private createNotificationTopic(notificationEmail: string, environmentPrefix: string): sns.Topic {
    const topic = new sns.Topic(this, 'TagComplianceTopic', {
      topicName: `tag-compliance-${environmentPrefix}`,
      displayName: 'Tag Compliance Notifications',
      description: 'Notifications for resource tag compliance violations and remediation actions'
    });

    // Subscribe email address to the topic
    topic.addSubscription(new sns_subscriptions.EmailSubscription(notificationEmail));

    return topic;
  }

  /**
   * Create S3 bucket for AWS Config storage
   */
  private createConfigBucket(environmentPrefix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `aws-config-${environmentPrefix}-${this.account}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'ConfigLogRetention',
          expiration: cdk.Duration.days(2555), // 7 years
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365)
            }
          ]
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true // For demo purposes - remove in production
    });

    // Grant AWS Config service access to the bucket
    bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AWSConfigBucketPermissionsCheck',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('config.amazonaws.com')],
      actions: ['s3:GetBucketAcl', 's3:ListBucket'],
      resources: [bucket.bucketArn],
      conditions: {
        StringEquals: {
          'AWS:SourceAccount': this.account
        }
      }
    }));

    bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AWSConfigBucketExistenceCheck',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('config.amazonaws.com')],
      actions: ['s3:ListBucket'],
      resources: [bucket.bucketArn],
      conditions: {
        StringEquals: {
          'AWS:SourceAccount': this.account
        }
      }
    }));

    bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AWSConfigBucketDelivery',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('config.amazonaws.com')],
      actions: ['s3:PutObject'],
      resources: [`${bucket.bucketArn}/AWSLogs/${this.account}/Config/*`],
      conditions: {
        StringEquals: {
          's3:x-amz-acl': 'bucket-owner-full-control',
          'AWS:SourceAccount': this.account
        }
      }
    }));

    return bucket;
  }

  /**
   * Setup AWS Config service with delivery channel and configuration recorder
   */
  private setupAwsConfig(): void {
    // Create IAM role for AWS Config
    const configRole = new iam.Role(this, 'ConfigRole', {
      roleName: `aws-config-role-${this.stackName}`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole')
      ],
      description: 'Service role for AWS Config to monitor resource configurations'
    });

    // Create delivery channel
    new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      name: 'default',
      s3BucketName: this.configBucket.bucketName,
      configSnapshotDeliveryProperties: {
        deliveryFrequency: 'TwentyFour_Hours'
      }
    });

    // Create configuration recorder
    new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      name: 'default',
      roleArn: configRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
        resourceTypes: undefined // Use allSupported instead
      }
    });
  }

  /**
   * Create Lambda function for automated tag remediation
   */
  private createRemediationFunction(environmentPrefix: string): lambda.Function {
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'RemediationLambdaRole', {
      roleName: `tag-remediation-lambda-role-${environmentPrefix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      description: 'Role for Lambda function to perform automated tag remediation'
    });

    // Add permissions for tag operations
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:CreateTags',
        'ec2:DescribeTags',
        's3:GetBucketTagging',
        's3:PutBucketTagging',
        'rds:AddTagsToResource',
        'rds:ListTagsForResource',
        'lambda:TagResource',
        'lambda:ListTags',
        'config:GetComplianceDetailsByConfigRule',
        'config:GetConfigurationRecorder'
      ],
      resources: ['*']
    }));

    // Add SNS publish permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [this.notificationTopic.topicArn]
    }));

    // Create Lambda function
    const fn = new lambda.Function(this, 'TagRemediationFunction', {
      functionName: `tag-remediation-${environmentPrefix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Automated tag remediation for cost management compliance',
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        REQUIRED_TAGS: JSON.stringify(['CostCenter', 'Environment', 'Project', 'Owner'])
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Automated tag remediation function for AWS Config rule violations
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Initialize AWS clients
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    rds = boto3.client('rds')
    sns = boto3.client('sns')
    
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Handle Config rule evaluation result
        if 'configurationItem' in event:
            config_item = event['configurationItem']
            resource_type = config_item['resourceType']
            resource_id = config_item['resourceId']
            
            # Generate default tags
            default_tags = get_default_tags(config_item)
            
            # Apply tags based on resource type
            if resource_type == 'AWS::EC2::Instance' and default_tags:
                ec2.create_tags(Resources=[resource_id], Tags=default_tags)
                logger.info(f"Applied tags to EC2 instance {resource_id}")
            elif resource_type == 'AWS::S3::Bucket' and default_tags:
                tag_set = [{'Key': tag['Key'], 'Value': tag['Value']} for tag in default_tags]
                s3.put_bucket_tagging(Bucket=resource_id, Tagging={'TagSet': tag_set})
                logger.info(f"Applied tags to S3 bucket {resource_id}")
            elif resource_type == 'AWS::RDS::DBInstance' and default_tags:
                db_arn = f"arn:aws:rds:{context.invoked_function_arn.split(':')[3]}:{context.invoked_function_arn.split(':')[4]}:db:{resource_id}"
                rds.add_tags_to_resource(ResourceName=db_arn, Tags=default_tags)
                logger.info(f"Applied tags to RDS instance {resource_id}")
            
            # Send notification
            if default_tags:
                send_notification(sns, sns_topic_arn, resource_type, resource_id, default_tags)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Tag remediation completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in tag remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def get_default_tags(config_item):
    """Generate default tags for non-compliant resources"""
    tags = []
    existing_tags = config_item.get('tags', {})
    
    # Add default tags if missing
    if 'CostCenter' not in existing_tags:
        tags.append({'Key': 'CostCenter', 'Value': 'Unassigned'})
    
    if 'Environment' not in existing_tags:
        tags.append({'Key': 'Environment', 'Value': 'Development'})
    
    if 'Project' not in existing_tags:
        tags.append({'Key': 'Project', 'Value': 'UntaggedResource'})
    
    if 'Owner' not in existing_tags:
        tags.append({'Key': 'Owner', 'Value': 'unknown@company.com'})
    
    # Add auto-tagging marker
    tags.append({'Key': 'AutoTagged', 'Value': f"true-{datetime.now().strftime('%Y%m%d')}"})
    
    return tags

def send_notification(sns, topic_arn, resource_type, resource_id, tags):
    """Send SNS notification about tag remediation"""
    message = f"""
Tag Remediation Notification

Resource Type: {resource_type}
Resource ID: {resource_id}
Auto-Applied Tags: {json.dumps(tags, indent=2)}

Please review and update tags as needed in the AWS Console.
Timestamp: {datetime.now().isoformat()}
"""
    
    sns.publish(
        TopicArn=topic_arn,
        Subject=f'Auto-Tag Applied: {resource_type}',
        Message=message
    )
`)
    });

    return fn;
  }

  /**
   * Create AWS Config rules for tag compliance monitoring
   */
  private createConfigRules(tagTaxonomy: TagTaxonomy): void {
    // Create Config rules for each required tag
    Object.entries(tagTaxonomy.requiredTags).forEach(([tagKey, tagDef]) => {
      const ruleName = `required-tag-${tagKey.toLowerCase()}`;
      
      // Prepare input parameters based on tag definition
      const inputParameters: Record<string, string> = {
        tag1Key: tagKey
      };
      
      // Add tag values if specified (not wildcard)
      if (tagDef.values.length > 0 && !tagDef.values.includes('*')) {
        inputParameters.tag1Value = tagDef.values.join(',');
      }

      new config.ManagedRule(this, `ConfigRule${tagKey}`, {
        configRuleName: ruleName,
        description: `Checks if resources have required ${tagKey} tag`,
        identifier: config.ManagedRuleIdentifiers.REQUIRED_TAGS,
        inputParameters: inputParameters,
        ruleScope: config.RuleScope.fromResources([
          config.ResourceType.EC2_INSTANCE,
          config.ResourceType.S3_BUCKET,
          config.ResourceType.RDS_DB_INSTANCE,
          config.ResourceType.LAMBDA_FUNCTION
        ])
      });
    });

    // Create EventBridge rule to trigger remediation function
    const configEventRule = new events.Rule(this, 'ConfigComplianceEventRule', {
      ruleName: `config-compliance-${this.stackName}`,
      description: 'Triggers tag remediation on Config compliance changes',
      eventPattern: {
        source: ['aws.config'],
        detailType: ['Config Rules Compliance Change'],
        detail: {
          newEvaluationResult: {
            complianceType: ['NON_COMPLIANT']
          }
        }
      }
    });

    configEventRule.addTarget(new events_targets.LambdaFunction(this.remediationFunction));
  }

  /**
   * Create Resource Groups for tag-based resource organization
   */
  private createResourceGroups(environmentPrefix: string): void {
    // Resource group for Production environment
    new resource_groups.CfnGroup(this, 'ProductionResourceGroup', {
      name: `Production-Environment-${environmentPrefix}`,
      description: 'Resources in Production environment for cost allocation',
      resourceQuery: {
        type: 'TAG_FILTERS_1_0',
        query: JSON.stringify({
          ResourceTypeFilters: ['AWS::AllSupported'],
          TagFilters: [
            {
              Key: 'Environment',
              Values: ['Production']
            }
          ]
        })
      },
      tags: [
        { key: 'Environment', value: 'Production' },
        { key: 'Purpose', value: 'CostAllocation' }
      ]
    });

    // Resource group for Engineering cost center
    new resource_groups.CfnGroup(this, 'EngineeringResourceGroup', {
      name: `Engineering-CostCenter-${environmentPrefix}`,
      description: 'Resources in Engineering cost center for chargeback',
      resourceQuery: {
        type: 'TAG_FILTERS_1_0',
        query: JSON.stringify({
          ResourceTypeFilters: ['AWS::AllSupported'],
          TagFilters: [
            {
              Key: 'CostCenter',
              Values: ['Engineering']
            }
          ]
        })
      },
      tags: [
        { key: 'CostCenter', value: 'Engineering' },
        { key: 'Purpose', value: 'CostAllocation' }
      ]
    });

    // Resource group for Marketing cost center
    new resource_groups.CfnGroup(this, 'MarketingResourceGroup', {
      name: `Marketing-CostCenter-${environmentPrefix}`,
      description: 'Resources in Marketing cost center for chargeback',
      resourceQuery: {
        type: 'TAG_FILTERS_1_0',
        query: JSON.stringify({
          ResourceTypeFilters: ['AWS::AllSupported'],
          TagFilters: [
            {
              Key: 'CostCenter',
              Values: ['Marketing']
            }
          ]
        })
      },
      tags: [
        { key: 'CostCenter', value: 'Marketing' },
        { key: 'Purpose', value: 'CostAllocation' }
      ]
    });
  }

  /**
   * Create demo resources to showcase proper tagging
   */
  private createDemoResources(environmentPrefix: string): void {
    // Get default VPC for demo resources
    const defaultVpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // Demo S3 bucket with comprehensive tagging
    const demoBucket = new s3.Bucket(this, 'DemoBucket', {
      bucketName: `cost-mgmt-demo-${environmentPrefix}-${this.account}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Apply tags to demo bucket
    cdk.Tags.of(demoBucket).add('CostCenter', 'Marketing');
    cdk.Tags.of(demoBucket).add('Environment', 'Production');
    cdk.Tags.of(demoBucket).add('Project', 'WebAssets');
    cdk.Tags.of(demoBucket).add('Owner', 'marketing@company.com');
    cdk.Tags.of(demoBucket).add('Application', 'web');
    cdk.Tags.of(demoBucket).add('Backup', 'true');

    // Demo RDS instance with proper tagging
    const demoDatabase = new rds.DatabaseInstance(this, 'DemoDatabase', {
      instanceIdentifier: `cost-mgmt-demo-db-${environmentPrefix}`,
      engine: rds.DatabaseEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      vpc: defaultVpc,
      allocatedStorage: 20,
      storageType: rds.StorageType.GP2,
      databaseName: 'demodb',
      credentials: rds.Credentials.fromGeneratedSecret('admin'),
      backupRetention: cdk.Duration.days(1),
      deletionProtection: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Apply tags to demo database
    cdk.Tags.of(demoDatabase).add('CostCenter', 'Engineering');
    cdk.Tags.of(demoDatabase).add('Environment', 'Development');
    cdk.Tags.of(demoDatabase).add('Project', 'TaggingDemo');
    cdk.Tags.of(demoDatabase).add('Owner', 'devops@company.com');
    cdk.Tags.of(demoDatabase).add('Application', 'database');
    cdk.Tags.of(demoDatabase).add('Backup', 'true');

    // Demo Lambda function with tagging
    const demoFunction = new lambda.Function(this, 'DemoFunction', {
      functionName: `cost-mgmt-demo-function-${environmentPrefix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      description: 'Demo function to showcase proper resource tagging',
      code: lambda.Code.fromInline(`
def handler(event, context):
    return {
        'statusCode': 200,
        'body': 'Demo function for tagging strategy demonstration'
    }
`)
    });

    // Apply tags to demo function
    cdk.Tags.of(demoFunction).add('CostCenter', 'Engineering');
    cdk.Tags.of(demoFunction).add('Environment', 'Development');
    cdk.Tags.of(demoFunction).add('Project', 'TaggingDemo');
    cdk.Tags.of(demoFunction).add('Owner', 'devops@company.com');
    cdk.Tags.of(demoFunction).add('Application', 'api');
    cdk.Tags.of(demoFunction).add('Backup', 'false');
  }

  /**
   * Create CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for tag compliance notifications',
      exportName: `${this.stackName}-NotificationTopicArn`
    });

    new cdk.CfnOutput(this, 'ConfigBucketName', {
      value: this.configBucket.bucketName,
      description: 'Name of the S3 bucket used by AWS Config',
      exportName: `${this.stackName}-ConfigBucketName`
    });

    new cdk.CfnOutput(this, 'RemediationFunctionArn', {
      value: this.remediationFunction.functionArn,
      description: 'ARN of the Lambda function for automated tag remediation',
      exportName: `${this.stackName}-RemediationFunctionArn`
    });

    new cdk.CfnOutput(this, 'TagTaxonomyGuidance', {
      value: 'https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html',
      description: 'AWS documentation for tagging best practices'
    });

    new cdk.CfnOutput(this, 'CostExplorerLink', {
      value: `https://${this.region}.console.aws.amazon.com/cost-management/home#/cost-explorer`,
      description: 'Link to AWS Cost Explorer for cost analysis by tags'
    });
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;

if (!notificationEmail) {
  throw new Error('Notification email is required. Set NOTIFICATION_EMAIL environment variable or pass notificationEmail in CDK context.');
}

const environmentPrefix = app.node.tryGetContext('environmentPrefix') || process.env.ENVIRONMENT_PREFIX || 'cost-mgmt';
const createDemoResources = app.node.tryGetContext('createDemoResources') !== 'false';

// Create the stack
new ResourceTaggingStrategiesStack(app, 'ResourceTaggingStrategiesStack', {
  notificationEmail: notificationEmail,
  environmentPrefix: environmentPrefix,
  createDemoResources: createDemoResources,
  
  // Standard stack properties
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  description: 'AWS CDK Stack for implementing comprehensive resource tagging strategies for cost management and governance',
  
  tags: {
    Project: 'ResourceTaggingStrategies',
    Component: 'CostManagement',
    ManagedBy: 'CDK'
  }
});

app.synth();