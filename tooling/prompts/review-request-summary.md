Write a concise explanation of the changes represented by the supplied MR evidence.
Help a reviewer understand the behavior, logic, or design that changed.

For global mode, summarize only the selected MR set. Explain a shared outcome when
the evidence supports one. For unrelated changes, name their separate themes.
For per-MR mode, explain only that MR's contribution. Avoid duplicating the global
summary when both modes are requested.

Prefer the supported before/after behavior and its practical effect. Include the
reason for the change only when recorded. Mention architecture, business rules,
interfaces, dependencies, or technology choices when they explain the change.
For a refactor, describe the design or responsibility change without inventing a
user-visible benefit. Distinguish technology choices from stacked MR relationships.

Avoid file inventories, lists of renamed symbols, copied titles, and vague claims
such as improved reliability. Use a technical identifier only when it helps explain
an interface or rule. Do not claim a test passed or a performance gain occurred
unless the supplied evidence supports it for the published change.

Use plain language. Follow the supplied mode's length limit. Return only the
requested summary fields through the supplied output contract. If the evidence
cannot support a meaningful explanation, use the supplied omission mechanism.
