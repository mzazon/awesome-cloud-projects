import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { CostAwareResourceLifecycleStack } from '../lib/cost-aware-resource-lifecycle-stack';

describe('CostAwareResourceLifecycleStack', () => {
  let app: cdk.App;
  let stack: CostAwareResourceLifecycleStack;
  let template: Template;

  beforeAll(() => {
    app = new cdk.App({
      context: {
        'enableCdkNag': 'false', // Disable CDK Nag for testing
      },
    });
    stack = new CostAwareResourceLifecycleStack(app, 'TestStack', {
      clusterName: 'test-cluster',
      costThreshold: 100,
    });
    template = Template.fromStack(stack);
  });

  test('creates MemoryDB cluster with correct configuration', () => {
    template.hasResourceProperties('AWS::MemoryDB::Cluster', {
      ClusterName: 'test-cluster',
      NodeType: 'db.t4g.small',
      NumShards: 1,
      NumReplicasPerShard: 0,
    });
  });

  test('creates MemoryDB subnet group', () => {
    template.hasResourceProperties('AWS::MemoryDB::SubnetGroup', {
      SubnetGroupName: 'test-cluster-subnet-group',
      Description: 'Subnet group for cost-aware MemoryDB cluster',
    });
  });

  test('creates Lambda function with correct properties', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.9',
      Handler: 'index.lambda_handler',
      Timeout: 300,
      MemorySize: 256,
      Description: 'Cost-aware MemoryDB cluster lifecycle management function',
      Environment: {
        Variables: {
          LOG_LEVEL: 'INFO',
        },
      },
    });
  });

  test('creates IAM role for Lambda with correct policies', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com',
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
              ':iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
            ],
          ],
        },
      ],
    });

    // Check for custom policy with MemoryDB permissions
    template.hasResourceProperties('AWS::IAM::Role', {
      Policies: [
        {
          PolicyDocument: {
            Statement: Match.arrayWith([
              {
                Effect: 'Allow',
                Action: [
                  'memorydb:DescribeClusters',
                  'memorydb:ModifyCluster',
                  'memorydb:DescribeSubnetGroups',
                  'memorydb:DescribeParameterGroups',
                ],
                Resource: '*',
              },
              {
                Effect: 'Allow',
                Action: [
                  'ce:GetCostAndUsage',
                  'ce:GetUsageReport',
                  'ce:GetDimensionValues',
                  'budgets:ViewBudget',
                ],
                Resource: '*',
              },
            ]),
          },
        },
      ],
    });
  });

  test('creates EventBridge Scheduler group', () => {
    template.hasResourceProperties('AWS::Scheduler::ScheduleGroup', {
      Name: 'cost-optimization-schedules',
      Description: 'Cost optimization schedules for MemoryDB lifecycle management',
    });
  });

  test('creates business hours schedules', () => {
    // Business hours start schedule
    template.hasResourceProperties('AWS::Scheduler::Schedule', {
      ScheduleExpression: 'cron(0 8 ? * MON-FRI *)',
      Description: 'Scale up MemoryDB for business hours performance',
      State: 'ENABLED',
      FlexibleTimeWindow: {
        Mode: 'OFF',
      },
    });

    // Business hours end schedule
    template.hasResourceProperties('AWS::Scheduler::Schedule', {
      ScheduleExpression: 'cron(0 18 ? * MON-FRI *)',
      Description: 'Scale down MemoryDB for cost optimization during off-hours',
      State: 'ENABLED',
    });

    // Weekly analysis schedule
    template.hasResourceProperties('AWS::Scheduler::Schedule', {
      ScheduleExpression: 'cron(0 9 ? * MON *)',
      Description: 'Weekly MemoryDB cost analysis and optimization review',
      State: 'ENABLED',
    });
  });

  test('creates CloudWatch dashboard', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardName: 'MemoryDB-Cost-Optimization-test-cluster',
    });
  });

  test('creates CloudWatch alarms', () => {
    // Cost alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'MemoryDB-Weekly-Cost-High-test-cluster',
      AlarmDescription: 'Alert when MemoryDB weekly costs exceed threshold',
      ComparisonOperator: 'GreaterThanThreshold',
      Threshold: 150, // 100 * 1.5
    });

    // Lambda error alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmName: 'MemoryDB-Optimizer-Lambda-Errors-test-cluster',
      AlarmDescription: 'Alert when cost optimization Lambda function has errors',
      ComparisonOperator: 'GreaterThanOrEqualToThreshold',
      Threshold: 1,
    });
  });

  test('creates AWS Budget', () => {
    template.hasResourceProperties('AWS::Budgets::Budget', {
      Budget: {
        BudgetName: 'MemoryDB-Cost-Budget-test-cluster',
        BudgetLimit: {
          Amount: '200', // costThreshold * 2
          Unit: 'USD',
        },
        TimeUnit: 'MONTHLY',
        BudgetType: 'COST',
        CostFilters: {
          Service: ['Amazon MemoryDB for Redis'],
        },
      },
    });
  });

  test('creates security group with correct ingress rules', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for MemoryDB cluster',
      SecurityGroupIngress: [
        {
          IpProtocol: 'tcp',
          FromPort: 6379,
          ToPort: 6379,
          Description: 'Allow Redis traffic from VPC',
        },
      ],
    });
  });

  test('generates correct stack outputs', () => {
    template.hasOutput('MemoryDbClusterName', {
      Description: 'Name of the MemoryDB cluster',
    });

    template.hasOutput('MemoryDbClusterEndpoint', {
      Description: 'MemoryDB cluster endpoint address',
    });

    template.hasOutput('CostOptimizerFunctionName', {
      Description: 'Name of the cost optimizer Lambda function',
    });

    template.hasOutput('CostOptimizerFunctionArn', {
      Description: 'ARN of the cost optimizer Lambda function',
    });

    template.hasOutput('DashboardUrl', {
      Description: 'URL to the CloudWatch dashboard for cost optimization monitoring',
    });
  });

  test('stack has appropriate tags', () => {
    // Check that resources are tagged appropriately
    template.hasResourceProperties('AWS::MemoryDB::Cluster', {
      Tags: Match.arrayWith([
        {
          Key: 'CostOptimization',
          Value: 'enabled',
        },
        {
          Key: 'ManagedBy',
          Value: 'CDK',
        },
      ]),
    });
  });
});