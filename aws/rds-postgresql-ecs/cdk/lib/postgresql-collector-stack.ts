import * as cdk from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';
import * as path from 'path';

export interface PostgreSQLCollectorStackProps extends cdk.StackProps {
  /**
   * VPC ID where the collector will be deployed
   */
  vpcId: string;

  /**
   * Deployment environment (prod, staging, dev)
   */
  environment: string;

  /**
   * Last9 OTLP endpoint URL
   */
  last9OtlpEndpoint: string;

  /**
   * RDS Instance Identifier to monitor
   */
  rdsInstanceId: string;

  /**
   * ARN of Secrets Manager secret containing DB credentials (optional)
   * If not provided, a new secret will be created
   */
  dbCredentialsSecretArn?: string;
}

export class PostgreSQLCollectorStack extends cdk.Stack {
  public readonly cluster: ecs.Cluster;
  public readonly service: ecs.FargateService;
  public readonly dbCredentialsSecret: secretsmanager.ISecret;
  public readonly last9AuthSecret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props: PostgreSQLCollectorStackProps) {
    super(scope, id, props);

    // ==========================================================================
    // VPC Lookup
    // ==========================================================================
    const vpc = ec2.Vpc.fromLookup(this, 'VPC', {
      vpcId: props.vpcId,
    });

    // ==========================================================================
    // ECS Cluster
    // ==========================================================================
    this.cluster = new ecs.Cluster(this, 'CollectorCluster', {
      vpc,
      clusterName: `postgresql-collector-${props.environment}`,
      containerInsights: true,
    });

    // ==========================================================================
    // Secrets
    // ==========================================================================

    // Last9 Authentication Secret
    this.last9AuthSecret = new secretsmanager.Secret(this, 'Last9AuthSecret', {
      secretName: `postgresql-collector/${props.environment}/last9-auth`,
      description: 'Last9 OTLP authentication header for PostgreSQL collector',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ placeholder: true }),
        generateStringKey: 'auth_header',
      },
    });

    // Database Credentials Secret
    if (props.dbCredentialsSecretArn) {
      this.dbCredentialsSecret = secretsmanager.Secret.fromSecretCompleteArn(
        this,
        'DBCredentials',
        props.dbCredentialsSecretArn
      );
    } else {
      // Create a new secret for DB credentials
      this.dbCredentialsSecret = new secretsmanager.Secret(this, 'DBCredentialsSecret', {
        secretName: `postgresql-collector/${props.environment}/db-credentials`,
        description: 'PostgreSQL monitoring user credentials',
        generateSecretString: {
          secretStringTemplate: JSON.stringify({
            username: 'otel_monitor',
            host: '<RDS_ENDPOINT>',
            port: 5432,
            dbname: '<DATABASE_NAME>',
          }),
          generateStringKey: 'password',
          excludePunctuation: true,
          passwordLength: 32,
        },
      });
    }

    // ==========================================================================
    // S3 Bucket for Config
    // ==========================================================================
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `postgresql-collector-config-${props.environment}-${this.account}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    });

    // ==========================================================================
    // IAM Roles
    // ==========================================================================

    // Task Execution Role
    const executionRole = new iam.Role(this, 'ExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Grant secret access to execution role
    this.last9AuthSecret.grantRead(executionRole);
    this.dbCredentialsSecret.grantRead(executionRole);

    // Task Role with AWS API permissions
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'Role for PostgreSQL collector task',
    });

    // RDS Discovery permissions
    taskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'RDSDiscovery',
        actions: ['rds:DescribeDBInstances', 'rds:ListTagsForResource'],
        resources: ['*'],
      })
    );

    // Performance Insights permissions
    taskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'PerformanceInsights',
        actions: [
          'pi:GetResourceMetrics',
          'pi:GetDimensionKeyDetails',
          'pi:DescribeDimensionKeys',
          'pi:GetResourceMetadata',
        ],
        resources: [`arn:aws:pi:${this.region}:${this.account}:metrics/rds/*`],
      })
    );

    // CloudWatch Metrics permissions
    taskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'CloudWatchMetrics',
        actions: [
          'cloudwatch:GetMetricStatistics',
          'cloudwatch:GetMetricData',
          'cloudwatch:ListMetrics',
        ],
        resources: ['*'],
      })
    );

    // CloudWatch Logs permissions
    taskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'CloudWatchLogs',
        actions: [
          'logs:GetLogEvents',
          'logs:FilterLogEvents',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
        ],
        resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws/rds/*`],
      })
    );

    // S3 Config access
    configBucket.grantRead(taskRole);

    // ==========================================================================
    // CloudWatch Log Group
    // ==========================================================================
    const logGroup = new logs.LogGroup(this, 'CollectorLogs', {
      logGroupName: `/ecs/postgresql-collector/${props.environment}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ==========================================================================
    // Task Definition
    // ==========================================================================
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDef', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole,
      taskRole,
      family: `postgresql-collector-${props.environment}`,
    });

    // Main collector container
    const collectorContainer = taskDefinition.addContainer('otel-collector', {
      image: ecs.ContainerImage.fromRegistry('otel/opentelemetry-collector-contrib:0.91.0'),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'collector',
        logGroup,
      }),
      environment: {
        ENVIRONMENT: props.environment,
        AWS_REGION: this.region,
        LAST9_OTLP_ENDPOINT: props.last9OtlpEndpoint,
        RDS_INSTANCE_ID: props.rdsInstanceId,
        PG_PORT: '5432',
      },
      secrets: {
        LAST9_AUTH_HEADER: ecs.Secret.fromSecretsManager(this.last9AuthSecret, 'auth_header'),
        PG_USERNAME: ecs.Secret.fromSecretsManager(this.dbCredentialsSecret, 'username'),
        PG_PASSWORD: ecs.Secret.fromSecretsManager(this.dbCredentialsSecret, 'password'),
        PG_ENDPOINT: ecs.Secret.fromSecretsManager(this.dbCredentialsSecret, 'host'),
        PG_DATABASE: ecs.Secret.fromSecretsManager(this.dbCredentialsSecret, 'dbname'),
      },
      healthCheck: {
        command: ['CMD-SHELL', 'wget --spider -q http://localhost:13133/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
      essential: true,
    });

    // Port mappings
    collectorContainer.addPortMappings(
      { containerPort: 13133, protocol: ecs.Protocol.TCP }, // Health check
      { containerPort: 8888, protocol: ecs.Protocol.TCP }, // Metrics
      { containerPort: 55679, protocol: ecs.Protocol.TCP } // zPages
    );

    // ==========================================================================
    // Security Group
    // ==========================================================================
    const securityGroup = new ec2.SecurityGroup(this, 'CollectorSG', {
      vpc,
      description: 'Security group for PostgreSQL collector',
      allowAllOutbound: true,
    });

    // Allow inbound for health checks from within VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(13133),
      'Health check from VPC'
    );

    // Allow PostgreSQL access (outbound already allowed)
    // The RDS security group needs to allow inbound from this SG

    // ==========================================================================
    // ECS Service
    // ==========================================================================
    this.service = new ecs.FargateService(this, 'CollectorService', {
      cluster: this.cluster,
      taskDefinition,
      serviceName: `postgresql-collector-${props.environment}`,
      desiredCount: 1,
      assignPublicIp: false,
      securityGroups: [securityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      circuitBreaker: {
        rollback: true,
      },
      enableECSManagedTags: true,
      propagateTags: ecs.PropagatedTagSource.SERVICE,
      minHealthyPercent: 0, // Allow 0 healthy during deployment for single task
      maxHealthyPercent: 100,
    });

    // ==========================================================================
    // Outputs
    // ==========================================================================
    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      description: 'ECS Cluster ARN',
      exportName: `${id}-ClusterArn`,
    });

    new cdk.CfnOutput(this, 'ServiceArn', {
      value: this.service.serviceArn,
      description: 'ECS Service ARN',
      exportName: `${id}-ServiceArn`,
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: this.service.serviceName,
      description: 'ECS Service Name',
      exportName: `${id}-ServiceName`,
    });

    new cdk.CfnOutput(this, 'Last9AuthSecretArn', {
      value: this.last9AuthSecret.secretArn,
      description: 'Last9 Auth Secret ARN - Update this with your auth header',
      exportName: `${id}-Last9AuthSecretArn`,
    });

    new cdk.CfnOutput(this, 'DBCredentialsSecretArn', {
      value: this.dbCredentialsSecret.secretArn,
      description: 'Database Credentials Secret ARN',
      exportName: `${id}-DBCredentialsSecretArn`,
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: securityGroup.securityGroupId,
      description: 'Collector Security Group ID - Add to RDS inbound rules',
      exportName: `${id}-SecurityGroupId`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for collector logs',
      exportName: `${id}-LogGroupName`,
    });
  }
}
