variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}


variable "restic_version" {
  type        = string
  default     = "0.19.1"
  description = "restic release to install, without the leading v."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.restic_version))
    error_message = "restic_version must be a release number such as \"0.19.1\", without the leading v."
  }
}

variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the linux_amd64 and linux_arm64 .bz2 release files, by architecture, x86_64 and aarch64, from the release's SHA256SUMS. Change these with restic_version."
  default = {
    x86_64  = "f415415624dcc452f2a02b8c33641791a8c6d6d3b65bbb3543fcf9a25151585c"
    aarch64 = "a5f64aaab53d51e311fa3829124c5b703f2d14cf187d8640b6be3b2b49376465"
  }

  validation {
    condition     = alltrue([for a, c in var.checksums : contains(["x86_64", "aarch64"], a) && can(regex("^[0-9a-f]{64}$", c))])
    error_message = "checksums maps x86_64 or aarch64 to a SHA-256 in lowercase hex."
  }
}

variable "repository" {
  type        = string
  description = "Repository to back up to, as restic takes it: a local path, or sftp:, rest:, s3:, b2:, azure:, gs: or rclone: followed by the location."

  validation {
    condition     = length(trimspace(var.repository)) > 0 && !strcontains(var.repository, "\n")
    error_message = "repository must be a single line, such as \"/srv/restic\" or \"sftp:backup@203.0.113.20:/srv/restic\"."
  }
}

variable "password" {
  type        = string
  sensitive   = true
  ephemeral   = true
  description = "Password the repository is encrypted with. Kept out of the plan and state. Lose it and the backups can't be read."

  validation {
    condition     = length(var.password) > 0
    error_message = "password can't be empty."
  }
}

variable "environment" {
  type        = map(string)
  default     = {}
  sensitive   = true
  ephemeral   = true
  description = "Environment variables the backend needs, such as { AWS_ACCESS_KEY_ID = \"...\", AWS_SECRET_ACCESS_KEY = \"...\" }. Kept out of the plan and state."

  validation {
    condition     = alltrue([for k, v in var.environment : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k)) && !strcontains(v, "\n")])
    error_message = "environment's names must be letters, digits and _, not starting with a digit, and its values single lines."
  }
}

variable "paths" {
  type        = list(string)
  default     = ["/etc", "/home", "/root"]
  description = "Absolute paths to back up."

  validation {
    condition     = length(var.paths) > 0 && alltrue([for p in var.paths : startswith(p, "/") && !strcontains(p, "\n")])
    error_message = "paths must hold at least one absolute path."
  }
}

variable "excludes" {
  type        = list(string)
  default     = []
  description = "Patterns restic skips, one per line in an --exclude-file, such as [\"/home/*/.cache\", \"*.tmp\"]."

  validation {
    condition     = alltrue([for e in var.excludes : !strcontains(e, "\n")])
    error_message = "Each of excludes must be a single line."
  }
}

variable "schedule" {
  type        = string
  default     = "daily"
  description = "When the backup runs, as a systemd calendar expression, such as \"daily\" or \"*-*-* 02:30:00\"."

  validation {
    condition     = length(var.schedule) > 0 && !strcontains(var.schedule, "\n") && !strcontains(var.schedule, "'")
    error_message = "schedule must be a single-line systemd calendar expression, such as \"daily\"."
  }
}

variable "randomized_delay" {
  type        = string
  default     = "1h"
  description = "Longest random delay systemd adds to each run, as a systemd time span such as \"30min\" or \"0\", so hosts on the same schedule don't all start at once."

  validation {
    condition     = can(regex("^[0-9]+ ?[a-z]*( [0-9]+ ?[a-z]*)*$", var.randomized_delay))
    error_message = "randomized_delay must be a systemd time span, such as \"1h\", \"30min\" or \"0\"."
  }
}

variable "retention" {
  type = object({
    keep_last    = optional(number)
    keep_hourly  = optional(number)
    keep_daily   = optional(number, 7)
    keep_weekly  = optional(number, 4)
    keep_monthly = optional(number, 12)
    keep_yearly  = optional(number)
  })
  default     = {}
  description = "Snapshots restic forget keeps after each backup, before it prunes the rest. Null keeps every snapshot. A keep of 0 or null is left out."

  validation {
    condition     = try(alltrue([for n in values(var.retention) : n == null || (n >= 0 && floor(n) == n)]), var.retention == null)
    error_message = "Each keep in retention must be a whole number, 0 or more."
  }
}

variable "check_schedule" {
  type        = string
  default     = null
  description = "When restic check verifies the repository, as a systemd calendar expression such as \"Sun *-*-* 04:00:00\". When null, it doesn't."

  validation {
    condition     = var.check_schedule == null || (!strcontains(coalesce(var.check_schedule, "-"), "\n") && !strcontains(coalesce(var.check_schedule, "-"), "'"))
    error_message = "check_schedule must be a single-line systemd calendar expression."
  }
}
