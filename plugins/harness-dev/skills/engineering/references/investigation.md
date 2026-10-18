# Investigate behavior and rationale

Start at a real user action, command or caller. Trace inputs, transformations, state ownership, outputs and side effects. Explain the relationships that let another engineer navigate the subsystem; an annotated list of functions is not a working model.

For a placement question, identify the invariant each module owns and the callers that would otherwise coordinate it. For a rationale question, code establishes behavior while history and records establish intent. Use targeted log, blame, originating PRs, decisions and linked issues. Follow an older decision when the most recent edit merely preserves it.

Search the evidence categories relevant to the question: source history, issues, design documents, team discussions, runtime signals, exceptions and product measurements. Use connected sources only within the requested scope. Record unavailable or searched-empty categories when they affect the conclusion. Do not search every service to explain a local helper, or mine other projects' conversations.

Keep five kinds of claim distinct:

- **Direct:** a cited record states the reason.
- **Supported:** several cited observations converge on it.
- **Inferred:** an interpretation whose reasoning is stated.
- **Speculative:** one plausible explanation among alternatives.
- **Unknown:** the searched evidence does not settle the question.

Show contradictory records together. A comment, a recent commit or the user's hypothesis is a lead to verify. None proves the original intent by itself. For an impending change, turn the relevant findings into preserve, change, avoid and risk constraints with their sources.

A read-only question ends with the answer, source locations, material unknowns and a recommendation when requested. Keep unrelated fixes as findings. For teaching, lead with the smallest complete explanation and a concrete user journey. Add a diagram when relationships are easier to see; use real screenshots for claims about a running UI. Keep uncertainty when simplifying the language.
