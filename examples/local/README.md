# Local example

Applies circuit-restic to a throwaway Rocky Linux 10 container with systemd, backing up `/etc` and `/root` to a repository at `/srv/restic` on the same container. You need Conn3x and Podman.

```sh
./up.sh
export TF_VAR_password='a long passphrase'
conn3x init
conn3x apply
conn3x plan
```

The second plan says `No changes.` Back up now, rather than at 02:30, and look at the snapshot:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts root@127.0.0.1
systemctl start conn3x-restic-backup.service
conn3x-restic snapshots
conn3x-restic restore latest --target /tmp/restore --include /etc/hostname
```

The example takes backend credentials from `TF_VAR_environment`, such as `'{ AWS_ACCESS_KEY_ID = "...", AWS_SECRET_ACCESS_KEY = "..." }'` for an `s3:` repository. A local path needs none.

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses. With rootless Podman on Linux, `PODMAN="sudo podman"` runs it rootful.

`./down.sh` removes the container, its volumes, the key and the state.
