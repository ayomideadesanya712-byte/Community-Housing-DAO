(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-NFT (err u101))
(define-constant ERR-INVALID-PARAM (err u102))
(define-constant ERR-DAO-INACTIVE (err u103))
(define-constant ERR-MEMBERSHIP-REQUIRED (err u104))
(define-constant ERR-QUORUM-NOT-MET (err u105))
(define-constant ERR-VOTING-NOT-ACTIVE (err u106))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u107))
(define-constant ERR-INVALID-VOTE (err u108))
(define-constant ERR-TIMESTAMP-INVALID (err u109))
(define-constant ERR-MAX-PROPOSALS-EXCEEDED (err u110))
(define-constant ERR-INSUFFICIENT-STAKE (err u111))
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN_QUORUM u50)
(define-constant DEFAULT-VOTING-PERIOD u1440)
(define-constant MAX-PROPOSALS u1000)

(define-data-var voting-period uint DEFAULT-VOTING-PERIOD)
(define-data-var proposal-fee uint u100)
(define-data-var quorum-threshold uint MIN_QUORUM)
(define-data-var dao-active bool true)
(define-data-var next-proposal-id uint u0)
(define-data-var max-proposals uint MAX-PROPOSALS)
(define-data-var nft-contract principal (as-contract tx-sender))
(define-data-var treasury-principal principal tx-sender)

(define-map proposals
  uint
  {
    title: (string-utf8 200),
    description: (string-utf8 500),
    budget: uint,
    milestones: (list 10 uint),
    status: (string-utf8 20),
    creator: principal,
    timestamp: uint,
    votes-for: uint,
    votes-against: uint,
    quorum-met: bool
  }
)

(define-map votes
  { proposal: uint, voter: principal }
  {
    vote: bool,
    stake: uint,
    timestamp: uint
  }
)

(define-map stakes
  principal
  {
    amount: uint,
    locked-until: uint
  }
)

(define-read-only (get-voting-period)
  (var-get voting-period)
)

(define-read-only (get-proposal-fee)
  (var-get proposal-fee)
)

(define-read-only (get-quorum-threshold)
  (var-get quorum-threshold)
)

(define-read-only (is-dao-active)
  (var-get dao-active)
)

(define-read-only (get-next-proposal-id)
  (var-get next-proposal-id)
)

(define-read-only (get-max-proposals)
  (var-get max-proposals)
)

(define-read-only (get-nft-contract)
  (var-get nft-contract)
)

(define-read-only (get-treasury-principal)
  (var-get treasury-principal)
)

(define-read-only (get-proposal (id uint))
  (map-get? proposals id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal: proposal-id, voter: voter })
)

(define-read-only (get-stake (user principal))
  (map-get? stakes user)
)

(define-read-only (has-membership (user principal))
  (let ((nft-balance (unwrap! (contract-call? (var-get nft-contract) get-balance user) false)))
    (> nft-balance u0)
  )
)

(define-private (validate-title (title (string-utf8 200)))
  (if (and (> (len title) u0) (<= (len title) u200))
      (ok true)
      (err ERR-INVALID-PARAM))
)

(define-private (validate-description (desc (string-utf8 500)))
  (if (and (> (len desc) u0) (<= (len desc) u500))
      (ok true)
      (err ERR-INVALID-PARAM))
)

(define-private (validate-budget (budget uint))
  (if (> budget u0)
      (ok true)
      (err ERR-INVALID-PARAM))
)

(define-private (validate-milestones (milestones (list 10 uint)))
  (if (> (len milestones) u0)
      (ok true)
      (err ERR-INVALID-PARAM))
)

(define-private (validate-timestamp (ts uint))
  (if (>= ts block-height)
      (ok true)
      (err ERR-TIMESTAMP-INVALID))
)

(define-private (is-voting-active (proposal { title: (string-utf8 200), description: (string-utf8 500), budget: uint, milestones: (list 10 uint), status: (string-utf8 20), creator: principal, timestamp: uint, votes-for: uint, votes-against: uint, quorum-met: bool }))
  (let (
        (start-ts (get timestamp proposal))
        (end-ts (+ start-ts (var-get voting-period)))
      )
    (and (>= block-height start-ts) (<= block-height end-ts))
  )
)

(define-public (set-nft-contract (new-nft-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq new-nft-contract (as-contract tx-sender))) ERR-INVALID-PARAM)
    (var-set nft-contract new-nft-contract)
    (ok true)
  )
)

(define-public (set-treasury-principal (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq new-treasury tx-sender)) ERR-INVALID-PARAM)
    (var-set treasury-principal new-treasury)
    (ok true)
  )
)

(define-public (update-voting-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-period u0) ERR-INVALID-PARAM)
    (var-set voting-period new-period)
    (ok true)
  )
)

(define-public (update-proposal-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (>= new-fee u0) ERR-INVALID-PARAM)
    (var-set proposal-fee new-fee)
    (ok true)
  )
)

(define-public (update-quorum-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (> new-threshold u0) (<= new-threshold u100)) ERR-INVALID-PARAM)
    (var-set quorum-threshold new-threshold)
    (ok true)
  )
)

(define-public (toggle-dao-active)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set dao-active (not (var-get dao-active)))
    (ok true)
  )
)

(define-public (submit-proposal
  (title (string-utf8 200))
  (description (string-utf8 500))
  (budget uint)
  (milestones (list 10 uint))
)
  (let (
        (next-id (var-get next-proposal-id))
        (current-max (var-get max-proposals))
      )
    (asserts! (var-get dao-active) ERR-DAO-INACTIVE)
    (asserts! (has-membership tx-sender) ERR-MEMBERSHIP-REQUIRED)
    (asserts! (< next-id current-max) ERR-MAX-PROPOSALS-EXCEEDED)
    (try! (validate-title title))
    (try! (validate-description description))
    (try! (validate-budget budget))
    (try! (validate-milestones milestones))
    (try! (stx-transfer? (var-get proposal-fee) tx-sender (var-get treasury-principal)))
    (map-set proposals next-id
      {
        title: title,
        description: description,
        budget: budget,
        milestones: milestones,
        status: u"pending",
        creator: tx-sender,
        timestamp: block-height,
        votes-for: u0,
        votes-against: u0,
        quorum-met: false
      }
    )
    (var-set next-proposal-id (+ next-id u1))
    (print { event: "proposal-submitted", id: next-id })
    (ok next-id)
  )
)

(define-public (cast-vote (proposal-id uint) (vote bool) (stake-amount uint))
  (let (
        (proposal (map-get? proposals proposal-id))
        (existing-vote (map-get? votes { proposal: proposal-id, voter: tx-sender }))
        (user-stake (map-get? stakes tx-sender))
      )
    (asserts! (var-get dao-active) ERR-DAO-INACTIVE)
    (asserts! (has-membership tx-sender) ERR-MEMBERSHIP-REQUIRED)
    (asserts! (is-some proposal) ERR-PROPOSAL-NOT-FOUND)
    (asserts! (is-voting-active (unwrap-panic proposal)) ERR-VOTING-NOT-ACTIVE)
    (asserts! (is-none existing-vote) ERR-INVALID-VOTE)
    (asserts! (> stake-amount u0) ERR-INSUFFICIENT-STAKE)
    (asserts! (>= (get amount (unwrap! user-stake { amount: u0, locked-until: u0 })) stake-amount) ERR-INSUFFICIENT-STAKE)
    (map-set votes { proposal: proposal-id, voter: tx-sender }
      {
        vote: vote,
        stake: stake-amount,
        timestamp: block-height
      }
    )
    (map-set stakes tx-sender
      {
        amount: (- (get amount (unwrap! user-stake { amount: u0, locked-until: u0 })) stake-amount),
        locked-until: (+ block-height (var-get voting-period))
      }
    )
    (if vote
        (map-set proposals proposal-id
          {
            title: (get title proposal),
            description: (get description proposal),
            budget: (get budget proposal),
            milestones: (get milestones proposal),
            status: (get status proposal),
            creator: (get creator proposal),
            timestamp: (get timestamp proposal),
            votes-for: (+ (get votes-for proposal) u1),
            votes-against: (get votes-against proposal),
            quorum-met: (check-quorum proposal-id)
          }
        )
        (map-set proposals proposal-id
          {
            title: (get title proposal),
            description: (get description proposal),
            budget: (get budget proposal),
            milestones: (get milestones proposal),
            status: (get status proposal),
            creator: (get creator proposal),
            timestamp: (get timestamp proposal),
            votes-for: (get votes-for proposal),
            votes-against: (+ (get votes-against proposal) u1),
            quorum-met: (check-quorum proposal-id)
          }
        )
    )
    (print { event: "vote-cast", proposal: proposal-id, vote: vote })
    (ok true)
  )
)

(define-private (check-quorum (proposal-id uint))
  (let (
        (proposal (unwrap! (map-get? proposals proposal-id) false))
        (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
      )
    (>= total-votes (var-get quorum-threshold))
  )
)

(define-public (withdraw-stake)
  (let (
        (user-stake (map-get? stakes tx-sender))
      )
    (asserts! (has-membership tx-sender) ERR-MEMBERSHIP-REQUIRED)
    (asserts! (is-some user-stake) ERR-INVALID-PARAM)
    (let (
          (stake (get amount user-stake))
          (lock-until (get locked-until user-stake))
        )
      (asserts! (>= block-height lock-until) ERR-INVALID-PARAM)
      (map-delete stakes tx-sender)
      (print { event: "stake-withdrawn", user: tx-sender, amount: stake })
      (ok stake)
    )
  )
)

(define-public (finalize-proposal (proposal-id uint))
  (let (
        (proposal (map-get? proposals proposal-id))
      )
    (asserts! (is-some proposal) ERR-PROPOSAL-NOT-FOUND)
    (asserts! (is-eq (get status (unwrap-panic proposal)) u"voting") ERR-VOTING-NOT-ACTIVE)
    (let (
          (for-votes (get votes-for (unwrap-panic proposal)))
          (against-votes (get votes-against (unwrap-panic proposal)))
          (quorum (check-quorum proposal-id))
        )
      (asserts! quorum ERR-QUORUM-NOT-MET)
      (if (> for-votes against-votes)
          (map-set proposals proposal-id
            {
              title: (get title (unwrap-panic proposal)),
              description: (get description (unwrap-panic proposal)),
              budget: (get budget (unwrap-panic proposal)),
              milestones: (get milestones (unwrap-panic proposal)),
              status: u"approved",
              creator: (get creator (unwrap-panic proposal)),
              timestamp: (get timestamp (unwrap-panic proposal)),
              votes-for: for-votes,
              votes-against: against-votes,
              quorum-met: quorum
            }
          )
          (map-set proposals proposal-id
            {
              title: (get title (unwrap-panic proposal)),
              description: (get description (unwrap-panic proposal)),
              budget: (get budget (unwrap-panic proposal)),
              milestones: (get milestones (unwrap-panic proposal)),
              status: u"rejected",
              creator: (get creator (unwrap-panic proposal)),
              timestamp: (get timestamp (unwrap-panic proposal)),
              votes-for: for-votes,
              votes-against: against-votes,
              quorum-met: quorum
            }
          )
      )
      (print { event: "proposal-finalized", id: proposal-id })
      (ok true)
    )
  )
)