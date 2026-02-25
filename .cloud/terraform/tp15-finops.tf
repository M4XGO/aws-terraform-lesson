# TP15: FinOps et résilience budgets, tags, test de continuité et runbook PRA

resource "aws_budgets_budget" "monthly" {
  name         = "esgi-monthly-budget"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["Project$${local.project}"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["alerts@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["alerts@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["alerts@example.com"]
  }

  tags = local.common_tags
}

resource "aws_budgets_budget" "daily" {
  name         = "esgi-daily-budget"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "DAILY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["alerts@example.com"]
  }

  tags = local.common_tags
}

output "alb_dns_name" {
  value       = aws_lb.alb.dns_name
  description = "ALB DNS name for testing"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.main.id
  description = "S3 bucket name"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.orders.name
  description = "DynamoDB table name"
}

output "sqs_queue_url" {
  value       = aws_sqs_queue.main.url
  description = "SQS queue URL"
}

output "dlq_url" {
  value       = aws_sqs_queue.dlq.url
  description = "DLQ URL"
}
