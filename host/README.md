# host

Host-level tuning for the home server that isn't tied to any one stack.

## `host-tuning.yml`

Raises `fs.inotify.max_user_watches` (to 1048576) and `fs.inotify.max_user_instances` (to 512)
via `/etc/sysctl.d/99-inotify.conf`, applied immediately. The default watch limit (65536) is too
low for Immich's library watcher on large photo libraries, which otherwise logs repeated
`ENOSPC: System limit for number of file watchers reached` errors. inotify isn't namespaced, so
this is a host kernel limit shared with all containers.

Requires the `ansible.posix` collection:

```bash
ansible-galaxy collection install ansible.posix
cd /home/oskar/github/home-server-tools/host
ansible-playbook host-tuning.yml --ask-become-pass
```
