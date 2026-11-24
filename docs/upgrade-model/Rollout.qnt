module Rollout {
  pure val peers = Set(1, 2)
  pure def prior(id: int): str = if (id == 1) "prior-A" else "prior-B"

  type Node = { booted: str, nextBoot: str, fallback: str, bgp: bool, fabric: bool }
  type State = {
    phase: str, peer: int, baseline: Set[int], copies: Set[int], staged: Set[int],
    servingChecks: Set[int], rejectedStage: str, healthyAtCheck: Set[int], passed: Set[int], rejected: Set[int], nodes: int -> Node
  }
  var s: State

  pure def initialNode(id: int): Node =
    { booted: prior(id), nextBoot: "none", fallback: "none", bgp: true, fabric: true }

  action init = s' = {
    phase: "preflight", peer: 1, baseline: Set(), copies: Set(), staged: Set(),
    servingChecks: Set(), rejectedStage: "none", healthyAtCheck: Set(), passed: Set(), rejected: Set(), nodes: peers.mapBy(id => initialNode(id))
  }

  val p = s.peer
  val n = s.nodes.get(p)
  pure def update(st: State, id: int, node: Node): State =
    { ...st, nodes: st.nodes.set(id, node) }
  val terminal = Set("done", "recovered", "stopped", "cancelled").contains(s.phase)

  action preflight = all {
    s.phase == "preflight",
    nondet id = peers.exclude(s.baseline).oneOf()
    s' = { ...s, baseline: s.baseline.union(Set(id)) }
  }

  action distribute = all {
    s.phase == "preflight", s.baseline == peers,
    s' = { ...s, phase: "distribute" }
  }

  action verifyCopy = all {
    s.phase == "distribute",
    nondet id = peers.exclude(s.copies).oneOf()
    s' = { ...s, copies: s.copies.union(Set(id)) }
  }

  val serving = s.nodes.get(3 - p)
  val beforeGate = Set("distribute", "handoff").contains(s.phase) and s.copies == peers

  action checkServing = all {
    beforeGate, serving.bgp and serving.fabric,
    s' = { ...s, phase: "ready", servingChecks: s.servingChecks.union(Set(p)) }
  }

  action loseServingBgp = all {
    beforeGate or s.phase == "ready", serving.bgp,
    s' = update(s, 3 - p, { ...serving, bgp: false })
  }

  action stage = all {
    s.phase == "ready",
    nondet observed = Set("candidate", "unrelated").oneOf()
    s' = update({ ...s, phase: "stageCheck", staged: s.staged.union(Set(p)) }, p,
                { ...n, nextBoot: observed })
  }

  action validateStage = all {
    s.phase == "stageCheck", n.nextBoot == "candidate", n.booted == prior(p),
    s' = { ...s, phase: "staged" }
  }

  action rejectStage = all {
    s.phase == "stageCheck",
    s' = { ...s, phase: "cancel", rejectedStage: n.nextBoot }
  }

  action cancelOwnedStage = all {
    s.phase == "cancel", n.nextBoot == "candidate", n.booted == prior(p),
    s' = update({ ...s, phase: "cancelled" }, p, { ...n, nextBoot: "none" })
  }

  action bootCandidate = all {
    s.phase == "staged", n.nextBoot == "candidate",
    nondet observed = Set(n.nextBoot, "unexpected").oneOf()
    nondet slot = Set(n.booted, "unexpected").oneOf()
    s' = update({ ...s, phase: "inspect" }, p,
                { booted: observed, nextBoot: "none", fallback: slot, bgp: false, fabric: false })
  }

  action inspect = all {
    s.phase == "inspect", n.booted == "candidate", n.fallback == prior(p),
    nondet bgpUp = Set(true, false).oneOf()
    nondet fabricUp = Set(true, false).oneOf()
    val evidence = if (bgpUp and fabricUp) s.healthyAtCheck.union(Set(p)) else s.healthyAtCheck
    s' = update({ ...s, phase: "validate", healthyAtCheck: evidence }, p,
                { ...n, bgp: bgpUp, fabric: fabricUp })
  }

  action accept = all {
    s.phase == "validate", n.bgp and n.fabric,
    s' = { ...s, passed: s.passed.union(Set(p)), peer: 2,
           phase: if (p == 1) "handoff" else "done" }
  }

  action reject = all {
    s.phase == "validate", not(n.bgp and n.fabric),
    s' = { ...s, phase: "rescue", rejected: s.rejected.union(Set(p)) }
  }

  action loseRollbackSlot = all {
    s.phase == "rescue", n.fallback == prior(p),
    s' = update(s, p, { ...n, fallback: "unexpected" })
  }

  action queuePrior = all {
    s.phase == "rescue", n.booted == "candidate", n.fallback == prior(p), n.nextBoot == "none",
    s' = update({ ...s, phase: "queued" }, p, { ...n, nextBoot: n.fallback })
  }

  action observeRecovery(observed: str, slot: str, bgpUp: bool, fabricUp: bool): bool = all {
    s.phase == "queued", n.nextBoot == prior(p),
    s' = update({ ...s, phase: "checkRecovery" }, p,
                { booted: observed, nextBoot: "none", fallback: slot, bgp: bgpUp, fabric: fabricUp })
  }

  action bootPrior = {
    nondet observed = Set(n.nextBoot, "unexpected").oneOf()
    nondet slot = Set(n.booted, "unexpected").oneOf()
    nondet bgpUp = Set(true, false).oneOf()
    nondet fabricUp = Set(true, false).oneOf()
    observeRecovery(observed, slot, bgpUp, fabricUp)
  }

  action confirmRecovery = all {
    s.phase == "checkRecovery", n.booted == prior(p), n.fallback == "candidate", n.bgp and n.fabric,
    s' = { ...s, phase: "recovered" }
  }

  action forward = any {
    preflight, distribute, verifyCopy, stage, bootCandidate, inspect, accept, reject,
    checkServing, loseServingBgp, validateStage, rejectStage, cancelOwnedStage
  }
  action halt = all { not(terminal), s' = { ...s, phase: "stopped" } }
  action step = any {
    forward, loseRollbackSlot, queuePrior, bootPrior, confirmRecovery, halt,
    all { terminal, s' = s }
  }

  val recovering = Set("rescue", "queued", "checkRecovery").contains(s.phase)
  action operationalRecoveryStep = any {
    forward, queuePrior, observeRecovery(n.nextBoot, n.booted, true, true), confirmRecovery,
    all { not(recovering), halt },
    all { terminal, s' = s }
  }

  val fleetBarrier = s.staged.size() == 0 or (s.baseline == peers and s.copies == peers)
  val serialHandoff = not(s.staged.contains(2)) or s.passed.contains(1)
  val stopOnFailure = not(s.rejected.contains(1)) or not(s.staged.contains(2))
  val validAcceptance = s.passed.subseteq(s.healthyAtCheck) and
    s.passed.forall(id => s.nodes.get(id).booted == "candidate" and not(s.rejected.contains(id)))
  val safeRollbackTarget = s.phase != "queued" or n.nextBoot == prior(p)
  val validSuccess = s.phase != "done" or (s.passed == peers and s.rejected.size() == 0)
  val validRecovery = s.phase != "recovered" or
    (s.rejected.contains(p) and n.booted == prior(p) and n.nextBoot == "none" and
      n.fallback == "candidate" and n.bgp and n.fabric)
  val safeCancellation = s.phase != "cancelled" or
    (s.rejectedStage == "candidate" and n.booted == prior(p) and n.nextBoot == "none")
  val observedServing = s.staged.subseteq(s.servingChecks)
  val safety = observedServing and safeCancellation and fleetBarrier and serialHandoff and stopOnFailure and validAcceptance and
    safeRollbackTarget and validSuccess and validRecovery

  val success = s.phase == "done"
  val recoveredA = s.phase == "recovered" and p == 1
  val recoveredB = s.phase == "recovered" and p == 2
  val stillHealthyAtHandoff = not(s.staged.contains(2)) or s.nodes.get(1).bgp
  temporal finishes = weakFair(step, s).implies(eventually(terminal))
  temporal restores = weakFair(operationalRecoveryStep, s).implies(
    leadsTo(s.phase == "rescue", s.phase == "recovered"))
}
