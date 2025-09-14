import { describe, it, expect, beforeEach } from "vitest";
import { stringUtf8CV, uintCV, listCV } from "@stacks/transactions";

const ERR_NOT_AUTHORIZED = 100;
const ERR_INVALID_PARAM = 102;
const ERR_DAO_INACTIVE = 103;
const ERR_MEMBERSHIP_REQUIRED = 104;
const ERR_QUORUM_NOT_MET = 105;
const ERR_VOTING_NOT_ACTIVE = 106;
const ERR_PROPOSAL_NOT_FOUND = 107;
const ERR_INVALID_VOTE = 108;
const ERR_MAX_PROPOSALS_EXCEEDED = 110;
const ERR_INSUFFICIENT_STAKE = 111;

interface Proposal {
  title: string;
  description: string;
  budget: number;
  milestones: number[];
  status: string;
  creator: string;
  timestamp: number;
  votesFor: number;
  votesAgainst: number;
  quorumMet: boolean;
}

interface Vote {
  vote: boolean;
  stake: number;
  timestamp: number;
}

interface Stake {
  amount: number;
  lockedUntil: number;
}

interface Result<T> {
  ok: boolean;
  value: T;
}

class DAOCoreMock {
  state: {
    votingPeriod: number;
    proposalFee: number;
    quorumThreshold: number;
    daoActive: boolean;
    nextProposalId: number;
    maxProposals: number;
    nftContract: string;
    treasuryPrincipal: string;
    proposals: Map<number, Proposal>;
    votes: Map<string, Vote>;
    stakes: Map<string, Stake>;
    stxTransfers: Array<{ amount: number; from: string; to: string }>;
  } = {
    votingPeriod: 1440,
    proposalFee: 100,
    quorumThreshold: 50,
    daoActive: true,
    nextProposalId: 0,
    maxProposals: 1000,
    nftContract: "ST1TESTNFT",
    treasuryPrincipal: "ST1TEST",
    proposals: new Map(),
    votes: new Map(),
    stakes: new Map(),
    stxTransfers: [],
  };
  blockHeight: number = 0;
  caller: string = "ST1TEST";
  nftBalances: Map<string, number> = new Map([["ST1TEST", 1]]);

  constructor() {
    this.reset();
  }

  reset() {
    this.state = {
      votingPeriod: 1440,
      proposalFee: 100,
      quorumThreshold: 50,
      daoActive: true,
      nextProposalId: 0,
      maxProposals: 1000,
      nftContract: "ST1TESTNFT",
      treasuryPrincipal: "ST1TEST",
      proposals: new Map(),
      votes: new Map(),
      stakes: new Map(),
      stxTransfers: [],
    };
    this.blockHeight = 0;
    this.caller = "ST1TEST";
    this.nftBalances = new Map([["ST1TEST", 1]]);
  }

  getBalance(user: string): number {
    return this.nftBalances.get(user) || 0;
  }

  setNFTContract(newNft: string): Result<boolean> {
    if (this.caller !== "ST1OWNER") return { ok: false, value: false };
    this.state.nftContract = newNft;
    return { ok: true, value: true };
  }

  setTreasuryPrincipal(newTreasury: string): Result<boolean> {
    if (this.caller !== "ST1OWNER") return { ok: false, value: false };
    this.state.treasuryPrincipal = newTreasury;
    return { ok: true, value: true };
  }

  updateVotingPeriod(newPeriod: number): Result<boolean> {
    if (this.caller !== "ST1OWNER") return { ok: false, value: false };
    if (newPeriod <= 0) return { ok: false, value: false };
    this.state.votingPeriod = newPeriod;
    return { ok: true, value: true };
  }

  updateProposalFee(newFee: number): Result<boolean> {
    if (this.caller !== "ST1OWNER") return { ok: false, value: false };
    if (newFee < 0) return { ok: false, value: false };
    this.state.proposalFee = newFee;
    return { ok: true, value: true };
  }

  updateQuorumThreshold(newThreshold: number): Result<boolean> {
    if (this.caller !== "ST1OWNER") return { ok: false, value: false };
    if (newThreshold <= 0 || newThreshold > 100) return { ok: false, value: false };
    this.state.quorumThreshold = newThreshold;
    return { ok: true, value: true };
  }

  toggleDAOActive(): Result<boolean> {
    if (this.caller !== "ST1OWNER") return { ok: false, value: false };
    this.state.daoActive = !this.state.daoActive;
    return { ok: true, value: true };
  }

  submitProposal(
    title: string,
    description: string,
    budget: number,
    milestones: number[]
  ): Result<number> {
    if (!this.state.daoActive) return { ok: false, value: ERR_DAO_INACTIVE };
    if (this.getBalance(this.caller) === 0) return { ok: false, value: ERR_MEMBERSHIP_REQUIRED };
    if (this.state.nextProposalId >= this.state.maxProposals) return { ok: false, value: ERR_MAX_PROPOSALS_EXCEEDED };
    if (title.length === 0 || title.length > 200 || description.length === 0 || description.length > 500 || budget <= 0 || milestones.length === 0) return { ok: false, value: ERR_INVALID_PARAM };
    this.state.stxTransfers = [{ amount: this.state.proposalFee, from: this.caller, to: this.state.treasuryPrincipal }];
    const id = this.state.nextProposalId;
    const proposal: Proposal = {
      title,
      description,
      budget,
      milestones,
      status: "pending",
      creator: this.caller,
      timestamp: this.blockHeight,
      votesFor: 0,
      votesAgainst: 0,
      quorumMet: false,
    };
    this.state.proposals.set(id, proposal);
    this.state.nextProposalId++;
    return { ok: true, value: id };
  }

  castVote(proposalId: number, vote: boolean, stakeAmount: number): Result<boolean> {
    if (!this.state.daoActive) return { ok: false, value: false };
    if (this.getBalance(this.caller) === 0) return { ok: false, value: false };
    const proposal = this.state.proposals.get(proposalId);
    if (!proposal) return { ok: false, value: false };
    const voteKey = `${proposalId}-${this.caller}`;
    if (this.state.votes.has(voteKey)) return { ok: false, value: false };
    if (stakeAmount <= 0) return { ok: false, value: false };
    const userStake = this.state.stakes.get(this.caller) || { amount: 0, lockedUntil: 0 };
    if (userStake.amount < stakeAmount) return { ok: false, value: false };
    this.state.votes.set(voteKey, { vote, stake: stakeAmount, timestamp: this.blockHeight });
    this.state.stakes.set(this.caller, { amount: userStake.amount - stakeAmount, lockedUntil: this.blockHeight + this.state.votingPeriod });
    if (vote) {
      proposal.votesFor += 1;
    } else {
      proposal.votesAgainst += 1;
    }
    proposal.quorumMet = (proposal.votesFor + proposal.votesAgainst) >= this.state.quorumThreshold;
    this.state.proposals.set(proposalId, proposal);
    return { ok: true, value: true };
  }

  withdrawStake(): Result<number> {
    if (this.getBalance(this.caller) === 0) return { ok: false, value: ERR_MEMBERSHIP_REQUIRED };
    const userStake = this.state.stakes.get(this.caller);
    if (!userStake) return { ok: false, value: ERR_INVALID_PARAM };
    if (this.blockHeight < userStake.lockedUntil) return { ok: false, value: ERR_INVALID_PARAM };
    const stake = userStake.amount;
    this.state.stakes.delete(this.caller);
    return { ok: true, value: stake };
  }

  finalizeProposal(proposalId: number): Result<boolean> {
    const proposal = this.state.proposals.get(proposalId);
    if (!proposal) return { ok: false, value: false };
    if (proposal.status !== "voting") return { ok: false, value: false };
    const quorum = (proposal.votesFor + proposal.votesAgainst) >= this.state.quorumThreshold;
    if (!quorum) return { ok: false, value: false };
    proposal.status = proposal.votesFor > proposal.votesAgainst ? "approved" : "rejected";
    this.state.proposals.set(proposalId, proposal);
    return { ok: true, value: true };
  }
}

describe("DAOCore", () => {
  let contract: DAOCoreMock;

  beforeEach(() => {
    contract = new DAOCoreMock();
    contract.reset();
  });

  it("submits a proposal successfully", () => {
    const result = contract.submitProposal(
      "Test Proposal",
      "Description",
      1000,
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    );
    expect(result.ok).toBe(true);
    expect(result.value).toBe(0);
    const proposal = contract.state.proposals.get(0);
    expect(proposal?.title).toBe("Test Proposal");
    expect(proposal?.budget).toBe(1000);
    expect(contract.state.stxTransfers).toEqual([{ amount: 100, from: "ST1TEST", to: "ST1TEST" }]);
  });

  it("rejects proposal without membership", () => {
    contract.nftBalances.set("ST1TEST", 0);
    const result = contract.submitProposal(
      "Test Proposal",
      "Description",
      1000,
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    );
    expect(result.ok).toBe(false);
    expect(result.value).toBe(ERR_MEMBERSHIP_REQUIRED);
  });

  it("rejects vote without sufficient stake", () => {
    contract.submitProposal(
      "Test Proposal",
      "Description",
      1000,
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    );
    const result = contract.castVote(0, true, 100);
    expect(result.ok).toBe(false);
    expect(result.value).toBe(false);
  });

  it("rejects finalization without quorum", () => {
    contract.submitProposal(
      "Test Proposal",
      "Description",
      1000,
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    );
    contract.state.proposals.get(0)!.status = "voting";
    const result = contract.finalizeProposal(0);
    expect(result.ok).toBe(false);
    expect(result.value).toBe(false);
  });

  it("withdraws stake after lock period", () => {
    contract.state.stakes.set("ST1TEST", { amount: 100, lockedUntil: 10 });
    contract.blockHeight = 11;
    const result = contract.withdrawStake();
    expect(result.ok).toBe(true);
    expect(result.value).toBe(100);
    expect(contract.state.stakes.has("ST1TEST")).toBe(false);
  });

  it("rejects stake withdrawal during lock", () => {
    contract.state.stakes.set("ST1TEST", { amount: 100, lockedUntil: 20 });
    contract.blockHeight = 15;
    const result = contract.withdrawStake();
    expect(result.ok).toBe(false);
    expect(result.value).toBe(ERR_INVALID_PARAM);
  });

  it("updates voting period successfully", () => {
    contract.caller = "ST1OWNER";
    const result = contract.updateVotingPeriod(2000);
    expect(result.ok).toBe(true);
    expect(result.value).toBe(true);
    expect(contract.state.votingPeriod).toBe(2000);
  });

  it("toggles DAO active", () => {
    contract.caller = "ST1OWNER";
    const result = contract.toggleDAOActive();
    expect(result.ok).toBe(true);
    expect(result.value).toBe(true);
    expect(contract.state.daoActive).toBe(false);
  });

  it("parses Clarity types correctly", () => {
    const title = stringUtf8CV("Test");
    const budget = uintCV(1000);
    const milestones = listCV([uintCV(1), uintCV(2), uintCV(3), uintCV(4), uintCV(5), uintCV(6), uintCV(7), uintCV(8), uintCV(9), uintCV(10)]);
    expect(title.value).toBe("Test");
    expect(budget.value.toString()).toBe("1000");
    expect(milestones.value.length).toBe(10);
  });
});