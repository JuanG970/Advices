"""Probe Woxi against standard Wolfram Language behaviour.

Usage:  python3 -I cloud-env/woxi-compat/probes.py [woxi-binary] [1|2|3|4]

Each probe runs in its own `woxi eval -` process, so a crash or hang in one
cannot hide the others. Expected values are what the real Wolfram Engine returns
in InputForm. They come from documented language semantics and from this repo's
own tests (which pass on the real Engine in CI); the real Engine was not
available when these were written. Tiers: 1 everyday functions, 2 evaluator
semantics the dispatcher depends on, 3 package loading, 4 Advices itself.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

WOXI = sys.argv[1] if len(sys.argv) > 1 else "woxi"
TIER = sys.argv[2] if len(sys.argv) > 2 else "all"
ADVICES = str(Path(__file__).resolve().parents[2] / "Advices.wl")

MINI_PKG = '''BeginPackage["Mini`"];
Double::usage = "Double[x] doubles x.";
Begin["`Private`"];
Double[x_] := 2 x;
End[];
EndPackage[];
'''

# (id, code, expected InputForm)
PROBES = [
    # ---- Tier 1: everyday functions Advices and its tests call ------------------
    ("1.01 SetDelayed",      'f[x_] := x^2; f[5]', '25'),
    ("1.02 AppendTo local",  'Module[{l = {}}, AppendTo[l, 1]; AppendTo[l, 2]; l]', '{1, 2}'),
    ("1.03 Association app", '<|"a" -> 1|>["a"]', '1'),
    ("1.04 Lookup default",  'Lookup[<|"a" -> 1|>, "z", 0]', '0'),
    ("1.05 KeyExistsQ",      'KeyExistsQ[<|"a" -> 1|>, "a"]', 'True'),
    ("1.06 KeyDropFrom",     'Module[{a = <|"x" -> 1|>}, KeyDropFrom[a, "x"]; a]', '<||>'),
    ("1.07 SortBy",          'SortBy[{3, 1, 2}, Identity]', '{1, 2, 3}'),
    ("1.08 Fold",            'Fold[Plus, 0, {1, 2, 3}]', '6'),
    ("1.09 AllTrue",         'AllTrue[{1, 2, 3}, # > 0 &]', 'True'),
    ("1.10 DeleteCases",     'DeleteCases[{1, 2, 3, 2}, 2]', '{1, 3}'),
    ("1.11 FreeQ",           'FreeQ[{1, 2}, 3]', 'True'),
    ("1.12 Catch/Throw",     'Catch[Throw[5]]', '5'),
    ("1.13 Attributes",      'MemberQ[Attributes[Plus], Protected]', 'True'),
    ("1.14 Reverse/SortBy",  'Reverse[SortBy[{{1, "a"}, {3, "c"}, {2, "b"}}, First]]',
                             '{{3, "c"}, {2, "b"}, {1, "a"}}'),
    # ---- Tier 2: evaluator semantics the dispatcher depends on ------------------
    ("2.01 HoldFirst",       'SetAttributes[g, HoldFirst]; g[x_] := Hold[x]; g[1 + 1]', 'Hold[1 + 1]'),
    ("2.02 BlankNullSeq",    'h[args___] := {args}; h[1, 2, 3]', '{1, 2, 3}'),
    ("2.03 DownValues read", 'ClearAll[k]; k[x_] := x; DownValues[k]', '{HoldPattern[k[x_]] :> x}'),
    ("2.04 PrependTo DV",    'ClearAll[k]; k[x_] := x; PrependTo[DownValues[k], HoldPattern[k[a___]] :> {a, "intercepted"}]; k[3]',
                             '{3, "intercepted"}'),
    ("2.05 /; definitions",  'ClearAll[m]; m[x_] /; x > 0 := "pos"; m[x_] := "neg"; {m[1], m[-1]}', '{"pos", "neg"}'),
    ("2.06 ReleaseHold",     'ReleaseHold[Hold[1 + 1]]', '2'),
    ("2.07 Return in def",   'r[] := Module[{}, Return[7]; 8]; r[]', '7'),
    ("2.08 HoldPattern arg", 'ClearAll[t]; SetAttributes[t, HoldFirst]; t[HoldPattern[s_Symbol]] := Hold[s]; t[zz]', 'Hold[zz]'),
    ("2.09 conditional DV",  'ClearAll[c]; c[x_] := x; PrependTo[DownValues[c], HoldPattern[c[args___]] /; ! TrueQ[flag] :> {"d", args}]; {c[1], (flag = True; c[1])}',
                             '{{"d", 1}, 1}'),
    ("2.10 assoc Hold key",  'Module[{a = <||>}, a[Hold[x]] = <|"k" -> {1}|>; a[Hold[x]]["k"]]', '{1}'),
    ("2.11 Hold[args___]",   'ClearAll[d]; SetAttributes[d, HoldFirst]; d[t_Symbol, Hold[args___]] := {Hold[args]}; d[q, Hold[1 + 1, 2]]',
                             '{Hold[1 + 1, 2]}'),
    ("2.12 DV delete rule",  'ClearAll[e2]; e2[x_] := x + 1; PrependTo[DownValues[e2], HoldPattern[e2[a___]] :> Disp[a]]; DownValues[e2] = DeleteCases[DownValues[e2], _[_, Disp[___]]]; e2[1]',
                             '2'),
    ("2.13 type patterns",   'ClearAll[p]; p[x_Integer] := "int"; p[x_] := "other"; {p[1], p["a"]}', '{"int", "other"}'),
    ("2.14 Check/Quiet msg", 'Quiet[Check[Message[General::stop, "x"]; 1, 2]]', '2'),
    # ---- Tier 3: package machinery ------------------------------------------------
    ("3.01 Get a package",   'Get["@PKG@"]; Mini`Double[4]', '8'),
    ("3.02 ::usage",         'Get["@PKG@"]; Mini`Double::usage', '"Double[x] doubles x."'),
    ("3.03 Context restored", 'Get["@PKG@"]; Context[]', '"Global`"'),
    # ---- Tier 4: Advices itself ---------------------------------------------------
    ("4.01 Get Advices.wl",  'Get["@ADV@"]; Head[Advices`AdviceAdd]', 'Symbol'),
    ("4.02 Test1 scenario",
     'Get["@ADV@"]; Module[{calls = {}, myFunc}, myFunc[x_] := (AppendTo[calls, {"inner", x}]; x^2); '
     'logBefore[args___] := AppendTo[calls, {"Before", {args}}]; logAfter[args___] := AppendTo[calls, {"After", {args}}]; '
     'AdviceAdd[myFunc, "Before", logBefore]; AdviceAdd[myFunc, "After", logAfter]; AdviceAdd[myFunc, "Before", logBefore]; '
     'myFunc[5]; AdviceClear[myFunc]; calls]',
     '{{"Before", {5}}, {"inner", 5}, {"After", {5}}}'),
]


def run(code, pkg_path):
    src = code.replace("@PKG@", pkg_path).replace("@ADV@", ADVICES)
    src = "zzRes = (" + src + "); ToString[zzRes, InputForm]"
    try:
        p = subprocess.run([WOXI, "eval", "-"], input=src, capture_output=True,
                           text=True, timeout=30, cwd=tempfile.gettempdir())
    except subprocess.TimeoutExpired:
        return "TIMEOUT", ""
    return p.stdout.strip(), p.stderr.strip()


def main():
    print(f"woxi: {subprocess.run([WOXI, '--version'], capture_output=True, text=True).stdout.strip()}")
    passed = failed = 0
    with tempfile.TemporaryDirectory() as d:
        pkg = os.path.join(d, "Mini.wl")
        Path(pkg).write_text(MINI_PKG)
        for pid, code, expected in PROBES:
            if TIER != "all" and not pid.startswith(TIER + "."):
                continue
            out, err = run(code, pkg)
            if out == expected:
                passed += 1
                print(f"PASS  {pid}")
            else:
                failed += 1
                print(f"FAIL  {pid:22} got={out[:90]!r}  expected={expected[:60]!r}")
                if err:
                    print(f"        stderr: {err.splitlines()[0][:150]}")
    print(f"\n{passed} passed, {failed} failed, of {passed + failed}")


main()
