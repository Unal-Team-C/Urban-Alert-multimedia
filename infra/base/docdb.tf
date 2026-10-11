# Metadata store: DocumentDB 5.0 (MongoDB API) with a single instance, private, encrypted, TLS enforced
# (spec 002 RF-003, RNF-007; plan D-002). Protection is only lifted by the deprovision workflow (RF-012).
resource "aws_docdb_subnet_group" "this" {
  name       = "${var.name}-docdb"
  subnet_ids = local.private_subnets
}

resource "aws_docdb_cluster_parameter_group" "this" {
  name        = "${var.name}-docdb"
  family      = "docdb5.0"
  description = "${var.name}: TLS required"

  parameter {
    name  = "tls"
    value = "enabled"
  }
}

resource "aws_docdb_cluster" "this" {
  cluster_identifier = "${var.name}-docdb"
  engine             = "docdb"
  engine_version     = var.docdb_engine_version
  port               = var.docdb_port

  master_username = var.docdb_master_user
  master_password = random_password.docdb.result

  db_subnet_group_name            = aws_docdb_subnet_group.this.name
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.this.name
  vpc_security_group_ids          = [aws_security_group.docdb.id]

  storage_encrypted       = true
  backup_retention_period = var.docdb_backup_retention_days
  apply_immediately       = true

  deletion_protection       = !var.allow_destroy
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-final-${var.final_snapshot_suffix}"
}

resource "aws_docdb_cluster_instance" "this" {
  identifier                 = "${var.name}-docdb-1"
  cluster_identifier         = aws_docdb_cluster.this.id
  instance_class             = var.docdb_instance_class
  auto_minor_version_upgrade = true
  apply_immediately          = true
}
