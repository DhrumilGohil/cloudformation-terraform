resource "aws_lambda_function" "TagInstanceFunction" {
  function_name = "TagInstanceFunction"
  handler       = "index.lambda_handler"
  runtime       = "python3.8"
  timeout       = 60
  role          = aws_iam_role.TagInstanceFunctionRole.arn
  filename      = "code.zip"

  source_code_hash = data.archive_file.lambda.output_base64sha256
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "index.py"
  output_path = "code.zip"
}

resource "aws_iam_role" "TagInstanceFunctionRole" {
  name               = "TagInstanceFunctionRole"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com"]
      }
      Action    = ["sts:AssumeRole"]
    }]
  })

  inline_policy {
    name = "root"
    policy = jsonencode({
      Version   = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["*"]
        Resource = ["*"]
      }]
    })
  }
}

resource "aws_cloudwatch_event_rule" "EventRule0" {
  name        = "rds-new"
  event_bus_name = "default"
  event_pattern = jsonencode({
    source      = ["aws.rds"],
    detail-type = ["AWS API Call via CloudTrail"],
    detail = {
      eventSource = ["rds.amazonaws.com"],
      eventName   = ["CreateDBInstance"]
    }
  })
}

resource "aws_cloudwatch_event_rule" "TagInstanceRule" {
  name        = "InstanceLaunchRule2"
  description = "Tag newly launched instances"
  event_pattern = jsonencode({
    source      = ["aws.ec2"],
    detail-type = ["AWS API Call via CloudTrail"],
    detail = {
      eventSource = ["ec2.amazonaws.com"],
      eventName   = ["RunInstances"]
    }
  })
}

resource "aws_cloudwatch_event_target" "rds_lambda" {
  rule      = aws_cloudwatch_event_rule.EventRule0.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.TagInstanceFunction.arn
}

resource "aws_cloudwatch_event_target" "ec2_lambda" {
  rule      = aws_cloudwatch_event_rule.TagInstanceRule.name
  target_id = "SendToLambda"
  arn       = aws_lambda_function.TagInstanceFunction.arn
}

resource "aws_lambda_permission" "TagInstancePermission" {
  statement_id  = "AllowExecutionFromCloudWatchEc2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.TagInstanceFunction.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.TagInstanceRule.arn
}

resource "aws_lambda_permission" "TagDBInstancePermission" {
  statement_id  = "AllowExecutionFromCloudWatchDB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.TagInstanceFunction.arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.EventRule0.arn
}

resource "aws_iam_group" "ManageEC2InstancesGroup" {
  name = "ManageEC2InstancesGroup"
}

resource "aws_iam_policy" "TagBasedEC2RestrictionsPolicy" {
  name   = "TagBasedEC2RestrictionsPolicy"
  path   = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LaunchEC2Instances"
      Effect = "Allow"
      Action = [
        "ec2:Describe*",
        "ec2:RunInstances"
      ]
      Resource = ["*"]
    }, {
      Sid    = "AllowActionsIfYouAreTheOwner"
      Effect = "Allow"
      Action = [
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:RebootInstances",
        "ec2:TerminateInstances"
      ]
      Resource = ["*"]
      Condition = {
        StringEquals = {
          "ec2:ResourceTag/PrincipalId" = data.aws_caller_identity.current.user_id
        }
      }
    }]
  })
}

resource "aws_iam_group_policy_attachment" "attach_s3_read_policy" {
  group = aws_iam_group.ManageEC2InstancesGroup.name
  policy_arn = aws_iam_policy.TagBasedEC2RestrictionsPolicy.arn
}

resource "aws_cloudtrail" "cdi_splunk_cloudtrail" {
  name                          = "Autotagging"
  s3_bucket_name                = aws_s3_bucket.S3BucketForCloudTrailCloudTrail.id
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = false
}

resource "aws_s3_bucket" "S3BucketForCloudTrailCloudTrail" {
  bucket = "s3-bucket-cloudtrail-${data.aws_caller_identity.current.account_id}"
}


data "aws_iam_policy_document" "S3BucketPolicy" {
  statement {
    sid       = "AWSCloudTrailBucketPermissionsCheck"
    effect    = "Allow"
    principals {
      type = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = ["${aws_s3_bucket.S3BucketForCloudTrailCloudTrail.arn}"]
  }

  statement {
    sid       = "AWSConfigBucketDelivery"
    effect    = "Allow"
    principals {
      type = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.S3BucketForCloudTrailCloudTrail.arn}/*"]
  }
}


resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.S3BucketForCloudTrailCloudTrail.id
  policy = data.aws_iam_policy_document.S3BucketPolicy.json
}

data "aws_caller_identity" "current" {}