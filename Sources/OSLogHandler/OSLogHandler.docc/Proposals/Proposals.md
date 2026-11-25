# Proposals

Collaborate on API changes to Swift Log OSLog by writing a proposal.

## Overview

For non-trivial changes that affect the public API, the Swift Log OSLog project adopts a lightweight version of the
[Swift Evolution](https://github.com/apple/swift-evolution/blob/main/process.md) process.

The process covers the whole `swift-log-oslog` package. This includes the `OSLogHandler` target and the
`SensitivityAttribute` target. The `SensitivityAttribute` target contains `Sensitivity`, `RedactionLogHandler`, and the
`package` code that `OSLogHandler` uses to split and cache metadata.

Writing a proposal first helps discuss multiple possible solutions early, apply useful feedback from other
contributors, and avoid reimplementing the same feature multiple times.

While it's encouraged to get feedback by opening a pull request with a proposal early in the process, it's also
important to consider the complexity of the implementation when evaluating different solutions. For example, this might
mean including a link to a branch containing a prototype implementation of the feature in the pull request description.

> Note: The goal of this process is to help solicit feedback from the whole community around the project, and we will
> continue to refine the proposal process itself. Use your best judgement, and don't hesitate to propose changes to the
> proposal structure itself!

### Steps

1. Make sure there's a GitHub issue for the feature or change you would like to propose.
2. Duplicate the `SLGO-NNNN.md` document and replace `NNNN` with the next available proposal number.
3. Link the GitHub issue from your proposal, and fill in the proposal.
4. Open a pull request with your proposal and solicit feedback from other contributors.
5. Once a maintainer confirms that the proposal is ready for review, the state is updated accordingly. The review
   period is 7 days, and ends when one of the maintainers marks the proposal as Ready for Implementation, or Deferred.
6. Before the pull request is merged, there should be an implementation ready, either in the same pull request, or a
   separate one, linked from the proposal.
7. The proposal is considered Approved once the implementation and proposal pull requests have been merged.

If you have any questions, ask in an issue on GitHub.

### Possible review states

- Awaiting Review
- In Review
- Ready for Implementation
- In Preview
- Approved
- Deferred

## Topics

### Proposal template

- <doc:SLGO-NNNN>

### Feature proposals

- <doc:SLGO-0001-json-metadata-format>
