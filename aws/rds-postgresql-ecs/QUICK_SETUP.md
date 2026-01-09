# RDS PostgreSQL Monitoring - Quick Setup

Complete monitoring setup in **4 simple steps** (~10 minutes).

---

## Prerequisites

**Local Tools:**
- AWS CLI configured
- Docker installed

**AWS Resources:**
- RDS PostgreSQL instance running
- AWS IAM user/role with these permissions:
  - `cloudformation:*` (create/update stacks)
  - `iam:CreateRole`, `iam:PutRolePolicy`, `iam:PassRole`
  - `ecs:*` (create clusters, services, tasks)
  - `ecr:*` (create repositories, push images)
  - `ec2:*SecurityGroup*` (modify security groups)
  - `rds:Describe*` (read RDS configuration)
  - `secretsmanager:CreateSecret`, `secretsmanager:PutSecretValue`
  - `logs:CreateLogGroup`, `logs:PutRetentionPolicy`
  - `lambda:CreateFunction` (for optional DB setup)

**Last9:**
- Last9 account ([Get credentials here](https://app.last9.io))

---

## Step 1: Configure Your Environment

Copy the template and add your credentials:

```bash
cd aws/rds-postgresql-ecs
cp .env.example .env
nano .env  # or use any text editor
```

**Fill in these values in `.env`:**

```bash
# Your RDS Details
RDS_INSTANCE_ID=<your-rds-instance-id>        # Find in AWS Console → RDS
DATABASE_NAME=postgres                         # Your database name
MASTER_USERNAME=postgres                       # RDS master username
MASTER_PASSWORD=<your-rds-password>           # RDS master password

# Your Last9 Details
LAST9_OTLP_ENDPOINT=<your-endpoint>           # From Last9 dashboard
LAST9_USERNAME=<your-username>                # From Last9 dashboard
LAST9_PASSWORD=<your-password>                # From Last9 dashboard

# Environment
ENVIRONMENT=prod

# Database user creation (RECOMMENDED: false for production)
CREATE_MONITORING_USER=false
```

**Save and close the file.**

---

## Step 2: Build Docker Images

Run this command:

```bash
./build-and-push-images.sh
```

**Wait for:** "All images built and pushed successfully!" (~5 minutes)

---

## Step 3: Deploy Monitoring

Run this command:

```bash
./quick-setup.sh
```

**What you'll see:**
1. Script checks prerequisites
2. Loads your `.env` configuration
3. Asks "Continue? [y/N]:" → Type `y` and press Enter
4. Deploys CloudFormation stack
5. Waits for deployment (~5 minutes)

**Success message:** "✓ Deployment Complete!"

---

## Step 4: Verify It's Working

**Check logs (wait 2 minutes after deployment):**

```bash
aws logs tail /ecs/rds-postgresql-monitoring-prod --since 2m
```

**You should see:**
```
✓ Connected to PostgreSQL
✓ Exported to OTLP: 154 query metrics
✓ Exported 14/17 CloudWatch metrics
```

**View metrics in Last9:**

1. Login to https://app.last9.io
2. Go to **Explore → Metrics**
3. Search for:
   - `postgresql.backends` → Should show data
   - `rds_cpu_utilization` → Should show data
   - `postgresql_dbm_query_time` → Should show data

**If you see data = SUCCESS!** 🎉

---

## Troubleshooting

### Problem: No metrics in Last9

**Solution 1:** Check if collectors are running

```bash
aws ecs describe-services \
  --cluster rds-postgresql-monitoring-prod \
  --services rds-postgresql-monitoring-prod \
  --query 'services[0].[status,runningCount]'
```

Expected: `["ACTIVE", 1]`

**Solution 2:** Check for errors in logs

```bash
aws logs tail /ecs/rds-postgresql-monitoring-prod --since 10m | grep -i error
```

**Solution 3:** Verify credentials in `.env` are correct

### Problem: "Connection refused" in logs

**Fix:** Check security groups allow ECS to connect to RDS

```bash
# This should show your RDS security groups
aws rds describe-db-instances \
  --db-instance-identifier <your-rds-instance-id> \
  --query 'DBInstances[0].VpcSecurityGroups'
```

### Problem: No query-level metrics

**Fix:** Enable `pg_stat_statements` extension (requires RDS reboot)

```bash
# Get parameter group name
aws rds describe-db-instances \
  --db-instance-identifier <your-rds-instance-id> \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text

# Modify parameter group (replace <param-group-name>)
aws rds modify-db-parameter-group \
  --db-parameter-group-name <param-group-name> \
  --parameters \
    "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"

# Schedule reboot during maintenance window
aws rds reboot-db-instance --db-instance-identifier <your-rds-instance-id>
```

---

## What You're Getting

**57 Total Metrics:**
- 34 PostgreSQL metrics (connections, transactions, tables, indexes)
- 9 Query performance metrics (execution time, I/O, cache hits)
- 14 RDS host metrics (CPU, memory, IOPS, storage)

**Example Queries in Last9:**

```promql
# CPU usage
rds_cpu_utilization

# Active connections
postgresql.backends

# Slowest queries
topk(10, postgresql_dbm_query_time_milliseconds_total)
```

---

## Cleanup (Remove Everything)

```bash
aws cloudformation delete-stack --stack-name rds-postgresql-monitoring-prod
```

Your RDS instance and data remain untouched.

---

## Cost

**~$16/month** for complete monitoring:
- ECS Fargate: ~$12
- CloudWatch Logs: ~$2.50
- Secrets Manager: ~$1.20

---

## Need Help?

**View live logs:**
```bash
aws logs tail /ecs/rds-postgresql-monitoring-prod --follow
```

**Check service status:**
```bash
aws ecs describe-services \
  --cluster rds-postgresql-monitoring-prod \
  --services rds-postgresql-monitoring-prod
```

**Full documentation:** [README.md](README.md)

**Last9 Support:** support@last9.io

---

**That's it! Your monitoring is live.** 🚀
