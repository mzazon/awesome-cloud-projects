#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as managedblockchain from 'aws-cdk-lib/aws-managedblockchain';

/**
 * Props for the HyperledgerFabricStack
 */
interface HyperledgerFabricStackProps extends cdk.StackProps {
  /**
   * Name for the blockchain network
   */
  readonly networkName?: string;
  
  /**
   * Name for the member organization
   */
  readonly memberName?: string;
  
  /**
   * Admin username for the member organization
   */
  readonly adminUsername?: string;
  
  /**
   * Admin password for the member organization
   */
  readonly adminPassword?: string;
  
  /**
   * Instance type for the peer node
   */
  readonly peerNodeInstanceType?: string;
  
  /**
   * Instance type for the client EC2 instance
   */
  readonly clientInstanceType?: string;
  
  /**
   * Key pair name for EC2 instances
   */
  readonly keyPairName?: string;
}

/**
 * CDK Stack for Enterprise Blockchain Network
 * 
 * This stack creates:
 * - Amazon Managed Blockchain network with Hyperledger Fabric
 * - Member organization with peer nodes
 * - VPC infrastructure for secure connectivity
 * - EC2 client instance for blockchain application development
 * - IAM roles and security groups with least privilege access
 */
export class HyperledgerFabricStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly blockchainNetwork: managedblockchain.CfnNetwork;
  public readonly blockchainMember: managedblockchain.CfnMember;
  public readonly peerNode: managedblockchain.CfnNode;
  public readonly clientInstance: ec2.Instance;
  public readonly vpcEndpoint: ec2.InterfaceVpcEndpoint;

  constructor(scope: Construct, id: string, props: HyperledgerFabricStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const networkName = props.networkName || `fabric-network-${this.generateRandomSuffix()}`;
    const memberName = props.memberName || `member-org-${this.generateRandomSuffix()}`;
    const adminUsername = props.adminUsername || 'admin';
    const adminPassword = props.adminPassword || 'TempPassword123!';
    const peerNodeInstanceType = props.peerNodeInstanceType || 'bc.t3.small';
    const clientInstanceType = props.clientInstanceType || 't3.medium';
    const keyPairName = props.keyPairName;

    // Validate required parameters
    if (!keyPairName) {
      throw new Error('keyPairName is required for EC2 instances');
    }

    // Create VPC for blockchain infrastructure
    this.vpc = new ec2.Vpc(this, 'BlockchainVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Add VPC tags for better resource management
    cdk.Tags.of(this.vpc).add('Purpose', 'Blockchain-Infrastructure');
    cdk.Tags.of(this.vpc).add('Environment', 'Development');

    // Create CloudWatch Log Group for blockchain logs
    const blockchainLogGroup = new logs.LogGroup(this, 'BlockchainLogGroup', {
      logGroupName: `/aws/managedblockchain/${networkName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create the Hyperledger Fabric network
    this.blockchainNetwork = new managedblockchain.CfnNetwork(this, 'BlockchainNetwork', {
      name: networkName,
      description: 'Enterprise blockchain network for secure transactions using Hyperledger Fabric',
      framework: 'HYPERLEDGER_FABRIC',
      frameworkVersion: '2.2',
      frameworkConfiguration: {
        networkFabricConfiguration: {
          edition: 'STARTER', // Use STARTER edition for development/testing
        },
      },
      votingPolicy: {
        approvalThresholdPolicy: {
          thresholdPercentage: 50,
          proposalDurationInHours: 24,
          thresholdComparator: 'GREATER_THAN',
        },
      },
    });

    // Create the founding member organization
    this.blockchainMember = new managedblockchain.CfnMember(this, 'BlockchainMember', {
      networkId: this.blockchainNetwork.attrId,
      memberConfiguration: {
        name: memberName,
        description: 'Founding member organization for blockchain network',
        memberFrameworkConfiguration: {
          memberFabricConfiguration: {
            adminUsername: adminUsername,
            adminPassword: adminPassword,
          },
        },
      },
    });

    // Create peer node for transaction processing
    this.peerNode = new managedblockchain.CfnNode(this, 'PeerNode', {
      networkId: this.blockchainNetwork.attrId,
      memberId: this.blockchainMember.attrId,
      nodeConfiguration: {
        instanceType: peerNodeInstanceType,
        availabilityZone: this.availabilityZones[0],
      },
    });

    // Create IAM role for blockchain accessor
    const blockchainAccessorRole = new iam.Role(this, 'BlockchainAccessorRole', {
      assumedBy: new iam.ServicePrincipal('managedblockchain.amazonaws.com'),
      description: 'Role for Managed Blockchain accessor',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonManagedBlockchainReadOnlyAccess'),
      ],
    });

    // Create Managed Blockchain accessor for VPC endpoint connectivity
    const blockchainAccessor = new managedblockchain.CfnAccessor(this, 'BlockchainAccessor', {
      accessorType: 'BILLING_TOKEN',
    });

    // Create security group for VPC endpoint
    const vpcEndpointSecurityGroup = new ec2.SecurityGroup(this, 'VpcEndpointSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Managed Blockchain VPC endpoint',
      allowAllOutbound: true,
    });

    // Allow HTTPS traffic from VPC
    vpcEndpointSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(443),
      'Allow HTTPS from VPC'
    );

    // Create VPC endpoint for secure blockchain access
    this.vpcEndpoint = new ec2.InterfaceVpcEndpoint(this, 'BlockchainVpcEndpoint', {
      vpc: this.vpc,
      service: new ec2.InterfaceVpcEndpointService(
        `com.amazonaws.${this.region}.managedblockchain.${this.blockchainNetwork.attrId}`,
        443
      ),
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [vpcEndpointSecurityGroup],
      privateDnsEnabled: true,
      policyDocument: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.AnyPrincipal()],
            actions: [
              'managedblockchain:*',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create security group for client instance
    const clientSecurityGroup = new ec2.SecurityGroup(this, 'ClientSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for blockchain client instance',
      allowAllOutbound: true,
    });

    // Allow SSH access (restrict to specific IP ranges in production)
    clientSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access (restrict in production)'
    );

    // Create IAM role for EC2 client instance
    const clientInstanceRole = new iam.Role(this, 'ClientInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'Role for blockchain client EC2 instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonManagedBlockchainReadOnlyAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
      inlinePolicies: {
        BlockchainClientPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'managedblockchain:GetNetwork',
                'managedblockchain:GetMember',
                'managedblockchain:GetNode',
                'managedblockchain:ListMembers',
                'managedblockchain:ListNodes',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // User data script for client instance setup
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      
      // Install Node.js and npm
      'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash',
      'export NVM_DIR="$HOME/.nvm"',
      '[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"',
      'nvm install 18',
      'nvm use 18',
      'npm install -g yarn',
      
      // Install AWS CLI v2
      'curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"',
      'unzip awscliv2.zip',
      './aws/install',
      
      // Create fabric client application directory
      'mkdir -p /home/ec2-user/fabric-client-app',
      'cd /home/ec2-user/fabric-client-app',
      
      // Create package.json for Fabric SDK
      'cat > package.json << \'EOF\'',
      '{',
      '  "name": "fabric-blockchain-client",',
      '  "version": "1.0.0",',
      '  "description": "Hyperledger Fabric client for Amazon Managed Blockchain",',
      '  "main": "app.js",',
      '  "dependencies": {',
      '    "fabric-network": "^2.2.20",',
      '    "fabric-client": "^1.4.22",',
      '    "fabric-ca-client": "^2.2.20"',
      '  }',
      '}',
      'EOF',
      
      // Install Fabric SDK dependencies
      'npm install',
      
      // Create sample chaincode directory
      'mkdir -p chaincode',
      
      // Create sample asset management chaincode
      'cat > chaincode/asset-contract.js << \'EOF\'',
      '\'use strict\';',
      '',
      'const { Contract } = require(\'fabric-contract-api\');',
      '',
      'class AssetContract extends Contract {',
      '',
      '    async initLedger(ctx) {',
      '        const assets = [',
      '            {',
      '                ID: \'asset1\',',
      '                Owner: \'Alice\',',
      '                Value: 100,',
      '                Timestamp: new Date().toISOString()',
      '            }',
      '        ];',
      '',
      '        for (const asset of assets) {',
      '            await ctx.stub.putState(asset.ID, Buffer.from(JSON.stringify(asset)));',
      '        }',
      '    }',
      '',
      '    async createAsset(ctx, id, owner, value) {',
      '        const asset = {',
      '            ID: id,',
      '            Owner: owner,',
      '            Value: parseInt(value),',
      '            Timestamp: new Date().toISOString()',
      '        };',
      '        ',
      '        await ctx.stub.putState(id, Buffer.from(JSON.stringify(asset)));',
      '        return JSON.stringify(asset);',
      '    }',
      '',
      '    async readAsset(ctx, id) {',
      '        const assetJSON = await ctx.stub.getState(id);',
      '        if (!assetJSON || assetJSON.length === 0) {',
      '            throw new Error(`Asset ${id} does not exist`);',
      '        }',
      '        return assetJSON.toString();',
      '    }',
      '',
      '    async getAllAssets(ctx) {',
      '        const allResults = [];',
      '        const iterator = await ctx.stub.getStateByRange(\'\', \'\');',
      '        let result = await iterator.next();',
      '        ',
      '        while (!result.done) {',
      '            const strValue = Buffer.from(result.value.value).toString(\'utf8\');',
      '            let record;',
      '            try {',
      '                record = JSON.parse(strValue);',
      '            } catch (err) {',
      '                record = strValue;',
      '            }',
      '            allResults.push({ Key: result.value.key, Record: record });',
      '            result = await iterator.next();',
      '        }',
      '        ',
      '        return JSON.stringify(allResults);',
      '    }',
      '}',
      '',
      'module.exports = AssetContract;',
      'EOF',
      
      // Set proper ownership
      'chown -R ec2-user:ec2-user /home/ec2-user/fabric-client-app',
      
      // Create environment variables file
      `echo "export NETWORK_ID=${this.blockchainNetwork.attrId}" >> /home/ec2-user/.bashrc`,
      `echo "export MEMBER_ID=${this.blockchainMember.attrId}" >> /home/ec2-user/.bashrc`,
      `echo "export NODE_ID=${this.peerNode.attrId}" >> /home/ec2-user/.bashrc`,
      
      // Signal completion
      '/opt/aws/bin/cfn-signal -e $? --stack ' + this.stackName + ' --resource ClientInstance --region ' + this.region
    );

    // Create the client EC2 instance
    this.clientInstance = new ec2.Instance(this, 'ClientInstance', {
      vpc: this.vpc,
      instanceType: new ec2.InstanceType(clientInstanceType),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      keyName: keyPairName,
      role: clientInstanceRole,
      securityGroup: clientSecurityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      userData: userData,
      userDataCausesReplacement: true,
    });

    // Add dependencies to ensure proper creation order
    this.blockchainMember.addDependency(this.blockchainNetwork);
    this.peerNode.addDependency(this.blockchainMember);
    this.vpcEndpoint.node.addDependency(this.blockchainNetwork);
    this.clientInstance.node.addDependency(this.peerNode);

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'HyperledgerFabric');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // Output important resource information
    new cdk.CfnOutput(this, 'NetworkId', {
      value: this.blockchainNetwork.attrId,
      description: 'Managed Blockchain Network ID',
      exportName: `${this.stackName}-NetworkId`,
    });

    new cdk.CfnOutput(this, 'MemberId', {
      value: this.blockchainMember.attrId,
      description: 'Managed Blockchain Member ID',
      exportName: `${this.stackName}-MemberId`,
    });

    new cdk.CfnOutput(this, 'NodeId', {
      value: this.peerNode.attrId,
      description: 'Managed Blockchain Peer Node ID',
      exportName: `${this.stackName}-NodeId`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for blockchain infrastructure',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'ClientInstanceId', {
      value: this.clientInstance.instanceId,
      description: 'EC2 Client Instance ID for blockchain development',
      exportName: `${this.stackName}-ClientInstanceId`,
    });

    new cdk.CfnOutput(this, 'VpcEndpointId', {
      value: this.vpcEndpoint.vpcEndpointId,
      description: 'VPC Endpoint ID for secure blockchain access',
      exportName: `${this.stackName}-VpcEndpointId`,
    });

    new cdk.CfnOutput(this, 'BlockchainConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/managedblockchain/home?region=${this.region}#/networks/${this.blockchainNetwork.attrId}`,
      description: 'AWS Console URL for Managed Blockchain Network',
    });
  }

  /**
   * Generate a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

// Main CDK application
const app = new cdk.App();

// Get context parameters or use defaults
const networkName = app.node.tryGetContext('networkName');
const memberName = app.node.tryGetContext('memberName');
const adminUsername = app.node.tryGetContext('adminUsername');
const adminPassword = app.node.tryGetContext('adminPassword');
const peerNodeInstanceType = app.node.tryGetContext('peerNodeInstanceType');
const clientInstanceType = app.node.tryGetContext('clientInstanceType');
const keyPairName = app.node.tryGetContext('keyPairName') || process.env.CDK_DEFAULT_KEY_PAIR;

// Create the Hyperledger Fabric stack
new HyperledgerFabricStack(app, 'HyperledgerFabricStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  networkName,
  memberName,
  adminUsername,
  adminPassword,
  peerNodeInstanceType,
  clientInstanceType,
  keyPairName,
  description: 'CDK stack for Enterprise Blockchain Network',
});

// Synthesize the CloudFormation template
app.synth();