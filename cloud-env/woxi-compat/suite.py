"""Run this repo's VerificationTests under Woxi, one fresh process per test.

Usage:  python3 -I cloud-env/woxi-compat/suite.py [woxi-binary]

Woxi marks VerificationTest "not planned" and has no TestReport, so a minimal
stand-in is defined here: evaluate input and expected, compare with SameQ, print
PASS or FAIL. Real VerificationTest also fails a test that emits a message
(unless it lists it); the runner reproduces that by reporting PASS+MSG.

The repo is never modified. Each mode copies Advices.wl and Advices.wlt into a
temporary directory first.

  as-is         the library exactly as committed
  install-form  one rewrite: the dispatcher rule in AdviceAdd moves the Condition
                inside HoldPattern (the form DownValues itself returns)
  portable      both rewrites: that one, plus the nested registry update
                `AppendTo[$Registry[key, c], x]; $Registry[key, c] = ...` as a
                single-key assignment. Both should be valid on the real Engine
                too, but that has not been verified; CI would confirm.
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

WOXI = sys.argv[1] if len(sys.argv) > 1 else "woxi"
REPO = Path(__file__).resolve().parents[2]

SHIM = '''Unprotect[VerificationTest];
SetAttributes[VerificationTest, HoldAll];
VerificationTest[input_, expected_, opts___] := Module[{actual, exp, id},
  id = Last[{opts}][[2]];
  actual = input;
  exp = expected;
  If[SameQ[actual, exp],
    Print["PASS ", id],
    Print["FAIL ", id, " | actual: ", ToString[actual, InputForm], " | expected: ", ToString[exp, InputForm]]
  ]
];
$TestFileName = "@TESTFILE@";
'''

INSTALL_OLD = 'HoldPattern[target[args___]] /; ! TrueQ[$InsideDispatch[Hold[target]]] :>'
INSTALL_NEW = 'HoldPattern[target[args___] /; ! TrueQ[$InsideDispatch[Hold[target]]]] :>'

NESTED_OLD = '''  AppendTo[$Registry[key, combinator], AdviceObj[adviceFunc, priority]];
  $Registry[key, combinator] = SortBy[$Registry[key, combinator], Last];'''
NESTED_NEW = '''  $Registry[key] = Append[$Registry[key],
    combinator -> SortBy[Append[$Registry[key, combinator], AdviceObj[adviceFunc, priority]], Last]];'''


def test_id(chunk):
    m = re.search(r'TestID\s*->\s*"([^"]+)"', chunk)
    return m.group(1) if m else "?"


def run_mode(mode, workdir):
    libdir = Path(workdir) / mode
    libdir.mkdir()
    src = (REPO / "Advices.wl").read_text()
    if mode in ("install-form", "portable"):
        assert INSTALL_OLD in src, "install-form anchor not found; Advices.wl changed"
        src = src.replace(INSTALL_OLD, INSTALL_NEW)
    if mode == "portable":
        assert NESTED_OLD in src, "nested-update anchor not found; Advices.wl changed"
        src = src.replace(NESTED_OLD, NESTED_NEW)
    (libdir / "Advices.wl").write_text(src)
    wlt = (REPO / "Advices.wlt").read_text()
    (libdir / "Advices.wlt").write_text(wlt)
    tests = re.split(r'(?m)^(?=VerificationTest\[)', wlt)[1:]
    load = tests[0]                      # the Load-Advices test; run first every time
    results = []
    for chunk in tests[1:]:
        prog = SHIM.replace("@TESTFILE@", str(libdir / "Advices.wlt")) + load + "\n" + chunk
        path = libdir / "chunk.wls"
        path.write_text(prog)
        try:
            p = subprocess.run([WOXI, "run", str(path)], capture_output=True, text=True,
                               timeout=30, cwd=tempfile.gettempdir())
            out = (p.stdout + "\n" + p.stderr).strip()
        except subprocess.TimeoutExpired:
            out = "TIMEOUT"
        tid = test_id(chunk)
        status, detail = "NOLINE", ""
        for line in out.splitlines():
            if line.startswith("PASS " + tid):
                status = "PASS"
            elif line.startswith("FAIL " + tid):
                status, detail = "FAIL", line[len("FAIL " + tid):].strip(" |")
        msgs = [l for l in out.splitlines()
                if re.search(r'\b\w+::\w+', l) and not l.startswith(("PASS", "FAIL"))]
        if "invcomb" in chunk:           # the 4-argument form lists the message it expects
            if status == "PASS" and not any("invcomb" in m for m in msgs):
                status, detail = "FAIL", "value ok but the expected AdviceAdd::invcomb message was not issued"
            msgs = [m for m in msgs if "invcomb" not in m]
        if status == "PASS" and msgs:
            status = "PASS+MSG"          # real VerificationTest would count this as a failure
        if status == "NOLINE":
            detail = out.replace("\n", " ~ ")[:160]
        results.append((tid, status, detail, msgs))
    return results


def main():
    print(f"woxi: {subprocess.run([WOXI, '--version'], capture_output=True, text=True).stdout.strip()}")
    with tempfile.TemporaryDirectory() as d:
        for mode in ("as-is", "install-form", "portable"):
            res = run_mode(mode, d)
            clean = sum(1 for r in res if r[1] == "PASS")
            msg = sum(1 for r in res if r[1] == "PASS+MSG")
            print(f"\n===== {mode}: {clean} clean passes, {msg} pass-with-messages, "
                  f"{len(res) - clean - msg} other, of {len(res)} tests =====")
            for tid, status, detail, msgs in res:
                extra = f"  {detail[:150]}" if detail else (f"  msg: {msgs[0][:110]}" if msgs else "")
                print(f"  {status:9} {tid:38}{extra}")


main()
