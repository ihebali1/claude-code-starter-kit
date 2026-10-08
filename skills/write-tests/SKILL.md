---
name: write-tests
description: Write tests that actually catch regressions — behaviour over implementation, the right level of the pyramid, and a mutation check that proves they work.
---

# Write Tests

Coverage percentage measures how much code ran, not how much is verified. This
skill is about the second thing.

## When to use

- New feature or bug fix that needs test coverage.
- Existing tests pass but bugs still ship.
- Before a refactor (characterization tests — see `refactor-safely`).

## The single most important rule

> **A test that does not fail when you break the code tests nothing.**

After writing any test: comment out the logic it covers, or invert a condition,
and confirm the test goes red. Then undo. This takes fifteen seconds and
eliminates most worthless tests.

## Procedure

1. **Pick the level deliberately.**
   - **Unit** — pure logic, branches, edge cases. Fast, many.
   - **Integration** — your code plus a real database/queue/filesystem. Where
     most real bugs live. Fewer, slower, worth it.
   - **End-to-end** — a handful of critical user journeys only. Slow and flaky
     by nature; do not build your safety net here.
   Default to the lowest level that can actually catch the bug class you care about.
2. **Test behaviour, not implementation.** Assert on what the caller observes:
   return values, persisted state, messages emitted. Do not assert that a
   private method was called — that test breaks on every refactor and catches
   nothing.
3. **One behaviour per test, named for the behaviour.**
   `returns 404 when the order belongs to another user`, not `test_get_order_2`.
   When it fails at 3am, the name should tell you what broke.
4. **Arrange / Act / Assert, visibly separated.** If the arrange block is 40
   lines, extract a builder — but keep the values that matter to *this* test
   visible in the test body, not buried in a fixture.
5. **Cover the edges, not just the happy path.** For every function:
   empty, one, many · null/undefined · zero and negative · maximum size ·
   duplicate input · unicode and whitespace · the error path.
6. **Mock only what you do not own.** Third-party HTTP, payment providers,
   email. Use the real database (in a container, or transaction-rolled-back).
   Mocking your own repository layer tests your mock, not your code.
7. **Make every test independent.** It must pass alone, in any order, in
   parallel, run twice. See `fix-flaky-test`.

## What to test first when time is limited

1. The bug you just fixed (a regression test, always)
2. Money, auth and data-loss paths
3. Complex branching logic and parsers
4. Boundaries between systems
5. Everything else

Skip: trivial getters, framework behaviour, third-party library internals.

## Checklist

- [ ] Each new test fails when the code under test is broken (verified, not assumed)
- [ ] Test name states the behaviour and the condition
- [ ] No assertions on private methods or call counts of internal functions
- [ ] No sleeps; waits are on conditions
- [ ] Independent: passes alone, in parallel, and twice in a row
- [ ] Error paths covered, not just success
- [ ] For a bug fix: the test fails on the pre-fix commit
- [ ] No test-only branches (`if (process.env.TEST)`) in production code

## Anti-patterns

- Asserting nothing — a test that only checks "it did not throw".
- One giant test covering twelve behaviours; the failure tells you nothing.
- Snapshot tests over large objects, auto-updated when they fail. That is a
  rubber stamp, not a test.
- Chasing a coverage number by testing getters.
- Tests that mirror the implementation line by line — they break on every
  refactor and catch no bugs.
