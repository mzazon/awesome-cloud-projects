import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as resourcegroups from 'aws-cdk-lib/aws-resourcegroups';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as ce from 'aws-cdk-lib/aws-ce';

export interface ResourceGroupsAutomationStackProps extends cdk.StackProps {
  resourceGroupName: string;
  notificationEmail?: string;
  budgetAmount: number;
}

/**
 * AWS Resource Groups Automated Resource Management Stack
 * 
 * This stack creates a comprehensive resource management solution including:
 * - Tag-based resource groups for logical organization
 * - Systems Manager automation for resource management
 * - CloudWatch monitoring with custom dashboards
 * - SNS notifications for proactive alerting
 * - Cost tracking with AWS Budgets
 * - Automated resource tagging via EventBridge
 */
export class ResourceGroupsAutomationStack extends cdk.Stack {
  public readonly resourceGroup: resourcegroups.CfnGroup;
  public readonly notificationTopic: sns.Topic;
  public readonly automationRole: iam.Role;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: ResourceGroupsAutomationStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Fn.select(2, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', this.stackId))));

    // Create SNS topic for notifications
    this.notificationTopic = this.createNotificationSystem(props.notificationEmail, uniqueSuffix);

    // Create IAM role for Systems Manager automation
    this.automationRole = this.createAutomationRole(uniqueSuffix);

    // Create resource group for organizing resources
    this.resourceGroup = this.createResourceGroup(props.resourceGroupName);

    // Create Systems Manager automation documents
    this.createSystemsManagerAutomation(props.resourceGroupName, uniqueSuffix);

    // Create CloudWatch monitoring and dashboards
    this.dashboard = this.createMonitoringSystem(uniqueSuffix);

    // Create cost tracking and budgets
    this.createCostTracking(props.budgetAmount, uniqueSuffix);

    // Create automated resource tagging system
    this.createAutomatedTagging(uniqueSuffix);

    // Output important resource information
    this.createOutputs(props.resourceGroupName, uniqueSuffix);
  }

  /**
   * Creates SNS topic and subscription for notifications
   */
  private createNotificationSystem(notificationEmail: string | undefined, uniqueSuffix: string): sns.Topic {
    // Create SNS topic with encryption
    const topic = new sns.Topic(this, 'ResourceAlertsTopic', {
      displayName: `Resource Management Alerts - ${uniqueSuffix}`,
      topicName: `resource-alerts-${uniqueSuffix}`,
      // Enable server-side encryption for sensitive notifications
      masterKey: cdk.aws_kms.Alias.fromAliasName(this, 'SnsKey', 'alias/aws/sns'),
    });

    // Add email subscription if provided
    if (notificationEmail) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(notificationEmail));
    }

    // Apply tags for resource organization
    cdk.Tags.of(topic).add('Component', 'Notifications');
    cdk.Tags.of(topic).add('Purpose', 'ResourceManagement');

    return topic;
  }

  /**
   * Creates IAM role for Systems Manager automation with appropriate permissions
   */
  private createAutomationRole(uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'AutomationRole', {
      roleName: `ResourceGroupAutomationRole-${uniqueSuffix}`,
      description: 'IAM role for Systems Manager automation and resource management',
      assumedBy: new iam.ServicePrincipal('ssm.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMAutomationRole'),
      ],
    });

    // Add custom permissions for resource group management
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'resource-groups:ListGroupResources',
        'resource-groups:GetGroup',
        'resource-groups:SearchResources',
        'resourcegroupstaggingapi:GetResources',
        'resourcegroupstaggingapi:TagResources',
        'resourcegroupstaggingapi:UntagResources',
        'tag:GetResources',
        'tag:TagResources',
        'tag:UntagResources',
      ],
      resources: ['*'],
      conditions: {
        StringEquals: {
          'aws:RequestedRegion': this.region,
        },
      },
    }));

    // Add permissions for CloudWatch metrics
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData',
        'cloudwatch:ListMetrics',
        'cloudwatch:GetMetricStatistics',
      ],
      resources: ['*'],
    }));

    cdk.Tags.of(role).add('Component', 'Automation');
    cdk.Tags.of(role).add('Purpose', 'SystemsManagerAutomation');

    return role;
  }

  /**
   * Creates tag-based resource group for logical organization
   */
  private createResourceGroup(resourceGroupName: string): resourcegroups.CfnGroup {
    const resourceGroup = new resourcegroups.CfnGroup(this, 'ResourceGroup', {
      name: resourceGroupName,
      description: 'Production web application resources organized by tags',
      resourceQuery: {
        type: 'TAG_FILTERS_1_0',
        query: {
          resourceTypeFilters: ['AWS::AllSupported'],
          tagFilters: [
            {
              key: 'Environment',
              values: ['production'],
            },
            {
              key: 'Application',
              values: ['web-app'],
            },
          ],
        },
      },
      tags: [
        { key: 'Environment', value: 'production' },
        { key: 'Application', value: 'web-app' },
        { key: 'Purpose', value: 'resource-management' },
        { key: 'Component', value: 'ResourceGroup' },
      ],
    });

    return resourceGroup;
  }

  /**
   * Creates Systems Manager automation documents for resource management
   */
  private createSystemsManagerAutomation(resourceGroupName: string, uniqueSuffix: string): void {
    // Resource group maintenance automation document
    new ssm.CfnDocument(this, 'ResourceGroupMaintenanceDocument', {
      documentType: 'Automation',
      documentFormat: 'YAML',
      name: `ResourceGroupMaintenance-${uniqueSuffix}`,
      content: {
        schemaVersion: '0.3',
        description: 'Automated maintenance and health checks for resource group',
        assumeRole: this.automationRole.roleArn,
        parameters: {
          ResourceGroupName: {
            type: 'String',
            description: 'Name of the resource group to process',
            default: resourceGroupName,
          },
        },
        mainSteps: [
          {
            name: 'GetResourceGroupResources',
            action: 'aws:executeAwsApi',
            description: 'Retrieve all resources in the specified resource group',
            inputs: {
              Service: 'resource-groups',
              Api: 'ListGroupResources',
              GroupName: '{{ ResourceGroupName }}',
            },
            outputs: [
              {
                Name: 'ResourceCount',
                Selector: '$.length(ResourceIdentifiers)',
                Type: 'Integer',
              },
            ],
          },
          {
            name: 'PublishMetrics',
            action: 'aws:executeAwsApi',
            description: 'Publish resource count metrics to CloudWatch',
            inputs: {
              Service: 'cloudwatch',
              Api: 'PutMetricData',
              Namespace: 'ResourceGroups/Management',
              MetricData: [
                {
                  MetricName: 'ResourceCount',
                  Value: '{{ GetResourceGroupResources.ResourceCount }}',
                  Unit: 'Count',
                  Dimensions: [
                    {
                      Name: 'ResourceGroup',
                      Value: '{{ ResourceGroupName }}',
                    },
                  ],
                },
              ],
            },
          },
        ],
      },
      tags: [
        { key: 'Component', value: 'Automation' },
        { key: 'Purpose', value: 'ResourceMaintenance' },
      ],
    });

    // Automated resource tagging document
    new ssm.CfnDocument(this, 'AutomatedTaggingDocument', {
      documentType: 'Automation',
      documentFormat: 'YAML',
      name: `AutomatedResourceTagging-${uniqueSuffix}`,
      content: {
        schemaVersion: '0.3',
        description: 'Automated resource tagging for consistent organization',
        assumeRole: this.automationRole.roleArn,
        parameters: {
          ResourceArns: {
            type: 'StringList',
            description: 'List of resource ARNs to tag',
          },
          TagKey: {
            type: 'String',
            description: 'Tag key to apply',
          },
          TagValue: {
            type: 'String',
            description: 'Tag value to apply',
          },
        },
        mainSteps: [
          {
            name: 'TagResources',
            action: 'aws:executeAwsApi',
            description: 'Apply tags to specified resources',
            inputs: {
              Service: 'resourcegroupstaggingapi',
              Api: 'TagResources',
              ResourceARNList: '{{ ResourceArns }}',
              Tags: {
                '{{ TagKey }}': '{{ TagValue }}',
              },
            },
          },
        ],
      },
      tags: [
        { key: 'Component', value: 'Automation' },
        { key: 'Purpose', value: 'ResourceTagging' },
      ],
    });
  }

  /**
   * Creates CloudWatch monitoring system with dashboards and alarms
   */
  private createMonitoringSystem(uniqueSuffix: string): cloudwatch.Dashboard {
    // Create CloudWatch dashboard for resource group monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'ResourceGroupDashboard', {
      dashboardName: `resource-dashboard-${uniqueSuffix}`,
      
    });

    // Add widgets for monitoring different aspects
    dashboard.addWidgets(
      // Resource count monitoring
      new cloudwatch.GraphWidget({
        title: 'Resource Group Resource Count',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'ResourceGroups/Management',
            metricName: 'ResourceCount',
            dimensionsMap: {
              ResourceGroup: this.resourceGroup.name!,
            },
            statistic: 'Average',
          }),
        ],
      }),

      // EC2 CPU utilization monitoring
      new cloudwatch.GraphWidget({
        title: 'EC2 CPU Utilization',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            statistic: 'Average',
          }),
        ],
      }),
    );

    // Add cost monitoring widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Estimated Monthly Charges',
        width: 24,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Billing',
            metricName: 'EstimatedCharges',
            dimensionsMap: {
              Currency: 'USD',
            },
            statistic: 'Maximum',
            region: 'us-east-1', // Billing metrics are only available in us-east-1
          }),
        ],
      }),
    );

    // Create CloudWatch alarms
    this.createCloudWatchAlarms(uniqueSuffix);

    cdk.Tags.of(dashboard).add('Component', 'Monitoring');
    cdk.Tags.of(dashboard).add('Purpose', 'ResourceDashboard');

    return dashboard;
  }

  /**
   * Creates CloudWatch alarms for proactive monitoring
   */
  private createCloudWatchAlarms(uniqueSuffix: string): void {
    // High CPU utilization alarm
    const highCpuAlarm = new cloudwatch.Alarm(this, 'HighCPUAlarm', {
      alarmName: `ResourceGroup-HighCPU-${uniqueSuffix}`,
      alarmDescription: 'High CPU usage detected across resource group',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        statistic: 'Average',
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    highCpuAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.notificationTopic));

    // Resource health check alarm
    const healthCheckAlarm = new cloudwatch.Alarm(this, 'ResourceHealthAlarm', {
      alarmName: `ResourceGroup-HealthCheck-${uniqueSuffix}`,
      alarmDescription: 'Resource health monitoring for resource group',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'StatusCheckFailed',
        statistic: 'Maximum',
      }),
      threshold: 0,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    healthCheckAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.notificationTopic));

    cdk.Tags.of(highCpuAlarm).add('Component', 'Monitoring');
    cdk.Tags.of(healthCheckAlarm).add('Component', 'Monitoring');
  }

  /**
   * Creates cost tracking with AWS Budgets and Cost Anomaly Detection
   */
  private createCostTracking(budgetAmount: number, uniqueSuffix: string): void {
    // Create budget for resource group cost monitoring
    new budgets.CfnBudget(this, 'ResourceGroupBudget', {
      budget: {
        budgetName: `ResourceGroup-Budget-${uniqueSuffix}`,
        budgetLimit: {
          amount: budgetAmount,
          unit: 'USD',
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          TagKey: ['Environment', 'Application'],
          TagValue: ['production', 'web-app'],
        },
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: this.notificationTopic.topicArn,
            },
          ],
        },
        {
          notification: {
            notificationType: 'FORECASTED',
            comparisonOperator: 'GREATER_THAN',
            threshold: 100,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              subscriptionType: 'SNS',
              address: this.notificationTopic.topicArn,
            },
          ],
        },
      ],
    });

    // Create cost anomaly detector
    new ce.CfnAnomalyDetector(this, 'CostAnomalyDetector', {
      anomalyDetector: {
        detectorName: `ResourceGroupAnomalyDetector-${uniqueSuffix}`,
        monitorType: 'DIMENSIONAL',
        dimensionKey: 'SERVICE',
        monitorSpecification: JSON.stringify({
          TagKey: 'Environment',
          TagValues: ['production'],
        }),
      },
    });
  }

  /**
   * Creates automated resource tagging system using EventBridge
   */
  private createAutomatedTagging(uniqueSuffix: string): void {
    // Create EventBridge rule for automated tagging on resource creation
    const autoTagRule = new events.Rule(this, 'AutoTagNewResourcesRule', {
      ruleName: `AutoTagNewResources-${uniqueSuffix}`,
      description: 'Automatically tag new resources for resource group inclusion',
      eventPattern: {
        source: ['aws.ec2', 'aws.s3', 'aws.rds', 'aws.lambda'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventSource: [
            'ec2.amazonaws.com',
            's3.amazonaws.com',
            'rds.amazonaws.com',
            'lambda.amazonaws.com',
          ],
          eventName: [
            'RunInstances',
            'CreateBucket',
            'CreateDBInstance',
            'CreateFunction',
          ],
        },
      },
      enabled: true,
    });

    // Create Lambda function for processing tagging events
    const taggingFunction = new cdk.aws_lambda.Function(this, 'AutoTaggingFunction', {
      functionName: `resource-auto-tagger-${uniqueSuffix}`,
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      description: 'Automatically applies tags to new resources',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      code: cdk.aws_lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Automatically tag new AWS resources for inclusion in resource groups
    """
    try:
        # Parse CloudTrail event
        detail = event.get('detail', {})
        event_name = detail.get('eventName')
        source_ip = detail.get('sourceIPAddress', 'unknown')
        user_identity = detail.get('userIdentity', {})
        
        # Extract resource information based on event type
        resource_arn = None
        tags = {
            'Environment': 'production',
            'Application': 'web-app',
            'AutoTagged': 'true',
            'TaggedBy': 'AutoTaggingFunction'
        }
        
        # Process different resource types
        if event_name == 'RunInstances':
            # EC2 instances
            instances = detail.get('responseElements', {}).get('instancesSet', {}).get('items', [])
            for instance in instances:
                instance_id = instance.get('instanceId')
                if instance_id:
                    resource_arn = f"arn:aws:ec2:{context.aws_region}:{context.account_id}:instance/{instance_id}"
                    apply_tags(resource_arn, tags)
                    
        elif event_name == 'CreateBucket':
            # S3 buckets
            bucket_name = detail.get('requestParameters', {}).get('bucketName')
            if bucket_name:
                resource_arn = f"arn:aws:s3:::{bucket_name}"
                apply_tags(resource_arn, tags)
                
        elif event_name == 'CreateDBInstance':
            # RDS instances
            db_instance_id = detail.get('requestParameters', {}).get('dBInstanceIdentifier')
            if db_instance_id:
                resource_arn = f"arn:aws:rds:{context.aws_region}:{context.account_id}:db:{db_instance_id}"
                apply_tags(resource_arn, tags)
                
        elif event_name == 'CreateFunction':
            # Lambda functions
            function_name = detail.get('requestParameters', {}).get('functionName')
            if function_name:
                resource_arn = f"arn:aws:lambda:{context.aws_region}:{context.account_id}:function:{function_name}"
                apply_tags(resource_arn, tags)
        
        logger.info(f"Successfully processed {event_name} event for resource: {resource_arn}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Resource tagging completed successfully',
                'resourceArn': resource_arn,
                'eventName': event_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing tagging event: {str(e)}")
        raise

def apply_tags(resource_arn, tags):
    """Apply tags to the specified resource"""
    try:
        client = boto3.client('resourcegroupstaggingapi')
        response = client.tag_resources(
            ResourceARNList=[resource_arn],
            Tags=tags
        )
        logger.info(f"Applied tags to resource {resource_arn}: {tags}")
        return response
    except Exception as e:
        logger.error(f"Failed to apply tags to {resource_arn}: {str(e)}")
        raise
`),
      environment: {
        LOG_LEVEL: 'INFO',
      },
    });

    // Grant permissions for the tagging function
    taggingFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'resourcegroupstaggingapi:TagResources',
        'resourcegroupstaggingapi:GetResources',
        'tag:TagResources',
        'tag:GetResources',
        'ec2:CreateTags',
        's3:PutBucketTagging',
        'rds:AddTagsToResource',
        'lambda:TagResource',
      ],
      resources: ['*'],
    }));

    // Add Lambda function as target for EventBridge rule
    autoTagRule.addTarget(new eventsTargets.LambdaFunction(taggingFunction));

    cdk.Tags.of(autoTagRule).add('Component', 'Automation');
    cdk.Tags.of(taggingFunction).add('Component', 'Automation');
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(resourceGroupName: string, uniqueSuffix: string): void {
    new cdk.CfnOutput(this, 'ResourceGroupName', {
      description: 'Name of the created resource group',
      value: resourceGroupName,
      exportName: `${this.stackName}-ResourceGroupName`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      description: 'ARN of the SNS topic for notifications',
      value: this.notificationTopic.topicArn,
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'AutomationRoleArn', {
      description: 'ARN of the Systems Manager automation role',
      value: this.automationRole.roleArn,
      exportName: `${this.stackName}-AutomationRoleArn`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      description: 'URL of the CloudWatch dashboard',
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      exportName: `${this.stackName}-DashboardURL`,
    });

    new cdk.CfnOutput(this, 'ResourceGroupURL', {
      description: 'URL to view the resource group in AWS Console',
      value: `https://${this.region}.console.aws.amazon.com/resource-groups/group/${resourceGroupName}`,
      exportName: `${this.stackName}-ResourceGroupURL`,
    });
  }
}