import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import * as ResourceGroupsAutomation from '../lib/resource-groups-automation-stack';

/**
 * Unit tests for ResourceGroupsAutomationStack
 * 
 * These tests verify that the CDK stack creates the expected AWS resources
 * with proper configurations for security, monitoring, and automation.
 */

describe('ResourceGroupsAutomationStack', () => {
  let app: cdk.App;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    const stack = new ResourceGroupsAutomation.ResourceGroupsAutomationStack(app, 'TestStack', {
      resourceGroupName: 'test-resource-group',
      notificationEmail: 'test@example.com',
      budgetAmount: 100,
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('Resource Group Creation', () => {
    test('Creates resource group with correct configuration', () => {
      template.hasResourceProperties('AWS::ResourceGroups::Group', {
        Name: 'test-resource-group',
        Description: 'Production web application resources organized by tags',
        ResourceQuery: {
          Type: 'TAG_FILTERS_1_0',
          Query: {
            ResourceTypeFilters: ['AWS::AllSupported'],
            TagFilters: [
              {
                Key: 'Environment',
                Values: ['production'],
              },
              {
                Key: 'Application',
                Values: ['web-app'],
              },
            ],
          },
        },
      });
    });

    test('Resource group has proper tags', () => {
      template.hasResourceProperties('AWS::ResourceGroups::Group', {
        Tags: Match.arrayWith([
          { Key: 'Environment', Value: 'production' },
          { Key: 'Application', Value: 'web-app' },
          { Key: 'Purpose', Value: 'resource-management' },
          { Key: 'Component', Value: 'ResourceGroup' },
        ]),
      });
    });
  });

  describe('SNS Notification System', () => {
    test('Creates SNS topic with encryption', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        DisplayName: Match.stringLikeRegexp('Resource Management Alerts'),
        KmsMasterKeyId: Match.anyValue(),
      });
    });

    test('Creates email subscription when email provided', () => {
      template.hasResourceProperties('AWS::SNS::Subscription', {
        Protocol: 'email',
        Endpoint: 'test@example.com',
      });
    });
  });

  describe('IAM Roles and Permissions', () => {
    test('Creates automation role with correct assume role policy', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: {
                Service: 'ssm.amazonaws.com',
              },
              Action: 'sts:AssumeRole',
            },
          ],
        },
        ManagedPolicyArns: [
          {
            'Fn::Join': [
              '',
              [
                'arn:',
                { Ref: 'AWS::Partition' },
                ':iam::aws:policy/AmazonSSMAutomationRole',
              ],
            ],
          },
        ],
      });
    });

    test('Automation role has resource group permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: Match.arrayWith([
                'resource-groups:ListGroupResources',
                'resource-groups:GetGroup',
                'resourcegroupstaggingapi:TagResources',
              ]),
              Resource: '*',
            },
          ]),
        },
      });
    });
  });

  describe('Systems Manager Automation', () => {
    test('Creates resource maintenance automation document', () => {
      template.hasResourceProperties('AWS::SSM::Document', {
        DocumentType: 'Automation',
        DocumentFormat: 'YAML',
        Name: Match.stringLikeRegexp('ResourceGroupMaintenance-'),
        Content: {
          schemaVersion: '0.3',
          description: 'Automated maintenance and health checks for resource group',
          parameters: {
            ResourceGroupName: {
              type: 'String',
              description: 'Name of the resource group to process',
              default: 'test-resource-group',
            },
          },
        },
      });
    });

    test('Creates automated tagging document', () => {
      template.hasResourceProperties('AWS::SSM::Document', {
        DocumentType: 'Automation',
        DocumentFormat: 'YAML',
        Name: Match.stringLikeRegexp('AutomatedResourceTagging-'),
        Content: {
          schemaVersion: '0.3',
          description: 'Automated resource tagging for consistent organization',
        },
      });
    });
  });

  describe('CloudWatch Monitoring', () => {
    test('Creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: Match.stringLikeRegexp('resource-dashboard-'),
        DashboardBody: Match.anyValue(),
      });
    });

    test('Creates high CPU alarm', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('ResourceGroup-HighCPU-'),
        AlarmDescription: 'High CPU usage detected across resource group',
        MetricName: 'CPUUtilization',
        Namespace: 'AWS/EC2',
        Statistic: 'Average',
        Threshold: 80,
        ComparisonOperator: 'GreaterThanThreshold',
        EvaluationPeriods: 2,
      });
    });

    test('Creates health check alarm', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('ResourceGroup-HealthCheck-'),
        AlarmDescription: 'Resource health monitoring for resource group',
        MetricName: 'StatusCheckFailed',
        Namespace: 'AWS/EC2',
        ComparisonOperator: 'GreaterThanThreshold',
      });
    });

    test('Alarms have SNS actions configured', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmActions: [
          {
            Ref: Match.stringLikeRegexp('ResourceAlertsTopic'),
          },
        ],
      });
    });
  });

  describe('Cost Management', () => {
    test('Creates budget with correct configuration', () => {
      template.hasResourceProperties('AWS::Budgets::Budget', {
        Budget: {
          BudgetName: Match.stringLikeRegexp('ResourceGroup-Budget-'),
          BudgetLimit: {
            Amount: 100,
            Unit: 'USD',
          },
          TimeUnit: 'MONTHLY',
          BudgetType: 'COST',
          CostFilters: {
            TagKey: ['Environment', 'Application'],
            TagValue: ['production', 'web-app'],
          },
        },
      });
    });

    test('Budget has notification thresholds configured', () => {
      template.hasResourceProperties('AWS::Budgets::Budget', {
        NotificationsWithSubscribers: [
          {
            Notification: {
              NotificationType: 'ACTUAL',
              ComparisonOperator: 'GREATER_THAN',
              Threshold: 80,
              ThresholdType: 'PERCENTAGE',
            },
            Subscribers: Match.anyValue(),
          },
          {
            Notification: {
              NotificationType: 'FORECASTED',
              ComparisonOperator: 'GREATER_THAN',
              Threshold: 100,
              ThresholdType: 'PERCENTAGE',
            },
            Subscribers: Match.anyValue(),
          },
        ],
      });
    });

    test('Creates cost anomaly detector', () => {
      template.hasResourceProperties('AWS::CE::AnomalyDetector', {
        AnomalyDetector: {
          DetectorName: Match.stringLikeRegexp('ResourceGroupAnomalyDetector-'),
          MonitorType: 'DIMENSIONAL',
          DimensionKey: 'SERVICE',
        },
      });
    });
  });

  describe('EventBridge and Lambda Integration', () => {
    test('Creates EventBridge rule for auto-tagging', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: Match.stringLikeRegexp('AutoTagNewResources-'),
        Description: 'Automatically tag new resources for resource group inclusion',
        EventPattern: {
          source: ['aws.ec2', 'aws.s3', 'aws.rds', 'aws.lambda'],
          detailType: ['AWS API Call via CloudTrail'],
          detail: {
            eventSource: [
              'ec2.amazonaws.com',
              's3.amazonaws.com',
              'rds.amazonaws.com',
              'lambda.amazonaws.com',
            ],
          },
        },
        State: 'ENABLED',
      });
    });

    test('Creates Lambda function for auto-tagging', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('resource-auto-tagger-'),
        Runtime: 'python3.11',
        Handler: 'index.lambda_handler',
        Description: 'Automatically applies tags to new resources',
        Timeout: 300,
        MemorySize: 256,
      });
    });

    test('Lambda function has required permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: Match.arrayWith([
                'resourcegroupstaggingapi:TagResources',
                'ec2:CreateTags',
                's3:PutBucketTagging',
                'rds:AddTagsToResource',
                'lambda:TagResource',
              ]),
              Resource: '*',
            },
          ]),
        },
      });
    });
  });

  describe('Stack Outputs', () => {
    test('Creates all required outputs', () => {
      const outputs = [
        'ResourceGroupName',
        'SNSTopicArn',
        'AutomationRoleArn',
        'DashboardURL',
        'ResourceGroupURL',
      ];

      outputs.forEach(outputName => {
        template.hasOutput(outputName, {});
      });
    });

    test('Resource group name output has correct value', () => {
      template.hasOutput('ResourceGroupName', {
        Value: 'test-resource-group',
        Export: {
          Name: 'TestStack-ResourceGroupName',
        },
      });
    });
  });

  describe('Resource Counts', () => {
    test('Creates expected number of resources', () => {
      // Count key resource types
      const resourceCounts = [
        ['AWS::ResourceGroups::Group', 1],
        ['AWS::SNS::Topic', 1],
        ['AWS::IAM::Role', 2], // Automation role + Lambda execution role
        ['AWS::SSM::Document', 2], // Maintenance + Tagging documents
        ['AWS::CloudWatch::Dashboard', 1],
        ['AWS::CloudWatch::Alarm', 2], // CPU + Health alarms
        ['AWS::Budgets::Budget', 1],
        ['AWS::CE::AnomalyDetector', 1],
        ['AWS::Events::Rule', 1],
        ['AWS::Lambda::Function', 1],
      ];

      resourceCounts.forEach(([resourceType, expectedCount]) => {
        template.resourceCountIs(resourceType, expectedCount);
      });
    });
  });

  describe('Security Best Practices', () => {
    test('IAM roles use least privilege principle', () => {
      // Verify that IAM policies don't use overly broad permissions
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.not({
              Effect: 'Allow',
              Action: '*',
              Resource: '*',
            }),
          ]),
        },
      });
    });

    test('SNS topic uses encryption', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        KmsMasterKeyId: Match.anyValue(),
      });
    });

    test('Resources have appropriate tags for governance', () => {
      // Verify key resources have governance tags
      const resourceTypesToCheck = [
        'AWS::ResourceGroups::Group',
        'AWS::SNS::Topic',
        'AWS::Lambda::Function',
      ];

      resourceTypesToCheck.forEach(resourceType => {
        template.hasResourceProperties(resourceType, {
          Tags: Match.anyValue(),
        });
      });
    });
  });

  describe('Error Handling', () => {
    test('CloudWatch alarms handle missing data appropriately', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        TreatMissingData: 'notBreaching',
      });
    });

    test('Lambda function has appropriate timeout and memory', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Timeout: Match.numberLikeRegexp('^[1-9]\\d*$'), // Positive number
        MemorySize: Match.numberLikeRegexp('^[1-9]\\d*$'), // Positive number
      });
    });
  });
});