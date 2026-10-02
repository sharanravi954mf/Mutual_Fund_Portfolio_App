#!/usr/bin/env bash
# EXPLICIT ONE-TIME commissioning only. Never invoked by local tests/CI/reconciler.
# Usage: sudo bash bootstrap.sh /absolute/reviewed/config.json
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo 'Run only during separately authorized host commissioning.'; exit 1; }
config=${1:?absolute reviewed config.json required}
[[ "$config" = /* ]] && test -f "$config"
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
visudo -cf "$source_dir/dispatcher.sudoers"
runtime=/home/ubuntu/moneybowl-runtime/outbox-dispatcher
install -d -o root -g ubuntu -m 0750 "$runtime"
install -o root -g ubuntu -m 0640 "$source_dir/reconcile.py" "$source_dir/process-spool.py" "$runtime/"
install -o root -g ubuntu -m 0640 "$config" "$runtime/config.json"
install -d -o root -g root -m 0700 "$runtime/state"
install -o root -g root -m 0644 "$source_dir/moneybowl-outbox-dispatcher-reconcile.service" "$source_dir/moneybowl-outbox-dispatcher-reconcile.timer" "$source_dir/moneybowl-outbox-dispatcher-reconcile@.service" /etc/systemd/system/
install -o root -g ubuntu -m 0640 "$source_dir/webhook-dispatch.override.conf" "$runtime/webhook-dispatch.override.conf"
install -o root -g root -m 0440 "$source_dir/dispatcher.sudoers" /etc/sudoers.d/moneybowl-outbox-dispatcher
systemctl daemon-reload
echo 'Artifacts installed. After commissioning review, start the reconciliation service and enable its timer as documented.'
