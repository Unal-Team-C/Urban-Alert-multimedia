# Connection of the function to DocumentDB (spec 002 RF-004, plan D-006). The function only receives the ARN and reads
# the URI at runtime. The password lives in the encrypted, private Terraform state (same pattern as Geoespacial).
resource "random_password" "docdb" {
  length  = 32
  special = false
}

locals {
  # retryWrites=false: DocumentDB does not support retryable writes. replicaSet=rs0 lets the driver follow failovers.
  docdb_uri = format(
    "mongodb://%s:%s@%s:%d/?tls=true&tlsCAFile=%s&replicaSet=rs0&retryWrites=false",
    var.docdb_master_user, random_password.docdb.result, aws_docdb_cluster.this.endpoint, var.docdb_port, var.docdb_ca_file,
  )
}

# recovery_window_in_days = 0: deleted immediately on deprovision, so the next provision can recreate the name.
resource "aws_secretsmanager_secret" "docdb" {
  name                    = "${var.name}-docdb"
  description             = "MongoDB URI of ${var.name} (DocumentDB, TLS required)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "docdb" {
  secret_id     = aws_secretsmanager_secret.docdb.id
  secret_string = local.docdb_uri
}
