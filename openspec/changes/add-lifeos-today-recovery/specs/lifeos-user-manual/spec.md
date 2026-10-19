## ADDED Requirements

### Requirement: Daily reset and disruption recovery are dashboard-first
The manual SHALL direct users to the Today dashboard as the single starting point
for choosing work, changing today's capacity or work mode, and recovering after a
disruption. The daily reset and recovery guidance SHALL lead with a short
attention-recovery path, expected visible outcomes, and safe fallback actions;
configuration, metadata, and solver troubleshooting SHALL remain secondary unless
their absence blocks every useful next action.

#### Scenario: User starts the day
- **WHEN** the user opens daily reset guidance
- **THEN** the first workflow opens Today, checks or changes today's ephemeral inputs, and chooses or clocks the recommendation before offering deeper planning reports

#### Scenario: Day diverges from the plan
- **WHEN** the user opens missed-block, overrun, reduced-capacity, changed-mode, or urgent-arrival guidance
- **THEN** the first workflow returns to Today, invokes Replan from now, protects commitments, reviews consequences, and explicitly accepts or cancels the revision

#### Scenario: Solver evidence is unavailable
- **WHEN** recovery guidance is followed while solver proof is stale or unavailable
- **THEN** the manual explains the local-only recommendation or recovery fallback without requiring solver repair before useful action

#### Scenario: Missing metadata blocks safe action
- **WHEN** no bounded recommendation or recovery preview can be produced because required task information is missing
- **THEN** the manual directs the user to the smallest specific repair exposed by Today and then back to the daily workflow

### Requirement: Manual distinguishes ephemeral recovery state from durable plans
The manual SHALL explain that daily check-in overrides and pre-schedule-draft
Today plans expire and do not rewrite weekly policy or Org scheduling fields. It
SHALL separately explain that accepted schedule-draft blocks, when that capability
is installed, use its guarded durable acceptance flow.

#### Scenario: User changes remaining capacity
- **WHEN** the user consults the manual before reducing today's usable time
- **THEN** the guidance states that the change applies only to the current local day and does not alter recurring availability

#### Scenario: Schedule drafts are unavailable
- **WHEN** the user follows recovery guidance before adjustable schedule drafts are installed
- **THEN** the manual describes ephemeral Today-plan acceptance and does not instruct the user to use nonexistent draft commands

#### Scenario: Schedule drafts are available
- **WHEN** the user follows recovery guidance with accepted schedule-draft blocks
- **THEN** the manual identifies the guarded draft acceptance boundary and distinguishes accepted blocks from unaccepted proposals
