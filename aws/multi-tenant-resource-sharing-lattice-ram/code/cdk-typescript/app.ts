#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ram from 'aws-cdk-lib/aws-ram';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the MultiTenantResourceSharingStack
 */
interface MultiTenantResourceSharingStackProps extends cdk.StackProps {
  /** List of AWS account IDs to share resources with */
  readonly sharedAccountIds?: string[];
  /** Organization ID for RAM sharing (if using AWS Organizations) */
  readonly organizationId?: string;
  /** Database instance class for the shared RDS instance */
  readonly dbInstanceClass?: string;
  /** VPC ID to use (if not provided, will use default VPC) */
  readonly vpcId?: string;
  /** Enable CloudTrail audit logging */
  readonly enableAuditLogging?: boolean;
}

/**
 * CDK Stack for Multi-Tenant Resource Sharing with VPC Lattice and RAM
 * 
 * This stack demonstrates how to implement secure multi-tenant resource sharing
 * using Amazon VPC Lattice for application networking and AWS Resource Access Manager (RAM)
 * for cross-account resource sharing. The solution includes:
 * 
 * - VPC Lattice Service Network with IAM authentication
 * - Shared RDS database with proper security configuration
 * - Resource configuration for VPC Lattice integration
 * - AWS RAM resource sharing setup
 * - IAM roles with team-based access control
 * - CloudTrail audit logging for compliance
 * - Comprehensive security policies following AWS best practices
 */
export class MultiTenantResourceSharingStack extends cdk.Stack {
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly rdsInstance: rds.DatabaseInstance;
  public readonly resourceShare: ram.CfnResourceShare;
  public readonly auditBucket?: s3.Bucket;
  public readonly cloudTrail?: cloudtrail.Trail;

  constructor(scope: Construct, id: string, props?: MultiTenantResourceSharingStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Get or create VPC
    const vpc = this.getOrCreateVpc(props?.vpcId);

    // Create security group for RDS with least privilege access
    const dbSecurityGroup = this.createDatabaseSecurityGroup(vpc, uniqueSuffix);

    // Create RDS subnet group for multi-AZ deployment
    const dbSubnetGroup = this.createDatabaseSubnetGroup(vpc, uniqueSuffix);

    // Create shared RDS database instance
    this.rdsInstance = this.createSharedDatabase(
      vpc, 
      dbSecurityGroup, 
      dbSubnetGroup, 
      uniqueSuffix,
      props?.dbInstanceClass
    );

    // Create VPC Lattice service network
    this.serviceNetwork = this.createServiceNetwork(uniqueSuffix);

    // Associate VPC with service network
    const vpcAssociation = this.associateVpcWithServiceNetwork(vpc);

    // Create resource configuration for RDS
    const resourceConfig = this.createResourceConfiguration(vpc, uniqueSuffix);

    // Associate resource configuration with service network
    this.associateResourceWithServiceNetwork(resourceConfig);

    // Create authentication policy for multi-tenant access
    this.createAuthenticationPolicy();

    // Create IAM roles for different tenant teams
    this.createTenantRoles(uniqueSuffix);

    // Create AWS RAM resource share
    this.resourceShare = this.createResourceShare(
      uniqueSuffix,
      props?.sharedAccountIds,
      props?.organizationId
    );

    // Create audit logging if enabled
    if (props?.enableAuditLogging !== false) {
      const auditResources = this.createAuditLogging(uniqueSuffix);
      this.auditBucket = auditResources.bucket;
      this.cloudTrail = auditResources.trail;
    }

    // Create stack outputs
    this.createOutputs();

    // Add comprehensive tags for resource management
    this.addResourceTags();
  }

  /**
   * Get existing VPC or create default VPC reference
   */
  private getOrCreateVpc(vpcId?: string): ec2.IVpc {
    if (vpcId) {
      return ec2.Vpc.fromLookup(this, 'ExistingVpc', {
        vpcId: vpcId
      });
    } else {
      // Use default VPC
      return ec2.Vpc.fromLookup(this, 'DefaultVpc', {
        isDefault: true
      });
    }
  }

  /**
   * Create security group for RDS with proper network isolation
   */
  private createDatabaseSecurityGroup(vpc: ec2.IVpc, suffix: string): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: vpc,
      securityGroupName: `shared-db-sg-${suffix}`,
      description: 'Security group for shared database with VPC Lattice access',
      allowAllOutbound: false
    });

    // Allow MySQL/Aurora access only from within the VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL access from VPC CIDR'
    );

    // Self-referencing rule for enhanced security
    securityGroup.addIngressRule(
      securityGroup,
      ec2.Port.tcp(3306),
      'Allow access from same security group'
    );

    return securityGroup;
  }

  /**
   * Create DB subnet group for multi-AZ deployment
   */
  private createDatabaseSubnetGroup(vpc: ec2.IVpc, suffix: string): rds.SubnetGroup {
    return new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      subnetGroupName: `shared-db-subnet-${suffix}`,
      description: 'Subnet group for shared database instance',
      vpc: vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        availabilityZones: vpc.availabilityZones.slice(0, 2) // Use first two AZs
      }
    });
  }

  /**
   * Create shared RDS database instance with enterprise security features
   */
  private createSharedDatabase(
    vpc: ec2.IVpc, 
    securityGroup: ec2.SecurityGroup, 
    subnetGroup: rds.SubnetGroup, 
    suffix: string,
    instanceClass?: string
  ): rds.DatabaseInstance {
    
    // Create database instance with comprehensive security configuration
    const database = new rds.DatabaseInstance(this, 'SharedDatabase', {
      instanceIdentifier: `shared-db-${suffix}`,
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3, 
        instanceClass === 'micro' ? ec2.InstanceSize.MICRO : ec2.InstanceSize.SMALL
      ),
      vpc: vpc,
      subnetGroup: subnetGroup,
      securityGroups: [securityGroup],
      
      // Database configuration
      databaseName: 'multitenant',
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        description: 'Credentials for shared database',
        excludeCharacters: '"@/\\\'',
        secretName: `shared-db-credentials-${suffix}`
      }),
      
      // Security and compliance features
      storageEncrypted: true,
      storageEncryptionKey: undefined, // Use default AWS managed key
      deletionProtection: false, // Set to true for production
      publiclyAccessible: false,
      
      // Backup and maintenance
      backupRetention: cdk.Duration.days(7),
      deleteAutomatedBackups: true,
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'Sun:04:00-Sun:05:00',
      
      // Monitoring and performance
      monitoringInterval: cdk.Duration.seconds(60),
      enablePerformanceInsights: true,
      performanceInsightEncryptionKey: undefined, // Use default AWS managed key
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      
      // Storage configuration
      allocatedStorage: 20,
      maxAllocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      
      // Removal policy for development/testing
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Add resource tags
    cdk.Tags.of(database).add('Environment', 'Multi-Tenant');
    cdk.Tags.of(database).add('Purpose', 'SharedResource');
    cdk.Tags.of(database).add('Component', 'Database');

    return database;
  }

  /**
   * Create VPC Lattice service network with IAM authentication
   */
  private createServiceNetwork(suffix: string): vpclattice.CfnServiceNetwork {
    return new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `multitenant-network-${suffix}`,
      authType: 'AWS_IAM'
    });
  }

  /**
   * Associate VPC with the service network
   */
  private associateVpcWithServiceNetwork(vpc: ec2.IVpc): vpclattice.CfnServiceNetworkVpcAssociation {
    return new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VpcAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      vpcIdentifier: vpc.vpcId
    });
  }

  /**
   * Create resource configuration for RDS integration with VPC Lattice
   */
  private createResourceConfiguration(vpc: ec2.IVpc, suffix: string): vpclattice.CfnResourceConfiguration {
    return new vpclattice.CfnResourceConfiguration(this, 'ResourceConfiguration', {
      name: `shared-database-${suffix}`,
      type: 'SINGLE',
      resourceGatewayIdentifier: vpc.vpcId,
      resourceConfigurationDefinition: {
        ipResource: {
          ipAddress: this.rdsInstance.instanceEndpoint.hostname
        }
      },
      portRanges: ['3306'],
      protocol: 'TCP',
      allowAssociationToShareableServiceNetwork: true
    });
  }

  /**
   * Associate resource configuration with service network
   */
  private associateResourceWithServiceNetwork(resourceConfig: vpclattice.CfnResourceConfiguration): void {
    new vpclattice.CfnResourceConfigurationAssociation(this, 'ResourceAssociation', {
      resourceConfigurationIdentifier: resourceConfig.attrId,
      serviceNetworkIdentifier: this.serviceNetwork.attrId
    });
  }

  /**
   * Create comprehensive authentication policy with team-based access control
   */
  private createAuthenticationPolicy(): void {
    const authPolicy = {
      Version: '2012-10-17',
      Statement: [
        {
          Effect: 'Allow',
          Principal: '*',
          Action: 'vpc-lattice-svcs:Invoke',
          Resource: '*',
          Condition: {
            StringEquals: {
              'aws:PrincipalTag/Team': ['TeamA', 'TeamB']
            },
            DateGreaterThan: {
              'aws:CurrentTime': '2025-01-01T00:00:00Z'
            },
            IpAddress: {
              'aws:SourceIp': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']
            }
          }
        },
        {
          Effect: 'Allow',
          Principal: {
            AWS: `arn:aws:iam::${this.account}:root`
          },
          Action: 'vpc-lattice-svcs:Invoke',
          Resource: '*'
        }
      ]
    };

    new vpclattice.CfnAuthPolicy(this, 'AuthPolicy', {
      resourceIdentifier: this.serviceNetwork.attrId,
      policy: authPolicy
    });
  }

  /**
   * Create IAM roles for different tenant teams with proper tagging
   */
  private createTenantRoles(suffix: string): void {
    // Create Team A role with appropriate tags and policies
    const teamARole = new iam.Role(this, 'TeamARole', {
      roleName: `TeamA-DatabaseAccess-${suffix}`,
      description: 'IAM role for Team A database access through VPC Lattice',
      assumedBy: new iam.AccountRootPrincipal().withConditions({
        StringEquals: {
          'sts:ExternalId': 'TeamA-Access'
        }
      }),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('VPCLatticeServicesInvokeAccess')
      ]
    });

    // Add tags to Team A role
    cdk.Tags.of(teamARole).add('Team', 'TeamA');
    cdk.Tags.of(teamARole).add('Purpose', 'DatabaseAccess');

    // Create Team B role with appropriate tags and policies
    const teamBRole = new iam.Role(this, 'TeamBRole', {
      roleName: `TeamB-DatabaseAccess-${suffix}`,
      description: 'IAM role for Team B database access through VPC Lattice',
      assumedBy: new iam.AccountRootPrincipal().withConditions({
        StringEquals: {
          'sts:ExternalId': 'TeamB-Access'
        }
      }),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('VPCLatticeServicesInvokeAccess')
      ]
    });

    // Add tags to Team B role
    cdk.Tags.of(teamBRole).add('Team', 'TeamB');
    cdk.Tags.of(teamBRole).add('Purpose', 'DatabaseAccess');

    // Create VPC Lattice service role
    const latticeServiceRole = new iam.Role(this, 'LatticeServiceRole', {
      roleName: `VPCLatticeServiceRole-${suffix}`,
      description: 'Service role for VPC Lattice operations',
      assumedBy: new iam.ServicePrincipal('vpc-lattice.amazonaws.com')
    });
  }

  /**
   * Create AWS RAM resource share for cross-account sharing
   */
  private createResourceShare(
    suffix: string, 
    sharedAccountIds?: string[], 
    organizationId?: string
  ): ram.CfnResourceShare {
    
    // Determine principals for sharing
    let principals: string[] = [];
    if (organizationId) {
      principals.push(organizationId);
    } else if (sharedAccountIds && sharedAccountIds.length > 0) {
      principals = sharedAccountIds;
    } else {
      // Default to a placeholder account ID for demonstration
      principals.push('123456789012');
    }

    return new ram.CfnResourceShare(this, 'ResourceShare', {
      name: `database-share-${suffix}`,
      allowExternalPrincipals: !organizationId, // Only allow external if not using Organizations
      principals: principals,
      resourceArns: [this.serviceNetwork.attrArn],
      tags: [
        {
          key: 'Purpose',
          value: 'MultiTenantSharing'
        },
        {
          key: 'Component',
          value: 'ResourceShare'
        }
      ]
    });
  }

  /**
   * Create comprehensive audit logging with CloudTrail and S3
   */
  private createAuditLogging(suffix: string): { bucket: s3.Bucket; trail: cloudtrail.Trail } {
    // Create S3 bucket for CloudTrail logs with security features
    const auditBucket = new s3.Bucket(this, 'AuditLogsBucket', {
      bucketName: `lattice-audit-logs-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'audit-log-lifecycle',
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
          ],
          expiration: cdk.Duration.days(2555) // 7 years retention
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY // For development/testing
    });

    // Create CloudWatch Log Group for CloudTrail
    const logGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/vpc-lattice-audit-${suffix}`,
      retention: logs.RetentionDays.ONE_YEAR,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create CloudTrail with comprehensive logging
    const trail = new cloudtrail.Trail(this, 'AuditTrail', {
      trailName: `VPCLatticeAuditTrail-${suffix}`,
      bucket: auditBucket,
      cloudWatchLogGroup: logGroup,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      sendToCloudWatchLogs: true
    });

    // Add event selectors for VPC Lattice and RAM operations
    trail.addEventSelector(cloudtrail.DataResourceType.S3_OBJECT, [`${auditBucket.bucketArn}/*`]);
    
    return { bucket: auditBucket, trail: trail };
  }

  /**
   * Create comprehensive stack outputs for integration and verification
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`
    });

    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      value: this.serviceNetwork.attrArn,
      description: 'VPC Lattice Service Network ARN',
      exportName: `${this.stackName}-ServiceNetworkArn`
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: this.rdsInstance.instanceEndpoint.hostname,
      description: 'RDS Database Endpoint',
      exportName: `${this.stackName}-DatabaseEndpoint`
    });

    new cdk.CfnOutput(this, 'DatabasePort', {
      value: this.rdsInstance.instanceEndpoint.port.toString(),
      description: 'RDS Database Port',
      exportName: `${this.stackName}-DatabasePort`
    });

    new cdk.CfnOutput(this, 'ResourceShareArn', {
      value: this.resourceShare.attrResourceShareArn,
      description: 'AWS RAM Resource Share ARN',
      exportName: `${this.stackName}-ResourceShareArn`
    });

    if (this.auditBucket) {
      new cdk.CfnOutput(this, 'AuditBucketName', {
        value: this.auditBucket.bucketName,
        description: 'S3 Bucket for CloudTrail audit logs',
        exportName: `${this.stackName}-AuditBucketName`
      });
    }

    if (this.cloudTrail) {
      new cdk.CfnOutput(this, 'CloudTrailArn', {
        value: this.cloudTrail.trailArn,
        description: 'CloudTrail ARN for audit logging',
        exportName: `${this.stackName}-CloudTrailArn`
      });
    }
  }

  /**
   * Add comprehensive resource tags for management and compliance
   */
  private addResourceTags(): void {
    const tags = {
      'Project': 'MultiTenantResourceSharing',
      'Component': 'VPCLattice-RAM-Integration',
      'Environment': 'Development',
      'CostCenter': 'Engineering',
      'DataClassification': 'Internal',
      'Backup': 'Required',
      'MaintenanceWindow': 'Sunday-04:00-05:00'
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const sharedAccountIds = app.node.tryGetContext('sharedAccountIds') || 
  process.env.SHARED_ACCOUNT_IDS?.split(',');
const organizationId = app.node.tryGetContext('organizationId') || 
  process.env.ORGANIZATION_ID;
const dbInstanceClass = app.node.tryGetContext('dbInstanceClass') || 
  process.env.DB_INSTANCE_CLASS || 'micro';
const vpcId = app.node.tryGetContext('vpcId') || 
  process.env.VPC_ID;
const enableAuditLogging = app.node.tryGetContext('enableAuditLogging') !== false;

// Create the stack with configuration
new MultiTenantResourceSharingStack(app, 'MultiTenantResourceSharingStack', {
  description: 'Multi-Tenant Resource Sharing with VPC Lattice and RAM (Recipe: f7e9d2a8)',
  sharedAccountIds: sharedAccountIds,
  organizationId: organizationId,
  dbInstanceClass: dbInstanceClass,
  vpcId: vpcId,
  enableAuditLogging: enableAuditLogging,
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },

  // Stack-level tags
  tags: {
    'Recipe': 'multi-tenant-resource-sharing-lattice-ram',
    'RecipeId': 'f7e9d2a8',
    'GeneratedBy': 'CDK-TypeScript',
    'Version': '1.0.0'
  }
});

app.synth();