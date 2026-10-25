# Claude cloud environment for Wolfram Language work

Record of the setup done on 2026-10-25 in an Anthropic-hosted Claude Code cloud
session for this repo. Everything below was run and observed in that session
unless marked *untested*. No secret value appears anywhere in this directory.

## Where things stand

| Piece | State |
|---|---|
| Wolfram Engine 14.3, pinned by image digest | Installed and checksum-verified. `wolframscript` runs, the kernel binary starts and prints its (unlicensed) banner, no unresolved shared libraries. From scratch: 1 min 48 s, 6.7 GB on disk. |
| `emacs-nox` and `make tangle` | Works. The committed `Advices.wl` / `Advices.wlt` are identical to a fresh tangle of the `.org` sources. |
| Evaluating Wolfram Language (a licensed kernel) | **Blocked in this kind of session** -- see below. |
| Woxi (open-source interpreter, no license needed) | Installs in 4 s from a hash-pinned PyPI wheel. Release 0.3.0 cannot run Advices; its `main` branch can after two portable edits (12 of 15 tests clean). Not a substitute for the real Engine -- see option E. |
| `make test` | Not run here (needs a licensed kernel). Baseline: 16 of 16 passed in your CI run on 2026-09-28. |

## The blocker: the license check is not HTTPS

With `WOLFRAMSCRIPT_ENTITLEMENTID` set, `wolframscript` starts the kernel as

```
WolframKernel -pwfile !cloudlm.wolfram.com -entitlement <ID> ...
```

and the kernel opens a **raw TCP connection to `cloudlm.wolfram.com`, port 16286**
(the MathLM license protocol). Anthropic-hosted sessions forward only HTTP/HTTPS
through their proxy; other outbound TCP is dropped, so the connection never
completes.

| Check (this session) | Result |
|---|---|
| Kernel started with a deliberately invalid ID, traced with `strace -f -e trace=connect` | DNS to 8.8.8.8 works. Then `connect(..., sin_port=htons(16286), sin_addr=inet_addr("140.177.8.234")) = -1 ETIMEDOUT` after about 134 s, once more, then the kernel exits 255 with `No valid password found.` -- 4 min 30 s in all. It tries nothing else. |
| Plain TCP handshake, no data sent, 6 s cap | `cloudlm.wolfram.com:443`, `www.wolframcloud.com:443` and `example.com:443` connect. `cloudlm.wolfram.com:16286` and `github.com:22` time out. |
| Docs (cloud-environments page) | "Cloud sessions in Anthropic-hosted environments run behind an HTTP/HTTPS network proxy ... All outbound internet traffic from an Anthropic-hosted session passes through this proxy." In a self-hosted environment, "outbound traffic leaves through your own network boundary instead." |
| Your CI run (`wolfram-once.yml`, run 36481324090) | Passed. GitHub-hosted runners allow arbitrary outbound TCP, which is what the kernel's license check needs. |

**Not tested:** a valid entitlement. The connection to the license server comes
before any entitlement is checked, so I expect the same hang, but my evidence is
for the invalid-ID case. The invalid ID (`INVALID-DIAGNOSTIC-ONLY`) cannot match a
real entitlement, so no one's Service Credits were touched. I never had yours:
`WOLFRAMSCRIPT_ENTITLEMENTID` is not set in this session.

Two things to know when it fails:

- `wolframscript` ignores SIGTERM while it waits on the license server
  (`timeout 120` was still waiting at 187 s). Always `timeout -k <grace> <secs>`.
- `verify.sh` probes the license port in 5 s, so nobody has to rediscover this.

## Options for running Wolfram code

| | How | Checked here | Needs from you | Trade-off |
|---|---|---|---|---|
| **A. GitHub Actions** (my recommendation) | Re-add a `workflow_dispatch` workflow like your one-off, taking a `.wls` path and running it in the pinned image. I trigger it and read the job logs with the GitHub tools in this session. The entitlement stays in GitHub Secrets. | Read side: I read run 1's job and log (`Total: 16, Passed: 16`). Triggering (`actions_run_trigger`) not exercised. | Your OK to add the workflow; a credit budget. | About 1.5 min per round trip (your run: 86 s). Logs only, not interactive. Each run spends credits. |
| **B. Self-hosted Claude environment** | Sessions run on your infrastructure, so you can allow TCP 16286. | Docs only. | Plan/org support for self-hosted environments and a runner you operate. | Interactive local kernel; most to operate. |
| **C. Wolfram Cloud over HTTPS** | `wolframscript -cloud` runs code on Wolfram's servers. | With no credentials it connected to the session proxy (`strace`: the only non-DNS connect was `127.0.0.1:46513`), prompted for a Wolfram ID and printed `Incorrect username or password`. That is consistent with the cloud login answering over HTTPS, but I did not verify the reply, and nothing further. | A Wolfram ID and password as environment variables, readable by anyone using the environment. | Runs remotely (no local files), cloud limits and billing, `Advices.wl` would have to be shipped to the cloud kernel. |
| **D. Activation key (node-locked)** | The unlicensed kernel offers "automatic Web Activation" with an activation key (its banner points to `https://user.wolfram.com`). | Only that the prompt appears. This VM's MathID was `6532-72628-33049`, machine name `vm`; whether it is stable across sessions is unknown. | A license type that has an activation key (the on-demand entitlement does not) and its credentials. | *Untested.* May need re-activation on every VM and count against activation limits. |
| **E. Woxi** (open-source reimplementation, AGPL-3.0) | Runs locally with no license check, so the port-16286 problem does not exist for it. | Installed and measured; see the next section. | A decision on how far to trust a reimplementation, and which build. | Silently differs from the real Engine in places I tested. `VerificationTest` is "not planned" in Woxi. Advices needs edits to run on it. |

There is no environment setting for raw TCP: the access levels are None / Trusted /
Full / Custom, and all are domain-based.

## Woxi (option E): what I measured

[Woxi](https://woxi.ad-si.com) is an open-source (AGPL-3.0-or-later) Wolfram Language
interpreter written in Rust. It needs no kernel and no license server. Release 0.3.0 is
on PyPI (dated 2026-08-06 in its changelog); `main` is moving fast (1,882 commits since
2026-08-05, the latest on 2026-10-25). Its own `functions.csv` marks 3,314 of 6,382
symbols implemented on `main` (52%, up from 47% at 0.3.0). That list marks
`VerificationTest` "out of scope for Woxi" (the source's wording for its not-planned
marker) and leaves `TestReport` blank ("not implemented (yet)"), so this repo's test
runner cannot run on Woxi unchanged.

**Install** (verified here: 3.7 s; pip refuses a wrong hash). Hosts: `pypi.org` and
`files.pythonhosted.org`, both on the Trusted list.

```bash
python3 -m venv /opt/woxi
echo 'woxi==0.3.0 --hash=sha256:46fedeab967568383f3fef2da5543bcb119be92a2de7093f5a778952003c5a0b' > /tmp/woxi-requirements.txt
/opt/woxi/bin/pip install --require-hashes -r /tmp/woxi-requirements.txt
ln -sf /opt/woxi/bin/woxi /usr/local/bin/woxi
```

`main` cannot be installed that way. I built it (dev profile, `--locked`, in a stripped
environment without session credentials) in 8 min 21 s, which is longer than the roughly
five-minute setup-script cache window, and it needs crates.io plus a git dependency on
GitHub (`astro-float`).

**Results.** Re-run them with `python3 -I cloud-env/woxi-compat/probes.py woxi` and
`python3 -I cloud-env/woxi-compat/suite.py woxi`. Neither touches the repo.

| | Release 0.3.0 | `main` @ 385306a |
|---|---|---|
| 33 probes (everyday functions, evaluator semantics, packages, Advices) | 28 pass | 31 pass |
| The repo's 15 tests after the load test, library as committed | 1 clean, 4 with messages | same |
| ... with one edit (the dispatcher rule's form) | 5 clean, but four of those tests also pass when no advice ever fires | 3 clean |
| ... with both portable edits below | 5 clean, the same five | **12 clean**, 1 with messages, 2 failing |

Both builds reject a rule written `HoldPattern[f[a___]] /; cond :> rhs` in
`PrependTo[DownValues[f], ...]` ("Tag HoldPattern ... is Protected"), which is how
Advices installs its dispatcher. 0.3.0 also fails rule removal from `DownValues`
(probe 2.12) and package loading (3.01, 3.02); `main` fixed those.

**The two portable edits** (not applied to the repo). I believe both are valid on the
real Engine: the first is the form `DownValues` itself returns, and the second uses only
`Append`. That is unverified, so CI on the real Engine must confirm before merging.

1. `Advices.wl` line 91: `HoldPattern[target[args___]] /; cond :> rhs` becomes
   `HoldPattern[target[args___] /; cond] :> rhs`.
2. `Advices.wl` lines 79-80: the nested `AppendTo[$Registry[key, c], x]` followed by
   `$Registry[key, c] = SortBy[...]` becomes the single-key assignment
   `$Registry[key] = Append[$Registry[key], c -> SortBy[Append[$Registry[key, c], x], Last]]`.

Still failing on `main` after both edits: `Remove-Non-Existent-Is-No-Op` (a garbage
result containing `"KeyAbsent"`, so a `Missing[...]` is leaking through somewhere; I did
not trace it), `AdviceClear-Fully-Purges` (passes but emits `Lookup::invrl` about a
`Missing[...]` argument, which real `VerificationTest` counts as a failure) and
`Holding-Boundary-Args-Evaluated-Once` (`$RecursionLimit` exceeded).

**Silent divergences, the worst kind (no error, wrong result).** `r[k1, k2] = v` and
`AppendTo[r[k1, k2], x]` on a nested Association do nothing in both builds. That is why
Advices registered no hooks. In 0.3.0 only: `DownValues[f] = {}` did not clear,
conditional definitions lost their condition in `DownValues`, and a named blank inside
`Rule[a, id_]` never bound. In both builds `InputForm[expr]` prints as the literal
wrapper (`InputForm[ab]`) instead of the input-form text. Treat Woxi results as
hypotheses to confirm on the real Engine.

**License.** AGPL-3.0-or-later (the wheel's metadata says so). As I understand it,
running your own scripts through the CLI does not put them under the AGPL, while
modifying Woxi and distributing it or offering it over a network carries obligations. I
am not a lawyer; check if it matters for you.

## What I need from you

1. **Pick a path (A-E).** Without one I cannot evaluate any Wolfram Language on the
   real Engine. I recommend A as the source of truth, plus E only if you want a quick
   local loop while editing.
2. **Do not put `WOLFRAMSCRIPT_ENTITLEMENTID` in the Claude environment yet.**
   Environment variables are readable by "anyone who uses the environment" and by
   any command I run, and in a hosted session it cannot work anyway. Keep it in
   GitHub Secrets (A) or add it only to a self-hosted environment (B).
3. **Engine version.** I pinned 14.3 (your README and CI). 15.0 exists
   (`sha256:3ac08d6aaa33...`, untested here). Say if you want it.
4. **Woxi: yes or no, and which build.** Release 0.3.0 installs in 4 s but cannot run
   Advices. `main` runs 12 of 15 tests after two edits to `Advices.wl`, but takes 8 min
   to build (too slow for the setup-script cache) and still diverges from the real
   Engine. If you want it, I also need your OK to make those two edits, which must
   then pass CI on the real Engine before merging.
5. **What the experiments are**, mainly whether they need the internet
   (Wolfram|Alpha, `Entity` data, `ResourceFunction`, `PacletInstall`, LLM
   functions) or heavy compute. That decides allowlist entries and credit use. Also
   a rough **Service Credit budget**: I cannot see your balance or rates, and I
   assume from your CI comment that every kernel session spends credits.
6. **Merge it.** This directory is committed and pushed on branch
   `claude/cloud-env-wolfram` (no PR opened). The setup-script line below only works
   once these files are on the branch your environment clones (`v0.1`), so merge
   when you are happy with them, or tell me and I will open the PR.
7. *(Optional)* A short `CLAUDE.md` so future sessions read this file first and do
   not start a kernel blindly.

## Replicating the environment

### Environment dialog (claude.ai/code, your environment, Edit)

Setup script (the line to paste):

```bash
cd Advices && bash cloud-env/setup.sh || true
```

| Field | Value |
|---|---|
| Network access | **Trusted** covers the Engine download: `auth.docker.io`, `registry-1.docker.io` and `production.cloudfront.docker.com` are on its default list. The list names no Ubuntu mirror and no Wolfram host. This session reached `example.com`, so it was on a broader level than Trusted, and I could not confirm apt works under Trusted. If it does not: **Custom**, include the defaults, add `archive.ubuntu.com` and `security.ubuntu.com`. |
| Environment variables | None needed today (see item 2 above). |

For Wolfram internet features at runtime (not licensing) add the hosts you need
under Custom. Reachable in this session: `account.wolfram.com`, `user.wolfram.com`,
`www.wolframcloud.com`, `pacletserver.wolfram.com`, `www.wolframalpha.com`,
`reference.wolfram.com`. None of this opens port 16286.

Setup-script rules from the docs, and how this script meets them:

- Runs as root **before** the environment's variables exist, so it can never see a
  secret. Nothing here needs one.
- A non-zero exit stops the session from starting, hence `|| true`. `verify.sh`
  reports a broken install.
- The snapshot is cached only if setup finishes in roughly five minutes. This one
  took 1 min 48 s. The cache is rebuilt when the script **text** or the allowed
  hosts change, and after about seven days. Editing `cloud-env/*.sh` does not change
  the text in the dialog, so by the docs' wording it should not trigger a rebuild on
  its own; bump a comment in the dialog to force one.
- The script reads `cloud-env/` from the cloned repo, so these files must be on the
  branch the environment clones. Otherwise paste `setup.sh` and
  `install-wolfram-engine.sh` into the dialog (limit 64 KB).
- `WOLFRAM_ENGINE=skip` (`cd Advices && WOLFRAM_ENGINE=skip bash cloud-env/setup.sh`)
  installs only the apt tools, saving about 7 GB and 100 s. Do this for path A.

### Files

| File | Purpose |
|---|---|
| `setup.sh` | Entry point. apt libraries and tools, then the Engine. Idempotent: a re-run is a 3 s no-op. |
| `install-wolfram-engine.sh` | Installs the pinned official image without a Docker daemon. Verifies every sha256 back to the pinned manifest digest. Never starts a kernel. |
| `verify.sh` | Checks platform, install, libraries, tangle sync, entitlement presence (never its value) and the license port. `--kernel` also starts one licensed kernel (spends credits; skipped if the port is closed). Exit status = number of failures. |
| `woxi-compat/probes.py`, `woxi-compat/suite.py` | Re-runnable checks of Woxi against standard Wolfram behaviour and against this repo's tests. Standard-library Python only; they copy anything they change into temp dirs and never touch the repo. Re-run them when Woxi 0.4.0 appears. |

### Expected `verify.sh` output today

```
Platform
  [ ok ] Ubuntu 24.04 x86_64 (what the installer targets)
Wolfram Engine
  [ ok ] installed from the pinned image: 14.3 (sha256:ff018b403ca9...)
  [ ok ] WolframScript 1.13.0 for Linux x86 (64-bit)
  [ ok ] kernel binary links cleanly
Repo tooling
  [ ok ] emacs 29.3: Advices.wl/.wlt match a fresh tangle of the .org sources
Licensing
  [FAIL] WOLFRAMSCRIPT_ENTITLEMENTID is not set -- add it as an environment secret
  [FAIL] TCP cloudlm.wolfram.com:16286 not reachable -- a licensed kernel will hang here (see README, 'The blocker')
  [info] TCP :443 on the same host connects, so the sandbox is up; it is specifically the license port that is closed

NOT READY: 2 check(s) failed
```

### Moving to another Engine release (*untested* beyond 14.3)

Tags move, so pin digests. Look one up:

```bash
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:wolframresearch/wolframengine:pull" | jq -r .token)
curl -sI -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  https://registry-1.docker.io/v2/wolframresearch/wolframengine/manifests/15.0 | grep -i docker-content-digest
```

Then `WOLFRAM_IMAGE_DIGEST=<digest> bash cloud-env/install-wolfram-engine.sh`, and
update the default in the script. On 2026-10-25 `14.3` and `14.3.0` resolved to
`sha256:ff018b403ca9...` (your pin, unmoved) and `15.0`, `15.0.0` and `latest` to
`sha256:3ac08d6aaa33...`. By design (untested) releases install side by side and the
most recent install takes the `WolframKernel` link.

## Rules for running Wolfram code (once a path works)

- One kernel per task: put everything in one `.wls` and run `wolframscript -script`.
  Never call `wolframscript -code` in a loop; each call is a new kernel.
- Always `timeout -k 5 <secs>` (see SIGTERM above).
- Run `make tangle` and `verify.sh` first; they are free. Your old CI did the same
  ("a tangle mismatch does not spend Service Credits").

## What I did, in order

1. **Read the repo.** Makefile, `scripts/`, README, git history. Found the removed
   `wolfram-once.yml` (commit `a66932c`): official image `wolframresearch/wolframengine:14.3`
   pinned by digest, `WOLFRAMSCRIPT_ENTITLEMENTID` from a repo secret, tests run with
   `wolframscript -script scripts/run-tests.wls`.
2. **Surveyed the container.** Ubuntu 24.04.5, x86_64, 4 vCPU, 15 GiB RAM, about 30 GB
   free, running as root. Docker CLI present, no daemon running. No Wolfram, no emacs.
   Entitlement variable not set.
3. **Surveyed the network.** Reachable: Wolfram web hosts, Docker Hub, apt, GitHub.
   `account.wolfram.com/download/public/wolfram-engine/desktop/LINUX` (the old public
   installer URL) returns 404, so I used the Docker Hub image as the source.
   (`license.wolfram.com` is not a real host: a made-up host gets the same 502.)
4. **Read the image's manifest and config** straight from the registry, checking each
   sha256. The build history gave the apt dependencies, the install command
   (`/WolframEngine-Install.sh -- -auto`) and the base (Ubuntu 24.04, build 12039118).
5. **Listed the Engine layer before extracting it.** It also carries the image's whole
   `/var/lib/dpkg` database, which would overwrite this host's package database. So
   the installer flattens layers into a staging directory and copies a whitelist.
6. **Wrote and linted the scripts** (`bash -n`, `shellcheck`, both clean). First
   end-to-end run: apt plus a 2.5 GiB download (2,593 MiB), unpack and install,
   1 min 48 s.
7. **Verified the install.** Layout and links, no leftover staging or cache,
   `ldd` clean for `WolframKernel` and `wolframscript`, `wolframscript -version`,
   `make tangle` sync.
8. **Probed licensing without spending anything**: no entitlement (exit 255 in about
   0.2 s with "not activated", no network traffic), an invalid entitlement (hangs), an invalid
   entitlement under `strace`, a 4.5-minute run to see any fallback (none), and an
   unauthenticated `-cloud` run.
9. **Read the docs and your CI history** to confirm the limitation is by design and to
   get the 16/16 baseline.
10. **Hardened the installer.** Download helper tested on the real small layers: fresh
    download, cache hit with the network deliberately broken, same-size corruption,
    truncated resume, oversize file, bad digest. Re-ran `setup.sh`: 3 s no-op. Added
    `WOLFRAM_ENGINE=skip`.
11. **Evaluated Woxi** when you asked about it. Installed the PyPI wheel into a scratch
    venv, read its own `functions.csv`, ran 33 probes and this repo's 15 tests (through
    a stand-in for `VerificationTest`), cloned `main` read-only and built it in a
    stripped environment, found the two blocking constructs, and tested portable
    rewrites in scratch copies. Details in "Woxi (option E)". I attached nothing: the
    tool reported that read access to the public repo was already available.

## Reference

**Pins.** Image `wolframresearch/wolframengine@sha256:ff018b403ca9095c6b339aac3d6e719ed5b8cf7a318bbe6521db52cb6d7c567a`
(single-platform amd64 manifest, config created 2025-11-05, build 12039118, Ubuntu 24.04
base, Engine 14.3.0.0, WolframScript 1.13.0). Layers, in order: base rootfs 29.7 MB
`953cdd41...`; empty build-arg check 32 B `4f4fb700...`; apt dependencies 125 MB
`ebf61c7b...`; Engine 2.56 GB `963ee1ec...`; patched CURLLink-14.1.4 2.2 MB
`83732623...` (the first three roles inferred from the build history, the last two
confirmed by listing). The installer uses all five.

**Installed layout.** `/usr/local/Wolfram/WolframEngine/14.3` (6.7 GB);
`/usr/local/bin/WolframKernel` (symlink); `/opt/Wolfram/WolframScript/bin/wolframscript`
registered through `update-alternatives` (priority 40, as the image's own postinst does)
as `/usr/bin/wolframscript`; `/usr/share/WolframEngine/Applications/CURLLink-14.1.4`;
`/usr/share/Mathematica/Installer/.installdirs`; `/etc/profile.d/Mathematica.sh`
(`MATHEMATICA_HOME`); marker `/usr/local/Wolfram/.installed-from-image`. Deliberately not
copied: the image's `/var/lib/dpkg`, `/var/log`, `/tmp`, mime, icons, man pages.

**apt packages.** From the image's Dockerfile: `ca-certificates netbase curl xz-utils
avahi-daemon libatomic1 libegl1 libxkbcommon0 libgl1 libglx-mesa0 libfontconfig1
libasound2t64 libxinerama1`. For this repo: `emacs-nox jq make git`. Installed ad hoc in
this session for diagnosis and not part of `setup.sh`: `shellcheck`, `strace`.

**Hosts the install uses.** `archive.ubuntu.com` and `security.ubuntu.com` (apt),
`auth.docker.io`, `registry-1.docker.io`, `production.cloudfront.docker.com`.

**Baseline.** CI run 36481324090, 2026-09-28, commit `a66932c`: job 86 s, of which the
Engine step (pull a 2.5 GiB image, start a kernel, run the tests) took 61 s. Report:
`Total: 16, Passed: 16, Failed: 0`. (`README.org` says 15 tests; the suite has 16.)

**The sandbox.** Ubuntu 24.04.5 on a Firecracker VM (kernel 6.18.44), 4 vCPU, 15 GiB RAM,
about 30 GB disk. Docs list 4 vCPU / 16 GB / 30 GB as the ceilings.

**Woxi pins.** PyPI `woxi==0.3.0`, the `manylinux_2_17_x86_64` wheel, sha256
`46fedeab967568383f3fef2da5543bcb119be92a2de7093f5a778952003c5a0b` (matches PyPI's
published digest). `main` was measured at commit
`385306acfaa2cc14741fe2f50eef4abc25c06105` (2026-10-25). Its `Cargo.toml` still says
0.3.0, so `woxi --version` cannot tell the two builds apart.
