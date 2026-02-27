# Runbook PRA — Infrastructure ESGI AWS
**Projet** : esgi-aws | **Env** : training | **Région** : eu-west-3
**Owner** : nony_faugeras | **Dernière révision** : 2026-02-27

---

## 1. Objectifs RTO / RPO

| Composant | Service AWS | RTO | RPO | Justification |
|---|---|---|---|---|
| Load Balancer | ALB `esgi-alb` | < 1 min | N/A | Multi-AZ natif, health checks automatiques |
| Compute | ASG `esgi-asg` | < 5 min | N/A | Stateless, remplacement automatique |
| Conteneurs | ECS Fargate `esgi-cluster` | < 3 min | N/A | Stateless, scheduler ECS relance les tasks |
| API serverless | Lambda `esgi-lambda-api` | < 1 min | N/A | AWS gère la disponibilité |
| Messages | SQS `esgi-queue` + DLQ | < 1 min | 0 | DLQ conserve les messages en échec |
| Base de données | RDS `esgi-rds` (PostgreSQL 15) | < 20 min | < 5 min | Backups automatiques + PITR (fenêtre 03h-04h) |
| Stockage objets | S3 `esgi-bucket-*` | < 1 min | 0 | Versioning activé, HA natif AWS |
| Base NoSQL | DynamoDB `esgi-orders` | < 1 min | 0 | Multi-AZ natif, Streams activés |
| Secrets | Secrets Manager `esgi-*` | < 2 min | N/A | Répliqué par AWS |
| Réseau | VPC + CF Stack `esgi-cf-network` | < 30 min | N/A | Terraform/CloudFormation idempotent |

**RTO global** : **30 minutes**
**RPO global** : **5 minutes** (limité par la fenêtre de backup RDS)

---

## 2. Contacts et escalade

| Rôle | Contact | Délai de réponse |
|---|---|---|
| On-call infra | nony_faugeras | 15 min |
| Alertes automatiques | SNS `esgi-alerts` → alerts@example.com | Immédiat |
| Dashboard de supervision | CloudWatch `esgi-dashboard` | Continu |

---

## 3. Détection de l'incident

Les alarmes CloudWatch déclenchent automatiquement une notification SNS :

```bash
# Vérifier l'état des alarmes actives
aws cloudwatch describe-alarms \
  --state-value ALARM \
  --query "MetricAlarms[*].{Alarm:AlarmName,Raison:StateReason}" \
  --output table --region eu-west-3 --profile toplu

# Consulter le dashboard de supervision
aws cloudwatch get-dashboard \
  --dashboard-name esgi-dashboard \
  --region eu-west-3 --profile toplu
```

**Alarmes définies** :
- `esgi-alb-5xx-errors` → erreurs 5xx ALB > 10 sur 10 min
- `esgi-lambda-errors` → erreurs Lambda > 5 sur 10 min
- `esgi-dlq-not-empty` → messages en DLQ > 0

---

## 4. Scénarios d'incident et procédures de reprise

### 4.1 Panne instance EC2 (ASG)

**Symptômes** : alarme ALB 5xx, cible unhealthy dans le target group
**Cause probable** : instance défaillante, OOM, crash applicatif

**Étapes de reprise** :

```bash
# 1. Identifier les instances en échec
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names esgi-asg \
  --query "AutoScalingGroups[0].Instances[*].{Id:InstanceId,State:LifecycleState,Health:HealthStatus}" \
  --output table --region eu-west-3 --profile toplu

# 2. Forcer le remplacement de l'instance défaillante
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id i-XXXXXXXXXXXXXXXXX \
  --should-decrement-desired-capacity false \
  --region eu-west-3 --profile toplu

# 3. Suivre le remplacement
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name esgi-asg \
  --max-items 5 \
  --region eu-west-3 --profile toplu
```

**Validation** : voir section 5.1

---

### 4.2 Erreur Lambda (panne logique)

**Symptômes** : alarme `esgi-lambda-errors`, messages dans DLQ
**Cause probable** : variable d'env manquante, secret inaccessible, bug de code

```bash
# 1. Consulter les logs d'erreur
aws logs filter-log-events \
  --log-group-name /aws/lambda/esgi-lambda-api \
  --filter-pattern "ERROR" \
  --start-time $(date -v-1H +%s000) \
  --region eu-west-3 --profile toplu

# 2. Vérifier la configuration de la fonction
aws lambda get-function-configuration \
  --function-name esgi-lambda-api \
  --region eu-west-3 --profile toplu

# 3. Consulter les messages en DLQ
aws sqs get-queue-attributes \
  --queue-url $(aws sqs get-queue-url --queue-name esgi-dlq --query QueueUrl --output text --region eu-west-3 --profile toplu) \
  --attribute-names ApproximateNumberOfMessages \
  --region eu-west-3 --profile toplu

# 4. Redéployer la version précédente via Terraform
terraform apply -target=aws_lambda_function.api_handler \
  -var="..." --auto-approve
```

**Reprise des messages DLQ** (une fois le bug corrigé) :
```bash
# Relire les messages depuis la DLQ vers la queue principale
aws sqs receive-message \
  --queue-url <DLQ_URL> \
  --max-number-of-messages 10 \
  --region eu-west-3 --profile toplu
```

---

### 4.3 Panne base de données RDS

**Symptômes** : connexions refusées, timeout applicatif, alarme RDS CPU
**Cause probable** : instance arrêtée, storage saturé, credentials expirés

**Reprise depuis snapshot automatique** :

```bash
# 1. Lister les snapshots disponibles (rétention 7 jours)
aws rds describe-db-snapshots \
  --db-instance-identifier esgi-rds \
  --snapshot-type automated \
  --query "DBSnapshots[*].{Id:DBSnapshotIdentifier,Date:SnapshotCreateTime,Status:Status}" \
  --output table --region eu-west-3 --profile toplu

# 2. Restaurer depuis le snapshot le plus récent
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier esgi-rds-restored \
  --db-snapshot-identifier <SNAPSHOT_ID> \
  --db-instance-class db.t4g.micro \
  --db-subnet-group-name esgi-db-subnet-group \
  --vpc-security-group-ids <SG_ID> \
  --no-publicly-accessible \
  --region eu-west-3 --profile toplu

# 3. Attendre la disponibilité
aws rds wait db-instance-available \
  --db-instance-identifier esgi-rds-restored \
  --region eu-west-3 --profile toplu

# 4. Récupérer le nouvel endpoint
aws rds describe-db-instances \
  --db-instance-identifier esgi-rds-restored \
  --query "DBInstances[0].Endpoint.Address" \
  --output text --region eu-west-3 --profile toplu

# 5. Mettre à jour le secret dans Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id esgi-db-credentials \
  --secret-string '{"host":"<NOUVEL_ENDPOINT>","port":5432,"dbname":"esgidb","username":"esgi_admin","password":"<PWD>"}' \
  --region eu-west-3 --profile toplu
```

**Reprise PITR** (Point-In-Time Recovery — précision à 5 min) :
```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier esgi-rds \
  --target-db-instance-identifier esgi-rds-pitr \
  --restore-time 2026-02-27T03:30:00Z \
  --db-instance-class db.t4g.micro \
  --region eu-west-3 --profile toplu
```

---

### 4.4 Perte de données S3

**Symptômes** : objet absent, version corrompue
**Cause probable** : suppression accidentelle, écrasement

```bash
# 1. Lister les versions d'un objet supprimé
aws s3api list-object-versions \
  --bucket <BUCKET_NAME> \
  --prefix "input/mon-fichier.csv" \
  --region eu-west-3 --profile toplu

# 2. Restaurer une version précédente (copier vers la clé courante)
aws s3api copy-object \
  --bucket <BUCKET_NAME> \
  --copy-source "<BUCKET_NAME>/input/mon-fichier.csv?versionId=<VERSION_ID>" \
  --key "input/mon-fichier.csv" \
  --region eu-west-3 --profile toplu

# 3. Supprimer un delete marker pour restaurer un objet effacé
aws s3api delete-object \
  --bucket <BUCKET_NAME> \
  --key "input/mon-fichier.csv" \
  --version-id <DELETE_MARKER_ID> \
  --region eu-west-3 --profile toplu
```

---

### 4.5 Perte de la stack réseau (CloudFormation)

**Symptômes** : VPC introuvable, subnets manquants
**Cause probable** : suppression accidentelle de stack

```bash
# Redéployer le socle réseau depuis Terraform (idempotent)
cd .cloud/terraform
terraform apply -target=aws_cloudformation_stack.network --auto-approve

# Vérifier les outputs
terraform output cf_network_vpc_id
terraform output cf_network_public_subnet_1_id
```

---

## 5. Validation post-reprise

### 5.1 ALB / ASG

```bash
# Vérifier la santé des cibles ALB
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names esgi-tg --query "TargetGroups[0].TargetGroupArn" \
    --output text --region eu-west-3 --profile toplu) \
  --query "TargetHealthDescriptions[*].{Id:Target.Id,State:TargetHealth.State}" \
  --output table --region eu-west-3 --profile toplu
# → Attendu : tous les targets en "healthy"

# Test HTTP bout en bout
curl -o /dev/null -s -w "%{http_code}" http://<ALB_DNS>/
# → Attendu : 200
```

### 5.2 Lambda + SQS

```bash
# Invoquer la Lambda manuellement
aws lambda invoke \
  --function-name esgi-lambda-api \
  --payload '{"test": true}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-test.json \
  --region eu-west-3 --profile toplu
cat /tmp/lambda-test.json
# → Attendu : {"statusCode": 200, ...}

# Vérifier que la DLQ est vide
aws sqs get-queue-attributes \
  --queue-url <DLQ_URL> \
  --attribute-names ApproximateNumberOfMessages \
  --output text --region eu-west-3 --profile toplu
# → Attendu : 0
```

### 5.3 RDS

```bash
# Vérifier que l'instance est available
aws rds describe-db-instances \
  --db-instance-identifier esgi-rds \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text --region eu-west-3 --profile toplu
# → Attendu : available

# Tester la connexion (depuis un bastion ou une Lambda dans le VPC)
psql -h <RDS_ENDPOINT> -U esgi_admin -d esgidb -c "SELECT 1;"
# → Attendu : 1 row
```

### 5.4 S3

```bash
# Vérifier l'accessibilité du bucket
aws s3 ls s3://<BUCKET_NAME>/input/ \
  --region eu-west-3 --profile toplu
# → Attendu : liste des objets sans erreur

# Tester l'upload
aws s3 cp /tmp/test.txt s3://<BUCKET_NAME>/input/test-pra.txt \
  --region eu-west-3 --profile toplu
```

### 5.5 Alarmes CloudWatch

```bash
# Vérifier qu'aucune alarme n'est encore en état ALARM
aws cloudwatch describe-alarms \
  --alarm-name-prefix esgi- \
  --state-value ALARM \
  --query "MetricAlarms[*].AlarmName" \
  --output text --region eu-west-3 --profile toplu
# → Attendu : aucune alarme active
```

---

## 6. Checklist de clôture d'incident

```
[ ] Toutes les alarmes CloudWatch repassées en OK
[ ] Health checks ALB : 100% healthy
[ ] Lambda : 0 erreur sur les 15 dernières minutes
[ ] DLQ : 0 message
[ ] RDS : statut "available", connexion testée
[ ] S3 : versioning actif, lecture/écriture OK
[ ] DynamoDB : table active, streams actifs
[ ] Secrets Manager : secrets accessibles depuis les Lambdas
[ ] Dashboard esgi-dashboard : toutes les métriques nominales
[ ] Post-mortem rédigé (cause, timeline, actions correctives)
```

---

## 7. Commandes de supervision rapide (war room)

```bash
# Vue globale de l'état des ressources en une commande
aws cloudwatch describe-alarms \
  --alarm-name-prefix esgi- \
  --query "MetricAlarms[*].{Nom:AlarmName,Etat:StateValue}" \
  --output table --region eu-west-3 --profile toplu

# Dernières activités ASG
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name esgi-asg --max-items 3 \
  --query "Activities[*].{Date:StartTime,Status:StatusCode,Desc:Description}" \
  --output table --region eu-west-3 --profile toplu

# Erreurs Lambda des 30 dernières minutes
aws logs filter-log-events \
  --log-group-name /aws/lambda/esgi-lambda-api \
  --filter-pattern "ERROR" \
  --start-time $(python3 -c "import time; print(int((time.time()-1800)*1000))") \
  --region eu-west-3 --profile toplu
```
