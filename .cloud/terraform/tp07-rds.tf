# TP7: Données RDS privé, SG restrictif, snapshot et restauration

resource "aws_db_subnet_group" "main" {
  name       = "esgi-db-subnet-group"
  subnet_ids = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]

  tags = merge(local.common_tags, {
    Name = "esgi-db-subnet-group"
  })
}

resource "aws_db_instance" "postgres" {
  identifier = "esgi-rds"

  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "esgidb"
  username = "esgi_admin"
  password = random_password.db_password.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [data.aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot      = true
  delete_automated_backups = true
  deletion_protection      = false
  apply_immediately        = true

  tags = merge(local.common_tags, {
    Name = "esgi-rds"
  })
}

resource "random_password" "db_password" {
  length  = 16
  special = false
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "esgi-db-credentials"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "esgi-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = aws_db_instance.postgres.username
    password = random_password.db_password.result
    host     = aws_db_instance.postgres.address
    port     = aws_db_instance.postgres.port
    dbname   = aws_db_instance.postgres.db_name
  })
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "RDS endpoint"
}
