# EVPN Gateway Appliance (EGA) — productization critical path

Baseline checked 2026-09-29 from Jira (CORENET-7400 and its children, PLMPGM-6293, RELENG-503/589/596);
RELENG-596's status rechecked 2026-10-08.
These are the requests that take calendar time from other teams. Start the applicable
requests alongside small source-CI changes; confirm the product home before requesting
identities or processes already owned by an existing offering. They do not gate source lint. Dates are the tickets' own; the
plan's owners are proposals. [Decisions](kickoff-decisions.md) lists the inputs to settle,
and [source evidence](source-evidence.md#10-production-identity-precedents) records the
repository-side precedents (KRD `prodsec` test, product-definitions, advisories).

## The template is for operators

BGP Cloud Connector followed PLMPGM-6293, "Productization - Konflux (EPIC) Template": twelve
numbered tasks for an OLM operator, cloned with the Jira UI Clone dialog (not the API, which
loses the child tasks) and dated to GA at about start + 60 days. CORENET-7400 is that clone.
The September 29 survey found no EVPN productization epic; confirm current onboarding with PM.

| Template task | Applies to EGA? |
| --- | --- |
| 01 Operations Readiness Form (branding, export compliance, SKU), 02 Privacy Impact Assessment, 03 ProdSec onboarding and RH-SDL, 08 Eng ID → SKU, 10 QE, 11 docs | Confirm applicability and existing coverage with the offering owners; retain the required approvals and QE/docs outcomes, without duplicating completed onboarding |
| 04 Jira project | Skip: CORENET exists. Ask for an OCPBUGS component or other bug home for customers |
| 05 Cicada | Partly: the bootc repository fits. Bundle repositories and `fbc_opt_in` do not. Disk downloads and any Hub or AMI channel have no template task ([channels](bib-configuration-spec.md#customer-delivery-channels)) |
| 06 Konflux | Yes, with the [artifact graph](pipeline-spec.md#artifact-graph-and-candidate-integrity) in place of operator, bundle and FBC |
| 07 Multi-version FBC | No. BGP Cloud Connector skipped it too (rolling stream, one ReleasePlan and RPA) |
| 09 Operator lifecycle, 12 GA (OperatorHub, Master Operators List) | Adapt: an appliance needs a lifecycle-page entry and support tier, not OperatorHub visibility |

The other PLMPGM template, for Agentic/Applied AI products, adds AI-specific prerequisites
(model, MCP, guardrails) and does not fit, so ask Program Management how a non-operator
product is onboarded. The operator template's export-compliance task adds an operator to the OCP
EARF document; ask the export team which section covers a bootc appliance and collection.

## Measured path: BGP Cloud Connector

| Step | Dates | Elapsed | Note |
| --- | --- | --- | --- |
| Repository created, Eng ID requested (RELENG-503), RPA merge request opened | Jul 30 | — | The request linked its draft RPA MR; short name recorded as "No short name was approved" |
| Template cloned; Jira project (7401) | Aug 4 | same day | |
| PIA (7406) | Aug 4 → 6 | 2 days | The template quotes 10 business days to get a reviewer and 2–3 weeks or more |
| Eng ID 1209 assigned | Aug 11 | 12 days | Through a merge request to the product-service configuration repository |
| Delivery repositories created as Tech Preview (Cicada) | Aug 12 | | Promoted to GA with the `1.0` content stream Aug 31 |
| Export authorization form submitted | Aug 13 | | The form's request showed no activity by Sep 16, so clearance stayed unconfirmed; ask the export team for an explicit answer before GA |
| First stage advisories; Konflux onboarding closed (7409) | Aug 17–19 | 18–20 days after repository | Tenant, RPAs, ReleasePlans, `prodsec` template (KRD !21378), 14 stage RHBAs by closure |
| Eng ID → SKU mapping requested (7402) | Aug 24 → Sep 17 | 24 days | The owner was told 2–3 weeks; it reached Offering Manager on Sep 28 and did not block GA |
| Product listing merge request | Sep 10 | | Done by direct MR; Cicada was not used |
| ProdSec and RH-SDL (7410, tracked in SSE-7659) | Aug 6 → Sep 17 | 42 days | Assigned to a ProdSec engineer; the CPE request starts here |
| First production advisory (2026:67519) | Sep 15 | 47 days after repository | |
| GA tasks closed (7403); catalog listing linked | Sep 28 | | Lifecycle enablement (PLMCORE-17446) still In Progress; FBC 5.0 builds fail to inject lifecycle data |

Reading the timeline:

- **Konflux work overlapped the approvals.** Stage releases ran from Aug 17 while the
  export form, SKU mapping and SDL were open. This timeline does not prove each
  approval blocked production: SKU mapping trailed GA and export clearance was
  unconfirmed. Obtain EGA's explicit release requirements from the responsible owners.
- **The Operations Readiness task closed after the Eng ID existed** (Sep 28 against Aug 11),
  and RELENG-503 records no name approvals: its marketing, branding/legal and program-manager
  boxes are unchecked, with marketing marked "Not needed for operators". RELENG-589, a
  non-operator product, had all three checked. The internal Engineering ID guide still says
  name approval comes first for a new identity. If EGA needs a separate offering, confirm its
  required approvals with PM; the precedent shows the ID request need not wait for the form's closure.
- **A draft RPA can carry the request.** RELENG-589 (Sep 15 → 25, 10 days) linked a draft
  RPA MR with placeholder product ID, advisory metadata and Pyxis paths; the reviewer also
  asked whether its proposed short name, already approved by the brand team, collided with an
  existing certification name. Check the proposed short name for collisions before filing.
- **A product without its own SKU still needs an Eng ID** to publish through Pyxis
  (RELENG-596, a bootc product, reopened Sep 28 and Closed as of Oct 8). If EGA rides an
  existing offering, decide that in the [product-home row](kickoff-decisions.md) first;
  it selects whose ID, CPE and stream apply.
- **Late-arriving records are non-blocking only if PM says so.** SKU mapping and lifecycle
  enablement trailed GA for BGP Cloud Connector; record the same call for EGA explicitly.

## How an Engineering ID is created

Checked against the releng SOP for it (internal `konflux/docs/sop`,
[`releng/engineering-id-creation.md`](https://gitlab.cee.redhat.com/konflux/docs/sop/-/blob/f4f0e13/releng/engineering-id-creation.md),
`f4f0e13`). File the request with the RELENG-345 Jira template. Releng will not open the change
until two things are on the ticket: Legal/Branding approval of the product name and short name,
in the exact spelling and capitalization to be used, and Product Management's acknowledgment
that a separate Engineering ID is needed. The second ties to the
[product-home decision](kickoff-decisions.md): a product that rides an existing offering may not
get a separate ID, though publishing through Pyxis still needs one (RELENG-596). The change is a
merge request adding `cloud/<short-name>/<short-name>.yaml` to `product-service-config-auto`, with
the name, the **architectures**, the **environments** (stage, prod) and the customer-portal label.
It has no `id` field: the ID is assigned when the merge pipeline runs, and a release engineer who
owns the directory approves. Architectures and environments are entered at request time.
BGP Cloud Connector entered x86_64 only, yet its first advisory (2026:67519) also lists an arm64
operator image, so ask releng whether the entered architectures must match what ships, and settle
EGA's supported architectures before filing.

## Order of work

Confirm the product home and existing coverage first. Start the missing requests below
in parallel as their inputs become ready; reuse the offering's approvals and identities.

1. **PM, now:** official name, short name and brand approval; the Operations Readiness Form;
   the export form, opened at least 30–60 days before the first customer release; the PIA.
2. **Product Security, now:** an assigned engineer, the RH-SDL tracker, the CPE request and a
   product-definitions entry. The KRD `prodsec/<tenant>.yaml` template and every production
   RPA depend on them.
3. **Releng, as the request inputs are ready:** request the Eng ID after name approval,
   PM acknowledgment and architecture/environment choices; tenant creation is not a
   prerequisite in the checked SOP. A draft RPA may accompany the request. Start delivery
   repository/channel requests in parallel; stage ReleasePlans and RPAs need their tenant
   and channel inputs. Disk downloads also need the content set, Pulp and Content Gateway
   requests from [source evidence](source-evidence.md#10-production-identity-precedents).
4. **PM, in parallel:** Eng ID → SKU mapping, lifecycle page, support tier, bug and RFE routing.
