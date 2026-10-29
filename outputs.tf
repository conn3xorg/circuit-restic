output "restic_command" {
  description = "Command on each host that runs restic against the repository, such as conn3x-restic snapshots."
  value       = local.restic
}

output "backup_unit" {
  description = "Name of the systemd service the timer starts. Start it to back up now."
  value       = "${local.unit}.service"
}
