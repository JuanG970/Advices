#!/usr/bin/env bash
#
# cloud-env/setup.sh -- build this repo's Claude cloud environment.
#
# Put this in the environment's "Setup script" field (it runs one directory
# above the repo, hence the cd):
#
#     cd Advices && bash cloud-env/setup.sh
#
# What it does (all idempotent, no secrets, no Wolfram kernel is started):
#   1. apt: runtime libraries the Wolfram Engine links against, plus emacs-nox
#      for `make tangle`.
#   2. install-wolfram-engine.sh: the pinned Wolfram Engine 14.3 build.
#
# To skip the Engine (about 7 GB and 100 s) and keep only the apt tools, put
# the switch on the command line -- the setup script cannot see the
# environment's variables:
#
#     cd Advices && WOLFRAM_ENGINE=skip bash cloud-env/setup.sh
#
# What it does NOT do: activate a license. Read "The blocker" in
# cloud-env/README.md before expecting a kernel to start.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "setup.sh: run as root" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

# Same list the official wolframresearch/wolframengine image installs
# (recorded in its build history), so the Engine sees the libraries it expects.
engine_libs=(
  ca-certificates netbase curl xz-utils avahi-daemon
  libatomic1 libegl1 libxkbcommon0 libgl1 libglx-mesa0
  libfontconfig1 libasound2t64 libxinerama1
)
# What this repo's Makefile needs around the Engine.
repo_tools=(emacs-nox jq make git)

install_engine=1
[ "${WOLFRAM_ENGINE:-install}" = "skip" ] && install_engine=0

apt-get update -qq
if [ "$install_engine" = 1 ]; then
  apt-get install -y -qq --no-install-recommends "${engine_libs[@]}" "${repo_tools[@]}"
  bash "$here/install-wolfram-engine.sh"
else
  apt-get install -y -qq --no-install-recommends "${repo_tools[@]}"
  echo "setup.sh: WOLFRAM_ENGINE=skip -- not installing the Wolfram Engine"
fi
