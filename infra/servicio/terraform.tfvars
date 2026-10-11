# Values are documented in variables.tf; change them here, in a commit, never by hand in AWS.
# paquete_zip and commit are passed by the workflows.
region                 = "us-east-2"
memory_mb              = 512
timeout_s              = 15
init_timeout_s         = 60
concurrencia_reservada = -1
mongodb_max_pool_size  = 2
log_level              = "INFO"
