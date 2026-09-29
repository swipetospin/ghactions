## CloudFormation-specific checks

These rules apply to CloudFormation and SAM templates in YAML or JSON. Read
the whole template, not only the diff. Most CloudFormation bugs come from
how a changed resource relates to others, or to the resources that already
exist in the deployed stack.

### Replacement of stateful resources (Blocking)

Some property changes make CloudFormation delete the resource and create a
new one. On a database, table, bucket, file system, queue, or KMS key, this
loses data. Renaming a resource's logical ID has the same effect: the old
resource is deleted and a new one is created.

Flag a changed logical ID on any stateful resource. Also flag a change to a
property that the AWS docs list as "Update requires: Replacement". Common
ones are `DBInstanceIdentifier`, `Engine` (RDS), `KeySchema` and
`TableName` (DynamoDB), `BucketName` (S3), and `QueueName` (SQS).

Assume that the author knows that they are doing and raise this as an
informational reminder.

Bad:
```yaml
Resources:
  OrdersTableV2:            # was OrdersTable; the old table is deleted
    Type: AWS::DynamoDB::Table
```

Good: keep the logical ID. If the table must be replaced, the PR must say
how the data moves to the new table.

### `!Ref` returns the wrong value (Blocking)

`!Ref` returns a different value for each resource type. It is often the
name, ID, or URL, not the ARN. A property that needs an ARN then gets the
wrong value. Check the resource type's "Return values" docs.

Common mistakes:

- `AWS::IAM::Role`: `!Ref` gives the role name. Use `!GetAtt Role.Arn`.
- `AWS::SQS::Queue`: `!Ref` gives the queue URL. Use `!GetAtt Queue.Arn`.
- `AWS::S3::Bucket`: `!Ref` gives the bucket name. Use
  `!GetAtt Bucket.Arn`.
- `AWS::Lambda::Function`: `!Ref` gives the function name. Use
  `!GetAtt Function.Arn` where an ARN is needed.

### Over-broad IAM permissions and using wildcards (Blocking)

Flag wildcards that grant broad permissions; e.g. `Action: "*"`, `Resource: "*"`,
or `s3:*`, when a narrower-scope is appropriate.
Flag `Principal: "*"` in a resource policy that has no `Condition` to limit it.

Bad:
```yaml
- Effect: Allow
  Action: "s3:*"
  Resource: "*"
```

Good:
```yaml
- Effect: Allow
  Action:
    - s3:GetObject
    - s3:PutObject
  Resource: !Sub "${UploadsBucket.Arn}/*"
```

Do not flag `Resource: "*"` on actions that do not support resource-level
permissions, such as `ec2:Describe*` or `xray:PutTraceSegments`.

Scope permissions *at least* to account and region. Best is to scope to a
precise resource ARN or use `!Ref` or `!GetAtt`.

Bad:
```yaml
- Effect: Allow
  Action: sqs:SendMessage
  Resource: "*"
```

Good:
```yaml
- Effect: Allow
  Action: sqs:SendMessage
  Resource: !Sub "arn:aws:sqs:${AWS::Region}:${AWS::AccountId}:*"
```

Best:
```yaml
- Effect: Allow
  Action: sqs:SendMessage
  Resource: !GetAtt OrdersQueue.Arn
```

Also consider using `NotAction` or `NotResource` in a `Deny` statement when
it would simplify an IAM permission. Flag them in an `Allow` statement where
they could unintentially allow new permissions as they are added.

### Open network access (Blocking)

Flag security group ingress from `0.0.0.0/0` or `::/0` on any port other
than 80 or 443, most of all SSH (22), RDP (3389), and database ports.
Also flag a database or cache with `PubliclyAccessible: true`.

Bad:
```yaml
SecurityGroupIngress:
  - IpProtocol: tcp
    FromPort: 22
    ToPort: 22
    CidrIp: 0.0.0.0/0
```

Good:
```yaml
SecurityGroupIngress:
  - IpProtocol: tcp
    FromPort: 22
    ToPort: 22
    SourceSecurityGroupId: !Ref BastionSecurityGroup
```

### Hardcoded account or region (Minor)

Hardcoded account IDs, regions, and `arn:aws:` prefixes break the template
in other accounts and regions. Use `AWS::AccountId` and `AWS::Region`.
`AWS::Partition` is excempt from this rule.

Do not flag a hardcoded value that points to a resource that exists in only
one account or region, such as a shared central logging bucket.

Bad:
```yaml
Resource: "arn:aws:sns:us-east-1:123456789012:alerts"
```

Good:
```yaml
Resource: !Sub "arn:aws:sns:${AWS::Region}:${AWS::AccountId}:alerts"
```

### Static physical names (Minor)

Naming resources with static names (such as `BucketName`, `TableName`, `RoleName`, etc.) blocks any update that needs replacement. It also stops the template from deploying
twice in one account. Flag a new hardcoded name unless other systems must
find the resource by that exact name.

### Hardcoded public AMI IDs (Minor)

Public AMI IDs differ by region and go out of date. Get the latest AMI from an
SSM public parameter.

Bad:
```yaml
ImageId: ami-0abcdef1234567890
```

Good:
```yaml
Parameters:
  LatestAmiId:
    Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
    Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
```

### Log groups with no retention (Minor)

An `AWS::Logs::LogGroup` with no `RetentionInDays` keeps logs forever, and
the cost grows. Lambda functions with no log group in the template get one
with no retention. Flag this on new log groups and new functions.

### Prefer shorthand syntax and concise phrasing

Prefer the shorthand syntax (e.g. `Fn::Sub` -> `!Sub`) unless limited by a nested function.
Also, prefer concise forms over multi-line forms except when doing long substitutions.

Bad:
```yaml
Role:
  Fn::GetAtt:
    - LambdaExecutionRole
    - Arn
QueueUrl:
  Fn::Join:
    - ""
    - - "https://sqs."
      - Ref: AWS::Region
      - ".amazonaws.com/"
      - Ref: AWS::AccountId
      - "/orders"
```

Good:
```yaml
Role: !GetAtt LambdaExecutionRole.Arn
QueueUrl: !Sub "https://sqs.${AWS::Region}.amazonaws.com/${AWS::AccountId}/orders"
```

A long substitution may use the multi-line form when it is easier to read:
```yaml
DashboardBody: !Sub
  - '{"widgets": [{"properties": {"metrics": [["AWS/Lambda", "Errors", "FunctionName", "${Fn}"]], "region": "${AWS::Region}"}}]}'
  - Fn: !Ref OrdersFunction
```

### Limit the use of parameters

Parameters are to be used when the user or deployer is expected to supply input.
Parameters are not stand-ins for variables or constants. Consider Mappings to define
well-understood constants such as VPC and Subnet IDs, account IDs, or similar.

Bad:
```yaml
Parameters:
  VpcId:
    Type: AWS::EC2::VPC::Id
    Default: vpc-0a1b2c3d4e5f67890
  PrivateSubnetId:
    Type: AWS::EC2::Subnet::Id
    Default: subnet-0123456789abcdef0
```

Good:
```yaml
Parameters:
  Environment:
    Type: String
    AllowedValues: [dev, prod]

Mappings:
  EnvironmentConfig:
    dev:
      VpcId: vpc-0a1b2c3d4e5f67890
      PrivateSubnetId: subnet-0123456789abcdef0
    prod:
      VpcId: vpc-0fedcba9876543210
      PrivateSubnetId: subnet-0fedcba9876543210
```

### Properties set to their default value (Minor)

Leave out a property whose value equals the default in the AWS docs for
that resource type. An explicit default adds noise and hides the settings
that matter. Only flag it when you are sure of the default. Do not flag it
when a comment explains why the value is set on purpose.
