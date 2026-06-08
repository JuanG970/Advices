(* ::Title:: Test runner — invokes TestReport on Advices.wlt and exits non-zero on failure *)

report = TestReport[
  Get[FileNameJoin[{DirectoryName[$InputFileName], "..", "Advices.wlt"}]]
];

(* A TestReportObject is its own Association-like thing; use its accessor methods. *)
succeeded     = Length[report["TestsSucceededKeys"]];
failedWrong   = Length[report["TestsFailedWrongResultsKeys"]];
failedMsgs    = Length[report["TestsFailedWithMessagesKeys"]];
failedErrors  = Length[report["TestsFailedWithErrorsKeys"]];
totalFailed   = failedWrong + failedMsgs + failedErrors;
total         = totalFailed + succeeded;

Print[""];
Print[StringRepeat["=", 60]];
Print["  Advices.wl — Test Report"];
Print[StringRepeat["=", 60]];
Print["  Total:      ", total];
Print["  Passed:     ", succeeded];
Print["  Failed:     ", totalFailed];
Print["    (wrong):  ", failedWrong];
Print["    (msgs):   ", failedMsgs];
Print["    (errors): ", failedErrors];
Print[StringRepeat["=", 60]];

If[totalFailed > 0,
  Print[""];
  Print["FAILED TESTS:"];
  testResults = report["TestResults"];
  Do[
    Print[""];
    Print["  --- ", k, "  [", bucketName, "] ---"];
    Print["  TestID:    ", Lookup[testResults[k], "TestID",        "?"]];
    Print["  Outcome:   ", Lookup[testResults[k], "Outcome",        "?"]];
    Print["  Expected:  ", Lookup[testResults[k], "ExpectedOutput", "?"]];
    Print["  Actual:    ", Lookup[testResults[k], "ActualOutput",   "?"]];
  ,
    {bucketName, keyList} = {
      {"WrongResults", report["TestsFailedWrongResultsKeys"]},
      {"Messages",     report["TestsFailedWithMessagesKeys"]},
      {"Errors",       report["TestsFailedWithErrorsKeys"]}
    };
    {k, keyList}
  ];
  Exit[1]
];

Print["All tests passed."];
Exit[0]
