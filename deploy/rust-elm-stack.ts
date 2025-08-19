import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

export class RustElmStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC
    const vpc = new ec2.Vpc(this, 'RustElmVpc', {
      maxAzs: 2,
      natGateways: 0, // Use public subnets only for simplicity
    });

    // Security group for EC2
    const securityGroup = new ec2.SecurityGroup(this, 'RustElmSecurityGroup', {
      vpc,
      description: 'Security group for Rust Elm application',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(3000),
      'Allow HTTP traffic on port 3000'
    );

    // Allow SSH for deployment
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    // S3 bucket for deployment artifacts
    const deploymentBucket = new s3.Bucket(this, 'RustElmDeploymentBucket', {
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // IAM role for EC2 instance
    const role = new iam.Role(this, 'RustElmInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Grant EC2 access to the deployment bucket
    deploymentBucket.grantRead(role);

    // User data script to set up the instance
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      // Install system dependencies
      'yum update -y',
      'yum install -y awscli',
      
      // Create app directory
      'mkdir -p /home/ec2-user/app',
      'chown ec2-user:ec2-user /home/ec2-user/app',
      
      // Create deployment script
      `cat > /home/ec2-user/deploy.sh << 'EOF'`,
      '#!/bin/bash',
      'set -e',
      '',
      `# Download latest deployment from S3`,
      `aws s3 cp s3://${deploymentBucket.bucketName}/rust-elm /home/ec2-user/app/rust-elm`,
      `aws s3 sync s3://${deploymentBucket.bucketName}/assets/ /home/ec2-user/app/assets/`,
      '',
      '# Make binary executable',
      'chmod +x /home/ec2-user/app/rust-elm',
      '',
      '# Restart service if running',
      'if systemctl is-active --quiet rust-elm; then',
      '  sudo systemctl restart rust-elm',
      'fi',
      'EOF',
      '',
      'chmod +x /home/ec2-user/deploy.sh',
      'chown ec2-user:ec2-user /home/ec2-user/deploy.sh',
      
      // Create systemd service
      'cat > /etc/systemd/system/rust-elm.service << EOF',
      '[Unit]',
      'Description=Rust Elm WebSocket Server',
      'After=network.target',
      '',
      '[Service]',
      'Type=simple',
      'User=ec2-user',
      'WorkingDirectory=/home/ec2-user/app',
      'ExecStart=/home/ec2-user/app/rust-elm',
      'Restart=always',
      'RestartSec=10',
      '',
      '[Install]',
      'WantedBy=multi-user.target',
      'EOF',
      
      // Enable the service
      'systemctl daemon-reload',
      'systemctl enable rust-elm'
    );

    // Create EC2 instance
    const instance = new ec2.Instance(this, 'RustElmInstance', {
      vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      securityGroup,
      role,
      userData,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    // Outputs
    new cdk.CfnOutput(this, 'InstanceId', {
      value: instance.instanceId,
      description: 'EC2 Instance ID',
    });

    new cdk.CfnOutput(this, 'PublicIp', {
      value: instance.instancePublicIp,
      description: 'Public IP address',
    });

    new cdk.CfnOutput(this, 'ApplicationUrl', {
      value: `http://${instance.instancePublicIp}:3000`,
      description: 'Application URL',
    });

    new cdk.CfnOutput(this, 'DeploymentBucket', {
      value: deploymentBucket.bucketName,
      description: 'S3 bucket for deployment artifacts',
    });
  }
}