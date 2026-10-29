variable "port" {
  type    = number
  default = 2222
}

# Set it with TF_VAR_password, so it isn't written to a file.
variable "password" {
  type      = string
  sensitive = true
  ephemeral = true
}

# Backend credentials, such as AWS_ACCESS_KEY_ID for an s3: repository.
# Set them with TF_VAR_environment='{ AWS_ACCESS_KEY_ID = "..." }'.
variable "environment" {
  type      = map(string)
  default   = {}
  sensitive = true
  ephemeral = true
}

module "restic" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  # A repository on the host itself, which is enough to try it. Point it
  # at another machine, such as sftp:backup@203.0.113.20:/srv/restic, for
  # backups worth having.
  repository  = "/srv/restic"
  password    = var.password
  environment = var.environment

  paths    = ["/etc", "/root"]
  excludes = ["/root/.cache"]

  schedule         = "*-*-* 02:30:00"
  randomized_delay = "30min"
  retention        = { keep_daily = 7, keep_weekly = 4, keep_monthly = 6 }
  check_schedule   = "Sun *-*-* 04:00:00"
}
