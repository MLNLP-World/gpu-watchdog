#!/usr/bin/env bash
# One-shot: show your GPU usage and PID and full command and cwd on this node.

set -euo pipefail

# Build uuid->index map
declare -A UUID2IDX
while IFS=, read -r idx uuid; do
  idx=$(echo "$idx" | xargs)
  uuid=$(echo "$uuid" | xargs)
  UUID2IDX["$uuid"]="$idx"
done < <(nvidia-smi --query-gpu=index,uuid --format=csv,noheader 2>/dev/null)

# List compute apps and filter to current user
nvidia-smi --query-compute-apps=gpu_uuid,pid,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null \
| while IFS=, read -r gpu_uuid pid mem; do
    gpu_uuid=$(echo "$gpu_uuid" | xargs)
    pid=$(echo "$pid" | xargs)
    mem=$(echo "$mem" | xargs)
    [ -z "${pid:-}" ] && continue

    # Only show my processes
    if ps -o user= -p "$pid" 2>/dev/null | grep -qx "$USER"; then
      idx="${UUID2IDX[$gpu_uuid]:-?}"
      cmd="$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | sed 's/[[:space:]]\+/ /g')"
      cwd="$(readlink -f /proc/$pid/cwd 2>/dev/null || true)"
      etime="$(ps -p "$pid" -o etime= 2>/dev/null | xargs || true)"

      echo "GPU=$idx  MEM=${mem}MiB  PID=$pid  ETIME=${etime:-NA}"
      echo "  CWD: ${cwd:-NA}"
      echo "  CMD: ${cmd:-NA}"
      echo
    fi
  done
