Write useful reviewer hints from the supplied evidence for the selected MRs.
Each hint must identify something worth inspecting and explain why it matters.

Prefer supported edge cases, compatibility constraints, design tradeoffs, findings,
stack review order, and verification gaps. Choose the most useful hints rather than
covering every MR. Identify the MR or component when a hint applies to only one.

Separate confirmed findings, accepted tradeoffs, unanswered questions, and checks
that did not run. A review question can follow from observed behavior, but do not
present an unverified concern as a defect. Do not describe a fixed historical issue
as a current issue. Include stack ordering only when the evidence supplies it.

Avoid repeating the summary or MR metadata. Do not use generic advice such as
please check the tests. Include test or CI details only when they explain a useful
review focus or limitation. Do not invent risks, deadlines, approvals, or reviewer
obligations. Write to help the reviewer understand, without exaggeration or bait.

Use plain language and at most three bullets totaling 60 words. Return only the
requested note field through the supplied output contract. If no useful hint is
supported, use the supplied omission mechanism instead of generic filler.
