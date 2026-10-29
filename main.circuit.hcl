# Facts give each host's architecture, which picks the release binary, and
# its family, which names the SSH client package for an sftp: repository.
data "conn3x_host" "facts" {
  for_each = var.hosts

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }

  lifecycle {
    postcondition {
      condition     = contains(keys(var.checksums), self.arch)
      error_message = "Host ${each.key} is ${self.arch}. The circuit has restic builds for ${join(" and ", keys(var.checksums))}."
    }
  }
}

locals {
  dir      = "/opt/restic/${var.restic_version}"
  binary   = "${local.dir}/restic"
  conf_dir = "/etc/conn3x-restic"
  restic   = "/usr/local/sbin/conn3x-restic"
  backup   = "/usr/local/sbin/conn3x-restic-backup"
  unit     = "conn3x-restic-backup"

  # restic names its builds after Go's architectures.
  goarch = { x86_64 = "amd64", aarch64 = "arm64" }
  asset  = { for name, f in data.conn3x_host.facts : name => "restic_${var.restic_version}_linux_${local.goarch[f.arch]}.bz2" }

  ssh_client = { for name, f in data.conn3x_host.facts : name => f.os_family == "redhat" ? "openssh-clients" : "openssh-client" }

  # Single quotes keep the shell from reading anything in a value.
  repository_q = "'${replace(var.repository, "'", "'\\''")}'"
  paths_q      = join(" ", [for p in var.paths : "'${replace(p, "'", "'\\''")}'"])

  # Double-quoted, with the four characters the shell treats specially in
  # double quotes escaped, so the file reads the same to sh and to systemd's
  # EnvironmentFile.
  environment = join("", [for k, v in var.environment : "${k}=\"${replace(replace(replace(replace(v, "\\", "\\\\"), "\"", "\\\""), "$", "\\$"), "`", "\\`")}\"\n"])

  # Runs restic with the repository, password and backend credentials set,
  # for the timers and for you.
  wrapper = <<-EOT
    #!/bin/sh
    # Written by Conn3x. Runs restic against this host's repository, such as:
    #   conn3x-restic snapshots
    set -a
    . ${local.conf_dir}/environment
    set +a
    export RESTIC_REPOSITORY=${local.repository_q}
    export RESTIC_PASSWORD_FILE=${local.conf_dir}/password
    export RESTIC_CACHE_DIR=/var/cache/restic
    exec ${local.binary} "$@"
  EOT

  keep = var.retention == null ? [] : [
    for flag, n in {
      "--keep-last"    = var.retention.keep_last
      "--keep-hourly"  = var.retention.keep_hourly
      "--keep-daily"   = var.retention.keep_daily
      "--keep-weekly"  = var.retention.keep_weekly
      "--keep-monthly" = var.retention.keep_monthly
      "--keep-yearly"  = var.retention.keep_yearly
    } : "${flag} ${n}" if n != null && n != 0
  ]

  # Snapshots carry the conn3x tag, so forget leaves alone any you take by
  # hand without it.
  backup_script = join("\n", concat([
    "#!/bin/sh",
    "# Written by Conn3x. Changes here are overwritten on the next apply.",
    "set -eu",
    "${local.restic} backup --tag conn3x --exclude-file ${local.conf_dir}/excludes ${local.paths_q}",
    ], length(local.keep) == 0 ? [] : [
    "${local.restic} forget --tag conn3x --group-by host,tags --prune ${join(" ", local.keep)}",
  ], [""]))
}

circuit "restic" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  step "schedule_valid" {
    for_each = toset(compact([var.schedule, var.check_schedule]))
    command {
      command = "echo 'Not a calendar expression systemd understands: ${item.value}' >&2; exit 1"
      unless  = "systemd-analyze calendar '${item.value}' >/dev/null"
    }
  }

  # Minimal images can lack either.
  step "tools" {
    for_each = toset(["curl", "bzip2"])
    package {
      name = item.value
    }
  }

  # restic talks to an sftp: repository through the ssh command.
  step "ssh_client" {
    for_each = toset(startswith(var.repository, "sftp:") ? ["ssh"] : [])
    package {
      name = local.ssh_client[each.key]
    }
  }

  # The release is one static binary, compressed on its own, so every
  # distribution runs the same restic.
  step "download" {
    download {
      url    = "https://github.com/restic/restic/releases/download/v${var.restic_version}/${local.asset[each.key]}"
      sha256 = var.checksums[data.conn3x_host.facts[each.key].arch]
      dest   = "${local.dir}/${local.asset[each.key]}"
    }
  }

  step "unpack" {
    command {
      command = "bunzip2 -c ${local.dir}/${local.asset[each.key]} > ${local.binary}.tmp && chmod 755 ${local.binary}.tmp && mv ${local.binary}.tmp ${local.binary}"
      creates = local.binary
    }
  }

  step "link" {
    link {
      path   = "/usr/local/bin/restic"
      target = local.binary
    }
  }

  # Holds the password and backend credentials, so only root reads it.
  step "conf_dir" {
    directory {
      path = local.conf_dir
      mode = "0700"
    }
  }

  # Both are write-only: they reach the host, but the plan and state hold
  # only an HMAC of each.
  step "password" {
    file {
      path       = "${local.conf_dir}/password"
      content_wo = var.password
    }
  }

  step "environment" {
    file {
      path       = "${local.conf_dir}/environment"
      content_wo = local.environment
    }
  }

  step "excludes" {
    file {
      path    = "${local.conf_dir}/excludes"
      content = join("", [for e in var.excludes : "${e}\n"])
    }
  }

  step "wrapper" {
    file {
      path    = local.restic
      content = local.wrapper
      mode    = "0755"
    }
  }

  step "script" {
    file {
      path    = local.backup
      content = local.backup_script
      mode    = "0755"
    }
  }

  # A repository that already exists, with this password, is left as it
  # is. With another password, cat config fails, init refuses to write
  # over the repository, and the apply stops here. It runs again whenever
  # the password, credentials or repository change. There's no unless,
  # which would be checked at plan time against the old files, and would
  # make every plan reach the repository.
  step "init" {
    command {
      command = "${local.restic} cat config >/dev/null 2>&1 || ${local.restic} init"
      triggers = [
        conn3x_file.restic__password[each.key].content_hmac,
        conn3x_file.restic__environment[each.key].content_hmac,
        conn3x_file.restic__wrapper[each.key].sha256,
      ]
    }
  }

  # Spreads hosts on the same schedule across the delay, so they don't all
  # hit the repository at once. Written before the timer so its first start
  # already has it.
  step "delay" {
    file {
      path    = "/etc/systemd/system/${local.unit}.timer.d/conn3x.conf"
      content = "# Written by Conn3x. Changes here are overwritten on the next apply.\n[Timer]\nRandomizedDelaySec=${var.randomized_delay}\n"
    }
  }

  step "timer" {
    timer {
      name        = local.unit
      description = "restic backup to ${var.repository}"
      on_calendar = var.schedule
      command     = local.backup
      persistent  = true
    }
  }

  # daemon-reload alone picks up a new delay. Restarting the timer would
  # make it catch up on a missed run straight away.
  step "delay_applied" {
    command {
      command  = "systemctl daemon-reload"
      triggers = { delay = conn3x_file.restic__delay[each.key].revision }
    }
  }

  step "check" {
    for_each = toset(var.check_schedule == null ? [] : ["check"])
    timer {
      name        = "conn3x-restic-check"
      description = "restic check of ${var.repository}"
      on_calendar = var.check_schedule
      command     = "${local.restic} check"
      persistent  = true
    }
  }
}
