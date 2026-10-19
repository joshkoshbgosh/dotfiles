## MODIFIED Requirements

### Requirement: Existing rollout safety remains intact
Portfolio review, project proofs, scenarios, negotiation results, candidate generation, and candidate manipulation SHALL remain shadow evidence and MUST NOT replace heuristic
overlays, write timestamps, change task or project metadata, modify calendars, or
schedule work. The sole write boundary SHALL be explicit complete
schedule-candidate acceptance, or its bounded guarded restore, which MUST validate
the current snapshot and plan-level source fingerprint and atomically replace
only the machine-owned future plan in `planning.org`.

#### Scenario: Review completes successfully
- **WHEN** project or portfolio analysis returns feasible placements without explicit draft acceptance
- **THEN** all placements remain virtual and existing Org content is byte-for-byte unchanged

#### Scenario: Candidate is manipulated
- **WHEN** the user places, excludes, or re-estimates proposed work
- **THEN** the changes remain transient shadow overlays and no authoritative source is modified

#### Scenario: Guarded acceptance is requested
- **WHEN** the user explicitly accepts a complete current verified candidate
- **THEN** only the acceptance boundary may atomically replace the machine-owned future plan after all freshness and conflict checks pass

#### Scenario: Acceptance validation fails
- **WHEN** the draft or any authoritative source is stale, mismatched, conflicting, or unverified
- **THEN** the write boundary refuses the complete transaction and Org remains byte-for-byte unchanged
