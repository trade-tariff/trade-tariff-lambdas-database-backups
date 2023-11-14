# trade-tariff-lambdas-database-backups

Scheduled go lambda function to backup the database to S3. This is used by
developers and various stakeholders to get access to current snapshots of
development, staging and production environments.

```mermaid
sequenceDiagram
  participant Scheduler as Scheduler
  participant Lambda as Lambda
  participant RDS as RDS
  participant S3 as AWS S3 Bucket

  Scheduler->>Lambda: Trigger at 1200 UTC
  Lambda->>RDS: Describe snapshots
  Lambda->>Lambda: Get latest snapshot
  Lambda->>RDS: Start export to S3
  RDS->>S3: Export backup to S3 bucket
  Lambda->>S3: Rotate backups in S3
```
