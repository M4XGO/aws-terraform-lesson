# AWS Terraform Training - TPs 4-15

Infrastructure AWS deployee en Terraform pour le module Cloud Computing AWS ESGI.

## Prerequisites

- VPC existant: `vpc-040089e30f22f2bd5`
- Subnets prives: `esgi-sn`, `esgi-sn-2`
- Subnets publics: `esgi-sn-pub-1`, `esgi-sn-pub-2`
- Security Groups: `esgi-web-sg`, `esgi-app-sg`, `esgi-db-sg`

## Convention de nommage

Toutes les ressources utilisent le prefixe `esgi-*`.

## Tags obligatoires

```hcl
Project    = "esgi-aws-training"
Owner      = "toplu"
Env        = "dev"
CostCenter = "esgi-m1"
```

## TPs Implementes

### TP4: EC2 privee avec SSM
- Instance t4g.nano en subnet prive, IMDSv2 force
- Role IAM SSM + CloudWatch, EBS 10GB monte sur /data

### TP5: ALB + ASG
- Launch Template, ALB public, ASG (1-2 instances) en prive

### TP6: S3 securise
- Versioning, chiffrement AES256, blocage public, policy TLS, lifecycle

### TP7: RDS PostgreSQL
- db.t4g.micro prive, chiffre, backup 7j, credentials dans Secrets Manager

### TP8: DynamoDB
- Table PAY_PER_REQUEST avec GSI, TTL, Streams

### TP9: Lambda S3 trigger
- Validation fichiers input/, sortie output/, role minimal

### TP10: API Gateway + SQS
- POST /items -> Lambda -> SQS -> Lambda consumer -> DynamoDB, DLQ

### TP11: Observabilite
- Flow Logs, Dashboard CloudWatch, Alarmes (5xx, erreurs, DLQ)

### TP12: KMS + Secrets Manager
- Cle KMS avec rotation, secrets chiffres, GuardDuty

### TP14: ECS Fargate
- ECR, cluster ECS, service nginx:alpine expose via ALB /ecs/*

### TP15: FinOps
- Budget mensuel 50 USD, budget journalier 5 USD, alertes

## Deploiement

```bash
cd .cloud/terraform
terraform init
terraform plan
terraform apply
```

## Teardown

```bash
terraform destroy
```
