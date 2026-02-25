# TP12: KMS et Secrets Manager chiffrement et secrets au runtime, GuardDuty

resource "aws_kms_key" "main" {
  description             = "ESGI project encryption key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Decrypt"
        Effect = "Allow"
        Principal = {
          AWS = [
            aws_iam_role.lambda_api.arn,
            aws_iam_role.lambda_consumer.arn,
            aws_iam_role.lambda_s3_processor.arn
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "esgi-kms-key"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/esgi-key"
  target_key_id = aws_kms_key.main.key_id
}

resource "aws_secretsmanager_secret" "app_config" {
  name                    = "esgi-app-config"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "esgi-app-config"
  })
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    api_key     = "esgi-demo-api-key-${random_id.bucket_suffix.hex}"
    environment = local.environment
    project     = local.project
  })
}

resource "aws_iam_policy" "secrets_access" {
  name = "esgi-secrets-access-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.app_config.arn,
          aws_secretsmanager_secret.db_credentials.arn
        ]
      },
      {
        Sid    = "DecryptWithKMS"
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
      }
    ]
  })
}

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "esgi-guardduty"
  })
}
