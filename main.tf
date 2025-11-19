terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

# Optional: fetch current account id if not provided
data "aws_caller_identity" "current" {}

locals {
  account_id = var.account_id != "" ? var.account_id : data.aws_caller_identity.current.account_id
}

# IAM role for Lambda
resource "aws_iam_role" "lambda_backup_role" {
  name = "lambda-backup-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Inline policy granting limited permissions for snapshots and logs
resource "aws_iam_role_policy" "lambda_backup_policy" {
  name = "lambda-backup-policy-${random_id.suffix.hex}"
  role = aws_iam_role.lambda_backup_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "RDSBackupPermissions",
        Effect = "Allow",
        Action = [
          "rds:CreateDBSnapshot",
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource"
        ],
        Resource = "*"
      },
      {
        Sid = "EC2SnapshotPermissions",
        Effect = "Allow",
        Action = [
          "ec2:CreateSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:CreateTags",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags"
        ],
        Resource = "*"
      },
      {
        Sid = "Logs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Minimal AWS-managed policy attachment for CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# small random suffix to avoid name collisions
resource "random_id" "suffix" {
  byte_length = 2
}

# Package the lambda code (uses local file lambda_function.py)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# S3 bucket to store lambda zip is not necessary if using local archive_file; Terraform will upload it
resource "aws_lambda_function" "backup_lambda" {
  function_name = var.lambda_function_name
  filename      = data.archive_file.lambda_zip.output_path
  source_code_hash = filebase64sha256(data.archive_file.lambda_zip.output_path)
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_backup_role.arn
  timeout       = 300
  environment {
    variables = {
      RDS_INSTANCE_IDS = var.rds_instance_identifier
      EC2_INSTANCE_IDS = var.ec2_instance_id
      TAG_KEY           = var.snapshot_tag_key
      TAG_VALUE         = var.snapshot_tag_value
    }
  }
}

# Permission so EventBridge can invoke Lambda
resource "aws_lambda_permission" "allow_events" {
  statement_id  = "AllowExecutionFromEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backup_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_schedule.arn
}

# EventBridge rule (schedule)
resource "aws_cloudwatch_event_rule" "backup_schedule" {
  name                = "daily-backup-rule-${random_id.suffix.hex}"
  schedule_expression = var.backup_schedule_cron
}

resource "aws_cloudwatch_event_target" "backup_target" {
  rule = aws_cloudwatch_event_rule.backup_schedule.name
  arn  = aws_lambda_function.backup_lambda.arn
}

# SNS Topic for alarm notifications
resource "aws_sns_topic" "alerts_topic" {
  name = "infra-alerts-topic-${random_id.suffix.hex}"
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "ec2_high_cpu" {
  alarm_name          = "EC2-High-CPU-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  dimensions = {
    InstanceId = var.ec2_instance_id
  }
  alarm_actions = [aws_sns_topic.alerts_topic.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "RDS-Low-FreeStorage-${random_id.suffix.hex}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1073741824
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }
  alarm_actions = [aws_sns_topic.alerts_topic.arn]
}

# CloudWatch Dashboard (simple)
resource "aws_cloudwatch_dashboard" "infra_dashboard" {
  dashboard_name = "infra-monitor-dashboard-${random_id.suffix.hex}"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric",
        x = 0,
        y = 0,
        width = 12,
        height = 6,
        properties = {
          metrics = [["AWS/EC2","CPUUtilization","InstanceId", var.ec2_instance_id]],
          period = 300,
          stat = "Average",
          title = "EC2 CPU"
        }
      },
      {
        type = "metric",
        x = 12,
        y = 0,
        width = 12,
        height = 6,
        properties = {
          metrics = [["AWS/RDS","FreeStorageSpace","DBInstanceIdentifier", var.rds_instance_identifier]],
          period = 300,
          stat = "Average",
          title = "RDS FreeStorageSpace"
        }
      }
    ]
  })
}
