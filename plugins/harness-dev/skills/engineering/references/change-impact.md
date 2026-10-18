# Prove the assumptions outside the diff

Read the intended behavior change and its actual base-to-head diff. Follow changed and deleted symbols into callers, configuration, serialized data, generated artifacts and dependency boundaries. A symbol search misses consumers in another language, stored state, wire formats and teardown timing. Check the dependency version and relevant implementation when safety depends on a library's behavior.

Find the one or two facts the safety argument actually needs. For example, does uninstall preserve a consumer's settings, or does cleanup leave proof files intact? State a counterexample that would break each fact, then choose the cheapest observation that could expose it.

Rank the evidence honestly: a statement, a cited implementation, a traced unreachable failure, execution of the real code, or reproduction through the running product. Do not claim one level from evidence at another. Reuse a regression test or a small script that invokes the shipped boundary. Give the probe a failing case or positive control where practical so an observation that sees nothing cannot count as proof.

Report confirmed risks separately from cases checked and cleared. Each material risk needs a reachable failure, source location, expected impact and a check. Do not invent callers, probabilities or a panel of reviewers. A missing environment or unexercised platform remains a coverage limit.

Finish with the safety fact, command and result, revision and artifact path. When the deciding fact is unproven, say which claim remains unsupported and what observation would settle it. A long list of plausible concerns is not a substitute for testing the fact that decides the change.
