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
DATABASE_NAME=postgres                         # Keep as 'postgres' to monitor ALL databases
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

# IMPORTANT: If CREATE_MONITORING_USER=false, you MUST provide:
PG_USERNAME=otel_monitor                       # Your monitoring username
PG_PASSWORD=<your-monitoring-password>         # Your monitoring password
```

**If `CREATE_MONITORING_USER=false`**, you must:
1. **Manually create the monitoring user** in PostgreSQL first (see Database Setup section below)
2. **Add `PG_USERNAME` and `PG_PASSWORD`** to your `.env` file

**Save and close the file.**

---

## Step 1.5: Setup Database Monitoring (REQUIRED if CREATE_MONITORING_USER=false)

**⚠️ IMPORTANT: This step is REQUIRED if you have multiple databases on your RDS instance!**

The monitoring setup must be run on **EACH** database you want to monitor. The setup creates monitoring views and functions that are database-specific.

### Option A: Automated Setup (Recommended)

Use the helper script to automatically set up all databases:

```bash
cd scripts
export PGPASSWORD='your-master-password'
./setup-all-databases.sh -h your-rds-endpoint.rds.amazonaws.com -U postgres
```

**What it does:**
- Auto-detects all databases on your RDS instance
- Creates `otel_monitor` user (once)
- Sets up monitoring schema, views, and functions in each database
- Shows progress with colored output

**Example output:**
```
[INFO] Found databases: app_db,analytics_db,postgres
[INFO] Starting setup on 3 database(s)...
[SUCCESS] ✓ Setup completed successfully for database: app_db
[SUCCESS] ✓ Setup completed successfully for database: analytics_db
[SUCCESS] ✓ Setup completed successfully for database: postgres
[SUCCESS] All databases setup successfully!
```

### Option B: Manual Setup

For a single database or specific databases only:

```bash
cd scripts
export PGPASSWORD='your-master-password'
psql -h your-rds-endpoint.rds.amazonaws.com -U postgres -d database_name -f setup-db-user.sql
```

**For multiple databases, repeat for each:**
```bash
psql -h your-rds-endpoint -U postgres -d app_db -f setup-db-user.sql
psql -h your-rds-endpoint -U postgres -d analytics_db -f setup-db-user.sql
psql -h your-rds-endpoint -U postgres -d reporting_db -f setup-db-user.sql
```

### Verify Setup

After running the setup, verify it worked:

```bash
psql -h your-rds-endpoint -U postgres -d your_database -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'otel_monitor';"
```

**Expected output:** Should show `otel_monitor` schema exists.

### Important Note on Multi-Database Monitoring

The OpenTelemetry collector connects to the `postgres` database (specified in `DATABASE_NAME` or `PG_DATABASE`), but it automatically collects instance-wide metrics for **all databases** via PostgreSQL system catalogs (like `pg_stat_database`).

**However**, for query-level monitoring from `pg_stat_statements`, you must run the setup script on each database individually. This is why Step 1.5 is critical if you have multiple databases.

**In summary:**
- ✅ **Instance metrics** (connections, transactions, etc.) - Collected for all databases automatically
- ⚠️ **Query-level metrics** (pg_stat_statements) - Only collected from databases where you ran the setup script

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

### Problem: "Connection refused" or "Connection timeout" in logs

This means the ECS containers cannot reach your RDS instance over the network.

**Cause:** Security group rules not allowing traffic from ECS to RDS

**Fix 1: Verify security group ingress rules were added**

The CloudFormation stack automatically adds ingress rules to ALL your RDS security groups. Check if they were created:

```bash
# Get your RDS security group IDs
RDS_SG_IDS=$(aws rds describe-db-instances \
  --db-instance-identifier <your-rds-instance-id> \
  --query 'DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId' \
  --output text)

# Get collector security group
COLLECTOR_SG=$(aws cloudformation describe-stacks \
  --stack-name rds-postgresql-monitoring-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`CollectorSecurityGroup`].OutputValue' \
  --output text)

# Check each RDS security group has ingress from collector
for sg in $RDS_SG_IDS; do
  echo "Checking $sg..."
  aws ec2 describe-security-groups \
    --group-ids $sg \
    --query "SecurityGroups[0].IpPermissions[?contains(UserIdGroupPairs[].GroupId, '$COLLECTOR_SG')]"
done
```

**Expected:** You should see TCP port 5432 rules allowing traffic from the collector security group.

**Fix 2: If rules are missing, manually add them**

```bash
# Add ingress rule to each RDS security group
for sg in $RDS_SG_IDS; do
  aws ec2 authorize-security-group-ingress \
    --group-id $sg \
    --protocol tcp \
    --port 5432 \
    --source-group $COLLECTOR_SG \
    --description "Allow PostgreSQL from monitoring collectors"
done
```

**Fix 3: Check if RDS is in a private subnet with no NAT**

If your RDS is in a private subnet with no internet access, ensure the ECS tasks are deployed in the same VPC and can reach RDS directly:

```bash
# Verify ECS tasks are in the same VPC as RDS
aws ecs describe-tasks \
  --cluster rds-postgresql-monitoring-prod \
  --tasks $(aws ecs list-tasks --cluster rds-postgresql-monitoring-prod --query 'taskArns[0]' --output text) \
  --query 'tasks[0].attachments[0].details[?name==`subnetId`].value' \
  --output text
```

### Problem: "Lambda layer permission denied" (CREATE_MONITORING_USER=true)

If you get an error like:
```
User is not authorized to perform lambda:GetLayerVersion on resource
```

This means the CloudFormation template references a Lambda layer from a different AWS account that you cannot access.

**Solution: Create your own psycopg2 layer**

```bash
# 1. Create layer directory
mkdir -p psycopg2-layer/python/lib/python3.11/site-packages

# 2. Install psycopg2-binary
pip install psycopg2-binary -t psycopg2-layer/python/lib/python3.11/site-packages

# 3. Create ZIP
cd psycopg2-layer
zip -r ../psycopg2-layer.zip .
cd ..

# 4. Publish to your AWS account
aws lambda publish-layer-version \
  --layer-name psycopg2-py311 \
  --zip-file fileb://psycopg2-layer.zip \
  --compatible-runtimes python3.11 \
  --region ap-south-1

# 5. Note the returned LayerVersionArn (e.g., arn:aws:lambda:ap-south-1:YOUR-ACCOUNT:layer:psycopg2-py311:1)

# 6. Add to your .env
echo "PSYCOPG2_LAYER_ARN=arn:aws:lambda:ap-south-1:YOUR-ACCOUNT:layer:psycopg2-py311:1" >> .env

# 7. Re-deploy
./quick-setup.sh
```

**Recommended alternative**: Set `CREATE_MONITORING_USER=false` and create the database user manually (see below).

### Problem: "Empty environment variable PG_USERNAME/PG_PASSWORD"

This means you set `CREATE_MONITORING_USER=false` but didn't provide credentials.

**Fix:** Create monitoring user manually and add credentials to .env

```bash
# 1. Connect to PostgreSQL
psql -h <your-rds-endpoint> -U postgres -d postgres

# 2. Create monitoring user
CREATE USER otel_monitor WITH PASSWORD 'YourSecurePassword123!';
GRANT pg_monitor TO otel_monitor;
GRANT rds_superuser TO otel_monitor;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON pg_stat_statements TO otel_monitor;
GRANT USAGE ON SCHEMA public TO otel_monitor;
CREATE SCHEMA IF NOT EXISTS otel_monitor;
GRANT USAGE, CREATE ON SCHEMA otel_monitor TO otel_monitor;

# 3. Add to .env file
echo "PG_USERNAME=otel_monitor" >> .env
echo "PG_PASSWORD=YourSecurePassword123!" >> .env

# 4. Re-deploy
./quick-setup.sh
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
