# Advices — Wolfram Language paclet
#
# This repo is literate-Org-first. The .org files are the source of truth;
# the .wl / .wlt files are produced by org-babel-tangle and committed to
# the repo so GitHub renders the code natively. If you edit a .wl/.wlt
# directly, your changes will be wiped on the next `make tangle`.
#
# Workflow:
#   1. Edit the .org in Doom (or any editor)
#   2. make tangle           # regenerates Advices.wl + Advices.wlt
#   3. make verify           # runs the test suite via wolframscript
#   4. git diff .wl .wlt     # review what changed
#   5. git commit -am ...
#
# To bootstrap org-tangle without Doom, the Makefile invokes
# `emacs --batch` with a small init file (scripts/emacs-tangle.el) that
# loads `org` and runs `org-babel-tangle-file`. The init file does NOT
# load your personal config — it's hermetic, headless, no GUI.
#
# Requires: emacs-nox, wolframscript (Wolfram Engine 13+).

.PHONY: tangle verify test check clean help

# The two literate sources and their tangle targets.
ORGS := Implementation.org Tests.org

help:
	@echo "make tangle   - regenerate .wl/.wlt from .org via emacs org-babel"
	@echo "make verify   - regenerate + run the Wolfram test suite"
	@echo "make test     - run the Wolfram test suite only (no regen)"
	@echo "make check    - regen + test + verify .wl/.wlt are in sync w/ .org"
	@echo "make clean    - remove the tangled .wl/.wlt (forces fresh regen)"
	@echo ""
	@echo "Sources:  $(ORGS)"
	@echo "Targets:  Advices.wl  (from Implementation.org)"
	@echo "          Advices.wlt (from Tests.org)"

# Tangle every .org that declares a tangle target. Re-running on an
# unchanged .org is cheap — emacs rewrites the file, git diff shows no
# change.
tangle:
	@for org in $(ORGS); do \
		echo "  tangle: $$org"; \
		emacs --batch --load scripts/emacs-tangle.el \
		      --eval "(org-babel-tangle-file \"$$org\")" 2>&1 \
		      | tail -2 || exit 1; \
	done
	@echo "tangle complete. Run 'make verify' to test."

# Tangle then run the test suite. If tangle changes anything, this
# catches it before you commit.
verify: tangle
	@wolframscript -script scripts/run-tests.wls

# Just run tests (assumes .wl/.wlt are in sync).
test:
	@wolframscript -script scripts/run-tests.wls

# Drop the tangled outputs. Next `make tangle` rebuilds them from .org.
clean:
	@rm -f Advices.wl Advices.wlt
	@echo "removed Advices.wl, Advices.wlt (rebuild with 'make tangle')"

# CI gate: tangle, then run tests, then check that the tangled output
# matches the committed file. Catches the case where someone edited the
# .wl directly (or the .org was edited but the .wl wasn't regenerated).
# Skipped gracefully if the repo isn't a git checkout.
check: tangle test
	@if [ -d .git ]; then \
		echo ""; \
		echo "[check] verifying Advices.wl/.wlt are in sync with .org..."; \
		if git diff --quiet -- Advices.wl Advices.wlt; then \
			echo "[check] OK -- committed outputs match freshly tangled outputs."; \
		else \
			echo ""; \
			echo "[check] FAILED -- committed .wl/.wlt differ from tangle output."; \
			echo "         Run 'make tangle' and commit the result."; \
			git diff --stat -- Advices.wl Advices.wlt; \
			exit 1; \
		fi; \
	else \
		echo "[check] not a git repo -- skipping sync check."; \
	fi
