---
name: debug-systematically
description: Diagnose a bug by forming and killing hypotheses with evidence instead of guess-and-patch — use when something fails and the cause is not obvious.
---

# Debug Systematically

Guess-and-patch is how a one-hour bug becomes a one-day bug. The discipline here
is simple: never change code until you can state *why* it is broken.

## When to use

- A test fails and the stack trace does not immediately name the cause.
- Behaviour differs between environments (works locally, fails in CI/prod).
- An intermittent failure you have already "fixed" once.

## When not to use

- The error message names the file, line and cause outright. Just fix it.

## Procedure

1. **Reproduce deterministically first.** A bug you cannot trigger on demand
   cannot be verified as fixed. Spend the time here — it pays back every later
   step. Record the exact command, input and environment.
2. **Capture the actual evidence.** Full stack trace, the real values (not what
   you assume they are), the surrounding log lines, the request/response pair.
   Print the thing. Assumptions are the bug's favourite hiding place.
3. **Write down 3 hypotheses, ranked by prior probability.** Force yourself to
   three — the first is usually the obvious wrong one. Example:
   - H1: the cache returns a stale object after the update
   - H2: the ID is a string on one side and a number on the other
   - H3: two requests race and the second overwrites the first
4. **Design the cheapest test that kills a hypothesis.** The goal of each step
   is *elimination*, not confirmation. A log line that proves H2 false is worth
   more than one that is "consistent with" H1.
5. **Bisect when hypotheses run out.** `git bisect` across commits, or binary
   search the data: halve the input until the failure disappears. Mechanical
   bisection beats staring at code.
6. **Confirm the mechanism before patching.** You should be able to say: "line
   88 passes a string, line 104 compares with `===` against a number, so the
   lookup always misses." That sentence is the finish line for diagnosis.
7. **Fix the cause, then prove it.** Write the failing test *first* if one does
   not exist. Revert the fix and watch the test fail — otherwise you do not
   know the test covers the bug.
8. **Check for siblings.** The same mistake is usually in two other places.
   Grep for the pattern.

## Environment-difference checklist

When it works here and fails there, the difference is almost always one of:

- [ ] Version skew — language, dependency, OS, database
- [ ] Config / environment variables (including ones that are *missing*)
- [ ] Timezone, locale, or filesystem case sensitivity
- [ ] Data — prod has rows your local DB does not (nulls, old formats, scale)
- [ ] Concurrency — prod runs N workers, local runs one
- [ ] Clock and network latency
- [ ] Permissions and credentials

## Anti-patterns

- Changing several things at once, then not knowing which one worked.
- "Adding a null check" without asking why it was null.
- Deleting a failing assertion to make CI green.
- Adding `sleep()` to fix a race. The race is still there, now it is slower.
- Declaring it fixed because it did not reproduce once. Run it twenty times.
