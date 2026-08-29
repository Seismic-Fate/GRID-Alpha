---
model-spec-id:
status: Draft            # Draft | Approved | Superseded
statistical-owner:
version:
supersedes:
---

# Model spec — <component name>

Contract before implementation (alpha-spec.md 1.6). This document is authority level 4 and
exists **before** the code that implements it. Equations are approved by the statistical
owner; the implementing agent may not redefine them (alpha-spec.md 1.3).

## Target
The quantity predicted, its units, and its support (e.g. non-negative real, count, probability).
Name the exact stat-vector component or scoring output.

## Inputs
Each feature: source, units, null semantics, as-of rule, and the feature-schema version it
belongs to. Every input must be point-in-time correct — nothing knowable only after lock.

## Equations
The estimator in full, with every symbol defined. Include the objective, any regularization
and its penalty term, and the update rule for online components. Prose is not a substitute.

## Priors
Prior families, hyperparameters, and where they come from. For empirical-Bayes, state what is
pooled over and how the shrinkage weight is derived. For NCAA priors, state the translation
and the low-evidence eligibility rule.

## Constraints
Invariants that must hold: non-negativity, sum-to-team-total allocation, monotonicity,
probability normalization, covariance positive-semi-definiteness. State what happens when a
constraint is violated — never silently clamp.

## Seed policy
Every stochastic path is seeded and reproducible. State the seed source, how it is versioned,
and how it enters the prediction version. Identical inputs must yield identical outputs.

## Tolerances
Numerical error bands for golden tests, with units and the machine/dataset assumptions they
hold under. State absolute vs. relative and the comparison method.

## Reference examples
Worked numeric examples an implementer can verify against by hand or fixture, with expected
outputs to the stated tolerance. These become the golden tests.

## Explanation fields
What the component contributes to the user-facing explanation payload: driver names, units,
sign conventions, and how contributions are attributed.

## Validation and promotion
Backtest design, the metric this component is judged on, and the threshold that gates
promotion. Thresholds are versioned before results are seen (alpha-spec.md 12.7).

## Known limitations
Where the model is expected to be weak, and what would falsify it.
