#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as config from 'aws-cdk-lib/aws-config';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as path from 'path';

/**
 * Props for the ComplianceMonitoringStack
 */
export interface ComplianceMonitoringStackProps extends cdk.StackProps {
  /**
   * The name prefix for all resources
   * @default 'ComplianceMonitoring'
   */
  readonly resourcePrefix?: string;

  /**
   * The S3 bucket name for Config delivery channel
   * If not provided, a unique bucket name will be generated
   */
  readonly configBucketName?: string;

  /**
   * Enable automated remediation
   * @default true
   */
  readonly enableRemediation?: boolean;

  /**
   * SNS topic name for notifications
   * If not provided, a unique topic name will be generated
   */
  readonly snsTopicName?: string;

  /**
   * Enable CloudWatch dashboard
   * @default true
   */
  readonly enableDashboard?: boolean;
}

/**
 * AWS CDK Stack for AWS Config Compliance Monitoring
 * 
 * This stack creates a comprehensive compliance monitoring solution using AWS Config
 * with automated remediation capabilities, real-time notifications, and monitoring dashboards.
 * 
 * Key Components:
 * - AWS Config service with delivery channel and configuration recorder
 * - AWS managed Config rules for common compliance scenarios
 * - Custom Lambda-based Config rules for organization-specific policies
 * - Automated remediation Lambda functions
 * - EventBridge rules for real-time remediation triggers
 * - CloudWatch dashboard and alarms for monitoring
 * - SNS topic for compliance notifications
 */
export class ComplianceMonitoringStack extends cdk.Stack {
  
  /** The S3 bucket for Config delivery channel */
  public readonly configBucket: s3.Bucket;
  
  /** The SNS topic for compliance notifications */
  public readonly snsTopic: sns.Topic;
  
  /** The Config delivery channel */
  public readonly deliveryChannel: config.CfnDeliveryChannel;
  
  /** The Config configuration recorder */
  public readonly configurationRecorder: config.CfnConfigurationRecorder;
  
  /** The remediation Lambda function */
  public readonly remediationFunction: lambda.Function;
  
  /** The custom Config rule Lambda function */
  public readonly customRuleFunction: lambda.Function;
  
  /** The CloudWatch dashboard */
  public readonly dashboard?: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: ComplianceMonitoringStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'ComplianceMonitoring';
    const enableRemediation = props.enableRemediation ?? true;
    const enableDashboard = props.enableDashboard ?? true;

    // Create S3 bucket for Config delivery channel
    this.configBucket = this.createConfigBucket(props.configBucketName);

    // Create SNS topic for notifications
    this.snsTopic = this.createSnsTopic(props.snsTopicName);

    // Create IAM roles
    const configServiceRole = this.createConfigServiceRole();
    const lambdaRole = this.createLambdaRole();
    const remediationRole = this.createRemediationRole();

    // Create Config delivery channel and configuration recorder
    this.deliveryChannel = this.createDeliveryChannel();
    this.configurationRecorder = this.createConfigurationRecorder(configServiceRole);

    // Create AWS managed Config rules
    this.createManagedConfigRules();

    // Create custom Lambda function for Config rules
    this.customRuleFunction = this.createCustomRuleFunction(lambdaRole);

    // Create custom Config rule
    this.createCustomConfigRule();

    if (enableRemediation) {
      // Create remediation Lambda function
      this.remediationFunction = this.createRemediationFunction(remediationRole);

      // Create EventBridge rule for automatic remediation
      this.createRemediationEventRule();

      // Create CloudWatch alarms
      this.createCloudWatchAlarms();
    }

    if (enableDashboard) {
      // Create CloudWatch dashboard
      this.dashboard = this.createDashboard();
    }

    // Add outputs
    this.addOutputs();

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ComplianceMonitoring');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'SecurityTeam');
  }

  /**
   * Creates the S3 bucket for Config delivery channel with appropriate permissions and security settings
   */
  private createConfigBucket(bucketName?: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: bucketName,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldConfigData',
          enabled: true,
          expiration: cdk.Duration.days(365),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Add bucket policy for Config service
    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketPermissionsCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:GetBucketAcl', 's3:GetBucketLocation'],
        resources: [bucket.bucketArn],
        conditions: {
          StringEquals: {
            'AWS:SourceAccount': this.account,
          },
        },
      })
    );

    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketExistenceCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:ListBucket'],
        resources: [bucket.bucketArn],
        conditions: {
          StringEquals: {
            'AWS:SourceAccount': this.account,
          },
        },
      })
    );

    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketDelivery',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [`${bucket.bucketArn}/*`],
        conditions: {
          StringEquals: {
            's3:x-amz-acl': 'bucket-owner-full-control',
            'AWS:SourceAccount': this.account,
          },
        },
      })
    );

    return bucket;
  }

  /**
   * Creates the SNS topic for compliance notifications
   */
  private createSnsTopic(topicName?: string): sns.Topic {
    const topic = new sns.Topic(this, 'ComplianceTopic', {
      topicName: topicName,
      displayName: 'AWS Config Compliance Notifications',
    });

    // Add topic policy for Config service
    topic.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigSNSPolicy',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['sns:Publish'],
        resources: [topic.topicArn],
        conditions: {
          StringEquals: {
            'AWS:SourceAccount': this.account,
          },
        },
      })
    );

    return topic;
  }

  /**
   * Creates the IAM role for Config service with necessary permissions
   */
  private createConfigServiceRole(): iam.Role {
    const role = new iam.Role(this, 'ConfigServiceRole', {
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
    });

    // Add permissions for S3 bucket and SNS topic
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetBucketAcl',
          's3:GetBucketLocation',
          's3:GetBucketPolicy',
          's3:ListBucket',
          's3:PutObject',
          's3:GetObject',
          's3:DeleteObject',
        ],
        resources: [
          this.configBucket.bucketArn,
          `${this.configBucket.bucketArn}/*`,
        ],
      })
    );

    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['sns:Publish'],
        resources: [this.snsTopic.topicArn],
      })
    );

    return role;
  }

  /**
   * Creates the IAM role for Lambda functions used in Config rules
   */
  private createLambdaRole(): iam.Role {
    const role = new iam.Role(this, 'ConfigLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSConfigRulesExecutionRole'),
      ],
    });

    return role;
  }

  /**
   * Creates the IAM role for remediation Lambda functions
   */
  private createRemediationRole(): iam.Role {
    const role = new iam.Role(this, 'RemediationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add permissions for remediation actions
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ec2:DescribeInstances',
          'ec2:CreateTags',
          'ec2:AuthorizeSecurityGroupIngress',
          'ec2:RevokeSecurityGroupIngress',
          'ec2:DescribeSecurityGroups',
          's3:PutBucketPublicAccessBlock',
          's3:GetBucketPublicAccessBlock',
        ],
        resources: ['*'],
      })
    );

    return role;
  }

  /**
   * Creates the Config delivery channel
   */
  private createDeliveryChannel(): config.CfnDeliveryChannel {
    return new config.CfnDeliveryChannel(this, 'DeliveryChannel', {
      name: 'default',
      s3BucketName: this.configBucket.bucketName,
      snsTopicArn: this.snsTopic.topicArn,
      configSnapshotDeliveryProperties: {
        deliveryFrequency: 'TwentyFour_Hours',
      },
    });
  }

  /**
   * Creates the Config configuration recorder
   */
  private createConfigurationRecorder(serviceRole: iam.Role): config.CfnConfigurationRecorder {
    const recorder = new config.CfnConfigurationRecorder(this, 'ConfigurationRecorder', {
      name: 'default',
      roleArn: serviceRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
        resourceTypes: [],
      },
    });

    // Ensure delivery channel is created before recorder
    recorder.addDependency(this.deliveryChannel);

    return recorder;
  }

  /**
   * Creates AWS managed Config rules for common compliance scenarios
   */
  private createManagedConfigRules(): void {
    // S3 bucket public access prohibited
    new config.CfnConfigRule(this, 'S3BucketPublicAccessProhibited', {
      configRuleName: 's3-bucket-public-access-prohibited',
      description: 'Checks that S3 buckets do not allow public access',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'S3_BUCKET_PUBLIC_ACCESS_PROHIBITED',
      },
      scope: {
        complianceResourceTypes: ['AWS::S3::Bucket'],
      },
    });

    // Encrypted EBS volumes
    new config.CfnConfigRule(this, 'EncryptedVolumes', {
      configRuleName: 'encrypted-volumes',
      description: 'Checks whether EBS volumes are encrypted',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'ENCRYPTED_VOLUMES',
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::Volume'],
      },
    });

    // Root access key check
    new config.CfnConfigRule(this, 'RootAccessKeyCheck', {
      configRuleName: 'root-access-key-check',
      description: 'Checks whether root access keys exist',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'ROOT_ACCESS_KEY_CHECK',
      },
    });

    // Required tags for EC2 instances
    new config.CfnConfigRule(this, 'RequiredTagsEc2', {
      configRuleName: 'required-tags-ec2',
      description: 'Checks whether EC2 instances have required tags',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'REQUIRED_TAGS',
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::Instance'],
      },
      inputParameters: JSON.stringify({
        tag1Key: 'Environment',
        tag2Key: 'Owner',
      }),
    });
  }

  /**
   * Creates the custom Lambda function for Config rules
   */
  private createCustomRuleFunction(role: iam.Role): lambda.Function {
    return new lambda.Function(this, 'CustomRuleFunction', {
      functionName: `ConfigSecurityGroupRule-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.seconds(60),
      code: lambda.Code.fromInline(`
import boto3
import json

def lambda_handler(event, context):
    """
    Custom Config rule to check security group configurations
    Evaluates whether security groups allow unrestricted ingress except for ports 80 and 443
    """
    # Initialize AWS Config client
    config = boto3.client('config')
    
    # Get configuration item from event
    configuration_item = event['configurationItem']
    
    # Initialize compliance status
    compliance_status = 'COMPLIANT'
    
    try:
        # Check if resource is a Security Group
        if configuration_item['resourceType'] == 'AWS::EC2::SecurityGroup':
            # Get security group configuration
            sg_config = configuration_item['configuration']
            
            # Check for overly permissive ingress rules
            for rule in sg_config.get('ipPermissions', []):
                for ip_range in rule.get('ipRanges', []):
                    if ip_range.get('cidrIp') == '0.0.0.0/0':
                        # Check if it's not port 80 or 443
                        from_port = rule.get('fromPort')
                        if from_port not in [80, 443]:
                            compliance_status = 'NON_COMPLIANT'
                            break
                if compliance_status == 'NON_COMPLIANT':
                    break
        
        # Put evaluation result
        config.put_evaluations(
            Evaluations=[
                {
                    'ComplianceResourceType': configuration_item['resourceType'],
                    'ComplianceResourceId': configuration_item['resourceId'],
                    'ComplianceType': compliance_status,
                    'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
                }
            ],
            ResultToken=event['resultToken']
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Config rule evaluation completed successfully')
        }
        
    except Exception as e:
        print(f"Error evaluating config rule: {str(e)}")
        # Put failed evaluation
        config.put_evaluations(
            Evaluations=[
                {
                    'ComplianceResourceType': configuration_item['resourceType'],
                    'ComplianceResourceId': configuration_item['resourceId'],
                    'ComplianceType': 'NOT_APPLICABLE',
                    'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
                }
            ],
            ResultToken=event['resultToken']
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Config rule evaluation failed: {str(e)}')
        }
      `),
    });
  }

  /**
   * Creates the custom Config rule using the Lambda function
   */
  private createCustomConfigRule(): void {
    // Add permission for Config to invoke Lambda
    this.customRuleFunction.addPermission('ConfigPermission', {
      principal: new iam.ServicePrincipal('config.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceAccount: this.account,
    });

    // Create custom Config rule
    new config.CfnConfigRule(this, 'SecurityGroupRestrictedIngress', {
      configRuleName: 'security-group-restricted-ingress',
      description: 'Checks that security groups do not allow unrestricted ingress except for ports 80 and 443',
      source: {
        owner: 'CUSTOM_LAMBDA',
        sourceIdentifier: this.customRuleFunction.functionArn,
        sourceDetails: [
          {
            eventSource: 'aws.config',
            messageType: 'ConfigurationItemChangeNotification',
          },
        ],
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::SecurityGroup'],
      },
    });
  }

  /**
   * Creates the remediation Lambda function for automatic compliance fixes
   */
  private createRemediationFunction(role: iam.Role): lambda.Function {
    return new lambda.Function(this, 'RemediationFunction', {
      functionName: `ConfigRemediation-${this.stackName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: role,
      timeout: cdk.Duration.seconds(60),
      code: lambda.Code.fromInline(`
import boto3
import json

def lambda_handler(event, context):
    """
    Automated remediation function for Config compliance violations
    Handles common violations like missing tags and public S3 access
    """
    ec2 = boto3.client('ec2')
    s3 = boto3.client('s3')
    
    try:
        # Parse the event
        detail = event['detail']
        config_rule_name = detail['configRuleName']
        compliance_type = detail['newEvaluationResult']['complianceType']
        resource_type = detail['resourceType']
        resource_id = detail['resourceId']
        
        print(f"Processing remediation for rule: {config_rule_name}")
        print(f"Resource: {resource_type}:{resource_id}")
        print(f"Compliance: {compliance_type}")
        
        if compliance_type == 'NON_COMPLIANT':
            if config_rule_name == 'required-tags-ec2' and resource_type == 'AWS::EC2::Instance':
                # Add missing tags to EC2 instance
                ec2.create_tags(
                    Resources=[resource_id],
                    Tags=[
                        {'Key': 'Environment', 'Value': 'Unknown'},
                        {'Key': 'Owner', 'Value': 'Unknown'}
                    ]
                )
                print(f"Added missing tags to EC2 instance {resource_id}")
            
            elif config_rule_name == 's3-bucket-public-access-prohibited' and resource_type == 'AWS::S3::Bucket':
                # Block public access on S3 bucket
                try:
                    s3.put_public_access_block(
                        Bucket=resource_id,
                        PublicAccessBlockConfiguration={
                            'BlockPublicAcls': True,
                            'IgnorePublicAcls': True,
                            'BlockPublicPolicy': True,
                            'RestrictPublicBuckets': True
                        }
                    )
                    print(f"Blocked public access on S3 bucket {resource_id}")
                except Exception as e:
                    print(f"Failed to remediate S3 bucket {resource_id}: {str(e)}")
            
            else:
                print(f"No remediation available for rule: {config_rule_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Remediation completed successfully')
        }
        
    except Exception as e:
        print(f"Error during remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Remediation failed: {str(e)}')
        }
      `),
    });
  }

  /**
   * Creates EventBridge rule for automatic remediation triggers
   */
  private createRemediationEventRule(): void {
    // Add permission for EventBridge to invoke Lambda
    this.remediationFunction.addPermission('EventBridgePermission', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });

    // Create EventBridge rule for Config compliance changes
    const rule = new events.Rule(this, 'ConfigComplianceRule', {
      ruleName: `ConfigComplianceRule-${this.stackName}`,
      description: 'Triggers remediation when Config detects non-compliant resources',
      eventPattern: {
        source: ['aws.config'],
        detailType: ['Config Rules Compliance Change'],
        detail: {
          newEvaluationResult: {
            complianceType: ['NON_COMPLIANT'],
          },
        },
      },
    });

    // Add Lambda function as target
    rule.addTarget(new targets.LambdaFunction(this.remediationFunction));
  }

  /**
   * Creates CloudWatch alarms for monitoring compliance and remediation
   */
  private createCloudWatchAlarms(): void {
    // Alarm for non-compliant resources
    new cloudwatch.Alarm(this, 'NonCompliantResourcesAlarm', {
      alarmName: `ConfigNonCompliantResources-${this.stackName}`,
      alarmDescription: 'Alert when non-compliant resources are detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Config',
        metricName: 'ComplianceByConfigRule',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Alarm for remediation function errors
    new cloudwatch.Alarm(this, 'RemediationErrorsAlarm', {
      alarmName: `ConfigRemediationErrors-${this.stackName}`,
      alarmDescription: 'Alert when remediation function encounters errors',
      metric: this.remediationFunction.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
    });

    // Both alarms can be configured to send notifications to the SNS topic
    // This would require adding SNS actions to the alarms
  }

  /**
   * Creates CloudWatch dashboard for compliance monitoring
   */
  private createDashboard(): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'ComplianceDashboard', {
      dashboardName: `ConfigComplianceDashboard-${this.stackName}`,
    });

    // Add widget for Config rule compliance status
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Config Rule Compliance Status',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 's3-bucket-public-access-prohibited',
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 'encrypted-volumes',
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 'root-access-key-check',
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 'required-tags-ec2',
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 'security-group-restricted-ingress',
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add widget for remediation function metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Remediation Function Metrics',
        left: [
          this.remediationFunction.metricInvocations({
            period: cdk.Duration.minutes(5),
          }),
          this.remediationFunction.metricErrors({
            period: cdk.Duration.minutes(5),
          }),
          this.remediationFunction.metricDuration({
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    return dashboard;
  }

  /**
   * Adds CloudFormation outputs for important resource information
   */
  private addOutputs(): void {
    new cdk.CfnOutput(this, 'ConfigBucketName', {
      value: this.configBucket.bucketName,
      description: 'Name of the S3 bucket for Config delivery channel',
      exportName: `${this.stackName}-ConfigBucketName`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'ARN of the SNS topic for compliance notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'RemediationFunctionArn', {
      value: this.remediationFunction?.functionArn || 'Not created',
      description: 'ARN of the Lambda function for automated remediation',
      exportName: `${this.stackName}-RemediationFunctionArn`,
    });

    new cdk.CfnOutput(this, 'CustomRuleFunctionArn', {
      value: this.customRuleFunction.functionArn,
      description: 'ARN of the Lambda function for custom Config rules',
      exportName: `${this.stackName}-CustomRuleFunctionArn`,
    });

    if (this.dashboard) {
      new cdk.CfnOutput(this, 'DashboardUrl', {
        value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
        description: 'URL to the CloudWatch dashboard for compliance monitoring',
        exportName: `${this.stackName}-DashboardUrl`,
      });
    }
  }
}

/**
 * CDK App for AWS Config Compliance Monitoring
 */
const app = new cdk.App();

// Create the compliance monitoring stack
new ComplianceMonitoringStack(app, 'ComplianceMonitoringStack', {
  description: 'AWS Config compliance monitoring with automated remediation',
  
  // Stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Uncomment and customize these properties as needed:
  // resourcePrefix: 'MyOrg',
  // configBucketName: 'my-config-bucket-unique-name',
  // enableRemediation: true,
  // snsTopicName: 'my-compliance-topic',
  // enableDashboard: true,
  
  // Add termination protection for production deployments
  terminationProtection: false,
});

// Synthesize the CloudFormation template
app.synth();