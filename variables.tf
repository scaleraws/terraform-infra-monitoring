variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "account_id" {
  description = "AWS Account ID (optional, used for ARNs). If empty, Terraform will fill using data source"
  type        = string
  default     = ""
}

variable "ec2_instance_id" {
  description = "EC2 Instance ID to monitor (e.g. i-0abc1234)"
  type        = string
  default     = ""
}

variable "rds_instance_identifier" {
  description = "RDS DB Instance identifier to snapshot/monitor (e.g. mydb1)"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Name for the Lambda function"
  type        = string
  default     = "infra-backup-lambda"
}

variable "backup_schedule_cron" {
  description = "Cron expression for scheduling backups (EventBridge). Example: 0 2 * * ? * => 02:00 UTC daily"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "snapshot_tag_key" { default = "CreatedBy" }
variable "snapshot_tag_value" { default = "terraform-backup" }
