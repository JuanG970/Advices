(* ::Title:: PacletInfo.wl — Advices.wl paclet manifest *)
(* ::Description:: Emacs-style function advising for the Wolfram Language *)

PacletObject[<|
    "Name" -> "Advices",
    "Version" -> "0.1.0",
    "MathematicaVersion" -> "13+",
    "WolframVersion" -> "13+",
    "Description" -> "Emacs-style function advising for the Wolfram Language. Provides \"Before\", \"Around\", and \"After\" combinators with priority-ordered composition and recursion-safe dispatch.",
    "Creator" -> "Cass x JuanG970",
    "Publisher" -> "JuanG970",
    "URL" -> "https://github.com/JuanG970/Advices",
    "Category" -> "Utility",
    "Tags" -> {"advice", "advising", "function-decoration", "combinators", "meta-programming", "emacs"},
    "SystemID" -> "All",
    "Extensions" -> {
        {"Kernel", Context -> "Advices`"},
        {"Documentation", Language -> "English", MainPage -> "README.org"}
    },
    "Kernel" -> {
        "Context" -> "Advices`"
    }
|>]
