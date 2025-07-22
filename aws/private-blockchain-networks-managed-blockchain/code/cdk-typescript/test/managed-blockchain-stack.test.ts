import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { ManagedBlockchainStack } from '../lib/managed-blockchain-stack';

describe('ManagedBlockchainStack', () => {
  let app: cdk.App;
  let stack: ManagedBlockchainStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    const config = {
      networkName: 'TestNetwork',
      memberName: 'TestMember',
      adminUsername: 'admin',
      adminPassword: 'TestPassword123!',
      nodeInstanceType: 'bc.t3.small',
      ec2InstanceType: 't3.medium',
      environment: 'test'
    };

    stack = new ManagedBlockchainStack(app, 'TestStack', {
      config,
      env: {
        account: '123456789012',
        region: 'us-east-1'
      }
    });

    template = Template.fromStack(stack);
  });

  test('Creates Managed Blockchain Network', () => {
    template.hasResourceProperties('AWS::ManagedBlockchain::Network', {
      Framework: 'HYPERLEDGER_FABRIC',
      FrameworkVersion: '2.2'
    });
  });

  test('Creates Managed Blockchain Member', () => {
    template.hasResourceProperties('AWS::ManagedBlockchain::Member', {
      MemberConfiguration: {
        Name: cdk.Match.stringLikeRegexp('TestMember-.*')
      }
    });
  });

  test('Creates Managed Blockchain Node', () => {
    template.hasResourceProperties('AWS::ManagedBlockchain::Node', {
      NodeConfiguration: {
        InstanceType: 'bc.t3.small'
      }
    });
  });

  test('Creates VPC Endpoint for Managed Blockchain', () => {
    template.hasResourceProperties('AWS::EC2::VPCEndpoint', {
      ServiceName: cdk.Match.stringLikeRegexp('com.amazonaws.us-east-1.managedblockchain')
    });
  });

  test('Creates EC2 Instance for Blockchain Client', () => {
    template.hasResourceProperties('AWS::EC2::Instance', {
      InstanceType: 't3.medium'
    });
  });

  test('Creates Security Group with Required Ports', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      SecurityGroupIngress: cdk.Match.arrayWith([
        {
          CidrIp: '10.0.0.0/8',
          FromPort: 30001,
          ToPort: 30001,
          IpProtocol: 'tcp'
        },
        {
          CidrIp: '10.0.0.0/8',
          FromPort: 30002,
          ToPort: 30002,
          IpProtocol: 'tcp'
        }
      ])
    });
  });

  test('Creates IAM Role for Managed Blockchain', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: cdk.Match.arrayWith([
          {
            Principal: {
              Service: 'managedblockchain.amazonaws.com'
            }
          }
        ])
      }
    });
  });

  test('Creates CloudWatch Log Group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: cdk.Match.stringLikeRegexp('/aws/managedblockchain/TestNetwork-.*'),
      RetentionInDays: 7
    });
  });

  test('Creates Key Pair for EC2 Access', () => {
    template.hasResourceProperties('AWS::EC2::KeyPair', {
      KeyName: cdk.Match.stringLikeRegexp('blockchain-client-key-.*')
    });
  });

  test('Outputs Network Information', () => {
    template.hasOutput('NetworkId', {});
    template.hasOutput('MemberId', {});
    template.hasOutput('NodeId', {});
    template.hasOutput('VpcEndpointId', {});
    template.hasOutput('ClientInstanceId', {});
    template.hasOutput('ClientPublicIp', {});
    template.hasOutput('KeyPairName', {});
    template.hasOutput('NetworkName', {});
    template.hasOutput('MemberName', {});
  });

  test('Stack has correct tags', () => {
    const stackTags = Template.fromStack(stack).toJSON().Resources;
    
    // Check that resources have appropriate tags
    Object.keys(stackTags).forEach(resourceKey => {
      const resource = stackTags[resourceKey];
      if (resource.Type === 'AWS::ManagedBlockchain::Network') {
        expect(resource.Properties.Tags).toEqual(
          expect.objectContaining({
            Environment: 'test',
            Project: 'SupplyChain'
          })
        );
      }
    });
  });

  test('Security group allows required communication', () => {
    // Test that security group allows internal communication
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      SecurityGroupIngress: cdk.Match.arrayWith([
        {
          FromPort: 7051,
          ToPort: 7051,
          IpProtocol: 'tcp'
        },
        {
          FromPort: 7053,
          ToPort: 7053,
          IpProtocol: 'tcp'
        }
      ])
    });
  });

  test('EC2 instance has correct IAM permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: cdk.Match.arrayWith([
          {
            Principal: {
              Service: 'ec2.amazonaws.com'
            }
          }
        ])
      },
      ManagedPolicyArns: cdk.Match.arrayWith([
        'arn:aws:iam::aws:policy/AmazonManagedBlockchainReadOnlyAccess',
        'arn:aws:iam::aws:policy/CloudWatchLogsFullAccess'
      ])
    });
  });

  test('VPC Flow Logs are enabled', () => {
    template.hasResourceProperties('AWS::EC2::FlowLog', {
      ResourceType: 'VPC',
      TrafficType: 'ALL'
    });
  });
});