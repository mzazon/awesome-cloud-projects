import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { MultiRegionDistributedApplicationsStack } from '../lib/multi-region-distributed-applications-stack';

describe('MultiRegionDistributedApplicationsStack', () => {
  let app: cdk.App;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
  });

  test('Primary region stack creates required resources', () => {
    // Create primary region stack
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true
    });

    template = Template.fromStack(stack);

    // Test Aurora DSQL Cluster
    template.hasResourceProperties('AWS::DSQL::Cluster', {
      Tags: [
        { Key: 'Name', Value: {} },
        { Key: 'Environment', Value: 'Production' },
        { Key: 'Application', Value: 'DistributedApp' },
        { Key: 'Region', Value: 'Primary' }
      ]
    });

    // Test Lambda Function
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'nodejs20.x',
      Handler: 'index.handler',
      Timeout: 30,
      MemorySize: 256
    });

    // Test EventBridge Custom Bus
    template.hasResourceProperties('AWS::Events::EventBus', {
      Name: {}
    });

    // Test EventBridge Rule
    template.hasResourceProperties('AWS::Events::Rule', {
      EventPattern: {
        source: ['dsql.application'],
        'detail-type': ['Transaction Created', 'Transaction Updated', 'Transaction Deleted']
      },
      State: 'ENABLED'
    });

    // Test IAM Role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com'
            },
            Action: 'sts:AssumeRole'
          }
        ]
      }
    });
  });

  test('Secondary region stack creates required resources', () => {
    // Create secondary region stack
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-west-2' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: false
    });

    template = Template.fromStack(stack);

    // Test Aurora DSQL Cluster with secondary region tags
    template.hasResourceProperties('AWS::DSQL::Cluster', {
      Tags: [
        { Key: 'Name', Value: {} },
        { Key: 'Environment', Value: 'Production' },
        { Key: 'Application', Value: 'DistributedApp' },
        { Key: 'Region', Value: 'Secondary' }
      ]
    });

    // Verify Lambda function exists
    template.resourceCountIs('AWS::Lambda::Function', 1);
    
    // Verify EventBridge resources exist
    template.resourceCountIs('AWS::Events::EventBus', 1);
    template.resourceCountIs('AWS::Events::Rule', 1);
  });

  test('Stack has required outputs', () => {
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true
    });

    template = Template.fromStack(stack);

    // Test stack outputs
    template.hasOutput('DSQLClusterArn', {});
    template.hasOutput('DSQLClusterEndpoint', {});
    template.hasOutput('LambdaFunctionArn', {});
    template.hasOutput('LambdaFunctionName', {});
    template.hasOutput('EventBusArn', {});
    template.hasOutput('EventBusName', {});
  });

  test('Lambda function has correct environment variables', () => {
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true
    });

    template = Template.fromStack(stack);

    // Test Lambda environment variables
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          DSQL_CLUSTER_ID: {},
          AWS_REGION: 'us-east-1',
          IS_PRIMARY_REGION: 'true',
          EVENT_BUS_NAME: {}
        }
      }
    });
  });

  test('IAM role has correct policies', () => {
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true
    });

    template = Template.fromStack(stack);

    // Test managed policy attachment
    template.hasResourceProperties('AWS::IAM::Role', {
      ManagedPolicyArns: [
        'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
      ]
    });

    // Test inline policy for DSQL and EventBridge permissions
    template.hasResourceProperties('AWS::IAM::Role', {
      Policies: [
        {
          PolicyName: 'DSQLEventBridgePolicy',
          PolicyDocument: {
            Statement: [
              {
                Effect: 'Allow',
                Action: [
                  'dsql:Connect',
                  'dsql:DbConnect',
                  'dsql:ExecuteStatement'
                ],
                Resource: '*'
              },
              {
                Effect: 'Allow',
                Action: ['events:PutEvents'],
                Resource: '*'
              }
            ]
          }
        }
      ]
    });
  });

  test('CloudWatch Log Group is created', () => {
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true
    });

    template = Template.fromStack(stack);

    // Test CloudWatch Log Group
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: {},
      RetentionInDays: 7
    });
  });

  test('EventBridge rule targets Lambda function', () => {
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true
    });

    template = Template.fromStack(stack);

    // Test EventBridge rule has Lambda target
    template.hasResourceProperties('AWS::Events::Rule', {
      Targets: [
        {
          Arn: {},
          Id: '1',
          InputTransformer: {
            InputPathsMap: {
              'detail': '$.detail',
              'detail-type': '$.detail-type',
              'region': '$.region',
              'time': '$.time'
            },
            InputTemplate: {}
          }
        }
      ]
    });
  });

  test('Stack tags are applied correctly', () => {
    const stack = new MultiRegionDistributedApplicationsStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' },
      primaryRegion: 'us-east-1',
      secondaryRegion: 'us-west-2',
      witnessRegion: 'eu-west-1',
      isPrimaryRegion: true,
      tags: {
        Environment: 'Production',
        Application: 'DistributedApp',
        Region: 'Primary'
      }
    });

    // Tags are applied at the stack level, verify they exist
    expect(stack.tags.tagValues()).toEqual({
      Environment: 'Production',
      Application: 'DistributedApp',
      Region: 'Primary',
      Project: 'MultiRegionDistributedApplications',
      Service: 'Aurora DSQL',
      CostCenter: 'Engineering',
      Owner: 'DevOps Team'
    });
  });
});