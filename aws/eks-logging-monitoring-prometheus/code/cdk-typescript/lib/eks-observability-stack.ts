import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cwactions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as cr from 'aws-cdk-lib/custom-resources';

export interface EksObservabilityStackProps extends cdk.StackProps {
  clusterName: string;
  prometheusWorkspaceName: string;
  enableControlPlaneLogging: boolean;
  enableContainerInsights: boolean;
  nodeGroupConfig: {
    instanceTypes: string[];
    minSize: number;
    maxSize: number;
    desiredSize: number;
  };
}

export class EksObservabilityStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly vpc: ec2.Vpc;
  public readonly prometheusWorkspace: cdk.CfnOutput;
  public readonly dashboardUrl: cdk.CfnOutput;

  constructor(scope: Construct, id: string, props: EksObservabilityStackProps) {
    super(scope, id, props);

    // Create VPC for EKS cluster
    this.vpc = new ec2.Vpc(this, 'EksVpc', {
      maxAzs: 2,
      natGateways: 2,
      cidr: '10.0.0.0/16',
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create EKS cluster with comprehensive logging
    this.cluster = new eks.Cluster(this, 'EksCluster', {
      clusterName: props.clusterName,
      version: eks.KubernetesVersion.V1_28,
      vpc: this.vpc,
      vpcSubnets: [{
        subnets: this.vpc.privateSubnets,
      }],
      
      // Enable all control plane logging
      clusterLogging: props.enableControlPlaneLogging ? [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ] : [],
      
      // Default capacity configuration
      defaultCapacity: 0, // We'll add managed node groups separately
      
      // Enable endpoint access from both private and public
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      
      // Enable OIDC provider for IAM roles for service accounts
      outputConfigCommand: true,
      outputClusterName: true,
      outputMastersRoleArn: true,
    });

    // Create managed node group
    const nodeGroup = this.cluster.addNodegroupCapacity('EksNodeGroup', {
      instanceTypes: props.nodeGroupConfig.instanceTypes.map(type => 
        ec2.InstanceType.of(
          ec2.InstanceClass.T3,
          ec2.InstanceSize.MEDIUM
        )
      ),
      minSize: props.nodeGroupConfig.minSize,
      maxSize: props.nodeGroupConfig.maxSize,
      desiredSize: props.nodeGroupConfig.desiredSize,
      subnets: {
        subnets: this.vpc.privateSubnets,
      },
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      capacityType: eks.CapacityType.ON_DEMAND,
      diskSize: 20,
      
      // Enable remote access if needed
      remoteAccess: {
        ec2SshKey: this.node.tryGetContext('ec2SshKey'),
      },
    });

    // Add CloudWatch addon for Container Insights
    if (props.enableContainerInsights) {
      this.enableContainerInsights();
    }

    // Deploy monitoring components
    this.deployFluentBit();
    this.deployCloudWatchAgent();
    this.createPrometheusWorkspace(props.prometheusWorkspaceName);
    this.createCloudWatchDashboard(props.clusterName);
    this.createCloudWatchAlarms(props.clusterName);
    this.deploySampleApplication();

    // Add tags to all resources
    if (props.tags) {
      Object.entries(props.tags).forEach(([key, value]) => {
        cdk.Tags.of(this).add(key, value);
      });
    }
  }

  private enableContainerInsights(): void {
    // Create CloudWatch namespace
    const cloudwatchNamespace = this.cluster.addManifest('CloudwatchNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'amazon-cloudwatch',
        labels: {
          name: 'amazon-cloudwatch',
        },
      },
    });

    // Create service account for CloudWatch agent
    const cloudwatchServiceAccount = new eks.ServiceAccount(this, 'CloudwatchServiceAccount', {
      cluster: this.cluster,
      name: 'cloudwatch-agent',
      namespace: 'amazon-cloudwatch',
    });

    // Add CloudWatch agent server policy
    cloudwatchServiceAccount.role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
    );

    // Add dependency
    cloudwatchServiceAccount.node.addDependency(cloudwatchNamespace);
  }

  private deployFluentBit(): void {
    // Create ConfigMap for Fluent Bit configuration
    const fluentBitConfig = this.cluster.addManifest('FluentBitConfig', {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'fluent-bit-config',
        namespace: 'amazon-cloudwatch',
      },
      data: {
        'fluent-bit.conf': `
[SERVICE]
    Flush                     5
    Grace                     30
    Log_Level                 info
    Daemon                    off
    Parsers_File              parsers.conf
    HTTP_Server               On
    HTTP_Listen               0.0.0.0
    HTTP_Port                 2020
    storage.path              /var/fluent-bit/state/flb-storage/
    storage.sync              normal
    storage.checksum          off
    storage.backlog.mem_limit 5M

[INPUT]
    Name                tail
    Tag                 application.*
    Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
    Path                /var/log/containers/*.log
    multiline.parser    docker, cri
    DB                  /var/fluent-bit/state/flb_container.db
    Mem_Buf_Limit       50MB
    Skip_Long_Lines     On
    Refresh_Interval    10
    Rotate_Wait         30
    storage.type        filesystem
    Read_from_Head      Off

[FILTER]
    Name                kubernetes
    Match               application.*
    Kube_URL            https://kubernetes.default.svc:443
    Kube_Tag_Prefix     application.var.log.containers.
    Merge_Log           On
    Merge_Log_Key       log_processed
    K8S-Logging.Parser  On
    K8S-Logging.Exclude Off
    Labels              Off
    Annotations         Off
    Use_Kubelet         On
    Kubelet_Port        10250
    Buffer_Size         0

[OUTPUT]
    Name                cloudwatch_logs
    Match               application.*
    region              ${this.region}
    log_group_name      /aws/containerinsights/${this.cluster.clusterName}/application
    log_stream_prefix   \${kubernetes_namespace_name}-
    auto_create_group   On
    extra_user_agent    container-insights
        `,
        'parsers.conf': `
[PARSER]
    Name                docker
    Format              json
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L
    Time_Keep           On

[PARSER]
    Name                cri
    Format              regex
    Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
    Time_Key            time
    Time_Format         %Y-%m-%dT%H:%M:%S.%L%z
        `,
      },
    });

    // Deploy Fluent Bit DaemonSet
    const fluentBitDaemonSet = this.cluster.addManifest('FluentBitDaemonSet', {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: {
        name: 'fluent-bit',
        namespace: 'amazon-cloudwatch',
      },
      spec: {
        selector: {
          matchLabels: {
            name: 'fluent-bit',
          },
        },
        template: {
          metadata: {
            labels: {
              name: 'fluent-bit',
            },
          },
          spec: {
            serviceAccountName: 'cloudwatch-agent',
            containers: [{
              name: 'fluent-bit',
              image: 'amazon/aws-for-fluent-bit:stable',
              imagePullPolicy: 'Always',
              env: [
                {
                  name: 'AWS_REGION',
                  value: this.region,
                },
                {
                  name: 'CLUSTER_NAME',
                  value: this.cluster.clusterName,
                },
                {
                  name: 'HTTP_SERVER',
                  value: 'On',
                },
                {
                  name: 'HTTP_PORT',
                  value: '2020',
                },
                {
                  name: 'READ_FROM_HEAD',
                  value: 'Off',
                },
                {
                  name: 'READ_FROM_TAIL',
                  value: 'On',
                },
                {
                  name: 'HOST_NAME',
                  valueFrom: {
                    fieldRef: {
                      fieldPath: 'spec.nodeName',
                    },
                  },
                },
                {
                  name: 'HOSTNAME',
                  valueFrom: {
                    fieldRef: {
                      apiVersion: 'v1',
                      fieldPath: 'metadata.name',
                    },
                  },
                },
              ],
              resources: {
                limits: {
                  memory: '200Mi',
                },
                requests: {
                  cpu: '500m',
                  memory: '100Mi',
                },
              },
              volumeMounts: [
                {
                  name: 'fluentbitstate',
                  mountPath: '/var/fluent-bit/state',
                },
                {
                  name: 'varlog',
                  mountPath: '/var/log',
                  readOnly: true,
                },
                {
                  name: 'varlibdockercontainers',
                  mountPath: '/var/lib/docker/containers',
                  readOnly: true,
                },
                {
                  name: 'fluent-bit-config',
                  mountPath: '/fluent-bit/etc/',
                },
                {
                  name: 'runlogjournal',
                  mountPath: '/run/log/journal',
                  readOnly: true,
                },
                {
                  name: 'dmesg',
                  mountPath: '/var/log/dmesg',
                  readOnly: true,
                },
              ],
            }],
            terminationGracePeriodSeconds: 10,
            volumes: [
              {
                name: 'fluentbitstate',
                hostPath: {
                  path: '/var/fluent-bit/state',
                },
              },
              {
                name: 'varlog',
                hostPath: {
                  path: '/var/log',
                },
              },
              {
                name: 'varlibdockercontainers',
                hostPath: {
                  path: '/var/lib/docker/containers',
                },
              },
              {
                name: 'fluent-bit-config',
                configMap: {
                  name: 'fluent-bit-config',
                },
              },
              {
                name: 'runlogjournal',
                hostPath: {
                  path: '/run/log/journal',
                },
              },
              {
                name: 'dmesg',
                hostPath: {
                  path: '/var/log/dmesg',
                },
              },
            ],
            tolerations: [
              {
                key: 'node-role.kubernetes.io/master',
                operator: 'Exists',
                effect: 'NoSchedule',
              },
              {
                operator: 'Exists',
                effect: 'NoExecute',
              },
              {
                operator: 'Exists',
                effect: 'NoSchedule',
              },
            ],
          },
        },
      },
    });

    fluentBitDaemonSet.node.addDependency(fluentBitConfig);
  }

  private deployCloudWatchAgent(): void {
    // Create ConfigMap for CloudWatch agent configuration
    const cwAgentConfig = this.cluster.addManifest('CwAgentConfig', {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: {
        name: 'cwagentconfig',
        namespace: 'amazon-cloudwatch',
      },
      data: {
        'cwagentconfig.json': JSON.stringify({
          metrics: {
            namespace: 'ContainerInsights',
            metrics_collected: {
              cpu: {
                measurement: [
                  'cpu_usage_idle',
                  'cpu_usage_iowait',
                  'cpu_usage_user',
                  'cpu_usage_system',
                ],
                metrics_collection_interval: 60,
                resources: ['*'],
                totalcpu: false,
              },
              disk: {
                measurement: ['used_percent'],
                metrics_collection_interval: 60,
                resources: ['*'],
              },
              diskio: {
                measurement: [
                  'io_time',
                  'read_bytes',
                  'write_bytes',
                  'reads',
                  'writes',
                ],
                metrics_collection_interval: 60,
                resources: ['*'],
              },
              mem: {
                measurement: ['mem_used_percent'],
                metrics_collection_interval: 60,
              },
              netstat: {
                measurement: ['tcp_established', 'tcp_time_wait'],
                metrics_collection_interval: 60,
              },
              swap: {
                measurement: ['swap_used_percent'],
                metrics_collection_interval: 60,
              },
            },
          },
        }),
      },
    });

    // Deploy CloudWatch agent DaemonSet
    const cwAgentDaemonSet = this.cluster.addManifest('CwAgentDaemonSet', {
      apiVersion: 'apps/v1',
      kind: 'DaemonSet',
      metadata: {
        name: 'cloudwatch-agent',
        namespace: 'amazon-cloudwatch',
      },
      spec: {
        selector: {
          matchLabels: {
            name: 'cloudwatch-agent',
          },
        },
        template: {
          metadata: {
            labels: {
              name: 'cloudwatch-agent',
            },
          },
          spec: {
            serviceAccountName: 'cloudwatch-agent',
            containers: [{
              name: 'cloudwatch-agent',
              image: 'amazon/cloudwatch-agent:1.300026.2b361',
              ports: [{
                containerPort: 8125,
                hostPort: 8125,
                protocol: 'UDP',
              }],
              resources: {
                limits: {
                  cpu: '200m',
                  memory: '200Mi',
                },
                requests: {
                  cpu: '200m',
                  memory: '200Mi',
                },
              },
              env: [
                {
                  name: 'HOST_IP',
                  valueFrom: {
                    fieldRef: {
                      fieldPath: 'status.hostIP',
                    },
                  },
                },
                {
                  name: 'HOST_NAME',
                  valueFrom: {
                    fieldRef: {
                      fieldPath: 'spec.nodeName',
                    },
                  },
                },
                {
                  name: 'K8S_NAMESPACE',
                  valueFrom: {
                    fieldRef: {
                      fieldPath: 'metadata.namespace',
                    },
                  },
                },
              ],
              volumeMounts: [
                {
                  name: 'cwagentconfig',
                  mountPath: '/etc/cwagentconfig',
                },
                {
                  name: 'rootfs',
                  mountPath: '/rootfs',
                  readOnly: true,
                },
                {
                  name: 'dockersock',
                  mountPath: '/var/run/docker.sock',
                  readOnly: true,
                },
                {
                  name: 'varlibdocker',
                  mountPath: '/var/lib/docker',
                  readOnly: true,
                },
                {
                  name: 'containerdsock',
                  mountPath: '/run/containerd/containerd.sock',
                  readOnly: true,
                },
                {
                  name: 'sys',
                  mountPath: '/sys',
                  readOnly: true,
                },
                {
                  name: 'devdisk',
                  mountPath: '/dev/disk',
                  readOnly: true,
                },
              ],
            }],
            volumes: [
              {
                name: 'cwagentconfig',
                configMap: {
                  name: 'cwagentconfig',
                },
              },
              {
                name: 'rootfs',
                hostPath: {
                  path: '/',
                },
              },
              {
                name: 'dockersock',
                hostPath: {
                  path: '/var/run/docker.sock',
                },
              },
              {
                name: 'varlibdocker',
                hostPath: {
                  path: '/var/lib/docker',
                },
              },
              {
                name: 'containerdsock',
                hostPath: {
                  path: '/run/containerd/containerd.sock',
                },
              },
              {
                name: 'sys',
                hostPath: {
                  path: '/sys',
                },
              },
              {
                name: 'devdisk',
                hostPath: {
                  path: '/dev/disk/',
                },
              },
            ],
            terminationGracePeriodSeconds: 60,
            tolerations: [
              {
                operator: 'Exists',
                effect: 'NoSchedule',
              },
              {
                operator: 'Exists',
                effect: 'NoExecute',
              },
            ],
          },
        },
      },
    });

    cwAgentDaemonSet.node.addDependency(cwAgentConfig);
  }

  private createPrometheusWorkspace(workspaceName: string): void {
    // Create Prometheus workspace using custom resource
    const prometheusWorkspace = new cr.AwsCustomResource(this, 'PrometheusWorkspace', {
      onCreate: {
        service: 'PrometheusService',
        action: 'createWorkspace',
        parameters: {
          alias: workspaceName,
        },
        physicalResourceId: cr.PhysicalResourceId.fromResponse('workspaceId'),
      },
      onDelete: {
        service: 'PrometheusService',
        action: 'deleteWorkspace',
        parameters: {
          workspaceId: new cr.PhysicalResourceIdReference(),
        },
      },
      policy: cr.AwsCustomResourcePolicy.fromStatements([
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'aps:CreateWorkspace',
            'aps:DeleteWorkspace',
            'aps:DescribeWorkspace',
            'aps:ListWorkspaces',
          ],
          resources: ['*'],
        }),
      ]),
    });

    // Output the workspace ID
    this.prometheusWorkspace = new cdk.CfnOutput(this, 'PrometheusWorkspaceId', {
      value: prometheusWorkspace.getResponseField('workspaceId'),
      description: 'Amazon Managed Service for Prometheus Workspace ID',
    });
  }

  private createCloudWatchDashboard(clusterName: string): void {
    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'EksDashboard', {
      dashboardName: `${clusterName}-observability`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'EKS Cluster Node Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'cluster_node_count',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'cluster_node_running_count',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'cluster_node_failed_count',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'EKS Cluster Pod Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'cluster_running_count',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'cluster_pending_count',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'cluster_failed_count',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Node Resource Utilization',
            left: [
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'node_cpu_utilization',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'node_memory_utilization',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'ContainerInsights',
                metricName: 'node_filesystem_utilization',
                dimensionsMap: {
                  ClusterName: clusterName,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.LogQueryWidget({
            title: 'EKS Control Plane Errors',
            logGroups: [
              logs.LogGroup.fromLogGroupName(this, 'EksControlPlaneLogGroup', `/aws/eks/${clusterName}/cluster`),
            ],
            queryString: `
              fields @timestamp, @message
              | filter @message like /ERROR/
              | sort @timestamp desc
              | limit 20
            `,
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Output dashboard URL
    this.dashboardUrl = new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
    });
  }

  private createCloudWatchAlarms(clusterName: string): void {
    // Create SNS topic for alerts
    const alertTopic = new sns.Topic(this, 'EksAlertTopic', {
      topicName: `${clusterName}-alerts`,
      displayName: 'EKS Cluster Alerts',
    });

    // High CPU utilization alarm
    const cpuAlarm = new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `${clusterName}-high-cpu-utilization`,
      alarmDescription: 'High CPU utilization in EKS cluster',
      metric: new cloudwatch.Metric({
        namespace: 'ContainerInsights',
        metricName: 'node_cpu_utilization',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    cpuAlarm.addAlarmAction(new cwactions.SnsAction(alertTopic));

    // High memory utilization alarm
    const memoryAlarm = new cloudwatch.Alarm(this, 'HighMemoryAlarm', {
      alarmName: `${clusterName}-high-memory-utilization`,
      alarmDescription: 'High memory utilization in EKS cluster',
      metric: new cloudwatch.Metric({
        namespace: 'ContainerInsights',
        metricName: 'node_memory_utilization',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    memoryAlarm.addAlarmAction(new cwactions.SnsAction(alertTopic));

    // High number of failed pods alarm
    const podFailureAlarm = new cloudwatch.Alarm(this, 'HighPodFailureAlarm', {
      alarmName: `${clusterName}-high-pod-count`,
      alarmDescription: 'High number of failed pods in EKS cluster',
      metric: new cloudwatch.Metric({
        namespace: 'ContainerInsights',
        metricName: 'cluster_failed_count',
        dimensionsMap: {
          ClusterName: clusterName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });

    podFailureAlarm.addAlarmAction(new cwactions.SnsAction(alertTopic));

    // Output SNS topic ARN
    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS Topic ARN for EKS alerts',
    });
  }

  private deploySampleApplication(): void {
    // Deploy sample application with Prometheus metrics
    const sampleApp = this.cluster.addManifest('SampleApp', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        name: 'sample-app',
        namespace: 'default',
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            app: 'sample-app',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'sample-app',
            },
            annotations: {
              'prometheus.io/scrape': 'true',
              'prometheus.io/port': '8080',
              'prometheus.io/path': '/metrics',
            },
          },
          spec: {
            containers: [{
              name: 'sample-app',
              image: 'nginx:1.21',
              ports: [
                {
                  containerPort: 80,
                },
                {
                  containerPort: 8080,
                },
              ],
              resources: {
                requests: {
                  cpu: '100m',
                  memory: '128Mi',
                },
                limits: {
                  cpu: '200m',
                  memory: '256Mi',
                },
              },
              env: [{
                name: 'PROMETHEUS_ENABLED',
                value: 'true',
              }],
            }],
          },
        },
      },
    });

    // Create service for sample application
    const sampleAppService = this.cluster.addManifest('SampleAppService', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        name: 'sample-app-service',
        namespace: 'default',
        annotations: {
          'prometheus.io/scrape': 'true',
          'prometheus.io/port': '8080',
        },
      },
      spec: {
        selector: {
          app: 'sample-app',
        },
        ports: [
          {
            name: 'http',
            port: 80,
            targetPort: 80,
          },
          {
            name: 'metrics',
            port: 8080,
            targetPort: 8080,
          },
        ],
        type: 'ClusterIP',
      },
    });

    sampleAppService.node.addDependency(sampleApp);
  }
}