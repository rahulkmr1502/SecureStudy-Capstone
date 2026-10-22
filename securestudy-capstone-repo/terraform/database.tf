############################################
# PostgreSQL in the isolated data tier. Credentials are generated and rotated by
# RDS in Secrets Manager (manage_master_user_password), so no password exists in
# code, state or variables.
############################################

resource "aws_db_subnet_group" "main" {
  name       = "securestudy-db"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_db_parameter_group" "main" {
  name   = "securestudy-pg"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_statement"
    value = "ddl"
  }
}

resource "aws_db_instance" "main" {
  # checkov:skip=CKV2_AWS_30:Query logging is set through log_statement in the parameter group (ddl) with log exports to CloudWatch
  identifier        = "securestudy-db"
  engine            = "postgres"
  engine_version    = "16.4"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  db_name           = "students"
  username          = "dbadmin"

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn

  storage_encrypted                     = true
  kms_key_id                            = aws_kms_key.main.arn
  multi_az                              = true
  publicly_accessible                   = false
  db_subnet_group_name                  = aws_db_subnet_group.main.name
  vpc_security_group_ids                = [aws_security_group.db.id]
  parameter_group_name                  = aws_db_parameter_group.main.name
  iam_database_authentication_enabled   = true
  backup_retention_period               = 7
  deletion_protection                   = true
  copy_tags_to_snapshot                 = true
  auto_minor_version_upgrade            = true
  skip_final_snapshot                   = false
  final_snapshot_identifier             = "securestudy-db-final"
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.main.arn
  performance_insights_retention_period = 7
}
