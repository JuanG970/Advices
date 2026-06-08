(* ::Section:: Test Infrastructure *)
(* ::DO NOT EDIT:: This file is auto-generated from Tests.org.      *)
(*                Edit the .org, then run `make tangle` (Makefile).  *)
(*                See Implementation.org for the code under test.    *)

(* Load the package under test. *)
VerificationTest[
  Block[{dir = DirectoryName[$TestFileName]},
    If[FileExistsQ[FileNameJoin[{dir, "Advices.m"}]],
      Get[FileNameJoin[{dir, "Advices.m"}]],
      Get[FileNameJoin[{dir, "Advices.wl"}]]
    ];
  ],
  Null,
  TestID -> "Load-Advices"
]

(* ::Section:: Test 1 — Basic "before" / "after" *)

VerificationTest[
  Module[{calls = {}, myFunc},
    myFunc[x_] := (AppendTo[calls, {"inner", x}]; x^2);
    logBefore[args___] := AppendTo[calls, {"before", {args}}];
    logAfter[args___]  := AppendTo[calls, {"after", {args}}];
    AdviceAdd[myFunc, "before", logBefore];
    AdviceAdd[myFunc, "after", logAfter];
    AdviceAdd[myFunc, "before", logBefore]; (* idempotent — should not double-fire *)
    myFunc[5];
    AdviceClear[myFunc];
    calls
  ],
  {{"before", {5}}, {"inner", 5}, {"after", {5}}},
  TestID -> "Basic-Before-After"
]

VerificationTest[
  Module[{targetCalc, aroundHook},
    targetCalc[val_] := val + 10;
    aroundHook[origFun_, val_] := If[val < 0,
      -1,
      origFun[val] * 2
    ];
    AdviceAdd[targetCalc, "around", aroundHook];
    {targetCalc[5], targetCalc[-3]}
  ],
  {30, -1},
  TestID -> "Around-Intercept-Bypass"
]

VerificationTest[
  Module[{calls = {}, f, a, b, c},
    f[x_] := x;
    a[args___] := AppendTo[calls, "A"];  (* default priority 50 *)
    b[args___] := AppendTo[calls, "B"];  (* default priority 50 *)
    c[args___] := AppendTo[calls, "C"];  (* default priority 50 *)
    AdviceAdd[f, "before", b, 10];
    AdviceAdd[f, "before", a, 20];
    AdviceAdd[f, "before", c, 5];
    f[1];
    AdviceClear[f];
    calls
  ],
  {"C", "B", "A"},
  TestID -> "Priority-Ordering-Lower-First"
]

VerificationTest[
  Module[{calls = {}, f, h1, h2, h3},
    f[x_] := (AppendTo[calls, "orig"]; x);
    h1[next_, args___] := (AppendTo[calls, "h1-in"]; next[args] + 1);
    h2[next_, args___] := (AppendTo[calls, "h2-in"]; next[args] * 10);
    h3[next_, args___] := (AppendTo[calls, "h3-in"]; next[args] - 100);
    (* h1, h2, h3 in priority order; around composes with first-added as outermost *)
    AdviceAdd[f, "around", h1, 10];
    AdviceAdd[f, "around", h2, 20];
    AdviceAdd[f, "around", h3, 30];
    result = f[1];
    AdviceClear[f];
    {calls, result}
  ],
  {{"h1-in", "h2-in", "h3-in", "orig"}, -989},
  TestID -> "Around-Chain-Composes"
]

VerificationTest[
  Module[{captured = <||>, f, beforeFn, afterFn},
    f[x_, y_] := x + y;
    beforeFn[args___] := captured["before"] = {args};
    afterFn[args___]  := captured["after"] = {args};
    AdviceAdd[f, "before", beforeFn];
    AdviceAdd[f, "after", afterFn];
    f[3, 4];
    AdviceClear[f];
    {captured["before"], captured["after"]}
  ],
  {{3, 4}, {3, 4}},
  TestID -> "Before-After-See-Same-Args"
]

VerificationTest[
  Module[{calls = {}, f, recurseHook},
    f[0] := 1;
    f[n_Integer?Positive] := n * f[n - 1];
    recurseHook[args___] := (AppendTo[calls, "hook"]; f[2]);
    AdviceAdd[f, "before", recurseHook];
    result = f[3];
    AdviceClear[f];
    {Length[calls], result}
  ],
  {1, 6},
  TestID -> "Recursion-Safety"
]

VerificationTest[
  Module[{myFunc, hook},
    myFunc[x_] := x + 1;
    Protect[myFunc];
    hook[args___] := Null;
    AdviceAdd[myFunc, "before", hook];
    protected1 = MemberQ[Attributes[myFunc], Protected];
    result = myFunc[10];
    AdviceClear[myFunc];
    protected2 = MemberQ[Attributes[myFunc], Protected];
    {protected1, result, protected2}
  ],
  {True, 11, True},
  TestID -> "Protected-Symbol-Round-Trip"
]

VerificationTest[
  Module[{calls = 0, f, hook},
    f[x_] := x;
    hook[args___] := calls++;
    AdviceAdd[f, "before", hook];
    AdviceAdd[f, "before", hook];
    AdviceAdd[f, "before", hook];
    f[1];
    AdviceClear[f];
    calls
  ],
  1,
  TestID -> "Idempotency-Same-Advice-Twice"
]

VerificationTest[
  Module[{calls = {}, f, h1, h2, h3},
    f[x_] := x;
    h1[args___] := AppendTo[calls, "h1"];
    h2[args___] := AppendTo[calls, "h2"];
    h3[args___] := AppendTo[calls, "h3"];
    AdviceAdd[f, "before", h1];
    AdviceAdd[f, "before", h2];
    AdviceAdd[f, "before", h3];
    AdviceRemove[f, h2];
    f[1];
    AdviceClear[f];
    calls
  ],
  {"h1", "h3"},
  TestID -> "AdviceRemove-One-Leaves-Others"
]

VerificationTest[
  Module[{f, neverAdded},
    f[x_] := x;
    neverAdded[args___] := Null;
    AdviceAdd[f, "before", neverAdded];
    AdviceRemove[f, neverAdded];
    AdviceRemove[f, neverAdded]; (* double-remove *)
    result = f[1];
    AdviceClear[f];
    {result, AdviceCount[f]}
  ],
  {1, 0},
  TestID -> "Remove-Non-Existent-Is-No-Op"
]

VerificationTest[
  Module[{calls = {}, f, h1, h2},
    f[x_] := x;
    h1[args___] := AppendTo[calls, "h1"];
    h2[args___] := AppendTo[calls, "h2"];
    AdviceAdd[f, "before", h1];
    AdviceAdd[f, "after", h2];
    AdviceClear[f];
    f[1];
    {calls, AdviceCount[f]}
  ],
  {{}, 0},
  TestID -> "AdviceClear-Fully-Purges"
]

VerificationTest[
  Module[{counter = 0, f, sideEffect, hook},
    f[x_] := x;
    sideEffect := (counter++; Unique[]);
    hook[args___] := {args};
    AdviceAdd[f, "before", hook];
    result = f[sideEffect, sideEffect];
    AdviceClear[f];
    {counter, Length[result]}
  ],
  {2, 2},
  TestID -> "Holding-Boundary-Args-Evaluated-Once"
]

VerificationTest[
  Module[{f, g, fh, gh},
    fHooks = {};
    gHooks = {};
    f[x_] := x + 1;
    g[x_] := x * 2;
    fh[args___] := AppendTo[fHooks, "f-hook"];
    gh[args___] := AppendTo[gHooks, "g-hook"];
    AdviceAdd[f, "before", fh];
    AdviceAdd[g, "before", gh];
    {f[5], g[5]};
    AdviceClear[f];
    AdviceClear[g];
    {fHooks, gHooks}
  ],
  {{"f-hook"}, {"g-hook"}},
  TestID -> "Multiple-Symbols-No-Interference"
]

VerificationTest[
  Module[{f, h1, h2, ds},
    f[x_] := x;
    h1[args___] := Null;
    h2[args___] := Null;
    AdviceAdd[f, "before", h1];
    AdviceAdd[f, "after", h2];
    ds = AdviceList[f];
    AdviceClear[f];
    {Head[ds], AdviceCount[f]}
  ],
  {Dataset, 0},
  TestID -> "AdviceList-Returns-Dataset"
]

VerificationTest[
  Module[{f, h},
    f[x_] := x;
    h[args___] := Null;
    result = AdviceAdd[f, "override", h] (* "override" is not in v0.1 *)
  ],
  $Failed,
  {AdviceAdd::invcomb},
  TestID -> "Invalid-Combinator-Fails"
]
