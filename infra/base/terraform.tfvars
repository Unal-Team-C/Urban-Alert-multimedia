# Values are documented in variables.tf; change them here, in a commit, never by hand in AWS.
region                      = "us-east-2"
name                        = "urban-alert-multimedia"
docdb_engine_version        = "5.0.0"
docdb_instance_class        = "db.t4g.medium"
docdb_master_user           = "multimedia"
docdb_backup_retention_days = 7
log_retention_days          = 30
