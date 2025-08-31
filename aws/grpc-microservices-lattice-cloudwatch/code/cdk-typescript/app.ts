#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * Properties for the gRPC Microservices Stack
 */
interface GrpcMicroservicesStackProps extends cdk.StackProps {
  /**
   * Environment name (e.g., 'dev', 'staging', 'prod')
   */
  environment?: string;
  
  /**
   * VPC CIDR block
   */
  vpcCidr?: string;
  
  /**
   * Instance type for EC2 instances
   */
  instanceType?: ec2.InstanceType;
  
  /**
   * Number of instances per service
   */
  instanceCount?: number;
}

/**
 * CDK Stack for gRPC Microservices with VPC Lattice and CloudWatch
 * 
 * This stack creates a complete gRPC microservices architecture using:
 * - VPC Lattice for service mesh networking with HTTP/2 support
 * - EC2 instances hosting gRPC services
 * - CloudWatch monitoring and alerting
 * - Security groups and IAM roles with least privilege
 */
class GrpcMicroservicesStack extends cdk.Stack {
  private readonly vpc: ec2.Vpc;
  private readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  private readonly logGroup: logs.LogGroup;
  private readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: GrpcMicroservicesStackProps = {}) {
    super(scope, id, props);

    // Set default values
    const environment = props.environment || 'dev';
    const vpcCidr = props.vpcCidr || '10.0.0.0/16';
    const instanceType = props.instanceType || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO);
    const instanceCount = props.instanceCount || 1;

    // Create VPC with public and private subnets
    this.vpc = this.createVpc(vpcCidr, environment);

    // Create VPC Lattice Service Network
    this.serviceNetwork = this.createServiceNetwork(environment);

    // Associate VPC with Service Network
    this.associateVpcWithServiceNetwork();

    // Create CloudWatch resources
    this.logGroup = this.createCloudWatchResources(environment);

    // Create security group for gRPC services
    const securityGroup = this.createSecurityGroup();

    // Create gRPC services configuration
    const services = this.createGrpcServices(environment, securityGroup, instanceType, instanceCount);

    // Create CloudWatch Dashboard
    this.dashboard = this.createDashboard(environment, services);

    // Create CloudWatch Alarms
    this.createCloudWatchAlarms(environment, services);

    // Output important values
    this.createOutputs(services);
  }

  /**
   * Create VPC with appropriate subnets for gRPC services
   */
  private createVpc(cidr: string, environment: string): ec2.Vpc {
    return new ec2.Vpc(this, 'GrpcVpc', {
      ipAddresses: ec2.IpAddresses.cidr(cidr),
      maxAzs: 2,
      natGateways: 1, // Cost optimization - single NAT gateway
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
      flowLogs: {
        cloudWatchLogs: {
          destination: ec2.FlowLogDestination.toCloudWatchLogs(),
          trafficType: ec2.FlowLogTrafficType.REJECT, // Monitor rejected traffic for security
        }
      }
    });
  }

  /**
   * Create VPC Lattice Service Network
   */
  private createServiceNetwork(environment: string): vpclattice.CfnServiceNetwork {
    return new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `grpc-microservices-${environment}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'gRPC-Services' },
        { key: 'Protocol', value: 'HTTP2' }
      ]
    });
  }

  /**
   * Associate VPC with Service Network
   */
  private associateVpcWithServiceNetwork(): void {
    new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VpcAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      vpcIdentifier: this.vpc.vpcId,
      tags: [
        { key: 'Service', value: 'gRPC-Network' }
      ]
    });
  }

  /**
   * Create CloudWatch Log Group and access logging configuration
   */
  private createCloudWatchResources(environment: string): logs.LogGroup {
    const logGroup = new logs.LogGroup(this, 'VpcLatticeLogGroup', {
      logGroupName: `/aws/vpc-lattice/grpc-services-${environment}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY // For development environments
    });

    // Enable access logging for the service network
    new vpclattice.CfnAccessLogSubscription(this, 'AccessLogSubscription', {
      resourceIdentifier: this.serviceNetwork.attrId,
      destinationArn: logGroup.logGroupArn
    });

    return logGroup;
  }

  /**
   * Create security group for gRPC services
   */
  private createSecurityGroup(): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'GrpcSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for gRPC microservices',
      allowAllOutbound: true
    });

    // Allow gRPC traffic on ports 50051-50053
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcpRange(50051, 50053),
      'gRPC service ports'
    );

    // Allow health check traffic on port 8080
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(8080),
      'Health check endpoint'
    );

    // Allow SSH for management (only from VPC)
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(22),
      'SSH access'
    );

    return securityGroup;
  }

  /**
   * Create gRPC services with target groups and instances
   */
  private createGrpcServices(
    environment: string, 
    securityGroup: ec2.SecurityGroup, 
    instanceType: ec2.InstanceType,
    instanceCount: number
  ) {
    const services = [];

    const serviceConfigs = [
      { name: 'user', port: 50051 },
      { name: 'order', port: 50052 },
      { name: 'inventory', port: 50053 }
    ];

    for (const config of serviceConfigs) {
      const service = this.createGrpcService(
        config.name,
        config.port,
        environment,
        securityGroup,
        instanceType,
        instanceCount
      );
      services.push(service);
    }

    return services;
  }

  /**
   * Create individual gRPC service with all necessary components
   */
  private createGrpcService(
    serviceName: string,
    grpcPort: number,
    environment: string,
    securityGroup: ec2.SecurityGroup,
    instanceType: ec2.InstanceType,
    instanceCount: number
  ) {
    // Create IAM role for EC2 instances
    const instanceRole = new iam.Role(this, `${serviceName}ServiceRole`, {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ]
    });

    // Create instance profile
    const instanceProfile = new iam.CfnInstanceProfile(this, `${serviceName}InstanceProfile`, {
      roles: [instanceRole.roleName]
    });

    // Create target group for gRPC service with HTTP/2 support
    const targetGroup = new vpclattice.CfnTargetGroup(this, `${serviceName}TargetGroup`, {
      name: `${serviceName}-service-${environment}`,
      type: 'INSTANCE',
      config: {
        port: grpcPort,
        protocol: 'HTTP',
        protocolVersion: 'HTTP2', // Essential for gRPC
        vpcIdentifier: this.vpc.vpcId,
        healthCheck: {
          enabled: true,
          protocol: 'HTTP',
          protocolVersion: 'HTTP1', // Health checks use HTTP/1.1
          port: 8080,
          path: '/health',
          healthCheckIntervalSeconds: 30,
          healthCheckTimeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
          matcher: {
            httpCode: '200'
          }
        }
      },
      tags: [
        { key: 'Service', value: `${serviceName}Service` },
        { key: 'Environment', value: environment }
      ]
    });

    // Create user data script for gRPC service
    const userData = this.createUserDataScript(serviceName, grpcPort);

    // Launch EC2 instances
    const instances = [];
    const privateSubnets = this.vpc.privateSubnets;
    
    for (let i = 0; i < instanceCount; i++) {
      const subnet = privateSubnets[i % privateSubnets.length];
      
      const instance = new ec2.Instance(this, `${serviceName}Instance${i}`, {
        instanceType,
        machineImage: ec2.MachineImage.latestAmazonLinux2023(),
        vpc: this.vpc,
        vpcSubnets: { subnets: [subnet] },
        securityGroup,
        userData: ec2.UserData.custom(userData),
        role: instanceRole,
        keyName: undefined, // Use SSM Session Manager instead of SSH keys
      });

      // Register instance with target group
      new vpclattice.CfnTargetGroupTargetAssociation(this, `${serviceName}TargetAssociation${i}`, {
        targetGroupIdentifier: targetGroup.attrId,
        target: {
          id: instance.instanceId
        }
      });

      instances.push(instance);
    }

    // Create VPC Lattice service
    const latticeService = new vpclattice.CfnService(this, `${serviceName}LatticeService`, {
      name: `${serviceName}-service-${environment}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Service', value: `${serviceName}Service` },
        { key: 'Protocol', value: 'gRPC' },
        { key: 'Environment', value: environment }
      ]
    });

    // Associate service with service network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, `${serviceName}ServiceAssociation`, {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      serviceIdentifier: latticeService.attrId,
      tags: [
        { key: 'Service', value: `${serviceName}Service` }
      ]
    });

    // Create HTTPS listener for gRPC traffic
    const listener = new vpclattice.CfnListener(this, `${serviceName}Listener`, {
      serviceIdentifier: latticeService.attrId,
      name: 'grpc-listener',
      protocol: 'HTTPS',
      port: 443,
      defaultAction: {
        forward: {
          targetGroups: [{
            targetGroupIdentifier: targetGroup.attrId,
            weight: 100
          }]
        }
      },
      tags: [
        { key: 'Protocol', value: 'gRPC' }
      ]
    });

    return {
      name: serviceName,
      service: latticeService,
      targetGroup,
      listener,
      instances,
      grpcPort
    };
  }

  /**
   * Create user data script for EC2 instances
   */
  private createUserDataScript(serviceName: string, grpcPort: number): string {
    return `#!/bin/bash
yum update -y
yum install -y python3 python3-pip

# Install required Python packages
pip3 install grpcio grpcio-tools flask

# Create health check server
cat > /home/ec2-user/health_server.py << 'EOF'
from flask import Flask, jsonify
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy', 
        'service': '${serviceName}-service',
        'grpc_port': ${grpcPort}
    }), 200

@app.route('/ready')
def ready():
    return jsonify({
        'status': 'ready',
        'service': '${serviceName}-service'
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

# Create a simple gRPC server stub
cat > /home/ec2-user/grpc_server.py << 'EOF'
import grpc
from concurrent import futures
import time
import logging

# This is a stub - in a real implementation, you would have your gRPC service definition
# For now, it just starts a server that listens on the specified port

def serve():
    # In a real implementation, add your gRPC service here
    print(f"gRPC ${serviceName} service would start on port ${grpcPort}")
    
    # Keep the process running
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("Shutting down gRPC server")

if __name__ == '__main__':
    serve()
EOF

# Start health check server
nohup python3 /home/ec2-user/health_server.py > /var/log/health_server.log 2>&1 &

# Start gRPC server stub
nohup python3 /home/ec2-user/grpc_server.py > /var/log/grpc_server.log 2>&1 &

# Install and configure CloudWatch agent
yum install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/health_server.log",
                        "log_group_name": "/aws/ec2/grpc-services/${serviceName}",
                        "log_stream_name": "{instance_id}/health"
                    },
                    {
                        "file_path": "/var/log/grpc_server.log",
                        "log_group_name": "/aws/ec2/grpc-services/${serviceName}",
                        "log_stream_name": "{instance_id}/grpc"
                    }
                ]
            }
        }
    },
    "metrics": {
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 300
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 300,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 300
            }
        }
    }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
`;
  }

  /**
   * Create CloudWatch Dashboard for monitoring
   */
  private createDashboard(environment: string, services: any[]): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'GrpcDashboard', {
      dashboardName: `gRPC-Microservices-${environment}`,
    });

    // Add request count widget
    const requestCountWidget = new cloudwatch.GraphWidget({
      title: 'gRPC Request Count',
      width: 12,
      height: 6,
      left: services.map(service => 
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'TotalRequestCount',
          dimensionsMap: {
            Service: `${service.name}-service-${environment}`
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5)
        })
      )
    });

    // Add latency widget
    const latencyWidget = new cloudwatch.GraphWidget({
      title: 'gRPC Request Latency',
      width: 12,
      height: 6,
      left: services.map(service => 
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'RequestTime',
          dimensionsMap: {
            Service: `${service.name}-service-${environment}`
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5)
        })
      )
    });

    // Add error rate widget
    const errorWidget = new cloudwatch.GraphWidget({
      title: 'Error Rates',
      width: 12,
      height: 6,
      left: services.map(service => 
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HTTPCode_5XX_Count',
          dimensionsMap: {
            Service: `${service.name}-service-${environment}`
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5)
        })
      )
    });

    // Add target health widget
    const healthWidget = new cloudwatch.GraphWidget({
      title: 'Target Health',
      width: 12,
      height: 6,
      left: services.map(service => 
        new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HealthyTargetCount',
          dimensionsMap: {
            TargetGroup: `${service.name}-service-${environment}`
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5)
        })
      )
    });

    dashboard.addWidgets(requestCountWidget, latencyWidget);
    dashboard.addWidgets(errorWidget, healthWidget);

    return dashboard;
  }

  /**
   * Create CloudWatch Alarms for proactive monitoring
   */
  private createCloudWatchAlarms(environment: string, services: any[]): void {
    services.forEach(service => {
      // High error rate alarm
      new cloudwatch.Alarm(this, `${service.name}HighErrorAlarm`, {
        alarmName: `gRPC-${service.name}Service-HighErrorRate-${environment}`,
        alarmDescription: `High error rate in ${service.name} service`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HTTPCode_5XX_Count',
          dimensionsMap: {
            Service: `${service.name}-service-${environment}`
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5)
        }),
        threshold: 10,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      // High latency alarm
      new cloudwatch.Alarm(this, `${service.name}HighLatencyAlarm`, {
        alarmName: `gRPC-${service.name}Service-HighLatency-${environment}`,
        alarmDescription: `High latency in ${service.name} service`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'RequestTime',
          dimensionsMap: {
            Service: `${service.name}-service-${environment}`
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5)
        }),
        threshold: 1000, // 1 second in milliseconds
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      // Unhealthy targets alarm
      new cloudwatch.Alarm(this, `${service.name}UnhealthyTargetsAlarm`, {
        alarmName: `gRPC-${service.name}Service-UnhealthyTargets-${environment}`,
        alarmDescription: `Unhealthy targets in ${service.name} service`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/VpcLattice',
          metricName: 'HealthyTargetCount',
          dimensionsMap: {
            TargetGroup: `${service.name}-service-${environment}`
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5)
        }),
        threshold: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.BREACHING
      });
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(services: any[]): void {
    new cdk.CfnOutput(this, 'VpcId', {
      description: 'VPC ID for the gRPC services',
      value: this.vpc.vpcId
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      description: 'VPC Lattice Service Network ID',
      value: this.serviceNetwork.attrId
    });

    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      description: 'VPC Lattice Service Network ARN',
      value: this.serviceNetwork.attrArn
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      description: 'CloudWatch Dashboard URL',
      value: `https://${cdk.Stack.of(this).region}.console.aws.amazon.com/cloudwatch/home?region=${cdk.Stack.of(this).region}#dashboards:name=${this.dashboard.dashboardName}`
    });

    services.forEach(service => {
      new cdk.CfnOutput(this, `${service.name}ServiceId`, {
        description: `${service.name} service ID`,
        value: service.service.attrId
      });

      new cdk.CfnOutput(this, `${service.name}ServiceArn`, {
        description: `${service.name} service ARN`,
        value: service.service.attrArn
      });

      new cdk.CfnOutput(this, `${service.name}ServiceDns`, {
        description: `${service.name} service DNS endpoint`,
        value: service.service.attrDnsEntryDomainName || 'DNS not available yet'
      });
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get environment and account from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';

// Create the main stack
const grpcStack = new GrpcMicroservicesStack(app, 'GrpcMicroservicesStack', {
  env: {
    account,
    region
  },
  environment,
  description: 'gRPC Microservices with VPC Lattice and CloudWatch monitoring'
});

// Apply CDK Nag for security best practices
// Only apply in non-development environments to avoid overwhelming developers
if (environment !== 'dev') {
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}

// Add tags to all resources
cdk.Tags.of(grpcStack).add('Project', 'gRPC-Microservices');
cdk.Tags.of(grpcStack).add('Environment', environment);
cdk.Tags.of(grpcStack).add('ManagedBy', 'CDK');
cdk.Tags.of(grpcStack).add('Recipe', 'grpc-microservices-lattice-cloudwatch');