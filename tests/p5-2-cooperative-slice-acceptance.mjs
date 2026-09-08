import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";

const browser = await chromium.launch({ headless: true });
try {
  const page = await browser.newPage();
  await page.goto(pathToFileURL(path.resolve("index.html")).href);
  await page.waitForFunction(() => window.AstraLifeP5 && window.AstraLifeP52);
  const result = await page.evaluate(() => {
    AstraColony.reset("P5.2-TEAM-03-SHELTER-20260908");
    runtime.state.running = false;
    const p5 = window.AstraLifeP5;
    const p52 = window.AstraLifeP52;
    const [proposer, worker, offerOnly] = runtime.state.agents.slice(0, 3);
    for (const agent of [proposer, worker, offerOnly]) {
      agent.body.x = runtime.state.camp.x;
      agent.body.y = runtime.state.camp.y;
    }
    runtime.state.stock.wood = CONFIG.buildWoodCost;
    runtime.state.camp.shelter = 0;
    runtime.state.camp.construction = { active: false, progress: 0, startedTick: 0, crew: [] };

    const originalGoals = new Map([proposer, worker, offerOnly].map(agent => [agent.id, agent.mind.goal]));
    const offerOnlySkillBefore = cloneJson(offerOnly.development.skills.building);
    const offerOnlyRepBefore = offerOnly.development.domainReputation.building;

    const proposal = p52.createShelterProposal({
      taskId: "team03:shelter",
      proposerId: proposer.id,
      memberIds: [worker.id, offerOnly.id],
      requiredMembers: 2,
      deadlineTick: 100
    });
    const workerAccepted = p5.accept("team03:shelter", worker.id);
    const offerOnlyAccepted = p5.accept("team03:shelter", offerOnly.id);
    const acceptOnlyScenario = p52.getScenario("team03:shelter");
    const acceptOnlyNotCompletion = acceptOnlyScenario.state !== "COMPLETED" && runtime.state.camp.shelter === 0;
    const started = p52.startShelter("team03:shelter");
    const firstStep = p52.performResolverActions("team03:shelter", [
      { agentId: proposer.id, type: ACTION.BUILD, payload: {} },
      { agentId: worker.id, type: ACTION.BUILD, payload: {} }
    ]);
    const run = p52.runCommittedShelter("team03:shelter", [proposer.id, worker.id], { maxRounds: 100 });
    const scenario = p52.getScenario("team03:shelter");
    const task = p5.getTask("team03:shelter");
    const snapshot = runtime.snapshot();
    const integrity = p52.selfTest();
    const runtimeIntegrity = runtime.selfTest();

    const offerOnlySkillUnchanged = JSON.stringify(offerOnly.development.skills.building) === JSON.stringify(offerOnlySkillBefore);
    const offerOnlyRepUnchanged = offerOnly.development.domainReputation.building === offerOnlyRepBefore;
    const goalChanges = [proposer, worker, offerOnly].filter(agent => agent.mind.goal !== originalGoals.get(agent.id)).map(agent => agent.id);
    const confirmedIds = scenario?.completionEvidence?.contributorIds || [];
    const successfulResolverOutcomes = scenario?.confirmedContributions?.filter(item => item.resolverConfirmed === true) || [];
    const tests = {
      proposalCreatesRecruitingScenario: proposal.ok && proposal.scenario.state === "RECRUITING",
      explicitMemberCommitmentsRequired: workerAccepted.ok && offerOnlyAccepted.ok && started.ok,
      proposalAndAcceptAreNotCompletion: acceptOnlyNotCompletion,
      worldConstraintUsesShelterMaterial: runtime.state.stock.wood === 0 && runtime.state.camp.shelter === 1,
      team03ShelterCompleted: run.ok && scenario.state === "COMPLETED" && task.state === "COMPLETED",
      resolverConfirmedContributionRequired: successfulResolverOutcomes.length >= 2 && confirmedIds.includes(proposer.id) && confirmedIds.includes(worker.id),
      offerRecipientSeparatedFromRealParticipant: scenario.offeredMemberIds.includes(offerOnly.id) && scenario.acceptedMemberIds.includes(offerOnly.id) && !confirmedIds.includes(offerOnly.id),
      noHiddenTeamBonus: scenario.teamBonus === 0 && scenario.bonusApplied === false && scenario.completionEvidence.noHiddenTeamBonus === true,
      noOfferOnlySkillOrReputationCredit: offerOnlySkillUnchanged && offerOnlyRepUnchanged,
      coordinatorDidNotOverwriteGoals: goalChanges.length === 0 && scenario.completionEvidence.goalChanges.length === 0,
      noDanglingReservation: p5.snapshot().reservations.every(reservation => reservation.status !== "ACTIVE"),
      cooperativeEvidenceExported: snapshot.cooperativeSlice?.scenarios?.some(item => item.taskId === "team03:shelter" && item.completionEvidence?.resolverConfirmed) === true,
      protocolAndRuntimeIntegrity: integrity.ok && runtimeIntegrity.ok
    };
    return { ok: Object.values(tests).every(Boolean), tests, summary: { proposal: proposal.ok, acceptedMembers: [workerAccepted.ok, offerOnlyAccepted.ok].filter(Boolean).length, start: started.ok, rounds: run.rounds.length, shelter: runtime.state.camp.shelter, woodRemaining: runtime.state.stock.wood, confirmedContributorIds: scenario.confirmedContributorIds, offeredMemberIds: scenario.offeredMemberIds, goalChanges, noHiddenTeamBonus: scenario.completionEvidence.noHiddenTeamBonus, noDanglingReservation: p5.snapshot().reservations.every(reservation => reservation.status !== "ACTIVE") }, integrity, runtimeIntegrity, offerOnlySkillUnchanged, offerOnlyRepUnchanged };
  });
  console.log(JSON.stringify(result, null, 2));
  if (!result.ok) process.exitCode = 1;
} finally {
  await browser.close();
}
