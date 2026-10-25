#!/usr/bin/env bash
#
# cloud-env/verify.sh -- check the cloud environment and say what is missing.
# By default it never starts a Wolfram kernel, so it costs no Service Credits.
#
# Usage:
#   cloud-env/verify.sh            checks only
#   cloud-env/verify.sh --kernel   also start ONE licensed kernel and print $Version
#                                  (spends Service Credits; needs the secret AND
#                                  outbound TCP 16286 -- see README)
#
# Exit status: the number of failed checks (0 = ready).

set -uo pipefail   # no -e: every check runs and is reported

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_kernel=0
[ "${1:-}" = "--kernel" ] && run_kernel=1

fails=0
ok()   { printf '  [ ok ] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; fails=$((fails + 1)); }
info() { printf '  [info] %s\n' "$*"; }
skip() { printf '  [skip] %s\n' "$*"; }
tcp_open() { timeout 5 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

echo "Platform"
if [ "$(uname -m)" = "x86_64" ] && grep -q 'VERSION_ID="24.04"' /etc/os-release; then
  ok "Ubuntu 24.04 x86_64 (what the installer targets)"
else
  bad "expected Ubuntu 24.04 x86_64, found $(uname -m) / $(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")"
fi

echo "Wolfram Engine"
marker=/usr/local/Wolfram/.installed-from-image
want="$(grep -oE 'sha256:[0-9a-f]{64}' "$repo/cloud-env/install-wolfram-engine.sh" | head -1)"
if [ -f "$marker" ] && grep -qxF "digest=${want}" "$marker"; then
  ok "installed from the pinned image: $(grep '^versions=' "$marker" | cut -d= -f2) (${want:0:19}...)"
else
  bad "Engine not installed from the pinned digest -- run: bash cloud-env/setup.sh"
fi
if command -v wolframscript >/dev/null && v="$(timeout -k 3 20 wolframscript -version </dev/null 2>&1)"; then
  ok "$v"
else
  bad "wolframscript missing or not runnable"
fi
kernel="$(find /usr/local/Wolfram/WolframEngine -path '*Binaries/Linux-x86-64/WolframKernel' -type f 2>/dev/null | head -1)"
if [ -n "$kernel" ]; then
  if ldd "$kernel" 2>&1 | grep -q 'not found'; then
    bad "kernel has unresolved shared libraries: $(ldd "$kernel" | grep 'not found' | tr -s '\t ' ' ' | paste -sd,)"
  else
    ok "kernel binary links cleanly"
  fi
else
  bad "no WolframKernel binary found"
fi

echo "Repo tooling"
if command -v emacs >/dev/null; then
  # Tangle in a temp copy so the working tree is never touched.
  tmp="$(mktemp -d)"; mkdir "$tmp/scripts"
  cp "$repo/Implementation.org" "$repo/Tests.org" "$tmp/"
  cp "$repo/scripts/emacs-tangle.el" "$tmp/scripts/"
  for org in Implementation.org Tests.org; do
    (cd "$tmp" && emacs --batch --load scripts/emacs-tangle.el --eval "(org-babel-tangle-file \"$org\")" >/dev/null 2>&1)
  done
  if cmp -s "$tmp/Advices.wl" "$repo/Advices.wl" && cmp -s "$tmp/Advices.wlt" "$repo/Advices.wlt"; then
    ok "emacs $(emacs --version | head -1 | awk '{print $3}'): Advices.wl/.wlt match a fresh tangle of the .org sources"
  else
    bad "Advices.wl/.wlt differ from a fresh tangle (run 'make tangle')"
  fi
  rm -rf "$tmp"
else
  bad "emacs missing (apt-get install emacs-nox)"
fi

echo "Licensing"
if [ -n "${WOLFRAMSCRIPT_ENTITLEMENTID:-}" ]; then
  ok "WOLFRAMSCRIPT_ENTITLEMENTID is set (${#WOLFRAMSCRIPT_ENTITLEMENTID} chars; value not shown)"
else
  bad "WOLFRAMSCRIPT_ENTITLEMENTID is not set -- add it as an environment secret"
fi
# The kernel's on-demand license check is raw TCP to the MathLM port, not HTTPS.
# When that port is dropped the kernel blocks in connect() for minutes.
license_port_open=0
if tcp_open cloudlm.wolfram.com 16286; then
  license_port_open=1
  ok "TCP cloudlm.wolfram.com:16286 reachable (on-demand license check can work)"
else
  bad "TCP cloudlm.wolfram.com:16286 not reachable -- a licensed kernel will hang here (see README, 'The blocker')"
fi
if tcp_open cloudlm.wolfram.com 443; then
  info "TCP :443 on the same host connects, so the sandbox is up; it is specifically the license port that is closed"
fi

if [ "$run_kernel" = 1 ]; then
  echo "Kernel (spends Service Credits)"
  if [ -z "${WOLFRAMSCRIPT_ENTITLEMENTID:-}" ]; then
    skip "no entitlement in the environment"
  elif [ "$license_port_open" != 1 ]; then
    skip "license port closed; the kernel would hang"
  else
    # -k: wolframscript ignores SIGTERM while it waits on the license server.
    # shellcheck disable=SC2016  # $Version is Wolfram code, not a shell variable
    if out="$(timeout -k 5 180 wolframscript -code 'Print[$Version]' </dev/null 2>&1)"; then
      ok "kernel started: $out"
    else
      bad "kernel did not start: $(printf '%s' "$out" | head -c 300)"
    fi
  fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "READY"; else echo "NOT READY: ${fails} check(s) failed"; fi
exit "$fails"
